//! Turns a song into stereo floats at its own sample rate: format guess,
//! decoding with the encoder's delay and padding trimmed (gapless),
//! sample-accurate seeking, and the loudness tags.

use std::sync::{Arc, Mutex, OnceLock};

use rubato::audioadapter_buffers::direct::InterleavedSlice;
use rubato::{Fft, FixedSync, Resampler as _};
use symphonia::core::codecs::CodecParameters;
use symphonia::core::codecs::audio::well_known::CODEC_ID_AAC;
use symphonia::core::codecs::audio::{AudioCodecParameters, AudioDecoder, AudioDecoderOptions};
use symphonia::core::codecs::registry::CodecRegistry;
use symphonia::core::errors::Error as DecodeError;
use symphonia::core::formats::probe::Hint;
use symphonia::core::formats::{FormatOptions, FormatReader, SeekMode, SeekTo, TrackType};
use symphonia::core::io::{MediaSource, MediaSourceStream, MediaSourceStreamOptions};
use symphonia::core::meta::{MetadataOptions, StandardTag};
use symphonia::core::units::{Time, TimeBase};

use crate::error::{ErrorKind, Failure};
use crate::sound::replaygain::{self, ReplayGainInfo};
use crate::source::{Opened, Periods};

// Damaged stretches in a row a live stream may have before it counts as
// broken; each one is passed over.
const LIVE_BAD_READS: u32 = 64;

/// What the decoder found out about a song.
#[derive(Clone, Debug, PartialEq, uniffi::Record)]
pub struct TrackInfo {
    /// Like "flac", "mp3", "aac", "opus".
    pub codec: String,
    pub lossless: bool,
    pub sample_rate: u32,
    pub channels: u32,
    pub bits_per_sample: Option<u32>,
    /// The length, when the file says.
    pub duration_ms: Option<u64>,
    /// The loudness tags in the file.
    pub replay_gain: Option<ReplayGainInfo>,
}

fn codecs() -> &'static CodecRegistry {
    static REGISTRY: OnceLock<CodecRegistry> = OnceLock::new();
    REGISTRY.get_or_init(|| {
        let mut registry = CodecRegistry::new();
        symphonia::default::register_enabled_codecs(&mut registry);
        #[cfg(feature = "opus")]
        registry.register_audio_decoder::<crate::opus::OpusDecoder>();
        registry
    })
}

/// A song being decoded.
pub struct Decoder {
    format: Box<dyn FormatReader>,
    decoder: Box<dyn AudioDecoder>,
    track_id: u32,
    time_base: Option<TimeBase>,
    info: TrackInfo,
    source_channels: usize,
    // Where the next frame handed out sits, in frames from the start.
    position: u64,
    // After a seek: the first frame wanted; earlier ones are dropped.
    skip_until: Option<u64>,
    interleaved: Vec<f32>,
    live: bool,
    hint: Hint,
    remote: bool,
    periods: Option<Box<dyn Periods>>,
    // A live stream that came back at another sample rate, changed back to
    // the one it started at.
    convert: Option<Convert>,
    stereo: Vec<f32>,
    bad_reads: u32,
}

// A format's audio track and its decoder.
struct Track {
    decoder: Box<dyn AudioDecoder>,
    id: u32,
    time_base: Option<TimeBase>,
    sample_rate: u32,
    channels: usize,
    bits_per_sample: Option<u32>,
}

impl Decoder {
    /// Reads the song's header and gets ready to decode.
    pub fn open(opened: Opened) -> Result<Self, Failure> {
        let mut hint = Hint::new();
        if let Some(ext) = &opened.hint {
            hint.with_extension(ext);
        }
        let format = probe(&hint, opened.source, opened.remote)?;
        let mut decoder = Self::with_format(format, hint, opened.remote, opened.live)?;
        decoder.periods = opened.periods;
        if decoder.live {
            // Whatever a live stream's header guesses, it has no end.
            decoder.info.duration_ms = None;
        }
        Ok(decoder)
    }

