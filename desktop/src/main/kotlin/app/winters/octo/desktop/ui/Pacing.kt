package app.winters.octo.desktop.ui

import androidx.compose.animation.core.FastOutSlowInEasing
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.State
import androidx.compose.runtime.mutableFloatStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.withFrameNanos
import kotlinx.coroutines.delay

// How often the window is asked to draw for things that move slowly. Every
// frame asked for redraws the whole window, its glass and its moving
// colours, so a small slow thing is moved only as often as it shows.

// How long a progress line `lengthPx` long takes to move half a pixel
// through a song `durationMs` long: the most it can wait between steps and
// still look as if it glides. 0 when that is under a frame (every frame),
// and never more than a second.
fun progressStepMs(durationMs: Long, lengthPx: Float): Long {
    if (durationMs <= 0 || lengthPx <= 0f) return MAX_STEP_MS
    val step = (durationMs / (lengthPx * 2f)).toLong()
    return if (step < EVERY_FRAME_BELOW_MS) 0 else step.coerceAtMost(MAX_STEP_MS)
}

// How long until the clock `positionMs` shows next turns over a whole
// second, and a hair more so the clock is past it when read again, so a
// time in seconds changes on the second.
fun msToNextSecond(positionMs: Long): Long = 1_000L - (positionMs.coerceAtLeast(0) % 1_000L) + TURN_MARGIN_MS

private const val TURN_MARGIN_MS = 5L
private const val EVERY_FRAME_BELOW_MS = 16L
private const val MAX_STEP_MS = 1_000L

// A value easing from 1 down to `low` and back, over and over, `halfMs`
// each way: the curve of an infinite reversing tween, worked out `fps`
// times a second instead of on every frame of the screen. A small soft
// pulse looks the same either way. Not running, it rests at 1. Read it
// while drawing, so a new value only redraws.
@Composable
fun rememberSteppedPulse(low: Float, halfMs: Int, running: Boolean, fps: Int = PULSE_FPS): State<Float> {
    val value = remember { mutableFloatStateOf(1f) }
    LaunchedEffect(running, low, halfMs, fps) {
        value.floatValue = 1f
        if (!running) return@LaunchedEffect
        val start = withFrameNanos { it }
        val stepMs = 1_000L / fps.coerceAtLeast(1)
        while (true) {
            delay(stepMs)
            withFrameNanos { now -> value.floatValue = pulseAt((now - start) / 1_000_000, low, halfMs) }
        }
    }
    return value
}

// The pulse `elapsedMs` after it started: 1 at the start, `low` after
// `halfMs`, 1 again after twice that, eased as a tween is by default.
fun pulseAt(elapsedMs: Long, low: Float, halfMs: Int): Float {
    if (halfMs <= 0) return 1f
    val period = halfMs * 2L
    val t = ((elapsedMs % period) + period) % period
    val way = if (t <= halfMs) t.toFloat() / halfMs else (period - t).toFloat() / halfMs
    val eased = FastOutSlowInEasing.transform(way.coerceIn(0f, 1f))
    return 1f + (low - 1f) * eased
}

const val PULSE_FPS = 30
