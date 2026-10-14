//! The engine's own thread: it owns the queue, the mixer and the device,
//! keeps the ring to the device topped up, lines up the next song for a
//! gapless join or a crossfade, and turns what the listener actually hears
//! into events.

use std::collections::HashMap;
use std::sync::{Arc, Mutex, MutexGuard, OnceLock};
use std::thread::{self, Thread};
use std::time::{Duration, Instant};

use crossbeam_channel::{Receiver, Sender, TryRecvError};

use crate::api::{
    EndReason, EngineEvent, EngineListener, PlaybackPosition, PlaybackState, QueueItem, QueueSnapshot,
    RepeatMode,
};
use crate::automix::{
    AutomixSettings, HEAD_SECS, LATEST_EXIT_SECS, LEAD_SECS, LiveAnalysis, PlanInput, PlanSettings,
    RATE_EASE_SECS, SILENCE_BELOW_BODY_DB, SILENCE_FLOOR_DB, TAIL_SECS, TransitionContext, TransitionKind,
    TransitionPlan, TransitionProfile,
};
use crate::crossfade::{FadeSong, SHORTEST_FADE_MS, blend_decision};
use crate::deck::{Deck, DeckStatus};
use crate::decode::TrackInfo;
use crate::lane::Lane;
use crate::mixer::{FadeShape, LowPassSteps, Marker, MixState, Mixer, Transition};
use crate::output::{
    DeviceEvent, Driver, OpenedOutput, OutputDevice, OutputFormat, OutputShared, Renderer, ring,
};
use crate::pace::Pace;
use crate::scout::{ScoutJob, SectionPart};
use crate::sound::model::{DspSettings, EqSettings, ReplayGainSettings, SoundSettings};
use crate::sound::replaygain::{Loudness, stored_replay_gain};
use crate::source::http::{self, HttpOptions};
use crate::source::trust::Trust;
use crate::timeline::{Moment, Timeline};

/// How long a late blend waits for a next song moved to its entry point to
/// read ahead again, in seconds of real time.
const LATE_SEEK_SECS: f64 = 0.5;

/// How much sound is kept queued for the device, and the most it holds.
const RING_TARGET_SECS: f64 = 0.12;
const RING_SECS: f64 = 0.4;

/// How far ahead of a song's end the next one is opened.
const PREPARE_SECS: f64 = 20.0;

/// How long the scout may take before a blend is planned without it.
const SCOUT_LIMIT: Duration = Duration::from_secs(20);

// How many songs' transition profiles are kept before those no longer
// queued are let go.
const PROFILES_KEPT: usize = 64;

/// The latest a waiting blend is decided: this long, in song time, before
/// the crossfade at the end of the song would have to start.
const DECIDE_MARGIN_SECS: f64 = 1.0;

/// Past the deadline, a next song whose length is not known yet is waited
/// for until only the shortest blend and this much are left of the playing one.
const LAST_CALL_SECS: f64 = 0.1;

/// How long without sound, while playing, before it counts as buffering.
const STARVED_GRACE: Duration = Duration::from_millis(80);

/// How long a pause lasts before the device stream is stopped, so the
/// computer can sleep.
const IDLE_DEVICE_AFTER: Duration = Duration::from_secs(5);

const DEFAULT_DEVICE_CHECK: Duration = Duration::from_secs(2);

// A live stream paused this long starts again where its server is now,
// rather than minutes behind it from what was held.
const LIVE_PAUSE_LIMIT: Duration =
    if cfg!(test) { Duration::from_millis(300) } else { Duration::from_secs(30) };

pub enum Command {
    Load { items: Vec<QueueItem>, start_index: usize, start_ms: u64, play: bool },
    PlayNext(Vec<QueueItem>),
    Enqueue(Vec<QueueItem>),
    ReplaceUpcoming(Vec<QueueItem>),
    ReplaceQueue { items: Vec<QueueItem>, current: usize },
    SkipTo(usize),
    SkipNext,
    Play,
    Pause,
    Stop,
    Seek(u64),
    SetVolume(f32),
    SetMuted(bool),
    SetCrossfade(u32),
    SetAutomix(AutomixSettings),
    SetProfile { item_id: String, profile: Option<Arc<TransitionProfile>> },
    SetEq(EqSettings),
    SetReplayGain(ReplayGainSettings),
    SetDsp(DspSettings),
    SetPace(Pace),
    SetRepeat(RepeatMode),
    SetStopAfterCurrent(bool),
    SetStartAfter(u32),
    SetOutputDevice(Option<String>),
    Devices(Sender<Vec<OutputDevice>>),
    SetPositionInterval(u32),
    Shutdown,
}

/// What the player thread is given to run with.
pub struct Driven {
    pub driver: Box<dyn Driver>,
    pub commands: Receiver<Command>,
    pub events: Sender<EngineEvent>,
    pub shared: Arc<Shared>,
}

#[derive(Clone, Debug, PartialEq)]
struct QueueEntryView {
    key: u64,
    id: String,
    duration_ms: Option<u64>,
}

/// A snapshot for the app's quick questions, answered without a round trip.
#[derive(Clone, Debug)]
pub struct Status {
    pub state: PlaybackState,
    pub volume: f32,
    pub device: Option<OutputDevice>,
    /// What the open device's stream runs at.
    pub format: Option<OutputFormat>,
    pub info: Option<TrackInfo>,
    queue: Vec<QueueEntryView>,
    heard: Option<u64>,
}

/// What the app's threads and the player thread share.
pub struct Shared {
    pub listener: Mutex<Option<Arc<dyn EngineListener>>>,
    status: Mutex<Status>,
    timeline: Timeline,
    output: Mutex<Option<Arc<OutputShared>>>,
    player: OnceLock<Thread>,
    /// The certificates trusted for streams, changed from the app's threads.
    pub trust: Arc<Trust>,
    // The client every stream fetches with, knowing those certificates.
    agent: ureq::Agent,
    /// A planner used in place of `automix::plan` by this engine only.
    #[cfg(test)]
    pub planner: Mutex<Option<crate::automix::Planner>>,
}

impl Shared {
    pub fn new() -> Self {
        let trust = Arc::new(Trust::default());
        Shared {
            listener: Mutex::new(None),
            status: Mutex::new(Status {
                state: PlaybackState::Idle,
                volume: 1.0,
                device: None,
                format: None,
                info: None,
                queue: Vec::new(),
                heard: None,
            }),
            timeline: Timeline::new(),
            output: Mutex::new(None),
            player: OnceLock::new(),
            agent: http::agent(trust.clone()),
            trust,
            #[cfg(test)]
            planner: Mutex::new(None),
        }
    }

    pub fn set_player_thread(&self, thread: Thread) {
        let _ = self.player.set(thread);
    }

    /// Plans a transition, with this engine's test planner when it has one.
    fn plan(&self, input: &PlanInput) -> TransitionPlan {
        #[cfg(test)]
        if let Some(planner) = *self.planner.lock().unwrap_or_else(|e| e.into_inner()) {
            return planner(input);
        }
        crate::automix::plan(input)
    }

    /// Wakes the player thread to act on a command now.
    pub fn wake(&self) {
        if let Some(t) = self.player.get() {
            t.unpark();
        }
    }

    pub fn status(&self) -> Status {
        self.lock_status().clone()
    }