    fn with_format(
        mut format: Box<dyn FormatReader>,
        hint: Hint,
        remote: bool,
        live: bool,
    ) -> Result<Self, Failure> {
        let track = format
            .default_track(TrackType::Audio)
            .ok_or_else(|| Failure::new(ErrorKind::Unsupported, "no audio track"))?
            .clone();
        let parts = audio_track(format.as_mut(), live)?;
        let sample_rate = parts.sample_rate;
        let short_name = parts.decoder.codec_info().short_name.to_string();
        let lossless = ["flac", "alac", "pcm", "wav"].iter().any(|n| short_name.starts_with(n));
        let duration_ms = track.num_frames.map(|frames| frames * 1_000 / sample_rate as u64).or_else(|| {
            let (tb, dur) = (track.time_base?, track.duration?);
            tb.calc_duration(dur).map(|t| (t.as_secs_f64() * 1_000.0) as u64)
        });
        let info = TrackInfo {
            codec: short_name,
            lossless,
            sample_rate,
            channels: parts.channels as u32,
            bits_per_sample: parts.bits_per_sample,
            duration_ms,
            replay_gain: read_replay_gain(format.as_mut()),
        };
        Ok(Self {
            format,
            decoder: parts.decoder,
            track_id: parts.id,
            time_base: parts.time_base,
            info,
            source_channels: parts.channels,
            position: 0,
            skip_until: None,
            interleaved: Vec::new(),
            live,
            hint,
            remote,
            periods: None,
            convert: None,
            stereo: Vec::new(),
            bad_reads: 0,
        })
    }

    // Takes the format's audio track again, after the stream started it over.
    fn reset_track(&mut self) -> Result<(), Failure> {
        let parts = audio_track(self.format.as_mut(), self.live)?;
        log::info!("the stream's codec started again at {} Hz", parts.sample_rate);
        self.decoder = parts.decoder;
        self.track_id = parts.id;
        self.time_base = parts.time_base;
        self.source_channels = parts.channels;
        self.convert = if parts.sample_rate == self.info.sample_rate {
            None
        } else {
            Some(Convert::new(parts.sample_rate, self.info.sample_rate)?)
        };
        Ok(())
    }

    // Opens the stream's next period, if it has one.
    fn next_period(&mut self) -> Result<bool, Failure> {
        let Some(periods) = &mut self.periods else { return Ok(false) };
        let Some(source) = periods.next()? else { return Ok(false) };
        self.format = probe(&self.hint, source, self.remote)?;
        self.reset_track()?;
        Ok(true)
    }

    pub fn info(&self) -> &TrackInfo {
        &self.info
    }

    pub fn sample_rate(&self) -> u32 {
        self.info.sample_rate
    }

    /// Where the next frame handed out sits, in seconds.
    pub fn position_secs(&self) -> f64 {
        self.position as f64 / self.info.sample_rate as f64
    }

    /// Decodes the next part of the song into `out` as interleaved stereo.
    /// False at the end of the song.
    pub fn next_block(&mut self, out: &mut Vec<f32>) -> Result<bool, Failure> {
        out.clear();
        loop {
            let packet = match self.format.next_packet() {
                Ok(Some(packet)) => packet,
                Ok(None) => {
                    if self.next_period()? {
                        continue;
                    }
                    return Ok(false);
                }
                Err(DecodeError::IoError(e)) if e.kind() == std::io::ErrorKind::UnexpectedEof => {
                    if self.next_period()? {
                        continue;
                    }
                    return Ok(false);
                }
                // A live stream's codec may start over, after a reconnection
                // say: decoding carries on with a new decoder.
                Err(DecodeError::ResetRequired) if self.live => {
                    self.reset_track()?;
                    continue;
                }
                Err(DecodeError::ResetRequired) => return Ok(false),
                Err(DecodeError::DecodeError(e)) if self.live && self.bad_reads < LIVE_BAD_READS => {
                    self.bad_reads += 1;
                    log::warn!("passing over a damaged stretch of the stream: {e}");
                    continue;
                }
                Err(e) => return Err(failure("could not read the next part", e)),
            };
            self.bad_reads = 0;
            if packet.track_id != self.track_id {
                continue;
            }
            let first = self.frames_at(packet.pts.get() + packet.trim_start.get() as i64);
            let decoded = match self.decoder.decode(&packet) {
                Ok(decoded) => decoded,
                // A damaged packet is skipped, as players do.
                Err(DecodeError::DecodeError(e)) => {
                    log::warn!("skipping a damaged packet: {e}");
                    continue;
                }
                Err(e) => return Err(failure("decoding failed", e)),
            };
            let frames = decoded.frames();
            if frames == 0 {
                continue;
            }
            decoded.copy_to_vec_interleaved(&mut self.interleaved);
            let mut from = 0;
            if let Some(wanted) = self.skip_until {
                let start = first.unwrap_or(self.position);
                if start + frames as u64 <= wanted {
                    continue;
                }
                from = wanted.saturating_sub(start) as usize;
                self.position = start + from as u64;
                self.skip_until = None;
            }
            let src = &self.interleaved[from * self.source_channels..];
            if let Some(convert) = &mut self.convert {
                self.stereo.clear();
                to_stereo(src, self.source_channels, &mut self.stereo);
                convert.run(&self.stereo, out);
                if out.is_empty() {
                    continue;
                }
                self.position += (out.len() / 2) as u64;
                return Ok(true);
            }
            to_stereo(src, self.source_channels, out);
            self.position += (frames - from) as u64;
            return Ok(true);
        }
    }

