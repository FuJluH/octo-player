//! Chooses where and how one song hands over to the next.

use super::curves::{
    BLEND_CURVE, CROSSFADE_CURVE, CUT_CURVE, FILTER_STRENGTH, FadeCurve, LIFT_CURVE, beat_match_rate_at,
    blend_gains, incoming_high_pass_hz, outgoing_high_pass_hz, outgoing_low_pass_hz,
    stepped_outgoing_low_pass_hz,
};
use super::features::{
    BEATS_PER_BAR, SectionAnalysis, TEMPO_CONFIDENT, Tempo, fold_tempo_ratio, round_half_up,
};
use crate::crossfade::{FadeSong, SHORTEST_FADE_MS, crossfade_length};

/// Songs shorter than this get the plain crossfade, never a planned one.
pub const SHORTEST_AUTOMIX_SONG_MS: i64 = 35_000;

/// The shortest planned blend, and the longest that still counts as a cut.
pub const SHORTEST_BLEND_MS: i64 = 1_800;
pub const CUT_BLEND_MS: i64 = 2_400;

/// The latest a blend may end: this long before the outgoing song's end.
pub const END_MARGIN_MS: i64 = 250;

/// The earliest a blend may start: this far into the song, this share of
/// it, once the song has played long enough to count as played (half of it
/// or `COUNTS_AS_PLAYED_MS`, whichever is less), and no more than
/// `LONGEST_EARLY_EXIT_MS` before the latest end.
pub const EARLIEST_START_MS: i64 = 30_000;
pub const EARLIEST_START_SHARE: f64 = 0.5;
pub const COUNTS_AS_PLAYED_MS: i64 = 240_000;
pub const LONGEST_EARLY_EXIT_MS: i64 = 45_000;

/// The incoming song needs this long to get ready before the blend starts.
pub const PRE_ROLL_MS: i64 = 3_000;

/// Without a beat grid the start is tried every this many milliseconds.
pub const START_STEP_MS: i64 = 250;

/// The incoming song's entry moves onto a beat this close to its first sound.
pub const ENTRY_SNAP_MS: f64 = 300.0;

/// Both songs play this much quieter through the overlap, so their sum does
/// not clip.
pub const OVERLAP_HEADROOM_DB: f64 = 1.0;

/// Songs in genres holding any of these words (in any case) get the plain
/// crossfade, never a planned one.
pub const PLAIN_CROSSFADE_GENRES: [&str; 6] =
    ["classical", "opera", "spoken", "audiobook", "podcast", "comedy"];

/// How the two songs meet.
#[derive(Clone, Copy, Debug, PartialEq, Eq)]
pub enum TransitionKind {
    /// One song straight after the other, no overlap.
    Gapless,
    /// The fixed crossfade at the end of the song.
    Crossfade,
    /// A short planned swap.
    Cut,
    /// A planned blend into a louder song.
    Lift,
    /// A planned blend.
    Blend,
}

impl TransitionKind {
    pub fn name(self) -> &'static str {
        match self {
            TransitionKind::Gapless => "gapless",
            TransitionKind::Crossfade => "crossfade",
            TransitionKind::Cut => "cut",
            TransitionKind::Lift => "lift",
            TransitionKind::Blend => "blend",
        }
    }
}

/// What the player sets for planned transitions.
#[derive(Clone, Debug, PartialEq)]
pub struct PlanSettings {
    /// The longest blend, from the crossfade slider; 0 turns crossfade off.
    pub max_overlap_ms: i64,
    /// Off plays the fixed crossfade at the end of each song.
    pub smart: bool,
    pub filter_sweeps: bool,
    /// Nudges the incoming song's speed to the outgoing song's tempo.
    pub beat_match: bool,
    /// The shape of the fixed crossfade, with smart transitions off.
    /// Planned blends keep their own curves.
    pub fade_curve: FadeCurve,
}

impl PlanSettings {
    pub fn new(max_overlap_ms: i64) -> Self {
        PlanSettings {
            max_overlap_ms,
            smart: true,
            filter_sweeps: true,
            beat_match: false,
            fade_curve: FadeCurve::EqualPower,
        }
    }
}