    fn lock_status(&self) -> MutexGuard<'_, Status> {
        self.status.lock().unwrap_or_else(|e| e.into_inner())
    }

    fn heard_frame(&self) -> Option<f64> {
        self.heard_frame_at(Instant::now())
    }

    fn heard_frame_at(&self, now: Instant) -> Option<f64> {
        let output = self.output.lock().unwrap_or_else(|e| e.into_inner()).clone();
        output.and_then(|o| o.clock.heard(now))
    }

    pub fn position(&self) -> PlaybackPosition {
        self.position_at(Instant::now())
    }

    /// Where playback is at `now` by the audio clock.
    pub fn position_at(&self, now: Instant) -> PlaybackPosition {
        let moment = self.timeline.at(self.heard_frame_at(now));
        let status = self.lock_status();
        let Some(moment) = moment else {
            return PlaybackPosition { item_id: None, index: None, position_ms: 0.0, duration_ms: None };
        };
        let index = status.queue.iter().position(|e| e.key == moment.key);
        let entry = index.map(|i| &status.queue[i]);
        PlaybackPosition {
            item_id: entry.map(|e| e.id.clone()),
            index: index.map(|i| i as u32),
            position_ms: moment.secs * 1_000.0,
            duration_ms: entry.and_then(|e| e.duration_ms),
        }
    }

    pub fn underruns(&self) -> u64 {
        let output = self.output.lock().unwrap_or_else(|e| e.into_inner()).clone();
        output.map(|o| o.underruns()).unwrap_or(0)
    }

    pub fn queue(&self) -> QueueSnapshot {
        let status = self.lock_status();
        let current = status.heard.and_then(|k| status.queue.iter().position(|e| e.key == k));
        QueueSnapshot {
            item_ids: status.queue.iter().map(|e| e.id.clone()).collect(),
            current_index: current.map(|i| i as u32),
        }
    }
}

impl Default for Shared {
    fn default() -> Self {
        Self::new()
    }
}

struct Entry {
    key: u64,
    item: QueueItem,
    failed: bool,
}

// The next song, opened, while the way into it is still to be decided.
struct Upcoming {
    key: u64,
    deck: Deck,
    loudness: Loudness,
}

// A blend handed to the mixer: from which song into which, starting where
// in the outgoing song, with the incoming one moved to where.
struct Lined {
    from: u64,
    to: u64,
    start_secs: f64,
    entry_secs: f64,
}

// Sections of the playing song and the next one being decoded for the
// planner, by queue key.
#[derive(Default)]
struct Scouting {
    a_key: Option<u64>,
    a_tail: Option<ScoutJob>,
    b_key: Option<u64>,
    b_head: Option<ScoutJob>,
}

impl Scouting {
    // The jobs only use up their time limit while the player plays.
    fn set_running(&mut self, running: bool) {
        for job in [&mut self.a_tail, &mut self.b_head].into_iter().flatten() {
            job.set_running(running);
        }
    }
}

struct Out {
    opened: OpenedOutput,
    shared: Arc<OutputShared>,
    producer: rtrb::Producer<f32>,
    written: u64,
    target: u64,
}

struct Player {
    driver: Box<dyn Driver>,
    commands: Receiver<Command>,
    events: Sender<EngineEvent>,
    shared: Arc<Shared>,
    queue: Vec<Entry>,
    current: Option<usize>,
    next_key: u64,
    settings: SoundSettings,
    crossfade_ms: u32,
    automix: AutomixSettings,
    // Transition profiles from the app, by queue item id.
    profiles: HashMap<String, Arc<TransitionProfile>>,
    upcoming: Option<Upcoming>,
    lined: Option<Lined>,
    scouting: Scouting,
    pace: Pace,
    repeat: RepeatMode,
    stop_after_current: bool,
    // How much of a stream is decoded before it starts to play, in seconds,
    // and whether the song starting now still waits for it.
    start_after: f64,
    gated: bool,
    volume: f32,
    muted: bool,
    device_choice: Option<String>,
    out: Option<Out>,
    mixer: Option<Mixer>,
    mix_state: MixState,
    playing: bool,
    state: PlaybackState,
    ended: bool,
    prepared: Option<u64>,
    heard: Option<u64>,
    heard_frame: f64,
    end_reason: EndReason,
    starved_since: Option<Instant>,
    buffering: bool,
    tick: Duration,
    last_tick: Instant,
    silent_since: Option<Instant>,
    device_running: bool,
    last_default_check: Instant,
    // Where the song was when the device was lost and none would open, to
    // carry on from there once one does.
    lost_at: Option<Moment>,
    // When playback was paused, while it is.
    paused_at: Option<Instant>,
    infos: HashMap<u64, TrackInfo>,
    block: Vec<f32>,
    markers: Vec<Marker>,
    crossed: Vec<Marker>,
}

/// Runs the player until it is told to shut down.
pub fn run(driven: Driven) {
    let mut p = Player {
        driver: driven.driver,
        commands: driven.commands,
        events: driven.events,
        shared: driven.shared,
        queue: Vec::new(),
        current: None,
        next_key: 1,
        settings: SoundSettings::default(),
        crossfade_ms: 0,
        automix: AutomixSettings::default(),
        profiles: HashMap::new(),
        upcoming: None,
        lined: None,
        scouting: Scouting::default(),
        pace: Pace::default(),
        repeat: RepeatMode::Off,
        stop_after_current: false,
        start_after: 0.0,
        gated: false,
        volume: 1.0,
        muted: false,
        device_choice: None,
        out: None,
        mixer: None,
        mix_state: MixState::Ended,
        playing: false,
        state: PlaybackState::Idle,
        ended: false,
        prepared: None,
        heard: None,
        heard_frame: 0.0,
        end_reason: EndReason::Skipped,
        starved_since: None,
        buffering: false,
        tick: Duration::ZERO,
        last_tick: Instant::now(),
        silent_since: None,
        device_running: false,
        last_default_check: Instant::now(),
        lost_at: None,
        paused_at: None,
        infos: HashMap::new(),
        block: vec![0.0; 2048],
        markers: Vec::new(),
        crossed: Vec::new(),
    };
    loop {
        loop {
            match p.commands.try_recv() {
                Ok(Command::Shutdown) | Err(TryRecvError::Disconnected) => {
                    p.shutdown();
                    return;
                }
                Ok(command) => p.handle(command),
                Err(TryRecvError::Empty) => break,
            }
        }
        p.check_device();
        p.manage_queue();
        p.produce();
        p.follow_heard();
        p.publish();
        let wait = if p.playing { Duration::from_millis(10) } else { Duration::from_millis(50) };
        thread::park_timeout(wait);
    }
}

impl Player {
    fn emit(&self, event: EngineEvent) {
        let _ = self.events.send(event);
    }

    fn set_state(&mut self, state: PlaybackState) {
        if self.state != state {
            self.state = state;
            self.emit(EngineEvent::StateChanged { state });
        }
    }

    fn handle(&mut self, command: Command) {
        match command {
            Command::Load { items, start_index, start_ms, play } => {
                self.load(items, start_index, start_ms, play)
            }
            Command::PlayNext(items) => {
                let at = self.current.map(|c| c + 1).unwrap_or(0).min(self.queue.len());
                let entries: Vec<Entry> = items.into_iter().map(|i| self.entry(i)).collect();
                self.queue.splice(at..at, entries);
                self.queue_changed();
            }
            Command::Enqueue(items) => {
                let entries: Vec<Entry> = items.into_iter().map(|i| self.entry(i)).collect();
                self.queue.extend(entries);
                self.queue_changed();
            }
            Command::ReplaceUpcoming(items) => {
                let keep = self.current.map(|c| c + 1).unwrap_or(0).min(self.queue.len());
                let old = self.queue.split_off(keep);
                let entries = self.reuse_entries(old, items);
                self.queue.extend(entries);
                self.queue_changed();
            }
            Command::ReplaceQueue { items, current } => self.replace_queue(items, current),
            Command::SkipTo(index) => {
                if index < self.queue.len() {
                    self.current = Some(index);
                    self.start_current(0.0, Transition::Start, EndReason::Skipped);
                }
            }
            Command::SkipNext => match self.following(false) {
                Some(index) => {
                    self.current = Some(index);
                    self.start_current(0.0, Transition::Start, EndReason::Skipped);
                }
                None => self.stop(EndReason::Skipped),
            },
            Command::Play => self.play(),
            Command::Pause => self.pause(),
            Command::Stop => self.stop(EndReason::Stopped),
            Command::Seek(ms) => self.seek(ms as f64 / 1_000.0),
            Command::SetVolume(v) => {
                self.volume = v;
                self.apply_volume();
            }
            Command::SetMuted(m) => {
                self.muted = m;
                self.apply_volume();
            }
            Command::SetCrossfade(ms) => {
                self.crossfade_ms = ms;
                if let Some(m) = &mut self.mixer {
                    m.finish_fade();
                }
                self.drop_prepared();
            }
            Command::SetProfile { item_id, profile } => match profile {
                Some(profile) => {
                    self.profiles.insert(item_id, profile);
                    if self.profiles.len() > PROFILES_KEPT {
                        let queued: Vec<&str> = self.queue.iter().map(|e| e.item.id.as_str()).collect();
                        self.profiles.retain(|id, _| queued.contains(&id.as_str()));
                    }
                }
                None => {
                    self.profiles.remove(&item_id);
                }
            },
            Command::SetAutomix(settings) => {
                self.automix = settings;
                // A blend already under way plays out as it was planned.
                if !self.mixer.as_ref().is_some_and(|m| m.is_fading()) {
                    self.drop_prepared();
                }
            }
            Command::SetEq(eq) => {
                self.settings.eq = eq;
                self.apply_sound();
            }
            Command::SetReplayGain(rg) => {
                self.settings.replay_gain = rg;
                self.apply_sound();
            }
            Command::SetDsp(dsp) => {
                self.settings.dsp = dsp;
                self.apply_sound();
            }
            Command::SetPace(pace) => {
                self.pace = pace;
                if let Some(m) = &mut self.mixer {
                    m.set_pace(pace);
                }
                self.drop_prepared();
            }
            Command::SetRepeat(mode) => {
                self.repeat = mode;
                self.drop_prepared();
            }
            Command::SetStopAfterCurrent(on) => {
                self.stop_after_current = on;
                self.drop_prepared();
            }
            Command::SetStartAfter(ms) => self.start_after = ms as f64 / 1_000.0,
            Command::SetOutputDevice(id) => {
                self.device_choice = id;
                // Also when the device was lost and none opened since, if
                // there is a song to carry on with.
                if self.out.is_some() || self.mixer.is_some() {
                    self.reopen_output(true);
                }
            }
            Command::Devices(reply) => {
                let _ = reply.send(self.driver.devices());
            }
            Command::SetPositionInterval(ms) => self.tick = Duration::from_millis(ms as u64),
            Command::Shutdown => {}
        }
    }

