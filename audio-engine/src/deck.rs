//! One song being decoded on its own thread, a little ahead of playback.
//! Opening, network waits and decoding all happen there, so the mixing
//! thread never waits on any of them.

use std::collections::VecDeque;
use std::sync::atomic::{AtomicBool, Ordering};
use std::sync::{Arc, Condvar, Mutex, MutexGuard};
use std::thread;
use std::time::Duration;

use crate::decode::{Decoder, TrackInfo};
use crate::error::Failure;
use crate::fifo::Fifo;
use crate::source::{
    self,
    http::{HttpOptions, TitleSlot},
    icy::StreamMeta,
};

/// How much decoded sound a deck keeps ready, in seconds.
const AHEAD_SECS: f64 = 0.75;

/// What a deck is doing.
#[derive(Clone, Debug, PartialEq)]
pub enum DeckStatus {
    Opening,
    Playing,
    /// Decoded to the end; what is buffered can still be read.
    Ended,
    Failed(Failure),
}

/// What one read from a deck gave.
#[derive(Clone, Debug, PartialEq)]
pub struct DeckRead {
    /// Frames copied out.
    pub frames: usize,
    /// Where the first of them sits in the song, in seconds.
    pub start_secs: f64,
    /// Nothing more will come: the song is over or failed.
    pub finished: bool,
    pub failure: Option<Failure>,
}

struct State {
    pcm: Fifo,
    /// How much sound to keep ready once playing, in frames.
    steady: usize,
    head_secs: f64,
    status: DeckStatus,
    info: Option<TrackInfo>,
    seek: Option<f64>,
    seek_generation: u64,
    stop: bool,
    capacity: usize,
    // A live stream's titles, by the time in it where they start.
    titles: VecDeque<(f64, StreamMeta)>,
}

struct Shared {
    state: Mutex<State>,
    wake: Condvar,
    starved: Arc<AtomicBool>,
    cancel: Arc<AtomicBool>,
}

impl Shared {
    fn lock(&self) -> MutexGuard<'_, State> {
        self.state.lock().unwrap_or_else(|e| e.into_inner())
    }
}

/// A song decoding in the background. Dropping it stops the thread.
pub struct Deck {
    shared: Arc<Shared>,
    key: u64,
    live: bool,
}

impl Deck {
    /// Starts opening `source` (a path or an address) at `start_secs`.
    pub fn open(key: u64, source: String, start_secs: f64, http: HttpOptions) -> Deck {
        Deck::open_ahead(key, source, start_secs, http, AHEAD_SECS)
    }

    /// The same, decoding up to `first_secs` ahead before the first read
    /// (never less than usual), so playback can wait for that much. A live
    /// stream always starts where its server is.
    pub fn open_ahead(
        key: u64,
        source: String,
        start_secs: f64,
        mut http: HttpOptions,
        first_secs: f64,
    ) -> Deck {
        let starved = Arc::new(AtomicBool::new(false));
        let cancel = Arc::new(AtomicBool::new(false));
        let live = http.live;
        let start_secs = if live { 0.0 } else { start_secs };
        http.starved = Some(starved.clone());
        http.cancel = Some(cancel.clone());
        http.titles = live.then(|| Arc::new(TitleSlot::default()));
        let shared = Arc::new(Shared {
            state: Mutex::new(State {
                pcm: Fifo::default(),
                steady: 0,
                head_secs: start_secs,
                status: DeckStatus::Opening,
                info: None,
                seek: (start_secs > 0.0).then_some(start_secs),
                seek_generation: 0,
                stop: false,
                capacity: 0,
                titles: VecDeque::new(),
            }),
            wake: Condvar::new(),
            starved,
            cancel,
        });
        let worker = shared.clone();
        let first = first_secs.max(AHEAD_SECS);
        let spawned = thread::Builder::new().name("octo-deck".into()).spawn(move || {
            let watch = worker.clone();
            // Whatever goes wrong in there, the player hears of it.
            if std::panic::catch_unwind(std::panic::AssertUnwindSafe(|| run(worker, source, http, first)))
                .is_err()
            {
                let mut state = watch.lock();
                let broke = Failure::new(crate::error::ErrorKind::Other, "decoding broke down");
                state.status = DeckStatus::Failed(broke);
                watch.wake.notify_all();
            }
        });
        if let Err(e) = spawned {
            let mut state = shared.lock();
            state.status = DeckStatus::Failed(Failure::new(crate::error::ErrorKind::Other, e.to_string()));
        }
        Deck { shared, key, live }
    }

