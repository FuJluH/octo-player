//! The engine as the app sees it, through the generated Kotlin bindings:
//! an `Engine` object, the records it takes and gives, and the events it
//! sends to a listener.

use std::sync::{Arc, Mutex};
use std::thread;

use crossbeam_channel::{Sender, bounded, unbounded};

use crate::automix::{AutomixSettings, SongProfile};
use crate::decode::TrackInfo;
use crate::error::{EngineError, ErrorKind};
use crate::output::cpal_driver::CpalDriver;
use crate::output::null::NullDriver;
use crate::output::{OutputDevice, OutputFormat};
use crate::pace::Pace;
use crate::player::{Command, Driven, Shared};
use crate::sound::model::{DspSettings, EqPreset, EqSettings, ReplayGainSettings};
use crate::sound::replaygain::ReplayGainInfo;

/// An extra request header for a stream, such as one a server's proxy needs.
#[derive(Clone, Debug, PartialEq, Eq, uniffi::Record)]
pub struct HttpHeader {
    pub name: String,
    pub value: String,
}

/// A certificate the listener chose to trust for one host, although the
/// system does not (a server's own self-signed one, say).
#[derive(Clone, Debug, PartialEq, Eq, uniffi::Record)]
pub struct TrustedCertificate {
    /// The host's name or address, in any case.
    pub host: String,
    /// The SHA-256 of the certificate itself, in hex; colons and spaces are ignored.
    pub sha256: String,
}

/// One entry in the play queue.
#[derive(Clone, Debug, PartialEq, uniffi::Record)]
pub struct QueueItem {
    /// The app's own id for this entry, handed back in events.
    pub id: String,
    /// A file path, a `file://` address, a signed HTTP(S) stream address,
    /// or an HLS playlist's address.
    pub source: String,
    /// The album, for keeping albums gapless and for Smart ReplayGain.
    #[uniffi(default)]
    pub album_id: Option<String>,
    /// Where the song sits in its album (disc and track in one number),
    /// for telling an album played in order.
    #[uniffi(default)]
    pub album_order: Option<i32>,
    /// The library's length, used until the file says.
    #[uniffi(default)]
    pub duration_ms: Option<u64>,
    /// Loudness values the source keeps, for streams that lose their tags.
    #[uniffi(default)]
    pub replay_gain: Option<ReplayGainInfo>,
    #[uniffi(default)]
    pub headers: Vec<HttpHeader>,
    /// The song's genre; some genres are never mixed into the next song.
    #[uniffi(default)]
    pub genre: Option<String>,
    /// The song's tempo from its tags, which settles whether a beat found in
    /// it runs at double or half time.
    #[uniffi(default)]
    pub bpm: Option<f64>,
    /// A live stream, such as live radio: it has no length and cannot be
    /// sought, a dropped connection is made again, and its titles arrive as
    /// `StreamTitle` events.
    #[uniffi(default)]
    pub live: bool,
    /// The source is an HLS playlist even though its address and its
    /// server's content type do not say so.
    #[uniffi(default)]
    pub hls: bool,
}

/// What happens at the end of the queue or the song.
#[derive(Clone, Copy, Debug, PartialEq, Eq, uniffi::Enum)]
pub enum RepeatMode {
    Off,
    /// The current song again and again.
    One,
    /// Back to the start of the queue after the last song.
    All,
}

#[derive(Clone, Copy, Debug, PartialEq, Eq, uniffi::Enum)]
pub enum PlaybackState {
    /// Nothing loaded.
    Idle,
    /// Waiting for sound: opening a song or the network.
    Buffering,
    Playing,
    Paused,
    /// The queue played to its end.
    Ended,
}

/// Why a song stopped sounding.
#[derive(Clone, Copy, Debug, PartialEq, Eq, uniffi::Enum)]
pub enum EndReason {
    /// It played to its end.
    Finished,
    /// The listener moved to another song, or loaded a new queue.
    Skipped,
    /// It could not be played on.
    Failed,
    Stopped,
}

