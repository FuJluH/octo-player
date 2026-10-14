package app.winters.octo.lyrics.engine

import kotlin.math.PI
import kotlin.math.abs
import kotlin.math.ceil
import kotlin.math.exp
import kotlin.math.max
import kotlin.math.min
import kotlin.math.pow
import kotlin.math.roundToInt
import kotlin.math.sin
import kotlin.math.sqrt

// Everything here is plain arithmetic on the lyric clock, so it can be
// checked without a screen. Times are in seconds, sizes in pixels unless
// they say em (the main line's font size).

// ---- Line layout ----

// The focus line's middle sits this far down the view. A third of the way
// down, with the sung lines above it, so the lyrics use the whole screen
// rather than only its lower half.
const val FOCUS_AT = 0.33

// Where line `i` goes so the anchor line `a` sits at the focus: every line
// stacked on the ones above it, shifted so the anchor's middle lands at
// 47% of the view. `above` holds, for each line, the height of all lines
// before it (one more entry than there are lines).
fun targetY(i: Int, a: Int, above: DoubleArray, heights: DoubleArray, viewHeight: Double): Double =
    above[i] - above[a] + (FOCUS_AT * viewHeight - heights[a] / 2)

// The running heights `targetY` needs.
fun heightsAbove(heights: DoubleArray): DoubleArray {
    val above = DoubleArray(heights.size + 1)
    for (i in heights.indices) above[i + 1] = above[i] + heights[i]
    return above
}

// Lines count as on screen from a little above the top to a little below
// the bottom; outside that they jump instead of moving.
fun onScreen(y: Double, height: Double, viewHeight: Double): Boolean =
    y >= -(height + 0.3 * viewHeight) && y <= 1.3 * viewHeight

// A line never springs further than this many views; it is moved closer
// first.
const val MAX_TRAVEL_VIEWS = 1.5

// ---- The ripple ----

const val CASCADE_STEP_S = 0.05
const val CASCADE_SHRINK = 1.05

// How long each line waits before heading for its new place when the focus
// moves, so the lines ripple up one after another. Walking down the lines
// on screen, each waits one step longer than the one above; from the focus
// line down, the step shrinks a little each line, so the ripple tightens
// below it. Lines off screen do not wait. `stepScale` is the Ripple
// setting.
fun cascadeDelays(targets: DoubleArray, focus: Int, viewHeight: Double, stepScale: Double): DoubleArray {
    val delays = DoubleArray(targets.size)
    var step = CASCADE_STEP_S * stepScale
    var waited = 0.0
    for (i in targets.indices) {
        val y = targets[i]
        if (y < 0 || y > viewHeight) continue
        delays[i] = waited
        waited += step
        if (i >= focus) step /= CASCADE_SHRINK
    }
    return delays
}

// ---- How each line looks ----

enum class LineStatus { Upcoming, Active, Passed }

const val UPCOMING_OPACITY = 0.55
const val PASSED_SHOWN_OPACITY = 0.45
const val MAX_BLUR = 3.0

// Opacity and blur settle toward their targets with this time constant.
const val FADE_TIME_S = 0.12
const val OPACITY_SNAP = 0.002
const val BLUR_SNAP = 0.01

fun opacityTarget(status: LineStatus, showPassed: Boolean): Double = when (status) {
    LineStatus.Active -> 1.0
    LineStatus.Upcoming -> UPCOMING_OPACITY
    LineStatus.Passed -> if (showPassed) PASSED_SHOWN_OPACITY else 0.0
}

// Sharp for the lines being sung, softer the further a line is from the focus,
// but gently: the next lines stay readable at a glance.
fun blurTarget(status: LineStatus, distance: Int): Double =
    if (status == LineStatus.Active) 0.0 else min(MAX_BLUR, 0.4 + 0.6 * distance)

// One frame of settling toward a target, the same at any frame rate.
fun settle(current: Double, target: Double, dt: Double, snap: Double): Double {
    val next = current + (target - current) * (1 - exp(-dt / FADE_TIME_S))
    return if (abs(target - next) <= snap) target else next
}

// The blur as drawn: in quarter steps, and none below a tenth of a pixel.
fun shownBlur(blur: Double): Double {
    val stepped = (blur * 4).roundToInt() / 4.0
    return if (stepped < 0.1) 0.0 else stepped
}

// ---- Brightness ----

// How bright a line's sung and unsung words are.
data class Brightness(val bright: Double, val dark: Double)

// Touching a line lights it right up.
val TouchedBrightness = Brightness(1.0, 0.85)