    /// Jumps to `secs` and returns where playing will carry on, which is
    /// exactly there unless that is past the end. A live stream carries on
    /// where it is.
    pub fn seek(&mut self, secs: f64) -> Result<f64, Failure> {
        if self.live {
            return Ok(self.position_secs());
        }
        let time = Time::try_from_secs_f64(secs.max(0.0))
            .ok_or_else(|| Failure::new(ErrorKind::InvalidArgument, "bad seek position"))?;
        let seeked = self
            .format
            .seek(SeekMode::Accurate, SeekTo::Time { time, track_id: Some(self.track_id) })
            .map_err(|e| failure("could not seek", e))?;
        self.decoder.reset();
        // The reader rounds the time down to a frame; round to the nearest
        // instead, never before where the reader says it can start.
        let required = self.frames_at(seeked.required_ts.get()).unwrap_or(0);
        let nearest = (secs.max(0.0) * self.info.sample_rate as f64).round() as u64;
        let wanted = if nearest.abs_diff(required) <= 1 { nearest.max(required) } else { required };
        self.skip_until = Some(wanted);
        self.position = wanted;
        Ok(wanted as f64 / self.info.sample_rate as f64)
    }

    // A timestamp in the track's time base, as a frame count.
    fn frames_at(&self, ts: i64) -> Option<u64> {
        let ts = ts.max(0) as u64;
        match self.time_base {
            None => Some(ts),
            Some(tb) => {
                let secs = f64::from(tb) * ts as f64;
                let frames = secs * self.info.sample_rate as f64;
                // A time base of one over the rate is the usual case: exact.
                if (f64::from(tb) * self.info.sample_rate as f64 - 1.0).abs() < 1e-9 {
                    Some(ts)
                } else {
                    Some(frames.round() as u64)
                }
            }
        }
    }
}

// Reads a stream's header into a format reader.
fn probe(hint: &Hint, source: Box<dyn MediaSource>, remote: bool) -> Result<Box<dyn FormatReader>, Failure> {
    // Streams read in bigger steps, so fewer small reads wait on the network.
    let buffer_len = if remote { 256 << 10 } else { 64 << 10 };
    let failed = Arc::new(Mutex::new(None));
    let watched = Watched { inner: source, failed: failed.clone() };
    let mss = MediaSourceStream::new(Box::new(watched), MediaSourceStreamOptions { buffer_len });
    symphonia::default::get_probe()
        .probe(hint, mss, FormatOptions::default(), MetadataOptions::default())
        .map_err(|e| match failed.lock().unwrap_or_else(|e| e.into_inner()).take() {
            // The probe passes over a failed read as the end of the stream:
            // the source's own failure says what went wrong.
            Some(f) => Failure { message: format!("could not read the format: {}", f.message), ..f },
            None => failure("could not read the format", e),
        })
}

// A source that keeps the failure behind its last failed read.
struct Watched {
    inner: Box<dyn MediaSource>,
    failed: Arc<Mutex<Option<Failure>>>,
}

impl std::io::Read for Watched {
    fn read(&mut self, buf: &mut [u8]) -> std::io::Result<usize> {
        self.inner.read(buf).inspect_err(|e| {
            if let Some(f) = e.get_ref().and_then(|inner| inner.downcast_ref::<Failure>()) {
                *self.failed.lock().unwrap_or_else(|e| e.into_inner()) = Some(f.clone());
            }
        })
    }
}

