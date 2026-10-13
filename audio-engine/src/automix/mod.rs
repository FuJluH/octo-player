//! Planned transitions between songs: where the blend starts in the
//! outgoing song, where the incoming one comes in, how long they overlap,
//! the shape of the gain curve, the filter sweeps over each song, and an
//! optional rate for the incoming song so the two tempos line up.
//!
//! The scout decodes the end of the playing song and the start of the next
//! one into envelopes ([`SectionAnalyzer`]), unless the app handed over the
//! song's [`TransitionProfile`] from its server; a live tap follows the
//! playing song as it is heard ([`LiveAnalyzer`]); [`plan`] turns them into a
//! [`TransitionPlan`] that the mixer runs.

pub mod curves;
pub mod dsp;
pub mod envelope;
pub mod features;
pub mod planner;
pub mod profile;
pub mod song_profile;

pub use curves::*;
pub use dsp::{BUTTERWORTH_Q, Biquad};
pub use envelope::{ENVELOPE_HOP_MS, EnvelopeBuilder, SILENT_DB, SectionEnvelope, db_of};
pub use features::{
    LiveTap, SILENCE_BELOW_BODY_DB, SILENCE_FLOOR_DB, SectionAnalysis, SectionFeatures, Tempo, analyze_head,
    analyze_tail, body_level_of, fold_tempo_ratio,
};
pub use planner::{
    PRE_ROLL_MS, PlanSettings, TransitionContext, TransitionKind, TransitionPlan, is_plain_genre,
    plan_transition,
};
pub use profile::{PROFILE_VERSION, SectionProfile, TransitionProfile, level_code, level_of_code};
pub use song_profile::{SongProfile, SongProfileSection, SongProfileTempo};

use crate::crossfade::{FadeSong, SHORTEST_FADE_MS};
use crate::scout::PcmSink;

/// How much of the outgoing song's end the scout decodes, in seconds.
pub const TAIL_SECS: f64 = 60.0;

/// How much of the incoming song's start the scout decodes, in seconds.
pub const HEAD_SECS: f64 = 30.0;

/// How far before the end of the outgoing song a planned blend may start.
pub const LATEST_EXIT_SECS: f64 = planner::LONGEST_EARLY_EXIT_MS as f64 / 1_000.0;

/// After the blend, how long the incoming song takes to ease back to its
/// own rate when its tempo was matched.
pub const RATE_EASE_SECS: f64 = BEAT_MATCH_SETTLE_MS / 1_000.0;

/// The closest the incoming rate may be moved from normal, either way.
pub const RATE_RANGE: f64 = 0.06;

/// The least time between deciding a blend and its start, so the incoming
/// song is open and buffered from its entry point in time.
pub const LEAD_SECS: f64 = PRE_ROLL_MS as f64 / 1_000.0;

/// The user's choices for transitions.
#[derive(Clone, Debug, PartialEq, uniffi::Record)]
pub struct AutomixSettings {
    /// Choose where each blend starts from the music; off is the fixed
    /// crossfade at the end of the song.
    pub smart_transitions: bool,
    /// Sweep filters over both songs during a smart blend.
    pub filter_sweeps: bool,
    /// Nudge the incoming song's tempo to the outgoing one's.
    pub match_tempo: bool,
    /// The longest a smart blend may last, in milliseconds; 0 uses the
    /// crossfade length.
    pub max_overlap_ms: u32,
    /// The shape of the fixed crossfade, with smart transitions off.
    pub fade_curve: FadeCurve,
}

impl Default for AutomixSettings {
    fn default() -> Self {
        Self {
            smart_transitions: false,
            filter_sweeps: true,
            match_tempo: false,
            max_overlap_ms: 8_000,
            fade_curve: FadeCurve::EqualPower,
        }
    }
}

/// The outgoing and incoming gains at progress `t` (0 to 1) for curve
/// weight `k`. The incoming gain keeps the summed power at one; `k = 0` is
/// the equal-power crossfade.
pub fn gains(t: f64, k: f64) -> (f64, f64) {
    (automix_out_gain(t, k), automix_in_gain(t, k))
}

impl TransitionPlan {
    /// The equal-power crossfade at the end of the outgoing song: `overlap_ms`
    /// long, ending as the song does. [`TransitionPlan::with_curve`] gives
    /// it another shape.
    pub fn fixed_crossfade(len_a_ms: i64, overlap_ms: i64, why: &str) -> Self {
        let start_ms = (len_a_ms - overlap_ms).max(0);
        TransitionPlan {
            start_ms,
            entry_ms: 0,
            overlap_ms,
            kind: TransitionKind::Crossfade,
            k: 0.0,
            filter_strength: 0.0,
            beat_match_rate: None,
            beat_ms: None,
            beat_anchor_ms: None,
            late: false,
            headroom_db: 0.0,
            reason: format!(
                "crossfade at {} over {}: {why}",
                planner::seconds(start_ms),
                planner::seconds(overlap_ms)
            ),
            curve: FadeCurve::EqualPower,
        }
    }

    /// This fixed crossfade with `curve` for its shape, and the headroom
    /// that shape plays with.
    pub fn with_curve(self, curve: FadeCurve) -> Self {
        TransitionPlan { curve, headroom_db: fade_headroom_db(curve), ..self }
    }

