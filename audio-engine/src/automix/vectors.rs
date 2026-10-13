//! Every case in the shared automix vectors
//! (`shared/core/src/commonTest/resources/automix-vectors.json`), which the
//! app's own copy of this code runs too. The songs are rebuilt from their
//! layers, scouted, analyzed and planned, and every result must match
//! within the file's tolerances. A failure lists every case that is off,
//! not only the first.

use std::collections::HashMap;
use std::path::PathBuf;

use serde_json::Value;

use super::synthetic::{SongLayer, SyntheticSong};
use super::*;
use crate::crossfade::FadeSong;

// How many samples of each biquad answer the file holds.
const FILTER_VECTOR_SAMPLES: usize = 512;

fn vectors_path() -> PathBuf {
    PathBuf::from(env!("CARGO_MANIFEST_DIR"))
        .join("../shared/core/src/commonTest/resources/automix-vectors.json")
}

fn num(o: &Value, key: &str) -> f64 {
    o[key].as_f64().unwrap_or_else(|| panic!("{key} is not a number in {o}"))
}

fn num_or_none(o: &Value, key: &str) -> Option<f64> {
    o.get(key).and_then(Value::as_f64)
}

fn int(o: &Value, key: &str) -> i64 {
    o[key].as_i64().unwrap_or_else(|| panic!("{key} is not a whole number in {o}"))
}

fn text<'a>(o: &'a Value, key: &str) -> &'a str {
    o[key].as_str().unwrap_or_else(|| panic!("{key} is not text in {o}"))
}

fn text_or_none(o: &Value, key: &str) -> Option<String> {
    o.get(key).and_then(Value::as_str).map(str::to_string)
}

fn flag(o: &Value, key: &str) -> bool {
    o[key].as_bool().unwrap_or_else(|| panic!("{key} is not true or false in {o}"))
}

fn list<'a>(o: &'a Value, key: &str) -> &'a Vec<Value> {
    o[key].as_array().unwrap_or_else(|| panic!("{key} is not a list"))
}

fn song_of(o: &Value) -> SyntheticSong {
    SyntheticSong {
        rate: int(o, "rate") as u32,
        channels: int(o, "channels") as u32,
        length_ms: int(o, "lengthMs"),
        layers: list(o, "layers")
            .iter()
            .map(|l| SongLayer {
                kind: text(l, "kind").to_string(),
                from_ms: num(l, "fromMs"),
                to_ms: num(l, "toMs"),
                hz: num(l, "hz"),
                db: num(l, "db"),
                end_db: num(l, "endDb"),
                bpm: num_or_none(l, "bpm").unwrap_or(0.0),
                first_ms: num_or_none(l, "firstMs").unwrap_or(0.0),
                every: l.get("every").and_then(Value::as_i64).unwrap_or(1),
                decay_ms: num_or_none(l, "decayMs").unwrap_or(0.0),
            })
            .collect(),
    }
}

fn fade_song_of(o: &Value) -> FadeSong {
    FadeSong {
        album_id: text_or_none(o, "albumId"),
        album_order: o.get("albumOrder").and_then(Value::as_i64).map(|v| v as i32),
        duration_ms: int(o, "durationMs").max(0) as u64,
    }
}

fn context_of(o: &Value) -> TransitionContext {
    TransitionContext {
        now_ms: int(o, "nowMs"),
        played_ms: int(o, "playedMs"),
        repeat_one: flag(o, "repeatOne"),
        stop_at_end_of_song: flag(o, "stopAtEndOfSong"),
        pace: num(o, "pace"),
        skip_silence: flag(o, "skipSilence"),
        current_genre: text_or_none(o, "currentGenre"),
        next_genre: text_or_none(o, "nextGenre"),
        body_level_db: num_or_none(o, "bodyLevelDb"),
        tempo_prior: num_or_none(o, "tempoPrior"),
    }
}

fn biquad_of(kind: &str, rate: u32, hz: f64) -> Biquad {
    if kind == "lowPass" { Biquad::low_pass(rate, hz) } else { Biquad::high_pass(rate, hz) }
}

// The filter's answer to a 1 at sample 0.
fn impulse_of(mut filter: Biquad) -> Vec<f64> {
    (0..FILTER_VECTOR_SAMPLES).map(|i| filter.process(if i == 0 { 1.0 } else { 0.0 })).collect()
}

// The filter's answer to 0.5 * sin(2 pi 1000 n / rate).
fn sine_of(mut filter: Biquad, rate: u32) -> Vec<f64> {
    (0..FILTER_VECTOR_SAMPLES)
        .map(|n| filter.process(0.5 * (2.0 * std::f64::consts::PI * 1_000.0 * n as f64 / rate as f64).sin()))
        .collect()
}

