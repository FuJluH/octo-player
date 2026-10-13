//! The sound settings and the filter maths, matching the Android app's
//! `SoundModel.kt` so a curve sounds the same on both.

use std::f64::consts::PI;

/// The shapes a filter can take: a bump or dip around one frequency, or a
/// lift or cut of everything below or above one.
#[derive(Clone, Copy, Debug, PartialEq, Eq, uniffi::Enum)]
pub enum FilterType {
    Peak,
    LowShelf,
    HighShelf,
}

/// One equalizer filter. `q` is the width, as in the Audio EQ Cookbook.
#[derive(Clone, Debug, PartialEq, uniffi::Record)]
pub struct EqFilter {
    pub filter_type: FilterType,
    pub frequency: f32,
    pub gain_db: f32,
    pub q: f32,
    pub enabled: bool,
}

impl EqFilter {
    pub fn peak(frequency: f32, gain_db: f32, q: f32) -> Self {
        Self { filter_type: FilterType::Peak, frequency, gain_db, q, enabled: true }
    }
}

/// Ten sliders at fixed frequencies, or filters moved freely on the curve.
#[derive(Clone, Copy, Debug, PartialEq, Eq, uniffi::Enum)]
pub enum EqMode {
    Graphic,
    Parametric,
}

/// Evening out loudness between songs: off, per song, per album, or per
/// album only while an album plays in order.
#[derive(Clone, Copy, Debug, PartialEq, Eq, uniffi::Enum)]
pub enum ReplayGainMode {
    Off,
    Track,
    Album,
    Smart,
}

/// The ten standard octave bands, in hertz.
pub const GRAPHIC_BANDS: [f32; 10] =
    [31.0, 62.0, 125.0, 250.0, 500.0, 1_000.0, 2_000.0, 4_000.0, 8_000.0, 16_000.0];

/// The width of one octave band.
pub const GRAPHIC_Q: f32 = 1.41;

/// Filters at or above this share of the sample rate are left out: the
/// formulas bend out of shape that close to the top of the range.
pub const HIGHEST_BAND_SHARE: f32 = 0.45;

/// A correction for one model of headphones, made from its measurements.
#[derive(Clone, Debug, PartialEq, uniffi::Record)]
pub struct HeadphoneCorrection {
    pub name: String,
    /// Who measured them, for the credit line.
    pub source: String,
    pub preamp_db: f32,
    pub filters: Vec<EqFilter>,
}

/// The equalizer part of the sound settings.
#[derive(Clone, Debug, PartialEq, uniffi::Record)]
pub struct EqSettings {
    pub enabled: bool,
    pub mode: EqMode,
    /// One gain per graphic band, in decibels.
    pub graphic_gains: Vec<f32>,
    pub filters: Vec<EqFilter>,
    pub preamp_db: f32,
    /// Lowers the level by the curve's highest boost, so boosting never clips.
    pub auto_preamp: bool,
    pub correction: Option<HeadphoneCorrection>,
}

impl Default for EqSettings {
    fn default() -> Self {
        Self {
            enabled: false,
            mode: EqMode::Graphic,
            graphic_gains: vec![0.0; GRAPHIC_BANDS.len()],
            filters: Vec::new(),
            preamp_db: 0.0,
            auto_preamp: true,
            correction: None,
        }
    }
}

/// The loudness levelling part of the sound settings.
#[derive(Clone, Debug, PartialEq, uniffi::Record)]
pub struct ReplayGainSettings {
    pub mode: ReplayGainMode,
    pub preamp_db: f32,
    /// For songs with no loudness tags.
    pub fallback_db: f32,
    pub prevent_clipping: bool,
}

impl Default for ReplayGainSettings {
    fn default() -> Self {
        Self { mode: ReplayGainMode::Off, preamp_db: 0.0, fallback_db: 0.0, prevent_clipping: true }
    }
}