/// Where the player is when it plans, and what it knows besides the
/// scouted sections. `now_ms` is the outgoing song's position and
/// `played_ms` how much of it has actually been heard (less than `now_ms`
/// after a seek forward). `body_level_db` and `tempo_prior` come from a live
/// tap of the outgoing song. A pace other than 1 or skip-silence moves media
/// time away from the beat, so they turn off bar lock and tempo matching.
#[derive(Clone, Debug, PartialEq)]
pub struct TransitionContext {
    pub now_ms: i64,
    pub played_ms: i64,
    pub repeat_one: bool,
    pub stop_at_end_of_song: bool,
    pub pace: f64,
    pub skip_silence: bool,
    pub current_genre: Option<String>,
    pub next_genre: Option<String>,
    pub body_level_db: Option<f64>,
    pub tempo_prior: Option<f64>,
}

impl Default for TransitionContext {
    fn default() -> Self {
        TransitionContext {
            now_ms: 0,
            played_ms: 0,
            repeat_one: false,
            stop_at_end_of_song: false,
            pace: 1.0,
            skip_silence: false,
            current_genre: None,
            next_genre: None,
            body_level_db: None,
            tempo_prior: None,
        }
    }
}

/// How to move from one song to the next. At `start_ms` into the outgoing
/// song the incoming song starts playing from `entry_ms`, and over
/// `overlap_ms` the volumes follow [`blend_gains`]: the automix curve with
/// weight `k`, or a fixed crossfade's own `curve`, both lowered by
/// `headroom_db`. With a `filter_strength` above 0 the filter sweeps run
/// through the overlap and are bypassed once it ends. `beat_match_rate`,
/// when set, is the incoming song's playback rate through the blend.
/// `beat_ms` and `beat_anchor_ms`, when set, are the outgoing song's beat
/// length and one of its beats in song time: the blend is locked to the bar
/// and the low-pass steps on the beat. `late` marks a blend placed at the
/// end because there was no time or data to choose a better place.
/// `reason` says why this plan was chosen.
#[derive(Clone, Debug, PartialEq)]
pub struct TransitionPlan {
    pub start_ms: i64,
    pub entry_ms: i64,
    pub overlap_ms: i64,
    pub kind: TransitionKind,
    pub k: f64,
    pub filter_strength: f64,
    pub beat_match_rate: Option<f64>,
    pub beat_ms: Option<f64>,
    pub beat_anchor_ms: Option<f64>,
    pub late: bool,
    pub headroom_db: f64,
    pub reason: String,
    /// The shape of a fixed crossfade; equal power follows `k`.
    pub curve: FadeCurve,
}

impl TransitionPlan {
    pub fn bar_locked(&self) -> bool {
        self.beat_ms.is_some()
    }

    pub fn progress_at(&self, outgoing_ms: f64) -> f64 {
        if self.overlap_ms <= 0 {
            1.0
        } else {
            ((outgoing_ms - self.start_ms as f64) / self.overlap_ms as f64).clamp(0.0, 1.0)
        }
    }

    pub fn out_gain(&self, t: f64) -> f64 {
        blend_gains(self.curve, self.k, t, self.overlap_ms as f64).0
    }

    pub fn in_gain(&self, t: f64) -> f64 {
        blend_gains(self.curve, self.k, t, self.overlap_ms as f64).1
    }

    /// The outgoing song's beats inside the blend as places through it (0
    /// to 1). A beat within a twentieth of a beat of either end counts as
    /// the end itself and is left out.
    pub fn beat_progress(&self) -> Vec<f64> {
        let (Some(beat), Some(anchor)) = (self.beat_ms, self.beat_anchor_ms) else { return Vec::new() };
        if self.overlap_ms <= 0 || beat <= 0.0 {
            return Vec::new();
        }
        let grid = Tempo {
            bpm: 60_000.0 / beat,
            confidence: TEMPO_CONFIDENT,
            consistency: 1.0,
            steady: true,
            beat_ms: beat,
            first_beat_ms: anchor,
            downbeat_ms: anchor,
        };
        let margin = beat / 20.0;
        let (start, overlap) = (self.start_ms as f64, self.overlap_ms as f64);
        grid.beats_between(start + margin, start + overlap - margin)
            .into_iter()
            .map(|b| (b - start) / overlap)
            .collect()
    }