    // The length the decoder found for an entry, once it opened.
    fn decoded_length(&self, key: u64) -> Option<u64> {
        self.infos.get(&key).and_then(|i| i.duration_ms).filter(|&ms| ms > 0)
    }

    fn entry(&mut self, item: QueueItem) -> Entry {
        let key = self.next_key;
        self.next_key += 1;
        Entry { key, item, failed: false }
    }

    // Entries for items coming into the queue. An item whose id one of the
    // `old` entries has keeps that entry's key, and whether it failed, so
    // the song playing and the one lined up after it carry on untouched.
    fn reuse_entries(&mut self, old: Vec<Entry>, items: Vec<QueueItem>) -> Vec<Entry> {
        let mut known: HashMap<String, Entry> = HashMap::new();
        for e in old {
            known.entry(e.item.id.clone()).or_insert(e);
        }
        items
            .into_iter()
            .map(|mut item| match known.remove(&item.id) {
                Some(e) => {
                    // The decoder's length stands over the listed one.
                    if let Some(ms) = self.decoded_length(e.key) {
                        item.duration_ms = Some(ms);
                    } else if item.duration_ms.is_none() {
                        item.duration_ms = e.item.duration_ms;
                    }
                    Entry { key: e.key, item, failed: e.failed }
                }
                None => self.entry(item),
            })
            .collect()
    }

    // Replaces the whole queue around the playing song, which carries on
    // untouched. It is found in the new list by its id, since the engine
    // may have moved on to the next song before the app heard of it;
    // `current` is used only when it is not there.
    fn replace_queue(&mut self, items: Vec<QueueItem>, current: usize) {
        if items.is_empty() {
            self.load(items, 0, 0, false);
            return;
        }
        let playing = self
            .mixer
            .as_ref()
            .and_then(|m| m.lane())
            .map(|l| l.current().key())
            .or_else(|| self.current_entry().map(|e| e.key));
        let old = std::mem::take(&mut self.queue);
        self.queue = self.reuse_entries(old, items);
        let found = playing.and_then(|k| self.index_of(k));
        self.current = Some(found.unwrap_or(current.min(self.queue.len() - 1)));
        self.queue_changed();
    }

    fn index_of(&self, key: u64) -> Option<usize> {
        self.queue.iter().position(|e| e.key == key)
    }

    fn current_entry(&self) -> Option<&Entry> {
        self.current.and_then(|c| self.queue.get(c))
    }

    fn apply_volume(&mut self) {
        if let Some(out) = &self.out {
            out.shared.set_volume(if self.muted { 0.0 } else { self.volume });
        }
    }

    fn apply_sound(&mut self) {
        if let Some(m) = &mut self.mixer {
            m.set_sound(&self.settings);
        }
    }

    // The entry after the current one, skipping songs that failed. With
    // `repeat_one` honoured, the current one again.
    fn following(&self, repeat_one: bool) -> Option<usize> {
        let current = self.current?;
        if repeat_one && self.repeat == RepeatMode::One {
            return (!self.queue[current].failed).then_some(current);
        }
        let len = self.queue.len();
        for step in 1..=len {
            let i = current + step;
            let i = if i >= len {
                if self.repeat != RepeatMode::All {
                    return None;
                }
                i % len
            } else {
                i
            };
            if !self.queue[i].failed {
                return Some(i);
            }
        }
        None
    }

    // How a queued song is levelled, following the song before it.
    fn loudness(&self, index: usize, previous: Option<usize>) -> Loudness {
        let item = &self.queue[index].item;
        let before = previous.and_then(|p| self.queue.get(p)).and_then(|e| e.item.album_id.as_ref());
        Loudness {
            stored: item.replay_gain.as_ref().and_then(stored_replay_gain),
            follows_same_album: item.album_id.is_some() && item.album_id.as_ref() == before,
        }
    }

    fn http_for(&self, index: usize) -> HttpOptions {
        let item = &self.queue[index].item;
        HttpOptions {
            agent: self.shared.agent.clone(),
            headers: item.headers.iter().map(|h| (h.name.clone(), h.value.clone())).collect(),
            live: item.live,
            hls: item.hls,
            ..Default::default()
        }
    }

    // Whether the playing entry is a live stream.
    fn current_is_live(&self) -> bool {
        self.current_entry().is_some_and(|e| e.item.live)
    }

    fn open_deck(&self, index: usize, start_secs: f64) -> Deck {
        let entry = &self.queue[index];
        Deck::open(entry.key, entry.item.source.clone(), start_secs, self.http_for(index))
    }

    fn load(&mut self, items: Vec<QueueItem>, start_index: usize, start_ms: u64, play: bool) {
        self.queue = items.into_iter().map(|i| self.entry(i)).collect();
        self.publish_queue();
        if self.queue.is_empty() {
            self.stop(EndReason::Skipped);
            return;
        }
        self.current = Some(start_index.min(self.queue.len() - 1));
        self.playing = play;
        self.start_current(start_ms as f64 / 1_000.0, Transition::Start, EndReason::Skipped);
    }

