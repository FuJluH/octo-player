//! Renders the transition from one song into another through the real
//! mixer, with no sound device, to a WAV file to listen to. Prints the plan
//! and checks the sound of the blend.
//!
//! cargo run --release --example render_transition -- <A> <B> <out.wav> [options]
//! cargo run --release --example render_transition -- --batch <pairs.txt> <out dir> [options]
//!
//! A and B are paths or stream addresses. Each file holds the 10 s before
//! the blend, the blend, and the 10 s after it, as 32-bit float stereo at
//! 48 kHz. A pairs file has one pair a line, A and B split by a tab or by
//! " | "; empty lines and lines starting with # are skipped. Batch mode
//! writes 01.wav, 02.wav, ... and ends with a summary.
//!
//! The mixer runs with the desktop app's default sound settings, so its
//! limiter is on: it catches what the two songs' sum would push over full
//! scale while they blend.
//!
//! Checks, on the rendered sound:
//!   loudness  momentary loudness (BS.1770, 400 ms) through the blend against
//!             the two bodies, A before the blend and B after it: a dip is how
//!             far it falls below the quieter body's median, flagged when it is
//!             more than 3 dB and more than 3 dB deeper than the dip of a
//!             gapless join at the same exit (A cut where the blend lets it go,
//!             B straight after from its entry), so quiet music is not blamed
//!             on the blend; a swell, more than 2 dB above the louder body's
//!             90th percentile, is always flagged
//!   peaks     any sample inside the blend above -0.1 dBFS
//!   clicks    first-difference spikes near the blend that the gapless join
//!             does not have at the same place in either song, against how
//!             often they come in the music outside it
//!
//! Options (each override replaces the planner's choice):
//!   --crossfade <ms>   the longest blend (8000)
//!   --start <s>        when in A the blend starts
//!   --entry <s>        where B comes in
//!   --overlap <s>      how long both sound
//!   --k <0..1>         gain curve weight (0 is equal power)
//!   --filters <0..1>   filter sweep strength
//!   --rate <factor>    B's rate through the blend
//!   --headroom <dB>    both songs lowered this much through the blend
//!   --plain            the fixed equal-power crossfade, without scouting
//!   --no-sweeps        smart transitions without the filter sweeps
//!   --match            smart transitions with tempo matching (off in the app by default)
//!   --no-live          plan without A's whole-song level and tempo
//!   --click-ratio <x>  a click is a step this many times the local level (8)

#[path = "common/tags.rs"]
mod tags;

use std::io::Write;
use std::path::{Path, PathBuf};
use std::sync::atomic::AtomicBool;
use std::time::{Duration, Instant};

use octo_audio::automix::{
    self, Biquad, LiveAnalysis, LiveAnalyzer, PlanSettings, SectionAnalysis, SectionAnalyzer, SectionKind,
    TransitionContext, TransitionPlan,
};
use octo_audio::crossfade::FadeSong;
use octo_audio::deck::Deck;
use octo_audio::lane::Lane;
use octo_audio::mixer::{FadeShape, LowPassSteps, MixState, Mixer, Transition};
use octo_audio::pace::Pace;
use octo_audio::scout::{SectionPart, scout_section};
use octo_audio::sound::model::{ReplayGainSettings, SoundSettings};
use octo_audio::sound::replaygain::Loudness;
use octo_audio::source::http::HttpOptions;

const RATE: u32 = 48_000;
const AROUND_SECS: f64 = 10.0;

// The live tap has heard the outgoing song up to about here when the player
// plans: the next song opens this long before the end (20 s, the longest
// early exit and the longest blend).
const PLANNED_BEFORE_END_SECS: f64 = 20.0 + 45.0 + 16.0;

// The loudness check: below the quieter body's median by more than this,
// or above the louder body's 90th percentile by more than LOUDER_DB, is
// flagged.
const QUIETER_DB: f64 = 3.0;
const LOUDER_DB: f64 = 2.0;

// No sample may go above this.
const PEAK_DBFS: f64 = -0.1;

