//! Gain curves, filter cutoffs and the tempo-matched rate through a blend.

use std::f64::consts::PI;

/// The curve weight of each kind of transition: how much of the S-shaped
/// curve is mixed into the equal-power one. Higher swaps the songs faster
/// around the middle.
pub const CUT_CURVE: f64 = 0.75;
pub const LIFT_CURVE: f64 = 0.55;
pub const BLEND_CURVE: f64 = 0.2;
pub const CROSSFADE_CURVE: f64 = 0.4;

/// How deep the filter sweeps go, 0 for none and 1 for the full range.
pub const FILTER_STRENGTH: f64 = 0.7;

/// The outgoing song's low-pass runs from `OPEN_LOW_PASS_HZ` down toward
/// `LOW_PASS_FLOOR_HZ`.
pub const OPEN_LOW_PASS_HZ: f64 = 18_000.0;
pub const LOW_PASS_FLOOR_HZ: f64 = 450.0;

/// The outgoing song's bass cut rises from `OPEN_HIGH_PASS_HZ` toward
/// `BASS_SWAP_HZ` by the middle of the blend.
pub const OPEN_HIGH_PASS_HZ: f64 = 10.0;
pub const BASS_SWAP_HZ: f64 = 300.0;
pub const BASS_SWAP_AT: f64 = 0.5;

/// The incoming song's high-pass starts at `INCOMING_HIGH_PASS_HZ` and opens
/// to `INCOMING_OPEN_HZ` by `INCOMING_OPEN_AT` through the blend.
pub const INCOMING_HIGH_PASS_HZ: f64 = 675.0;
pub const INCOMING_OPEN_HZ: f64 = 20.0;
pub const INCOMING_OPEN_AT: f64 = 0.6;

/// After the blend a tempo-matched incoming song eases back to its own
/// speed over this long.
pub const BEAT_MATCH_SETTLE_MS: f64 = 5_000.0;

fn sigmoid12(t: f64) -> f64 {
    1.0 / (1.0 + (-12.0 * (t - 0.5)).exp())
}

/// The S curve scaled to run exactly from 0 at the start to 1 at the end.
pub fn s_curve(t: f64) -> f64 {
    let (low, high) = (sigmoid12(0.0), sigmoid12(1.0));
    (sigmoid12(t.clamp(0.0, 1.0)) - low) / (high - low)
}

/// The outgoing song's volume at `t` through the blend (0 to 1): an
/// equal-power fade mixed with an S curve by weight `k`.
pub fn automix_out_gain(t: f64, k: f64) -> f64 {
    let p = t.clamp(0.0, 1.0);
    ((p * PI / 2.0).cos() * (1.0 - k) + (1.0 - s_curve(p)) * k).clamp(0.0, 1.0)
}

/// The incoming song's volume: whatever keeps the two volumes' squares at one.
pub fn automix_in_gain(t: f64, k: f64) -> f64 {
    let out = automix_out_gain(t, k);
    (1.0 - out * out).max(0.0).sqrt()
}

// Moves from `from` to `to` on a log scale as u goes from 0 to 1.
fn log_between(from: f64, to: f64, u: f64) -> f64 {
    from * (to / from).powf(u.clamp(0.0, 1.0))
}

/// The outgoing song's low-pass cutoff in Hz at `t`, falling smoothly.
pub fn outgoing_low_pass_hz(t: f64, strength: f64) -> f64 {
    let end = OPEN_LOW_PASS_HZ * (LOW_PASS_FLOOR_HZ / OPEN_LOW_PASS_HZ).powf(strength.clamp(0.0, 1.0));
    log_between(OPEN_LOW_PASS_HZ, end, t)
}

/// The same low-pass moving in steps on the beat: it holds each beat's
/// cutoff until `glide` before the next beat, then glides to the next one.
/// `beats` are the beats' places through the blend (0 to 1, rising) and
/// `glide` is in the same units.
pub fn stepped_outgoing_low_pass_hz(t: f64, strength: f64, beats: &[f64], glide: f64) -> f64 {
    let p = t.clamp(0.0, 1.0);
    let mut from = 0.0;
    let mut to = 1.0;
    for &beat in beats {
        if beat <= 0.0 || beat >= 1.0 {
            continue;
        }
        if beat <= p {
            from = beat;
        } else {
            to = beat;
            break;
        }
    }
    let g = glide.max(0.0).min(to - from);
    let glide_start = to - g;
    let at = if p < glide_start || g <= 0.0 { from } else { from + (p - glide_start) / g * (to - from) };
    outgoing_low_pass_hz(at, strength)
}

/// The outgoing song's bass cut in Hz at `t`: rises to its top by the
/// middle of the blend and holds there.
pub fn outgoing_high_pass_hz(t: f64, strength: f64) -> f64 {
    let top = OPEN_HIGH_PASS_HZ.max(BASS_SWAP_HZ * strength.clamp(0.0, 1.0));
    log_between(OPEN_HIGH_PASS_HZ, top, t / BASS_SWAP_AT)
}

/// The incoming song's high-pass cutoff in Hz at `t`: thin at first, fully
/// open by `INCOMING_OPEN_AT`.
pub fn incoming_high_pass_hz(t: f64, strength: f64) -> f64 {
    let start = INCOMING_OPEN_HZ.max(INCOMING_HIGH_PASS_HZ * strength.clamp(0.0, 1.0));
    log_between(start, INCOMING_OPEN_HZ, t / INCOMING_OPEN_AT)
}

