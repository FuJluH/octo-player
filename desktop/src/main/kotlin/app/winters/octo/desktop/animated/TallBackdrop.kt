package app.winters.octo.desktop.animated

import androidx.compose.animation.core.Animatable
import androidx.compose.animation.core.tween
import androidx.compose.foundation.Image
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.BoxWithConstraints
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.offset
import androidx.compose.foundation.layout.size
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.produceState
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberUpdatedState
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.drawBehind
import androidx.compose.ui.draw.drawWithContent
import androidx.compose.ui.graphics.BlendMode
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.CompositingStrategy
import androidx.compose.ui.graphics.drawscope.drawIntoCanvas
import androidx.compose.ui.graphics.graphicsLayer
import androidx.compose.ui.graphics.skiaCanvas
import androidx.compose.ui.graphics.toArgb
import androidx.compose.ui.graphics.toComposeImageBitmap
import androidx.compose.ui.layout.ContentScale
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.dp
import app.winters.octo.animated.LOOP_FADE_MS
import app.winters.octo.animated.LoopPlay
import app.winters.octo.design.LocalReduceMotion
import app.winters.octo.desktop.ui.DarkInk
import app.winters.octo.subsonic.AnimatedClip
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import kotlinx.coroutines.withTimeoutOrNull
import org.jetbrains.skia.ColorAlphaType
import org.jetbrains.skia.ColorFilter
import org.jetbrains.skia.ColorMatrix
import org.jetbrains.skia.ColorType
import org.jetbrains.skia.FilterTileMode
import org.jetbrains.skia.ImageFilter
import org.jetbrains.skia.ImageInfo
import org.jetbrains.skia.Paint
import org.jetbrains.skia.Rect
import org.jetbrains.skia.SamplingMode
import org.jetbrains.skia.Surface
import java.io.File
import kotlin.math.max
import kotlin.math.min
import kotlin.math.pow
import kotlin.math.roundToInt
import org.jetbrains.skia.Image as SkiaImage

// How long the still is waited for before the backdrop comes in on the
// clip's color alone.
private const val StillWaitMs = 1_500L

// The blurred fill is drawn this many pixels wide, then stretched.
private const val FillWidth = 96

// How soft the blur is, in the fill's own pixels (about 75 window pixels
// at 1440 wide).
private const val FillBlur = 5f

// Where the tall loop sits in the full player, in the player's pixels: its
// left edge, size, and where its foot starts and finishes fading out.
data class TallPlacement(val x: Float, val width: Float, val height: Float, val fadeStart: Float, val fadeEnd: Float) {
    val right: Float get() = x + width
}

// The tall loop at its own shape, never enlarged past it: as tall as the
// player where the space beside allows, else as wide as the space (from
// `areaLeft` to `areaRight`), from the top, centered on `center` within
// that space. Its top runs clean to the player's edge; its foot fades out,
// eased, as late as it can while it is still gone `gap` above the title
// (`titleTop`, or the loop's foot when not known yet).
fun tallPlacement(
    playerHeight: Float,
    areaLeft: Float,
    areaRight: Float,
    center: Float,
    titleTop: Float?,
    aspect: Float,
    gap: Float,
    leastFade: Float,
): TallPlacement {
    val shape = aspect.takeIf { it > 0f } ?: 0.75f
    val width = min(max(areaRight - areaLeft, 1f), playerHeight * shape)
    val height = width / shape
    val x = (center - width / 2f).coerceIn(areaLeft, max(areaLeft, areaRight - width))
    val end = min(height, titleTop?.let { it - gap } ?: height).coerceAtLeast(0f)
    val start = (end - max(height * 0.2f, leastFade)).coerceAtLeast(0f)
    return TallPlacement(x, width, height, start, end)
}

// The still picture behind everything for a tall loop, made once for its
// still and place: the still drawn where the loop is, its edges stretched
// out to the player's edges, blurred hard, and toned so the words read.
class TallFill(val image: SkiaImage, val ink: Color)

