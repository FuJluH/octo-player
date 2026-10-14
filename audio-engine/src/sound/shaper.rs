//! The shaping chain after the mix, as in the Android app's `SoundShaper`:
//! the equalizer's preamp, its filters, crossfeed, mono and balance, then
//! the limiter.
//! ReplayGain is applied per song before the mix (see `lane.rs`), so each
//! song keeps its own level through a crossfade.

use super::biquad::FilterBank;
use super::crossfeed::{
    CrossfeedCoefficients, CrossfeedFilter, MAX_CUT_HZ, MAX_FEED_DB, MIN_CUT_HZ, MIN_FEED_DB,
};
use super::limiter::Limiter;
use super::model::{SoundSettings, band_coefficients};

/// How long a change of level, balance or curve takes, so it never clicks.
pub const GLIDE_MS: f32 = 30.0;

/// A value that glides to a new setting over a number of frames.
#[derive(Clone, Debug)]
pub struct Glide {
    value: f32,
    target: f32,
    step: f32,
    left: usize,
}

impl Glide {
    pub fn new(initial: f32) -> Self {
        Self { value: initial, target: initial, step: 0.0, left: 0 }
    }

    pub fn value(&self) -> f32 {
        self.value
    }

    pub fn moving(&self) -> bool {
        self.left > 0
    }

    pub fn to(&mut self, next: f32, frames: usize) {
        self.target = next;
        if frames == 0 || next == self.value {
            self.value = next;
            self.left = 0;
        } else {
            self.step = (next - self.value) / frames as f32;
            self.left = frames;
        }
    }

    #[inline]
    pub fn advance(&mut self) -> f32 {
        if self.left > 0 {
            self.left -= 1;
            self.value = if self.left == 0 { self.target } else { self.value + self.step };
        }
        self.value
    }
}

/// The shaping for one continuous stream. Samples are floats, interleaved,
/// full scale at 1.
pub struct SoundShaper {
    sample_rate: u32,
    channels: usize,
    glide_frames: usize,
    gain: Glide,
    left: Glide,
    right: Glide,
    mono: Glide,
    bank: FilterBank,
    // While the curve changes, the old filters keep running and fade out.
    fading_from: Option<FilterBank>,
    fade_left: usize,
    fade_scratch: Vec<f32>,
    crossfeed: CrossfeedFilter,
    limiter: Limiter,
    // Whether the settings turn the limiter on, and whether the sound would
    // pass through untouched without it.
    limiter_on: bool,
    untouched: bool,
    blending: bool,
    started: bool,
    output: Vec<f32>,
}

impl SoundShaper {
    pub fn new(sample_rate: u32, channels: usize) -> Self {
        let glide_frames = ((sample_rate as f32 * GLIDE_MS / 1_000.0).round() as usize).max(1);
        Self {
            sample_rate,
            channels,
            glide_frames,
            gain: Glide::new(1.0),
            left: Glide::new(1.0),
            right: Glide::new(1.0),
            mono: Glide::new(0.0),
            bank: FilterBank::new(channels, Vec::new()),
            fading_from: None,
            fade_left: 0,
            fade_scratch: Vec::new(),
            crossfeed: CrossfeedFilter::new(),
            limiter: Limiter::new(channels, sample_rate),
            limiter_on: true,
            untouched: true,
            blending: false,
            started: false,
            output: Vec::new(),
        }
    }

    /// How many frames late the sound comes out.
    pub fn latency(&self) -> usize {
        self.limiter.latency()
    }

    pub fn limiter_enabled(&self) -> bool {
        self.limiter.enabled
    }

    /// Takes up new settings. Changes glide in, unless `instant`.
    /// `song_gain` is the ReplayGain factor of the song playing now; it only
    /// decides whether the sound is touched at all, as on Android.
    pub fn apply(&mut self, settings: &SoundSettings, song_gain: f32, instant: bool) {
        let now = instant || !self.started;
        self.started = true;
        let frames = if now { 0 } else { self.glide_frames };

        let bands = band_coefficients(&settings.active_filters(), self.sample_rate);
        if bands != self.bank.coefficients() {
            let mut next = FilterBank::new(self.channels, bands.clone());
            next.continue_from(&self.bank);
            let old = std::mem::replace(&mut self.bank, next);
            self.fading_from = if now { None } else { Some(old) };
            self.fade_left = if now { 0 } else { self.glide_frames };
        }

        let preamp = 10f32.powf(settings.effective_preamp_db(self.sample_rate) / 20.0);
        self.gain.to(preamp, frames);

        let stereo = self.channels >= 2;
        let balance = if stereo { settings.dsp.balance.clamp(-1.0, 1.0) } else { 0.0 };
        self.left.to(if balance > 0.0 { 1.0 - balance } else { 1.0 }, frames);
        self.right.to(if balance < 0.0 { 1.0 + balance } else { 1.0 }, frames);
        let to_mono = stereo && settings.dsp.mono;
        self.mono.to(if to_mono { 1.0 } else { 0.0 }, frames);

        // Crossfeed blends the two sides, so it has nothing to do in mono.
        let feed = &settings.dsp.crossfeed;
        let crossfeed_on = stereo && feed.on && !to_mono;
        let coefficients = CrossfeedCoefficients::new(
            feed.cut_hz.clamp(MIN_CUT_HZ, MAX_CUT_HZ) as f64,
            feed.feed_db.clamp(MIN_FEED_DB, MAX_FEED_DB) as f64,
            self.sample_rate,
        );
        self.crossfeed.set(coefficients, crossfeed_on, frames);

        // Sound that is left as it is passes through untouched; the limiter
        // only catches peaks the shaping could push over.
        self.untouched =
            bands.is_empty() && preamp * song_gain == 1.0 && balance == 0.0 && !to_mono && !crossfeed_on;
        self.limiter_on = settings.dsp.limiter;
        self.follow_limiter();
    }