    /// How long the stepped low-pass takes to glide to each beat's cutoff,
    /// as a share of the blend: an eighth of a bar. `None` when the blend is
    /// not locked to the bar and the low-pass sweeps smoothly.
    pub fn low_pass_glide(&self) -> Option<f64> {
        let beat = self.beat_ms?;
        (self.overlap_ms > 0).then(|| beat * BEATS_PER_BAR as f64 / 8.0 / self.overlap_ms as f64)
    }

    /// The outgoing low-pass: stepped on the beat when the blend is locked
    /// to the bar, gliding over an eighth of a bar.
    pub fn outgoing_low_pass_at(&self, t: f64) -> f64 {
        match self.low_pass_glide() {
            None => outgoing_low_pass_hz(t, self.filter_strength),
            Some(glide) => {
                stepped_outgoing_low_pass_hz(t, self.filter_strength, &self.beat_progress(), glide)
            }
        }
    }

    pub fn outgoing_high_pass_at(&self, t: f64) -> f64 {
        outgoing_high_pass_hz(t, self.filter_strength)
    }

    pub fn incoming_high_pass_at(&self, t: f64) -> f64 {
        incoming_high_pass_hz(t, self.filter_strength)
    }

    /// The incoming song's playback rate `since_entry_ms` after it came in.
    pub fn incoming_rate_at(&self, since_entry_ms: f64) -> f64 {
        self.beat_match_rate.map_or(1.0, |r| beat_match_rate_at(r, since_entry_ms, self.overlap_ms as f64))
    }
}