    /// Which queue entry this deck plays.
    pub fn key(&self) -> u64 {
        self.key
    }

    /// Whether this is a live stream, which is never sought.
    pub fn is_live(&self) -> bool {
        self.live
    }

    /// The newest title of a live stream that starts by `heard_secs` into
    /// it, when there is one not taken before.
    pub fn take_title(&self, heard_secs: f64) -> Option<StreamMeta> {
        let mut state = self.shared.lock();
        let mut latest = None;
        while state.titles.front().is_some_and(|(at, _)| *at <= heard_secs) {
            latest = state.titles.pop_front().map(|(_, title)| title);
        }
        latest
    }

    pub fn info(&self) -> Option<TrackInfo> {
        self.shared.lock().info.clone()
    }

    pub fn status(&self) -> DeckStatus {
        self.shared.lock().status.clone()
    }

    /// Whether the song is open and has sound ready, or has finished.
    pub fn is_ready(&self) -> bool {
        let state = self.shared.lock();
        !state.pcm.is_empty() || matches!(state.status, DeckStatus::Ended | DeckStatus::Failed(_))
    }

    /// Whether a read is waiting on the network.
    pub fn is_starved(&self) -> bool {
        self.shared.starved.load(Ordering::Relaxed)
    }

    /// Frames buffered and ready.
    pub fn buffered(&self) -> usize {
        self.shared.lock().pcm.len() / 2
    }

    /// Whether as much sound is ready as the deck decodes ahead, or the
    /// song has been decoded to its end (or failed).
    pub fn is_filled(&self) -> bool {
        let state = self.shared.lock();
        let done = matches!(state.status, DeckStatus::Ended | DeckStatus::Failed(_));
        done || (state.capacity > 0 && state.pcm.len() / 2 >= state.capacity)
    }

    /// Takes up to `out.len() / 2` stereo frames.
    pub fn read(&self, out: &mut [f32]) -> DeckRead {
        let mut state = self.shared.lock();
        let rate = state.info.as_ref().map(|i| i.sample_rate).unwrap_or(44_100) as f64;
        let start_secs = state.head_secs;
        let samples = state.pcm.pop_into(out);
        let frames = samples / 2;
        state.head_secs += frames as f64 / rate;
        // Once playing, only the usual amount is kept ahead.
        if frames > 0 && state.steady > 0 {
            state.capacity = state.steady;
        }
        // Wake the decoder once half the buffer is free, not on every read.
        if frames > 0 && state.pcm.len() / 2 < state.capacity / 2 {
            self.shared.wake.notify_all();
        }
        let failure = match &state.status {
            DeckStatus::Failed(f) => Some(f.clone()),
            _ => None,
        };
        let done = matches!(state.status, DeckStatus::Ended | DeckStatus::Failed(_));
        DeckRead { frames, start_secs, finished: done && state.pcm.is_empty(), failure }
    }

    /// Jumps to `secs`. What is buffered is dropped at once. A live stream
    /// stays where it is.
    pub fn seek(&self, secs: f64) {
        if self.live {
            return;
        }
        let mut state = self.shared.lock();
        state.seek = Some(secs.max(0.0));
        state.seek_generation += 1;
        state.pcm.clear();
        state.head_secs = secs.max(0.0);
        if state.status == DeckStatus::Ended {
            state.status = DeckStatus::Playing;
        }
        self.shared.wake.notify_all();
    }
}

