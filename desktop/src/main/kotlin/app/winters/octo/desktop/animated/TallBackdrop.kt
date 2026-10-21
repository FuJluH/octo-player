package app.winters.octo.desktop.animated

import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.BoxWithConstraints
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.offset
import androidx.compose.foundation.layout.size
import androidx.compose.animation.core.Animatable
import androidx.compose.animation.core.tween
import androidx.compose.runtime.Composable
import androidx.compose.runtime.DisposableEffect
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
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.graphics.BlendMode
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.CompositingStrategy
import androidx.compose.ui.graphics.drawscope.drawIntoCanvas
import androidx.compose.ui.graphics.graphicsLayer
import androidx.compose.ui.graphics.skiaCanvas
import androidx.compose.ui.graphics.toArgb
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.IntSize
import androidx.compose.ui.unit.dp
import app.winters.octo.animated.LOOP_FADE_MS
import app.winters.octo.animated.LoopPlay
import app.winters.octo.design.LocalReduceMotion
import app.winters.octo.desktop.ui.DarkInk
import app.winters.octo.desktop.ui.LateClose
import app.winters.octo.desktop.ui.Shared
import app.winters.octo.subsonic.AnimatedClip
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import kotlinx.coroutines.withTimeoutOrNull
import org.jetbrains.skia.ColorAlphaType
import org.jetbrains.skia.ColorFilter
import org.jetbrains.skia.ColorMatrix
import org.jetbrains.skia.ColorType
import org.jetbrains.skia.CubicResampler
import org.jetbrains.skia.FilterMipmap
import org.jetbrains.skia.FilterMode
import org.jetbrains.skia.FilterTileMode
import org.jetbrains.skia.ImageInfo
import org.jetbrains.skia.Matrix33
import org.jetbrains.skia.MipmapMode
import org.jetbrains.skia.Paint
import org.jetbrains.skia.Rect
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

// The blurred copy of the loop is this many pixels across, then drawn
// large and smooth, which blurs it with no blur filter at all.
private const val SoftWidth = 20

// A smooth cubic (B-spline), so the enlarged copy has no edges or rings.
private val Smooth = CubicResampler(1f, 0f)

// Where the tall loop sits in the full player, in the player's pixels: its
// left edge, size, and where its foot starts and finishes giving way to
// its blurred copy.
data class TallPlacement(val x: Float, val width: Float, val height: Float, val fadeStart: Float, val fadeEnd: Float) {
    val right: Float get() = x + width
}

// The tall loop at its own shape, never enlarged past it: as tall as the
// player where the space beside allows, else as wide as the space (from
// `areaLeft` to `areaRight`), from the top, centered on `center` within
// that space. Its top runs clean to the player's edge; towards the title
// it dissolves into its blurred copy over an eased band (`leastRamp` at
// least, a sixth of its height on a tall one) that ends `gap` above the
// title's top (below it for a negative gap: the words' capitals sit a
// little under it), or at the loop's foot when that is not known yet.
fun tallPlacement(
    playerHeight: Float,
    areaLeft: Float,
    areaRight: Float,
    center: Float,
    titleTop: Float?,
    aspect: Float,
    gap: Float,
    leastRamp: Float,
): TallPlacement {
    val shape = aspect.takeIf { it > 0f } ?: 0.75f
    val width = min(max(areaRight - areaLeft, 1f), playerHeight * shape)
    val height = width / shape
    val x = (center - width / 2f).coerceIn(areaLeft, max(areaLeft, areaRight - width))
    val end = min(height, titleTop?.let { it - gap } ?: height).coerceAtLeast(0f)
    val start = (end - max(height * 0.16f, leastRamp)).coerceAtLeast(0f)
    return TallPlacement(x, width, height, start, end)
}

// The still's small copy and how the blurred loop is toned so the words
// read on it, made once per clip.
class SoftStill(val small: SkiaImage?, val tiny: SkiaImage?, val tone: FillTone, val ink: Color)

