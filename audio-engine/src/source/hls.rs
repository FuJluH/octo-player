//! HLS: a stream cut into short segments listed in a playlist. A master
//! playlist names variants at different bit rates; the best one the engine
//! can decode is picked, and its media playlist lists the segments. They
//! are fetched in order and read as one stream. A live playlist is fetched
//! again every target duration for the segments added since.
//!
//! Segments in AAC (ADTS), MP3 and the like are joined byte to byte, and
//! MPEG-TS segments are cut down to their audio first. Fragmented MP4
//! segments follow their init segment. A discontinuity, or a change of init
//! segment, starts a new period, which the decoder opens afresh.

use std::collections::VecDeque;
use std::io::{self, Read, Seek, SeekFrom};
use std::sync::atomic::Ordering;
use std::sync::{Arc, Condvar, Mutex, MutexGuard};
use std::thread;
use std::time::{Duration, Instant};

use symphonia::core::io::MediaSource;

use crate::error::{ErrorKind, Failure};
use crate::source::http::HttpOptions;
use crate::source::ts::TsDemuxer;
use crate::source::{Opened, Periods};

// The most a playlist or segment may be, so a wrong address cannot fill memory.
const MOST_BYTES: u64 = 64 << 20;

// Playlists that point at another address, followed this many in a row.
pub(crate) const MOST_HOPS: u32 = 3;

// Fetches in a row that may fail before the stream counts as gone.
const RETRIES: u32 = 4;

// Segments in a row the server may say are not there before the stream
// counts as gone.
const MISSING_IN_A_ROW: u32 = 8;

// A live playlist that adds nothing for this many target durations (and at
// least twenty times the first reconnect wait, 20 s by default) has stopped.
const STOPPED_AFTER_TARGETS: u32 = 3;
const STOPPED_AFTER_WAITS: u32 = 20;

/// Whether an address names an HLS playlist by its extension.
pub fn is_hls_url(url: &str) -> bool {
    let path = url.split(['?', '#']).next().unwrap_or(url);
    path.to_ascii_lowercase().ends_with(".m3u8")
}

/// Whether a server's content type is a playlist.
pub fn is_playlist_type(content_type: &str) -> bool {
    let bare = content_type.split(';').next().unwrap_or("").trim().to_ascii_lowercase();
    matches!(
        bare.as_str(),
        "application/vnd.apple.mpegurl" | "application/x-mpegurl" | "audio/mpegurl" | "audio/x-mpegurl"
    )
}

/// Opens the playlist at `url`: an HLS stream, or a plain list of
/// addresses, whose first entry is opened instead.
pub fn open(url: &str, http: HttpOptions) -> Result<Opened, Failure> {
    open_hop(url, http, 0)
}

/// The same, `hops` playlists in after the address first asked for.
pub(crate) fn open_hop(url: &str, http: HttpOptions, hops: u32) -> Result<Opened, Failure> {
    let text = fetch_text(url, &http)?;
    let media_url = match parse(&text, url) {
        Playlist::Master(variants) => {
            let chosen = choose(&variants).ok_or_else(|| {
                Failure::new(
                    ErrorKind::Unsupported,
                    "no stream in the HLS playlist is in a codec the engine plays",
                )
            })?;
            chosen.to_string()
        }
        Playlist::Media(media) => return start(url.to_string(), media, http),
        Playlist::Plain(entries) => {
            let first = entries
                .into_iter()
                .next()
                .ok_or_else(|| Failure::new(ErrorKind::Unsupported, "the playlist lists nothing to play"))?;
            if hops >= MOST_HOPS {
                let looped = "the playlist points at itself, or through too many others";
                return Err(Failure::new(ErrorKind::Unsupported, looped));
            }
            return if is_hls_url(&first) {
                open_hop(&first, http, hops + 1)
            } else {
                super::open_stream(&first, http, hops + 1)
            };
        }
    };
    let text = fetch_text(&media_url, &http)?;
    match parse(&text, &media_url) {
        Playlist::Media(media) => start(media_url, media, http),
        _ => Err(Failure::new(ErrorKind::Unsupported, "the HLS variant is not a media playlist")),
    }
}

// Checks the first media playlist and starts fetching its segments.
fn start(url: String, media: Media, http: HttpOptions) -> Result<Opened, Failure> {
    check(&media)?;
    let hint = media.segments.first().and_then(|s| match &s.map {
        Some(_) => Some("mp4".to_string()),
        None => super::url_extension(&s.uri).filter(|e| e != "ts"),
    });
    let shared = Arc::new(Shared { opts: http, state: Mutex::new(State::default()), wake: Condvar::new() });
    let worker = shared.clone();
    thread::Builder::new()
        .name("octo-hls".into())
        .spawn(move || {
            let ended = worker.clone();
            // Whatever goes wrong in there, the reader hears of it.
            if std::panic::catch_unwind(std::panic::AssertUnwindSafe(|| run(worker, url, media))).is_err() {
                let broke = Failure::new(ErrorKind::Other, "reading the HLS stream broke down");
                ended.end(Some(broke));
            }
        })
        .map_err(|e| Failure::new(ErrorKind::Other, format!("could not start fetching: {e}")))?;
    let reader = PeriodReader::new(shared.clone());
    Ok(Opened {
        source: Box::new(reader),
        hint,
        remote: true,
        seeks_cheaply: false,
        live: true,
        periods: Some(Box::new(HlsPeriods { shared })),
    })
}