// Clicks are looked for this far either side of the blend.
const CLICK_MARGIN_SECS: f64 = 0.5;

// A step smaller than this is never a click.
const CLICK_FLOOR: f32 = 0.01;

#[derive(Clone, Debug)]
struct Options {
    crossfade_ms: u32,
    plain: bool,
    sweeps: bool,
    match_tempo: bool,
    live: bool,
    click_ratio: f32,
    start: Option<f64>,
    entry: Option<f64>,
    overlap: Option<f64>,
    k: Option<f64>,
    filters: Option<f64>,
    rate: Option<f64>,
    headroom: Option<f64>,
}

fn value<T: std::str::FromStr>(args: &mut impl Iterator<Item = String>, name: &str) -> T {
    let raw = args.next().unwrap_or_else(|| fail(&format!("{name} needs a value")));
    raw.parse().unwrap_or_else(|_| fail(&format!("{name}: cannot read {raw}")))
}

fn fail(message: &str) -> ! {
    eprintln!("{message}");
    std::process::exit(2);
}

// The song's length in seconds, from its decoder.
fn length_of(source: &str) -> Result<f64, String> {
    let deck = Deck::open(0, source.to_string(), 0.0, HttpOptions::default());
    let until = Instant::now() + Duration::from_secs(30);
    loop {
        if let Some(info) = deck.info() {
            let ms = info.duration_ms.ok_or_else(|| format!("{source}: length unknown"))?;
            return Ok(ms as f64 / 1_000.0);
        }
        if let octo_audio::deck::DeckStatus::Failed(f) = deck.status() {
            return Err(format!("{source}: {f}"));
        }
        if Instant::now() > until {
            return Err(format!("{source}: did not open"));
        }
        std::thread::sleep(Duration::from_millis(5));
    }
}

fn scout(source: &str, part: SectionPart, tag_bpm: Option<f64>) -> Option<SectionAnalysis> {
    let kind = if matches!(part, SectionPart::Head { .. }) { SectionKind::Head } else { SectionKind::Tail };
    let mut analyzer = SectionAnalyzer::new(kind, tag_bpm);
    let never = AtomicBool::new(false);
    match scout_section(source, HttpOptions::default(), part, &never, &mut analyzer) {
        Ok(()) => analyzer.finish(),
        Err(f) => {
            eprintln!("could not scout {source}: {f}");
            None
        }
    }
}

// What the live tap would have heard of A by the time the player plans.
fn listen(source: &str, secs: f64, tag_bpm: Option<f64>) -> Option<LiveAnalysis> {
    if secs <= 1.0 {
        return None;
    }
    let mut live = LiveAnalyzer::new();
    let never = AtomicBool::new(false);
    let part = SectionPart::Head { secs };
    scout_section(source, HttpOptions::default(), part, &never, &mut live).ok()?;
    Some(live.summary(tag_bpm))
}

fn write_wav(path: &Path, samples: &[f32]) -> std::io::Result<()> {
    let data = (samples.len() * 4) as u32;
    let mut out = Vec::with_capacity(44 + data as usize);
    out.extend_from_slice(b"RIFF");
    out.extend_from_slice(&(36 + data).to_le_bytes());
    out.extend_from_slice(b"WAVEfmt ");
    out.extend_from_slice(&16u32.to_le_bytes());
    out.extend_from_slice(&3u16.to_le_bytes());
    out.extend_from_slice(&2u16.to_le_bytes());
    out.extend_from_slice(&RATE.to_le_bytes());
    out.extend_from_slice(&(RATE * 8).to_le_bytes());
    out.extend_from_slice(&8u16.to_le_bytes());
    out.extend_from_slice(&32u16.to_le_bytes());
    out.extend_from_slice(b"data");
    out.extend_from_slice(&data.to_le_bytes());
    for s in samples {
        out.extend_from_slice(&s.to_le_bytes());
    }
    std::fs::File::create(path)?.write_all(&out)
}