/// Plans the move from the playing song to the next one. `tail` is the
/// analysis of the end of the playing song ([`super::analyze_tail`]) and
/// `head` of the start of the next one ([`super::analyze_head`]), either
/// `None` when it is not ready. Every rule of `crossfade_length` still
/// holds: when it gives no crossfade the songs play gaplessly. With smart
/// transitions off the plan is the equal-power crossfade
/// ([`TransitionPlan::fixed_crossfade`]); for a song under 35 s or in a genre
/// that should not be mixed, the fixed crossfade with the plain curve. Without the tail, or when no
/// start is left at least [`PRE_ROLL_MS`] ahead, the plan is a late one: the
/// blend at the end, with the curve and the filters but no bar lock.
pub fn plan_transition(
    current: &FadeSong,
    next: Option<&FadeSong>,
    tail: Option<&SectionAnalysis>,
    head: Option<&SectionAnalysis>,
    settings: &PlanSettings,
    context: &TransitionContext,
) -> TransitionPlan {
    let len_a = current.duration_ms as i64;
    let plain = crossfade_length(
        current,
        next,
        settings.max_overlap_ms.max(0) as u64,
        context.repeat_one,
        context.stop_at_end_of_song,
    ) as i64;
    let Some(next) = next.filter(|_| plain != 0) else {
        let why = gapless_reason(current, next, settings.max_overlap_ms, context);
        return gapless_plan(len_a, &why);
    };
    let len_b = next.duration_ms as i64;
    if !settings.smart {
        return TransitionPlan::fixed_crossfade(len_a, plain, "smart transitions off")
            .with_curve(settings.fade_curve);
    }
    let genres = [context.current_genre.as_deref(), context.next_genre.as_deref()];
    if let Some(genre) = genres.into_iter().flatten().find(|g| is_plain_genre(g)) {
        return crossfade_plan(len_a, plain, &format!("genre {genre}"));
    }
    if len_a < SHORTEST_AUTOMIX_SONG_MS || len_b < SHORTEST_AUTOMIX_SONG_MS {
        return crossfade_plan(len_a, plain, &format!("a song under {} s", SHORTEST_AUTOMIX_SONG_MS / 1000));
    }

    let limit = (settings.max_overlap_ms as f64).min(len_a.min(len_b) as f64 / 2.0);
    let sweeps = if settings.filter_sweeps { FILTER_STRENGTH } else { 0.0 };
    let head_features = head.map(|h| &h.features).filter(|f| f.sound_start_ms.is_some());
    let head_entry = head_features.and_then(|f| f.sound_start_ms).unwrap_or(0);
    let can_lock = context.pace == 1.0 && !context.skip_silence;
    let fixed_end = (len_a - END_MARGIN_MS) as f64;

    let Some(tail) = tail else {
        let why = "no analysis of this song's end";
        return late_plan(len_a, fixed_end, limit, context.now_ms, head_entry, None, head, sweeps, why);
    };
    let measured = match context.body_level_db {
        Some(db) => tail.with_body_level(db),
        None => tail.clone(),
    };
    let a = &measured.features;
    let (Some(sound_end_a), Some(outro_a)) = (a.sound_end_ms, a.outro_start_ms) else {
        let why = "this song's end is silent";
        return late_plan(len_a, fixed_end, limit, context.now_ms, head_entry, None, head, sweeps, why);
    };

    let latest_end = sound_end_a.min(len_a - END_MARGIN_MS) as f64;
    let outro_start = (outro_a as f64).min(latest_end);
    let mut tempo_a = a.tempo.filter(Tempo::confident);
    if let (Some(t), Some(prior)) = (tempo_a, context.tempo_prior.filter(|&p| p > 0.0)) {
        // The end must keep the tempo the whole song has.
        let moved = t.in_octave_of(prior);
        tempo_a = ((moved.bpm / prior - 1.0).abs() <= 0.04).then_some(moved);
    }
    let tempo_b = head_features.and_then(|f| f.tempo).filter(Tempo::confident);
    let lock_a = tempo_a.filter(|_| can_lock && tempo_b.is_some());
    let lock_b = tempo_b.filter(|_| lock_a.is_some());
    let ratio = match (lock_a, lock_b) {
        (Some(a), Some(b)) => Some(fold_tempo_ratio(a.bpm / b.bpm)),
        _ => None,
    };

    let sound_start_b = head_entry as f64;
    let mut entry = sound_start_b;
    if let Some(b) = lock_b {
        let beat = b.nearest_beat(entry);
        if (beat - entry).abs() <= ENTRY_SNAP_MS {
            entry = beat.max(0.0);
        }
    }

    let mut bars = 0;
    let mut overlap = match (lock_a, ratio) {
        (Some(a), Some(ratio)) => {
            bars = if (ratio - 1.0).abs() > 0.08 { 2 } else { 4 };
            bars as f64 * a.bar_ms()
        }
        _ => latest_end - outro_start,
    };
    // The next song's quiet start plays under the end of this one, so the
    // blend lasts at least until the next song is near its full level.
    let quiet_start =
        head_features.and_then(|f| f.intro_end_ms).map_or(0.0, |end| (end as f64 - entry).max(0.0));
    let lengthened = quiet_start > overlap;
    if lengthened {
        match lock_a.filter(|_| bars > 0) {
            Some(a) => {
                bars = (quiet_start / a.bar_ms() - 1e-9).ceil() as i32;
                overlap = bars as f64 * a.bar_ms();
            }
            None => overlap = quiet_start,
        }
    }
    overlap = overlap.max(SHORTEST_BLEND_MS as f64).min(limit);
    if let Some(a) = lock_a
        && bars > 0
        && overlap < bars as f64 * a.bar_ms()
    {
        // Cut back to whole bars that fit, when that is still long enough.
        bars = (limit / a.bar_ms() + 1e-9).floor() as i32;
        let whole = bars as f64 * a.bar_ms();
        if bars >= 1 && whole >= SHORTEST_BLEND_MS as f64 {
            overlap = whole;
        } else {
            bars = 0;
        }
    }
    overlap = (overlap + 0.5).floor();

    // Where the song will count as played, at the current pace of listening.
    let counts_as_played = context.now_ms + 0.max((len_a / 2).min(COUNTS_AS_PLAYED_MS) - context.played_ms);
    let lo = (EARLIEST_START_SHARE * len_a as f64)
        .max(EARLIEST_START_MS as f64)
        .max(counts_as_played as f64)
        .max(latest_end - LONGEST_EARLY_EXIT_MS as f64)
        .max(tail.envelope.start_ms as f64)
        .max((context.now_ms + PRE_ROLL_MS) as f64);
    let hi = latest_end - overlap;
    if hi < lo {
        let why = format!("no start left before {}", seconds(hi as i64));
        return late_plan(
            len_a,
            latest_end,
            overlap,
            context.now_ms,
            head_entry,
            Some(&measured),
            head,
            sweeps,
            &why,
        );
    }

    // Bar lines when the blend is locked to the bar, otherwise a fixed step
    // back from the latest start.
    let bar_lines = lock_a.map(|a| a.bars_between(lo, hi)).unwrap_or_default();
    let on_bars = !bar_lines.is_empty();
    let candidates = if on_bars {
        bar_lines
    } else {
        let mut steps = Vec::new();
        let mut at = hi;
        while at >= lo - 1e-6 {
            steps.push(at);
            at -= START_STEP_MS as f64;
        }
        steps.reverse();
        steps
    };
    let phrase_anchor = lock_a
        .map(|a| a.downbeat_ms + round_half_up((outro_start - a.downbeat_ms) / a.bar_ms()) * a.bar_ms());
    let full_db = a.body_db - 3.0;

    let mut best_start = *candidates.last().expect("hi >= lo leaves a candidate");
    let mut best_score = f64::NEG_INFINITY;
    for &start in &candidates {
        let mut score = -0.08 * (latest_end - (start + overlap)) / 1000.0;
        if outro_start < latest_end - 1000.0 {
            score -= 0.15 * (start - outro_start).abs() / 1000.0;
        }
        if a.boundaries_ms.iter().any(|&b| (b as f64 - start).abs() <= 250.0) {
            score += 1.0;
        }
        if let (Some(lock), Some(anchor), true) = (lock_a, phrase_anchor, on_bars) {
            score += 0.6;
            let bars_back = round_half_up((anchor - start) / lock.bar_ms()) as i64;
            if bars_back % 8 == 0 {
                score += 0.8;
            }
        }
        score -= 1.5 * measured.share_at_least(start, start + overlap, full_db);
        if score >= best_score {
            best_score = score;
            best_start = start;
        }
    }

    let mut rate = None;
    if let (true, Some(_), Some(b), Some(ratio)) = (settings.beat_match, lock_a, lock_b, ratio) {
        let gap = (ratio - 1.0).abs();
        if (0.005..=0.04).contains(&gap) {
            rate = Some(ratio.clamp(0.94, 1.06));
            entry = b.downbeat_from(sound_start_b - ENTRY_SNAP_MS).max(0.0);
        }
    }

    let kind = kind_of(overlap, Some(&measured), head, best_start, entry);
    let start = (best_start + 0.5).floor() as i64;
    let entry_ms = (entry + 0.5).floor() as i64;
    let mut reason = format!("{} at {} over {}", kind.name(), seconds(start), seconds(overlap as i64));
    if let (true, Some(a)) = (bars > 0, lock_a) {
        reason += &format!(" ({bars} bars of {} BPM)", decimals(a.display_bpm(), 1));
    }
    reason += &format!(", next song from {}", seconds(entry_ms));
    if lengthened {
        reason += &format!(" (full from {})", seconds((entry + quiet_start) as i64));
    }
    reason += &format!(", outro at {}", seconds(outro_start as i64));
    reason += &format!(", latest end {}", seconds(latest_end as i64));
    if head.is_none() {
        reason += ", no analysis of the next song's start";
    }
    if let Some(r) = rate {
        reason += &format!(", rate {}", decimals(r, 3));
    }
    TransitionPlan {
        start_ms: start,
        entry_ms,
        overlap_ms: overlap as i64,
        kind,
        k: curve_of(kind),
        filter_strength: sweeps,
        beat_match_rate: rate,
        beat_ms: lock_a.map(|a| a.beat_ms),
        beat_anchor_ms: lock_a.map(|a| a.first_beat_ms),
        late: false,
        headroom_db: OVERLAP_HEADROOM_DB,
        reason,
        curve: FadeCurve::EqualPower,
    }
}