/// Where playback is, from the audio clock.
#[derive(Clone, Debug, PartialEq, uniffi::Record)]
pub struct PlaybackPosition {
    pub item_id: Option<String>,
    pub index: Option<u32>,
    /// Milliseconds into the song, with a fraction, for word-by-word lyrics.
    pub position_ms: f64,
    pub duration_ms: Option<u64>,
}

/// The queue as the engine holds it.
#[derive(Clone, Debug, PartialEq, uniffi::Record)]
pub struct QueueSnapshot {
    pub item_ids: Vec<String>,
    /// The entry being heard.
    pub current_index: Option<u32>,
}

/// Something the app may want to know, sent to the listener in order.
#[derive(Clone, Debug, PartialEq, uniffi::Enum)]
pub enum EngineEvent {
    /// A song began to be heard.
    TrackStarted {
        item_id: String,
        index: u32,
        info: Option<TrackInfo>,
    },
    TrackEnded {
        item_id: String,
        reason: EndReason,
    },
    /// One song ran into the next with no gap.
    GaplessTransition {
        from_id: String,
        to_id: String,
    },
    CrossfadeStarted {
        from_id: String,
        to_id: String,
        duration_ms: u64,
    },
    /// Sound stopped for lack of data.
    Buffering {
        item_id: Option<String>,
    },
    /// Sound is flowing again.
    Ready {
        item_id: Option<String>,
    },
    StateChanged {
        state: PlaybackState,
    },
    /// The last song finished and nothing follows.
    QueueEnded,
    Error {
        kind: ErrorKind,
        message: String,
        item_id: Option<String>,
    },
    /// Output moved to another device, or the device list changed under it.
    /// `format` is what the device's stream runs at.
    DeviceChanged {
        device: Option<OutputDevice>,
        format: Option<OutputFormat>,
    },
    /// Sent at the interval asked for with `set_position_interval`.
    Position {
        item_id: String,
        position_ms: f64,
    },
    /// A live stream's title changed, as it is heard: usually "Artist -
    /// Song" for what the station plays now, as the station sent it. An
    /// empty title says the stream no longer names what it plays. `url` is
    /// the address sent with it (`StreamArtwork`, else `StreamUrl`), empty
    /// when there is none.
    StreamTitle {
        item_id: String,
        title: String,
        url: String,
    },
    /// How the next song will follow the playing one, decided ahead of
    /// time. `start_ms` is when in `from_id` the blend starts (its length
    /// for a gapless join), `entry_ms` where `to_id` comes in, and
    /// `overlap_ms` how long both sound, 0 for a gapless join. `reason` is a
    /// line for the log, starting `automix:`.
    TransitionPlanned {
        from_id: String,
        to_id: String,
        start_ms: u64,
        entry_ms: u64,
        overlap_ms: u64,
        reason: String,
    },
}

/// Receives the engine's events, on the engine's own event thread.
#[uniffi::export(with_foreign)]
pub trait EngineListener: Send + Sync {
    fn on_event(&self, event: EngineEvent);
}

/// The audio engine. One per app; every call returns at once and the work
/// happens on the engine's own threads.
#[derive(uniffi::Object)]
pub struct Engine {
    commands: Sender<Command>,
    shared: Arc<Shared>,
    player: Mutex<Option<thread::JoinHandle<()>>>,
    events: Mutex<Option<thread::JoinHandle<()>>>,
}

#[uniffi::export]
impl Engine {
    /// An engine playing to the system's sound devices.
    #[uniffi::constructor]
    pub fn new() -> Arc<Self> {
        Self::with_driver(Box::new(|| Box::new(CpalDriver::new())))
    }

    /// An engine with no sound device, for tests and headless machines.
    #[uniffi::constructor]
    pub fn new_silent() -> Arc<Self> {
        Self::with_driver(Box::new(|| Box::new(NullDriver::new(48_000, 2))))
    }

    /// Sets who hears the events. Replaces any earlier listener.
    pub fn set_listener(&self, listener: Arc<dyn EngineListener>) {
        *self.shared.listener.lock().unwrap_or_else(|e| e.into_inner()) = Some(listener);
    }