fn describe_section(name: &str, a: Option<&SectionAnalysis>) -> String {
    let Some(a) = a else { return format!("{name}: no analysis") };
    let f = &a.features;
    let ms = |v: Option<i64>| v.map_or("-".to_string(), |v| format!("{:.2}", v as f64 / 1_000.0));
    let tempo = f.tempo.map_or("no beat".to_string(), |t| {
        format!(
            "{:.1} BPM (peak {:.1}, on beat {:.0} %{})",
            t.bpm,
            t.confidence,
            t.consistency * 100.0,
            if t.confident() { ", trusted" } else { "" }
        )
    });
    format!(
        "{name}: body {:.1} dBFS, sound {}..{} s, outro {} s, {} boundaries, {tempo}",
        f.body_db,
        ms(f.sound_start_ms),
        ms(f.sound_end_ms),
        ms(f.outro_start_ms),
        f.boundaries_ms.len()
    )
}

// How one pair came out.
struct Outcome {
    plan: String,
    kind: String,
    start_secs: f64,
    overlap_secs: f64,
    measures: Measures,
    flags: Vec<String>,
}

// What the checks measured.
#[derive(Clone, Copy, Debug, Default)]
struct Measures {
    // How far the blend and the gapless join fall below the quieter body, in dB.
    dip_db: Option<f64>,
    gapless_dip_db: Option<f64>,
    clicks: usize,
    peaks: usize,
}

fn plan_pair(a: &str, b: &str, a_len: f64, b_len: f64, opts: &Options) -> TransitionPlan {
    let a_tags = tags::read(a);
    let b_tags = tags::read(b);
    let blend_ms = (opts.crossfade_ms as f64).min(a_len.min(b_len) / 2.0 * 1_000.0) as i64;
    if opts.plain {
        return TransitionPlan::fixed_crossfade((a_len * 1_000.0) as i64, blend_ms, "fixed crossfade");
    }
    let tail = scout(a, SectionPart::Tail { secs: automix::TAIL_SECS, len_secs: Some(a_len) }, a_tags.bpm);
    let head = scout(b, SectionPart::Head { secs: automix::HEAD_SECS }, b_tags.bpm);
    let heard_secs = (a_len - PLANNED_BEFORE_END_SECS).max(0.0);
    let live = if opts.live { listen(a, heard_secs, a_tags.bpm) } else { None };
    println!("  {}", describe_section("A end", tail.as_ref()));
    println!("  {}", describe_section("B start", head.as_ref()));
    if let Some(l) = &live {
        let body = l.body_level_db.map_or("-".to_string(), |d| format!("{d:.1} dBFS"));
        let tempo = l.tempo_prior.map_or("no trusted beat".to_string(), |t| format!("{t:.1} BPM"));
        println!("  A as heard ({:.0} s): body {body}, {tempo}", l.heard_ms as f64 / 1_000.0);
    }
    if a_tags != tags::Tags::default() || b_tags != tags::Tags::default() {
        println!("  tags: A {:?} {:?}, B {:?} {:?}", a_tags.genre, a_tags.bpm, b_tags.genre, b_tags.bpm);
    }
    let song = |len: f64, album: &str| FadeSong {
        album_id: Some(album.into()),
        album_order: None,
        duration_ms: (len * 1_000.0) as u64,
    };
    let settings = PlanSettings {
        max_overlap_ms: opts.crossfade_ms as i64,
        smart: true,
        filter_sweeps: opts.sweeps,
        beat_match: opts.match_tempo,
        fade_curve: automix::FadeCurve::EqualPower,
    };
    let now_ms = (heard_secs * 1_000.0) as i64;
    let context = TransitionContext {
        now_ms,
        played_ms: now_ms,
        current_genre: a_tags.genre,
        next_genre: b_tags.genre,
        body_level_db: live.as_ref().and_then(|l| l.body_level_db),
        tempo_prior: live.as_ref().and_then(|l| l.tempo_prior),
        ..Default::default()
    };
    automix::plan_transition(
        &song(a_len, "a"),
        Some(&song(b_len, "b")),
        tail.as_ref(),
        head.as_ref(),
        &settings,
        &context,
    )
}

