//! Mixes what the listener hears: the playing lane, a second lane during a
//! crossfade, then speed and pitch, then the sound shaping. It also notes
//! which song and which moment of it each output frame holds, for the clock.
//!
//! A crossfade follows a shape: the gain curve, filters swept over each song
//! while both sound, and a rate for the incoming song that eases back to
//! normal after the blend. Outside a blend none of these touch the sound.

use std::collections::VecDeque;

use crate::automix::{
    BEAT_MATCH_SETTLE_MS, Biquad, FadeCurve, LiveAnalysis, LiveAnalyzer, RATE_RANGE, beat_match_rate_at,
    blend_gains, incoming_high_pass_hz, outgoing_high_pass_hz, outgoing_low_pass_hz,
    stepped_outgoing_low_pass_hz,
};
use crate::deck::Deck;
use crate::error::Failure;
use crate::fifo::Fifo;
use crate::lane::{Lane, LaneState, Span};
use crate::pace::{Pace, PaceStage, Stretch};
use crate::scout::PcmSink;
use crate::sound::biquad::FilterBank;
use crate::sound::model::SoundSettings;
use crate::sound::replaygain::Loudness;
use crate::sound::shaper::SoundShaper;

/// Frames mixed per step: about 5 ms.
const BLOCK: usize = 256;

/// Frames between filter moves during a sweep, short enough that the
/// moves are not heard as steps.
const SWEEP_STEP: usize = 32;

/// How long the outgoing song must stay under the silence gate before its
/// fade is finished early, and how quickly it then finishes.
const QUIET_SECS: f64 = 0.3;
const RUSH_SECS: f64 = 0.25;

/// How long the incoming song's high-pass takes to hand over to the dry
/// sound once a blend ends, in seconds. Taking it off at once would step the
/// waveform by the filter's phase shift: a click on bass notes.
const RELEASE_SECS: f64 = 0.01;

/// How long the sweeps take to come in from the dry sound at a blend's
/// start, in seconds. The filters start from rest, so switching them in at
/// once would step the outgoing song's waveform: a click.
const ENGAGE_SECS: f64 = 0.01;

/// How long a blend ended on demand takes to finish, in seconds.
const FINISH_SECS: f64 = 0.01;

/// How far into and out of a blend the headroom takes to come and go, as
/// a share of the blend.
const HEADROOM_RAMP: f64 = 0.1;

/// What began at a point in the output.
#[derive(Clone, Copy, Debug, PartialEq)]
pub enum Transition {
    /// A song started on its own: the first one, after a skip, or a load.
    Start,
    /// A song followed the one before it with no gap.
    Gapless,
    /// A song began fading in over the one before it.
    Crossfade { from: u64, frames: u64 },
    /// The same song carries on from another place.
    Seek,
}

/// Output frame `frame` holds second `secs` of song `key`; later frames
/// move on by `secs_per_frame` each until the next marker.
#[derive(Clone, Copy, Debug, PartialEq)]
pub struct Marker {
    pub frame: u64,
    pub key: u64,
    pub secs: f64,
    pub secs_per_frame: f64,
    pub transition: Option<Transition>,
}

/// Where mixing stands after a render.
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum MixState {
    Playing,
    /// Waiting on a song: opening, the network, or the next one.
    Waiting,
    /// Everything has played out.
    Ended,
}

/// The outgoing song's low-pass stepping on the beat rather than sweeping
/// smoothly: `beats` are the beats inside the blend as progress from 0 to 1,
/// and `glide` how long, in the same units, the cutoff takes to move to each
/// beat's value (see `automix::stepped_outgoing_low_pass_hz`).
#[derive(Clone, Debug, Default, PartialEq)]
pub struct LowPassSteps {
    pub beats: Vec<f64>,
    pub glide: f64,
}

/// How a crossfade sounds. The default is the plain equal-power crossfade.
#[derive(Clone, Debug, Default, PartialEq)]
pub struct FadeShape {
    /// Gain curve weight: 0 is equal power (see `automix::gains`).
    pub k: f64,
    /// The fixed crossfade's shape; equal power follows `k` (see
    /// `automix::blend_gains`).
    pub curve: FadeCurve,
    /// How deep the filter sweeps go, 0 for none.
    pub filter_strength: f64,
    /// Steps for the outgoing low-pass; `None` sweeps it smoothly.
    pub steps: Option<LowPassSteps>,
    /// The incoming song's rate through the blend, eased back to 1 after.
    pub rate: Option<f64>,
    /// When the outgoing song stays below this level (dBFS) for 0.3 s
    /// during the blend, the blend finishes early.
    pub silence_gate_db: Option<f32>,
    /// Lowers both songs by this many dB through the blend, coming and going
    /// over its first and last tenth, so the sum keeps clear of clipping.
    pub headroom_db: f32,
}