    /// This plan when its start has already passed, or comes too soon to
    /// line the incoming song up: the blend ends where it would have, starts
    /// at `now_ms` at the earliest, keeps its entry, curve and filters, and
    /// drops its bar lock and tempo matching. `None` when too little is left
    /// to blend.
    pub fn late_from(&self, now_ms: i64) -> Option<Self> {
        let end = self.start_ms + self.overlap_ms;
        let start_ms = self.start_ms.max(now_ms);
        let overlap_ms = end - start_ms;
        if overlap_ms < SHORTEST_FADE_MS as i64 {
            return None;
        }
        Some(TransitionPlan {
            start_ms,
            overlap_ms,
            beat_match_rate: None,
            beat_ms: None,
            beat_anchor_ms: None,
            late: true,
            reason: format!(
                "late {} at {} over {} ({})",
                self.kind.name(),
                planner::seconds(start_ms),
                planner::seconds(overlap_ms),
                self.reason
            ),
            ..self.clone()
        })
    }

    pub fn start_secs(&self) -> f64 {
        self.start_ms as f64 / 1_000.0
    }

    pub fn entry_secs(&self) -> f64 {
        self.entry_ms as f64 / 1_000.0
    }

    pub fn overlap_secs(&self) -> f64 {
        self.overlap_ms as f64 / 1_000.0
    }

    /// The line logged for this plan.
    pub fn describe(&self) -> String {
        format!("automix: {}", self.reason)
    }
}

/// Which part of a song a [`SectionAnalyzer`] takes in.
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum SectionKind {
    Head,
    Tail,
}

/// Takes in a section's mono sound as the scout decodes it, builds its
/// envelope, and finds its features.
pub struct SectionAnalyzer {
    kind: SectionKind,
    tag_bpm: Option<f64>,
    builder: Option<EnvelopeBuilder>,
}

impl SectionAnalyzer {
    /// `tag_bpm` is the song's tempo from its tags, when it has one.
    pub fn new(kind: SectionKind, tag_bpm: Option<f64>) -> Self {
        SectionAnalyzer { kind, tag_bpm, builder: None }
    }

    /// The section's features; `None` when no sound came in.
    pub fn finish(self) -> Option<SectionAnalysis> {
        let envelope = self.builder?.into_envelope();
        if envelope.size() == 0 {
            return None;
        }
        Some(match self.kind {
            SectionKind::Head => analyze_head(envelope, self.tag_bpm),
            SectionKind::Tail => analyze_tail(envelope, self.tag_bpm, None),
        })
    }
}

impl PcmSink for SectionAnalyzer {
    fn begin(&mut self, start_secs: f64, sample_rate: u32) {
        let start_ms = (start_secs * 1_000.0).round() as i64;
        self.builder = Some(EnvelopeBuilder::new(sample_rate, 1, start_ms));
    }

    fn pcm(&mut self, mono: &[f32]) {
        if let Some(b) = &mut self.builder {
            b.push(mono);
        }
    }
}

/// What the live tap learned about a song from what has played of it.
#[derive(Clone, Debug, Default, PartialEq)]
pub struct LiveAnalysis {
    /// How much of the song has been heard, in milliseconds.
    pub heard_ms: i64,
    /// The body level of what was heard, `None` while it was all silence.
    pub body_level_db: Option<f64>,
    /// The tempo of what was heard, when it is trusted.
    pub tempo_prior: Option<f64>,
}

/// Takes in the playing song's mono sound as it is mixed (on the mixing
/// thread, never the device's) and keeps its envelope.
#[derive(Default)]
pub struct LiveAnalyzer {
    tap: Option<LiveTap>,
}

impl LiveAnalyzer {
    pub fn new() -> Self {
        Self::default()
    }

    /// What has been heard so far. `tag_bpm` picks the tempo's octave.
    pub fn summary(&self, tag_bpm: Option<f64>) -> LiveAnalysis {
        let Some(tap) = &self.tap else { return LiveAnalysis::default() };
        LiveAnalysis {
            heard_ms: tap.heard_ms(),
            body_level_db: tap.body_level_db(),
            tempo_prior: tap.tempo_prior(tag_bpm),
        }
    }

    /// How much has been heard, in milliseconds.
    pub fn heard_ms(&self) -> i64 {
        self.tap.as_ref().map_or(0, |t| t.heard_ms())
    }
}

impl PcmSink for LiveAnalyzer {
    fn begin(&mut self, _start_secs: f64, sample_rate: u32) {
        self.tap = Some(LiveTap::new(sample_rate, 1));
    }

    fn pcm(&mut self, mono: &[f32]) {
        if let Some(tap) = &mut self.tap {
            tap.push(mono);
        }
    }
}

/// What the planner works from.
#[derive(Clone, Debug)]
pub struct PlanInput<'a> {
    pub current: FadeSong,
    pub next: FadeSong,
    /// The end of the outgoing song, when it was scouted.
    pub tail: Option<&'a SectionAnalysis>,
    /// The start of the incoming song, when it was scouted.
    pub head: Option<&'a SectionAnalysis>,
    pub settings: PlanSettings,
    pub context: TransitionContext,
}

/// Plans the transition from the scouted sections.
pub fn plan(input: &PlanInput) -> TransitionPlan {
    plan_transition(
        &input.current,
        Some(&input.next),
        input.tail,
        input.head,
        &input.settings,
        &input.context,
    )
}

/// A planner a test puts in place of `plan` on one engine.
#[cfg(test)]
pub type Planner = fn(&PlanInput) -> TransitionPlan;

#[cfg(test)]
mod fade_vectors;
#[cfg(test)]
mod synthetic;
#[cfg(test)]
mod tests;
#[cfg(test)]
mod vectors;
