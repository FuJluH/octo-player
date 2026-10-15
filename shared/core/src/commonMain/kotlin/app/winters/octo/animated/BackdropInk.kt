package app.winters.octo.animated

import app.winters.octo.player.immersive.DarkInkArgb
import app.winters.octo.player.immersive.contrastRatio
import app.winters.octo.player.immersive.overlay
import kotlin.math.roundToInt

private const val White = 0xFFFFFFFF.toInt()
private const val Black = 0xFF000000.toInt()

// Octo's blue gray, which the player's quieter words take over a dark
// background: the artist as it is, the album's name and the times at 80%.
private const val OctoAccentArgb = 0xFF97B1B9.toInt()

// One kind of thing drawn over the fill under a tall loop, and the contrast
// it must keep: the words' own ink at `alpha`, or with white words
// `onWhite` at `alpha` instead (Octo's blue gray for the quieter words).
data class InkNeed(val alpha: Float, val contrast: Double, val onWhite: Int? = null)

// What the player draws over the fill: the song's name (8:1), the artist
// and the small words (4.5:1), and the quiet icons at 45% (3:1).
val PlayerInkNeeds = listOf(
    InkNeed(alpha = 1f, contrast = 8.0),
    InkNeed(alpha = 0.75f, contrast = 4.5, onWhite = OctoAccentArgb),
    InkNeed(alpha = 0.6f, contrast = 4.5, onWhite = OctoAccentArgb),
    InkNeed(alpha = 0.45f, contrast = 3.0),
)

// The words' ink over the still fill a tall loop fades into, and how far
// the fill is dimmed for it (`gain`, 1 for not at all).
data class FillInk(val dark: Boolean, val gain: Float)

// The ink for a fill spanning `low` to `high` (its darkest and brightest
// colors): dark words when every need holds on its darkest part as it is;
// else white words, with the fill dimmed just enough that every need holds
// on its brightest part.
fun fillInk(low: Int, high: Int, needs: List<InkNeed> = PlayerInkNeeds): FillInk {
    fun holds(dark: Boolean, under: Int): Boolean = needs.all { need ->
        val ink = if (dark) DarkInkArgb else need.onWhite ?: White
        val alpha = when {
            dark || need.onWhite == null -> need.alpha
            // Octo's blue gray is solid for the artist, at 80% for the rest.
            need.alpha >= 0.75f -> 1f
            else -> 0.8f
        }
        contrastRatio(overlay(ink, alpha, under), under) >= need.contrast
    }
    if (holds(dark = true, low or Black)) return FillInk(dark = true, gain = 1f)
    var gain = 1f
    while (gain > 0f && !holds(dark = false, dimmed(high or Black, gain))) gain -= 0.01f
    return FillInk(dark = false, gain = gain.coerceAtLeast(0f))
}

// A color dimmed by `gain`, channel by channel.
fun dimmed(argb: Int, gain: Float): Int {
    fun channel(shift: Int) = ((argb shr shift and 0xFF) * gain.coerceIn(0f, 1f)).roundToInt().coerceIn(0, 255)
    return Black or (channel(16) shl 16) or (channel(8) shl 8) or channel(0)
}