    /// Replaces the queue and starts at `start_index`, `start_ms` in.
    pub fn load(
        &self,
        items: Vec<QueueItem>,
        start_index: u32,
        start_ms: u64,
        play: bool,
    ) -> Result<(), EngineError> {
        if !items.is_empty() && start_index as usize >= items.len() {
            return Err(invalid("start index past the end of the queue"));
        }
        self.send(Command::Load { items, start_index: start_index as usize, start_ms, play })
    }

    /// Puts songs right after the one playing.
    pub fn play_next(&self, items: Vec<QueueItem>) -> Result<(), EngineError> {
        self.send(Command::PlayNext(items))
    }

    /// Adds songs at the end of the queue.
    pub fn enqueue(&self, items: Vec<QueueItem>) -> Result<(), EngineError> {
        self.send(Command::Enqueue(items))
    }

    /// Replaces everything after the playing song, which carries on
    /// untouched. The songs before it stay as they are, so a new shuffle
    /// or order that moves them belongs in `replace_queue`.
    pub fn replace_upcoming(&self, items: Vec<QueueItem>) -> Result<(), EngineError> {
        self.send(Command::ReplaceUpcoming(items))
    }

    /// Replaces the whole queue, in the order it plays, around the playing
    /// song, which carries on untouched. The playing song is found in
    /// `items` by its id, and `current` is its place when it is not there.
    /// Songs already queued keep what the engine has for them, so the next
    /// one stays lined up for a gapless join or a crossfade. For shuffling,
    /// reordering and every other change to the queue.
    pub fn replace_queue(&self, items: Vec<QueueItem>, current: u32) -> Result<(), EngineError> {
        if !items.is_empty() && current as usize >= items.len() {
            return Err(invalid("current index past the end of the queue"));
        }
        self.send(Command::ReplaceQueue { items, current: current as usize })
    }

    pub fn skip_to(&self, index: u32) -> Result<(), EngineError> {
        self.send(Command::SkipTo(index as usize))
    }

    pub fn skip_next(&self) -> Result<(), EngineError> {
        self.send(Command::SkipNext)
    }

    pub fn play(&self) -> Result<(), EngineError> {
        self.send(Command::Play)
    }

    /// Pauses with a short fade, so it never clicks.
    pub fn pause(&self) -> Result<(), EngineError> {
        self.send(Command::Pause)
    }

    /// Stops and forgets the position; the queue stays.
    pub fn stop(&self) -> Result<(), EngineError> {
        self.send(Command::Stop)
    }

    pub fn seek(&self, position_ms: u64) -> Result<(), EngineError> {
        self.send(Command::Seek(position_ms))
    }

    /// The volume as a factor from 0 to 1.
    pub fn set_volume(&self, linear: f32) -> Result<(), EngineError> {
        if !linear.is_finite() {
            return Err(invalid("volume must be a number"));
        }
        self.send(Command::SetVolume(linear.clamp(0.0, 1.0)))
    }

    /// The volume in decibels, 0 at most.
    pub fn set_volume_db(&self, db: f32) -> Result<(), EngineError> {
        if db.is_nan() {
            return Err(invalid("volume must be a number"));
        }
        self.set_volume(10f32.powf(db.min(0.0) / 20.0))
    }

    pub fn volume(&self) -> f32 {
        self.shared.status().volume
    }

    pub fn set_muted(&self, muted: bool) -> Result<(), EngineError> {
        self.send(Command::SetMuted(muted))
    }

    /// Crossfade length in milliseconds, 0 to 16000; 0 turns it off.
    pub fn set_crossfade(&self, ms: u32) -> Result<(), EngineError> {
        self.send(Command::SetCrossfade(ms.min(crate::crossfade::LONGEST_FADE_MS)))
    }