impl Drop for Deck {
    fn drop(&mut self) {
        self.shared.cancel.store(true, Ordering::Relaxed);
        let mut state = self.shared.lock();
        state.stop = true;
        self.shared.wake.notify_all();
    }
}

fn run(shared: Arc<Shared>, source: String, http: HttpOptions, first_secs: f64) {
    // A transcode is opened at its start time rather than sought into.
    let by_time = source::seeks_by_time(&source);
    let mut offset = 0.0;
    let opened = if by_time {
        let start = shared.lock().seek.take();
        let (address, landed) = source::at_time(&source, start.unwrap_or(0.0));
        offset = landed;
        shared.lock().head_secs = landed;
        source::open(&address, http.clone()).and_then(Decoder::open)
    } else {
        source::open(&source, http.clone()).and_then(Decoder::open)
    };
    let mut decoder = match opened {
        Ok(d) => d,
        Err(failure) => {
            log::warn!("could not open {source}: {failure}");
            let mut state = shared.lock();
            state.status = DeckStatus::Failed(failure);
            shared.wake.notify_all();
            return;
        }
    };
    {
        let mut state = shared.lock();
        let rate = decoder.sample_rate() as f64;
        state.steady = (rate * AHEAD_SECS) as usize;
        state.capacity = (rate * first_secs) as usize;
        state.pcm = Fifo::with_capacity(state.capacity * 2 + 16_384);
        state.info = Some(decoder.info().clone());
        state.status = DeckStatus::Playing;
        shared.wake.notify_all();
    }
    let mut block = Vec::new();
    loop {
        let generation;
        {
            let mut state = shared.lock();
            loop {
                if state.stop {
                    return;
                }
                if let Some(target) = state.seek.take() {
                    let generation = state.seek_generation;
                    drop(state);
                    let landed = if by_time {
                        // Opened again at the time, as the server makes it from there.
                        let (address, at) = source::at_time(&source, target);
                        match source::open(&address, http.clone()).and_then(Decoder::open) {
                            Ok(fresh) => {
                                decoder = fresh;
                                offset = at;
                                Ok(at)
                            }
                            Err(f) => Err(f),
                        }
                    } else {
                        decoder.seek(target)
                    };
                    state = shared.lock();
                    if state.seek_generation == generation {
                        match landed {
                            Ok(at) => state.head_secs = at,
                            Err(f) => {
                                log::warn!("seek failed: {f}");
                                state.status = DeckStatus::Failed(f);
                            }
                        }
                        state.pcm.clear();
                    }
                    continue;
                }
                let full = state.pcm.len() / 2 >= state.capacity;
                let idle = matches!(state.status, DeckStatus::Ended | DeckStatus::Failed(_));
                if full || idle {
                    state = shared
                        .wake
                        .wait_timeout(state, Duration::from_millis(500))
                        .unwrap_or_else(|e| e.into_inner())
                        .0;
                    continue;
                }
                break;
            }
            generation = state.seek_generation;
        }
        let result = decoder.next_block(&mut block);
        let mut state = shared.lock();
        if state.seek_generation != generation || state.seek.is_some() {
            // A seek came in while decoding: this block is from before it.
            continue;
        }
        match result {
            Ok(true) => {
                let rate = decoder.sample_rate() as f64;
                let block_secs = offset + decoder.position_secs() - (block.len() / 2) as f64 / rate;
                if state.pcm.is_empty() {
                    state.head_secs = block_secs;
                }
                state.pcm.push(&block);
                // A title the stream reached while this was read starts with it.
                if let Some(title) = http.titles.as_ref().and_then(|slot| slot.take()) {
                    state.titles.push_back((block_secs, title));
                }
            }
            Ok(false) => state.status = DeckStatus::Ended,
            Err(f) => {
                log::warn!("decoding stopped: {f}");
                state.status = DeckStatus::Failed(f);
            }
        }
        shared.wake.notify_all();
    }
}