// What a media playlist holds that the engine cannot play.
fn check(media: &Media) -> Result<(), Failure> {
    if media.encrypted {
        return Err(Failure::new(ErrorKind::Unsupported, "encrypted HLS streams are not supported"));
    }
    Ok(())
}

// One piece of the stream as the fetch thread hands it over.
enum Piece {
    Bytes(Vec<u8>),
    // A new period starts after this.
    Break,
}

struct Shared {
    opts: HttpOptions,
    state: Mutex<State>,
    wake: Condvar,
}

#[derive(Default)]
struct State {
    pieces: VecDeque<Piece>,
    queued: usize,
    // Nothing more will come.
    ended: bool,
    failure: Option<Failure>,
    closed: bool,
}

impl Shared {
    fn lock(&self) -> MutexGuard<'_, State> {
        self.state.lock().unwrap_or_else(|e| e.into_inner())
    }

    fn cancelled(&self) -> bool {
        self.opts.cancel.as_ref().is_some_and(|c| c.load(Ordering::Relaxed))
    }

    fn stale(&self) -> bool {
        self.cancelled() || self.lock().closed
    }

    fn set_starved(&self, on: bool) {
        if let Some(flag) = &self.opts.starved {
            flag.store(on, Ordering::Relaxed);
        }
    }

    // Queues a piece once there is room. False once nobody reads. Nothing
    // is queued for no bytes, which a reader would take for the end.
    fn push(&self, piece: Piece) -> bool {
        if matches!(&piece, Piece::Bytes(bytes) if bytes.is_empty()) {
            return !self.stale();
        }
        let mut state = self.lock();
        loop {
            if state.closed || self.cancelled() {
                return false;
            }
            if state.queued < self.opts.read_ahead || matches!(piece, Piece::Break) {
                break;
            }
            state = self
                .wake
                .wait_timeout(state, Duration::from_millis(250))
                .unwrap_or_else(|e| e.into_inner())
                .0;
        }
        if let Piece::Bytes(bytes) = &piece {
            state.queued += bytes.len();
        }
        state.pieces.push_back(piece);
        self.wake.notify_all();
        true
    }

    fn end(&self, failure: Option<Failure>) {
        let mut state = self.lock();
        state.ended = true;
        state.failure = failure;
        self.wake.notify_all();
    }

    // Waits up to `wait`. False once nobody reads.
    fn sleep(&self, wait: Duration) -> bool {
        let until = Instant::now() + wait;
        while Instant::now() < until {
            if self.stale() {
                return false;
            }
            thread::sleep(Duration::from_millis(50).min(wait));
        }
        !self.stale()
    }
}

/// One period of the stream, read like a file that cannot be sought.
struct PeriodReader {
    shared: Arc<Shared>,
    current: Vec<u8>,
    at: usize,
    pos: u64,
    done: bool,
}

impl PeriodReader {
    fn new(shared: Arc<Shared>) -> Self {
        Self { shared, current: Vec::new(), at: 0, pos: 0, done: false }
    }
}

impl Read for PeriodReader {
    fn read(&mut self, out: &mut [u8]) -> io::Result<usize> {
        if out.is_empty() || self.done {
            return Ok(0);
        }
        if self.at >= self.current.len() {
            let shared = self.shared.clone();
            let mut state = shared.lock();
            loop {
                if state.closed || shared.cancelled() {
                    shared.set_starved(false);
                    return Err(io::Error::other("stream closed"));
                }
                match state.pieces.front() {
                    Some(Piece::Bytes(_)) => {
                        let Some(Piece::Bytes(bytes)) = state.pieces.pop_front() else { unreachable!() };
                        state.queued -= bytes.len();
                        shared.wake.notify_all();
                        if bytes.is_empty() {
                            continue;
                        }
                        self.current = bytes;
                        self.at = 0;
                        break;
                    }
                    // Left for the next period to take.
                    Some(Piece::Break) => {
                        self.done = true;
                        shared.set_starved(false);
                        return Ok(0);
                    }
                    None => {}
                }
                if let Some(failure) = &state.failure {
                    shared.set_starved(false);
                    return Err(failure.clone().into());
                }
                if state.ended {
                    self.done = true;
                    shared.set_starved(false);
                    return Ok(0);
                }
                shared.set_starved(true);
                state = shared
                    .wake
                    .wait_timeout(state, Duration::from_millis(250))
                    .unwrap_or_else(|e| e.into_inner())
                    .0;
            }
            shared.set_starved(false);
        }
        let n = out.len().min(self.current.len() - self.at);
        out[..n].copy_from_slice(&self.current[self.at..self.at + n]);
        self.at += n;
        self.pos += n as u64;
        Ok(n)
    }
}

