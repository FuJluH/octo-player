package app.winters.octo.design

import androidx.compose.foundation.clickable
import androidx.compose.foundation.hoverable
import androidx.compose.foundation.interaction.MutableInteractionSource
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.runtime.Composable
import androidx.compose.runtime.remember
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.alpha
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.painter.Painter
import androidx.compose.ui.input.pointer.PointerIcon
import androidx.compose.ui.input.pointer.pointerHoverIcon
import androidx.compose.ui.semantics.Role

// The accent mixed into black, so white text stays readable on it.
val AccentFill: Color get() = mix(OctoColors.Accent, Color.Black, 0.45f)

// The one filled button on a surface. Its words are black or white,
// whichever reads on `fill`; pass `OctoColors.AccentTonal` for the quieter
// tonal button. Pressed it shrinks and darkens, under the pointer it rises
// and lightens, and the keyboard's focus rings it in the accent.
@Composable
fun AccentButton(
    text: String,
    onClick: () -> Unit,
    modifier: Modifier = Modifier,
    enabled: Boolean = true,
    loading: Boolean = false,
    size: ButtonSize = ButtonSize.Large,
    fill: Color = AccentFill,
    icon: Painter? = null,
    dense: Boolean = false,
    interactionSource: MutableInteractionSource? = null,
) {
    val interaction = interactionSource ?: remember { MutableInteractionSource() }
    val look = rememberButtonLook(interaction)
    GlazeInset(
        fill = fill,
        shape = CircleShape,
        modifier = modifier
            .height(if (dense) size.dense else size.height)
            .buttonMotion(look, CircleShape)
            .alpha(if (enabled) 1f else OctoInk.DisabledAlpha)
            .hoverable(interaction, enabled = enabled && !loading)
            .pointerHoverIcon(if (enabled && !loading) PointerIcon.Hand else PointerIcon.Default)
            .clickable(
                interactionSource = interaction,
                indication = null,
                enabled = enabled && !loading,
                role = Role.Button,
                onClick = onClick,
            ),
    ) {
        ButtonShades(look, CircleShape)
        ButtonLabel(text, contentColorFor(fill), size, icon = icon, loading = loading)
    }
}
