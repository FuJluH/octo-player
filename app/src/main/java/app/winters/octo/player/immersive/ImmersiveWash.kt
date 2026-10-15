package app.winters.octo.player.immersive

import android.graphics.Bitmap
import android.graphics.Canvas
import android.graphics.Paint
import android.graphics.Rect
import android.os.Build
import android.os.SystemClock
import androidx.annotation.RequiresApi
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
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue
import androidx.compose.runtime.withFrameNanos
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.drawBehind
import androidx.compose.ui.graphics.drawscope.drawIntoCanvas
import androidx.compose.ui.graphics.nativeCanvas
import androidx.compose.ui.layout.onSizeChanged
import androidx.compose.ui.layout.onGloballyPositioned
import androidx.compose.ui.platform.LocalWindowInfo
import androidx.compose.ui.unit.IntSize
import androidx.lifecycle.Lifecycle
import androidx.lifecycle.compose.LocalLifecycleOwner
import androidx.lifecycle.repeatOnLifecycle
import app.winters.octo.player.rememberPowerSave
import app.winters.octo.player.LocalFrameTicker
import app.winters.octo.ui.common.GpuPictureStream
import kotlinx.coroutines.delay
import kotlin.math.ceil
import kotlin.math.min

// How long the wash takes to fade in once its first frame is drawn, and
// how long it waits for that frame before fading in regardless.
private const val FadeInMs = 500
private const val FirstFrameWaitNanos = 1_500_000_000L

// The moving wash, on phones that can draw it; the still artwork on
// others. `moving` off freezes the motion (a still wash) while covers
// still fade into each other.
@Composable
fun ImmersiveWash(cover: WashCover?, bpm: Float, speed: Float, moving: Boolean, dolly: () -> Float, glass: WashGlass? = null) {
    if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) {
        WashCanvas(cover, bpm, speed, moving, dolly, glass)
    } else {
        StillArtwork(cover, dolly)
    }
}

// Whether a frame has been drawn yet.
private class FirstFrame {
    var drawn = false
}

// Whether the clock is running, and whether a picture has arrived that its
// next frame should show.
private class PictureHandoff {
    var ticking = false
    var waiting = false
}

