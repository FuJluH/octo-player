package app.winters.octo.animated

import android.content.Context
import android.graphics.Bitmap
import android.util.LruCache
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.BoxWithConstraints
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.size
import androidx.compose.ui.draw.drawBehind
import androidx.compose.ui.graphics.BlurEffect
import androidx.compose.ui.graphics.TileMode
import androidx.compose.ui.graphics.TransformOrigin
import androidx.compose.ui.unit.Dp
import androidx.compose.runtime.Composable
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.drawWithContent
import androidx.compose.ui.graphics.BlendMode
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.CompositingStrategy
import androidx.compose.ui.graphics.graphicsLayer
import androidx.compose.ui.layout.ContentScale
import app.winters.octo.player.immersive.DarkInkArgb
import app.winters.octo.player.immersive.contrastRatio
import app.winters.octo.player.immersive.relativeLuminance
import app.winters.octo.subsonic.AnimatedClip
import coil3.SingletonImageLoader
import coil3.compose.AsyncImage
import coil3.request.ImageRequest
import coil3.request.SuccessResult
import coil3.request.allowHardware
import coil3.toBitmap
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import kotlin.math.roundToInt

// A tall loop's shape, width over height, 3:4 when it does not say.
fun AnimatedClip.shape(): Float = if (width > 0 && height > 0) width.toFloat() / height else 3f / 4f

// How far above the song's name the sharp loop starts to dissolve into its
// blurred copy, as a share of the screen's height; it is gone at the top
// of the name.
private const val BLUR_REACH = 0.06f

// How much smaller than the screen the blurred copy of the loop is drawn,
// blurred while small (`SMALL_BLUR` of its own pixels) and stretched back
// up: a heavy blur for the cost of a small one.
private const val BLUR_SHRINK = 4
private const val SMALL_BLUR = 10f

// The darkening over the blurred copy, eased between these points (shares
// of the screen's height to how dark): none above the dissolve, a little at
// the song's name, more under the controls.
private val Darkening = listOf(0.50f to 0f, 0.54f to 0.10f, 0.62f to 0.25f, 1f to 0.35f)

// The tall loop filling the player: sharp at the screen's width at its own
// shape from the top edge (never zoomed in), dissolving above the song's
// name (`wordsTop()`, in pixels from the top) into a heavily blurred copy
// of itself that covers the whole screen behind everything, darkened
// gently toward the foot. With `veil()` at 1 (lyrics showing) the blurred
// copy covers everything. `wordsTop` and `veil` are read only while
// drawing.
@Composable
fun LoopBackdrop(
    clip: AnimatedClip,
    play: LoopPlay,
    blurPlay: LoopPlay,
    base: Color,
    wordsTop: () -> Float,
    veil: () -> Float,
    cover: @Composable () -> Unit,
    modifier: Modifier = Modifier,
) {
    val still: @Composable () -> Unit = {
        Box(Modifier.fillMaxSize().background(base)) {
            if (clip.poster.isNullOrBlank()) {
                cover()
            } else {
                AsyncImage(model = clip.poster, contentDescription = null, contentScale = ContentScale.Crop, modifier = Modifier.fillMaxSize())
            }
        }
    }
    BoxWithConstraints(modifier.fillMaxSize()) {
        val loopHeight = maxWidth / clip.shape()
        LoopVideo(clip, play, Modifier.fillMaxWidth().height(loopHeight), still = still)
        BlurredLoop(clip, blurPlay, maxWidth, maxHeight, wordsTop, veil, still)
        Darken(veil)
    }
}

// The blurred copy of the loop, covering the whole screen (cut at the
// sides): a small copy in the app's window, blurred while small and
// stretched up. Clear over the sharp loop down to a little above the
// song's name, then rising smoothly to solid at its top and below.
@Composable
private fun BlurredLoop(
    clip: AnimatedClip,
    play: LoopPlay,
    width: Dp,
    height: Dp,
    wordsTop: () -> Float,
    veil: () -> Float,
    still: @Composable () -> Unit,
) {
    Box(
        Modifier
            .fillMaxSize()
            .graphicsLayer { compositingStrategy = CompositingStrategy.Offscreen }
            .drawWithContent {
                drawContent()
                val screen = size.height
                val words = wordsTop().takeIf { it > 0f } ?: (screen * 0.54f)
                val end = words / screen
                drawRect(blurMask((end - BLUR_REACH).coerceAtLeast(0f), end, veil().coerceIn(0f, 1f)), blendMode = BlendMode.DstIn)
            },
    ) {
        Box(
            Modifier
                .size(width / BLUR_SHRINK, height / BLUR_SHRINK)
                .graphicsLayer {
                    scaleX = BLUR_SHRINK.toFloat()
                    scaleY = BLUR_SHRINK.toFloat()
                    transformOrigin = TransformOrigin(0f, 0f)
                    renderEffect = BlurEffect(SMALL_BLUR, SMALL_BLUR, TileMode.Clamp)
                },
        ) {
            LoopVideo(clip, play, Modifier.fillMaxSize(), inWindow = true, still = still)
        }
    }
}

