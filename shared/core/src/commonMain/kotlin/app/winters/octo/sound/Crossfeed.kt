package app.winters.octo.sound

import kotlinx.serialization.Serializable
import kotlin.math.PI
import kotlin.math.abs
import kotlin.math.cos
import kotlin.math.exp
import kotlin.math.log10
import kotlin.math.pow
import kotlin.math.sin

// The range of the cut frequency, in hertz, and of the feed level, in
// decibels, that a custom crossfeed can be set to.
const val CROSSFEED_MIN_CUT_HZ = 300
const val CROSSFEED_MAX_CUT_HZ = 2_000
const val CROSSFEED_MIN_FEED_DB = 1f
const val CROSSFEED_MAX_FEED_DB = 15f

// A crossfeed's cut frequency (where the sound fed to the other ear has
// fallen by 3 dB) and feed level (how much quieter than the ear's own sound
// the other ear's sound is in the bass). Custom takes the listener's own.
enum class CrossfeedPreset(val cutHz: Int, val feedDb: Float) {
    Natural(700, 4.5f),
    ChuMoy(700, 6f),
    JanMeier(650, 9.5f),
    Custom(700, 4.5f),
}

// Headphone crossfeed: each ear hears a little of the other side, low
// frequencies most, as with speakers in a room. Off by default.
@Serializable
data class Crossfeed(
    val on: Boolean = false,
    val preset: CrossfeedPreset = CrossfeedPreset.Natural,
    // The listener's own values, used with Custom.
    val cutHz: Int = CrossfeedPreset.Custom.cutHz,
    val feedDb: Float = CrossfeedPreset.Custom.feedDb,
) {
    // The cut frequency in use, from the preset or the listener's own.
    val activeCutHz: Int
        get() = if (preset == CrossfeedPreset.Custom) cutHz.coerceIn(CROSSFEED_MIN_CUT_HZ, CROSSFEED_MAX_CUT_HZ) else preset.cutHz

    // The feed level in use.
    val activeFeedDb: Float
        get() = if (preset == CrossfeedPreset.Custom) feedDb.coerceIn(CROSSFEED_MIN_FEED_DB, CROSSFEED_MAX_FEED_DB) else preset.feedDb
}

// The settings as an output plays them. Crossfeed only makes sense in
// headphones, so on a speaker it stays off whatever the settings say.
fun SoundSettings.heardOn(headphones: Boolean): SoundSettings =
    if (headphones || !crossfeed.on) this else copy(crossfeed = crossfeed.copy(on = false))

// The filter behind crossfeed, one first-order low-pass on the difference
// between the two sides:
//
//   d[n] = gain * (R[n] - L[n]) + pole * d[n - 1]
//   L'[n] = L[n] + d[n]
//   R'[n] = R[n] - d[n]
//
// So each ear gets the other side through a low-pass at the cut frequency,
// and its own side through the matching high shelf (one minus that
// low-pass). In the bass the other side arrives `feedDb` below the ear's
// own; sound in the middle (the same in both ears) passes through exactly
// as it was, so the overall tone and a full-scale mono signal stay level.
data class CrossfeedCoefficients(val gain: Double, val pole: Double) {
    // The other ear's share of a side in the bass.
    val lowShare: Double get() = gain / (1 - pole)
}

fun crossfeedCoefficients(cutHz: Double, feedDb: Double, sampleRate: Int): CrossfeedCoefficients {
    val pole = exp(-2 * PI * cutHz / sampleRate)
    val feed = 10.0.pow(-feedDb / 20)
    // The bass shares of the ear's own side and of the other side add up
    // to one, the other side's being `feed` times the own side's.
    val lowShare = feed / (1 + feed)
    return CrossfeedCoefficients(gain = lowShare * (1 - pole), pole = pole)
}

fun crossfeedCoefficients(crossfeed: Crossfeed, sampleRate: Int): CrossfeedCoefficients =
    crossfeedCoefficients(crossfeed.activeCutHz.toDouble(), crossfeed.activeFeedDb.toDouble(), sampleRate)