// The song and moment at a mix frame, before speed changes. The song moves
// on `speed` seconds of its own per second of mix.
#[derive(Clone, Copy, Debug)]
struct MixMark {
    frame: u64,
    key: u64,
    secs: f64,
    speed: f64,
    transition: Option<Transition>,
}

// A crossfade lined up to start at a moment of the current song.
struct PlannedFade {
    key: u64,
    at_secs: f64,
    frames: u64,
    deck: Deck,
    loudness: Loudness,
    shape: FadeShape,
}

struct Fade {
    outgoing: Outgoing,
    frames: u64,
    done: u64,
    clock: FadeClock,
    k: f64,
    curve: FadeCurve,
    // The blend's length in milliseconds of output, for curves with edges
    // of a fixed length.
    overlap_ms: f64,
    sweeps: Option<Sweeps>,
    // Mean square under which the outgoing song counts as silent.
    gate: Option<f32>,
    quiet: u64,
    headroom_db: f32,
}

// The song fading out: its lane, through the rate stage it still had when
// its own blend began, so a song whose tempo was matched carries on easing
// back to normal instead of jumping.
struct Outgoing {
    lane: Lane,
    rated: Option<Rated>,
}

impl Outgoing {
    fn fill(&mut self, n: usize) -> LaneState {
        match &mut self.rated {
            Some(rated) => rated.fill(&mut self.lane, n),
            None => self.lane.fill(n),
        }
    }

    fn available(&self) -> usize {
        self.rated.as_ref().map_or_else(|| self.lane.available(), Rated::available)
    }

    fn pull(&mut self, out: &mut [f32], spans: &mut Vec<Span>) -> usize {
        let Some(rated) = &mut self.rated else { return self.lane.pull(out, spans) };
        let n = (out.len() / 2).min(rated.available());
        let got = rated.out.pop_into(&mut out[..n * 2]) / 2;
        rated.advance(got);
        if rated.is_done() {
            self.rated = None;
        }
        got
    }

    fn is_ended(&self) -> bool {
        self.lane.is_ended()
            && self.rated.as_ref().is_none_or(|r| r.available() == 0 && r.stretch.pending() == 0)
    }
}

// Where a blend is at, as progress from 0 to 1, by frames done. Finishing
// early moves the rest of the way over a short stretch from where it was.
#[derive(Clone, Copy, Debug)]
struct FadeClock {
    frames: u64,
    // From `done`, at progress `from`, the rest of the way over `len` frames.
    rush: Option<(u64, f64, u64)>,
}

impl FadeClock {
    fn progress(&self, done: u64) -> f64 {
        match self.rush {
            Some((at, from, len)) => {
                from + (1.0 - from) * (done.saturating_sub(at) as f64 / len.max(1) as f64).min(1.0)
            }
            None => done as f64 / self.frames.max(1) as f64,
        }
    }

    fn end(&self) -> u64 {
        match self.rush {
            Some((at, _, len)) => at + len,
            None => self.frames,
        }
    }
}

// Lowers a blend by `db` at progress `p`, coming in and going out smoothly.
fn headroom(db: f32, p: f64) -> f64 {
    let w = (p / HEADROOM_RAMP).min((1.0 - p) / HEADROOM_RAMP).clamp(0.0, 1.0);
    10f64.powf(-db as f64 * w / 20.0)
}

// Follows the playing song's sound as it is mixed, before the sound
// shaping and with its ReplayGain taken back out, for the planner.
struct LiveTap {
    key: Option<u64>,
    analyzer: LiveAnalyzer,
    mono: Vec<f32>,
}

impl LiveTap {
    fn feed(&mut self, key: u64, start_secs: f64, rate: u32, stereo: &[f32], gain: f32) {
        if self.key != Some(key) {
            self.key = Some(key);
            self.analyzer = LiveAnalyzer::new();
            self.analyzer.begin(start_secs, rate);
        }
        let undo = if gain > 0.0 { 0.5 / gain } else { 0.5 };
        self.mono.clear();
        self.mono.extend(stereo.chunks_exact(2).map(|f| (f[0] + f[1]) * undo));
        self.analyzer.pcm(&self.mono);
    }
}

