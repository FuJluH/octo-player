package app.winters.octo.player

import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.MutableLongState
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableLongStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberUpdatedState
import androidx.compose.runtime.withFrameMillis
import app.winters.octo.playback.NowPlaying
import app.winters.octo.ui.common.delayToNextTick
import kotlinx.coroutines.delay
import kotlinx.coroutines.awaitCancellation

// How far into the song playback is. While music plays it is read on a
// frame, so progress glides instead of stepping, even on a short song.
// Reading it is cheap: the player works the position out locally. It is
// writable so a seek shows at once. Read it while drawing, not composing,
// so a moving line only redraws.
//
// `lengthPx` is how long the drawn line is, in pixels. A line that long
// only needs a new frame each time it moves half a pixel, so the position
// is read that often instead of on every frame; 0 reads it on every frame,
// for what moves faster than any line (the words being sung).
//
// `everyMs`, when set, reads it once each whole `everyMs` of the clock
// instead (`delayToNextTick`), for a small line that moves a pixel or two
// a second and so shares its frames with the other slow things on screen.
//
// While a `LocalFrameTicker` has frames coming (the player's moving
// background), the line steps on those frames, as often as it needs, so it
// adds no frames of its own.
@Composable
fun rememberPositionMs(now: NowPlaying, positionMs: () -> Long, lengthPx: Float = 0f, everyMs: Long = 0): MutableLongState {
    val position = remember { mutableLongStateOf(positionMs()) }
    val length by rememberUpdatedState(lengthPx)
    val ticker = LocalFrameTicker.current
    val shared = ticker != null && ticker.running && everyMs == 0L
    LaunchedEffect(now.trackId, now.isPlaying, now.durationMs, everyMs, shared) {
        position.longValue = positionMs()
        if (shared && now.isPlaying && ticker != null) {
            var last = 0L
            val stop = ticker.listen { nanos ->
                val stepNanos = progressStepMs(now.durationMs, length) * 1_000_000
                // A twentieth short, so a frame landing a hair early still counts.
                if (nanos - last >= stepNanos - stepNanos / 20) {
                    last = nanos
                    position.longValue = positionMs()
                }
            }
            try {
                awaitCancellation()
            } finally {
                stop()
            }
        }
        while (now.isPlaying) {
            if (everyMs > 0) {
                delayToNextTick(everyMs)
                withFrameMillis { position.longValue = positionMs() }
                continue
            }
            withFrameMillis { position.longValue = positionMs() }
            val step = progressStepMs(now.durationMs, length)
            if (step > 0) delay(step)
        }
    }
    return position
}

// The time a `durationMs` song takes to move a `lengthPx` line on by half a
// pixel, at most a second, or 0 when that is about a frame or less (or the
// line or song has no length), meaning every frame.
fun progressStepMs(durationMs: Long, lengthPx: Float): Long {
    if (durationMs <= 0 || lengthPx <= 0f) return 0
    val step = (durationMs / (lengthPx * 2f)).toLong()
    return if (step < EVERY_FRAME_BELOW_MS) 0 else step.coerceAtMost(MAX_STEP_MS)
}

private const val EVERY_FRAME_BELOW_MS = 16L
private const val MAX_STEP_MS = 1_000L

fun NowPlaying.fractionAt(positionMs: Long): Float =
    if (durationMs > 0) (positionMs.toFloat() / durationMs).coerceIn(0f, 1f) else 0f