// Builds that fill, off the window's thread. Without a still it is the
// clip's color.
fun makeTallFill(still: SkiaImage?, color: Color, playerWidth: Float, playerHeight: Float, place: TallPlacement): TallFill {
    val w = FillWidth
    val h = max(1, (FillWidth * playerHeight / playerWidth).roundToInt())
    val s = w / playerWidth
    val raw = Surface.makeRasterN32Premul(w, h)
    raw.canvas.clear(color.toArgb())
    if (still != null) {
        val pw = still.width.toFloat()
        val ph = still.height.toFloat()
        val left = place.x * s
        val right = place.right * s
        val bottom = place.height * s
        val paint = Paint()
        val linear = SamplingMode.LINEAR
        // The foot's band across the whole width below the loop, then each
        // side's band out to the edge, then the still itself.
        raw.canvas.drawImageRect(still, Rect.makeLTRB(0f, ph * 0.9f, pw, ph), Rect.makeLTRB(0f, bottom - 1f, w.toFloat(), h.toFloat()), linear, paint, true)
        raw.canvas.drawImageRect(still, Rect.makeLTRB(0f, 0f, pw * 0.08f, ph), Rect.makeLTRB(0f, 0f, left + 1f, bottom), linear, paint, true)
        raw.canvas.drawImageRect(still, Rect.makeLTRB(pw * 0.92f, 0f, pw, ph), Rect.makeLTRB(right - 1f, 0f, w.toFloat(), bottom), linear, paint, true)
        raw.canvas.drawImageRect(still, Rect.makeWH(pw, ph), Rect.makeLTRB(left, 0f, right, bottom), linear, paint, true)
    }
    val drawn = raw.makeImageSnapshot()
    val blurred = Surface.makeRasterN32Premul(w, h)
    blurred.canvas.drawImage(drawn, 0f, 0f, Paint().apply { imageFilter = ImageFilter.makeBlur(FillBlur, FillBlur, FilterTileMode.CLAMP) })
    val soft = blurred.makeImageSnapshot()
    val tone = fillTone(lightnesses(soft))
    val toned = Surface.makeRasterN32Premul(w, h)
    toned.canvas.drawImage(soft, 0f, 0f, Paint().apply { colorFilter = tone.filter() })
    val image = toned.makeImageSnapshot()
    listOf(drawn, soft).forEach(SkiaImage::close)
    listOf(raw, blurred, toned).forEach(Surface::close)
    return TallFill(image, if (tone.white) Color.White else DarkInk)
}

// How the fill is toned for its words: white words on a fill darkened by
// `scale`, or dark ones on a fill lifted towards white by `lift`.
data class FillTone(val white: Boolean, val scale: Float, val lift: Float) {
    fun filter(): ColorFilter = ColorFilter.makeMatrix(
        ColorMatrix(
            scale * (1 - lift), 0f, 0f, 0f, lift,
            0f, scale * (1 - lift), 0f, 0f, lift,
            0f, 0f, scale * (1 - lift), 0f, lift,
            0f, 0f, 0f, 1f, 0f,
        ),
    )
}

// The tone that gives the words at least 4.5:1 over nearly all of the
// fill (all but its brightest or darkest twentieth): white words when they
// read better on its middle, darkening it as far as needed; else dark
// words, lifting it.
fun fillTone(lightness: List<Triple<Float, Float, Float>>): FillTone {
    if (lightness.isEmpty()) return FillTone(true, 1f, 0f)
    val lum = lightness.map { (r, g, b) -> luminance(r, g, b) }.sorted()
    val middle = lum[lum.size / 2]
    val whiteRatio = 1.05 / (middle + 0.05)
    val darkRatio = (middle + 0.05) / (luminanceOf(DarkInk) + 0.05)
    if (whiteRatio >= darkRatio) {
        var scale = 1f
        while (scale > 0.2f && lightness.quantile(0.95, scale, 0f) > 1.05 / 4.5 - 0.05) scale -= 0.04f
        return FillTone(true, scale, 0f)
    }
    var lift = 0f
    val darkest = (luminanceOf(DarkInk) + 0.05) * 4.5 - 0.05
    while (lift < 0.8f && lightness.quantile(0.05, 1f, lift) < darkest) lift += 0.04f
    return FillTone(false, 1f, lift)
}

