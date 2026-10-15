package app.winters.octo.desktop.animated

import androidx.compose.animation.core.Animatable
import androidx.compose.animation.core.tween
import androidx.compose.foundation.Image
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.BoxWithConstraints
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.offset
import androidx.compose.foundation.layout.size
import androidx.compose.runtime.Composable
import androidx.compose.runtime.DisposableEffect
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.produceState
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberUpdatedState
import androidx.compose.runtime.setValue
import androidx.compose.runtime.snapshotFlow
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.draw.drawBehind
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.ImageBitmap
import androidx.compose.ui.graphics.Shape
import androidx.compose.ui.graphics.drawscope.drawIntoCanvas
import androidx.compose.ui.graphics.graphicsLayer
import androidx.compose.ui.graphics.skiaCanvas
import androidx.compose.ui.graphics.toComposeImageBitmap
import androidx.compose.ui.layout.ContentScale
import androidx.compose.ui.layout.onSizeChanged
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.IntSize
import androidx.compose.ui.unit.dp
import app.winters.octo.animated.LOOP_FADE_MS
import app.winters.octo.animated.LoopPlay
import app.winters.octo.animated.loopPlay
import app.winters.octo.audio.LoopVideo
import app.winters.octo.audio.loopVideoAvailable
import app.winters.octo.design.LocalReduceMotion
import app.winters.octo.design.artworkRim
import app.winters.octo.desktop.ui.DarkInk
import app.winters.octo.subsonic.AnimatedClip
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.NonCancellable
import kotlinx.coroutines.flow.collectLatest
import kotlinx.coroutines.flow.first
import kotlinx.coroutines.isActive
import kotlinx.coroutines.withContext
import org.jetbrains.skia.Bitmap
import org.jetbrains.skia.ColorAlphaType
import org.jetbrains.skia.ColorType
import org.jetbrains.skia.ImageInfo
import org.jetbrains.skia.Paint
import org.jetbrains.skia.Rect
import org.jetbrains.skia.SamplingMode
import java.io.File
import java.util.concurrent.atomic.AtomicReference
import org.jetbrains.skia.Image as SkiaImage

// How long a frame is waited for at a time, so a loop going away is
// noticed within that.
private const val WaitMs = 100u

// Whether this computer can decode loops at all, asked once.
private val videoAvailable: Boolean by lazy { runCatching { loopVideoAvailable() }.getOrDefault(false) }

// What a loop on screen does now: the shared rule, with this window's
// motion setting and the computer's power saving.
@Composable
fun rememberLoopPlay(model: AnimatedArtModel, seen: Boolean): LoopPlay {
    val saving by model.powerSaving.on.collectAsState()
    return loopPlay(seen, saving, LocalReduceMotion.current)
}

// The frames of one loop, handed from the thread that reads them to the
// drawing: the newest waits in `mailbox` until it is drawn, and the one
// drawn stays until a newer one comes.
private class FrameBox {
    val mailbox = AtomicReference<SkiaImage?>(null)
    val arrived = mutableIntStateOf(0)

    @Volatile var closed = false
    private var shown: SkiaImage? = null

    // The frame to draw now. On the window's thread only.
    fun take(): SkiaImage? {
        mailbox.getAndSet(null)?.let { next ->
            shown?.close()
            shown = next
        }
        return shown
    }

    fun put(image: SkiaImage) {
        mailbox.getAndSet(image)?.close()
        if (closed) mailbox.getAndSet(null)?.close()
    }

    fun close() {
        closed = true
        mailbox.getAndSet(null)?.close()
        shown?.close()
        shown = null
    }
}

// A loop's frames filling the box, scaled to cover it: nothing at all
// until the first frame is drawn, then that frame fades in over what is
// under it. Frames are read only while it plays, as the loop makes them
// (24 a second), so the window draws again only for a new frame. Held,
// the last frame stays and nothing is decoded; with only the still, no
// decoder is opened.
@Composable
fun LoopFrames(file: File?, play: LoopPlay, modifier: Modifier = Modifier) {
    val box = remember(file) { FrameBox() }
    DisposableEffect(box) { onDispose { box.close() } }
    var size by remember { mutableStateOf(IntSize.Zero) }
    val fade = remember(file) { Animatable(0f) }
    val playing by rememberUpdatedState(play)
    val opened = file != null && play != LoopPlay.StillOnly && size != IntSize.Zero && videoAvailable

    LaunchedEffect(box, opened) {
        val target = file?.takeIf { opened } ?: return@LaunchedEffect
        val wanted = size
        val video = withContext(NonCancellable + Dispatchers.IO) {
            runCatching { LoopVideo.open(target.path, wanted.width.toUInt(), wanted.height.toUInt()) }.getOrNull()
        } ?: return@LaunchedEffect
        try {
            snapshotFlow { playing }.collectLatest { now ->
                if (now == LoopPlay.Play) {
                    video.play()
                    readFrames(video, box)
                } else {
                    video.hold()
                }
            }
        } finally {
            withContext(NonCancellable + Dispatchers.IO) {
                video.stop()
                video.destroy()
            }
        }
    }
    // The fade in, once the first frame is there to draw.
    LaunchedEffect(box) {
        snapshotFlow { box.arrived.intValue }.first { it > 0 }
        fade.animateTo(1f, tween(LOOP_FADE_MS))
    }

    val paint = remember { Paint() }
    Spacer(
        modifier
            .onSizeChanged { size = it }
            .graphicsLayer { alpha = fade.value }
            .drawBehind {
                box.arrived.intValue
                val image = box.take() ?: return@drawBehind
                val iw = image.width.toFloat()
                val ih = image.height.toFloat()
                val scale = maxOf(this.size.width / iw, this.size.height / ih)
                val sw = this.size.width / scale
                val sh = this.size.height / scale
                val src = Rect.makeXYWH((iw - sw) / 2f, (ih - sh) / 2f, sw, sh)
                val dst = Rect.makeWH(this.size.width, this.size.height)
                drawIntoCanvas { it.skiaCanvas.drawImageRect(image, src, dst, SamplingMode.LINEAR, paint, true) }
            },
    )
}