impl Seek for PeriodReader {
    fn seek(&mut self, to: SeekFrom) -> io::Result<u64> {
        let target = match to {
            SeekFrom::Start(p) => Some(p),
            SeekFrom::Current(d) => self.pos.checked_add_signed(d),
            SeekFrom::End(_) => None,
        };
        match target {
            Some(p) if p == self.pos => Ok(p),
            _ => Err(io::Error::new(io::ErrorKind::Unsupported, "an HLS stream cannot be sought")),
        }
    }
}

impl MediaSource for PeriodReader {
    fn is_seekable(&self) -> bool {
        false
    }

    fn byte_len(&self) -> Option<u64> {
        None
    }
}

// Hands out the stream's periods in turn.
struct HlsPeriods {
    shared: Arc<Shared>,
}

impl Periods for HlsPeriods {
    fn next(&mut self) -> Result<Option<Box<dyn MediaSource>>, Failure> {
        let shared = self.shared.clone();
        let mut state = shared.lock();
        loop {
            if state.closed || shared.cancelled() {
                return Err(Failure::new(ErrorKind::Other, "stream closed"));
            }
            // What the last period left unread goes, up to its end.
            while let Some(piece) = state.pieces.pop_front() {
                match piece {
                    Piece::Bytes(bytes) => state.queued -= bytes.len(),
                    Piece::Break => {
                        shared.wake.notify_all();
                        return Ok(Some(Box::new(PeriodReader::new(shared.clone()))));
                    }
                }
            }
            shared.wake.notify_all();
            if let Some(failure) = &state.failure {
                return Err(failure.clone());
            }
            if state.ended {
                return Ok(None);
            }
            state = shared
                .wake
                .wait_timeout(state, Duration::from_millis(250))
                .unwrap_or_else(|e| e.into_inner())
                .0;
        }
    }
}

impl Drop for HlsPeriods {
    fn drop(&mut self) {
        self.shared.lock().closed = true;
        self.shared.wake.notify_all();
    }
}