// Filters swept over both songs through a blend: a low-pass and a
// high-pass closing in on the outgoing song, and a high-pass opening up on
// the incoming one. They move every `SWEEP_STEP` frames. Over the first
// `engage` frames each song moves from its dry sound to its filtered one.
struct Sweeps {
    rate: u32,
    strength: f64,
    steps: Option<LowPassSteps>,
    outgoing: FilterBank,
    incoming: FilterBank,
    engaged: usize,
    engage: usize,
    dry_out: Vec<f32>,
    dry_in: Vec<f32>,
}

impl Sweeps {
    fn new(rate: u32, strength: f64, steps: Option<LowPassSteps>) -> Self {
        let mut sweeps = Sweeps {
            rate,
            strength,
            steps,
            outgoing: FilterBank::new(2, vec![Biquad::low_pass(rate, 18_000.0).coefficients(); 2]),
            incoming: FilterBank::new(2, vec![Biquad::high_pass(rate, 20.0).coefficients()]),
            engaged: 0,
            engage: ((ENGAGE_SECS * rate as f64) as usize).max(1),
            dry_out: vec![0.0; SWEEP_STEP * 2],
            dry_in: vec![0.0; SWEEP_STEP * 2],
        };
        sweeps.tune(0.0);
        sweeps
    }

    fn tune(&mut self, t: f64) {
        let s = self.strength;
        let low = match &self.steps {
            None => outgoing_low_pass_hz(t, s),
            Some(steps) => stepped_outgoing_low_pass_hz(t, s, &steps.beats, steps.glide),
        };
        self.outgoing.set(0, Biquad::low_pass(self.rate, low).coefficients());
        self.outgoing.set(1, Biquad::high_pass(self.rate, outgoing_high_pass_hz(t, s)).coefficients());
        self.incoming.set(0, Biquad::high_pass(self.rate, incoming_high_pass_hz(t, s)).coefficients());
    }

    // Filters `frames` frames of each song, `done` frames into a blend
    // whose progress at a frame is `progress`.
    fn run(
        &mut self,
        outgoing: &mut [f32],
        incoming: &mut [f32],
        frames: usize,
        done: u64,
        progress: impl Fn(u64) -> f64,
    ) {
        let mut at = 0;
        while at < frames {
            let n = SWEEP_STEP.min(frames - at);
            self.tune(progress(done + at as u64));
            let engaging = self.engaged < self.engage;
            if engaging {
                self.dry_out[..n * 2].copy_from_slice(&outgoing[at * 2..(at + n) * 2]);
                self.dry_in[..n * 2].copy_from_slice(&incoming[at * 2..(at + n) * 2]);
            }
            self.outgoing.process(&mut outgoing[at * 2..], n);
            self.incoming.process(&mut incoming[at * 2..], n);
            if engaging {
                for i in 0..n {
                    let wet = ((self.engaged + i + 1) as f32 / self.engage as f32).min(1.0);
                    for ch in 0..2 {
                        let (j, k) = (i * 2 + ch, (at + i) * 2 + ch);
                        outgoing[k] = self.dry_out[j] + (outgoing[k] - self.dry_out[j]) * wet;
                        incoming[k] = self.dry_in[j] + (incoming[k] - self.dry_in[j]) * wet;
                    }
                }
                self.engaged += n;
            }
            at += n;
        }
    }
}

// The incoming song played at another rate, pitch kept, to line its tempo
// up with the outgoing one: held through the blend, then eased back to
// normal (`automix::beat_match_rate_at`), after which it passes straight
// through and is dropped.
struct Rated {
    key: u64,
    out_rate: u32,
    from: f64,
    hold: u64,
    ease: u64,
    done: u64,
    stretch: Stretch,
    out: Fifo,
    scratch: Vec<f32>,
    spans: Vec<Span>,
    // Song time just after the last frame taken from the lane.
    in_end_secs: f64,
}

impl Rated {
    fn new(key: u64, out_rate: u32, rate: f64, hold: u64) -> Self {
        let from = rate.clamp(1.0 - RATE_RANGE, 1.0 + RATE_RANGE);
        Rated {
            key,
            out_rate,
            from,
            hold,
            ease: (BEAT_MATCH_SETTLE_MS / 1_000.0 * out_rate as f64) as u64,
            done: 0,
            stretch: Stretch::new(out_rate, 2, from),
            out: Fifo::with_capacity(BLOCK * 32),
            scratch: vec![0.0; BLOCK * 2],
            spans: Vec::new(),
            in_end_secs: 0.0,
        }
    }