fn render_pair(a: &str, b: &str, out: &Path, opts: &Options) -> Result<Outcome, String> {
    let (a_len, b_len) = (length_of(a)?, length_of(b)?);
    let mut plan = plan_pair(a, b, a_len, b_len, opts);
    if let Some(v) = opts.start {
        plan.start_ms = (v * 1_000.0) as i64;
    }
    if let Some(v) = opts.entry {
        plan.entry_ms = (v * 1_000.0) as i64;
    }
    if let Some(v) = opts.overlap {
        plan.overlap_ms = (v * 1_000.0) as i64;
    }
    if let Some(v) = opts.k {
        plan.k = v;
    }
    if let Some(v) = opts.filters {
        plan.filter_strength = v;
    }
    if opts.rate.is_some() {
        plan.beat_match_rate = opts.rate;
    }
    if let Some(v) = opts.headroom {
        plan.headroom_db = v;
    }
    println!("  {}", plan.describe());
    if plan.overlap_ms <= 0 {
        return Ok(Outcome {
            plan: plan.reason.clone(),
            kind: plan.kind.name().into(),
            start_secs: plan.start_secs(),
            overlap_secs: 0.0,
            measures: Measures::default(),
            flags: vec!["no blend to render".into()],
        });
    }

    let from = (plan.start_secs() - AROUND_SECS).max(0.0);
    let overlap = plan.overlap_secs();
    let frames = (overlap * RATE as f64) as u64;
    let shape = FadeShape {
        k: plan.k,
        curve: plan.curve,
        filter_strength: plan.filter_strength,
        steps: plan.low_pass_glide().map(|glide| LowPassSteps { beats: plan.beat_progress(), glide }),
        rate: plan.beat_match_rate,
        silence_gate_db: (plan.k != 0.0).then_some(automix::SILENCE_FLOOR_DB as f32),
        headroom_db: plan.headroom_db as f32,
    };
    let wanted = ((plan.start_secs() - from + overlap + AROUND_SECS) * RATE as f64) as usize;
    let (samples, markers) = render(a, b, from, plan.start_secs(), plan.entry_secs(), frames, shape, wanted)?;
    write_wav(out, &samples).map_err(|e| format!("{}: {e}", out.display()))?;

    // Where the blend lies in the file, by the mixer's own markers.
    let blend_from = markers
        .iter()
        .find(|m| m.key == 2)
        .map_or(((plan.start_secs() - from) * RATE as f64) as usize, |m| m.frame as usize);
    let blend_to = (blend_from + frames as usize).min(samples.len() / 2);
    println!(
        "  wrote {}: {:.1} s, the blend from {:.2} s to {:.2} s",
        out.display(),
        samples.len() as f64 / 2.0 / RATE as f64,
        blend_from as f64 / RATE as f64,
        blend_to as f64 / RATE as f64
    );

    // The same two songs joined gaplessly where the blend lets A go.
    let exit = plan.start_secs() + overlap;
    let (gapless, _) =
        render(a, b, from, exit, plan.entry_secs(), 1, FadeShape::default(), wanted + frames as usize)?;
    let (measures, flags) = check(&samples, &gapless, blend_from, blend_to, opts.click_ratio);
    Ok(Outcome {
        plan: plan.reason.clone(),
        kind: plan.kind.name().into(),
        start_secs: plan.start_secs(),
        overlap_secs: overlap,
        measures,
        flags,
    })
}