    // Starts the current entry from `secs`, replacing whatever plays.
    fn start_current(&mut self, secs: f64, transition: Transition, reason: EndReason) {
        let Some(index) = self.current else { return };
        // A live stream starts wherever its server is.
        let secs = if self.queue[index].item.live { 0.0 } else { secs };
        if !self.ensure_output() {
            // With a song already loaded, carry on with this one once a
            // device opens.
            if self.mixer.is_some() {
                self.hold_place(Some(Moment { key: self.queue[index].key, secs }));
            }
            return;
        }
        self.lost_at = None;
        // Loaded paused counts as paused from now.
        self.paused_at = (!self.playing).then(Instant::now);
        let previous = self.heard.and_then(|k| self.index_of(k));
        let loudness = self.loudness(index, previous);
        // A stream waits until `start_after` of it is decoded (or all of it,
        // when shorter); a file starts at once.
        let entry = &self.queue[index];
        self.gated = self.start_after > 0.0 && crate::source::is_remote(&entry.item.source);
        let deck = if self.gated {
            Deck::open_ahead(
                entry.key,
                entry.item.source.clone(),
                secs,
                self.http_for(index),
                self.start_after,
            )
        } else {
            self.open_deck(index, secs)
        };
        let key = self.queue[index].key;
        self.drop_prepared();
        self.flush_output(Moment { key, secs });
        let rate = self.out.as_ref().map(|o| o.opened.rate()).unwrap_or(48_000);
        let base = self.out.as_ref().map(|o| o.written).unwrap_or(0);
        if self.mixer.as_ref().is_none_or(|m| m.rate() != rate) {
            self.mixer = Some(Mixer::new(rate, base, &self.settings, self.pace));
        }
        let mixer = self.mixer.as_mut().expect("mixer just made");
        mixer.clear();
        let lane = Lane::new(deck, loudness, &self.settings.replay_gain, rate);
        mixer.start(lane, transition);
        self.mix_state = MixState::Waiting;
        self.ended = false;
        self.end_reason = reason;
        self.starved_since = None;
        let shared = self.out.as_ref().map(|o| o.shared.clone());
        if let Some(s) = shared {
            s.set_paused(!self.playing);
        }
        if self.playing {
            self.wake_device();
            self.set_state(PlaybackState::Playing);
        } else {
            self.set_state(PlaybackState::Paused);
        }
    }

    fn play(&mut self) {
        if self.queue.is_empty() {
            return;
        }
        self.playing = true;
        self.scouting.set_running(true);
        let long_paused = self.paused_at.take().is_some_and(|at| at.elapsed() >= LIVE_PAUSE_LIMIT);
        if long_paused && self.current_is_live() && self.mixer.is_some() && !self.ended {
            log::info!("a live stream paused a long while starts again where it is now");
            self.start_current(0.0, Transition::Start, EndReason::Skipped);
            return;
        }
        if self.mixer.is_none() || self.ended {
            if self.current.is_none() {
                self.current = Some(0);
            }
            self.start_current(0.0, Transition::Start, EndReason::Finished);
            return;
        }
        if self.out.is_none() {
            // The device was lost: open one again, carrying on from where
            // the song was heard.
            self.reopen_output(true);
            return;
        }
        self.wake_device();
        if let Some(out) = &self.out {
            out.shared.set_paused(false);
        }
        self.set_state(if self.buffering { PlaybackState::Buffering } else { PlaybackState::Playing });
    }

    fn pause(&mut self) {
        if self.playing {
            self.paused_at = Some(Instant::now());
        }
        self.playing = false;
        self.scouting.set_running(false);
        if let Some(out) = &self.out {
            out.shared.set_paused(true);
        }
        self.starved_since = None;
        if self.mixer.is_some() && !self.ended {
            self.set_state(PlaybackState::Paused);
        }
    }

    fn stop(&mut self, reason: EndReason) {
        if let Some(key) = self.heard.take() {
            self.emit_ended(key, reason);
        }
        self.drop_prepared();
        self.mixer = None;
        self.playing = false;
        self.ended = false;
        if let Some(out) = &self.out {
            out.shared.set_paused(true);
            out.shared.flush_to(out.written);
        }
        self.shared.timeline.clear();
        self.set_state(PlaybackState::Idle);
    }

    fn seek(&mut self, secs: f64) {
        let Some(index) = self.current else { return };
        if self.queue[index].item.live {
            // A live stream plays on from wherever its server is.
            return;
        }
        let key = self.queue[index].key;
        let can_seek = self.mixer.as_ref().and_then(|m| m.lane()).is_some_and(|l| l.current().key() == key);
        if !can_seek || self.ended {
            let reason = if self.ended { EndReason::Finished } else { EndReason::Skipped };
            self.start_current(secs, Transition::Start, reason);
            return;
        }
        self.drop_prepared();
        if let Some(m) = &mut self.mixer {
            m.seek(secs);
        }
        self.mix_state = MixState::Waiting;
        if self.out.is_none() {
            self.hold_place(Some(Moment { key, secs }));
        }
        self.flush_output(Moment { key, secs });
    }

    // Drops what the device has queued, with a short fade, and holds the
    // position at `moment` until the new sound is heard.
    fn flush_output(&mut self, moment: Moment) {
        if let Some(out) = &self.out {
            let heard = self.shared.heard_frame().unwrap_or(0.0);
            out.shared.flush_to(out.written);
            self.shared.timeline.discard_unheard(heard, out.written);
            self.shared.timeline.hold(out.written, moment);
            self.heard_frame = self.heard_frame.max(out.written as f64 - 0.5);
        }
    }

    // After the queue changed around the playing song.
    fn queue_changed(&mut self) {
        if let Some(key) = self.mixer.as_ref().and_then(|m| m.lane()).map(|l| l.current().key()) {
            self.current = self.index_of(key).or(self.current);
        }
        let next_key = self.following(true).map(|i| self.queue[i].key);
        if self.prepared.is_some() && self.prepared != next_key {
            self.drop_prepared();
        }
        if let Some(lane) = self.mixer.as_mut().and_then(|m| m.lane_mut())
            && next_key.is_some()
        {
            lane.last = false;
        }
        self.publish_queue();
    }

    // Forgets the song lined up after the current one.
    fn drop_prepared(&mut self) {
        self.prepared = None;
        self.upcoming = None;
        if let Some(m) = &mut self.mixer {
            drop(m.cancel_planned_fade());
            if let Some(lane) = m.lane_mut() {
                lane.set_next(None, Loudness::default());
                lane.last = false;
            }
        }
    }

    fn manage_queue(&mut self) {
        let Some(mixer) = &mut self.mixer else { return };
        for (key, failure) in mixer.take_failures() {
            if let Some(i) = self.queue.iter().position(|e| e.key == key) {
                self.queue[i].failed = true;
                let id = self.queue[i].item.id.clone();
                let _ = self.events.send(EngineEvent::Error {
                    kind: failure.kind,
                    message: failure.message.clone(),
                    item_id: Some(id),
                });
            }
            if self.prepared == Some(key) {
                self.prepared = None;
                self.upcoming = None;
                if let Some(lane) = mixer.lane_mut() {
                    lane.set_next(None, Loudness::default());
                }
            }
        }
        let Some(lane) = mixer.lane() else { return };
        // Keep what the decoder found out, for events and positions. Its
        // length is the sound's own, so it stands over the listed one.
        for deck in [Some(lane.current()), lane.next()].into_iter().flatten() {
            if !self.infos.contains_key(&deck.key())
                && let Some(info) = deck.info()
            {
                if let Some(i) = self.queue.iter().position(|e| e.key == deck.key())
                    && let Some(ms) = info.duration_ms.filter(|&ms| ms > 0)
                {
                    self.queue[i].item.duration_ms = Some(ms);
                }
                self.infos.insert(deck.key(), info);
            }
        }
        // Follow the lane onto the song it plays now.
        let lane_key = lane.current().key();
        if self.current_entry().map(|e| e.key) != Some(lane_key)
            && let Some(i) = self.index_of(lane_key)
        {
            self.current = Some(i);
            if self.prepared == Some(lane_key) {
                self.prepared = None;
            }
        }
        self.update_scouts();
        self.replan_if_cut_short();
        if self.prepared.is_none() {
            self.prepare_next();
        } else if self.upcoming.is_some() {
            self.settle_next();
        }
    }

    // A blend lined up past where the playing song's sound turns out to end
    // (its decoder reached the end of the stream early) is taken back, so the
    // next song is decided again on the sound's real end.
    fn replan_if_cut_short(&mut self) {
        let Some(lined) = &self.lined else { return };
        if self.prepared != Some(lined.to) || self.upcoming.is_some() {
            return;
        }
        let Some(mixer) = &self.mixer else { return };
        let Some(lane) = mixer.lane() else { return };
        if lane.current().key() != lined.from || !mixer.has_planned_fade() {
            return;
        }
        let Some(left) = lane.left_after_end_secs() else { return };
        let end = lane.position().map(|(_, s)| s).unwrap_or(0.0) + left;
        if end >= lined.start_secs {
            return;
        }
        let (from, to, moved) = (lined.from, lined.to, lined.entry_secs > 0.0);
        self.lined = None;
        let Some(deck) = self.mixer.as_mut().and_then(|m| m.cancel_planned_fade()) else { return };
        let (Some(current), Some(next)) = (self.index_of(from), self.index_of(to)) else { return };
        if moved {
            deck.seek(0.0);
        }
        let loudness = self.loudness(next, Some(current));
        self.upcoming = Some(Upcoming { key: to, deck, loudness });
        log::info!("automix: the sound ends at {end:.2} s, before the blend; deciding again");
    }