// How loud one side comes out at `frequency`, in decibels: in its own ear
// (first) and in the other ear (second).
fun crossfeedResponseDb(c: CrossfeedCoefficients, frequency: Double, sampleRate: Int): Pair<Double, Double> {
    val w = 2 * PI * frequency / sampleRate
    // Denominator 1 - pole e^-jw, squared size.
    val den = 1 - 2 * c.pole * cos(w) + c.pole * c.pole
    val other = c.gain * c.gain / den
    // Own ear: 1 - gain / (1 - pole e^-jw) = (1 - gain - pole e^-jw) / (1 - pole e^-jw).
    val re = 1 - c.gain - c.pole * cos(w)
    val im = c.pole * sin(w)
    val own = (re * re + im * im) / den
    return 10 * log10(own) to 10 * log10(other)
}

// State this small is set to zero, so a fading tail never slows the
// processor down with tiny numbers.
private const val TINY = 1e-25

// The crossfeed for one stream: the first two channels of interleaved
// float samples, changed in place. Turning it on or off fades it in or out
// over a number of frames; a new cut or feed level carries on from the
// filter's state, so neither clicks.
class CrossfeedFilter {
    var coefficients = CrossfeedCoefficients(0.0, 0.0)
        private set

    private var state = 0.0
    private var mix = 0.0
    private var target = 0.0
    private var step = 0.0
    private var left = 0

    // Whether there is anything to do: on, or fading.
    val active: Boolean get() = mix != 0.0 || left > 0

    // Takes up new coefficients, and fades to on or off over `frames`.
    fun set(coefficients: CrossfeedCoefficients, on: Boolean, frames: Int) {
        this.coefficients = coefficients
        val next = if (on) 1.0 else 0.0
        if (next == target && (left > 0 || mix == next)) return
        target = next
        if (frames <= 0 || mix == next) {
            mix = next
            left = 0
        } else {
            step = (next - mix) / frames
            left = frames
        }
        if (!active) state = 0.0
    }

    fun process(samples: FloatArray, frames: Int, channels: Int) {
        if (channels < 2 || !active) return
        val gain = coefficients.gain
        val pole = coefficients.pole
        var d = state
        var i = 0
        for (frame in 0 until frames) {
            if (left > 0) {
                left--
                mix = if (left == 0) target else mix + step
            }
            val l = samples[i].toDouble()
            val r = samples[i + 1].toDouble()
            d = gain * (r - l) + pole * d
            samples[i] = (l + mix * d).toFloat()
            samples[i + 1] = (r - mix * d).toFloat()
            i += channels
        }
        state = if (abs(d) < TINY || !active) 0.0 else d
    }
}

// What crossfeed does, in a line.
const val CROSSFEED_ABOUT = "Blends a little of each side into the other, like speakers in a room. Eases listening fatigue on headphones."

// What the crossfeed card says on an output that is not headphones.
const val CROSSFEED_HEADPHONES_ONLY = "Crossfeed is for headphones, so it stays off here."

// What the crossfeed card says while mono is on.
const val CROSSFEED_MONO = "Off while Mono is on: both ears already hear the same."

// The preset's name in the apps.
val CrossfeedPreset.label: String
    get() = when (this) {
        CrossfeedPreset.Natural -> "Natural"
        CrossfeedPreset.ChuMoy -> "Chu Moy"
        CrossfeedPreset.JanMeier -> "Jan Meier"
        CrossfeedPreset.Custom -> "Custom"
    }

// What the preset does, in a line.
val CrossfeedPreset.detail: String
    get() = when (this) {
        CrossfeedPreset.Natural -> "The fullest blend, close to speakers in a room. 700 Hz, 4.5 dB."
        CrossfeedPreset.ChuMoy -> "A little lighter. 700 Hz, 6 dB."
        CrossfeedPreset.JanMeier -> "The lightest touch, for music that is already easy on the ears. 650 Hz, 9.5 dB."
        CrossfeedPreset.Custom -> "Set how high the blend reaches and how strong it is."
    }

// The custom sliders' readings and lines.
const val CROSSFEED_CUT_TITLE = "Up to"
const val CROSSFEED_CUT_HELP = "The other ear hears the blend below this frequency."
const val CROSSFEED_FEED_TITLE = "Other side"
const val CROSSFEED_FEED_HELP = "How much quieter the other side is. Nearer 0 dB blends more."
