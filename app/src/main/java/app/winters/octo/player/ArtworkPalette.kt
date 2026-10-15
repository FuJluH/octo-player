package app.winters.octo.player

import android.content.Context
import android.util.LruCache
import androidx.compose.ui.graphics.Color
import androidx.core.graphics.ColorUtils
import androidx.palette.graphics.Palette
import app.winters.octo.playback.artworkBitmap
import dagger.hilt.android.qualifiers.ApplicationContext
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import javax.inject.Inject
import javax.inject.Singleton

// The colours the player paints behind a song: four for the moving
// background, a base that sits under everything, the artwork's main colour
// as it came, and the colour for the player's words and icons over the
// background (white, or dark over a light one).
data class PlayerColors(
    val mesh: List<Color>,
    val base: Color,
    val dominant: Color? = null,
    val content: Color = Color.White,
    // How much of the background shows over `base` so the words in
    // `content` read on every part of it: 1 for all of it.
    val show: Float = 1f,
    // How strongly the icons beside the song's name show in `content`, a
    // step quieter than the words while they still read.
    val quiet: Float = 0.7f,
) {
    companion object {
        // Before artwork loads, or for music without any: quiet shades of the
        // app's own accent, so the player never flashes a stranger's colours.
        val Quiet = PlayerColors(
            mesh = listOf(Color(0xFF2A3438), Color(0xFF1A1A1B), Color(0xFF3A4A50), Color(0xFF0A0B0F)),
            base = Color(0xFF0C0C0D),
        )
    }
}

// Picks colours out of a song's artwork. Each colour has a chain of
// fallbacks because small or dull artwork often lacks the ideal swatch.
@Singleton
class ArtworkPalette @Inject constructor(@ApplicationContext private val context: Context) {
    private val cache = LruCache<String, PlayerColors>(32)

    suspend fun colorsFor(ref: String?): PlayerColors {
        if (ref == null) return PlayerColors.Quiet
        cache.get(ref)?.let { return it }
        // Off the main thread, since a server's cover may need downloading.
        val colors = withContext(Dispatchers.IO) { extract(ref) } ?: return PlayerColors.Quiet
        cache.put(ref, colors)
        return colors
    }

    private fun extract(ref: String): PlayerColors? {
        // A small picture is plenty to find its main colours, and fast.
        val bitmap = artworkBitmap(context, ref, 128) ?: return null
        val palette = Palette.from(bitmap).maximumColorCount(16).generate()

        val main = palette.dominantSwatch?.rgb ?: palette.darkMutedSwatch?.rgb ?: return null
        val bright = palette.vibrantSwatch?.rgb ?: palette.lightVibrantSwatch?.rgb ?: shift(main, 0.16f)
        val deep = palette.darkVibrantSwatch?.rgb ?: palette.darkMutedSwatch?.rgb ?: shift(main, -0.18f)
        val base = ColorUtils.blendARGB(palette.darkMutedSwatch?.rgb ?: main, android.graphics.Color.BLACK, 0.7f)

        return PlayerColors(
            mesh = listOf(Color(main), Color(bright), Color(deep), Color(0xFF0A0B0F)),
            base = Color(base),
            dominant = palette.dominantSwatch?.rgb?.let { Color(it) },
        )
    }

    // The same hue, lighter or darker.
    private fun shift(rgb: Int, lightness: Float): Int {
        val hsl = FloatArray(3)
        ColorUtils.colorToHSL(rgb, hsl)
        hsl[2] = (hsl[2] + lightness).coerceIn(0f, 1f)
        return ColorUtils.HSLToColor(hsl)
    }
}