/// Headphone crossfeed: each ear hears a little of the other side.
#[derive(Clone, Debug, PartialEq, uniffi::Record)]
pub struct CrossfeedSettings {
    pub on: bool,
    /// Where the sound fed to the other ear has fallen by 3 dB, 300 to
    /// 2000 Hz.
    pub cut_hz: f32,
    /// How much quieter than the ear's own sound the other side is in the
    /// bass, 1 to 15 dB.
    pub feed_db: f32,
}

impl Default for CrossfeedSettings {
    fn default() -> Self {
        Self { on: false, cut_hz: 700.0, feed_db: 4.5 }
    }
}

/// The rest of the shaping: crossfeed, the limiter, balance and mono.
#[derive(Clone, Debug, PartialEq, uniffi::Record)]
pub struct DspSettings {
    /// Catches any peak that would still clip, just below full scale.
    pub limiter: bool,
    /// From -1 (all left) to 1 (all right).
    pub balance: f32,
    pub mono: bool,
    pub crossfeed: CrossfeedSettings,
}

impl Default for DspSettings {
    fn default() -> Self {
        Self { limiter: true, balance: 0.0, mono: false, crossfeed: CrossfeedSettings::default() }
    }
}

/// Everything that shapes the sound.
#[derive(Clone, Debug, Default, PartialEq)]
pub struct SoundSettings {
    pub eq: EqSettings,
    pub replay_gain: ReplayGainSettings,
    pub dsp: DspSettings,
}

impl SoundSettings {
    /// The filters the equalizer applies now: the headphone correction
    /// first, then the listener's own curve.
    pub fn active_filters(&self) -> Vec<EqFilter> {
        if !self.eq.enabled {
            return Vec::new();
        }
        let own: Vec<EqFilter> = match self.eq.mode {
            EqMode::Graphic => GRAPHIC_BANDS
                .iter()
                .zip(self.eq.graphic_gains.iter())
                .map(|(&f, &g)| EqFilter::peak(f, g, GRAPHIC_Q))
                .collect(),
            EqMode::Parametric => self.eq.filters.clone(),
        };
        let correction = self.eq.correction.as_ref().map(|c| c.filters.clone()).unwrap_or_default();
        correction.into_iter().chain(own).filter(|f| f.enabled && f.gain_db != 0.0).collect()
    }

    /// The level change before the filters, in decibels: set by hand (with
    /// a headphone correction's own preamp), or just enough to take back the
    /// curve's highest boost.
    pub fn effective_preamp_db(&self, sample_rate: u32) -> f32 {
        if !self.eq.enabled {
            return 0.0;
        }
        if self.eq.auto_preamp {
            -peak_db(&self.active_filters(), sample_rate).max(0.0)
        } else {
            self.eq.correction.as_ref().map(|c| c.preamp_db).unwrap_or(0.0) + self.eq.preamp_db
        }
    }
}

/// A named curve for the ten bands.
#[derive(Clone, Debug, PartialEq, uniffi::Record)]
pub struct EqPreset {
    pub name: String,
    pub gains: Vec<f32>,
}

