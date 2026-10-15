package app.winters.octo.playback

import kotlin.math.PI
import kotlin.math.cos
import kotlin.math.max
import kotlin.math.min
import kotlin.math.pow
import kotlin.math.sin
import kotlin.math.sqrt

// The shape of the fixed crossfade: how the outgoing song's volume falls and
// the incoming song's rises as the blend goes from 0 to 1.
enum class FadeCurve {
    // cos and sin: the two songs together keep a steady loudness.
    EqualPower,

    // Straight lines, with a slight dip in the middle.
    Linear,

    // Holds each song longer, then swaps them quickly around the middle.
    SCurve,

    // The same step down in decibels every moment, to -60 dB, then silence.
    EvenLoudness,

    // Both songs play at full volume; only the edges fade.
    MixOnly,
}

// Even in loudness falls in a straight line in decibels to this level...
const val EVEN_LOUDNESS_FLOOR_DB = -60.0

// ...reached at this point of the blend, then goes straight to silence.
const val EVEN_LOUDNESS_FLOOR_AT = 0.95

// Mix only fades the incoming song in over this long at the start and the
// outgoing one out over this long at the end, each at most half the blend.
const val MIX_ONLY_EDGE_MS = 300.0

// Both songs play this much quieter through a mix only blend, so their sum
// keeps clear of clipping.
const val MIX_ONLY_HEADROOM_DB = 3.0

// The headroom a fixed crossfade with `curve` plays with.
fun fadeHeadroomDb(curve: FadeCurve): Double = if (curve == FadeCurve.MixOnly) MIX_ONLY_HEADROOM_DB else 0.0

// The share of a mix only blend `overlapMs` long that each edge takes.
private fun mixOnlyEdge(overlapMs: Double): Double = if (overlapMs <= 0) 0.5 else min(0.5, MIX_ONLY_EDGE_MS / overlapMs)

// The even in loudness volume at `p`, falling from 1 to 0.
private fun evenLoudnessFall(p: Double): Double {
    val floor = 10.0.pow(EVEN_LOUDNESS_FLOOR_DB / 20)
    return if (p <= EVEN_LOUDNESS_FLOOR_AT) {
        10.0.pow(EVEN_LOUDNESS_FLOOR_DB * p / EVEN_LOUDNESS_FLOOR_AT / 20)
    } else {
        floor * (1 - p) / (1 - EVEN_LOUDNESS_FLOOR_AT)
    }
}

// The outgoing song's volume at `t` (0 to 1) through a blend `overlapMs`
// long. Equal power is exactly automixOutGain with no curve weight.
fun fadeOutGain(curve: FadeCurve, t: Double, overlapMs: Double): Double {
    val p = t.coerceIn(0.0, 1.0)
    return when (curve) {
        FadeCurve.EqualPower -> automixOutGain(p, 0.0)
        FadeCurve.Linear -> 1 - p
        FadeCurve.SCurve -> 1 - sCurve(p)
        FadeCurve.EvenLoudness -> evenLoudnessFall(p)
        FadeCurve.MixOnly -> {
            val edge = mixOnlyEdge(overlapMs)
            val from = 1 - edge
            if (p <= from) 1.0 else if (p >= 1) 0.0 else cos((p - from) / edge * PI / 2)
        }
    }.coerceIn(0.0, 1.0)
}

// The incoming song's volume at `t` through a blend `overlapMs` long.
fun fadeInGain(curve: FadeCurve, t: Double, overlapMs: Double): Double {
    val p = t.coerceIn(0.0, 1.0)
    return when (curve) {
        FadeCurve.EqualPower -> automixInGain(p, 0.0)
        FadeCurve.Linear -> p
        // Whatever keeps the two volumes' squares at one.
        FadeCurve.SCurve -> {
            val out = 1 - sCurve(p)
            sqrt(max(0.0, 1 - out * out))
        }
        FadeCurve.EvenLoudness -> evenLoudnessFall(1 - p)
        FadeCurve.MixOnly -> {
            val edge = mixOnlyEdge(overlapMs)
            if (p >= edge) 1.0 else sin(p / edge * PI / 2)
        }
    }.coerceIn(0.0, 1.0)
}

// Both volumes at once: outgoing, then incoming.
fun fadeGains(curve: FadeCurve, t: Double, overlapMs: Double): Pair<Double, Double> =
    fadeOutGain(curve, t, overlapMs) to fadeInGain(curve, t, overlapMs)

// The curve's name in the apps.
val FadeCurve.label: String
    get() = when (this) {
        FadeCurve.EqualPower -> "Equal power"
        FadeCurve.Linear -> "Linear"
        FadeCurve.SCurve -> "S-curve"
        FadeCurve.EvenLoudness -> "Even in loudness"
        FadeCurve.MixOnly -> "Mix only"
    }

// What the curve sounds like, in a line.
val FadeCurve.detail: String
    get() = when (this) {
        FadeCurve.EqualPower -> "Steady loudness from one song to the next."
        FadeCurve.Linear -> "A straight fade, with a slight dip in the middle."
        FadeCurve.SCurve -> "Holds each song longer, then swaps them quickly in the middle."
        FadeCurve.EvenLoudness -> "Fades by the same step every second, so the middle dips low."
        FadeCurve.MixOnly -> "Both songs play full over each other, like a DJ, a little quieter so they don't distort."
    }

// What the crossfade curve row says while smart transitions pick the
// curves: why it cannot be chosen, and the switch, just below it, that
// makes it choosable.
const val SMART_PICKS_THE_CURVE = "Smart transitions picks the curve for each blend. Turn off Smart transitions, just below, to choose one."

// The crossfade curve row's reading while smart transitions pick the curves.
const val SMART_CURVE_VALUE = "Picked for each blend"

// How the crossfade curve row shows: whether it can be chosen, the reading
// on its right, and the line under its title. Smart transitions shape each
// blend themselves, so the curve is only chosen with them off.
data class CurveRowLook(val choosable: Boolean, val value: String, val helper: String)

fun curveRowLook(curve: FadeCurve, smartTransitions: Boolean): CurveRowLook =
    if (smartTransitions) {
        CurveRowLook(choosable = false, value = SMART_CURVE_VALUE, helper = SMART_PICKS_THE_CURVE)
    } else {
        CurveRowLook(choosable = true, value = curve.label, helper = curve.detail)
    }
