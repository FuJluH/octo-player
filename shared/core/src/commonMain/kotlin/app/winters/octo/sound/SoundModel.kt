package app.winters.octo.sound

import kotlinx.serialization.Serializable
import kotlin.math.PI
import kotlin.math.cos
import kotlin.math.log10
import kotlin.math.pow
import kotlin.math.sin
import kotlin.math.sqrt

// The shapes a filter can take: a bump or dip around one frequency, or a
// lift or cut of everything below or above one.
enum class FilterType { Peak, LowShelf, HighShelf }

@Serializable
data class EqFilter(
    val type: FilterType = FilterType.Peak,
    val frequency: Float,
    val gainDb: Float,
    val q: Float = GRAPHIC_Q,
    val enabled: Boolean = true,
)

// Ten sliders at fixed frequencies, or filters moved freely on the curve.
enum class EqMode { Graphic, Parametric }

// Evening out loudness between songs: off, per song, per album, or per
// album only while an album plays in order.
enum class ReplayGainMode { Off, Track, Album, Smart }

// The ten standard octave bands, in hertz.
val GraphicBands = listOf(31f, 62f, 125f, 250f, 500f, 1_000f, 2_000f, 4_000f, 8_000f, 16_000f)

// The width of one octave band.
const val GRAPHIC_Q = 1.41f

// How far a slider goes either way, in decibels.
const val GAIN_RANGE_DB = 12f

// A correction for one model of headphones, made from its measurements.
@Serializable
data class HeadphoneCorrection(
    val name: String,
    // Who measured them, for the credit line.
    val source: String,
    val preampDb: Float,
    val filters: List<EqFilter>,
)

// Everything that shapes the sound on one output.
@Serializable
data class SoundSettings(
    val eqEnabled: Boolean = false,
    val mode: EqMode = EqMode.Graphic,
    val graphicGains: List<Float> = List(GraphicBands.size) { 0f },
    val filters: List<EqFilter> = emptyList(),
    // The preset the curve came from, until it is changed by hand.
    val preset: String? = "Flat",
    val preampDb: Float = 0f,
    // Lowers the level by the curve's highest boost, so boosting never clips.
    val autoPreamp: Boolean = true,
    val correction: HeadphoneCorrection? = null,
    val replayGain: ReplayGainMode = ReplayGainMode.Off,
    val replayGainPreampDb: Float = 0f,
    // For songs with no loudness tags.
    val replayGainFallbackDb: Float = 0f,
    val preventClipping: Boolean = true,
    // Catches any peak that would still clip, just below full scale.
    val limiter: Boolean = true,
    // From -1 (all left) to 1 (all right).
    val balance: Float = 0f,
    val mono: Boolean = false,
    // Each ear hears a little of the other side, for headphones.
    val crossfeed: Crossfeed = Crossfeed(),
) {
    // The filters the equalizer applies now: the headphone correction first,
    // then the user's own curve.
    fun activeFilters(): List<EqFilter> {
        if (!eqEnabled) return emptyList()
        val own = when (mode) {
            EqMode.Graphic -> GraphicBands.zip(graphicGains) { f, g -> EqFilter(FilterType.Peak, f, g, GRAPHIC_Q) }
            EqMode.Parametric -> filters
        }
        return (correction?.filters.orEmpty() + own).filter { it.enabled && it.gainDb != 0f }
    }

    // The level change before the filters, in decibels: set by hand (with a
    // headphone correction's own preamp), or just enough to take back the
    // curve's highest boost.
    fun effectivePreampDb(sampleRate: Int = 48_000): Float {
        if (!eqEnabled) return 0f
        return if (autoPreamp) {
            -maxOf(0f, ResponseCurve.peakDb(activeFilters(), sampleRate))
        } else {
            (correction?.preampDb ?: 0f) + preampDb
        }
    }
}

// A named curve for the ten bands.
data class EqPreset(val name: String, val gains: List<Float>)