    /// How crossfades are chosen and shaped: smart transitions, filter
    /// sweeps, tempo matching and the longest blend. Applies from the next
    /// transition on. Smart transitions are off until this is called.
    pub fn set_automix(&self, settings: AutomixSettings) -> Result<(), EngineError> {
        let max_overlap_ms = settings.max_overlap_ms.min(crate::crossfade::LONGEST_FADE_MS);
        self.send(Command::SetAutomix(AutomixSettings { max_overlap_ms, ..settings }))
    }

    /// The transition profile of the song queued as `item_id`, from its
    /// server, or `None` to forget it. With one, that song's start and end
    /// are planned from it instead of being read from the stream.
    pub fn set_song_profile(&self, item_id: String, profile: Option<SongProfile>) -> Result<(), EngineError> {
        let profile = match profile {
            None => None,
            Some(p) => Some(Arc::new(
                p.to_profile().ok_or_else(|| invalid("a profile without its levels or length"))?,
            )),
        };
        self.send(Command::SetProfile { item_id, profile })
    }

    pub fn set_eq(&self, eq: EqSettings) -> Result<(), EngineError> {
        self.send(Command::SetEq(eq))
    }

    pub fn set_replaygain(&self, settings: ReplayGainSettings) -> Result<(), EngineError> {
        self.send(Command::SetReplayGain(settings))
    }

    pub fn set_dsp(&self, dsp: DspSettings) -> Result<(), EngineError> {
        self.send(Command::SetDsp(dsp))
    }

    /// Speed from 0.5 to 2, keeping the pitch. `pitch` moves the pitch on
    /// top, as a factor (1 for none; the speed itself for record-style).
    pub fn set_speed(&self, speed: f32, pitch: f32) -> Result<(), EngineError> {
        self.send(Command::SetPace(Pace::clamped(speed, pitch)))
    }

    pub fn set_repeat(&self, mode: RepeatMode) -> Result<(), EngineError> {
        self.send(Command::SetRepeat(mode))
    }

    /// Pauses when the playing song ends, once.
    pub fn set_stop_after_current(&self, on: bool) -> Result<(), EngineError> {
        self.send(Command::SetStopAfterCurrent(on))
    }

    /// How much of a stream to have ready before a song starts, in
    /// milliseconds (at most a minute); 0 starts as soon as there is sound.
    /// Files start at once. Applies from the next song started.
    pub fn set_start_after(&self, ms: u32) -> Result<(), EngineError> {
        self.send(Command::SetStartAfter(ms.min(60_000)))
    }

    /// Plays to device `id` from `devices()`, or follows the system's
    /// default device with `None`.
    pub fn set_output_device(&self, id: Option<String>) -> Result<(), EngineError> {
        self.send(Command::SetOutputDevice(id))
    }

    /// The sound devices there are now.
    pub fn devices(&self) -> Vec<OutputDevice> {
        let (reply, answer) = bounded(1);
        if self.send(Command::Devices(reply)).is_err() {
            return Vec::new();
        }
        answer.recv_timeout(std::time::Duration::from_secs(5)).unwrap_or_default()
    }

    /// The device playing now.
    pub fn current_device(&self) -> Option<OutputDevice> {
        self.shared.status().device
    }

    /// What the device playing now runs at: its rate, channels and samples.
    pub fn output_format(&self) -> Option<OutputFormat> {
        self.shared.status().format
    }

    /// Where playback is, from the audio clock.
    pub fn position(&self) -> PlaybackPosition {
        self.shared.position()
    }

    pub fn state(&self) -> PlaybackState {
        self.shared.status().state
    }

    pub fn queue(&self) -> QueueSnapshot {
        self.shared.queue()
    }

    /// What the decoder found out about the song being heard.
    pub fn now_playing(&self) -> Option<TrackInfo> {
        self.shared.status().info
    }

    /// How many times the device ran out of sound while playing, since the
    /// device was opened. Above zero means audible gaps.
    pub fn underruns(&self) -> u64 {
        self.shared.underruns()
    }