/// Whether a genre gets the plain crossfade, never a planned one.
pub fn is_plain_genre(genre: &str) -> bool {
    let lower = genre.to_ascii_lowercase();
    PLAIN_CROSSFADE_GENRES.iter().any(|g| lower.contains(g))
}

// A cut for a short overlap; a lift when the next song's first 8 s are at
// least 3 dB louder than this song through the overlap; else a blend.
fn kind_of(
    overlap: f64,
    tail: Option<&SectionAnalysis>,
    head: Option<&SectionAnalysis>,
    start: f64,
    entry: f64,
) -> TransitionKind {
    if overlap <= CUT_BLEND_MS as f64 {
        return TransitionKind::Cut;
    }
    match (tail, head) {
        (Some(tail), Some(head))
            if head.level_db(entry, entry + 8_000.0) >= tail.level_db(start, start + overlap) + 3.0 =>
        {
            TransitionKind::Lift
        }
        _ => TransitionKind::Blend,
    }
}

fn curve_of(kind: TransitionKind) -> f64 {
    match kind {
        TransitionKind::Cut => CUT_CURVE,
        TransitionKind::Lift => LIFT_CURVE,
        TransitionKind::Blend => BLEND_CURVE,
        _ => CROSSFADE_CURVE,
    }
}

// The blend at the end: ending at latest_end, over `overlap` or whatever is
// left after now_ms, with the curve and filters but no bar lock. Too little
// left to blend plays gaplessly.
#[allow(clippy::too_many_arguments)]
fn late_plan(
    len_a: i64,
    latest_end: f64,
    overlap: f64,
    now_ms: i64,
    entry_ms: i64,
    tail: Option<&SectionAnalysis>,
    head: Option<&SectionAnalysis>,
    sweeps: f64,
    why: &str,
) -> TransitionPlan {
    let start = (now_ms as f64).max(latest_end - overlap);
    let length = (latest_end - start + 0.5).floor();
    if length < SHORTEST_FADE_MS as f64 {
        return gapless_plan(len_a, &format!("too late to blend: {why}"));
    }
    let kind = kind_of(length, tail, head, start, entry_ms as f64);
    let start_ms = (start + 0.5).floor() as i64;
    TransitionPlan {
        start_ms,
        entry_ms,
        overlap_ms: length as i64,
        kind,
        k: curve_of(kind),
        filter_strength: sweeps,
        beat_match_rate: None,
        beat_ms: None,
        beat_anchor_ms: None,
        late: true,
        headroom_db: OVERLAP_HEADROOM_DB,
        reason: format!(
            "late {} at {} over {}, next song from {}: {why}",
            kind.name(),
            seconds(start_ms),
            seconds(length as i64),
            seconds(entry_ms)
        ),
        curve: FadeCurve::EqualPower,
    }
}