// Shrinks the still to the blurred copy's size and works out its tone;
// without a still, the clip's color.
fun softStill(still: SkiaImage?, color: Color, aspect: Float): SoftStill {
    val w = SoftWidth
    val h = max(1, (SoftWidth / aspect).roundToInt())
    val surface = Surface.makeRasterN32Premul(w, h)
    surface.canvas.clear(color.toArgb())
    if (still != null) {
        Paint().use { paint ->
            surface.canvas.drawImageRect(
                still, Rect.makeWH(still.width.toFloat(), still.height.toFloat()), Rect.makeWH(w.toFloat(), h.toFloat()),
                FilterMipmap(FilterMode.LINEAR, MipmapMode.LINEAR), paint, true,
            )
        }
    }
    val small = surface.makeImageSnapshot()
    surface.close()
    val little = Surface.makeRasterN32Premul(max(2, w / 2), max(2, h / 2))
    edgePaint().use { paint ->
        little.canvas.drawImageRect(small, Rect.makeWH(w.toFloat(), h.toFloat()), Rect.makeWH(little.width.toFloat(), little.height.toFloat()), FilterMipmap(FilterMode.LINEAR, MipmapMode.LINEAR), paint, true)
    }
    val tiny = little.makeImageSnapshot()
    little.close()
    val tone = fillTone(lightnesses(small))
    return SoftStill(small, tiny, tone, if (tone.white) Color.White else DarkInk)
}

// How the fill is toned for its words: white words on a fill darkened by
// `scale`, or dark ones on a fill lifted towards white by `lift`.
data class FillTone(val white: Boolean, val scale: Float, val lift: Float) {
    // A color as the filter below tones it.
    fun applied(color: Color): Color {
        fun channel(c: Float) = (c * scale * (1 - lift) + lift).coerceIn(0f, 1f)
        return Color(channel(color.red), channel(color.green), channel(color.blue), color.alpha)
    }

    fun filter(): ColorFilter = ColorFilter.makeMatrix(
        ColorMatrix(
            scale * (1 - lift), 0f, 0f, 0f, lift,
            0f, scale * (1 - lift), 0f, 0f, lift,
            0f, 0f, scale * (1 - lift), 0f, lift,
            0f, 0f, 0f, 1f, 0f,
        ),
    )
}

// The contrast white words get over nearly all of the fill: more than the
// 4.5:1 a word needs, so the lyrics' quieter lines read too.
private const val WhiteRatio = 6.5

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
        while (scale > 0.2f && lightness.quantile(0.95, scale, 0f) > 1.05 / WhiteRatio - 0.05) scale -= 0.04f
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