// The fetch thread: segments in order, the playlist again while live.
fn run(shared: Arc<Shared>, url: String, first: Media) {
    let mut playlist = Some(first);
    // The media sequence number of the next segment wanted.
    let mut next: Option<u64> = None;
    // The init segment the current period started with.
    let mut init: Option<Option<Map>> = None;
    // The current period's MPEG-TS demuxer, once its segments turn out to
    // be MPEG-TS; it carries a packet or a PES packet cut between segments.
    let mut ts: Option<TsDemuxer> = None;
    let mut failures = 0u32;
    // Segments in a row the server said were not there.
    let mut missing = 0u32;
    // When the playlist last added a segment.
    let mut grew = Instant::now();
    loop {
        let media = match playlist.take() {
            Some(media) => media,
            None => match fetch_text(&url, &shared.opts).map(|text| parse(&text, &url)) {
                Ok(Playlist::Media(media)) => {
                    failures = 0;
                    media
                }
                Ok(_) => {
                    let wrong = Failure::new(ErrorKind::Unsupported, "the HLS playlist changed kind");
                    return shared.end(Some(wrong));
                }
                Err(failure) if failure.status.is_some_and(|s| (400..500).contains(&s)) => {
                    return shared.end(Some(failure));
                }
                Err(failure) => {
                    log::warn!("the HLS playlist could not be fetched: {failure}");
                    failures += 1;
                    if !wait_again(&shared, failures) {
                        return;
                    }
                    continue;
                }
            },
        };
        if let Err(failure) = check(&media) {
            return shared.end(Some(failure));
        }
        let last = media.first_seq.saturating_add(media.segments.len() as u64);
        // Live, start three segments from the newest, as players do.
        let edge = last.saturating_sub(3).max(media.first_seq);
        // Numbered from below where it was: the encoder started over.
        let restarted = next.is_some_and(|n| last < n);
        let from = match next {
            Some(n) if restarted => {
                log::warn!("the HLS stream started its numbers again; joining at {edge} after {n}");
                edge
            }
            Some(n) if n < media.first_seq => {
                log::warn!("the HLS stream moved on past {n}; carrying on at {}", media.first_seq);
                media.first_seq
            }
            Some(n) => n,
            None if !media.ended => edge,
            None => media.first_seq,
        };
        let mut added = false;
        let mut rejoin = restarted;
        for segment in media.segments.iter().filter(|s| s.seq >= from) {
            if shared.stale() {
                return;
            }
            // A new period: after a discontinuity, when the init segment
            // changes, or where the stream was joined again.
            let started = init.is_some();
            let fresh = !started || segment.discontinuity || rejoin || init.as_ref() != Some(&segment.map);
            rejoin = false;
            if started && fresh && !shared.push(Piece::Break) {
                return;
            }
            if fresh {
                if let Some(map) = &segment.map {
                    match fetch_retrying(&shared, &map.uri, map.range, &mut failures) {
                        Fetched::Bytes(bytes) => {
                            if !shared.push(Piece::Bytes(bytes)) {
                                return;
                            }
                        }
                        Fetched::Missing(failure) => return shared.end(Some(failure)),
                        Fetched::Gone => return,
                    }
                }
                init = Some(segment.map.clone());
                ts = None;
            }
            let mut bytes = match fetch_retrying(&shared, &segment.uri, segment.range, &mut failures) {
                Fetched::Bytes(bytes) => {
                    missing = 0;
                    bytes
                }
                Fetched::Missing(failure) => {
                    missing += 1;
                    if missing >= MISSING_IN_A_ROW {
                        return shared.end(Some(failure));
                    }
                    log::warn!("skipping an HLS segment: {failure}");
                    next = Some(segment.seq.saturating_add(1));
                    continue;
                }
                Fetched::Gone => return,
            };
            if segment.map.is_none() {
                if ts.is_none() && is_transport_stream(&bytes) {
                    ts = Some(TsDemuxer::new());
                }
                match &mut ts {
                    Some(demuxer) => {
                        let mut audio = Vec::with_capacity(bytes.len());
                        demuxer.feed(&bytes, &mut audio);
                        if demuxer.has_no_audio() {
                            let none = "the HLS stream's audio is in a codec the engine does not play";
                            return shared.end(Some(Failure::new(ErrorKind::Unsupported, none)));
                        }
                        bytes = audio;
                    }
                    None => strip_id3(&mut bytes),
                }
            }
            if !shared.push(Piece::Bytes(bytes)) {
                return;
            }
            next = Some(segment.seq.saturating_add(1));
            added = true;
        }
        if media.ended {
            return shared.end(None);
        }
        let stopped_after =
            (media.target * STOPPED_AFTER_TARGETS).max(shared.opts.live_backoff * STOPPED_AFTER_WAITS);
        if added {
            grew = Instant::now();
        } else if grew.elapsed() > stopped_after {
            let stopped = "the HLS stream stopped adding to its playlist";
            return shared.end(Some(Failure::new(ErrorKind::Network, stopped)));
        }
        // A playlist with nothing new is asked again sooner.
        let wait = if added { media.target } else { media.target / 2 };
        if !shared.sleep(wait) {
            return;
        }
    }
}

enum Fetched {
    Bytes(Vec<u8>),
    // The server says it is not there.
    Missing(Failure),
    // Given up, or nobody reads any more.
    Gone,
}

// Fetches a segment, trying again after network failures.
fn fetch_retrying(shared: &Shared, url: &str, range: Option<(u64, u64)>, failures: &mut u32) -> Fetched {
    loop {
        if shared.stale() {
            return Fetched::Gone;
        }
        match fetch_bytes(url, range, &shared.opts) {
            Ok(bytes) => {
                *failures = 0;
                return Fetched::Bytes(bytes);
            }
            Err(failure) if failure.status.is_some_and(|s| (400..500).contains(&s)) => {
                return Fetched::Missing(failure);
            }
            Err(failure) => {
                log::warn!("an HLS segment could not be fetched: {failure}");
                *failures += 1;
                if !wait_again(shared, *failures) {
                    return Fetched::Gone;
                }
            }
        }
    }
}

// Waits 1, 2, 4 and 8 times the first wait after failures in a row, then
// gives the stream up. False when it is given up, or nobody reads.
fn wait_again(shared: &Shared, failures: u32) -> bool {
    if failures > RETRIES {
        let gone = "the HLS stream stopped and did not come back";
        shared.end(Some(Failure::new(ErrorKind::Network, gone)));
        return false;
    }
    shared.sleep(shared.opts.live_backoff * (1 << (failures - 1)))
}

fn get(
    url: &str,
    range: Option<(u64, u64)>,
    opts: &HttpOptions,
) -> Result<ureq::http::Response<ureq::Body>, Failure> {
    let mut req = opts.agent.get(url);
    for (name, value) in &opts.headers {
        req = req.header(name, value);
    }
    if let Some((offset, len)) = range {
        let end = offset
            .checked_add(len.max(1) - 1)
            .ok_or_else(|| Failure::new(ErrorKind::InvalidArgument, "an HLS byte range runs past the end"))?;
        req = req.header("Range", format!("bytes={offset}-{end}"));
    }
    let response =
        req.config().timeout_global(Some(Duration::from_secs(30))).build().call().map_err(|e| match e {
            ureq::Error::StatusCode(status) => Failure::http(status),
            other => Failure::new(ErrorKind::Network, other.to_string()),
        })?;
    match response.status().as_u16() {
        200..300 => Ok(response),
        other => Err(Failure::http(other)),
    }
}