private fun List<Triple<Float, Float, Float>>.quantile(at: Double, scale: Float, lift: Float): Double {
    val values = map { (r, g, b) ->
        luminance(r * scale * (1 - lift) + lift, g * scale * (1 - lift) + lift, b * scale * (1 - lift) + lift)
    }.sorted()
    return values[((values.size - 1) * at).roundToInt()]
}

private fun luminanceOf(color: Color): Double = luminance(color.red, color.green, color.blue)

private fun luminance(r: Float, g: Float, b: Float): Double {
    fun channel(c: Float): Double = if (c <= 0.03928f) c / 12.92 else ((c + 0.055) / 1.055).pow(2.4)
    return 0.2126 * channel(r) + 0.7152 * channel(g) + 0.0722 * channel(b)
}

// Each pixel's red, green and blue, from 0 to 1.
private fun lightnesses(image: SkiaImage): List<Triple<Float, Float, Float>> {
    val info = ImageInfo(image.width, image.height, ColorType.BGRA_8888, ColorAlphaType.PREMUL)
    val bitmap = org.jetbrains.skia.Bitmap()
    bitmap.allocPixels(info)
    image.readPixels(bitmap, 0, 0)
    val bytes = bitmap.readPixels(info, image.width * 4, 0, 0) ?: return emptyList()
    bitmap.close()
    return (bytes.indices step 4).map { i ->
        Triple((bytes[i + 2].toInt() and 0xFF) / 255f, (bytes[i + 1].toInt() and 0xFF) / 255f, (bytes[i].toInt() and 0xFF) / 255f)
    }
}

