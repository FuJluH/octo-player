package app.winters.octo.animated

import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.runtime.Composable
import androidx.compose.runtime.remember
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.drawBehind
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.layout.ContentScale
import androidx.compose.ui.unit.dp
import app.winters.octo.subsonic.AnimatedClip
import coil3.compose.AsyncImage

// The tall loop filling the player behind everything, scaled to cover the
// screen, its poster first. Draws nothing over it: see BackdropFade.
@Composable
fun LoopBackdrop(clip: AnimatedClip, play: LoopPlay, fill: Color, cover: @Composable () -> Unit, modifier: Modifier = Modifier) {
    LoopVideo(clip, play, modifier.fillMaxSize()) {
        Box(Modifier.fillMaxSize().background(fill)) {
            if (clip.poster.isNullOrBlank()) {
                cover()
            } else {
                AsyncImage(model = clip.poster, contentDescription = null, contentScale = ContentScale.Crop, modifier = Modifier.fillMaxSize())
            }
        }
    }
}

// How far above the song's name the loop starts fading into its color.
private val FadeReach = 180.dp

// How far the color reaches down from the top, behind the album's name and
// the phone's status icons.
private val TopReach = 160.dp

// The color the tall loop fades into, so the words over it read: from
// clear above the song's name (`wordsTop()`, in pixels from the top) to
// `ink.scrim` where the words begin and fully solid at the foot, and a
// lighter band at the top behind the album's name and the status icons.
// With `veil()` at 1 (lyrics showing) the color lies over all of it at the
// scrim, so lines anywhere read. Both are read only while drawing.
@Composable
fun BackdropFade(ink: BackdropInk, wordsTop: () -> Float, veil: () -> Float, modifier: Modifier = Modifier) {
    val color = remember(ink.color) { Color(ink.color) }
    Box(
        modifier.fillMaxSize().drawBehind {
            val reach = FadeReach.toPx()
            val top = wordsTop().takeIf { it > 0f } ?: (size.height * 0.5f)
            val start = (top - reach).coerceAtLeast(0f)
            val middle = (start + reach * 0.5f).coerceAtMost(top)
            val foot = (top + (size.height - top) * 0.55f).coerceAtMost(size.height)
            drawRect(
                Brush.verticalGradient(
                    0f to Color.Transparent,
                    (start / size.height) to Color.Transparent,
                    // An eased ramp, so no line shows where the fade begins.
                    (middle / size.height) to color.copy(alpha = ink.scrim * 0.45f),
                    (top / size.height) to color.copy(alpha = ink.scrim),
                    (foot / size.height) to color.copy(alpha = maxOf(ink.scrim, 0.92f)),
                    1f to color,
                ),
            )
            val topReach = TopReach.toPx()
            drawRect(
                Brush.verticalGradient(
                    // As solid as the words need through the album's name,
                    // then easing out.
                    0f to color.copy(alpha = ink.scrim),
                    0.5f to color.copy(alpha = ink.scrim),
                    0.75f to color.copy(alpha = ink.scrim * 0.4f),
                    1f to Color.Transparent,
                    startY = 0f,
                    endY = topReach,
                ),
                size = size.copy(height = topReach),
                topLeft = Offset.Zero,
            )
            val lyrics = veil()
            if (lyrics > 0f) drawRect(color.copy(alpha = ink.scrim * lyrics))
        },
    )
}
