package app.winters.octo.ui.common

import androidx.compose.animation.core.FastOutSlowInEasing
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.State
import androidx.compose.runtime.mutableFloatStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.withFrameNanos
import app.winters.octo.player.LocalFrameTicker
import app.winters.octo.player.immersive.WashMaxFps
import kotlinx.coroutines.awaitCancellation
import kotlinx.coroutines.delay

// A value easing from 1 down to `low` and back, over and over, `halfMs` each
// way: the same curve as an infinite reversing tween, but worked out only
// `fps` times a second instead of on every frame of the screen. A small
// soft pulse looks the same either way, and the screen is redrawn a
// quarter as often on a 120 Hz phone. Not running, it rests at 1. Read it
// while drawing, so a new value only redraws. While the player's moving
// background draws its own frames (`LocalFrameTicker`), as often as this
// would, the pulse steps on those instead of waking frames of its own.
@Composable
fun rememberSteppedPulse(low: Float, halfMs: Int, running: Boolean, fps: Int = PULSE_FPS): State<Float> {
    val value = remember { mutableFloatStateOf(1f) }
    val ticker = LocalFrameTicker.current
    val shared = ticker != null && ticker.running && fps <= WashMaxFps
    LaunchedEffect(running, low, halfMs, fps, shared) {
        value.floatValue = 1f
        if (!running) return@LaunchedEffect
        val start = withFrameNanos { it }
        if (shared && ticker != null) {
            val stop = ticker.listen { now -> value.floatValue = pulseAt((now - start) / 1_000_000, low, halfMs) }
            try {
                awaitCancellation()
            } finally {
                stop()
            }
        }
        val stepMs = 1_000L / fps.coerceAtLeast(1)
        while (true) {
            delay(stepMs)
            withFrameNanos { now -> value.floatValue = pulseAt((now - start) / 1_000_000, low, halfMs) }
        }
    }
    return value
}

// The pulse `elapsedMs` after it started: 1 at the start, `low` after
// `halfMs`, 1 again after twice that, eased the way a tween is by default.
fun pulseAt(elapsedMs: Long, low: Float, halfMs: Int): Float {
    if (halfMs <= 0) return 1f
    val period = halfMs * 2L
    val t = ((elapsedMs % period) + period) % period
    val way = if (t <= halfMs) t.toFloat() / halfMs else (period - t).toFloat() / halfMs
    val eased = FastOutSlowInEasing.transform(way.coerceIn(0f, 1f))
    return 1f + (low - 1f) * eased
}

private const val PULSE_FPS = 30