impl std::io::Seek for Watched {
    fn seek(&mut self, to: std::io::SeekFrom) -> std::io::Result<u64> {
        self.inner.seek(to)
    }
}

impl MediaSource for Watched {
    fn is_seekable(&self) -> bool {
        self.inner.is_seekable()
    }

    fn byte_len(&self) -> Option<u64> {
        self.inner.byte_len()
    }
}

// The format's audio track and a decoder for it. A live stream's decoder
// keeps every frame: an encoder's delay and padding tags at its start would
// otherwise end it at the length they give.
fn audio_track(format: &mut dyn FormatReader, live: bool) -> Result<Track, Failure> {
    let track = format
        .default_track(TrackType::Audio)
        .ok_or_else(|| Failure::new(ErrorKind::Unsupported, "no audio track"))?
        .clone();
    let Some(CodecParameters::Audio(params)) = track.codec_params.as_ref() else {
        return Err(Failure::new(ErrorKind::Unsupported, "the audio track has no codec"));
    };
    let params = aac_core(params);
    let decoder = codecs()
        .make_audio_decoder(&params, &AudioDecoderOptions::default().gapless(!live))
        .map_err(|e| failure("no decoder for this codec", e))?;
    // The decoder's own rate stands over the track's: for HE-AAC the track
    // may give the full rate while the decoder plays the core at half of it.
    let own = decoder.codec_params();
    let sample_rate = own.sample_rate.or(params.sample_rate).filter(|&r| r > 0).unwrap_or(44_100);
    let channels = own.channels.as_ref().or(params.channels.as_ref()).map(|c| c.count()).unwrap_or(2).max(1);
    Ok(Track {
        decoder,
        id: track.id,
        time_base: track.time_base,
        sample_rate,
        channels,
        bits_per_sample: params.bits_per_sample,
    })
}

// HE-AAC described in full (SBR or PS in the AudioSpecificConfig) as its
// AAC-LC core, which the AAC decoder plays: the same sound without the
// rebuilt high band, at half the rate. Anything else is left as it is.
fn aac_core(params: &AudioCodecParameters) -> AudioCodecParameters {
    let mut params = params.clone();
    if params.codec != CODEC_ID_AAC {
        return params;
    }
    if let Some(core) = params.extra_data.as_deref().and_then(lc_core_config) {
        params.extra_data = Some(Box::new(core));
    }
    params
}

// The two-byte AAC-LC AudioSpecificConfig of an HE-AAC one, or `None` when
// it is not HE-AAC or names its rate in full.
pub(crate) fn lc_core_config(asc: &[u8]) -> Option<[u8; 2]> {
    if asc.len() < 2 {
        return None;
    }
    let mut bits = asc.iter().flat_map(|b| (0..8).rev().map(move |i| (b >> i) & 1));
    let mut read =
        |n: u32| -> Option<u16> { (0..n).try_fold(0u16, |v, _| Some((v << 1) | bits.next()? as u16)) };
    let object_type = read(5)?;
    let rate_index = read(4)?;
    let channels = read(4)?;
    if rate_index == 15 {
        return None;
    }
    if !matches!(object_type, 5 | 29) {
        // AAC-LC with SBR maybe signalled after it: its first two bytes alone.
        let extended = object_type == 2 && asc.len() > 2;
        return extended.then(|| [asc[0], asc[1]]);
    }
    let _extension_rate = read(4)?;
    if read(5)? != 2 {
        return None;
    }
    Some(((2 << 11) | (rate_index << 7) | (channels << 3)).to_be_bytes())
}

// Changes interleaved stereo from one sample rate to another.
struct Convert {
    inner: Fft<f32>,
    pending: Vec<f32>,
    out: Vec<f32>,
    // The resampler's delay, dropped from the front.
    delay_left: usize,
}

impl Convert {
    fn new(from: u32, to: u32) -> Result<Self, Failure> {
        let inner = Fft::<f32>::new(from as usize, to as usize, 1024, 2, FixedSync::Input).map_err(|e| {
            Failure::new(ErrorKind::Unsupported, format!("cannot change {from} Hz to {to} Hz: {e}"))
        })?;
        let delay_left = inner.output_delay();
        let out = vec![0.0; inner.output_frames_max() * 2];
        Ok(Self { inner, pending: Vec::new(), out, delay_left })
    }

