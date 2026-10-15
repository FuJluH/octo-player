package app.winters.octo.player.immersive

import kotlin.math.roundToInt

// The choices the wash's settings offer, on the phone and the desktop: the
// brightness cap, saturation and drift speed in percent, the contrast as a
// factor, and the frame rates it can be held to.
val BrightnessCapRange = 20..100
val SaturationRange = 0..300
val ContrastRange = 0.5f..2f
val FpsChoices = listOf(30, 60, 90, 120)
val SpeedRange = 5..100

// The darkest and the brightest a background gets, as colours.
data class WashRange(val low: Int, val high: Int) {
    // Both dimmed (or brightened) by `gain`, as the wash's final pass does.
    fun scaled(gain: Float): WashRange = WashRange(scale(low, gain), scale(high, gain))

    companion object {
        // A background of this one colour, or of these few (a flat fill, the
        // classic mesh).
        fun of(vararg colours: Int): WashRange =
            WashRange(colours.minBy { relativeLuminance(it) }, colours.maxBy { relativeLuminance(it) })
    }
}

// The range of a picture as a background drawn blurred from it shows: the
// picture averaged in `cells` x `cells` blocks (16 pixels each over the
// 512 square), and the darkest and brightest block. A patch of colour much
// smaller than a block is blurred away; one as big survives.
fun washRange(pixels: IntArray, width: Int, cells: Int = 32): WashRange {
    val height = pixels.size / width
    val bw = maxOf(1, width / cells)
    val bh = maxOf(1, height / cells)
    var low = 0
    var high = 0
    var lowL = Double.MAX_VALUE
    var highL = -1.0
    for (cy in 0 until height / bh) for (cx in 0 until width / bw) {
        var r = 0L
        var g = 0L
        var b = 0L
        for (y in cy * bh until (cy + 1) * bh) for (x in cx * bw until (cx + 1) * bw) {
            val p = pixels[y * width + x]
            r += p shr 16 and 0xFF
            g += p shr 8 and 0xFF
            b += p and 0xFF
        }
        val n = bw * bh
        val mean = (0xFF shl 24) or ((r / n).toInt() shl 16) or ((g / n).toInt() shl 8) or (b / n).toInt()
        val l = relativeLuminance(mean)
        if (l < lowL) { lowL = l; low = mean }
        if (l > highL) { highL = l; high = mean }
    }
    return WashRange(low, high)
}

private fun scale(argb: Int, gain: Float): Int {
    fun channel(shift: Int) = ((argb shr shift and 0xFF) * gain).roundToInt().coerceIn(0, 255)
    return (0xFF shl 24) or (channel(16) shl 16) or (channel(8) shl 8) or channel(0)
}

// The dark words used over a light background, on the phone and the desktop.
const val DarkInkArgb = 0xFF141416.toInt()
private const val WhiteArgb = 0xFFFFFFFF.toInt()

// The contrast the player's words keep against what is drawn under them,
// the usual minimum for reading.
const val PlayerContrast = 4.5

// What words over a background need: whether they are dark, and how much of
// the background shows over the colour under it (`show`, 1 for all of it)
// so that they read.
data class WashInk(val dark: Boolean, val show: Float)

// The words' colour for a background spanning `range`, drawn over `under`.
// Dark words when they read on its darkest part as it is and white ones
// would need it dimmed; otherwise white words, with the background dimmed
// just enough that they read on its brightest part. A background both light
// and dark in places (a teal cover with a deep red shape) gets white words
// and a little dimming, never dark words over its dark half.
fun inkOver(range: WashRange, under: Int, contrast: Double = PlayerContrast): WashInk {
    val white = readableAlpha(range.high, under, WhiteArgb, contrast, 1f)
    val darkReads = contrastRatio(DarkInkArgb, range.low) >= contrast
    return if (darkReads && white < 1f) WashInk(dark = true, show = 1f) else WashInk(dark = false, show = white)
}

// How strongly icons drawn a step quieter than the words, in `ink`, show
// over the colour `under` them: `soft` where that keeps `contrast`, more
// as far as reading needs over a background close to the words' limit,
// at most fully.
fun quietAlpha(under: Int, ink: Int, soft: Float, contrast: Double = PlayerContrast): Float {
    fun reads(alpha: Float) = contrastRatio(overlay(ink, alpha, under), under) >= contrast
    if (reads(soft)) return soft
    if (!reads(1f)) return 1f
    var low = soft
    var high = 1f
    repeat(20) {
        val mid = (low + high) / 2
        if (reads(mid)) high = mid else low = mid
    }
    return high
}

// The brightest the wash gets over a prepared cover, as a colour: the
// pixel at the 98th percentile of brightness (every `step`th pixel is
// looked at), dimmed as the final pass leaves it. The wash only mixes,
// blurs and stretches the cover's colours, so it is never brighter than
// its brightest pixels; the last 2% are too few to survive the blur.
fun washPeak(pixels: IntArray, step: Int = 7): Int {
    if (pixels.isEmpty()) return 0xFF000000.toInt()
    val picked = IntArray((pixels.size + step - 1) / step) { pixels[it * step] }
    val light = DoubleArray(picked.size) { relativeLuminance(picked[it]) }
    val line = light.sortedArray()[((picked.size - 1) * 0.98f).roundToInt()]
    val bright = picked[light.indexOfFirst { it == line }]
    val gain = FinalGain.coerceAtMost(1f)
    fun channel(shift: Int) = ((bright shr shift and 0xFF) * gain).roundToInt().coerceIn(0, 255)
    return (0xFF shl 24) or (channel(16) shl 16) or (channel(8) shl 8) or channel(0)
}

// One colour laid over another at some opacity, channel by channel, as the
// screen blends them.
fun overlay(top: Int, alpha: Float, under: Int): Int {
    fun channel(shift: Int): Int {
        val t = top shr shift and 0xFF
        val u = under shr shift and 0xFF
        return (u + (t - u) * alpha).roundToInt().coerceIn(0, 255)
    }
    return (0xFF shl 24) or (channel(16) shl 16) or (channel(8) shl 8) or channel(0)
}

// How much of a wash can show over a page's colour (`base`) while words in
// `ink` keep at least `contrast` against the wash's brightest part (`peak`,
// from `washPeak`): the most, up to `most`, that still reads. Words on a
// light wash cannot flip dark on a page the way the player's do, so a
// bright cover shows fainter instead.
fun readableAlpha(peak: Int, base: Int, ink: Int, contrast: Double, most: Float): Float {
    fun reads(alpha: Float) = contrastRatio(ink, overlay(peak, alpha, base)) >= contrast
    if (reads(most)) return most
    if (!reads(0f)) return 0f
    var low = 0f
    var high = most
    repeat(20) {
        val mid = (low + high) / 2f
        if (reads(mid)) low = mid else high = mid
    }
    return low
}