    // What is left of the playing song at `current`, in seconds: by its
    // length, or, once its decoder has reached the end of the stream, by
    // what the lane still holds, which is less when the sound stops short of
    // the stated length.
    fn remaining_secs(&self, current: usize, lane: &Lane) -> Option<f64> {
        let position = lane.position().map(|(_, s)| s).unwrap_or(0.0);
        let stated = self.length_ms(current).map(|d| d as f64 / 1_000.0 - position);
        match lane.left_after_end_secs() {
            Some(left) => Some(stated.map_or(left, |s| s.min(left))),
            None => stated,
        }
    }

    // The playing song's length in milliseconds as far as its sound goes:
    // the stated length, cut to where the sound ends once the decoder has
    // found that.
    fn sounding_length_ms(&self, current: usize) -> Option<u64> {
        let stated = self.length_ms(current);
        let Some(lane) = self.mixer.as_ref().and_then(|m| m.lane()) else { return stated };
        let Some(left) = lane.left_after_end_secs() else { return stated };
        let position = lane.position().map(|(_, s)| s).unwrap_or(0.0);
        let heard = ((position + left) * 1_000.0).round() as u64;
        Some(stated.map_or(heard, |s| s.min(heard))).filter(|&d| d > 0)
    }

    // A queued song's length in milliseconds: its decoder's once it opened,
    // else the queue's.
    fn length_ms(&self, index: usize) -> Option<u64> {
        let entry = &self.queue[index];
        self.decoded_length(entry.key).or(entry.item.duration_ms).filter(|&d| d > 0)
    }

    // With smart transitions on, decodes the end of the playing song once
    // it has played a second and its length is known, and the start of the
    // next one as soon as it is known; again whenever either changes. A song
    // with a transition profile from the app is not decoded.
    fn update_scouts(&mut self) {
        // A live stream has no end to blend from.
        if !self.automix.smart_transitions || self.crossfade_ms == 0 || self.current_is_live() {
            self.scouting = Scouting::default();
            return;
        }
        let Some(lane) = self.mixer.as_ref().and_then(|m| m.lane()) else { return };
        let a_key = lane.current().key();
        let position = lane.position().filter(|(k, _)| *k == a_key).map(|(_, s)| s).unwrap_or(0.0);
        if self.scouting.a_key != Some(a_key) {
            self.scouting.a_key = Some(a_key);
            self.scouting.a_tail = None;
        }
        if self.scouting.a_tail.is_none()
            && position >= 1.0
            && let Some(index) = self.index_of(a_key)
            && let Some(len) = self.length_ms(index)
            && self.profile_at(index).is_none()
        {
            let part = SectionPart::Tail { secs: TAIL_SECS, len_secs: Some(len as f64 / 1_000.0) };
            let item = &self.queue[index].item;
            let (source, bpm) = (item.source.clone(), item.bpm);
            self.scouting.a_tail = Some(ScoutJob::start(source, self.http_for(index), part, bpm));
        }
        let next = if self.stop_after_current { None } else { self.following(true) };
        let b_key = next.map(|i| self.queue[i].key).filter(|&k| k != a_key);
        if self.scouting.b_key != b_key {
            self.scouting.b_key = b_key;
            self.scouting.b_head = next
                .filter(|&i| b_key.is_some() && self.profile_at(i).is_none() && !self.queue[i].item.live)
                .map(|i| {
                    let part = SectionPart::Head { secs: HEAD_SECS };
                    let item = &self.queue[i].item;
                    ScoutJob::start(item.source.clone(), self.http_for(i), part, item.bpm)
                });
        }
        let playing = self.playing;
        self.scouting.set_running(playing);
    }

    // Whether the scout is done (or given up on) for the songs `a` then `b`;
    // a song with a profile needs none.
    fn scouts_settled(&self, a: u64, b: u64) -> bool {
        let s = &self.scouting;
        let profiled = |key: u64| self.index_of(key).and_then(|i| self.profile_at(i)).is_some();
        let tail = profiled(a)
            || (s.a_key == Some(a) && s.a_tail.as_ref().is_some_and(|j| j.is_settled(SCOUT_LIMIT)));
        let head = profiled(b)
            || (s.b_key == Some(b) && s.b_head.as_ref().is_some_and(|j| j.is_settled(SCOUT_LIMIT)));
        tail && head
    }

    // The transition profile the app handed over for the queued song at `index`.
    fn profile_at(&self, index: usize) -> Option<&Arc<TransitionProfile>> {
        self.profiles.get(&self.queue.get(index)?.item.id)
    }

    // Lines up the next song, for a gapless join or a crossfade.
    fn prepare_next(&mut self) {
        let Some(current) = self.current else { return };
        let Some(mixer) = &self.mixer else { return };
        let Some(lane) = mixer.lane() else { return };
        if lane.next().is_some() || mixer.has_planned_fade() {
            return;
        }
        let next = if self.stop_after_current { None } else { self.following(true) };
        let Some(next) = next else {
            if let Some(lane) = self.mixer.as_mut().and_then(|m| m.lane_mut()) {
                lane.last = true;
            }
            return;
        };
        let failed = matches!(lane.current().status(), DeckStatus::Failed(_));
        if !failed && lane.current().info().is_none() {
            // Still opening: its length may be known in a moment.
            return;
        }
        // A live stream plays on until it fails or the listener moves on, so
        // nothing is opened behind it before then.
        let ended = lane.current().status() == DeckStatus::Ended;
        if lane.current().is_live() && !failed && !ended {
            return;
        }
        let remaining = self.remaining_secs(current, lane);
        let speed = self.pace.speed as f64;
        let mut window = PREPARE_SECS + self.crossfade_ms as f64 / 1_000.0 * speed;
        if self.automix.smart_transitions {
            // A planned blend may start well before the end.
            window += LATEST_EXIT_SECS;
        }
        if !failed && remaining.is_some_and(|r| r > window) {
            return;
        }
        let deck = self.open_deck(next, 0.0);
        let loudness = self.loudness(next, Some(current));
        let key = self.queue[next].key;
        self.prepared = Some(key);
        self.upcoming = Some(Upcoming { key, deck, loudness });
        self.settle_next();
    }

    // Decides how the opened next song follows the playing one, once what
    // the decision needs is known: the next song's real length (from its
    // decoder when the queue has none) and, with smart transitions, the
    // scouted sections. Waiting ends in time for the crossfade at the end
    // of the song; anything still unknown then means a gapless join.
    fn settle_next(&mut self) {
        let (Some(current), Some(up)) = (self.current, &self.upcoming) else { return };
        let up_key = up.key;
        let Some(next) = self.index_of(up_key) else {
            self.drop_prepared();
            return;
        };
        let up_failed = matches!(up.deck.status(), DeckStatus::Failed(_));
        if let Some(info) = up.deck.info()
            && !self.infos.contains_key(&up_key)
        {
            // The decoder's length stands over the listed one.
            if let Some(ms) = info.duration_ms.filter(|&ms| ms > 0) {
                self.queue[next].item.duration_ms = Some(ms);
            }
            self.infos.insert(up_key, info);
        }
        let Some(lane) = self.mixer.as_ref().and_then(|m| m.lane()) else { return };
        let failed = matches!(lane.current().status(), DeckStatus::Failed(_));
        let position = lane.position().map(|(_, s)| s).unwrap_or(0.0);
        let remaining = self.remaining_secs(current, lane);
        let speed = self.pace.speed as f64;
        let mut blend_secs = self.crossfade_ms as f64 / 1_000.0 * speed;
        if self.automix.smart_transitions {
            // Room to line the incoming song up from its entry point.
            blend_secs += LEAD_SECS * speed;
        }
        let can_blend = self.crossfade_ms > 0
            && self.repeat != RepeatMode::One
            && !self.stop_after_current
            && !failed
            && next != current;
        // The next song's length is its decoder's once it has opened. Until
        // the deadline the decision waits for that; after it, a listed
        // length will do.
        let opened = self.infos.contains_key(&up_key) || up_failed;
        let next_known = opened || self.length_ms(next).is_some();
        let scouted = !self.automix.smart_transitions || self.scouts_settled(self.queue[current].key, up_key);
        let deadline = remaining.is_none_or(|r| r <= blend_secs + DECIDE_MARGIN_SECS);
        if can_blend && !deadline && !(opened && scouted) {
            return;
        }
        // Past the deadline the next song's length is still worth waiting
        // for while a short blend over what is left still fits.
        let last_call =
            remaining.is_none_or(|r| r <= SHORTEST_FADE_MS as f64 / 1_000.0 * speed + LAST_CALL_SECS);
        if can_blend && !next_known && !last_call {
            return;
        }
        self.decide_next(current, next, position, failed);
    }