    /// Replaces the certificates trusted for streams. A server's certificate
    /// is checked the system's way first; only when that fails is it let
    /// through, and only when its host has a pin equal to its SHA-256.
    /// Applies to connections made from now on.
    pub fn set_trusted_certificates(&self, certificates: Vec<TrustedCertificate>) {
        self.shared.trust.replace(certificates.into_iter().map(|c| (c.host, c.sha256)));
    }

    /// Sends a `Position` event every `ms` while playing; 0 turns it off.
    pub fn set_position_interval(&self, ms: u32) -> Result<(), EngineError> {
        self.send(Command::SetPositionInterval(ms))
    }

    /// Stops the engine's threads. The engine does nothing after this.
    pub fn shutdown(&self) {
        let _ = self.commands.send(Command::Shutdown);
        self.shared.wake();
        if let Some(h) = self.player.lock().unwrap_or_else(|e| e.into_inner()).take() {
            let _ = h.join();
        }
        // The event thread ends once the player is gone; it is not waited
        // for when this is called from a listener, which runs on it.
        let events = self.events.lock().unwrap_or_else(|e| e.into_inner()).take();
        if let Some(h) = events
            && h.thread().id() != thread::current().id()
        {
            let _ = h.join();
        }
    }
}

impl Engine {
    /// An engine with a chosen way to reach devices. The driver is made on
    /// the engine's thread, since device streams may not move between threads.
    pub fn with_driver(make_driver: Box<dyn FnOnce() -> Box<dyn crate::output::Driver> + Send>) -> Arc<Self> {
        let (commands, command_rx) = unbounded();
        let (event_tx, event_rx) = unbounded::<EngineEvent>();
        let shared = Arc::new(Shared::new());
        let events_shared = shared.clone();
        let events = thread::Builder::new()
            .name("octo-events".into())
            .spawn(move || {
                // Calls into the app happen here, never on the audio path.
                for event in event_rx {
                    let listener = events_shared.listener.lock().unwrap_or_else(|e| e.into_inner()).clone();
                    if let Some(listener) = listener {
                        listener.on_event(event);
                    }
                }
            })
            .expect("event thread");
        let player_shared = shared.clone();
        let player = thread::Builder::new()
            .name("octo-player".into())
            .spawn(move || {
                let driver = make_driver();
                crate::player::run(Driven {
                    driver,
                    commands: command_rx,
                    events: event_tx,
                    shared: player_shared,
                });
            })
            .expect("player thread");
        shared.set_player_thread(player.thread().clone());
        Arc::new(Engine {
            commands,
            shared,
            player: Mutex::new(Some(player)),
            events: Mutex::new(Some(events)),
        })
    }

    /// Where playback is at `now` by the audio clock.
    #[cfg(test)]
    pub fn position_at(&self, now: std::time::Instant) -> PlaybackPosition {
        self.shared.position_at(now)
    }

    /// Plans this engine's transitions with `planner` instead of the real
    /// planner. Other engines are not touched.
    #[cfg(test)]
    pub fn set_test_planner(&self, planner: Option<crate::automix::Planner>) {
        *self.shared.planner.lock().unwrap_or_else(|e| e.into_inner()) = planner;
    }

    fn send(&self, command: Command) -> Result<(), EngineError> {
        self.commands.send(command).map_err(|_| EngineError::Failed {
            kind: ErrorKind::Other,
            detail: "the engine has shut down".into(),
        })?;
        self.shared.wake();
        Ok(())
    }
}

impl Drop for Engine {
    fn drop(&mut self) {
        self.shutdown();
    }
}

fn invalid(message: &str) -> EngineError {
    EngineError::Failed { kind: ErrorKind::InvalidArgument, detail: message.into() }
}

/// The built-in equalizer curves, the same as the Android app's.
#[uniffi::export]
pub fn equalizer_presets() -> Vec<EqPreset> {
    crate::sound::model::eq_presets()
}

/// The ten graphic equalizer band frequencies, in hertz.
#[uniffi::export]
pub fn graphic_bands() -> Vec<f32> {
    crate::sound::model::GRAPHIC_BANDS.to_vec()
}