    fn rate_at(&self, done: u64) -> f64 {
        let ms = |frames: u64| frames as f64 * 1_000.0 / self.out_rate as f64;
        beat_match_rate_at(self.from, ms(done), ms(self.hold))
    }

    fn available(&self) -> usize {
        self.out.len() / 2
    }

    // Takes from the lane until `wanted` frames are ready, or the lane has
    // no more for now. Only what is missing is taken, so once the rate is
    // back to normal the stage empties and can be dropped.
    fn fill(&mut self, lane: &mut Lane, wanted: usize) -> LaneState {
        while self.available() < wanted {
            let need = (wanted - self.available()).min(BLOCK);
            let state = lane.fill(need);
            let n = lane.available().min(need);
            if n == 0 {
                if state == LaneState::Ended {
                    self.stretch.flush(&mut self.out);
                    if self.available() > 0 {
                        return LaneState::Ready;
                    }
                }
                return state;
            }
            lane.pull(&mut self.scratch[..n * 2], &mut self.spans);
            if let Some(last) = self.spans.last() {
                self.in_end_secs = last.start_secs + last.frames as f64 / self.out_rate as f64;
            }
            self.stretch.process(&self.scratch[..n * 2], &mut self.out);
        }
        LaneState::Ready
    }

    // The song time of the next frame to come out.
    fn head_secs(&self) -> f64 {
        let held = self.stretch.pending() as f64 + self.available() as f64 * self.stretch.rate();
        self.in_end_secs - held / self.out_rate as f64
    }

    fn advance(&mut self, frames: usize) {
        self.done += frames as u64;
        self.stretch.set_rate(self.rate_at(self.done));
    }

    fn is_done(&self) -> bool {
        self.done >= self.hold + self.ease && self.out.is_empty() && self.stretch.pending() == 0
    }
}

// The incoming song's filter after a swept blend, faded out from wet to dry
// over `len` frames.
struct Release {
    filter: FilterBank,
    done: usize,
    len: usize,
}

pub struct Mixer {
    rate: u32,
    lane: Option<Lane>,
    fade: Option<Fade>,
    release: Option<Release>,
    planned: Option<PlannedFade>,
    rated: Option<Rated>,
    tap: LiveTap,
    pace: PaceStage,
    shaper: SoundShaper,
    settings: SoundSettings,
    song_gain: f32,
    a: Vec<f32>,
    b: Vec<f32>,
    block: Vec<f32>,
    spans: Vec<Span>,
    spans_b: Vec<Span>,
    // Mix frames pushed on to the speed stage, and marks for them.
    mixed: u64,
    marks: VecDeque<MixMark>,
    next_transition: Option<Transition>,
    // Output frames made before the shaper's delay.
    made: u64,
    // Output frame numbering starts here.
    base: u64,
    tail_left: usize,
    failures: Vec<(u64, Failure)>,
    last_marker: Option<Marker>,
    // Whether two songs sounded together in what was mixed since the last
    // block went to the shaper.
    blended: bool,
}

impl Mixer {
    /// A mixer at output `rate`, numbering its frames from `base`.
    pub fn new(rate: u32, base: u64, settings: &SoundSettings, pace: Pace) -> Self {
        let mut shaper = SoundShaper::new(rate, 2);
        shaper.apply(settings, 1.0, true);
        let mut stage = PaceStage::new(rate, 2);
        stage.set(pace);
        Mixer {
            rate,
            lane: None,
            fade: None,
            release: None,
            planned: None,
            rated: None,
            tap: LiveTap { key: None, analyzer: LiveAnalyzer::new(), mono: Vec::with_capacity(BLOCK) },
            pace: stage,
            shaper,
            settings: settings.clone(),
            song_gain: 1.0,
            a: vec![0.0; BLOCK * 2],
            b: vec![0.0; BLOCK * 2],
            block: vec![0.0; BLOCK * 2],
            spans: Vec::new(),
            spans_b: Vec::new(),
            mixed: 0,
            marks: VecDeque::new(),
            next_transition: Some(Transition::Start),
            made: 0,
            base,
            tail_left: 0,
            failures: Vec::new(),
            last_marker: None,
            blended: false,
        }
    }

    pub fn rate(&self) -> u32 {
        self.rate
    }

    pub fn lane(&self) -> Option<&Lane> {
        self.lane.as_ref()
    }