// The tall loop behind the full player, as Full screen shows it, the way
// Apple Music does: sharp at its own shape on the cover's side, running
// clean to the top, and towards the title dissolving over an eased band
// into a blurred copy of itself that carries on, still moving, behind the
// title, the controls and everything else, toned so the words read. The
// blur is the loop's small copy drawn large and smooth, so no frame is
// ever blurred by a filter. Nothing shows until the still is there (or it
// has been waited for a moment); then it fades in, and `shown` is called
// once it covers what was under it. `ink` hears the words' color.
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
                aspect, gap = -16.dp.toPx(), leastRamp = 148.dp.toPx(),
            )
        }
        val playerWidth = with(density) { maxWidth.toPx() }
        val playerHeight = with(density) { maxHeight.toPx() }
        val wPx = place.width.roundToInt()
        val hPx = place.height.roundToInt()
        LaunchedEffect(wPx, hPx) { measured(wPx, hPx) }

        // The still and its small copy, made once, and closed once replaced
        // (the small copy is made from the still off the window's thread,
        // so the still waits for that too).
        var stillWaited by remember(albumId) { mutableStateOf(false) }
        val stillHeld by produceState<Shared<SkiaImage>?>(null, albumId, clip.poster) {
            val got = withTimeoutOrNull(StillWaitMs) { model.posterFile(albumId, LoopShape.Tall, clip) }
            stillWaited = true
            val file = got ?: model.posterFile(albumId, LoopShape.Tall, clip) ?: return@produceState
            value = withContext(Dispatchers.IO) { readStill(file) }?.let(::Shared)
        }
        // Each effect below closes the value it was keyed on: read inside
        // onDispose, a delegate gives the one replacing it.
        val held = stillHeld
        DisposableEffect(held) { onDispose { held?.release() } }
        val still = held?.thing
        val soft by produceState<SoftStill?>(null, held, stillWaited, color, aspect) {
            if (held == null && !stillWaited) return@produceState
            value = withContext(Dispatchers.Default) {
                if (held == null) softStill(null, color, aspect) else held.use { softStill(it, color, aspect) }
            }
        }
        val softNow = soft
        DisposableEffect(softNow) {
            onDispose {
                LateClose.close(softNow?.small)
                LateClose.close(softNow?.tiny)
            }
        }
        LaunchedEffect(softNow) { softNow?.ink?.let(inkNow) }
        val alpha = remember(albumId) { Animatable(0f) }
        LaunchedEffect(albumId, soft != null) {
            if (soft == null) return@LaunchedEffect
            if (calm) alpha.snapTo(1f) else alpha.animateTo(1f, tween(LOOP_FADE_MS))
            shownNow()
        }
        val ready = soft ?: return@BoxWithConstraints
        val file by produceState<File?>(null, albumId, clip.video, play == LoopPlay.StillOnly) {
            if (play == LoopPlay.StillOnly) return@produceState
            value = model.loopFile(albumId, LoopShape.Tall, clip, wPx, hPx)
        }
        ShowingFile(model, file)
        val smallSize = ready.small?.let { IntSize(it.width, it.height) }
        val feed = rememberLoopFeed(file, play, IntSize(wPx, hPx), small = smallSize)
        val tone = remember(ready) { ready.tone.filter() }
        val blurPaint = remember(tone) { Paint().apply { colorFilter = tone } }
        DisposableEffect(blurPaint) {
            onDispose {
                LateClose.close(blurPaint)
                LateClose.close(tone)
            }
        }
        val sharpPaint = remember { Paint() }
        DisposableEffect(sharpPaint) { onDispose { LateClose.close(sharpPaint) } }
        // The words' side darkens (or lightens) a little more, gently.
        val shade = if (ready.tone.white) Color.Black else Color.White
        Box(Modifier.fillMaxSize().graphicsLayer { this.alpha = alpha.value }) {
            // The small copy of the newest frame (the still's before the
            // first), taken once per frame for both blurred layers.
            fun smallNow(): SkiaImage? {
                feed.smalls?.arrived?.intValue
                return feed.smalls?.take()?.takeIf { feed.frames.arrived.intValue > 0 } ?: ready.small
            }
            val x: Dp = with(density) { place.x.toDp() }
            val width: Dp = with(density) { place.width.toDp() }
            val height: Dp = with(density) { place.height.toDp() }
            val atLeft = place.x <= 1f
            val atRight = place.right >= playerWidth - 1f
            // The blurred loop over the whole player: its tiniest copy at the
            // sharp loop's place and size, its edge colors carried out to the
            // player's edges, so the colors beside the loop are its own.
            val footColors = remember { FootColors() }
            fun tinyNow(): SkiaImage? {
                feed.tinies?.arrived?.intValue
                return feed.tinies?.take()?.takeIf { feed.frames.arrived.intValue > 0 } ?: ready.tiny
            }
            Spacer(
                Modifier.fillMaxSize().drawBehind {
                    feed.frames.arrived.intValue
                    val image = tinyNow() ?: return@drawBehind
                    val local = Matrix33.makeTranslate(place.x, 0f).makeConcat(
                        Matrix33.makeScale(place.width / image.width, place.height / image.height),
                    )
                    // The frame's shader is made for it; what was drawn keeps
                    // its own hold on it.
                    val shader = image.makeShader(FilterTileMode.CLAMP, FilterTileMode.CLAMP, Smooth, local)
                    blurPaint.shader = shader
                    drawIntoCanvas { it.skiaCanvas.drawRect(Rect.makeWH(size.width, size.height), blurPaint) }
                    blurPaint.shader = null
                    shader.close()
                    // Below a loop shorter than the player its last row would
                    // run on down as stripes behind the title and controls:
                    // there it eases into one even fill of its foot's color.
                    if (place.height < size.height - 1f) {
                        val foot = ready.tone.applied(Color(footColors.of(image)))
                        val ramp = FootRamp.toPx()
                        drawRect(
                            Brush.verticalGradient(0f to foot.copy(alpha = 0f), 1f to foot, startY = place.height, endY = place.height + ramp),
                            topLeft = Offset(0f, place.height),
                            size = androidx.compose.ui.geometry.Size(size.width, ramp),
                        )
                        drawRect(foot, topLeft = Offset(0f, place.height + ramp), size = androidx.compose.ui.geometry.Size(size.width, size.height - place.height - ramp))
                    }
                },
            )
            // And at the sharp loop's own place and size, so what the sharp
            // loop dissolves into is itself, blurred; its edges melt into
            // the layer under it.
            Spacer(
                Modifier.offset(x = x).size(width, height)
                    .graphicsLayer { compositingStrategy = CompositingStrategy.Offscreen }
                    .drawWithContent {
                        drawContent()
                        drawRect(softSides(atLeft, atRight, size.width), blendMode = BlendMode.DstIn)
                        if (place.height < playerHeight - 1f) drawRect(softFoot(size.height), blendMode = BlendMode.DstIn)
                    }
                    .drawBehind {
                        feed.frames.arrived.intValue
                        val image = smallNow() ?: return@drawBehind
                        drawIntoCanvas { smoothCover(it.skiaCanvas, image, size.width, size.height, blurPaint) }
                    },
            )
            // A little more shade on the words' side, gently, never at the top.
            Spacer(
                Modifier.fillMaxSize().drawBehind {
                    drawRect(
                        Brush.verticalGradient(
                            0f to Color.Transparent,
                            (place.fadeStart / size.height).coerceIn(0f, 1f) to Color.Transparent,
                            1f to shade.copy(alpha = 0.28f),
                        ),
                    )
                },
            )
            // The sharp loop, dissolving into the blurred one at its foot
            // and softly at its sides (not at the player's own edges).
            Spacer(
                Modifier.offset(x = x).size(width, height)
                    .graphicsLayer { compositingStrategy = CompositingStrategy.Offscreen }
                    .drawWithContent {
                        drawContent()
                        drawRect(footMask(place), blendMode = BlendMode.DstIn)
                        drawRect(sideMask(atLeft, atRight, size.width), blendMode = BlendMode.DstIn)
                    }
                    .drawBehind {
                        feed.frames.arrived.intValue
                        drawIntoCanvas { canvas ->
                            still?.let { coverDraw(canvas.skiaCanvas, it, size.width, size.height, sharpPaint, TopTrim) }
                            val frame = feed.frames.take() ?: return@drawIntoCanvas
                            sharpPaint.alpha = (feed.fade.value * 255).roundToInt()
                            coverDraw(canvas.skiaCanvas, frame, size.width, size.height, sharpPaint, TopTrim)
                            sharpPaint.alpha = 255
                        }
                    },
            )
            // A soft spot behind the window's own buttons at the top left,
            // so they read over a light loop; the top edge stays clean.
            Spacer(
                Modifier.fillMaxSize().drawBehind {
                    val spot = Offset(64.dp.toPx(), 20.dp.toPx())
                    drawRect(
                        Brush.radialGradient(
                            0f to shade.copy(alpha = 0.26f),
                            0.55f to shade.copy(alpha = 0.12f),
                            1f to Color.Transparent,
                            center = spot,
                            radius = 120.dp.toPx(),
                        ),
                    )
                },
            )
        }
    }
}

