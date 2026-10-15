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
import kotlinx.coroutines.delay

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
@Composable
fun rememberPositionMs(now: NowPlaying, positionMs: () -> Long, lengthPx: Float = 0f): MutableLongState {
    val position = remember { mutableLongStateOf(positionMs()) }
    val length by rememberUpdatedState(lengthPx)
    LaunchedEffect(now.trackId, now.isPlaying, now.durationMs) {
        position.longValue = positionMs()
        while (now.isPlaying) {
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