    fn decide_next(&mut self, current: usize, next: usize, position: f64, failed: bool) {
        let Some(Upcoming { key, deck, loudness }) = self.upcoming.take() else { return };
        let song = |e: &Entry, duration: Option<u64>| FadeSong {
            album_id: e.item.album_id.clone(),
            album_order: e.item.album_order,
            duration_ms: duration.unwrap_or(0),
        };
        let current_song = song(&self.queue[current], self.sounding_length_ms(current));
        let next_song = song(&self.queue[next], self.length_ms(next));
        let decision = if failed {
            Err("this song failed")
        } else {
            blend_decision(
                &current_song,
                Some(&next_song),
                self.crossfade_ms as u64,
                self.repeat == RepeatMode::One,
                self.stop_after_current,
            )
        };
        let current_key = self.queue[current].key;
        let speed = self.pace.speed as f64;
        let total = current_song.duration_ms as f64 / 1_000.0;
        let fade_ms = match decision {
            Ok(ms) => ms,
            Err(why) => {
                self.join_gaplessly(current_key, key, deck, loudness, total, why);
                return;
            }
        };
        let blend_ms = (fade_ms as f64 * speed).round() as i64;
        let b_len = next_song.duration_ms as f64 / 1_000.0;
        let now_ms = (position * 1_000.0) as i64;
        let (mut plan, live) = self.make_plan(current, next, &current_song, &next_song, blend_ms, now_ms);
        if plan.kind == TransitionKind::Gapless {
            let why = plan.reason.strip_prefix("gapless: ").unwrap_or(&plan.reason).to_string();
            self.join_gaplessly(current_key, key, deck, loudness, total, &why);
            return;
        }
        // A start already passed, or too soon to line the incoming song up
        // (a seek near the end), can only blend over what is left.
        let lead_ms = if self.automix.smart_transitions { (LEAD_SECS * speed * 1_000.0) as i64 } else { 0 };
        if !plan.late && now_ms + lead_ms > plan.start_ms {
            // A song that comes in part way is moved there first, which
            // empties what it had read ahead: the blend waits for it to read
            // again, or the mixer would find it not ready and join gaplessly.
            let settle_ms = if plan.entry_ms > 0 { (LATE_SEEK_SECS * speed * 1_000.0) as i64 } else { 0 };
            match plan.late_from(now_ms + settle_ms) {
                Some(late) if late.overlap_secs() / speed * 1_000.0 >= SHORTEST_FADE_MS as f64 => plan = late,
                _ => {
                    self.join_gaplessly(current_key, key, deck, loudness, total, "too late to blend");
                    return;
                }
            }
        }
        if plan.entry_ms > 0 {
            deck.seek(plan.entry_secs());
        }
        let body_db = live
            .as_ref()
            .and_then(|l| l.body_level_db)
            .or_else(|| self.profile_at(current).and_then(|p| p.body_db));
        let shape = self.shape_of(&plan, b_len, body_db);
        let rate = self.mixer.as_ref().map(|m| m.rate()).unwrap_or(48_000) as f64;
        let frames = (plan.overlap_secs() * rate) as u64;
        if let Some(mixer) = self.mixer.as_mut() {
            mixer.plan_fade(current_key, plan.start_secs(), frames, deck, loudness, shape);
        }
        self.lined = Some(Lined {
            from: current_key,
            to: key,
            start_secs: plan.start_secs(),
            entry_secs: plan.entry_secs(),
        });
        let reason = plan.describe();
        self.tell_plan(current_key, key, plan.start_secs(), plan.entry_secs(), plan.overlap_secs(), reason);
    }

    // The blend from the song at `current` into the one at `next`,
    // `blend_ms` of song time long by the crossfade rules, decided `now_ms`
    // into the playing song. Also hands back what the live tap heard of it.
    fn make_plan(
        &self,
        current: usize,
        next: usize,
        current_song: &FadeSong,
        next_song: &FadeSong,
        blend_ms: i64,
        now_ms: i64,
    ) -> (TransitionPlan, Option<LiveAnalysis>) {
        let a_len_ms = current_song.duration_ms as i64;
        if !self.automix.smart_transitions {
            return (
                TransitionPlan::fixed_crossfade(a_len_ms, blend_ms, "smart transitions off")
                    .with_curve(self.automix.fade_curve),
                None,
            );
        }
        let (a, b) = (self.queue[current].key, self.queue[next].key);
        let (a_item, b_item) = (&self.queue[current].item, &self.queue[next].item);
        let s = &self.scouting;
        // A profile's end is measured against the whole song already, so the
        // live tap's level does not go with it, and its tempo is the whole
        // song's.
        let (a_profile, b_profile) = (self.profile_at(current), self.profile_at(next));
        let tail = match a_profile {
            Some(p) => Some(p.tail_analysis()),
            None => s.a_tail.as_ref().filter(|_| s.a_key == Some(a)).and_then(|j| j.analysis()),
        };
        let head = match b_profile {
            Some(p) => Some(p.head_analysis()),
            None => s.b_head.as_ref().filter(|_| s.b_key == Some(b)).and_then(|j| j.analysis()),
        };
        let speed = self.pace.speed as f64;
        let live = self.mixer.as_ref().and_then(|m| m.live_analysis(a, a_item.bpm));
        let body_level_db = match a_profile {
            Some(_) => None,
            None => live.as_ref().and_then(|l| l.body_level_db),
        };
        let tempo_prior =
            a_profile.and_then(|p| p.tempo_prior()).or_else(|| live.as_ref().and_then(|l| l.tempo_prior));
        let max_ms =
            if self.automix.max_overlap_ms > 0 { self.automix.max_overlap_ms } else { self.crossfade_ms };
        let input = PlanInput {
            current: current_song.clone(),
            next: next_song.clone(),
            tail: tail.as_ref(),
            head: head.as_ref(),
            settings: PlanSettings {
                max_overlap_ms: (max_ms as f64 * speed).round() as i64,
                smart: true,
                filter_sweeps: self.automix.filter_sweeps,
                beat_match: self.automix.match_tempo,
                fade_curve: self.automix.fade_curve,
            },
            context: TransitionContext {
                now_ms,
                played_ms: live.as_ref().map_or(now_ms, |l| l.heard_ms),
                repeat_one: self.repeat == RepeatMode::One,
                stop_at_end_of_song: self.stop_after_current,
                pace: speed,
                skip_silence: false,
                current_genre: a_item.genre.clone(),
                next_genre: b_item.genre.clone(),
                body_level_db,
                tempo_prior,
            },
        };
        let plan = self.shared.plan(&input);
        // A plan that does not fit the songs falls back to the fixed point.
        let b_len_ms = next_song.duration_ms as i64;
        let fits = plan.kind == TransitionKind::Gapless
            || (plan.overlap_ms > 0
                && plan.start_ms >= 0
                && plan.start_ms + plan.overlap_ms <= a_len_ms
                && plan.entry_ms >= 0
                && plan.entry_ms + plan.overlap_ms < b_len_ms);
        if fits {
            (plan, live)
        } else {
            let why = format!("the plan did not fit ({})", plan.reason);
            (TransitionPlan::fixed_crossfade(a_len_ms, blend_ms, &why), live)
        }
    }