fn fetch_bytes(url: &str, range: Option<(u64, u64)>, opts: &HttpOptions) -> Result<Vec<u8>, Failure> {
    let response = get(url, range, opts)?;
    let mut bytes = Vec::new();
    response
        .into_body()
        .into_reader()
        .take(MOST_BYTES)
        .read_to_end(&mut bytes)
        .map_err(|e| Failure::new(ErrorKind::Network, e.to_string()))?;
    Ok(bytes)
}

fn fetch_text(url: &str, opts: &HttpOptions) -> Result<String, Failure> {
    let bytes = fetch_bytes(url, None, opts)?;
    Ok(String::from_utf8_lossy(&bytes).into_owned())
}

// MPEG-TS: 188-byte packets, each starting with 0x47.
fn is_transport_stream(bytes: &[u8]) -> bool {
    bytes.len() >= 188 && bytes[0] == 0x47 && (bytes.len() < 189 || bytes[188] == 0x47)
}

// Drops the ID3 tags packed audio segments start with, which hold the
// segment's time and would otherwise sit between its frames.
fn strip_id3(bytes: &mut Vec<u8>) {
    let mut at = 0;
    while bytes.len() >= at + 10 && &bytes[at..at + 3] == b"ID3" {
        let size = bytes[at + 6..at + 10].iter().fold(0usize, |n, &b| (n << 7) | (b & 0x7f) as usize);
        let footer = if bytes[at + 5] & 0x10 != 0 { 10 } else { 0 };
        at = (at + 10 + size + footer).min(bytes.len());
    }
    bytes.drain(..at);
}

// What a playlist turned out to be.
#[derive(Debug, PartialEq)]
enum Playlist {
    // Variants, each with the address of its media playlist.
    Master(Vec<Variant>),
    Media(Media),
    // A plain list of addresses.
    Plain(Vec<String>),
}

#[derive(Clone, Debug, PartialEq)]
struct Variant {
    uri: String,
    bandwidth: u64,
    codecs: Option<String>,
    // The address of the audio it plays, when that is a playlist of its own.
    audio: Option<String>,
}

#[derive(Debug, PartialEq)]
struct Media {
    target: Duration,
    first_seq: u64,
    segments: Vec<Segment>,
    ended: bool,
    encrypted: bool,
}

#[derive(Debug, PartialEq)]
struct Segment {
    seq: u64,
    uri: String,
    // Offset and length, for part of a file.
    range: Option<(u64, u64)>,
    discontinuity: bool,
    map: Option<Map>,
}

#[derive(Clone, Debug, PartialEq)]
struct Map {
    uri: String,
    range: Option<(u64, u64)>,
}

// A master playlist names its variants, a media playlist its target
// duration; anything else, such as a radio station's M3U with `#EXTINF:-1`
// entries, is a plain list of addresses.
fn parse(text: &str, base: &str) -> Playlist {
    let text = text.trim_start_matches('\u{feff}');
    let lines: Vec<&str> = text.lines().map(str::trim).filter(|l| !l.is_empty()).collect();
    if lines.iter().any(|l| l.starts_with("#EXT-X-STREAM-INF")) {
        return Playlist::Master(parse_master(&lines, base));
    }
    if lines.iter().any(|l| l.starts_with("#EXT-X-TARGETDURATION")) {
        return Playlist::Media(parse_media(&lines, base));
    }
    let entries = lines.iter().filter(|l| !l.starts_with('#')).map(|l| resolve(base, l)).collect();
    Playlist::Plain(entries)
}