// Reads frames while the loop plays: each new one is copied into a bitmap
// of the loop's size and handed to the drawing as an image of its own.
private suspend fun readFrames(video: LoopVideo, box: FrameBox) = withContext(Dispatchers.IO) {
    val width = video.width().toInt()
    val height = video.height().toInt()
    val bitmap = Bitmap()
    try {
        if (!bitmap.allocPixels(ImageInfo(width, height, ColorType.BGRA_8888, ColorAlphaType.OPAQUE))) return@withContext
        val pixels = bitmap.peekPixels() ?: return@withContext
        val address = pixels.addr.toULong()
        val rowBytes = pixels.rowBytes.toUInt()
        val length = pixels.computeByteSize().toULong()
        var have = 0uL
        while (isActive) {
            val newest = video.waitFrame(have, WaitMs)
            if (newest == have || newest == 0uL) {
                if (video.failure() != null) break
                continue
            }
            have = video.copyFrame(address, rowBytes, length, have)
            bitmap.notifyPixelsChanged()
            box.put(SkiaImage.makeFromBitmap(bitmap))
            withContext(Dispatchers.Main) { box.arrived.intValue++ }
        }
    } finally {
        bitmap.close()
    }
}

// The album's square loop over its cover: the cover first, then the loop
// fading in once its first frame is drawn, in the same box, corners and
// rim, so nothing jumps and nothing goes black. `seen` is whether the loop
// is on screen (the window shown and its page in front).
@Composable
fun AnimatedCover(
    model: AnimatedArtModel,
    albumId: String?,
    clip: AnimatedClip?,
    seen: Boolean,
    shape: Shape,
    modifier: Modifier = Modifier,
    // The size it shows at, for fetching the next song's at the same.
    measured: (Int) -> Unit = {},
    still: @Composable (Modifier) -> Unit,
) {
    Box(modifier) {
        still(Modifier.fillMaxSize())
        if (albumId == null || clip == null) return@Box
        val play = rememberLoopPlay(model, seen)
        if (play == LoopPlay.StillOnly) return@Box
        BoxWithConstraints(Modifier.fillMaxSize().clip(shape)) {
            val px = with(LocalDensity.current) { maxOf(maxWidth, maxHeight).roundToPx() }
            LaunchedEffect(px) { measured(px) }
            val file by produceState<File?>(null, albumId, clip.video) {
                value = model.loopFile(albumId, LoopShape.Square, clip, px, px)
            }
            ShowingFile(model, file)
            LoopFrames(file, play, Modifier.fillMaxSize())
            Box(Modifier.fillMaxSize().artworkRim(shape))
        }
    }
}

// Marks the file as on screen while it is, so the shelf keeps it.
@Composable
internal fun ShowingFile(model: AnimatedArtModel, file: File?) {
    DisposableEffect(file) {
        file?.let { model.showing(it, true) }
        onDispose { file?.let { model.showing(it, false) } }
    }
}

// The color a tall loop sits on: the clip's own, else the cover's.
fun backdropColor(clip: AnimatedClip, coverMain: Int?): Color {
    val rgb = clip.colorRgb ?: coverMain?.and(0xFFFFFF)?.takeIf { coverMain != 0 } ?: 0x101012
    return Color(0xFF000000.toInt() or rgb)
}

// Words over `base`: white unless dark words read better there.
fun inkOn(base: Color): Color {
    val light = relativeLuminance(base)
    val white = 1.05 / (light + 0.05)
    val dark = (light + 0.05) / 0.05
    return if (white >= 4.5 || white >= dark) Color.White else DarkInk
}

private fun relativeLuminance(color: Color): Double {
    fun channel(c: Float): Double = if (c <= 0.03928f) c / 12.92 else Math.pow((c + 0.055) / 1.055, 2.4)
    return 0.2126 * channel(color.red) + 0.7152 * channel(color.green) + 0.0722 * channel(color.blue)
}
