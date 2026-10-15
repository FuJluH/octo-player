package app.winters.octo.animated

import app.winters.octo.player.immersive.DarkInkArgb
import app.winters.octo.player.immersive.PlayerContrast
import app.winters.octo.player.immersive.contrastRatio
import app.winters.octo.player.immersive.overlay
import kotlin.math.roundToInt

private const val White = 0xFFFFFFFF.toInt()
private const val Black = 0xFF000000.toInt()

// The least of the color laid over the loop under the controls, so the
// fade reads as a color and not a smudge even where the words would read
// without it.
const val BACKDROP_LEAST_SCRIM = 0.55f

// What the player's words need over a tall loop that fades into a color
// under them: whether they are dark, the color the loop fades into (the
// clip's own, darkened only when neither white nor dark words could read
// on it), and how solid that color is (`scrim`, 1 for fully) where the
// words begin.
data class BackdropInk(val dark: Boolean, val color: Int, val scrim: Float)

// The words' ink over a loop fading into `color`. Dark words when they
// read better on it, else white. The scrim is the least that keeps them
// readable whatever the loop shows through it: a white frame under white
// words, a black one under dark words.
fun backdropInk(color: Int, contrast: Double = PlayerContrast): BackdropInk {
    var fill = color or Black
    // A middle gray reads with neither ink: darkened until white words do.
    var gain = 1f
    while (maxOf(contrastRatio(White, fill), contrastRatio(DarkInkArgb, fill)) < contrast && gain > 0f) {
        gain -= 0.02f
        fill = scaled(color or Black, gain)
    }
    val dark = contrastRatio(DarkInkArgb, fill) > contrastRatio(White, fill)
    val ink = if (dark) DarkInkArgb else White
    val worst = if (dark) Black else White
    fun reads(alpha: Float) = contrastRatio(ink, overlay(fill, alpha, worst)) >= contrast
    if (reads(BACKDROP_LEAST_SCRIM)) return BackdropInk(dark, fill, BACKDROP_LEAST_SCRIM)
    var low = BACKDROP_LEAST_SCRIM
    var high = 1f
    repeat(20) {
        val mid = (low + high) / 2f
        if (reads(mid)) high = mid else low = mid
    }
    return BackdropInk(dark, fill, high)
}

private fun scaled(argb: Int, gain: Float): Int {
    fun channel(shift: Int) = ((argb shr shift and 0xFF) * gain.coerceAtLeast(0f)).roundToInt().coerceIn(0, 255)
    return Black or (channel(16) shl 16) or (channel(8) shl 8) or channel(0)
}