// Follows the line's size: `grown` is 0 at the other lines' size and 1 at
// full size (the scale spring's own value), so a line dims as it shrinks.
// At full size sung words are at 100% and the rest at 40%; other lines are
// 30% all through. Rounded to 0.02 so tiny changes do not redraw.
fun brightness(grown: Double): Brightness {
    val e = grown.coerceIn(0.0, 1.0)
    return Brightness(round2(0.3 + 0.7 * e), round2(0.3 + 0.1 * e))
}

private fun round2(value: Double): Double = (value * 50).roundToInt() / 50.0

// ---- The word fill ----

// The fill is an alpha mask slid across the word: bright, a soft edge, then
// dark, wider than the word so it can slide right off either side. The
// soft edge is always half a line height wide (times the Fill softness
// setting). `size` is the mask's width in word widths; the stops are
// fractions of the mask's width.
data class MaskShape(val edge: Double, val size: Double, val brightStop: Double, val darkStop: Double)

fun maskShape(wordWidth: Double, lineHeight: Double, softness: Double): MaskShape {
    val f = if (wordWidth > 0) (0.5 * lineHeight * softness) / wordWidth else 0.0
    val size = 2 + f
    val v = f / size
    val bright = (1 - v) / 2
    return MaskShape(f, size, bright, bright + v)
}

// Where the mask's left edge goes for this much of the word sung: at 0 the
// dark part covers the word, at 1 the bright part does. Right-to-left
// words use the mask mirrored (dark on the left), so it slides the other
// way.
fun maskLeft(progress: Double, wordLeft: Double, wordWidth: Double, shape: MaskShape, rtl: Boolean): Double {
    val travel = (1 + shape.edge) * wordWidth
    val p = progress.coerceIn(0.0, 1.0)
    return if (rtl) wordLeft - p * travel else wordLeft - (1 - p) * travel
}

// How much of a word is sung: none before it starts, all after it ends,
// evenly in between.
fun wordProgress(t: Double, start: Double, end: Double): Double = when {
    t <= start -> 0.0
    t >= end -> 1.0
    else -> (t - start) / (end - start)
}

// The fill sets off a little before the word, by as long as its soft edge
// takes to cross half its own width. Without that, the middle of the edge
// is still half an edge short of the word as it is sung, so the word lights
// late. With it, the middle of the edge is on the word's first letter as the
// word starts and the word is mostly lit by the middle of its time. The
// mask's path and speed stay as they are. Long, narrow words lead by no
// more than a quarter second. `edge` is the soft edge in word widths.
const val FILL_LEAD_MAX_S = 0.25

fun fillLead(start: Double, end: Double, edge: Double): Double {
    val length = end - start
    if (length <= 0.0 || edge <= 0.0) return 0.0
    return min(FILL_LEAD_MAX_S, length * edge / (2 * (1 + edge)))
}

// How much of a word the fill has covered by `t`.
fun fillProgress(t: Double, start: Double, end: Double, edge: Double): Double =
    wordProgress(t + fillLead(start, end, edge), start, end)

// ---- Easing ----

// A CSS-style cubic-bezier timing curve from (0,0) to (1,1).
class CubicBezier(private val x1: Double, private val y1: Double, private val x2: Double, private val y2: Double) {
    private fun curve(a: Double, b: Double, u: Double): Double {
        val v = 1 - u
        return 3 * v * v * u * a + 3 * v * u * u * b + u * u * u
    }

    private fun slope(a: Double, b: Double, u: Double): Double {
        val v = 1 - u
        return 3 * v * v * a + 6 * v * u * (b - a) + 3 * u * u * (1 - b)
    }

    // The curve's height where it is `x` of the way along.
    fun at(x: Double): Double {
        if (x <= 0) return 0.0
        if (x >= 1) return 1.0
        // Newton's method first, with halving as the fallback.
        var u = x
        repeat(8) {
            val error = curve(x1, x2, u) - x
            if (abs(error) < 1e-7) return curve(y1, y2, u)
            val d = slope(x1, x2, u)
            if (abs(d) < 1e-6) return@repeat
            u -= error / d
        }
        var low = 0.0
        var high = 1.0
        u = x
        repeat(40) {
            val found = curve(x1, x2, u)
            if (abs(found - x) < 1e-7) return curve(y1, y2, u)
            if (found < x) low = u else high = u
            u = (low + high) / 2
        }
        return curve(y1, y2, u)
    }
}

val EaseOut = CubicBezier(0.0, 0.0, 0.58, 1.0)
private val SwellUp = CubicBezier(0.2, 0.4, 0.58, 1.0)
private val SwellDown = CubicBezier(0.3, 0.0, 0.58, 1.0)