fn parse_master(lines: &[&str], base: &str) -> Vec<Variant> {
    // Audio renditions with their own playlist, by group.
    let mut renditions: Vec<(String, bool, String)> = Vec::new();
    for line in lines {
        if let Some(rest) = line.strip_prefix("#EXT-X-MEDIA:") {
            let attrs = attributes(rest);
            let get = |k: &str| attrs.iter().find(|(n, _)| n == k).map(|(_, v)| v.clone());
            if get("TYPE").as_deref() == Some("AUDIO")
                && let (Some(group), Some(uri)) = (get("GROUP-ID"), get("URI"))
            {
                renditions.push((group, get("DEFAULT").as_deref() == Some("YES"), resolve(base, &uri)));
            }
        }
    }
    let mut variants = Vec::new();
    let mut pending: Option<Vec<(String, String)>> = None;
    for line in lines {
        if let Some(rest) = line.strip_prefix("#EXT-X-STREAM-INF:") {
            pending = Some(attributes(rest));
        } else if !line.starts_with('#')
            && let Some(attrs) = pending.take()
        {
            let get = |k: &str| attrs.iter().find(|(n, _)| n == k).map(|(_, v)| v.clone());
            let audio = get("AUDIO").and_then(|group| {
                let in_group: Vec<_> = renditions.iter().filter(|(g, _, _)| *g == group).collect();
                in_group
                    .iter()
                    .find(|(_, default, _)| *default)
                    .or(in_group.first())
                    .map(|(_, _, u)| u.clone())
            });
            variants.push(Variant {
                uri: resolve(base, line),
                bandwidth: get("AVERAGE-BANDWIDTH")
                    .or(get("BANDWIDTH"))
                    .and_then(|b| b.parse().ok())
                    .unwrap_or(0),
                codecs: get("CODECS"),
                audio,
            });
        }
    }
    variants
}

// The media playlist to play from a master playlist's variants: the best
// one whose codecs the engine decodes, preferring sound only, then the
// higher bit rate, then a codec decoded in full over one decoded in part.
fn choose(variants: &[Variant]) -> Option<&str> {
    variants
        .iter()
        .filter_map(|v| {
            let fit = codecs_fit(v.codecs.as_deref())?;
            let sound_only = !fit.video || v.audio.is_some();
            Some(((sound_only, v.bandwidth, fit.whole), v))
        })
        .max_by_key(|(rank, _)| *rank)
        .map(|(_, v)| v.audio.as_deref().unwrap_or(&v.uri))
}

struct Fit {
    video: bool,
    // Every audio codec is decoded in full, not just its core.
    whole: bool,
}

// How a variant's codecs suit the engine; `None` when it cannot play one.
fn codecs_fit(codecs: Option<&str>) -> Option<Fit> {
    let mut fit = Fit { video: false, whole: true };
    let Some(codecs) = codecs else { return Some(fit) };
    for codec in codecs.split(',').map(|c| c.trim().to_ascii_lowercase()) {
        let family = codec.split('.').next().unwrap_or("");
        match codec.as_str() {
            // AAC-LC, MP3 in MP4, and the lossless and open codecs.
            "mp4a.40.2" | "mp4a.40.34" | "mp4a.6b" | "mp4a.69" | "mp3" | "flac" | "opus" | "alac" => {}
            // HE-AAC: its AAC-LC core is played, without the high band.
            "mp4a.40.5" | "mp4a.40.29" => fit.whole = false,
            _ if matches!(
                family,
                "avc1" | "avc3" | "hvc1" | "hev1" | "av01" | "vp09" | "vp8" | "dvh1" | "dvhe"
            ) =>
            {
                fit.video = true;
            }
            _ => return None,
        }
    }
    Some(fit)
}

fn parse_media(lines: &[&str], base: &str) -> Media {
    let mut media = Media {
        target: Duration::from_secs(6),
        first_seq: 0,
        segments: Vec::new(),
        ended: false,
        encrypted: false,
    };
    let mut seq = None;
    let mut discontinuity = false;
    let mut map: Option<Map> = None;
    let mut range: Option<(u64, Option<u64>)> = None;
    // Where the last part of a file ended, for a range that names no offset.
    let mut range_end: Option<(String, u64)> = None;
    for line in lines {
        if let Some(v) = line.strip_prefix("#EXT-X-TARGETDURATION:") {
            let secs = v.trim().parse::<f64>().ok().filter(|s| s.is_finite());
            if let Some(target) = secs.and_then(|s| Duration::try_from_secs_f64(s.clamp(0.2, 60.0)).ok()) {
                media.target = target;
            }
        } else if let Some(v) = line.strip_prefix("#EXT-X-MEDIA-SEQUENCE:") {
            media.first_seq = v.trim().parse().unwrap_or(0);
        } else if line.starts_with("#EXT-X-DISCONTINUITY")
            && !line.starts_with("#EXT-X-DISCONTINUITY-SEQUENCE")
        {
            discontinuity = true;
        } else if line.starts_with("#EXT-X-ENDLIST") {
            media.ended = true;
        } else if let Some(v) = line.strip_prefix("#EXT-X-KEY:") {
            let attrs = attributes(v);
            let method = attrs.iter().find(|(n, _)| n == "METHOD").map(|(_, v)| v.as_str());
            media.encrypted = method.is_some_and(|m| m != "NONE");
        } else if let Some(v) = line.strip_prefix("#EXT-X-MAP:") {
            let attrs = attributes(v);
            let get = |k: &str| attrs.iter().find(|(n, _)| n == k).map(|(_, v)| v.clone());
            map = get("URI").map(|uri| Map {
                uri: resolve(base, &uri),
                range: get("BYTERANGE")
                    .and_then(|r| byte_range(&r))
                    .map(|(len, off)| (off.unwrap_or(0), len)),
            });
        } else if let Some(v) = line.strip_prefix("#EXT-X-BYTERANGE:") {
            range = byte_range(v);
        } else if !line.starts_with('#') {
            let uri = resolve(base, line);
            let n = *seq.get_or_insert(media.first_seq);
            seq = Some(n.saturating_add(1));
            let part = range.take().and_then(|(len, offset)| {
                let offset = offset.unwrap_or_else(|| match &range_end {
                    Some((u, end)) if *u == uri => *end,
                    _ => 0,
                });
                range_end = Some((uri.clone(), offset.checked_add(len)?));
                Some((offset, len))
            });
            media.segments.push(Segment {
                seq: n,
                uri,
                range: part,
                discontinuity: std::mem::take(&mut discontinuity),
                map: map.clone(),
            });
        }
    }
    media
}

