package app.winters.octo.player

// One mode a display offers: its id, its size in physical pixels (the same
// whichever way the phone is turned) and its refresh rate in Hz.
data class ScreenMode(val id: Int, val width: Int, val height: Int, val refreshRate: Float)

// Rates closer than this are the same rate (59.94 and 60, say).
private const val SameRateHz = 0.5f

// What the full player asks of the display, in Hz: 0 for nothing (the
// phone decides), infinity for the fastest it has.
//
// Nothing with battery saver or Reduce motion on. The fastest while music
// plays, as the lyrics, the progress line and the background all move.
// Paused, only a moving background is left, so the background's own frame
// limit is enough; with a still background, nothing.
fun playerRefreshNeed(playing: Boolean, calm: Boolean, powerSave: Boolean, movingBackgroundFps: Int?): Float = when {
    powerSave || calm -> 0f
    playing -> Float.POSITIVE_INFINITY
    movingBackgroundFps != null -> movingBackgroundFps.toFloat()
    else -> 0f
}

// The display mode to ask for, or null to leave the choice to the phone.
//
// Only modes at the current size count, so the picture never changes
// size. Where the display names the rates it can switch to without a
// blank frame (`seamlessRates`, empty when it does not say), only those
// count. Of those, the slowest that reaches `needHz`, or the fastest when
// none does. Asking for the slowest rate there is would change nothing, so
// that is null, as is a display with a single rate. Equal rates prefer the
// current mode, then the first listed.
fun pickScreenMode(modes: List<ScreenMode>, current: ScreenMode, seamlessRates: List<Float>, needHz: Float): Int? {
    if (needHz <= 0f) return null
    val sameSize = modes.filter { it.width == current.width && it.height == current.height }
    val candidates = if (seamlessRates.isEmpty()) {
        sameSize
    } else {
        sameSize.filter { mode -> sameRate(mode.refreshRate, current.refreshRate) || seamlessRates.any { sameRate(it, mode.refreshRate) } }
    }.ifEmpty { return null }
    val slowest = candidates.minOf { it.refreshRate }
    val fastest = candidates.maxOf { it.refreshRate }
    if (sameRate(slowest, fastest)) return null
    val enough = candidates.filter { it.refreshRate >= needHz - SameRateHz }
    val rate = if (enough.isEmpty()) fastest else enough.minOf { it.refreshRate }
    if (sameRate(rate, slowest)) return null
    val atRate = candidates.filter { sameRate(it.refreshRate, rate) }
    return (atRate.firstOrNull { it.id == current.id } ?: atRate.first()).id
}

private fun sameRate(a: Float, b: Float): Boolean = kotlin.math.abs(a - b) < SameRateHz