// How far below a short loop's foot its blurred copy takes to ease into one
// even fill.
private val FootRamp = 120.dp

// The average color of the bottom fifth of a small copy, as opaque ARGB,
// worked out again only when the copy changes.
internal class FootColors {
    private var last: SkiaImage? = null
    private var color = 0xFF000000.toInt()

    fun of(image: SkiaImage): Int {
        if (image === last) return color
        last = image
        color = footColor(image) ?: color
        return color
    }
}

internal fun footColor(image: SkiaImage): Int? {
    val info = ImageInfo(image.width, image.height, ColorType.BGRA_8888, ColorAlphaType.PREMUL)
    val bitmap = org.jetbrains.skia.Bitmap()
    try {
        if (!bitmap.allocPixels(info) || !image.readPixels(bitmap, 0, 0)) return null
        val bytes = bitmap.readPixels(info, image.width * 4, 0, 0) ?: return null
        val from = image.height - maxOf(1, image.height / 5)
        var r = 0L
        var g = 0L
        var b = 0L
        var n = 0
        for (y in from until image.height) for (x in 0 until image.width) {
            val o = (y * image.width + x) * 4
            b += bytes[o].toInt() and 0xFF
            g += bytes[o + 1].toInt() and 0xFF
            r += bytes[o + 2].toInt() and 0xFF
            n++
        }
        if (n == 0) return null
        return (0xFF shl 24) or ((r / n).toInt() shl 16) or ((g / n).toInt() shl 8) or (b / n).toInt()
    } finally {
        bitmap.close()
    }
}