// The gentle darkening over the blurred copy, eased with no steps. With
// the veil, the darkest of it everywhere, for lyrics.
@Composable
private fun Darken(veil: () -> Float) {
    Box(
        Modifier.fillMaxSize().drawBehind {
            val shown = veil().coerceIn(0f, 1f)
            val most = Darkening.maxOf { it.second }
            drawRect(gradient(easedStops(Darkening).map { (y, a) -> y to a + (most - a) * shown }))
        },
    )
}

private fun smooth(t: Float) = t * t * (3 - 2 * t)

// Stops between the given points, eased with a smooth step between each
// pair, so nothing shows where one stretch meets the next.
private fun easedStops(points: List<Pair<Float, Float>>): List<Pair<Float, Float>> = buildList {
    add(0f to points.first().second)
    for ((a, b) in points.zipWithNext()) {
        for (i in 0 until 8) {
            val t = i / 8f
            add((a.first + (b.first - a.first) * t) to (a.second + (b.second - a.second) * smooth(t)))
        }
    }
    add(points.last())
    if (points.last().first < 1f) add(1f to points.last().second)
}

private fun gradient(stops: List<Pair<Float, Float>>): Brush =
    Brush.verticalGradient(*stops.map { (y, a) -> y.coerceIn(0f, 1f) to Color.Black.copy(alpha = a.coerceIn(0f, 1f)) }.sortedBy { it.first }.toTypedArray())

// The blurred copy's mask, in shares of the screen's height: clear to
// `start`, rising smoothly to solid at `end`, and solid below. `shown` (the
// veil) lifts the clear part.
private fun blurMask(start: Float, end: Float, shown: Float): Brush =
    gradient(easedStops(listOf(start to 0f, end to 1f)).map { (y, a) -> y to a + (1f - a) * shown })

// How dark the darkening is at the foot, which the plain color allows for.
private const val FOOT_DARKENING = 0.35f

// A tall loop's colors, from its poster: the words' ink over the loop, its
// plain color (the bottom of the poster, averaged and dimmed as far as the
// words need), and whether its top is light (so the status icons and the
// album's name go dark over it).
data class BackdropFill(val ink: FillInk, val base: Color, val lightTop: Boolean = false)

// How a clip's colors are found: from the bottom and top of its poster;
// kept for the clips seen lately.
object BackdropFills {
    private val made = LruCache<String, BackdropFill>(8)

    // The fill for `clip`: from its poster, or a flat `fallback` color when
    // it has none or the poster cannot be had.
    suspend fun fillFor(context: Context, clip: AnimatedClip, fallback: Int): BackdropFill {
        val key = "${clip.poster}|$fallback"
        made.get(key)?.let { return it }
        val poster = clip.poster?.takeIf(String::isNotBlank)?.let { address ->
            val request = ImageRequest.Builder(context).data(address).allowHardware(false).size(256).build()
            (SingletonImageLoader.get(context).execute(request) as? SuccessResult)?.image?.toBitmap()
        }
        val fill = withContext(Dispatchers.Default) { poster?.let { fromPoster(it).copy(lightTop = lightTop(it)) } ?: flat(fallback) }
        made.put(key, fill)
        return fill
    }

    // The poster's bottom band, averaged: the loop's plain color.
    private fun fromPoster(poster: Bitmap): BackdropFill {
        val bandTop = (poster.height * 0.85f).roundToInt().coerceIn(0, poster.height - 1)
        val band = Bitmap.createScaledBitmap(Bitmap.createBitmap(poster, 0, bandTop, poster.width, poster.height - bandTop), 16, 4, true)
        val pixels = IntArray(64)
        band.getPixels(pixels, 0, 16, 0, 0, 16, 4)
        return finish(pixels)
    }

    // Whether the poster's top band is light: dark words and icons read on
    // it better than white ones.
    private fun lightTop(poster: Bitmap): Boolean {
        val band = Bitmap.createScaledBitmap(Bitmap.createBitmap(poster, 0, 0, poster.width, (poster.height * 0.08f).roundToInt().coerceAtLeast(1)), 16, 2, true)
        val pixels = IntArray(32)
        band.getPixels(pixels, 0, 16, 0, 0, 16, 2)
        val mean = 0xFF000000.toInt() or meanColor(pixels)
        return contrastRatio(DarkInkArgb, mean) > contrastRatio(0xFFFFFFFF.toInt(), mean)
    }

    private fun meanColor(pixels: IntArray): Int {
        var r = 0L
        var g = 0L
        var b = 0L
        for (p in pixels) {
            r += p shr 16 and 0xFF
            g += p shr 8 and 0xFF
            b += p and 0xFF
        }
        val n = pixels.size
        return ((r / n).toInt() shl 16) or ((g / n).toInt() shl 8) or (b / n).toInt()
    }

    private fun flat(color: Int): BackdropFill = finish(IntArray(4) { color or 0xFF000000.toInt() })

    // The words' ink over the loop's colors, and its plain color, dimmed so
    // that, under the foot's darkening, the words hold there too.
    private fun finish(pixels: IntArray): BackdropFill {
        val low = pixels.minBy { relativeLuminance(it) }
        val high = pixels.maxBy { relativeLuminance(it) }
        val ink = fillInk(low, high, LoopInkNeeds)
        val plain = dimmed(0xFF000000.toInt() or meanColor(pixels), (ink.gain / (1f - FOOT_DARKENING)).coerceAtMost(1f))
        return BackdropFill(ink, Color(plain))
    }
}