fn gapless_plan(len_a: i64, reason: &str) -> TransitionPlan {
    TransitionPlan {
        start_ms: len_a.max(0),
        entry_ms: 0,
        overlap_ms: 0,
        kind: TransitionKind::Gapless,
        k: CROSSFADE_CURVE,
        filter_strength: 0.0,
        beat_match_rate: None,
        beat_ms: None,
        beat_anchor_ms: None,
        late: false,
        headroom_db: 0.0,
        reason: format!("gapless: {reason}"),
        curve: FadeCurve::EqualPower,
    }
}

fn crossfade_plan(len_a: i64, length: i64, why: &str) -> TransitionPlan {
    TransitionPlan {
        start_ms: len_a - length,
        entry_ms: 0,
        overlap_ms: length,
        kind: TransitionKind::Crossfade,
        k: CROSSFADE_CURVE,
        filter_strength: 0.0,
        beat_match_rate: None,
        beat_ms: None,
        beat_anchor_ms: None,
        late: false,
        headroom_db: OVERLAP_HEADROOM_DB,
        reason: format!("crossfade at {} over {}: {why}", seconds(len_a - length), seconds(length)),
        curve: FadeCurve::EqualPower,
    }
}

fn gapless_reason(
    current: &FadeSong,
    next: Option<&FadeSong>,
    fade_ms: i64,
    context: &TransitionContext,
) -> String {
    let why = match next {
        _ if fade_ms <= 0 => "crossfade off",
        None => "nothing next",
        _ if context.repeat_one => "repeat one",
        _ if context.stop_at_end_of_song => "stopping at the end of the song",
        Some(next) if current.duration_ms == 0 || next.duration_ms == 0 => "a song's length is unknown",
        Some(next) if current.album_id.is_some() && current.album_id == next.album_id => {
            "the album plays in order"
        }
        Some(_) => "a song too short to blend",
    };
    why.to_string()
}

/// Milliseconds as seconds with two decimals, like "182.50 s".
pub fn seconds(ms: i64) -> String {
    let sign = if ms < 0 { "-" } else { "" };
    let abs = ms.unsigned_abs();
    format!("{sign}{}.{:02} s", abs / 1000, (abs % 1000) / 10)
}

// A positive number with a fixed count of decimals, like "120.0".
fn decimals(x: f64, places: u32) -> String {
    let scale = 10i64.pow(places);
    let scaled = (x * scale as f64 + 0.5).floor() as i64;
    format!("{}.{:0width$}", scaled / scale, scaled % scale, width = places as usize)
}