/// The built-in curves, the same as the Android app's.
pub fn eq_presets() -> Vec<EqPreset> {
    const PRESETS: [(&str, [f32; 10]); 19] = [
        ("Flat", [0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0, 0.0]),
        ("Bass Boost", [6.0, 5.5, 4.5, 2.5, 0.5, 0.0, 0.0, 0.0, 0.0, 0.0]),
        ("Bass Reducer", [-6.0, -5.0, -4.0, -2.5, -1.0, 0.0, 0.0, 0.0, 0.0, 0.0]),
        ("Treble Boost", [0.0, 0.0, 0.0, 0.0, 0.0, 0.5, 1.5, 3.5, 5.0, 6.0]),
        ("Treble Reducer", [0.0, 0.0, 0.0, 0.0, 0.0, -0.5, -1.5, -3.5, -5.0, -6.0]),
        ("Vocal", [-2.0, -2.0, -1.0, 0.5, 2.0, 3.5, 3.5, 2.5, 1.0, 0.0]),
        ("Rock", [5.0, 5.0, 4.0, 3.0, 0.5, -0.5, 1.5, 3.0, 4.0, 5.0]),
        ("Pop", [-1.0, -1.0, 0.5, 2.0, 3.5, 4.5, 2.5, 1.0, -1.0, -2.0]),
        ("Jazz", [4.0, 4.0, 3.0, 2.0, -0.5, -1.5, 0.5, 2.0, 4.0, 5.0]),
        ("Classical", [5.0, 5.0, 4.0, 2.5, 0.0, -1.5, 1.5, 4.0, 4.0, 4.0]),
        ("Electronic", [6.0, 6.0, 2.5, 0.0, 1.0, 2.0, 3.0, 4.0, 2.0, 1.0]),
        ("Hip-Hop", [5.0, 5.0, 4.0, 3.0, 1.5, 0.0, 0.5, 1.0, 2.0, 3.0]),
        ("Metal", [4.0, 4.0, 2.5, 1.5, 5.5, 8.5, 5.5, 3.0, 1.0, 0.0]),
        ("Folk", [3.0, 3.0, 1.5, 0.0, 0.0, 0.0, 1.0, 2.0, 0.0, -1.0]),
        ("Acoustic", [3.0, 3.0, 2.5, 1.0, 1.0, 0.5, 1.5, 2.5, 2.5, 1.5]),
        ("Loudness", [6.0, 5.0, 3.0, 1.0, 0.0, 0.0, 0.0, 1.0, 3.0, 4.0]),
        ("Late Night", [-4.0, -3.0, -1.5, 0.0, 0.5, 1.0, 2.0, 1.5, 0.0, -1.0]),
        ("Spoken Word", [-6.0, -5.0, -3.0, -1.0, 1.0, 2.5, 3.5, 2.5, 0.0, -2.0]),
        ("Small Speakers", [-6.0, -3.0, 2.0, 3.0, 1.5, 0.0, 0.0, 1.5, 2.5, 1.0]),
    ];
    PRESETS
        .iter()
        .map(|(name, gains)| EqPreset { name: (*name).to_string(), gains: gains.to_vec() })
        .collect()
}

/// One filter's coefficients, normalised so a0 is 1.
#[derive(Clone, Copy, Debug, PartialEq)]
pub struct Coefficients {
    pub b0: f64,
    pub b1: f64,
    pub b2: f64,
    pub a1: f64,
    pub a2: f64,
}

impl crate::automix::Biquad {
    /// The same coefficients for a filter bank.
    pub fn coefficients(&self) -> Coefficients {
        Coefficients { b0: self.b0, b1: self.b1, b2: self.b2, a1: self.a1, a2: self.a2 }
    }
}

/// The standard formulas for these filters (the Audio EQ Cookbook).
pub fn coefficients(filter: &EqFilter, sample_rate: u32) -> Coefficients {
    let a = 10f64.powf(filter.gain_db as f64 / 40.0);
    let w0 = 2.0 * PI * filter.frequency as f64 / sample_rate as f64;
    let c = w0.cos();
    let alpha = w0.sin() / (2.0 * filter.q as f64);
    match filter.filter_type {
        FilterType::Peak => {
            normalise(1.0 + alpha * a, -2.0 * c, 1.0 - alpha * a, 1.0 + alpha / a, -2.0 * c, 1.0 - alpha / a)
        }
        FilterType::LowShelf => {
            let s = 2.0 * a.sqrt() * alpha;
            normalise(
                a * ((a + 1.0) - (a - 1.0) * c + s),
                2.0 * a * ((a - 1.0) - (a + 1.0) * c),
                a * ((a + 1.0) - (a - 1.0) * c - s),
                (a + 1.0) + (a - 1.0) * c + s,
                -2.0 * ((a - 1.0) + (a + 1.0) * c),
                (a + 1.0) + (a - 1.0) * c - s,
            )
        }
        FilterType::HighShelf => {
            let s = 2.0 * a.sqrt() * alpha;
            normalise(
                a * ((a + 1.0) + (a - 1.0) * c + s),
                -2.0 * a * ((a - 1.0) + (a + 1.0) * c),
                a * ((a + 1.0) + (a - 1.0) * c - s),
                (a + 1.0) - (a - 1.0) * c + s,
                2.0 * ((a - 1.0) - (a + 1.0) * c),
                (a + 1.0) - (a - 1.0) * c - s,
            )
        }
    }
}

