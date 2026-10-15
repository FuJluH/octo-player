package app.winters.octo.animated

import android.content.Context
import android.graphics.Bitmap
import android.util.LruCache
import androidx.compose.foundation.Image
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.BoxWithConstraints
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.runtime.Composable
import androidx.compose.runtime.remember
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.drawWithContent
import androidx.compose.ui.graphics.BlendMode
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.CompositingStrategy
import androidx.compose.ui.graphics.FilterQuality
import androidx.compose.ui.graphics.ImageBitmap
import androidx.compose.ui.graphics.asImageBitmap
import androidx.compose.ui.graphics.graphicsLayer
import androidx.compose.ui.graphics.painter.BitmapPainter
import androidx.compose.ui.layout.ContentScale
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.unit.dp
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

// The tall loop at the top of the player, as wide as the screen at its own
// shape (never zoomed in), its poster first.
@Composable
fun LoopBackdrop(clip: AnimatedClip, play: LoopPlay, fill: Color, cover: @Composable () -> Unit, modifier: Modifier = Modifier) {
    BoxWithConstraints(modifier.fillMaxSize()) {
        LoopVideo(clip, play, Modifier.fillMaxWidth().height(maxWidth / clip.shape())) {
            Box(Modifier.fillMaxSize().background(fill)) {
                if (clip.poster.isNullOrBlank()) {
                    cover()
                } else {
                    AsyncImage(model = clip.poster, contentDescription = null, contentScale = ContentScale.Crop, modifier = Modifier.fillMaxSize())
                }
            }
        }
    }
}

// How far above the song's name the loop is gone, and how tall its fade
// into the fill is: as late and short as still reads as a melt.
private val FadeGap = 12.dp
private val FadeLength = 120.dp

// The still fill under the words: drawn over the whole player, clear over
// the loop up to its top edge and solid from just above the song's name
// (`wordsTop()`, in pixels from the top) down, with an eased fade between
// so the loop melts into it. With `veil()` at 1 (lyrics showing) it covers
// everything. Its picture is made once per clip and its layer redraws only
// when these change.
@Composable
fun BackdropFillLayer(fill: BackdropFill, shape: Float, wordsTop: () -> Float, veil: () -> Float, modifier: Modifier = Modifier) {
    val painter = remember(fill.picture) { BitmapPainter(fill.picture, filterQuality = FilterQuality.High) }
    val density = LocalDensity.current
    val gap = with(density) { FadeGap.toPx() }
    val length = with(density) { FadeLength.toPx() }
    Image(
        painter,
        contentDescription = null,
        contentScale = ContentScale.FillBounds,
        modifier = modifier
            .fillMaxSize()
            .graphicsLayer { compositingStrategy = CompositingStrategy.Offscreen }
            .drawWithContent {
                drawContent()
                val height = size.height
                val loopBottom = size.width / shape
                val words = wordsTop().takeIf { it > 0f } ?: (height * 0.55f)
                val end = minOf(words - gap, loopBottom).coerceIn(1f, height)
                val start = (end - length).coerceIn(0f, end)
                val shown = veil().coerceIn(0f, 1f)
                fun alpha(a: Float) = a + (1f - a) * shown
                val stops = buildList {
                    add(0f to alpha(0f))
                    add(start / height to alpha(0f))
                    // A smooth step from clear to solid, so no line shows.
                    for (i in 1..5) {
                        val t = i / 6f
                        add((start + (end - start) * t) / height to alpha(t * t * (3 - 2 * t)))
                    }
                    add(end / height to 1f)
                    add(1f to 1f)
                }
                drawRect(Brush.verticalGradient(*stops.map { (y, a) -> y to Color.Black.copy(alpha = a) }.toTypedArray()), blendMode = BlendMode.DstIn)
            },
    )
}

// A tall loop's fill: a still picture from the loop's own colors, the
// words' ink over it, its average color, and whether the loop's top is
// light (so the status icons and the album's name go dark over it).
data class BackdropFill(val picture: ImageBitmap, val ink: FillInk, val base: Color, val lightTop: Boolean = false)

// How a clip's fill is made: the bottom of its poster, blurred heavily and
// dimmed as far as the words need, kept for the clips seen lately.
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

    // The poster's bottom band, shrunk to a few pixels, grown back a little
    // and blurred, so it stretches over the player as a soft wash.
    private fun fromPoster(poster: Bitmap): BackdropFill {
        val bandTop = (poster.height * 0.8f).roundToInt().coerceIn(0, poster.height - 1)
        val band = Bitmap.createBitmap(poster, 0, bandTop, poster.width, poster.height - bandTop)
        val tiny = Bitmap.createScaledBitmap(band, 8, 4, true)
        val soft = Bitmap.createScaledBitmap(tiny, FILL_WIDTH, FILL_HEIGHT, true)
        val pixels = IntArray(FILL_WIDTH * FILL_HEIGHT)
        soft.getPixels(pixels, 0, FILL_WIDTH, 0, 0, FILL_WIDTH, FILL_HEIGHT)
        repeat(3) { boxBlur(pixels, FILL_WIDTH, FILL_HEIGHT, 10) }
        return finish(pixels, FILL_WIDTH, FILL_HEIGHT)
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

    private fun flat(color: Int): BackdropFill = finish(IntArray(4) { color or 0xFF000000.toInt() }, 2, 2)

    // Dims the picture as far as the words' ink needs.
    private fun finish(pixels: IntArray, width: Int, height: Int): BackdropFill {
        val low = pixels.minBy { relativeLuminance(it) }
        val high = pixels.maxBy { relativeLuminance(it) }
        val ink = fillInk(low, high)
        for (i in pixels.indices) pixels[i] = dimmed(pixels[i], ink.gain)
        val picture = Bitmap.createBitmap(pixels, width, height, Bitmap.Config.ARGB_8888)
        return BackdropFill(picture.asImageBitmap(), ink, Color(0xFF000000.toInt() or meanColor(pixels)))
    }
}

// The fill picture's size: small, as it is only a wash of a few colors.
private const val FILL_WIDTH = 64
private const val FILL_HEIGHT = 32

// One pass of a box blur `radius` pixels each way, across then down.
internal fun boxBlur(pixels: IntArray, width: Int, height: Int, radius: Int) {
    val out = IntArray(pixels.size)
    fun pass(read: IntArray, write: IntArray, lines: Int, length: Int, at: (line: Int, i: Int) -> Int) {
        for (line in 0 until lines) {
            for (i in 0 until length) {
                var r = 0
                var g = 0
                var b = 0
                for (k in -radius..radius) {
                    val p = read[at(line, (i + k).coerceIn(0, length - 1))]
                    r += p shr 16 and 0xFF
                    g += p shr 8 and 0xFF
                    b += p and 0xFF
                }
                val n = 2 * radius + 1
                write[at(line, i)] = (0xFF shl 24) or ((r / n) shl 16) or ((g / n) shl 8) or (b / n)
            }
        }
    }
    pass(pixels, out, height, width) { line, i -> line * width + i }
    pass(out, pixels, width, height) { line, i -> i * width + line }
}