#[cfg(test)]
mod tests {
    use super::*;
    use crate::testing::fixtures::*;
    use std::time::Instant;

    fn wait_ready(deck: &Deck) {
        let until = Instant::now() + Duration::from_secs(5);
        while !deck.is_ready() {
            assert!(Instant::now() < until, "deck never got ready");
            thread::sleep(Duration::from_millis(2));
        }
    }

    fn read_all(deck: &Deck) -> (Vec<f32>, Option<Failure>) {
        let mut all = Vec::new();
        let mut buf = vec![0.0; 2048];
        let until = Instant::now() + Duration::from_secs(10);
        loop {
            let r = deck.read(&mut buf);
            all.extend_from_slice(&buf[..r.frames * 2]);
            if r.finished {
                return (all, r.failure);
            }
            if r.frames == 0 {
                assert!(Instant::now() < until);
                thread::sleep(Duration::from_millis(1));
            }
        }
    }

    #[test]
    fn decodes_ahead_and_to_the_end() {
        let dir = temp_dir();
        let path = dir.join("a.wav");
        let samples = sine(440.0, 44_100, 2, 0, 100_000, 0.5);
        write_wav(&path, 44_100, 2, &samples);
        let deck = Deck::open(7, path.to_string_lossy().into(), 0.0, HttpOptions::default());
        wait_ready(&deck);
        assert_eq!(deck.key(), 7);
        assert_eq!(deck.info().unwrap().sample_rate, 44_100);
        let (all, failure) = read_all(&deck);
        assert!(failure.is_none());
        assert_eq!(all.len(), samples.len());
        assert_eq!(all[1234], samples[1234] as f32 / 32768.0);
    }

    #[test]
    fn opens_at_a_position_and_seeks() {
        let dir = temp_dir();
        let path = dir.join("b.flac");
        let rate = 48_000;
        let samples: Vec<i16> = (0..rate * 2).flat_map(|n| [(n % 20_000) as i16, 0]).collect();
        write_flac(&path, rate, 2, &samples, &[]);
        let deck = Deck::open(1, path.to_string_lossy().into(), 1.0, HttpOptions::default());
        wait_ready(&deck);
        let mut buf = vec![0.0; 64];
        let r = deck.read(&mut buf);
        assert!((r.start_secs - 1.0).abs() < 1e-9);
        assert_eq!(buf[0], (48_000 % 20_000) as f32 / 32768.0);

        deck.seek(0.5);
        wait_ready(&deck);
        let r = deck.read(&mut buf);
        assert!((r.start_secs - 0.5).abs() < 1e-9, "{}", r.start_secs);
        assert_eq!(buf[0], (24_000 % 20_000) as f32 / 32768.0);
    }

    #[test]
    fn decodes_further_ahead_before_the_first_read_then_as_usual() {
        let dir = temp_dir();
        let path = dir.join("long.wav");
        write_wav(&path, 48_000, 2, &sine(440.0, 48_000, 2, 0, 48_000 * 4, 0.5));
        let deck = Deck::open_ahead(1, path.to_string_lossy().into(), 0.0, HttpOptions::default(), 2.0);
        let until = Instant::now() + Duration::from_secs(5);
        while !deck.is_filled() {
            assert!(Instant::now() < until, "never filled");
            thread::sleep(Duration::from_millis(2));
        }
        assert!(deck.buffered() >= 96_000 - 1, "{}", deck.buffered());
        // A song shorter than that is ready once decoded to its end.
        let short = dir.join("short.wav");
        write_wav(&short, 48_000, 2, &sine(440.0, 48_000, 2, 0, 4_800, 0.5));
        let tiny = Deck::open_ahead(2, short.to_string_lossy().into(), 0.0, HttpOptions::default(), 2.0);
        let until = Instant::now() + Duration::from_secs(5);
        while !tiny.is_filled() {
            assert!(Instant::now() < until, "a short song never counted as ready");
            thread::sleep(Duration::from_millis(2));
        }
        assert_eq!(tiny.buffered(), 4_800);
    }