/// The incoming song's playback rate `since_entry_ms` after it came in:
/// `rate` through the blend, then eased back to 1 over
/// [`BEAT_MATCH_SETTLE_MS`].
pub fn beat_match_rate_at(rate: f64, since_entry_ms: f64, overlap_ms: f64) -> f64 {
    if since_entry_ms <= overlap_ms {
        return rate;
    }
    let u = (since_entry_ms - overlap_ms) / BEAT_MATCH_SETTLE_MS;
    if u >= 1.0 {
        return 1.0;
    }
    rate + (1.0 - rate) * (1.0 - (PI * u).cos()) / 2.0
}

/// The shape of the fixed crossfade: how the outgoing song's volume falls
/// and the incoming song's rises as the blend goes from 0 to 1.
#[derive(Clone, Copy, Debug, Default, PartialEq, Eq, uniffi::Enum)]
pub enum FadeCurve {
    /// cos and sin: the two songs together keep a steady loudness.
    #[default]
    EqualPower,
    /// Straight lines, with a slight dip in the middle.
    Linear,
    /// Holds each song longer, then swaps them quickly around the middle.
    SCurve,
    /// The same step down in decibels every moment, to -60 dB, then silence.
    EvenLoudness,
    /// Both songs play at full volume; only the edges fade.
    MixOnly,
}

/// Even in loudness falls in a straight line in decibels to this level...
pub const EVEN_LOUDNESS_FLOOR_DB: f64 = -60.0;

/// ...reached at this point of the blend, then goes straight to silence.
pub const EVEN_LOUDNESS_FLOOR_AT: f64 = 0.95;

/// Mix only fades the incoming song in over this long at the start and the
/// outgoing one out over this long at the end, each at most half the blend.
pub const MIX_ONLY_EDGE_MS: f64 = 300.0;

/// Both songs play this much quieter through a mix only blend, so their
/// sum keeps clear of clipping.
pub const MIX_ONLY_HEADROOM_DB: f64 = 3.0;

/// The headroom a fixed crossfade with `curve` plays with.
pub fn fade_headroom_db(curve: FadeCurve) -> f64 {
    if curve == FadeCurve::MixOnly { MIX_ONLY_HEADROOM_DB } else { 0.0 }
}

// The share of a mix only blend `overlap_ms` long that each edge takes.
fn mix_only_edge(overlap_ms: f64) -> f64 {
    if overlap_ms <= 0.0 { 0.5 } else { (MIX_ONLY_EDGE_MS / overlap_ms).min(0.5) }
}

// The even in loudness volume at `p`, falling from 1 to 0.
fn even_loudness_fall(p: f64) -> f64 {
    let floor = 10f64.powf(EVEN_LOUDNESS_FLOOR_DB / 20.0);
    if p <= EVEN_LOUDNESS_FLOOR_AT {
        10f64.powf(EVEN_LOUDNESS_FLOOR_DB * p / EVEN_LOUDNESS_FLOOR_AT / 20.0)
    } else {
        floor * (1.0 - p) / (1.0 - EVEN_LOUDNESS_FLOOR_AT)
    }
}

/// The outgoing song's volume at `t` (0 to 1) through a blend
/// `overlap_ms` long. Equal power is exactly [`automix_out_gain`] with no
/// curve weight.
pub fn fade_out_gain(curve: FadeCurve, t: f64, overlap_ms: f64) -> f64 {
    let p = t.clamp(0.0, 1.0);
    let gain = match curve {
        FadeCurve::EqualPower => automix_out_gain(p, 0.0),
        FadeCurve::Linear => 1.0 - p,
        FadeCurve::SCurve => 1.0 - s_curve(p),
        FadeCurve::EvenLoudness => even_loudness_fall(p),
        FadeCurve::MixOnly => {
            let edge = mix_only_edge(overlap_ms);
            let from = 1.0 - edge;
            if p <= from {
                1.0
            } else if p >= 1.0 {
                0.0
            } else {
                ((p - from) / edge * PI / 2.0).cos()
            }
        }
    };
    gain.clamp(0.0, 1.0)
}

/// The incoming song's volume at `t` through a blend `overlap_ms` long.
pub fn fade_in_gain(curve: FadeCurve, t: f64, overlap_ms: f64) -> f64 {
    let p = t.clamp(0.0, 1.0);
    let gain = match curve {
        FadeCurve::EqualPower => automix_in_gain(p, 0.0),
        FadeCurve::Linear => p,
        // Whatever keeps the two volumes' squares at one.
        FadeCurve::SCurve => {
            let out = 1.0 - s_curve(p);
            (1.0 - out * out).max(0.0).sqrt()
        }
        FadeCurve::EvenLoudness => even_loudness_fall(1.0 - p),
        FadeCurve::MixOnly => {
            let edge = mix_only_edge(overlap_ms);
            if p >= edge { 1.0 } else { (p / edge * PI / 2.0).sin() }
        }
    };
    gain.clamp(0.0, 1.0)
}

/// Both volumes at once: outgoing, then incoming.
pub fn fade_gains(curve: FadeCurve, t: f64, overlap_ms: f64) -> (f64, f64) {
    (fade_out_gain(curve, t, overlap_ms), fade_in_gain(curve, t, overlap_ms))
}

/// The gains of a blend at `t`: the automix curve with weight `k` for
/// equal power (`k = 0` being the plain equal-power crossfade), otherwise
/// the fixed crossfade's `curve`.
pub fn blend_gains(curve: FadeCurve, k: f64, t: f64, overlap_ms: f64) -> (f64, f64) {
    match curve {
        FadeCurve::EqualPower => (automix_out_gain(t, k), automix_in_gain(t, k)),
        other => fade_gains(other, t, overlap_ms),
    }
}
