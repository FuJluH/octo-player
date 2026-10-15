package app.winters.octo.ui.nav

import androidx.compose.foundation.Canvas
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.material3.Icon
import androidx.compose.runtime.Composable
import androidx.compose.runtime.FloatState
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.mutableFloatStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.withFrameNanos
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.StrokeCap
import androidx.compose.ui.graphics.drawscope.Stroke
import androidx.compose.ui.graphics.graphicsLayer
import androidx.compose.ui.res.painterResource
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.dp
import androidx.lifecycle.Lifecycle
import androidx.lifecycle.compose.LocalLifecycleOwner
import androidx.lifecycle.repeatOnLifecycle
import app.winters.octo.design.OctoColors
import app.winters.octo.design.OctoIcons
import app.winters.octo.playback.NowPlaying
import app.winters.octo.ui.common.Artwork
import app.winters.octo.ui.common.LocalReduceMotion
import app.winters.octo.ui.output.CastingMark
import kotlinx.coroutines.delay
import kotlin.math.PI
import kotlin.math.cos

// The face of the round button at the end of the bar: the song's artwork
// with a thin ring round it showing how far through the song it is. While
// paused the ring breathes slowly; playing, it holds steady and advances.
// With nothing loaded it shows the play sign, since the button then
// shuffles the library. The bar supplies the glaze around it.
@Composable
fun NowPlayingFace(now: NowPlaying, progress: () -> Float, size: Dp = BarHeight) {
    Box(Modifier.size(size), contentAlignment = Alignment.Center) {
        if (now.trackId == null) {
            Icon(painterResource(OctoIcons.Play), contentDescription = null, tint = OctoColors.TextPrimary, modifier = Modifier.size(22.dp))
        } else {
            Artwork(now.artwork, size - 12.dp, shape = CircleShape)
            ProgressRing(progress, paused = isPaused(now), modifier = Modifier.matchParentSize().padding(3.dp), whole = now.live != null)
        }
        // Playing on a TV or speaker.
        if (now.casting) CastingMark(Modifier.align(Alignment.BottomEnd).padding(2.dp))
    }
}

// Paused by the listener (or a station stopped). Waiting for sound to come
// still counts as playing, so a slow start never looks paused.
fun isPaused(now: NowPlaying): Boolean = now.trackId != null && !now.playWhenReady

// What the round button says: whether it plays and the song, or what a tap
// does with nothing loaded.
fun nowPlayingWords(now: NowPlaying): String {
    if (now.trackId == null) return "Shuffle your library"
    val song = listOfNotNull(now.title?.takeIf(String::isNotBlank), now.artist?.takeIf(String::isNotBlank)).joinToString(", ")
    return if (song.isEmpty()) "Now playing" else "Now playing: $song"
}

fun nowPlayingState(now: NowPlaying): String = when {
    now.trackId == null -> ""
    !isPaused(now) -> "Playing"
    now.live != null -> "Stopped"
    else -> "Paused"
}

// How far through the song it is, as an arc from the top, or the whole
// circle for a station (`whole`). The value is read while drawing, so the
// arc can move every frame without recomposing. Paused, a faint track
// shows the full circle and the arc breathes in brightness and width; with
// motion reduced it holds still, dimmed, instead. The ring draws in its own
// layer, so a breath redraws only the ring.
@Composable
fun ProgressRing(progress: () -> Float, paused: Boolean, modifier: Modifier, whole: Boolean = false) {
    val still = LocalReduceMotion.current
    val breath = rememberPauseBreath(paused && !still)
    val accent = OctoColors.Accent
    Canvas(modifier.graphicsLayer()) {
        val thin = 2.dp.toPx()
        val sweep = if (whole) 360f else 360f * progress()
        if (!paused) {
            drawArc(accent, -90f, sweep, useCenter = false, style = Stroke(thin, cap = StrokeCap.Round))
            return@Canvas
        }
        drawArc(accent.copy(alpha = PausedTrackAlpha), 0f, 360f, useCenter = false, style = Stroke(thin))
        val calm = still || breath.floatValue == BreathRested
        val b = if (calm) 0f else breath.floatValue
        val alpha = if (calm) PausedStillAlpha else PausedLowAlpha + (1f - PausedLowAlpha) * b
        val width = thin + (PausedWideDp - 2f).dp.toPx() * b
        drawArc(accent.copy(alpha = alpha), -90f, sweep, useCenter = false, style = Stroke(width, cap = StrokeCap.Round))
    }
}

// The paused ring: its faint full track, the arc's dimmest point in a
// breath (and its brightness held still with motion reduced), and its
// widest point in dp.
const val PausedTrackAlpha = 0.18f
const val PausedLowAlpha = 0.35f
const val PausedStillAlpha = 0.45f
const val PausedWideDp = 3f

// One breath in and out, in seconds, and the time between redraws: about
// 12 a second, smooth enough for something this slow. Each one redraws the
// whole window with its frosted glass, so fewer keep a paused phone cool.
const val PauseBreathSeconds = 2.6
const val PauseFrameMs = 83L

// How long the ring breathes after a pause, in seconds, before it settles
// into the still paused look until playing starts or the app comes back.
const val PauseBreathLimitSeconds = 60.0

// The breath's value once it has settled: the ring draws its still look.
const val BreathRested = -1f

// How far into a breath it is at `seconds`, 1 at its fullest and 0 at its
// faintest, easing at both ends.
fun pauseBreath(seconds: Double): Float = (0.5 + 0.5 * cos(2 * PI * seconds / PauseBreathSeconds)).toFloat()

// Whether a breath `seconds` in settles now: past the limit, near its
// faintest, where the still look is close, so settling shows no jump.
fun breathSettles(seconds: Double): Boolean =
    seconds >= PauseBreathLimitSeconds && pauseBreath(seconds) <= SettleBelow

private const val SettleBelow = 0.2f

// The breath, ticking only while `on` and while the app is on screen, for
// a minute before it settles; it stops with the ring when the ring leaves
// the screen, and breathes again when the app comes back.
@Composable
private fun rememberPauseBreath(on: Boolean): FloatState {
    val breath = remember { mutableFloatStateOf(1f) }
    val lifecycle = LocalLifecycleOwner.current.lifecycle
    LaunchedEffect(on, lifecycle) {
        breath.floatValue = 1f
        if (!on) return@LaunchedEffect
        lifecycle.repeatOnLifecycle(Lifecycle.State.STARTED) {
            val start = withFrameNanos { it }
            while (true) {
                delay(PauseFrameMs)
                val seconds = withFrameNanos { now -> (now - start) / 1e9 }
                if (breathSettles(seconds)) {
                    breath.floatValue = BreathRested
                    break
                }
                breath.floatValue = pauseBreath(seconds)
            }
        }
    }
    return breath
}