@RequiresApi(Build.VERSION_CODES.TIRAMISU)
@Composable
private fun WashCanvas(cover: WashCover?, bpm: Float, speed: Float, moving: Boolean, dolly: () -> Float, glass: WashGlass?) {
    val renderer = remember { WashRenderer() }
    DisposableEffect(renderer) { onDispose { renderer.release() } }
    val covers = remember { CoverSwap<Bitmap>() }
    val first = remember { FirstFrame() }
    // One more for every frame the clock steps, and for every picture that
    // arrives. Only the drawing reads them, so a new frame redraws this
    // layer and nothing is recomposed.
    val frames = remember { mutableIntStateOf(0) }
    val landed = remember { mutableIntStateOf(0) }
    val shown = remember { Animatable(0f) }
    // Changes when a new cover arrives, to wake the clock for its fade.
    var arrivals by remember { mutableIntStateOf(0) }

    // The wash's pictures, made at a quarter of its size, once its size is
    // known. Null where they cannot be made: it then draws on the window.
    var area by remember { mutableStateOf(IntSize.Zero) }
    val pictures = remember(area) { washPictures(area) }
    // While the clock runs, a picture that arrives waits for the clock's
    // next frame, which shows it and asks for the next one, so each step
    // of the wash costs the window one frame, not two.
    val handoff = remember { PictureHandoff() }
    DisposableEffect(pictures) {
        pictures?.onPicture = {
            if (handoff.ticking) {
                handoff.waiting = true
            } else {
                renderer.pictureArrived(pictures)
                landed.intValue++
            }
        }
        glass?.follow(if (pictures != null) renderer else null, landed, { dollyScale(dolly()) }, { shown.value })
        onDispose {
            glass?.pictureShown(false)
            pictures?.close()
        }
    }

    val focused = LocalWindowInfo.current.isWindowFocused
    val powerSave = rememberPowerSave()
    val target by rememberUpdatedState(
        targetFps(if (focused) WashVisibility.Focused else WashVisibility.Unfocused, WashMaxFps, powerSave),
    )
    val tempo by rememberUpdatedState(bpm)
    val pace by rememberUpdatedState(speed)
    val clock = remember { WashClock(target) }
    val zoomNow by rememberUpdatedState(dolly)

    // Asks for a picture of the wash as the clock has it now; false when
    // the last one is still on its way.
    val render: () -> Boolean = {
        val stream = pictures
        if (stream != null) {
            renderer.renderPicture(stream, area.width, area.height, clock.motion, clock.fade.mix, dollyScale(zoomNow()))
        } else {
            frames.intValue++
            true
        }
    }

    LaunchedEffect(cover) {
        val next = cover?.square ?: return@LaunchedEffect
        val (from, to) = covers.arrive(next, clock.fade, SystemClock.uptimeMillis(), ::mixCovers)
        renderer.setCovers(from, to)
        arrivals++
    }

    // Fades in on the first frame drawn, or after 1.5 s if that is slow.
    LaunchedEffect(Unit) {
        val start = withFrameNanos { it }
        var now = start
        while (!first.drawn && now - start < FirstFrameWaitNanos) now = withFrameNanos { it }
        shown.animateTo(1f, tween(FadeInMs))
    }

    val lifecycle = LocalLifecycleOwner.current.lifecycle
    // The wash's frames, offered to the player's slower movers.
    val ticker = LocalFrameTicker.current

    // The one clock. It runs while the player is in view (hidden or with
    // the screen off it stops, as the app is no longer started) and while
    // there is something to move: the motion, or a cover fading in.
    LaunchedEffect(lifecycle, moving, arrivals, pictures) {
        lifecycle.repeatOnLifecycle(Lifecycle.State.STARTED) {
            clock.start(withFrameNanos { it })
            render()
            handoff.ticking = true
            if (moving) ticker?.running = true
            try {
                while (clock.busy(moving)) {
                    // Between drawn frames the clock rests rather than waking on
                    // every frame of a faster screen.
                    val rest = withFrameNanos { now ->
                        if (clock.tick(now, target, tempo, pace, moving)) {
                            if (handoff.waiting && pictures != null) {
                                handoff.waiting = false
                                renderer.pictureArrived(pictures)
                                landed.intValue++
                            }
                            render()
                            ticker?.tick(now)
                        }
                        clock.restNanos(now)
                    }
                    if (rest > 0) delay(rest / 1_000_000)
                }
            } finally {
                ticker?.running = false
                handoff.ticking = false
                if (handoff.waiting && pictures != null) {
                    handoff.waiting = false
                    renderer.pictureArrived(pictures)
                    landed.intValue++
                }
            }
            // The frame the clock stopped on, once the one before is in, so
            // a still wash shows the cover fully faded in.
            var tries = 0
            while (!render() && tries++ < FinalPictureTries) withFrameNanos { }
        }
    }

    Spacer(
        Modifier
            .fillMaxSize()
            .onSizeChanged { area = it }
            .onGloballyPositioned { glass?.placed(it) }
            .drawBehind {
                frames.intValue
                landed.intValue
                val zoom = dollyScale(dolly())
                drawIntoCanvas { canvas ->
                    val drew = if (pictures != null) {
                        renderer.drawPicture(canvas.nativeCanvas, size.width.toInt(), size.height.toInt(), zoom, shown.value)
                    } else {
                        renderer.draw(
                            canvas.nativeCanvas,
                            size.width.toInt(),
                            size.height.toInt(),
                            clock.motion,
                            clock.fade.mix,
                            zoom,
                            shown.value,
                        )
                    }
                    if (drew) first.drawn = true
                    if (pictures != null) glass?.pictureShown(drew)
                }
            },
    )
}

// The frame rate the wash draws at: its slow drift needs no more than 30
// frames a second.
const val WashMaxFps = 30

// Frames the clock waits, at most, to ask for the picture it stopped on.
private const val FinalPictureTries = 30

// The stream of pictures for a wash of `area`, or null when it has no size
// yet or the phone cannot make them.
@RequiresApi(Build.VERSION_CODES.TIRAMISU)
private fun washPictures(area: IntSize): GpuPictureStream? {
    if (area.width <= 0 || area.height <= 0) return null
    val width = ceil(area.width * PictureOverscan / PictureScaleDown).toInt()
    val height = ceil(area.height * PictureOverscan / PictureScaleDown).toInt()
    return runCatching { GpuPictureStream(width, height) }.getOrNull()
}

// Two covers mixed as the wash mixes them, `mix` of the new over the old,
// for a fade that starts while another is under way.
private fun mixCovers(old: Bitmap, new: Bitmap, mix: Float): Bitmap {
    val out = Bitmap.createBitmap(old.width, old.height, Bitmap.Config.ARGB_8888)
    val canvas = Canvas(out)
    canvas.drawBitmap(old, 0f, 0f, null)
    canvas.drawBitmap(new, null, Rect(0, 0, old.width, old.height), Paint(Paint.FILTER_BITMAP_FLAG).apply { alpha = (mix.coerceIn(0f, 1f) * 255).toInt() })
    return out
}