// "1000@200" gives a length of 1000 from offset 200.
fn byte_range(value: &str) -> Option<(u64, Option<u64>)> {
    let (len, offset) = match value.trim().split_once('@') {
        Some((l, o)) => (l, Some(o.trim().parse().ok()?)),
        None => (value, None),
    };
    Some((len.trim().parse().ok()?, offset))
}

// `NAME=value,NAME="quoted, value"` as pairs, quotes taken off.
fn attributes(text: &str) -> Vec<(String, String)> {
    let mut out = Vec::new();
    let mut rest = text.trim();
    while !rest.is_empty() {
        let Some((name, after)) = rest.split_once('=') else { break };
        let (value, next) = match after.strip_prefix('"') {
            Some(quoted) => match quoted.split_once('"') {
                Some((v, n)) => (v, n.trim_start_matches(',')),
                None => (quoted, ""),
            },
            None => match after.split_once(',') {
                Some((v, n)) => (v, n),
                None => (after, ""),
            },
        };
        out.push((name.trim().to_ascii_uppercase(), value.trim().to_string()));
        rest = next.trim_start();
    }
    out
}

// `reference` as a full address, read against the playlist at `base`.
fn resolve(base: &str, reference: &str) -> String {
    let reference = reference.trim();
    if reference.contains("://") {
        return reference.to_string();
    }
    let scheme_end = base.find("://").map_or(0, |i| i + 3);
    if let Some(rest) = reference.strip_prefix("//") {
        return format!("{}{rest}", &base[..scheme_end]);
    }
    let base = base.split(['?', '#']).next().unwrap_or(base);
    if reference.starts_with('/') {
        let host_end = base[scheme_end..].find('/').map_or(base.len(), |i| scheme_end + i);
        return format!("{}{reference}", &base[..host_end]);
    }
    let dir_end = base.rfind('/').filter(|&i| i >= scheme_end).map_or(base.len(), |i| i + 1);
    let dir = &base[..dir_end];
    if dir.ends_with('/') { format!("{dir}{reference}") } else { format!("{dir}/{reference}") }
}

#[cfg(test)]
mod tests {
    use super::*;

    #[test]
    fn addresses_resolve_against_the_playlist() {
        let base = "https://h.example/live/radio/index.m3u8?token=1";
        assert_eq!(resolve(base, "seg1.aac"), "https://h.example/live/radio/seg1.aac");
        assert_eq!(resolve(base, "/other/a.aac"), "https://h.example/other/a.aac");
        assert_eq!(resolve(base, "//cdn.example/x.aac"), "https://cdn.example/x.aac");
        assert_eq!(resolve(base, "http://o.example/y.aac"), "http://o.example/y.aac");
        assert_eq!(resolve("http://h.example", "a.m3u8"), "http://h.example/a.m3u8");
    }