// Built-in curves. The genre ones follow Android's own presets, spread onto
// ten bands; the rest are tuned by ear for what their names promise.
val EqPresets = listOf(
    EqPreset("Flat", listOf(0f, 0f, 0f, 0f, 0f, 0f, 0f, 0f, 0f, 0f)),
    EqPreset("Bass Boost", listOf(6f, 5.5f, 4.5f, 2.5f, 0.5f, 0f, 0f, 0f, 0f, 0f)),
    EqPreset("Bass Reducer", listOf(-6f, -5f, -4f, -2.5f, -1f, 0f, 0f, 0f, 0f, 0f)),
    EqPreset("Treble Boost", listOf(0f, 0f, 0f, 0f, 0f, 0.5f, 1.5f, 3.5f, 5f, 6f)),
    EqPreset("Treble Reducer", listOf(0f, 0f, 0f, 0f, 0f, -0.5f, -1.5f, -3.5f, -5f, -6f)),
    EqPreset("Vocal", listOf(-2f, -2f, -1f, 0.5f, 2f, 3.5f, 3.5f, 2.5f, 1f, 0f)),
    EqPreset("Rock", listOf(5f, 5f, 4f, 3f, 0.5f, -0.5f, 1.5f, 3f, 4f, 5f)),
    EqPreset("Pop", listOf(-1f, -1f, 0.5f, 2f, 3.5f, 4.5f, 2.5f, 1f, -1f, -2f)),
    EqPreset("Jazz", listOf(4f, 4f, 3f, 2f, -0.5f, -1.5f, 0.5f, 2f, 4f, 5f)),
    EqPreset("Classical", listOf(5f, 5f, 4f, 2.5f, 0f, -1.5f, 1.5f, 4f, 4f, 4f)),
    EqPreset("Electronic", listOf(6f, 6f, 2.5f, 0f, 1f, 2f, 3f, 4f, 2f, 1f)),
    EqPreset("Hip-Hop", listOf(5f, 5f, 4f, 3f, 1.5f, 0f, 0.5f, 1f, 2f, 3f)),
    EqPreset("Metal", listOf(4f, 4f, 2.5f, 1.5f, 5.5f, 8.5f, 5.5f, 3f, 1f, 0f)),
    EqPreset("Folk", listOf(3f, 3f, 1.5f, 0f, 0f, 0f, 1f, 2f, 0f, -1f)),
    EqPreset("Acoustic", listOf(3f, 3f, 2.5f, 1f, 1f, 0.5f, 1.5f, 2.5f, 2.5f, 1.5f)),
    EqPreset("Loudness", listOf(6f, 5f, 3f, 1f, 0f, 0f, 0f, 1f, 3f, 4f)),
    EqPreset("Late Night", listOf(-4f, -3f, -1.5f, 0f, 0.5f, 1f, 2f, 1.5f, 0f, -1f)),
    EqPreset("Spoken Word", listOf(-6f, -5f, -3f, -1f, 1f, 2.5f, 3.5f, 2.5f, 0f, -2f)),
    EqPreset("Small Speakers", listOf(-6f, -3f, 2f, 3f, 1.5f, 0f, 0f, 1.5f, 2.5f, 1f)),
)

// One filter's coefficients, normalised so a0 is 1.
data class Coefficients(val b0: Double, val b1: Double, val b2: Double, val a1: Double, val a2: Double)

// The standard formulas for these filters (the Audio EQ Cookbook).
fun coefficients(filter: EqFilter, sampleRate: Int): Coefficients {
    val a = 10.0.pow(filter.gainDb / 40.0)
    val w0 = 2 * PI * filter.frequency / sampleRate
    val c = cos(w0)
    val alpha = sin(w0) / (2 * filter.q)
    return when (filter.type) {
        FilterType.Peak -> normalise(1 + alpha * a, -2 * c, 1 - alpha * a, 1 + alpha / a, -2 * c, 1 - alpha / a)
        FilterType.LowShelf -> {
            val s = 2 * sqrt(a) * alpha
            normalise(
                a * ((a + 1) - (a - 1) * c + s), 2 * a * ((a - 1) - (a + 1) * c), a * ((a + 1) - (a - 1) * c - s),
                (a + 1) + (a - 1) * c + s, -2 * ((a - 1) + (a + 1) * c), (a + 1) + (a - 1) * c - s,
            )
        }
        FilterType.HighShelf -> {
            val s = 2 * sqrt(a) * alpha
            normalise(
                a * ((a + 1) + (a - 1) * c + s), -2 * a * ((a - 1) + (a + 1) * c), a * ((a + 1) + (a - 1) * c - s),
                (a + 1) - (a - 1) * c + s, 2 * ((a - 1) - (a + 1) * c), (a + 1) - (a - 1) * c - s,
            )
        }
    }
}

private fun normalise(b0: Double, b1: Double, b2: Double, a0: Double, a1: Double, a2: Double) =
    Coefficients(b0 / a0, b1 / a0, b2 / a0, a1 / a0, a2 / a0)

// How filters change the level at each frequency, for drawing the curve and
// for keeping boosts from clipping.
object ResponseCurve {
    // Log-spaced frequencies from 20 Hz to 20 kHz.
    fun frequencies(points: Int = 256): List<Float> =
        List(points) { i -> (20.0 * 1_000.0.pow(i.toDouble() / (points - 1))).toFloat() }

    // The change in decibels at one frequency.
    fun gainDb(filters: List<EqFilter>, frequency: Float, sampleRate: Int = 48_000): Float =
        filters.filter { it.frequency < sampleRate * 0.45f }.sumOf { magnitudeDb(coefficients(it, sampleRate), frequency, sampleRate) }.toFloat()

    fun curve(filters: List<EqFilter>, points: Int = 256, sampleRate: Int = 48_000): List<Float> =
        frequencies(points).map { gainDb(filters, it, sampleRate) }

    // The highest boost anywhere on the curve.
    fun peakDb(filters: List<EqFilter>, sampleRate: Int = 48_000): Float =
        if (filters.isEmpty()) 0f else curve(filters, 512, sampleRate).max()

    private fun magnitudeDb(k: Coefficients, frequency: Float, sampleRate: Int): Double {
        val phi = sin(PI * frequency / sampleRate).pow(2)
        fun part(x0: Double, x1: Double, x2: Double) =
            (x0 + x1 + x2).pow(2) - 4 * (x0 * x1 + 4 * x0 * x2 + x1 * x2) * phi + 16 * x0 * x2 * phi * phi
        val num = part(k.b0, k.b1, k.b2)
        val den = part(1.0, k.a1, k.a2)
        return 10 * log10(num / den)
    }
}
