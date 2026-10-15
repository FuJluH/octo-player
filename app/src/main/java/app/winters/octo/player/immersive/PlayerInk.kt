package app.winters.octo.player.immersive

import androidx.compose.animation.AnimatedVisibilityScope
import androidx.compose.animation.EnterExitState
import androidx.compose.animation.core.Animatable
import androidx.compose.animation.core.CubicBezierEasing
import androidx.compose.animation.core.tween
import androidx.compose.material3.LocalContentColor
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.ReadOnlyComposable
import androidx.compose.runtime.State
import androidx.compose.runtime.remember
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.luminance
import app.winters.octo.design.OctoColors

// The player's words and icons take the content colour its background
// asks for (PlayerColors.content), handed down as the content colour.
// Over the usual dark background these give the app's own colours; over a
// light one, shades of the dark ink.

// Whether the words are dark, over a light background.
val Color.isDarkInk: Boolean get() = luminance() < 0.5f

// Secondary words: times, the album's name.
val mutedInk: Color
    @Composable @ReadOnlyComposable
    get() = LocalContentColor.current.let { if (it.isDarkInk) it.copy(alpha = 0.6f) else OctoColors.TextMuted }

// The artist's name under the title.
val accentInk: Color
    @Composable @ReadOnlyComposable
    get() = LocalContentColor.current.let { if (it.isDarkInk) it.copy(alpha = 0.75f) else OctoColors.Accent }

// The way in and out: the background dollies in over 0.8 s after 0.02 s,
// quick then settling, and out over 0.5 s, slow then quick. 1 is fully in.
// It follows the player opening and closing without being part of that
// animation, so it never holds a closed player on screen longer.
private val DollyIn = CubicBezierEasing(0.22f, 1f, 0.36f, 1f)
private val DollyOut = CubicBezierEasing(0.64f, 0f, 0.78f, 0f)

@Composable
fun AnimatedVisibilityScope.backgroundDolly(): State<Float> {
    val dolly = remember { Animatable(0f) }
    val target = transition.targetState
    LaunchedEffect(target) {
        if (target == EnterExitState.Visible) {
            dolly.animateTo(1f, tween(800, delayMillis = 20, easing = DollyIn))
        } else {
            dolly.animateTo(0f, tween(500, easing = DollyOut))
        }
    }
    return dolly.asState()
}
