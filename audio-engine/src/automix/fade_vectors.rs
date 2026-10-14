//! The crossfade curves against the shared vectors
//! (`shared/core/src/commonTest/resources/fade-curve-vectors.json`), which
//! the app's own copy of the curves checks too.

use std::path::PathBuf;

use serde_json::Value;

use super::*;
use crate::crossfade::FadeSong;

fn vectors() -> Value {
    let path = PathBuf::from(env!("CARGO_MANIFEST_DIR"))
        .join("../shared/core/src/commonTest/resources/fade-curve-vectors.json");
    let text = std::fs::read_to_string(&path).unwrap_or_else(|e| panic!("{}: {e}", path.display()));
    serde_json::from_str(&text).expect("the fade curve vectors are JSON")
}

fn curve_named(name: &str) -> FadeCurve {
    match name {
        "EqualPower" => FadeCurve::EqualPower,
        "Linear" => FadeCurve::Linear,
        "SCurve" => FadeCurve::SCurve,
        "EvenLoudness" => FadeCurve::EvenLoudness,
        "MixOnly" => FadeCurve::MixOnly,
        other => panic!("unknown curve {other}"),
    }
}

#[test]
fn every_fade_curve_vector_matches() {
    let vectors = vectors();
    let tolerance = vectors["tolerance"].as_f64().unwrap();
    let mut failures = Vec::new();
    for case in vectors["cases"].as_array().unwrap() {
        let curve = curve_named(case["curve"].as_str().unwrap());
        let overlap = case["overlapMs"].as_f64().unwrap();
        for point in case["points"].as_array().unwrap() {
            let t = point["t"].as_f64().unwrap();
            let (out, gain_in) = fade_gains(curve, t, overlap);
            let (want_out, want_in) = (point["out"].as_f64().unwrap(), point["in"].as_f64().unwrap());
            if (out - want_out).abs() > tolerance || (gain_in - want_in).abs() > tolerance {
                failures.push(format!(
                    "{curve:?} over {overlap} ms at {t}: ({out}, {gain_in}), want ({want_out}, {want_in})"
                ));
            }
        }
    }
    assert!(failures.is_empty(), "{}", failures.join("\n"));
}

#[test]
fn equal_power_is_the_crossfade_as_it_was() {
    for i in 0..=100 {
        let t = i as f64 / 100.0;
        assert_eq!(fade_gains(FadeCurve::EqualPower, t, 8_000.0), gains(t, 0.0));
    }
    let plan = TransitionPlan::fixed_crossfade(200_000, 8_000, "test");
    assert_eq!(plan.curve, FadeCurve::EqualPower);
    assert_eq!(plan.headroom_db, 0.0);
    assert_eq!(plan.out_gain(0.3), automix_out_gain(0.3, 0.0));
}

#[test]
fn every_curve_runs_from_the_old_song_to_the_new_one_and_never_raises_one() {
    let curves = [
        FadeCurve::EqualPower,
        FadeCurve::Linear,
        FadeCurve::SCurve,
        FadeCurve::EvenLoudness,
        FadeCurve::MixOnly,
    ];
    for curve in curves {
        for overlap in [400.0, 8_000.0] {
            let (out0, in0) = fade_gains(curve, 0.0, overlap);
            let (out1, in1) = fade_gains(curve, 1.0, overlap);
            assert!((out0 - 1.0).abs() < 1e-12 && in0.abs() < 1e-12, "{curve:?} start");
            assert!(out1.abs() < 1e-12 && (in1 - 1.0).abs() < 1e-12, "{curve:?} end");
            let (mut last_out, mut last_in) = (1.0, 0.0);
            for i in 0..=1_000 {
                let (out, gain_in) = fade_gains(curve, i as f64 / 1_000.0, overlap);
                assert!((0.0..=1.0).contains(&out) && (0.0..=1.0).contains(&gain_in), "{curve:?} in range");
                assert!(out <= last_out + 1e-12 && gain_in >= last_in - 1e-12, "{curve:?} one way");
                (last_out, last_in) = (out, gain_in);
            }
        }
    }
}

#[test]
fn the_curve_shapes_only_the_crossfade_with_smart_transitions_off() {
    let a = FadeSong { album_id: Some("a".into()), album_order: Some(1), duration_ms: 200_000 };
    let b = FadeSong { album_id: Some("b".into()), album_order: Some(1), duration_ms: 180_000 };
    let context = TransitionContext::default();
    let off = PlanSettings { smart: false, fade_curve: FadeCurve::MixOnly, ..PlanSettings::new(8_000) };
    let fixed = plan_transition(&a, Some(&b), None, None, &off, &context);
    assert_eq!(fixed.kind, TransitionKind::Crossfade);
    assert_eq!(fixed.curve, FadeCurve::MixOnly);
    assert_eq!(fixed.headroom_db, MIX_ONLY_HEADROOM_DB);
    assert_eq!((fixed.out_gain(0.5), fixed.in_gain(0.5)), (1.0, 1.0));
    let on = PlanSettings { fade_curve: FadeCurve::Linear, ..PlanSettings::new(8_000) };
    let planned = plan_transition(&a, Some(&b), None, None, &on, &context);
    assert_eq!(planned.curve, FadeCurve::EqualPower);
    assert_eq!(planned.out_gain(0.25), automix_out_gain(0.25, planned.k));
}