struct Checker {
    failures: Vec<String>,
}

impl Checker {
    fn near(&mut self, what: &str, expected: Option<f64>, actual: Option<f64>, within: f64) {
        match (expected, actual) {
            (Some(e), Some(a)) if (e - a).abs() > within => {
                self.failures.push(format!("{what}: expected {e}, got {a} (within {within})"))
            }
            (Some(_), Some(_)) | (None, None) => {}
            (e, a) => self.failures.push(format!("{what}: expected {e:?}, got {a:?}")),
        }
    }

    fn fail(&mut self, message: String) {
        self.failures.push(message);
    }
}

// Analyzes one section the way the file describes.
fn analyze(song: &SyntheticSong, section: &Value) -> SectionAnalysis {
    let envelope = song.envelope(num(section, "fromMs"), num(section, "toMs"), 4_093);
    let tag = num_or_none(section, "tagBpm");
    if text(section, "part") == "tail" {
        analyze_tail(envelope, tag, None)
    } else {
        analyze_head(envelope, tag)
    }
}

fn check(vectors: &Value) -> Vec<String> {
    let mut c = Checker { failures: Vec::new() };
    let tol = &vectors["tolerances"];
    let t = |name: &str| num(tol, name);

    let songs: HashMap<String, SyntheticSong> = vectors["songs"]
        .as_object()
        .expect("songs")
        .iter()
        .map(|(name, song)| (name.clone(), song_of(song)))
        .collect();

    // The sections are independent; analyze them on a few threads, leaving
    // room for the engine's timing tests running alongside.
    let sections = list(vectors, "sections");
    let workers = 4;
    let analyses: Vec<SectionAnalysis> = std::thread::scope(|scope| {
        let jobs: Vec<_> = (0..workers)
            .map(|w| {
                let songs = &songs;
                scope.spawn(move || {
                    let mine = sections.iter().enumerate().skip(w).step_by(workers);
                    mine.map(|(i, section)| (i, analyze(&songs[text(section, "song")], section)))
                        .collect::<Vec<_>>()
                })
            })
            .collect();
        let mut all: Vec<_> = jobs.into_iter().flat_map(|j| j.join().expect("analysis")).collect();
        all.sort_by_key(|(i, _)| *i);
        all.into_iter().map(|(_, a)| a).collect()
    });

    let mut untagged: HashMap<String, &SectionAnalysis> = HashMap::new();
    for (section, analysis) in sections.iter().zip(&analyses) {
        let name = text(section, "song");
        let part = text(section, "part");
        let tag = num_or_none(section, "tagBpm");
        let what = match tag {
            None => format!("{name} {part}"),
            Some(tag) => format!("{name} {part} tagged {tag}"),
        };
        if tag.is_none() {
            untagged.insert(format!("{name}/{part}"), analysis);
        }
        let envelope = &analysis.envelope;
        if envelope.size() as i64 != int(section, "hops") {
            c.fail(format!("{what}: {} hops", envelope.size()));
        }
        if envelope.start_ms != int(section, "startMs") {
            c.fail(format!("{what}: starts at {}", envelope.start_ms));
        }
        for probe in list(section, "probes") {
            let i = int(probe, "index") as usize;
            let at = |values: &Vec<f32>| values.get(i).map(|&v| v as f64);
            c.near(&format!("{what} hop {i} db"), Some(num(probe, "db")), at(&envelope.db), t("db"));
            c.near(
                &format!("{what} hop {i} lowDb"),
                Some(num(probe, "lowDb")),
                at(&envelope.low_db),
                t("db"),
            );
            c.near(
                &format!("{what} hop {i} onset"),
                Some(num(probe, "onset")),
                at(&envelope.onset),
                t("onset"),
            );
            c.near(
                &format!("{what} hop {i} lowOnset"),
                Some(num(probe, "lowOnset")),
                at(&envelope.low_onset),
                t("onset"),
            );
        }
        let expected = &section["features"];
        let f = &analysis.features;
        let ms = |v: Option<i64>| v.map(|v| v as f64);
        c.near(&format!("{what} bodyDb"), Some(num(expected, "bodyDb")), Some(f.body_db), t("db"));
        c.near(&format!("{what} gateDb"), Some(num(expected, "gateDb")), Some(f.gate_db), t("db"));
        c.near(
            &format!("{what} soundStartMs"),
            num_or_none(expected, "soundStartMs"),
            ms(f.sound_start_ms),
            t("ms"),
        );
        c.near(
            &format!("{what} soundEndMs"),
            num_or_none(expected, "soundEndMs"),
            ms(f.sound_end_ms),
            t("ms"),
        );
        c.near(
            &format!("{what} outroStartMs"),
            num_or_none(expected, "outroStartMs"),
            ms(f.outro_start_ms),
            t("ms"),
        );
        c.near(
            &format!("{what} introEndMs"),
            num_or_none(expected, "introEndMs"),
            ms(f.intro_end_ms),
            t("ms"),
        );
        let boundaries: Vec<f64> = list(expected, "boundariesMs").iter().filter_map(Value::as_f64).collect();
        if boundaries.len() != f.boundaries_ms.len() {
            c.fail(format!("{what} boundaries: expected {boundaries:?}, got {:?}", f.boundaries_ms));
        } else {
            for (e, a) in boundaries.iter().zip(&f.boundaries_ms) {
                c.near(&format!("{what} boundary"), Some(*e), Some(*a as f64), t("ms"));
            }
        }
        match (&expected["tempo"], &f.tempo) {
            (Value::Null, None) => {}
            (Value::Null, Some(a)) => c.fail(format!("{what}: expected no tempo, got {a:?}")),
            (_, None) => c.fail(format!("{what}: expected a tempo, got none")),
            (e, Some(a)) => {
                c.near(&format!("{what} bpm"), Some(num(e, "bpm")), Some(a.bpm), t("bpm"));
                let confidence = num(e, "confidence");
                c.near(
                    &format!("{what} confidence"),
                    Some(confidence),
                    Some(a.confidence),
                    confidence * t("confidenceShare"),
                );
                c.near(
                    &format!("{what} consistency"),
                    Some(num(e, "consistency")),
                    Some(a.consistency),
                    0.02,
                );
                if flag(e, "steady") != a.steady {
                    c.fail(format!("{what}: steady {}", a.steady));
                }
                if flag(e, "confident") != a.confident() {
                    c.fail(format!("{what}: confident {}", a.confident()));
                }
                c.near(&format!("{what} beatMs"), Some(num(e, "beatMs")), Some(a.beat_ms), t("ms") / 10.0);
                c.near(
                    &format!("{what} firstBeatMs"),
                    Some(num(e, "firstBeatMs")),
                    Some(a.first_beat_ms),
                    t("ms"),
                );
                c.near(
                    &format!("{what} downbeatMs"),
                    Some(num(e, "downbeatMs")),
                    Some(a.downbeat_ms),
                    t("ms"),
                );
            }
        }
    }

    for case in list(vectors, "plans") {
        let name = text(case, "name");
        let settings = &case["settings"];
        let next = fade_song_of(&case["next"]);
        let tail = (!flag(case, "tailMissing")).then(|| untagged[&format!("{}/tail", text(case, "a"))]);
        let head = (!flag(case, "headMissing")).then(|| untagged[&format!("{}/head", text(case, "b"))]);
        let plan = plan_transition(
            &fade_song_of(&case["current"]),
            Some(&next),
            tail,
            head,
            &PlanSettings {
                max_overlap_ms: int(settings, "maxOverlapMs"),
                smart: flag(settings, "smart"),
                filter_sweeps: flag(settings, "filterSweeps"),
                beat_match: flag(settings, "beatMatch"),
                fade_curve: FadeCurve::EqualPower,
            },
            &context_of(&case["context"]),
        );
        let e = &case["expected"];
        let what = format!("plan {name}");
        if text(e, "kind") != plan.kind.name() {
            c.fail(format!("{what}: kind {}, expected {}", plan.kind.name(), text(e, "kind")));
        }
        c.near(&format!("{what} startMs"), Some(num(e, "startMs")), Some(plan.start_ms as f64), t("ms"));
        c.near(&format!("{what} entryMs"), Some(num(e, "entryMs")), Some(plan.entry_ms as f64), t("ms"));
        c.near(
            &format!("{what} overlapMs"),
            Some(num(e, "overlapMs")),
            Some(plan.overlap_ms as f64),
            t("ms"),
        );
        c.near(&format!("{what} k"), Some(num(e, "k")), Some(plan.k), t("curve"));
        c.near(
            &format!("{what} filterStrength"),
            Some(num(e, "filterStrength")),
            Some(plan.filter_strength),
            t("curve"),
        );
        c.near(
            &format!("{what} beatMatchRate"),
            num_or_none(e, "beatMatchRate"),
            plan.beat_match_rate,
            t("rate") * 10.0,
        );
        c.near(&format!("{what} beatMs"), num_or_none(e, "beatMs"), plan.beat_ms, t("ms") / 10.0);
        c.near(&format!("{what} beatAnchorMs"), num_or_none(e, "beatAnchorMs"), plan.beat_anchor_ms, t("ms"));
        c.near(&format!("{what} headroomDb"), Some(num(e, "headroomDb")), Some(plan.headroom_db), t("curve"));
        if flag(e, "late") != plan.late {
            c.fail(format!("{what}: late {}", plan.late));
        }
        if text(e, "reason") != plan.reason {
            c.fail(format!("{what}: reason \"{}\", expected \"{}\"", plan.reason, text(e, "reason")));
        }
    }

    for g in list(vectors, "gains") {
        let (time, k) = (num(g, "t"), num(g, "k"));
        c.near(
            &format!("out gain at {time} k {k}"),
            Some(num(g, "out")),
            Some(automix_out_gain(time, k)),
            t("curve"),
        );
        c.near(
            &format!("in gain at {time} k {k}"),
            Some(num(g, "in")),
            Some(automix_in_gain(time, k)),
            t("curve"),
        );
    }
    for f in list(vectors, "filters") {
        let (time, s) = (num(f, "t"), num(f, "strength"));
        let cases = [
            ("low-pass", "outgoingLowPassHz", outgoing_low_pass_hz(time, s)),
            ("bass cut", "outgoingHighPassHz", outgoing_high_pass_hz(time, s)),
            ("incoming high-pass", "incomingHighPassHz", incoming_high_pass_hz(time, s)),
        ];
        for (label, key, actual) in cases {
            let expected = num(f, key);
            c.near(
                &format!("{label} at {time} strength {s}"),
                Some(expected),
                Some(actual),
                expected * t("hzShare"),
            );
        }
    }
    for f in list(vectors, "steppedLowPass") {
        let beats: Vec<f64> = list(f, "beats").iter().filter_map(Value::as_f64).collect();
        let actual = stepped_outgoing_low_pass_hz(num(f, "t"), num(f, "strength"), &beats, num(f, "glide"));
        let expected = num(f, "hz");
        c.near(
            &format!("stepped low-pass at {}", num(f, "t")),
            Some(expected),
            Some(actual),
            expected * t("hzShare"),
        );
    }
    for f in list(vectors, "biquads") {
        let kind = text(f, "type");
        let rate = int(f, "rate") as u32;
        let hz = num(f, "hz");
        let what = format!("{kind} at {hz} Hz, {rate} Hz");
        let q = num(f, "q");
        let filter = if kind == "lowPass" {
            Biquad::low_pass_q(rate, hz, q)
        } else {
            Biquad::high_pass_q(rate, hz, q)
        };
        let expected = list(f, "coefficients");
        for (i, actual) in [filter.b0, filter.b1, filter.b2, filter.a1, filter.a2].into_iter().enumerate() {
            c.near(&format!("{what} coefficient {i}"), expected[i].as_f64(), Some(actual), t("sample"));
        }
        let impulse = impulse_of(biquad_of(kind, rate, hz));
        for (i, x) in list(f, "impulse").iter().enumerate() {
            c.near(&format!("{what} impulse {i}"), x.as_f64(), impulse.get(i).copied(), t("sample"));
        }
        let sine = sine_of(biquad_of(kind, rate, hz), rate);
        for (i, x) in list(f, "sine").iter().enumerate() {
            c.near(&format!("{what} sine {i}"), x.as_f64(), sine.get(i).copied(), t("sample"));
        }
    }
    for v in list(vectors, "tempoTrust") {
        let (confidence, steady) = (num(v, "confidence"), flag(v, "steady"));
        let tempo = Tempo {
            bpm: 120.0,
            confidence,
            consistency: 1.0,
            steady,
            beat_ms: 500.0,
            first_beat_ms: 0.0,
            downbeat_ms: 0.0,
        };
        if tempo.confident() != flag(v, "confident") {
            c.fail(format!("tempo scoring {confidence}, steady {steady}: confident {}", tempo.confident()));
        }
    }
    for r in list(vectors, "rates") {
        let actual = beat_match_rate_at(num(r, "rate"), num(r, "sinceEntryMs"), num(r, "overlapMs"));
        c.near(
            &format!("rate at {}", num(r, "sinceEntryMs")),
            Some(num(r, "value")),
            Some(actual),
            t("curve"),
        );
    }
    c.failures
}

#[test]
fn every_shared_vector_matches() {
    let raw = std::fs::read_to_string(vectors_path()).expect("the shared automix vectors");
    let vectors: Value = serde_json::from_str(&raw).expect("the vectors are JSON");
    assert_eq!(vectors["version"].as_i64(), Some(1), "a vectors version this test does not know");
    let failures = check(&vectors);
    assert!(failures.is_empty(), "{} off:\n{}", failures.len(), failures.join("\n"));
}