    // A transcode has no length to jump in by bytes: it is opened again at
    // the time, and the sound from there counts as that time.
    #[test]
    fn a_transcode_seeks_by_opening_at_a_time() {
        use crate::testing::http_server::{Behaviour, TestServer};
        let rate = 48_000;
        let samples: Vec<i16> = (0..rate * 3).flat_map(|n| [(n % 20_000) as i16, 0]).collect();
        let server = TestServer::start(flac_bytes(rate, 2, &samples, &[]), Behaviour::default());
        let address = format!("{}?id=1&format=mp3&maxBitRate=192", server.url());
        let deck = Deck::open(1, address, 0.0, HttpOptions::default());
        wait_ready(&deck);
        deck.seek(1.4);
        let until = Instant::now() + Duration::from_secs(5);
        let mut buf = vec![0.0; 64];
        let r = loop {
            let r = deck.read(&mut buf);
            if r.frames > 0 {
                break r;
            }
            assert!(Instant::now() < until, "nothing after the seek");
            thread::sleep(Duration::from_millis(2));
        };
        assert!((r.start_secs - 1.0).abs() < 1e-9, "{}", r.start_secs);
        // The server's answer starts at its own beginning: what it made from 1 s.
        assert_eq!(buf[0], 0.0);
        let targets = server.targets_asked();
        assert_eq!(targets.len(), 2, "{targets:?}");
        assert!(!targets[0].contains("timeOffset"), "{targets:?}");
        assert!(targets[1].ends_with("&timeOffset=1"), "{targets:?}");
        assert!(server.ranges_asked().iter().all(|&start| start == 0), "{:?}", server.ranges_asked());

        // Opened partway in, it asks for that time from the start.
        let later = Deck::open(2, format!("{}?id=1&format=mp3", server.url()), 2.0, HttpOptions::default());
        wait_ready(&later);
        assert!((later.read(&mut buf).start_secs - 2.0).abs() < 1e-9);
        assert!(server.targets_asked().last().unwrap().ends_with("timeOffset=2"));
    }

    // The original file still jumps by bytes.
    #[test]
    fn the_original_file_seeks_by_bytes() {
        use crate::testing::http_server::{Behaviour, TestServer};
        let rate = 48_000;
        let samples: Vec<i16> = (0..rate * 3).flat_map(|n| [(n % 20_000) as i16, 0]).collect();
        let server = TestServer::start(flac_bytes(rate, 2, &samples, &[]), Behaviour::default());
        let deck = Deck::open(1, format!("{}?id=1&format=raw", server.url()), 0.0, HttpOptions::default());
        wait_ready(&deck);
        deck.seek(2.0);
        let until = Instant::now() + Duration::from_secs(5);
        let mut buf = vec![0.0; 64];
        let r = loop {
            let r = deck.read(&mut buf);
            if r.frames > 0 && (r.start_secs - 2.0).abs() < 1e-9 {
                break r;
            }
            assert!(Instant::now() < until, "nothing after the seek");
            thread::sleep(Duration::from_millis(2));
        };
        assert_eq!(buf[0], (96_000 % 20_000) as f32 / 32768.0, "{r:?}");
        assert!(server.targets_asked().iter().all(|t| !t.contains("timeOffset")));
    }

    #[test]
    fn a_missing_file_fails() {
        let deck = Deck::open(1, "Z:/nothing/here.flac".into(), 0.0, HttpOptions::default());
        wait_ready(&deck);
        let r = deck.read(&mut [0.0; 8]);
        assert!(r.finished);
        assert_eq!(r.failure.unwrap().kind, crate::error::ErrorKind::NotFound);
    }
}