// Up to 1 at the middle and back down to 0: how a held letter swells.
fun upAndBack(t: Double): Double = when {
    t <= 0 || t >= 1 -> 0.0
    t < 0.5 -> SwellUp.at(t / 0.5)
    else -> 1 - SwellDown.at((t - 0.5) / 0.5)
}

fun easeOutExpo(x: Double): Double = if (x >= 1) 1.0 else 1 - 2.0.pow(-10 * x)

private const val BACK_C2 = 2.5949095

fun easeInOutBack(x: Double): Double = if (x < 0.5) {
    (2 * x).pow(2) * ((BACK_C2 + 1) * 2 * x - BACK_C2) / 2
} else {
    ((2 * x - 2).pow(2) * ((BACK_C2 + 1) * (x * 2 - 2) + BACK_C2) + 2) / 2
}

// ---- Word lift ----

const val LIFT_EM = 0.05
const val BACKGROUND_LIFT_EM = 0.10

// How far sung words rise when fast singing blooms too.
const val FAST_LIFT_EM = 0.08
const val FAST_BACKGROUND_LIFT_EM = 0.16

// How far a word rises by the end, `fast` when fast singing blooms too.
fun liftOf(background: Boolean, fast: Boolean): Double = when {
    fast -> if (background) FAST_BACKGROUND_LIFT_EM else FAST_LIFT_EM
    else -> if (background) BACKGROUND_LIFT_EM else LIFT_EM
}

// How far a sung word has risen, in em (up is negative): it eases up over
// at least a second from its start and stays up.
fun liftEm(t: Double, start: Double, end: Double, background: Boolean, lift: Double, fast: Boolean = false): Double {
    val over = max(1.0, end - start)
    val done = ((t - start) / over).coerceIn(0.0, 1.0)
    return -liftOf(background, fast) * lift * EaseOut.at(done)
}

// ---- Long-word emphasis ----

// Words held at least this long bloom letter by letter.
const val EMPHASIS_MIN_S = 1.0

// When fast singing blooms too, a word also blooms when it is held at least
// this long and at least this many times as long as its line's middle word,
// and blooms as strongly as a word held FAST_EMPHASIS_STRENGTH_S.
const val FAST_EMPHASIS_MIN_S = 0.6
const val FAST_EMPHASIS_RATIO = 2.5
const val FAST_EMPHASIS_STRENGTH_S = 1.6

// Which of a line's words bloom: those held EMPHASIS_MIN_S or more, and,
// with `fast`, those held long for their line.
fun heldWords(words: List<SyncWord>, fast: Boolean): BooleanArray {
    val durations = words.map { it.end - it.start }
    val sorted = durations.filter { it > 0 }.sorted()
    val middle = if (sorted.isEmpty()) 0.0 else sorted[sorted.size / 2]
    return BooleanArray(durations.size) { i ->
        val d = durations[i]
        d >= EMPHASIS_MIN_S || (fast && d >= FAST_EMPHASIS_MIN_S && d >= FAST_EMPHASIS_RATIO * middle)
    }
}

// How strongly a held word blooms, and over how long.
data class Emphasis(
    // Scale, spread and rise strength, with the Emphasis setting in it.
    val amount: Double,
    // Glow strength, with the Glow setting in it.
    val glow: Double,
    // How far the glow spreads, in em.
    val glowRadiusEm: Double,
    // How long each letter's swell runs.
    val run: Double,
    // How much later each letter starts than the one before.
    val stagger: Double,
)

// The bloom for a word held `duration` seconds with `glyphs` letters (not
// counting spaces), or null when it does not bloom (`held`, by default held
// EMPHASIS_MIN_S or more). The line's last word blooms harder and longer.
// With `fast`, a word held long for its line blooms as strongly as one
// held FAST_EMPHASIS_STRENGTH_S, and words held 1 to 3 s glow more.
fun emphasisFor(
    duration: Double,
    glyphs: Int,
    last: Boolean,
    emphasis: Double,
    glow: Double,
    fast: Boolean = false,
    held: Boolean = duration >= EMPHASIS_MIN_S,
): Emphasis? {
    if (!held || glyphs <= 0) return null
    val d = (if (fast) max(duration, FAST_EMPHASIS_STRENGTH_S) else duration) * 1000
    var a = d / 2000
    a = (if (a > 1) sqrt(a) else a * a * a) * 0.6
    var g = d / 3000
    g = (if (g > 1) sqrt(g) else if (fast) g * sqrt(g) else g * g * g) * 0.5
    var run = duration
    if (last) {
        a *= 1.6
        g *= 1.5
        run *= 1.2
    }
    val amount = min(1.2, a) * emphasis
    val shine = min(0.8, g) * glow
    return Emphasis(amount, shine, min(0.3, shine * 0.3), run, run / 2.5 / glyphs)
}