    // How the mixer runs `plan`. The outgoing song's silence gate comes from
    // its level, as heard so far or else from its profile.
    fn shape_of(&self, plan: &TransitionPlan, b_len: f64, body_db: Option<f64>) -> FadeShape {
        // The incoming song must outlast the rate's ease back to normal.
        let room = b_len - plan.entry_secs() > plan.overlap_secs() + RATE_EASE_SECS + 1.0;
        let gate =
            body_db.map_or(SILENCE_FLOOR_DB, |body| SILENCE_FLOOR_DB.max(body - SILENCE_BELOW_BODY_DB));
        let equal_power = plan.k == 0.0;
        FadeShape {
            k: plan.k,
            curve: plan.curve,
            filter_strength: plan.filter_strength,
            steps: plan.low_pass_glide().map(|glide| LowPassSteps { beats: plan.beat_progress(), glide }),
            rate: plan.beat_match_rate.filter(|_| room),
            silence_gate_db: (!equal_power).then_some(gate as f32),
            headroom_db: plan.headroom_db as f32,
        }
    }

    fn join_gaplessly(&mut self, from: u64, to: u64, deck: Deck, loudness: Loudness, a_len: f64, why: &str) {
        if let Some(lane) = self.mixer.as_mut().and_then(|m| m.lane_mut()) {
            lane.set_next(Some(deck), loudness);
        }
        self.tell_plan(from, to, a_len, 0.0, 0.0, format!("automix: gapless, {why}"));
    }

    fn tell_plan(&self, from: u64, to: u64, start: f64, entry: f64, overlap: f64, reason: String) {
        log::info!("{reason}");
        if let (Some(from_id), Some(to_id)) = (self.id_of(from), self.id_of(to)) {
            self.emit(EngineEvent::TransitionPlanned {
                from_id,
                to_id,
                start_ms: (start.max(0.0) * 1_000.0) as u64,
                entry_ms: (entry * 1_000.0) as u64,
                overlap_ms: (overlap * 1_000.0) as u64,
                reason,
            });
        }
    }

    // Keeps the device's ring topped up.
    fn produce(&mut self) {
        let (Some(out), Some(mixer)) = (&mut self.out, &mut self.mixer) else { return };
        if self.gated {
            if mixer.lane().is_some_and(|lane| !lane.current().is_filled()) {
                self.mix_state = MixState::Waiting;
                return;
            }
            self.gated = false;
        }
        let mut buffered = out.written.saturating_sub(out.shared.read_frames());
        while buffered < out.target {
            let room = out.producer.slots() / 2;
            let n = ((out.target - buffered) as usize).min(self.block.len() / 2).min(room);
            if n == 0 {
                break;
            }
            let (made, state) = mixer.render(&mut self.block[..n * 2], &mut self.markers);
            self.mix_state = state;
            if !self.markers.is_empty() {
                self.shared.timeline.push(&self.markers);
                self.markers.clear();
            }
            if made == 0 {
                break;
            }
            if out.producer.push_entire_slice(&self.block[..made * 2]).is_err() {
                log::error!("the ring had less room than it said");
                break;
            }
            out.written += made as u64;
            buffered += made as u64;
            if made < n {
                break;
            }
        }
        out.shared.set_expect_sound(self.playing && self.mix_state == MixState::Playing);
        out.shared.set_mix_ended(self.mix_state == MixState::Ended);
        out.shared.set_blend_waiting(mixer.planned_fade_waiting());
    }

    // Turns what is heard into events, and notices buffering and the end.
    fn follow_heard(&mut self) {
        let Some(out) = &self.out else { return };
        let now = Instant::now();
        let heard = out.shared.clock.heard(now);
        let buffered = out.written.saturating_sub(out.shared.read_frames());
        let written = out.written;
        let rate = out.opened.rate() as u64;
        if let Some(frame) = heard {
            self.crossed.clear();
            self.shared.timeline.crossed(self.heard_frame, frame, &mut self.crossed);
            let crossed = std::mem::take(&mut self.crossed);
            for m in &crossed {
                if let Some(t) = m.transition {
                    self.on_transition(m.key, t, rate);
                }
            }
            self.crossed = crossed;
            self.heard_frame = self.heard_frame.max(frame);
        }

        // A live stream's new title, once the sound it starts with is heard.
        if let Some(key) = self.heard
            && let Some(lane) = self.mixer.as_ref().and_then(|m| m.lane())
            && lane.current().key() == key
            && lane.current().is_live()
            && let Some(i) = self.index_of(key)
        {
            let position = self.shared.position();
            let item_id = &self.queue[i].item.id;
            if position.item_id.as_ref() == Some(item_id)
                && let Some(meta) = lane.current().take_title(position.position_ms / 1_000.0)
            {
                self.emit(EngineEvent::StreamTitle {
                    item_id: item_id.clone(),
                    title: meta.title,
                    url: meta.url,
                });
            }
        }

        // Buffering: playing, but the ring has run dry waiting on a song.
        if self.playing && self.mixer.is_some() && !self.ended {
            let starved = self.mix_state == MixState::Waiting && buffered < rate / 200;
            if starved {
                let since = *self.starved_since.get_or_insert(now);
                if !self.buffering && now - since > STARVED_GRACE {
                    self.buffering = true;
                    let id = self.current_entry().map(|e| e.item.id.clone());
                    self.emit(EngineEvent::Buffering { item_id: id });
                    self.set_state(PlaybackState::Buffering);
                }
            } else {
                self.starved_since = None;
                if self.buffering && buffered > rate / 20 {
                    self.buffering = false;
                    let id = self.current_entry().map(|e| e.item.id.clone());
                    self.emit(EngineEvent::Ready { item_id: id });
                    self.set_state(PlaybackState::Playing);
                }
            }
        }

        // The end: everything mixed has been played out and heard.
        if !self.ended
            && self.mixer.is_some()
            && self.mix_state == MixState::Ended
            && buffered == 0
            && heard.is_none_or(|h| h >= written as f64 - 1.0)
        {
            self.on_end();
        }

        // Not for a song skipped away from while the next one opens: its
        // sound is gone, and the app took the word as the song going on
        // and went back to it. Through a join or a crossfade the song
        // heard is still playing out, and is told of as ever.
        let left = self.mix_state == MixState::Waiting && self.current_entry().map(|e| e.key) != self.heard;
        if self.playing
            && !left
            && !self.tick.is_zero()
            && now - self.last_tick >= self.tick
            && let Some(key) = self.heard
        {
            self.last_tick = now;
            // The place heard can already be the next song's start, held
            // there before that song is heard: it is not the heard song's.
            let position = self.shared.position();
            if let Some(i) = self.index_of(key)
                && position.item_id.as_deref() == Some(self.queue[i].item.id.as_str())
            {
                let id = self.queue[i].item.id.clone();
                self.emit(EngineEvent::Position { item_id: id, position_ms: position.position_ms });
            }
        }
    }

    fn id_of(&self, key: u64) -> Option<String> {
        self.index_of(key).map(|i| self.queue[i].item.id.clone())
    }

    fn emit_ended(&self, key: u64, reason: EndReason) {
        if let Some(id) = self.id_of(key) {
            self.emit(EngineEvent::TrackEnded { item_id: id, reason });
        }
    }

    fn on_transition(&mut self, key: u64, transition: Transition, rate: u64) {
        let previous = self.heard;
        match transition {
            Transition::Seek if previous == Some(key) => return,
            // A seek before the song was first heard (its start was never
            // heard, or never mixed) is where it starts being heard.
            Transition::Start | Transition::Seek => {
                if let Some(p) = previous {
                    self.emit_ended(p, self.end_reason);
                }
            }
            Transition::Gapless => {
                if let Some(p) = previous {
                    self.emit_ended(p, EndReason::Finished);
                    if let (Some(from), Some(to)) = (self.id_of(p), self.id_of(key)) {
                        self.emit(EngineEvent::GaplessTransition { from_id: from, to_id: to });
                    }
                }
            }
            Transition::Crossfade { from, frames } => {
                self.emit_ended(from, EndReason::Finished);
                if let (Some(from), Some(to)) = (self.id_of(from), self.id_of(key)) {
                    let speed = self.pace.speed as f64;
                    let duration_ms = (frames as f64 / rate as f64 / speed * 1_000.0) as u64;
                    self.emit(EngineEvent::CrossfadeStarted { from_id: from, to_id: to, duration_ms });
                }
            }
        }
        self.heard = Some(key);
        self.end_reason = EndReason::Skipped;
        if let Some(i) = self.index_of(key) {
            let info = self.infos.get(&key).cloned();
            let id = self.queue[i].item.id.clone();
            self.emit(EngineEvent::TrackStarted { item_id: id, index: i as u32, info });
        }
        self.publish_queue();
    }

