//! Headphone crossfeed: each ear hears a little of the other side, low
//! frequencies most, as with speakers in a room.
//!
//! One first-order low-pass runs on the difference between the two sides:
//!
//! ```text
//! d[n]  = gain * (R[n] - L[n]) + pole * d[n - 1]
//! L'[n] = L[n] + d[n]
//! R'[n] = R[n] - d[n]
//! ```
//!
//! So each ear gets the other side through a low-pass at the cut frequency,
//! and its own side through the matching high shelf (one minus that
//! low-pass). In the bass the other side arrives `feed_db` below the ear's
//! own; sound in the middle (the same in both ears) passes through exactly
//! as it was, so the overall tone and a full-scale mono signal stay level.

use std::f64::consts::PI;

/// The range of the cut frequency, in hertz, and of the feed level, in
/// decibels.
pub const MIN_CUT_HZ: f32 = 300.0;
pub const MAX_CUT_HZ: f32 = 2_000.0;
pub const MIN_FEED_DB: f32 = 1.0;
pub const MAX_FEED_DB: f32 = 15.0;

/// The filter's coefficients for one sample rate.
#[derive(Clone, Copy, Debug, Default, PartialEq)]
pub struct CrossfeedCoefficients {
    pub gain: f64,
    pub pole: f64,
}

impl CrossfeedCoefficients {
    /// The filter for a cut frequency (where the sound fed to the other ear
    /// has fallen by 3 dB) and a feed level (how much quieter than the
    /// ear's own sound the other side is in the bass).
    pub fn new(cut_hz: f64, feed_db: f64, sample_rate: u32) -> Self {
        let pole = (-2.0 * PI * cut_hz / sample_rate as f64).exp();
        let feed = 10f64.powf(-feed_db / 20.0);
        // The bass shares of the ear's own side and of the other side add
        // up to one, the other side's being `feed` times the own side's.
        let low_share = feed / (1.0 + feed);
        Self { gain: low_share * (1.0 - pole), pole }
    }

    /// The other ear's share of a side in the bass.
    pub fn low_share(&self) -> f64 {
        self.gain / (1.0 - self.pole)
    }

    /// How loud one side comes out at `frequency`, in decibels: in its own
    /// ear, then in the other ear.
    pub fn response_db(&self, frequency: f64, sample_rate: u32) -> (f64, f64) {
        let w = 2.0 * PI * frequency / sample_rate as f64;
        let den = 1.0 - 2.0 * self.pole * w.cos() + self.pole * self.pole;
        let other = self.gain * self.gain / den;
        let re = 1.0 - self.gain - self.pole * w.cos();
        let im = self.pole * w.sin();
        let own = (re * re + im * im) / den;
        (10.0 * own.log10(), 10.0 * other.log10())
    }
}

// State this small is set to zero, so a fading tail never slows the
// processor down with tiny numbers.
const TINY: f64 = 1e-25;

/// The crossfeed for one stream: the first two channels of interleaved
/// float samples, changed in place. Turning it on or off fades it in or out
/// over a number of frames; a new cut or feed level carries on from the
/// filter's state, so neither clicks.
#[derive(Clone, Debug, Default)]
pub struct CrossfeedFilter {
    coefficients: CrossfeedCoefficients,
    state: f64,
    mix: f64,
    target: f64,
    step: f64,
    left: usize,
}

impl CrossfeedFilter {
    pub fn new() -> Self {
        Self::default()
    }

    pub fn coefficients(&self) -> CrossfeedCoefficients {
        self.coefficients
    }

    /// Whether there is anything to do: on, or fading.
    pub fn active(&self) -> bool {
        self.mix != 0.0 || self.left > 0
    }

    /// Takes up new coefficients, and fades to on or off over `frames`.
    pub fn set(&mut self, coefficients: CrossfeedCoefficients, on: bool, frames: usize) {
        self.coefficients = coefficients;
        let next = if on { 1.0 } else { 0.0 };
        if next == self.target && (self.left > 0 || self.mix == next) {
            return;
        }
        self.target = next;
        if frames == 0 || self.mix == next {
            self.mix = next;
            self.left = 0;
        } else {
            self.step = (next - self.mix) / frames as f64;
            self.left = frames;
        }
        if !self.active() {
            self.state = 0.0;
        }
    }

    pub fn process(&mut self, samples: &mut [f32], frames: usize, channels: usize) {
        if channels < 2 || !self.active() {
            return;
        }
        let CrossfeedCoefficients { gain, pole } = self.coefficients;
        let mut d = self.state;
        for frame in samples[..frames * channels].chunks_exact_mut(channels) {
            if self.left > 0 {
                self.left -= 1;
                self.mix = if self.left == 0 { self.target } else { self.mix + self.step };
            }
            let (l, r) = (frame[0] as f64, frame[1] as f64);
            d = gain * (r - l) + pole * d;
            frame[0] = (l + self.mix * d) as f32;
            frame[1] = (r - self.mix * d) as f32;
        }
        self.state = if d.abs() < TINY || !self.active() { 0.0 } else { d };
    }
}