    pub fn lane_mut(&mut self) -> Option<&mut Lane> {
        self.lane.as_mut()
    }

    pub fn is_fading(&self) -> bool {
        self.fade.is_some()
    }

    pub fn has_planned_fade(&self) -> bool {
        self.planned.is_some()
    }

    /// Whether a blend is planned whose incoming song has no sound ready yet.
    pub fn planned_fade_waiting(&self) -> bool {
        self.planned.as_ref().is_some_and(|p| !p.deck.is_ready())
    }

    /// What the live tap has learned so far about song `key`, while it is
    /// the one playing (the incoming one, during a blend). `tag_bpm` picks
    /// the tempo's octave.
    pub fn live_analysis(&self, key: u64, tag_bpm: Option<f64>) -> Option<LiveAnalysis> {
        (self.tap.key == Some(key)).then(|| self.tap.analyzer.summary(tag_bpm))
    }

    /// Starts playing `lane` in place of whatever played.
    pub fn start(&mut self, lane: Lane, transition: Transition) {
        self.lane = Some(lane);
        self.fade = None;
        self.release = None;
        self.planned = None;
        self.rated = None;
        self.next_transition = Some(transition);
        self.tail_left = self.shaper.latency();
    }

    /// Stops everything; what the stages hold is dropped.
    pub fn clear(&mut self) {
        self.lane = None;
        self.fade = None;
        self.release = None;
        self.planned = None;
        self.rated = None;
        self.pace.clear();
        self.shaper.clear_held();
    }

    /// Jumps within the current song.
    pub fn seek(&mut self, secs: f64) {
        self.fade = None;
        self.release = None;
        self.planned = None;
        self.rated = None;
        if let Some(lane) = &mut self.lane {
            lane.seek(secs);
        }
        self.pace.clear();
        self.shaper.clear_held();
        self.next_transition = Some(Transition::Seek);
        self.tail_left = self.shaper.latency();
    }

    /// Takes up new sound settings, gliding into them.
    pub fn set_sound(&mut self, settings: &SoundSettings) {
        self.settings = settings.clone();
        self.shaper.apply(settings, self.song_gain, false);
        if let Some(lane) = &mut self.lane {
            lane.set_replay_gain(&settings.replay_gain);
        }
        if let Some(fade) = &mut self.fade {
            fade.outgoing.lane.set_replay_gain(&settings.replay_gain);
        }
    }

    pub fn settings(&self) -> &SoundSettings {
        &self.settings
    }

    // The ReplayGain of the song playing now decides whether the limiter
    // needs to run at all.
    fn follow_song_gain(&mut self) {
        let gain = self.lane.as_ref().map(|l| l.current_gain()).unwrap_or(1.0);
        if gain != self.song_gain {
            self.song_gain = gain;
            let settings = self.settings.clone();
            self.shaper.apply(&settings, gain, false);
        }
    }

    pub fn set_pace(&mut self, pace: Pace) {
        self.pace.set(pace);
    }

    pub fn pace(&self) -> Pace {
        self.pace.pace()
    }

    /// Lines up a crossfade into `deck`, starting when song `key` reaches
    /// `at_secs` and lasting `frames` mix frames, shaped by `shape`. The
    /// outgoing song stops when the crossfade ends, even with sound left.
    pub fn plan_fade(
        &mut self,
        key: u64,
        at_secs: f64,
        frames: u64,
        deck: Deck,
        loudness: Loudness,
        shape: FadeShape,
    ) {
        self.planned = Some(PlannedFade { key, at_secs, frames, deck, loudness, shape });
    }

    /// Drops a planned crossfade, handing its deck back.
    pub fn cancel_planned_fade(&mut self) -> Option<Deck> {
        self.planned.take().map(|p| p.deck)
    }

    /// Ends a crossfade now: the rest of the blend runs over
    /// `FINISH_SECS`, so the outgoing song glides out and the incoming one up
    /// to its own level instead of stepping, and the incoming song's filter
    /// then hands over to its dry sound as at a blend's end.
    pub fn finish_fade(&mut self) {
        let len = ((FINISH_SECS * self.rate as f64) as u64).max(1);
        if let Some(fade) = &mut self.fade
            && fade.clock.end().saturating_sub(fade.done) > len
        {
            fade.clock.rush = Some((fade.done, fade.clock.progress(fade.done), len));
        }
    }