    /// Says whether two songs sound together. Their sum can pass full scale
    /// even when each passes through untouched, so while they blend the
    /// limiter runs whenever the settings have it on.
    pub fn set_blending(&mut self, blending: bool) {
        if blending != self.blending {
            self.blending = blending;
            self.follow_limiter();
        }
    }

    fn follow_limiter(&mut self) {
        self.limiter.enabled = self.limiter_on && (!self.untouched || self.blending);
    }

    /// Shapes `frames` frames of `samples` in place. The limiter's delay
    /// means the frames that come out are `latency` frames old; the first
    /// `latency` frames of a fresh stream come out as silence, so the frame
    /// count never changes.
    pub fn process(&mut self, samples: &mut [f32], frames: usize) {
        let count = frames * self.channels;
        self.apply_gain(samples, frames);
        self.apply_filters(samples, frames);
        self.crossfeed.process(samples, frames, self.channels);
        self.apply_mix(samples, frames);
        if self.output.len() < count {
            self.output.resize(count, 0.0);
        }
        let written = self.limiter.process(&samples[..count], frames, &mut self.output);
        // While the delay fills, pad the front with silence so every call
        // hands back as many frames as it took.
        let missing = (frames - written) * self.channels;
        samples[..missing].fill(0.0);
        samples[missing..count].copy_from_slice(&self.output[..written * self.channels]);
    }

    /// Forgets the sound held back, after a jump to another place.
    pub fn clear_held(&mut self) {
        self.limiter.clear();
    }

    fn apply_gain(&mut self, samples: &mut [f32], frames: usize) {
        if !self.gain.moving() && self.gain.value() == 1.0 {
            return;
        }
        for frame in samples[..frames * self.channels].chunks_exact_mut(self.channels) {
            let g = self.gain.advance();
            for s in frame {
                *s *= g;
            }
        }
    }

    fn apply_filters(&mut self, samples: &mut [f32], frames: usize) {
        let Some(old) = self.fading_from.as_mut() else {
            self.bank.process(samples, frames);
            return;
        };
        let count = frames * self.channels;
        if self.fade_scratch.len() < count {
            self.fade_scratch.resize(count, 0.0);
        }
        self.fade_scratch[..count].copy_from_slice(&samples[..count]);
        old.process(&mut self.fade_scratch, frames);
        self.bank.process(samples, frames);
        let glide = self.glide_frames as f32;
        for (frame, faded) in samples[..count]
            .chunks_exact_mut(self.channels)
            .zip(self.fade_scratch[..count].chunks_exact(self.channels))
        {
            let w = if self.fade_left > 0 { 1.0 - self.fade_left as f32 / glide } else { 1.0 };
            if self.fade_left > 0 {
                self.fade_left -= 1;
            }
            for (s, f) in frame.iter_mut().zip(faded) {
                *s = f + (*s - f) * w;
            }
        }
        if self.fade_left == 0 {
            self.fading_from = None;
        }
    }

    fn apply_mix(&mut self, samples: &mut [f32], frames: usize) {
        if self.channels < 2 {
            return;
        }
        let still = !self.mono.moving() && !self.left.moving() && !self.right.moving();
        if still && self.mono.value() == 0.0 && self.left.value() == 1.0 && self.right.value() == 1.0 {
            return;
        }
        let channels = self.channels;
        for frame in samples[..frames * channels].chunks_exact_mut(channels) {
            let m = self.mono.advance();
            if m != 0.0 {
                let average = frame.iter().sum::<f32>() / channels as f32;
                for s in frame.iter_mut() {
                    *s += (average - *s) * m;
                }
            }
            frame[0] *= self.left.advance();
            frame[1] *= self.right.advance();
        }
    }
}
