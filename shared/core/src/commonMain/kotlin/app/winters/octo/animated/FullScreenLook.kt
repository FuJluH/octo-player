package app.winters.octo.animated

// How Full screen draws a tall loop, the same in every app: the loop at
// FULL_SCREEN_ZOOM times the screen's width at its own shape, centered,
// its top FULL_SCREEN_LOOP_TOP of the screen's height from the top edge
// (above it when negative), melting into the player's Live background over
// its lower part. Positions are shares of the screen's height from the top.
const val FULL_SCREEN_ZOOM = 1.10f
const val FULL_SCREEN_LOOP_TOP = -0.005f

// The loop shows fully down to FULL_SCREEN_MELT_FROM and is gone by
// FULL_SCREEN_MELT_TO, or by its own bottom edge when that comes first,
// along a smoothstep.
const val FULL_SCREEN_MELT_FROM = 0.505f
const val FULL_SCREEN_MELT_TO = 0.68f

// No feather at the sides and no darkening over the loop.
const val FULL_SCREEN_SIDE_FEATHER = 0f
const val FULL_SCREEN_DARKENING = 0f

// How much brighter the Live background is drawn under a tall loop than
// on its own (0.80 against the default 0.62), as far as the words over it
// still keep their contrast.
const val FULL_SCREEN_BACKGROUND_GAIN = 0.80f / 0.62f

// Where the loop's own bottom edge is, as a share of the screen's height,
// for a loop of `shape` (width over height) on a screen `widthShare` as
// wide as it is tall.
fun fullScreenLoopBottom(shape: Float, widthShare: Float): Float =
    FULL_SCREEN_LOOP_TOP + FULL_SCREEN_ZOOM * widthShare / shape

// Where the melt ends: FULL_SCREEN_MELT_TO, or the loop's bottom edge when
// that comes first, so the melt is always done before the loop ends.
fun fullScreenMeltEnd(shape: Float, widthShare: Float): Float =
    minOf(FULL_SCREEN_MELT_TO, fullScreenLoopBottom(shape, widthShare)).coerceAtLeast(FULL_SCREEN_MELT_FROM + 0.01f)

// How much of the loop shows at `at`: 1 above the melt, 0 below it, a
// smoothstep between.
fun fullScreenLoopAlpha(at: Float, meltEnd: Float): Float {
    if (at <= FULL_SCREEN_MELT_FROM) return 1f
    if (at >= meltEnd) return 0f
    val t = (at - FULL_SCREEN_MELT_FROM) / (meltEnd - FULL_SCREEN_MELT_FROM)
    return 1f - t * t * (3 - 2 * t)
}
