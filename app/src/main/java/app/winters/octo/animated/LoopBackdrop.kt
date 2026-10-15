package app.winters.octo.animated

import android.content.Context
import android.graphics.Bitmap
import android.os.Build
import android.util.LruCache
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.BoxWithConstraints
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.offset
import androidx.compose.foundation.layout.requiredSize
import androidx.compose.ui.Alignment
import androidx.compose.ui.draw.clipToBounds
import androidx.compose.runtime.Composable
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.drawWithContent
import androidx.compose.ui.graphics.BlendMode
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.CompositingStrategy
import androidx.compose.ui.graphics.RenderEffect
import androidx.compose.ui.graphics.asComposeRenderEffect
import androidx.compose.ui.graphics.graphicsLayer
import androidx.compose.ui.layout.ContentScale
import app.winters.octo.player.immersive.DarkInkArgb
import app.winters.octo.player.immersive.contrastRatio
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

// The tall loop at the top of the player, as FullScreenLook sets it out:
// FULL_SCREEN_ZOOM times the screen's width at its own shape, centered,
// lifted FULL_SCREEN_LOOP_TOP above the top edge, its poster first. The
// player's own background is drawn over its lower part through meltMask.
@Composable
fun LoopBackdrop(clip: AnimatedClip, play: LoopPlay, base: Color, cover: @Composable () -> Unit, modifier: Modifier = Modifier) {
    BoxWithConstraints(modifier.fillMaxSize().clipToBounds(), contentAlignment = Alignment.TopCenter) {
        val width = maxWidth * FULL_SCREEN_ZOOM
        LoopVideo(
            clip,
            play,
            Modifier
                .offset(y = maxHeight * FULL_SCREEN_LOOP_TOP)
                .requiredSize(width, width / clip.shape()),
        ) {
            Box(Modifier.fillMaxSize().background(base)) {
                if (clip.poster.isNullOrBlank()) {
                    cover()
                } else {
                    AsyncImage(model = clip.poster, contentDescription = null, contentScale = ContentScale.Crop, modifier = Modifier.fillMaxSize())
                }
            }
        }
    }
}

// The player's background drawn over the tall loop (of shape `shape`, as
// LoopBackdrop shows it): clear where the loop shows fully, solid where it
// is gone, along fullScreenLoopAlpha, so the loop melts into it with no
// line; drawn FULL_SCREEN_BACKGROUND_GAIN times brighter. With `veil()` at
// 1 (lyrics showing) the background covers the loop altogether. `veil` is
// read only while drawing.
fun Modifier.meltMask(shape: Float, veil: () -> Float): Modifier = this
    .graphicsLayer {
        compositingStrategy = CompositingStrategy.Offscreen
        renderEffect = BrighterEffect
    }
    .drawWithContent {
        drawContent()
        val end = fullScreenMeltEnd(shape, size.width / size.height)
        val shown = veil().coerceIn(0f, 1f)
        val stops = buildList {
            add(0f to shown)
            for (i in 0..16) {
                val at = FULL_SCREEN_MELT_FROM + (end - FULL_SCREEN_MELT_FROM) * i / 16f
                val solid = 1f - fullScreenLoopAlpha(at, end)
                add(at to solid + (1f - solid) * shown)
            }
            add(1f to 1f)
        }
        drawRect(Brush.verticalGradient(*stops.map { (y, a) -> y to Color.Black.copy(alpha = a) }.toTypedArray()), blendMode = BlendMode.DstIn)
    }

// The background's colors scaled up by FULL_SCREEN_BACKGROUND_GAIN (on
// Android 12 and newer; older phones draw it as it is).
private val BrighterEffect: RenderEffect? =
    if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
        val gain = FULL_SCREEN_BACKGROUND_GAIN
        android.graphics.RenderEffect.createColorFilterEffect(
            android.graphics.ColorMatrixColorFilter(android.graphics.ColorMatrix().apply { setScale(gain, gain, gain, 1f) }),
        ).asComposeRenderEffect()
    } else {
        null
    }

// Whether a tall loop's top is light, from its poster, so the status icons
// and the album's name go dark over it; kept for the clips seen lately.
object LoopTops {
    private val known = LruCache<String, Boolean>(16)

    suspend fun lightTop(context: Context, clip: AnimatedClip): Boolean {
        val address = clip.poster?.takeIf(String::isNotBlank) ?: return false
        known.get(address)?.let { return it }
        val request = ImageRequest.Builder(context).data(address).allowHardware(false).size(256).build()
        val poster = (SingletonImageLoader.get(context).execute(request) as? SuccessResult)?.image?.toBitmap() ?: return false
        val light = withContext(Dispatchers.Default) { lightTop(poster) }
        known.put(address, light)
        return light
    }

    private fun lightTop(poster: Bitmap): Boolean {
        val band = Bitmap.createScaledBitmap(Bitmap.createBitmap(poster, 0, 0, poster.width, (poster.height * 0.08f).roundToInt().coerceAtLeast(1)), 16, 2, true)
        val pixels = IntArray(32)
        band.getPixels(pixels, 0, 16, 0, 0, 16, 2)
        var r = 0L
        var g = 0L
        var b = 0L
        for (p in pixels) {
            r += p shr 16 and 0xFF
            g += p shr 8 and 0xFF
            b += p and 0xFF
        }
        val mean = 0xFF000000.toInt() or ((r / 32).toInt() shl 16) or ((g / 32).toInt() shl 8) or (b / 32).toInt()
        return contrastRatio(DarkInkArgb, mean) > contrastRatio(0xFFFFFFFF.toInt(), mean)
    }
}