    // Drops the blend, keeping its incoming filter for the release.
    fn end_fade(&mut self) {
        if let Some(sweeps) = self.fade.take().and_then(|f| f.sweeps) {
            let len = ((RELEASE_SECS * self.rate as f64) as usize).max(1);
            self.release = Some(Release { filter: sweeps.incoming, done: 0, len });
        }
    }

    /// Songs that failed while playing, since the last call.
    pub fn take_failures(&mut self) -> Vec<(u64, Failure)> {
        let mut all = std::mem::take(&mut self.failures);
        if let Some(lane) = &mut self.lane {
            all.extend(lane.take_failures());
        }
        if let Some(fade) = &mut self.fade {
            all.extend(fade.outgoing.lane.take_failures());
        }
        all
    }

    /// Fills `out` (interleaved stereo) as far as it can. Returns the frames
    /// made; `markers` gets where songs start or the clock needs a new
    /// reference point.
    pub fn render(&mut self, out: &mut [f32], markers: &mut Vec<Marker>) -> (usize, MixState) {
        let wanted = out.len() / 2;
        let mut made = 0;
        let mut state = MixState::Playing;
        while made < wanted {
            let n = (wanted - made).min(BLOCK);
            let got = if self.pace.is_active() {
                self.render_paced(n, markers)
            } else {
                self.render_direct(n, markers)
            };
            let (frames, s) = got;
            if frames == 0 {
                state = s;
                if s == MixState::Ended && self.tail_left > 0 {
                    // Let the shaper's held-back tail out.
                    let n = self.tail_left.min(wanted - made).min(BLOCK);
                    self.block[..n * 2].fill(0.0);
                    self.tail_left -= n;
                    self.shaper.process(&mut self.block, n);
                    out[made * 2..(made + n) * 2].copy_from_slice(&self.block[..n * 2]);
                    made += n;
                    self.made += n as u64;
                    continue;
                }
                break;
            }
            self.shaper.set_blending(std::mem::take(&mut self.blended));
            self.shaper.process(&mut self.block, frames);
            out[made * 2..(made + frames) * 2].copy_from_slice(&self.block[..frames * 2]);
            made += frames;
            self.made += frames as u64;
        }
        (made, state)
    }

    // At normal pace: mix straight into the block.
    fn render_direct(&mut self, n: usize, markers: &mut Vec<Marker>) -> (usize, MixState) {
        let start = self.mixed;
        let (frames, state) = self.mix(n);
        if frames > 0 {
            self.emit_markers(start as f64, frames, 1.0, markers);
        }
        (frames, state)
    }

    // With a speed or pitch change: mix into the speed stage until it has
    // enough to hand out.
    fn render_paced(&mut self, n: usize, markers: &mut Vec<Marker>) -> (usize, MixState) {
        let mut state = MixState::Playing;
        while self.pace.available() < n {
            let (frames, s) = self.mix(BLOCK);
            if frames == 0 {
                state = s;
                if s == MixState::Ended {
                    // The last of the song is still inside the stage.
                    self.pace.drain();
                }
                break;
            }
            self.pace.push(&self.block[..frames * 2]);
        }
        let pending = self.pace.pending_input();
        let start = self.mixed as f64 - pending;
        let frames = self.pace.pull(&mut self.block[..n * 2]);
        if frames > 0 {
            self.emit_markers(start, frames, self.pace.pace().speed as f64, markers);
            state = MixState::Playing;
        }
        (frames, state)
    }

    // Turns the marks for mix frames from `start` on into output markers
    // for `frames` output frames, where each output frame is `step` mix frames.
    fn emit_markers(&mut self, start: f64, frames: usize, step: f64, markers: &mut Vec<Marker>) {
        let latency = self.shaper.latency() as u64;
        let first_out = self.base + self.made + latency;
        let end = start + frames as f64 * step;
        // The mark in force at the start, then any that begin inside.
        let from = self.marks.iter().rposition(|m| (m.frame as f64) <= start + 1e-6).unwrap_or(0);
        for i in from..self.marks.len() {
            let mark = self.marks[i];
            let at = (mark.frame as f64).max(start);
            if i > from && at >= end {
                break;
            }
            let offset = ((at - start) / step).round() as u64;
            let secs = mark.secs + (at - mark.frame as f64) * mark.speed / self.rate as f64;
            let secs_per_frame = step * mark.speed / self.rate as f64;
            // A song start is told exactly once, even when the speed stage
            // puts the first output frame a little past its mark.
            let transition = mark.transition;
            self.marks[i].transition = None;
            let marker =
                Marker { frame: first_out + offset, key: mark.key, secs, secs_per_frame, transition };
            // Only when it tells the clock something new.
            let predicted = self.last_marker.map(|m| {
                m.key == marker.key
                    && (m.secs + (marker.frame - m.frame.min(marker.frame)) as f64 * m.secs_per_frame - secs)
                        .abs()
                        < 0.002
                    && (m.secs_per_frame - secs_per_frame).abs() < 1e-12
            });
            if marker.transition.is_some() || predicted != Some(true) {
                markers.push(marker);
                self.last_marker = Some(marker);
            }
        }
        // Keep only the mark in force from here on.
        while self.marks.len() > 1 && (self.marks[1].frame as f64) < end {
            self.marks.pop_front();
        }
    }