// The tall loop behind the full player, as Full screen shows it: at its own
// shape on the cover's side, its foot fading out before the title, on a
// blurred fill made from its still. Nothing shows until the still is there
// (or it has been waited for a moment); then it fades in, and `shown` is
// called once it covers what was under it. `ink` hears the words' color.
@Composable
fun TallBackdrop(
    model: AnimatedArtModel,
    albumId: String,
    clip: AnimatedClip,
    seen: Boolean,
    color: Color,
    // The space on the cover's side, its middle, and the title's top, in dp
    // of the player.
    areaLeft: Dp,
    areaRight: Dp,
    center: Dp,
    titleTop: Dp?,
    modifier: Modifier = Modifier,
    ink: (Color) -> Unit = {},
    shown: () -> Unit = {},
    measured: (Int, Int) -> Unit = { _, _ -> },
) {
    val play = rememberLoopPlay(model, seen)
    val calm = LocalReduceMotion.current
    val inkNow by rememberUpdatedState(ink)
    val shownNow by rememberUpdatedState(shown)
    BoxWithConstraints(modifier) {
        val density = LocalDensity.current
        val aspect = if (clip.width > 0 && clip.height > 0) clip.width.toFloat() / clip.height else 0.75f
        val place = with(density) {
            tallPlacement(
                maxHeight.toPx(), areaLeft.toPx(), areaRight.toPx(), center.toPx(), titleTop?.toPx(),
                aspect, gap = 12.dp.toPx(), leastFade = 110.dp.toPx(),
            )
        }
        val playerWidth = with(density) { maxWidth.toPx() }
        val playerHeight = with(density) { maxHeight.toPx() }
        val wPx = place.width.roundToInt()
        val hPx = place.height.roundToInt()
        LaunchedEffect(wPx, hPx) { measured(wPx, hPx) }

        // The still, read once.
        var stillWaited by remember(albumId) { mutableStateOf(false) }
        val still by produceState<SkiaImage?>(null, albumId, clip.poster) {
            val got = withTimeoutOrNull(StillWaitMs) { model.posterFile(albumId, LoopShape.Tall, clip) }
            stillWaited = true
            val file = got ?: model.posterFile(albumId, LoopShape.Tall, clip) ?: return@produceState
            value = withContext(Dispatchers.IO) { readStill(file) }
        }
        val stillBitmap = remember(still) { still?.toComposeImageBitmap() }
        // The fill, made again only when the still or the place changes.
        val fill by produceState<TallFill?>(null, still, place, playerWidth, playerHeight, color) {
            if (still == null && !stillWaited) return@produceState
            val made = withContext(Dispatchers.Default) { makeTallFill(still, color, playerWidth, playerHeight, place) }
            value?.image?.close()
            value = made
        }
        LaunchedEffect(fill?.ink) { fill?.ink?.let(inkNow) }
        val alpha = remember(albumId) { Animatable(0f) }
        LaunchedEffect(albumId, fill != null) {
            if (fill == null) return@LaunchedEffect
            if (calm) alpha.snapTo(1f) else alpha.animateTo(1f, tween(LOOP_FADE_MS))
            shownNow()
        }
        val current = fill ?: return@BoxWithConstraints
        val paint = remember { Paint() }
        Box(
            Modifier.fillMaxSize().graphicsLayer { this.alpha = alpha.value }.drawBehind {
                drawIntoCanvas {
                    val image = current.image
                    it.skiaCanvas.drawImageRect(
                        image, Rect.makeWH(image.width.toFloat(), image.height.toFloat()), Rect.makeWH(size.width, size.height),
                        SamplingMode.MITCHELL, paint, true,
                    )
                }
            },
        ) {
            val x: Dp = with(density) { place.x.toDp() }
            val width: Dp = with(density) { place.width.toDp() }
            val height: Dp = with(density) { place.height.toDp() }
            val atLeft = place.x <= 1f
            val atRight = place.right >= playerWidth - 1f
            Box(
                Modifier.offset(x = x).size(width, height)
                    .graphicsLayer { compositingStrategy = CompositingStrategy.Offscreen }
                    .drawWithContent {
                        drawContent()
                        drawRect(footMask(place), blendMode = BlendMode.DstIn)
                        drawRect(sideMask(atLeft, atRight, size.width), blendMode = BlendMode.DstIn)
                    },
            ) {
                stillBitmap?.let { Image(it, null, Modifier.fillMaxSize(), contentScale = ContentScale.Crop) }
                if (play != LoopPlay.StillOnly) {
                    val file by produceState<File?>(null, albumId, clip.video) {
                        value = model.loopFile(albumId, LoopShape.Tall, clip, wPx, hPx)
                    }
                    ShowingFile(model, file)
                    LoopFrames(file, play, Modifier.fillMaxSize())
                }
            }
        }
    }
}

// Opaque down to the fade's start, then eased out to nothing at its end.
private fun footMask(place: TallPlacement): Brush {
    val steps = 8
    val stops = buildList {
        add(0f to Color.Black)
        for (i in 0..steps) {
            val t = i / steps.toFloat()
            val y = place.fadeStart + (place.fadeEnd - place.fadeStart) * t
            // Smoothstep, so neither end of the fade shows as a line.
            val eased = t * t * (3 - 2 * t)
            add((y / place.height).coerceIn(0f, 1f) to Color.Black.copy(alpha = 1f - eased))
        }
        add(1f to Color.Transparent)
    }
    return Brush.verticalGradient(*stops.distinctBy { it.first }.toTypedArray(), startY = 0f, endY = place.height)
}

// The sides fade softly into the fill, but not at the player's own edge.
private fun sideMask(atLeft: Boolean, atRight: Boolean, width: Float): Brush = Brush.horizontalGradient(
    0f to if (atLeft) Color.Black else Color.Transparent,
    0.1f to Color.Black,
    0.9f to Color.Black,
    1f to if (atRight) Color.Black else Color.Transparent,
    startX = 0f,
    endX = width,
)

private fun readStill(file: File): SkiaImage? = runCatching { SkiaImage.makeFromEncoded(file.readBytes()) }.getOrNull()