/// A second-order low-pass or high-pass (Butterworth, Q 0.7071) at
/// `frequency`, kept below the top of the range.
pub fn pass_coefficients(high_pass: bool, frequency: f32, sample_rate: u32) -> Coefficients {
    let frequency = (frequency as f64).clamp(1.0, sample_rate as f64 * 0.45);
    let w0 = 2.0 * PI * frequency / sample_rate as f64;
    let c = w0.cos();
    let alpha = w0.sin() / (2.0 * std::f64::consts::FRAC_1_SQRT_2);
    if high_pass {
        normalise((1.0 + c) / 2.0, -(1.0 + c), (1.0 + c) / 2.0, 1.0 + alpha, -2.0 * c, 1.0 - alpha)
    } else {
        normalise((1.0 - c) / 2.0, 1.0 - c, (1.0 - c) / 2.0, 1.0 + alpha, -2.0 * c, 1.0 - alpha)
    }
}

fn normalise(b0: f64, b1: f64, b2: f64, a0: f64, a1: f64, a2: f64) -> Coefficients {
    Coefficients { b0: b0 / a0, b1: b1 / a0, b2: b2 / a0, a1: a1 / a0, a2: a2 / a0 }
}

/// The coefficients to run for these filters at this sample rate, leaving
/// out any too close to the top of the range.
pub fn band_coefficients(filters: &[EqFilter], sample_rate: u32) -> Vec<Coefficients> {
    filters
        .iter()
        .filter(|f| f.frequency < sample_rate as f32 * HIGHEST_BAND_SHARE)
        .map(|f| coefficients(f, sample_rate))
        .collect()
}

/// Log-spaced frequencies from 20 Hz to 20 kHz.
pub fn response_frequencies(points: usize) -> Vec<f32> {
    let last = (points.max(2) - 1) as f64;
    (0..points).map(|i| (20.0 * 1_000f64.powf(i as f64 / last)) as f32).collect()
}

/// The change in decibels these filters make at one frequency.
pub fn response_db(filters: &[EqFilter], frequency: f32, sample_rate: u32) -> f32 {
    filters
        .iter()
        .filter(|f| f.frequency < sample_rate as f32 * HIGHEST_BAND_SHARE)
        .map(|f| magnitude_db(&coefficients(f, sample_rate), frequency, sample_rate))
        .sum::<f64>() as f32
}

/// The highest boost anywhere on the curve.
pub fn peak_db(filters: &[EqFilter], sample_rate: u32) -> f32 {
    if filters.is_empty() {
        return 0.0;
    }
    response_frequencies(512)
        .into_iter()
        .map(|f| response_db(filters, f, sample_rate))
        .fold(f32::NEG_INFINITY, f32::max)
}

/// A filter's level change at one frequency, from its coefficients.
pub fn magnitude_db(k: &Coefficients, frequency: f32, sample_rate: u32) -> f64 {
    let phi = (PI * frequency as f64 / sample_rate as f64).sin().powi(2);
    let part = |x0: f64, x1: f64, x2: f64| {
        (x0 + x1 + x2).powi(2) - 4.0 * (x0 * x1 + 4.0 * x0 * x2 + x1 * x2) * phi + 16.0 * x0 * x2 * phi * phi
    };
    let num = part(k.b0, k.b1, k.b2);
    let den = part(1.0, k.a1, k.a2);
    10.0 * (num / den).log10()
}