    fn on_end(&mut self) {
        self.ended = true;
        if let Some(key) = self.heard.take() {
            self.emit_ended(key, EndReason::Finished);
        }
        if self.stop_after_current {
            // Pause at the end of the song, ready at the start of the next.
            self.stop_after_current = false;
            if let Some(next) = self.following(true) {
                self.current = Some(next);
                self.playing = false;
                self.start_current(0.0, Transition::Start, EndReason::Finished);
                return;
            }
        }
        self.playing = false;
        if let Some(out) = &self.out {
            out.shared.set_paused(true);
        }
        self.emit(EngineEvent::QueueEnded);
        self.set_state(PlaybackState::Ended);
    }

    // Opens the device if it is not open. False if there is none.
    fn ensure_output(&mut self) -> bool {
        if self.out.is_none() {
            self.open_output(true);
        }
        self.out.is_some()
    }

    // Opens the chosen device, or the default. `report` sends an error
    // when none opens; the quiet retries after a lost device leave it out.
    fn open_output(&mut self, report: bool) {
        let choice = self.device_choice.clone();
        let result = self.try_open(choice.as_deref());
        let result = match result {
            Err(e) if choice.is_some() => {
                log::warn!("could not open the chosen device ({e}); using the default");
                self.try_open(None)
            }
            other => other,
        };
        match result {
            Ok(()) => {
                let device = self.out.as_ref().map(|o| o.opened.device.clone());
                let format = self.out.as_ref().map(|o| o.opened.format.clone());
                let mut status = self.lock_status();
                status.device = device.clone();
                status.format = format.clone();
                drop(status);
                self.emit(EngineEvent::DeviceChanged { device, format });
            }
            Err(e) if report => {
                self.emit(EngineEvent::Error { kind: e.kind, message: e.message, item_id: None });
            }
            Err(e) => log::info!("still no sound device: {e}"),
        }
    }

    fn try_open(&mut self, id: Option<&str>) -> Result<(), crate::error::Failure> {
        let volume = if self.muted { 0.0 } else { self.volume };
        let paused = !self.playing;
        let mut made: Option<(rtrb::Producer<f32>, Arc<OutputShared>)> = None;
        let opened = self.driver.open(id, &mut |rate, channels| {
            let (producer, consumer) = ring((rate as f64 * RING_SECS) as usize);
            let shared = Arc::new(OutputShared::new(rate));
            shared.set_volume(volume);
            shared.set_paused(paused);
            made = Some((producer, shared.clone()));
            Renderer::new(consumer, shared, rate, channels)
        })?;
        let (producer, shared) = made.expect("renderer made on open");
        *self.shared.output.lock().unwrap_or_else(|e| e.into_inner()) = Some(shared.clone());
        let target = (opened.rate() as f64 * RING_TARGET_SECS) as u64;
        self.out = Some(Out { opened, shared, producer, written: 0, target });
        self.heard_frame = 0.0;
        self.device_running = true;
        self.silent_since = None;
        Ok(())
    }

    // Moves to another device (or the new default), carrying on from what
    // was heard; with no device open, since it was lost, from what was
    // heard last.
    fn reopen_output(&mut self, report: bool) {
        let heard = self.shared.timeline.at(self.shared.heard_frame()).or(self.lost_at);
        self.driver.close();
        self.out = None;
        *self.shared.output.lock().unwrap_or_else(|e| e.into_inner()) = None;
        self.open_output(report);
        if self.mixer.is_none() || self.ended {
            self.lost_at = None;
            return;
        }
        if self.out.is_none() {
            self.hold_place(heard);
            return;
        }
        self.lost_at = None;
        // The ring and its clock start over on the new device.
        self.shared.timeline.clear();
        self.mixer = None;
        let resume = heard.and_then(|m| self.index_of(m.key).map(|i| (i, m.secs)));
        if let Some((index, secs)) = resume {
            self.current = Some(index);
            self.start_current(secs, Transition::Seek, EndReason::Skipped);
        } else {
            self.start_current(0.0, Transition::Start, EndReason::Skipped);
        }
    }

    // With no device open: keeps where the song is, to carry on from there
    // once one opens, and shows it as the position meanwhile.
    fn hold_place(&mut self, moment: Option<Moment>) {
        self.lost_at = moment;
        self.shared.timeline.clear();
        if let Some(m) = moment {
            self.shared.timeline.hold(0, m);
        }
    }

    fn wake_device(&mut self) {
        if !self.device_running {
            self.driver.set_running(true);
            self.device_running = true;
        }
        self.silent_since = None;
    }

    fn check_device(&mut self) {
        let events = self.driver.take_events();
        for event in events {
            match event {
                DeviceEvent::Lost(why) => {
                    log::warn!("sound device lost: {why}");
                    self.reopen_output(true);
                }
                DeviceEvent::Rerouted => {
                    // The same stream, so the same format, on another device.
                    let device = self.driver.default_device();
                    let format = self.out.as_ref().map(|o| o.opened.format.clone());
                    self.lock_status().device = device.clone();
                    self.emit(EngineEvent::DeviceChanged { device, format });
                }
            }
        }
        let Some(out) = &self.out else {
            // Lost, and no device would open: try again now and then while
            // a song is meant to be playing, without a fresh error each time.
            if self.playing
                && self.mixer.is_some()
                && !self.ended
                && self.last_default_check.elapsed() > DEFAULT_DEVICE_CHECK
            {
                self.last_default_check = Instant::now();
                self.reopen_output(false);
            }
            return;
        };
        // Following the system default: move when it changes.
        if self.device_choice.is_none() && self.last_default_check.elapsed() > DEFAULT_DEVICE_CHECK {
            self.last_default_check = Instant::now();
            let current = out.opened.device.id.clone();
            if let Some(default) = self.driver.default_device()
                && !current.is_empty()
                && default.id != current
            {
                log::info!("default device is now {}", default.name);
                self.reopen_output(true);
                return;
            }
        }
        // A long pause lets the device sleep.
        let Some(out) = &self.out else { return };
        if !self.playing && out.shared.is_silent() {
            let since = *self.silent_since.get_or_insert(Instant::now());
            if self.device_running && since.elapsed() > IDLE_DEVICE_AFTER {
                self.driver.set_running(false);
                self.device_running = false;
            }
        } else {
            self.silent_since = None;
        }
    }

    fn lock_status(&self) -> MutexGuard<'_, Status> {
        self.shared.lock_status()
    }

    fn publish_queue(&self) {
        let queue: Vec<QueueEntryView> = self
            .queue
            .iter()
            .map(|e| QueueEntryView { key: e.key, id: e.item.id.clone(), duration_ms: e.item.duration_ms })
            .collect();
        let mut status = self.lock_status();
        status.queue = queue;
        status.heard = self.heard;
    }

    fn publish(&self) {
        let info = self.heard.and_then(|k| self.infos.get(&k).cloned());
        let mut status = self.lock_status();
        status.state = self.state;
        status.volume = self.volume;
        status.heard = self.heard;
        if status.info != info {
            status.info = info;
        }
        // Durations learned from the decoder.
        for (view, entry) in status.queue.iter_mut().zip(&self.queue) {
            if view.key == entry.key {
                view.duration_ms = entry.item.duration_ms;
            }
        }
    }

    fn shutdown(&mut self) {
        self.mixer = None;
        self.driver.close();
        self.out = None;
        *self.shared.output.lock().unwrap_or_else(|e| e.into_inner()) = None;
    }
}