// Rows left off the top of the tall loop: Apple's carry a darker first row.
private const val TopTrim = 2f

// Opaque down to the band's start, then eased out to nothing at its end.
private fun footMask(place: TallPlacement): Brush {
    val steps = 10
    val stops = buildList {
        add(0f to Color.Black)
        for (i in 0..steps) {
            val t = i / steps.toFloat()
            val y = place.fadeStart + (place.fadeEnd - place.fadeStart) * t
            // Smootherstep, so neither end of the band shows as a line.
            val eased = t * t * t * (t * (t * 6 - 15) + 10)
            add((y / place.height).coerceIn(0f, 1f) to Color.Black.copy(alpha = 1f - eased))
        }
        add(1f to Color.Transparent)
    }
    return Brush.verticalGradient(*stops.distinctBy { it.first }.toTypedArray(), startY = 0f, endY = place.height)
}

// The sides dissolve softly into the blurred copy, but not at the player's
// own edge.
private fun sideMask(atLeft: Boolean, atRight: Boolean, width: Float): Brush = Brush.horizontalGradient(
    0f to if (atLeft) Color.Black else Color.Transparent,
    0.16f to Color.Black,
    0.84f to Color.Black,
    1f to if (atRight) Color.Black else Color.Transparent,
    startX = 0f,
    endX = width,
)

// Draws a small image scaled to cover the box, enlarged smoothly.
private fun smoothCover(canvas: org.jetbrains.skia.Canvas, image: SkiaImage, width: Float, height: Float, paint: Paint) {
    val iw = image.width.toFloat()
    val ih = image.height.toFloat()
    val scale = max(width / iw, height / ih)
    val sw = width / scale
    val sh = height / scale
    canvas.drawImageRect(image, Rect.makeXYWH((iw - sw) / 2f, (ih - sh) / 2f, sw, sh), Rect.makeWH(width, height), Smooth, paint, false)
}

// The aligned blurred copy's edges: its sides (not at the player's own
// edges), and its foot when it ends above the player's, melt away.
private fun softSides(atLeft: Boolean, atRight: Boolean, width: Float): Brush = Brush.horizontalGradient(
    0f to if (atLeft) Color.Black else Color.Transparent,
    0.3f to Color.Black,
    0.7f to Color.Black,
    1f to if (atRight) Color.Black else Color.Transparent,
    startX = 0f,
    endX = width,
)

private fun softFoot(height: Float): Brush =
    Brush.verticalGradient(0f to Color.Black, 0.8f to Color.Black, 1f to Color.Transparent, startY = 0f, endY = height)

private fun readStill(file: File): SkiaImage? = runCatching { SkiaImage.makeFromEncoded(file.readBytes()) }.getOrNull()