    // Mixes up to `n` frames into `self.block`.
    fn mix(&mut self, wanted: usize) -> (usize, MixState) {
        let mut n = self.frames_before_fade(wanted);
        if n == 0 && self.planned.is_some() {
            self.begin_fade();
            n = wanted;
        }
        self.blended |= self.fade.is_some();
        // A blend ends on its exact frame, where the filters come off.
        if let Some(fade) = &self.fade {
            n = n.min(fade.clock.end().saturating_sub(fade.done).max(1) as usize);
        }
        let Some(lane) = &mut self.lane else {
            return (0, MixState::Ended);
        };
        let (state, mut frames) = match &mut self.rated {
            Some(rated) => (rated.fill(lane, n), rated.available().min(n)),
            None => (lane.fill(n), lane.available().min(n)),
        };
        let fade_state = self.fade.as_mut().map(|f| f.outgoing.fill(n));
        if let Some(fade) = &self.fade {
            // Both songs sound together; wait for both unless the old one is over.
            if !fade.outgoing.is_ended() {
                frames = frames.min(fade.outgoing.available());
            }
        }
        if frames == 0 {
            let state = match (state, fade_state) {
                (LaneState::Ended, None | Some(LaneState::Ended)) => MixState::Ended,
                _ => MixState::Waiting,
            };
            return (0, state);
        }
        if let Some(rated) = &mut self.rated {
            let (key, secs, speed) = (rated.key, rated.head_secs(), rated.stretch.rate());
            let got = rated.out.pop_into(&mut self.a[..frames * 2]) / 2;
            debug_assert_eq!(got, frames);
            rated.advance(frames);
            if rated.is_done() {
                self.rated = None;
            }
            let transition = self.next_transition.take();
            self.push_mark(key, secs, speed, transition);
            self.mixed += frames as u64;
            self.tap.feed(key, secs, self.rate, &self.a[..frames * 2], self.song_gain);
        } else {
            let got = lane.pull(&mut self.a[..frames * 2], &mut self.spans);
            debug_assert_eq!(got, frames);
            let spans = std::mem::take(&mut self.spans);
            let mut transition = self.next_transition.take();
            let mut at = 0;
            for span in &spans {
                let t = if span.joined { Some(Transition::Gapless) } else { transition.take() };
                self.push_mark(span.key, span.start_secs, 1.0, t);
                self.mixed += span.frames as u64;
                let gain = self.lane.as_ref().map(|l| l.current_gain()).unwrap_or(1.0);
                let part = &self.a[at * 2..(at + span.frames) * 2];
                self.tap.feed(span.key, span.start_secs, self.rate, part, gain);
                at += span.frames;
            }
            self.spans = spans;
        }
        self.follow_song_gain();
        if let Some(fade) = &mut self.fade {
            let old = fade.outgoing.pull(&mut self.b[..frames * 2], &mut self.spans_b);
            self.b[old * 2..frames * 2].fill(0.0);
            if let Some(gate) = fade.gate {
                let power = self.b[..frames * 2].iter().map(|s| s * s).sum::<f32>() / (frames * 2) as f32;
                fade.quiet = if power < gate { fade.quiet + frames as u64 } else { 0 };
                if fade.clock.rush.is_none() && fade.quiet as f64 >= QUIET_SECS * self.rate as f64 {
                    // The outgoing song has gone quiet: finish the blend now.
                    let len =
                        ((RUSH_SECS * self.rate as f64) as u64).min(fade.frames.saturating_sub(fade.done));
                    fade.clock.rush = Some((fade.done, fade.clock.progress(fade.done), len.max(1)));
                }
            }
            if let Some(sweeps) = &mut fade.sweeps {
                let clock = fade.clock;
                sweeps.run(&mut self.b, &mut self.a, frames, fade.done, |d| clock.progress(d));
            }
        } else if let Some(release) = &mut self.release {
            let wet = &mut self.b[..frames * 2];
            wet.copy_from_slice(&self.a[..frames * 2]);
            release.filter.process(wet, frames);
            for i in 0..frames {
                let dry = ((release.done + i) as f32 / release.len as f32).min(1.0);
                for ch in 0..2 {
                    let at = i * 2 + ch;
                    self.a[at] = wet[at] * (1.0 - dry) + self.a[at] * dry;
                }
            }
            release.done += frames;
            if release.done >= release.len {
                self.release = None;
            }
        }
        self.block[..frames * 2].copy_from_slice(&self.a[..frames * 2]);
        if let Some(fade) = &mut self.fade {
            for i in 0..frames {
                let p = fade.clock.progress(fade.done + i as u64);
                let (mut gout, mut gin) = blend_gains(fade.curve, fade.k, p, fade.overlap_ms);
                if fade.headroom_db > 0.0 {
                    let h = headroom(fade.headroom_db, p);
                    gout *= h;
                    gin *= h;
                }
                let (gout, gin) = (gout as f32, gin as f32);
                self.block[i * 2] = self.a[i * 2] * gin + self.b[i * 2] * gout;
                self.block[i * 2 + 1] = self.a[i * 2 + 1] * gin + self.b[i * 2 + 1] * gout;
            }
            fade.done += frames as u64;
            if fade.done >= fade.clock.end() || fade.outgoing.is_ended() {
                self.failures.extend(fade.outgoing.lane.take_failures());
                self.end_fade();
            }
        }
        (frames, MixState::Playing)
    }