// Renders A from `from` into B from `entry`, blending over `frames` from
// `at` in A, `wanted` frames in all.
#[allow(clippy::too_many_arguments)]
fn render(
    a: &str,
    b: &str,
    from: f64,
    at: f64,
    entry: f64,
    frames: u64,
    shape: FadeShape,
    wanted: usize,
) -> Result<(Vec<f32>, Vec<octo_audio::mixer::Marker>), String> {
    let a_deck = Deck::open(1, a.to_string(), from, HttpOptions::default());
    let b_deck = Deck::open(2, b.to_string(), entry, HttpOptions::default());
    let until = Instant::now() + Duration::from_secs(30);
    while !(a_deck.is_ready() && b_deck.is_ready()) {
        if Instant::now() > until {
            return Err("the songs did not open".into());
        }
        std::thread::sleep(Duration::from_millis(5));
    }
    let mut mixer = Mixer::new(RATE, 0, &SoundSettings::default(), Pace::default());
    let mut lane = Lane::new(a_deck, Loudness::default(), &ReplayGainSettings::default(), RATE);
    lane.last = true;
    mixer.start(lane, Transition::Start);
    mixer.plan_fade(1, at, frames, b_deck, Loudness::default(), shape);
    let mut samples = Vec::with_capacity(wanted * 2);
    let mut block = vec![0.0f32; 2_048];
    let mut markers = Vec::new();
    let until = Instant::now() + Duration::from_secs(120);
    while samples.len() / 2 < wanted {
        let (made, state) = mixer.render(&mut block, &mut markers);
        samples.extend_from_slice(&block[..made * 2]);
        if made == 0 {
            if state == MixState::Ended || Instant::now() > until {
                break;
            }
            std::thread::sleep(Duration::from_millis(1));
        }
    }
    samples.truncate(wanted * 2);
    Ok((samples, markers))
}

