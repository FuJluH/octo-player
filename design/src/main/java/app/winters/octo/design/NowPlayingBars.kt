package app.winters.octo.design

import androidx.compose.foundation.Canvas
import androidx.compose.foundation.layout.Box
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.State
import androidx.compose.runtime.mutableFloatStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.withFrameNanos
import kotlinx.coroutines.delay
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.BlurredEdgeTreatment
import androidx.compose.ui.draw.alpha
import androidx.compose.ui.draw.blur
import androidx.compose.ui.geometry.CornerRadius
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.geometry.Size
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.drawscope.DrawScope
import androidx.compose.ui.unit.dp
import kotlin.math.PI
import kotlin.math.abs
import kotlin.math.sin

// Shared by the phone and the desktop, so the song playing is marked the
// same way in both.

// How tall each of the three bars stands while paused, and how each moves
// while playing: its own whole number of beats a loop, so the loop joins
// up, and its own starting point.
private val RestHeights = floatArrayOf(0.45f, 0.8f, 0.6f)
private val Speeds = floatArrayOf(2f, 3f, 4f)
private val Offsets = floatArrayOf(0f, 0.3f, 0.65f)

// Three small bars that mark the song playing now: moving and softly lit
// while it plays, still and quiet while it is paused.
@Composable
fun NowPlayingBars(playing: Boolean, modifier: Modifier = Modifier) {
    // With motion reduced a playing song's bars rest, still lit.
    if (playing && motionScale().still) {
        Canvas(modifier) { bars(OctoColors.TextPrimary, null) }
        return
    }
    if (playing) {
        val phase = rememberLoopPhase(LOOP_MS)
        Box(modifier) {
            // The glow: the same bars, blurred, behind the sharp ones.
            Canvas(Modifier.matchParentSize().blur(4.dp, BlurredEdgeTreatment.Unbounded).alpha(0.7f)) {
                bars(OctoColors.TextPrimary, phase)
            }
            Canvas(Modifier.matchParentSize()) { bars(OctoColors.TextPrimary, phase) }
        }
    } else {
        Canvas(modifier) { bars(OctoColors.TextMuted, null) }
    }
}

// How long the bars take to come round to where they started.
private const val LOOP_MS = 2_400

// How many times a second the bars move: three small bars look the same at
// this rate as on every frame of the screen, and the screen is redrawn far
// less often.
private const val BARS_FPS = 30

// Where the bars are in their loop, from 0 to 1, moving on BARS_FPS times
// a second.
@Composable
private fun rememberLoopPhase(loopMs: Int): State<Float> {
    val phase = remember { mutableFloatStateOf(0f) }
    LaunchedEffect(loopMs) {
        val start = withFrameNanos { it }
        while (true) {
            delay(1_000L / BARS_FPS)
            withFrameNanos { now -> phase.floatValue = ((now - start) / 1_000_000L % loopMs).toFloat() / loopMs }
        }
    }
    return phase
}

// Reads the phase while drawing, so only the drawing repeats as it moves.
private fun DrawScope.bars(color: Color, phase: State<Float>?) {
    val gap = size.width / 7f
    val width = (size.width - gap * 2) / 3
    for (i in 0 until 3) {
        val height = if (phase == null) {
            RestHeights[i]
        } else {
            0.25f + 0.75f * abs(sin((phase.value * Speeds[i] + Offsets[i]) * PI.toFloat()))
        }
        val h = size.height * height
        drawRoundRect(
            color,
            topLeft = Offset(i * (width + gap), size.height - h),
            size = Size(width, h),
            cornerRadius = CornerRadius(width / 2, width / 2),
        )
    }
}