    fn push_mark(&mut self, key: u64, secs: f64, speed: f64, transition: Option<Transition>) {
        // A plain continuation of the last mark needs no new one.
        if transition.is_none()
            && let Some(last) = self.marks.back()
            && last.key == key
            && last.speed == speed
            && (last.secs + (self.mixed - last.frame) as f64 * speed / self.rate as f64 - secs).abs() < 0.0005
        {
            return;
        }
        self.marks.push_back(MixMark { frame: self.mixed, key, secs, speed, transition });
    }

    // How many frames can be mixed before a planned crossfade begins. A song
    // whose sound stops short of the blend's start begins it at once.
    fn frames_before_fade(&self, n: usize) -> usize {
        let (Some(plan), Some(lane)) = (&self.planned, &self.lane) else { return n };
        if lane.current().key() == plan.key && lane.ran_dry() {
            return 0;
        }
        let Some((key, secs)) = lane.position() else { return n };
        if key != plan.key {
            return n;
        }
        let left = ((plan.at_secs - secs) * self.rate as f64).round();
        if left <= 0.0 { 0 } else { (left as usize).min(n) }
    }

    fn begin_fade(&mut self) {
        let Some(plan) = self.planned.take() else { return };
        let Some(mut old) = self.lane.take() else { return };
        if !plan.deck.is_ready() {
            // Not ready in time: the song ends as usual and the next one
            // follows without a gap.
            old.set_next(Some(plan.deck), plan.loudness);
            self.lane = Some(old);
            return;
        }
        let from = old.current().key();
        old.set_next(None, Loudness::default());
        old.last = true;
        let to = plan.deck.key();
        let incoming = Lane::new(plan.deck, plan.loudness, &self.settings.replay_gain, self.rate);
        self.lane = Some(incoming);
        self.next_transition = Some(Transition::Crossfade { from, frames: plan.frames });
        let shape = plan.shape;
        let sweeps =
            (shape.filter_strength > 0.0).then(|| Sweeps::new(self.rate, shape.filter_strength, shape.steps));
        // A rate stage still easing the outgoing song stays with it.
        let easing = self.rated.take().filter(|r| r.key == from);
        self.rated =
            shape.rate.filter(|r| (r - 1.0).abs() > 1e-4).map(|r| Rated::new(to, self.rate, r, plan.frames));
        let gate = shape.silence_gate_db.map(|db| 10f32.powf(db / 10.0));
        self.fade = Some(Fade {
            outgoing: Outgoing { lane: old, rated: easing },
            frames: plan.frames,
            done: 0,
            clock: FadeClock { frames: plan.frames, rush: None },
            k: shape.k,
            curve: shape.curve,
            overlap_ms: plan.frames as f64 * 1_000.0 / self.rate as f64,
            sweeps,
            gate,
            quiet: 0,
            headroom_db: shape.headroom_db,
        });
    }
}