// The loudness, peak and click checks on a rendered blend. `gapless` is
// the same two songs joined without a blend where the blend lets A go: the
// same sound up to the blend's start, then the rest of A's part of the
// blend, then B's.
fn check(
    samples: &[f32],
    gapless: &[f32],
    blend_from: usize,
    blend_to: usize,
    click_ratio: f32,
) -> (Measures, Vec<String>) {
    let mut flags = Vec::new();
    let mut measures = Measures::default();
    let frames = samples.len() / 2;
    let secs = |frame: usize| frame as f64 / RATE as f64;

    // Loudness: each body's momentary levels, A's before the blend and B's
    // after it, against the momentary levels through the blend and through
    // the same music joined gaplessly.
    let weighted = k_weighted(samples);
    let a_body = momentary(&weighted, 0, blend_from);
    let b_body = momentary(&weighted, blend_to, frames);
    let blend = momentary(&weighted, blend_from, blend_to);
    let joined = k_weighted(gapless);
    let span = blend_to - blend_from;
    let join = momentary(&joined, blend_from, (blend_from + 2 * span).min(gapless.len() / 2));
    let lowest =
        |w: &[(usize, f64)]| w.iter().copied().fold((0, f64::INFINITY), |m, w| if w.1 < m.1 { w } else { m });
    match (body_of(&a_body), body_of(&b_body)) {
        (Some((a_typical, a_loud)), Some((b_typical, b_loud))) if !blend.is_empty() => {
            let quieter = a_typical.min(b_typical);
            let ceiling = a_loud.max(b_loud) + LOUDER_DB;
            let (low_at, low) = lowest(&blend);
            let (high_at, high) =
                blend.iter().copied().fold((0, f64::NEG_INFINITY), |m, w| if w.1 > m.1 { w } else { m });
            let dip = quieter - low;
            measures.dip_db = Some(dip);
            let gapless_dip = (!join.is_empty()).then(|| quieter - lowest(&join).1);
            measures.gapless_dip_db = gapless_dip;
            println!(
                "  loudness: A before {a_typical:.1} LUFS (loud {a_loud:.1}), B after {b_typical:.1} (loud {b_loud:.1}); through the blend {low:.1} (at {:.2} s) to {high:.1} (at {:.2} s); dip {dip:.1} dB, gapless join {}",
                secs(low_at),
                secs(high_at),
                gapless_dip.map_or("-".to_string(), |d| format!("{d:.1} dB"))
            );
            let beyond_gapless = dip - gapless_dip.unwrap_or(f64::NEG_INFINITY);
            if dip > QUIETER_DB && beyond_gapless > QUIETER_DB {
                flags.push(format!(
                    "dips {dip:.1} dB below the quieter body at {:.2} s, {beyond_gapless:.1} dB more than a gapless join",
                    secs(low_at)
                ));
            }
            if high > ceiling {
                flags.push(format!(
                    "swells {:.1} dB above the louder body at {:.2} s",
                    high - ceiling + LOUDER_DB,
                    secs(high_at)
                ));
            }
        }
        _ => println!("  loudness: too little sound before or after the blend to compare"),
    }

    // Peaks inside the blend.
    let limit = 10f64.powf(PEAK_DBFS / 20.0) as f32;
    let inside = &samples[blend_from * 2..blend_to * 2];
    let peak = inside.iter().fold(0.0f32, |m, s| m.max(s.abs()));
    let over = inside.iter().filter(|s| s.abs() > limit).count();
    measures.peaks = over;
    println!(
        "  peak in the blend {:.2} dBFS, {over} samples above {PEAK_DBFS} dBFS",
        20.0 * (peak.max(1e-10) as f64).log10()
    );
    if over > 0 {
        flags.push(format!(
            "{over} samples in the blend above {PEAK_DBFS} dBFS (peak {:.2})",
            20.0 * (peak as f64).log10()
        ));
    }

    // Clicks near the blend that are not in the music itself: the gapless
    // join has A's sound at the same frame and B's one blend length later.
    // What is left is weighed against how often the music has them elsewhere.
    let spikes = clicks(samples, click_ratio);
    let joined_spikes = clicks(gapless, click_ratio);
    let close = (RATE / 100) as usize;
    let in_music =
        |f: usize| joined_spikes.iter().any(|&g| g.abs_diff(f) <= close || g.abs_diff(f + span) <= close);
    let margin = (CLICK_MARGIN_SECS * RATE as f64) as usize;
    let (near_from, near_to) = (blend_from.saturating_sub(margin), (blend_to + margin).min(frames));
    let near: Vec<usize> =
        spikes.iter().copied().filter(|&f| f >= near_from && f < near_to && !in_music(f)).collect();
    let outside = spikes.iter().filter(|&&f| f < near_from || f >= near_to).count();
    let outside_secs = secs(frames - (near_to - near_from)).max(1e-9);
    let expected = outside as f64 / outside_secs * secs(near_to - near_from);
    let times: Vec<String> = near.iter().take(5).map(|&f| format!("{:.3}", secs(f))).collect();
    println!(
        "  clicks: {} near the blend not in the music{}, {outside} elsewhere ({expected:.1} expected near it at that rate)",
        near.len(),
        if times.is_empty() { String::new() } else { format!(" at {} s", times.join(", ")) }
    );
    let excess = near.len().saturating_sub((2.0 * expected).ceil() as usize);
    measures.clicks = excess;
    if !near.is_empty() && excess > 0 {
        flags.push(format!("{} clicks near the blend, first at {} s", near.len(), times[0]));
    }
    (measures, flags)
}

// The two K-weighting stages of BS.1770 at 48 kHz, run over each channel.
fn k_weighted(samples: &[f32]) -> Vec<f64> {
    let mut out = vec![0.0; samples.len()];
    for ch in 0..2 {
        let mut shelf = Biquad::new(
            1.535_124_859_586_97,
            -2.691_696_189_406_38,
            1.198_392_810_852_85,
            -1.690_659_293_182_41,
            0.732_480_774_215_85,
        );
        let mut high_pass = Biquad::new(1.0, -2.0, 1.0, -1.990_047_454_833_98, 0.990_072_250_366_21);
        for i in (ch..samples.len()).step_by(2) {
            out[i] = high_pass.process(shelf.process(samples[i] as f64));
        }
    }
    out
}