    // Takes `input` in and adds whatever is ready to `out`.
    fn run(&mut self, input: &[f32], out: &mut Vec<f32>) {
        self.pending.extend_from_slice(input);
        loop {
            let needed = self.inner.input_frames_next();
            if self.pending.len() < needed * 2 {
                return;
            }
            let frames = self.inner.output_frames_max();
            let made = {
                let Ok(input) = InterleavedSlice::new(&self.pending[..needed * 2], 2, needed) else { return };
                let Ok(mut output) = InterleavedSlice::new_mut(&mut self.out[..frames * 2], 2, frames) else {
                    return;
                };
                match self.inner.process_into_buffer(&input, &mut output, None) {
                    Ok((_, made)) => made,
                    Err(e) => {
                        log::error!("resampling failed: {e}");
                        0
                    }
                }
            };
            let skip = self.delay_left.min(made);
            self.delay_left -= skip;
            out.extend_from_slice(&self.out[skip * 2..made * 2]);
            self.pending.drain(..needed * 2);
        }
    }
}

// Any channel count to stereo. Mono is doubled; surround is folded down
// with the usual weights, leaving out the bass channel.
fn to_stereo(src: &[f32], channels: usize, out: &mut Vec<f32>) {
    match channels {
        2 => out.extend_from_slice(src),
        1 => out.extend(src.iter().flat_map(|&s| [s, s])),
        6 => {
            const C: f32 = std::f32::consts::FRAC_1_SQRT_2;
            let norm = 1.0 / (1.0 + 2.0 * C);
            for f in src.chunks_exact(6) {
                out.push((f[0] + C * f[2] + C * f[4]) * norm);
                out.push((f[1] + C * f[2] + C * f[5]) * norm);
            }
        }
        n => {
            for f in src.chunks_exact(n) {
                out.push(f[0]);
                out.push(f[1]);
            }
        }
    }
}

// The loudness tags from every set of metadata the file has.
fn read_replay_gain(format: &mut dyn FormatReader) -> Option<ReplayGainInfo> {
    let mut pairs: Vec<(String, String)> = Vec::new();
    let mut metadata = format.metadata();
    loop {
        if let Some(rev) = metadata.current() {
            let tracks = rev.per_track.iter().flat_map(|t| t.metadata.tags.iter());
            for tag in rev.media.tags.iter().chain(tracks) {
                let named = match &tag.std {
                    Some(StandardTag::ReplayGainTrackGain(v)) => {
                        Some(("REPLAYGAIN_TRACK_GAIN", v.to_string()))
                    }
                    Some(StandardTag::ReplayGainTrackPeak(v)) => {
                        Some(("REPLAYGAIN_TRACK_PEAK", v.to_string()))
                    }
                    Some(StandardTag::ReplayGainAlbumGain(v)) => {
                        Some(("REPLAYGAIN_ALBUM_GAIN", v.to_string()))
                    }
                    Some(StandardTag::ReplayGainAlbumPeak(v)) => {
                        Some(("REPLAYGAIN_ALBUM_PEAK", v.to_string()))
                    }
                    _ => None,
                };
                match named {
                    Some((name, value)) => pairs.push((name.to_string(), value)),
                    None => {
                        // Free-form keys like "TXXX:R128_TRACK_GAIN" or
                        // "----:com.apple.iTunes:replaygain_track_gain".
                        let key = tag.raw.key.rsplit(':').next().unwrap_or(&tag.raw.key);
                        pairs.push((key.to_string(), tag.raw.value.to_string()));
                    }
                }
            }
        }
        if metadata.pop().is_none() {
            break;
        }
    }
    replaygain::from_tags(pairs.iter().map(|(k, v)| (k.as_str(), v.as_str())))
}

fn failure(what: &str, e: DecodeError) -> Failure {
    let kind = match &e {
        DecodeError::Unsupported(_) => ErrorKind::Unsupported,
        DecodeError::IoError(io) => {
            // A network failure from a stream arrives as an I/O error.
            match io.get_ref().and_then(|inner| inner.downcast_ref::<Failure>()) {
                Some(f) => return Failure { message: format!("{what}: {}", f.message), ..f.clone() },
                None => ErrorKind::Other,
            }
        }
        DecodeError::DecodeError(_) => ErrorKind::Decode,
        _ => ErrorKind::Decode,
    };
    Failure::new(kind, format!("{what}: {e}"))
}
