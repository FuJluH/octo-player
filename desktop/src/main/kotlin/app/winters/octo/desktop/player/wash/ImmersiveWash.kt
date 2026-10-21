package app.winters.octo.desktop.player.wash

import app.winters.octo.design.motionScale
import androidx.compose.animation.core.Animatable
import androidx.compose.animation.core.tween
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.runtime.Composable
import androidx.compose.runtime.DisposableEffect
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberUpdatedState
import androidx.compose.runtime.setValue
import androidx.compose.runtime.withFrameNanos
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.drawBehind
import androidx.compose.ui.graphics.drawscope.drawIntoCanvas
import androidx.compose.ui.graphics.skiaCanvas
import androidx.compose.ui.platform.LocalWindowInfo
import app.winters.octo.player.immersive.CoverSwap
import app.winters.octo.player.immersive.RestMarginNanos
import app.winters.octo.player.immersive.WashClock
import app.winters.octo.player.immersive.WashVisibility
import app.winters.octo.player.immersive.dollyScale
import app.winters.octo.player.immersive.targetFps
import app.winters.octo.desktop.ui.LateClose
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.runInterruptible
import org.jetbrains.skia.Image
import org.jetbrains.skia.Paint
import org.jetbrains.skia.Rect
import org.jetbrains.skia.Surface
import kotlin.math.roundToInt

// How long the wash takes to fade in once its first frame is drawn, and
// how long it waits for that frame before fading in regardless.
private const val FadeInMs = 500
private const val FirstFrameWaitNanos = 1_500_000_000L

// Whether a frame has been drawn yet.
private class FirstFrame {
    var drawn = false
}

// The full player's moving background: the cover torn into eight drifting
// copies, warped and blurred into a slow wash of its colours, as on the
// phone, on the same clock (WashClock in the shared core). `moving` off
// holds it still while covers still fade into each other. `speed` is the
// share of the full pace, `bpm` the song's tempo (or the base), `fpsLimit`
// the frame rate it is held to; behind another window it drops to 10
// frames a second. `dolly` (the way in) and `opacity` (how much of it
// shows) are read while drawing.
@Composable
fun ImmersiveWash(
    cover: WashCover?,
    bpm: Float,
    fpsLimit: Int,
    speed: Float,
    moving: Boolean,
    dolly: () -> Float,
    modifier: Modifier = Modifier,
    opacity: () -> Float = { 1f },
) {
    val renderer = remember { WashRenderer() }
    val covers = remember { CoverSwap<Image>() }
    val first = remember { FirstFrame() }
    // One more for every frame drawn; only the drawing reads it.
    val frames = remember { mutableIntStateOf(0) }
    val shown = remember { Animatable(0f) }
    val fadeIn = motionScale().ms(FadeInMs.toInt())
    var arrivals by remember { mutableIntStateOf(0) }

    val focused = LocalWindowInfo.current.isWindowFocused
    val target by rememberUpdatedState(targetFps(if (focused) WashVisibility.Focused else WashVisibility.Unfocused, fpsLimit, powerSave = false))
    val tempo by rememberUpdatedState(bpm)
    val pace by rememberUpdatedState(speed)
    val clock = remember { WashClock(target) }

    // The squares in the fade are this wash's own holds on the covers' (or
    // blends it made), so the covers can close theirs once let go; each
    // one the fade leaves is closed after the frame that last drew it.
    DisposableEffect(Unit) {
        onDispose {
            LateClose.close(covers.old)
            if (covers.new !== covers.old) LateClose.close(covers.new)
            LateClose.close(renderer)
        }
    }
    LaunchedEffect(cover) {
        val next = cover?.hold() ?: return@LaunchedEffect
        val before = listOfNotNull(covers.old, covers.new)
        val (from, to) = covers.arrive(next, clock.fade, System.nanoTime() / 1_000_000, ::mixCovers)
        renderer.setCovers(from, to)
        before.filter { it !== from && it !== to }.distinct().forEach(LateClose::close)
        arrivals++
    }

    // Fades in on the first frame drawn, or after 1.5 s if that is slow.
    LaunchedEffect(Unit) {
        val start = withFrameNanos { it }
        var now = start
        while (!first.drawn && now - start < FirstFrameWaitNanos) now = withFrameNanos { it }
        shown.animateTo(1f, tween(fadeIn))
    }

    // The one clock, while there is something to move: the motion, or a
    // cover fading in. Between frames it rests rather than asking for each
    // of the screen's, since every frame asked for redraws the window.
    LaunchedEffect(moving, arrivals) {
        clock.start(withFrameNanos { it })
        frames.intValue++
        while (clock.busy(moving)) {
            val now = withFrameNanos { now ->
                if (clock.tick(now, target, tempo, pace, moving)) frames.intValue++
                now
            }
            // The rest here keeps to the millisecond, so it runs right up to
            // when the next frame is due rather than waking early for a
            // late timer: a frame asked for before then is a whole window
            // drawn again for nothing.
            restFor(clock.restNanos(now) + RestMarginNanos - WakeEarlyNanos)
        }
    }

    Spacer(
        modifier
            .fillMaxSize()
            .drawBehind {
                frames.intValue
                val zoom = dollyScale(dolly())
                val alpha = shown.value * opacity()
                drawIntoCanvas { canvas ->
                    if (renderer.draw(canvas.skiaCanvas, size.width, size.height, clock.motion, clock.fade.mix, zoom, alpha)) first.drawn = true
                }
            },
    )
}

// Two covers mixed as the wash mixes them, `mix` of the new over the old,
// for a fade that starts while another is under way.
internal fun mixCovers(old: Image, new: Image, mix: Float): Image {
    val surface = Surface.makeRasterN32Premul(old.width, old.height)
    val paint = Paint().apply { alpha = (mix.coerceIn(0f, 1f) * 255).roundToInt() }
    try {
        val all = Rect.makeWH(old.width.toFloat(), old.height.toFloat())
        surface.canvas.drawImage(old, 0f, 0f)
        surface.canvas.drawImageRect(new, all, paint)
        return surface.makeImageSnapshot()
    } finally {
        paint.close()
        surface.close()
    }
}

// Rests this long, closely. Longer waits here wake on the system's coarse
// timer, up to 15 ms late, which would miss the frame they wait for; short
// sleeps keep to the millisecond. Off the window's thread.
private suspend fun restFor(nanos: Long) {
    if (nanos <= 0L) return
    runInterruptible(Dispatchers.IO) {
        val end = System.nanoTime() + nanos
        while (true) {
            val left = (end - System.nanoTime()) / 1_000_000
            if (left <= 0L) break
            Thread.sleep(minOf(left, ShortSleepMs))
        }
    }
}

// How much before a frame is due the rest ends, for the frame to be asked for.
private const val WakeEarlyNanos = 1_000_000L

// The longest sleep the system keeps to the millisecond.
private const val ShortSleepMs = 9L