    #[test]
    fn reads_attributes_with_commas_in_quotes() {
        let attrs = attributes(r#"BANDWIDTH=128000,CODECS="mp4a.40.2,avc1.4d401f",AUDIO="aud""#);
        assert_eq!(attrs[0], ("BANDWIDTH".into(), "128000".into()));
        assert_eq!(attrs[1], ("CODECS".into(), "mp4a.40.2,avc1.4d401f".into()));
        assert_eq!(attrs[2], ("AUDIO".into(), "aud".into()));
    }

    #[test]
    fn picks_the_best_variant_it_can_decode() {
        let text = "#EXTM3U\n\
            #EXT-X-STREAM-INF:BANDWIDTH=64000,CODECS=\"mp4a.40.5\"\nhe.m3u8\n\
            #EXT-X-STREAM-INF:BANDWIDTH=128000,CODECS=\"mp4a.40.2\"\nlc.m3u8\n\
            #EXT-X-STREAM-INF:BANDWIDTH=320000,CODECS=\"ec-3\"\nac3.m3u8\n\
            #EXT-X-STREAM-INF:BANDWIDTH=900000,CODECS=\"avc1.4d401f,mp4a.40.2\"\nvideo.m3u8\n";
        let Playlist::Master(variants) = parse(text, "http://h/m.m3u8") else { panic!() };
        assert_eq!(variants.len(), 4);
        assert_eq!(choose(&variants), Some("http://h/lc.m3u8"));
        // With only HE-AAC and something unplayable, the HE-AAC one.
        assert_eq!(choose(&[variants[0].clone(), variants[2].clone()]), Some("http://h/he.m3u8"));
        // Nothing playable at all.
        assert_eq!(choose(&[variants[2].clone()]), None);
    }

    #[test]
    fn a_variant_with_its_own_audio_plays_that() {
        let text = "#EXTM3U\n\
            #EXT-X-MEDIA:TYPE=AUDIO,GROUP-ID=\"a\",NAME=\"en\",DEFAULT=YES,URI=\"audio/en.m3u8\"\n\
            #EXT-X-STREAM-INF:BANDWIDTH=900000,CODECS=\"avc1.4d401f,mp4a.40.2\",AUDIO=\"a\"\nvideo.m3u8\n";
        let Playlist::Master(variants) = parse(text, "http://h/m.m3u8") else { panic!() };
        assert_eq!(choose(&variants), Some("http://h/audio/en.m3u8"));
    }

    #[test]
    fn reads_a_media_playlist() {
        let text = "#EXTM3U\n#EXT-X-TARGETDURATION:4\n#EXT-X-MEDIA-SEQUENCE:120\n\
            #EXT-X-MAP:URI=\"init.mp4\"\n#EXTINF:4,\na.m4s\n#EXT-X-DISCONTINUITY\n#EXTINF:4,\nb.m4s\n\
            #EXT-X-BYTERANGE:100@0\n#EXTINF:4,\nc.aac\n#EXT-X-BYTERANGE:50\n#EXTINF:4,\nc.aac\n#EXT-X-ENDLIST\n";
        let Playlist::Media(media) = parse(text, "http://h/x/list.m3u8") else { panic!() };
        assert_eq!(media.target, Duration::from_secs(4));
        assert!(media.ended);
        let seqs: Vec<u64> = media.segments.iter().map(|s| s.seq).collect();
        assert_eq!(seqs, [120, 121, 122, 123]);
        assert!(!media.segments[0].discontinuity && media.segments[1].discontinuity);
        assert_eq!(media.segments[0].map.as_ref().unwrap().uri, "http://h/x/init.mp4");
        assert_eq!(media.segments[2].range, Some((0, 100)));
        assert_eq!(media.segments[3].range, Some((100, 50)));
    }

    #[test]
    fn a_plain_list_gives_its_addresses() {
        let text = "#EXTM3U\n#EXTINF:-1,Station\nhttp://s.example/stream\n";
        assert_eq!(parse(text, "http://h/a.m3u"), Playlist::Plain(vec!["http://s.example/stream".into()]));
        // HLS-looking tags without a target duration, and a byte order mark.
        let text = "\u{feff}#EXTM3U\n#EXT-X-VERSION:3\n#EXTINF:-1,Station\nhttp://s.example/stream\n";
        assert_eq!(parse(text, "http://h/a.m3u"), Playlist::Plain(vec!["http://s.example/stream".into()]));
    }

    #[test]
    fn id3_tags_come_off_the_front() {
        let mut bytes = b"ID3\x04\x00\x00\x00\x00\x00\x02ab\xff\xf1".to_vec();
        strip_id3(&mut bytes);
        assert_eq!(bytes, b"\xff\xf1");
        assert!(is_transport_stream(&[0x47; 400]));
        assert!(!is_transport_stream(b"\xff\xf1rest"));
    }

    #[test]
    fn odd_numbers_in_a_playlist_are_survived() {
        let text = "#EXTM3U
#EXT-X-TARGETDURATION:nan
#EXT-X-MEDIA-SEQUENCE:18446744073709551615
            #EXT-X-BYTERANGE:18446744073709551615@18446744073709551615
#EXTINF:4,
a.aac
#EXTINF:4,
b.aac
";
        let Playlist::Media(media) = parse(text, "http://h/x.m3u8") else { panic!() };
        assert_eq!(media.target, Duration::from_secs(6));
        assert_eq!(media.segments[0].range, None);
        assert_eq!(media.segments[1].seq, u64::MAX);
        for odd in ["inf", "-inf", "1e400", "-3"] {
            let text = format!(
                "#EXTM3U
#EXT-X-TARGETDURATION:{odd}
#EXTINF:4,
a.aac
"
            );
            let Playlist::Media(media) = parse(&text, "http://h/x.m3u8") else { panic!() };
            assert!(
                media.target >= Duration::from_millis(200) && media.target <= Duration::from_secs(60),
                "{odd}"
            );
        }
    }
}