// When letter `i` starts to swell.
fun glyphStart(wordStart: Double, emphasis: Emphasis, i: Int): Double = wordStart + emphasis.stagger * i

// One letter's pose: its scale, how far it moves across and up (em), and
// its glow's strength.
data class GlyphPose(val scale: Double, val dxEm: Double, val dyEm: Double, val glowAlpha: Double)

val RestingGlyph = GlyphPose(1.0, 0.0, 0.0, 0.0)

fun glyphPose(t: Double, wordStart: Double, emphasis: Emphasis, i: Int, glyphs: Int): GlyphPose {
    val start = glyphStart(wordStart, emphasis, i)
    val e = upAndBack((t - start) / emphasis.run)
    if (e == 0.0) return RestingGlyph
    return GlyphPose(
        scale = 1 + 0.1 * emphasis.amount * e,
        dxEm = -0.03 * emphasis.amount * (glyphs / 2.0 - i) * e,
        dyEm = -0.025 * emphasis.amount * e,
        glowAlpha = e * emphasis.glow,
    )
}

// A small bob on top: it starts 400 ms before the letter and runs 1.4 times
// as long. Backing vocals bob twice as far. In em, up is negative.
fun bobEm(t: Double, wordStart: Double, emphasis: Emphasis, i: Int, lift: Double, background: Boolean): Double {
    val start = glyphStart(wordStart, emphasis, i) - 0.4
    val length = 1.4 * emphasis.run
    val x = (t - start) / length
    if (x <= 0 || x >= 1) return 0.0
    return -0.05 * sin(PI * x) * lift * (if (background) 2 else 1)
}

// ---- Interlude dots ----

// The three dots at `p` seconds into a gap of `f` seconds: their shared
// scale and opacity, and each one's light. `grown` skips the grow-in, for
// a seek into the gap.
data class DotsPose(val scale: Double, val opacity: Double, val lights: DoubleArray)

fun dotsPose(p: Double, f: Double, grown: Boolean): DotsPose {
    val period = f / ceil(f / 1.5)
    val breathe = sin(1.5 * PI - 2 * p / period) / 20 + 1
    var scale = breathe
    var opacity = 1.0
    if (!grown && p < 1) {
        scale = breathe * easeOutExpo(p / 2)
        opacity = if (p < 0.5) 0.0 else (p - 0.5) / 0.5
    }
    val r = f - p
    if (r < 0.75) scale *= 1 - easeInOutBack((0.75 - r) / 0.75 / 2)
    if (r < 0.375) opacity = r / 0.375
    val u = max(0.001, f - 0.75)
    val lights = DoubleArray(3) { k -> ((p - k * u / 3) * 3 / u * 0.75).coerceIn(0.25, 1.0) }
    return DotsPose(scale * 0.7, opacity.coerceIn(0.0, 1.0), lights)
}

// Held still, for reduced motion.
val StillDots = DotsPose(0.7, 1.0, doubleArrayOf(0.85, 0.85, 0.85))

// How much of its full height an interlude takes: it opens over 0.8 s and
// closes over the last 0.6 s.
fun interludeOpen(p: Double, f: Double, grown: Boolean): Double {
    if (p < 0 || p >= f) return 0.0
    val opening = if (grown) 1.0 else easeOutExpo(p / 0.8)
    val closing = easeOutExpo((f - p) / 0.6)
    return min(opening, closing)
}

// ---- Curved lyrics ----

const val ARC_DEPTH = 60.0
const val ARC_LIFT = 40.0
const val ARC_YAW = 0.09
const val ARC_PERSPECTIVE = 1400.0

// A line bent around the drum: how far it moves inward, how far it comes
// forward, its turn (radians) and the scale that stands in for coming
// forward. `side` is 1 for lines set on the left and -1 for the right.
data class ArcPose(val translationX: Double, val z: Double, val rotationY: Double, val scale: Double)

fun arcPose(
    centre: Double,
    viewHeight: Double,
    side: Int,
    depth: Double = ARC_DEPTH,
    lift: Double = ARC_LIFT,
    yaw: Double = ARC_YAW,
    perspective: Double = ARC_PERSPECTIVE,
): ArcPose {
    val radius = 0.55 * viewHeight
    val r = if (radius > 0) ((centre - FOCUS_AT * viewHeight) / radius).coerceIn(-1.0, 1.0) else 0.0
    val a = 1 - r * r
    val z = lift * a
    return ArcPose(
        translationX = side * depth * (1 - a),
        z = z,
        rotationY = side * yaw * r * a,
        scale = perspective / (perspective - z),
    )
}