// The momentary loudness (LUFS, 400 ms windows every 100 ms) of the
// K-weighted stereo whose window middles lie from frame `from` to `to`, by
// window middle. Windows reach into the sound either side.
fn momentary(weighted: &[f64], from: usize, to: usize) -> Vec<(usize, f64)> {
    let frames = weighted.len() / 2;
    let (window, step) = (RATE as usize * 4 / 10, RATE as usize / 10);
    let mut out = Vec::new();
    let mut middle = from;
    while middle < to {
        let start = middle.saturating_sub(window / 2);
        let end = (start + window).min(frames);
        if end > start {
            let sum: f64 = weighted[start * 2..end * 2].iter().map(|x| x * x).sum();
            let power = sum / (end - start) as f64;
            out.push((middle, -0.691 + 10.0 * power.max(1e-12).log10()));
        }
        middle += step;
    }
    out
}

// A body's typical level (the median momentary loudness) and its loud level
// (the 90th percentile), or None with under a second of it.
fn body_of(windows: &[(usize, f64)]) -> Option<(f64, f64)> {
    if windows.len() < 10 {
        return None;
    }
    let mut levels: Vec<f64> = windows.iter().map(|w| w.1).collect();
    levels.sort_by(f64::total_cmp);
    let at = |p: f64| levels[((levels.len() - 1) as f64 * p).round() as usize];
    Some((at(0.5), at(0.9)))
}

// Frames where either channel steps by more than `ratio` times the step
// size around it (10 ms either side) and more than CLICK_FLOOR.
fn clicks(samples: &[f32], ratio: f32) -> Vec<usize> {
    let frames = samples.len() / 2;
    let half = (RATE / 100) as usize;
    let mut found = Vec::new();
    for ch in 0..2 {
        let steps: Vec<f32> = (0..frames)
            .map(|i| if i == 0 { 0.0 } else { samples[i * 2 + ch] - samples[(i - 1) * 2 + ch] })
            .collect();
        let mut prefix = vec![0.0f64; frames + 1];
        for (i, d) in steps.iter().enumerate() {
            prefix[i + 1] = prefix[i] + (*d as f64) * (*d as f64);
        }
        for (i, &d) in steps.iter().enumerate() {
            if d.abs() < CLICK_FLOOR {
                continue;
            }
            let (from, to) = (i.saturating_sub(half), (i + half + 1).min(frames));
            let local = ((prefix[to] - prefix[from]) / (to - from) as f64).sqrt() as f32;
            if d.abs() > ratio * local {
                found.push(i);
            }
        }
    }
    found.sort_unstable();
    found.dedup_by(|a, b| a.abs_diff(*b) < half);
    found
}

// The pairs in a pairs file.
fn pairs_in(path: &str) -> Vec<(String, String)> {
    let text = std::fs::read_to_string(path).unwrap_or_else(|e| fail(&format!("{path}: {e}")));
    text.lines()
        .map(str::trim)
        .filter(|l| !l.is_empty() && !l.starts_with('#'))
        .map(|l| {
            let (a, b) = l
                .split_once('\t')
                .or_else(|| l.split_once(" | "))
                .unwrap_or_else(|| fail(&format!("{path}: no tab or \" | \" between the two songs in: {l}")));
            (a.trim().to_string(), b.trim().to_string())
        })
        .collect()
}

fn main() {
    let mut args = std::env::args().skip(1);
    let mut files = Vec::new();
    let mut batch = false;
    let mut opts = Options {
        crossfade_ms: 8_000,
        plain: false,
        sweeps: true,
        match_tempo: false,
        live: true,
        click_ratio: 8.0,
        start: None,
        entry: None,
        overlap: None,
        k: None,
        filters: None,
        rate: None,
        headroom: None,
    };
    while let Some(arg) = args.next() {
        match arg.as_str() {
            "--batch" => batch = true,
            "--crossfade" => opts.crossfade_ms = value(&mut args, &arg),
            "--start" => opts.start = Some(value(&mut args, &arg)),
            "--entry" => opts.entry = Some(value(&mut args, &arg)),
            "--overlap" => opts.overlap = Some(value(&mut args, &arg)),
            "--k" => opts.k = Some(value(&mut args, &arg)),
            "--filters" => opts.filters = Some(value(&mut args, &arg)),
            "--rate" => opts.rate = Some(value(&mut args, &arg)),
            "--headroom" => opts.headroom = Some(value(&mut args, &arg)),
            "--click-ratio" => opts.click_ratio = value(&mut args, &arg),
            "--plain" => opts.plain = true,
            "--no-sweeps" => opts.sweeps = false,
            "--match" => opts.match_tempo = true,
            "--no-live" => opts.live = false,
            other if other.starts_with("--") => fail(&format!("unknown option {other}")),
            other => files.push(other.to_string()),
        }
    }

    let (pairs, outs): (Vec<(String, String)>, Vec<PathBuf>) = if batch {
        let [list, dir] = files.as_slice() else {
            fail("usage: render_transition --batch <pairs.txt> <out dir> [options]");
        };
        std::fs::create_dir_all(dir).unwrap_or_else(|e| fail(&format!("{dir}: {e}")));
        let pairs = pairs_in(list);
        let outs = (1..=pairs.len()).map(|i| Path::new(dir).join(format!("{i:02}.wav"))).collect();
        (pairs, outs)
    } else {
        let [a, b, out] = files.as_slice() else {
            fail("usage: render_transition <A> <B> <out.wav> [options]");
        };
        (vec![(a.clone(), b.clone())], vec![PathBuf::from(out)])
    };

    let mut summary = Vec::new();
    for (i, ((a, b), out)) in pairs.iter().zip(&outs).enumerate() {
        println!("[{}] {a}\n  -> {b}", i + 1);
        let outcome = render_pair(a, b, out, &opts);
        match &outcome {
            Ok(o) if o.flags.is_empty() => println!("  ok"),
            Ok(o) => println!("  FLAGGED: {}", o.flags.join("; ")),
            Err(e) => println!("  FAILED: {e}"),
        }
        println!();
        summary.push((out.clone(), outcome));
    }
    if batch {
        let flagged = summary.iter().filter(|(_, o)| !matches!(o, Ok(o) if o.flags.is_empty())).count();
        println!("{} pairs, {} ok, {flagged} flagged or failed", summary.len(), summary.len() - flagged);
        for (out, outcome) in &summary {
            let name = out.file_name().map(|n| n.to_string_lossy().to_string()).unwrap_or_default();
            match outcome {
                Ok(o) if o.flags.is_empty() => println!("  {name}  ok        {}", o.plan),
                Ok(o) => println!("  {name}  FLAGGED   {} [{}]", o.plan, o.flags.join("; ")),
                Err(e) => println!("  {name}  FAILED    {e}"),
            }
        }
        println!();
        println!(
            "| Pair | Plan | Start | Overlap | Dip | Gapless dip | Dip vs gapless | Clicks | Peaks | Flags |"
        );
        println!("| --- | --- | --- | --- | --- | --- | --- | --- | --- | --- |");
        let db = |d: Option<f64>| d.map_or("-".to_string(), |d| format!("{d:.1} dB"));
        for (out, outcome) in &summary {
            let name = out.file_stem().map(|n| n.to_string_lossy().to_string()).unwrap_or_default();
            match outcome {
                Ok(o) => {
                    let m = o.measures;
                    let beyond = match (m.dip_db, m.gapless_dip_db) {
                        (Some(d), Some(g)) => format!("{:+.1} dB", d - g),
                        _ => "-".to_string(),
                    };
                    println!(
                        "| {name} | {} | {:.2} s | {:.2} s | {} | {} | {beyond} | {} | {} | {} |",
                        o.kind,
                        o.start_secs,
                        o.overlap_secs,
                        db(m.dip_db),
                        db(m.gapless_dip_db),
                        m.clicks,
                        m.peaks,
                        if o.flags.is_empty() { "none".to_string() } else { o.flags.join("; ") }
                    );
                }
                Err(e) => println!("| {name} | failed: {e} | | | | | | | | |"),
            }
        }
    }
}
