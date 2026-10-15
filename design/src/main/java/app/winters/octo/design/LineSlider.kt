package app.winters.octo.design

import android.graphics.BlurMaskFilter
import androidx.compose.animation.core.animateDpAsState
import androidx.compose.animation.core.animateFloatAsState
import androidx.compose.animation.core.spring
import androidx.compose.foundation.gestures.detectHorizontalDragGestures
import androidx.compose.foundation.gestures.detectTapGestures
import androidx.compose.foundation.interaction.DragInteraction
import androidx.compose.foundation.interaction.MutableInteractionSource
import androidx.compose.foundation.interaction.collectIsDraggedAsState
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableFloatStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberUpdatedState
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.drawBehind
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.StrokeCap
import androidx.compose.ui.graphics.drawscope.drawIntoCanvas
import androidx.compose.ui.graphics.nativeCanvas
import androidx.compose.ui.graphics.toArgb
import androidx.compose.ui.graphics.graphicsLayer
import androidx.compose.ui.input.pointer.pointerInput
import androidx.compose.ui.text.rememberTextMeasurer
import androidx.compose.ui.unit.dp

// A line that glows along the part already filled, for song progress and
// volume. The line thickens and a thumb appears while it is dragged. By
// default the value is only sent when the finger lifts, so scrubbing a song
// does not stutter the audio; `live` sends it all along, for volume.
// `look` Jewel draws it as the settings slider instead, filled with
// `fill`; `steps` snaps it to that many equal steps and marks them, and
// `valueLabel` puts the value in a bubble above the thumb while dragging.
@Composable
fun LineSlider(
    fraction: () -> Float,
    onSeek: (Float) -> Unit,
    modifier: Modifier = Modifier,
    live: Boolean = false,
    color: Color = Color.White,
    trackColor: Color = Color.White.copy(alpha = 0.24f),
    look: SliderLook = SliderLook.Glow,
    fill: Color = OctoColors.Accent,
    steps: Int = 0,
    valueLabel: ((Float) -> String)? = null,
    interactionSource: MutableInteractionSource? = null,
) {
    val interaction = interactionSource ?: remember { MutableInteractionSource() }
    var dragging by remember { mutableStateOf(false) }
    var dragFraction by remember { mutableFloatStateOf(0f) }
    val seek by rememberUpdatedState(onSeek)
    // A drag started by someone else on the same interactions (a preview)
    // shows as one too.
    val draggedElsewhere by interaction.collectIsDraggedAsState()
    val held = dragging || draggedElsewhere
    var drag by remember { mutableStateOf<DragInteraction.Start?>(null) }

    val thickness by animateDpAsState(if (held) 8.dp else 3.5.dp, spring(0.5f, 200f), label = "track")
    val thumb by animateDpAsState(if (held) 9.dp else 0.dp, spring(0.5f, 200f), label = "thumb")
    val glowBlur by animateFloatAsState(if (held) 24f else 12f, spring(1f, 200f), label = "glow blur")
    val glowAlpha by animateFloatAsState(if (held) 0.8f else 0.4f, spring(1f, 200f), label = "glow")

    val jewel = if (look == SliderLook.Jewel) rememberJewelLook(hovered = false, dragging = held) else null
    val followed = if (look == SliderLook.Jewel) rememberFollowedFraction(fraction, dragging) else null
    val measurer = if (valueLabel != null) rememberTextMeasurer() else null

    val glowPaint = remember { android.graphics.Paint(android.graphics.Paint.ANTI_ALIAS_FLAG) }
    val glowFilters = remember { GlowFilters() }

    Box(
        modifier
            .fillMaxWidth()
            .height(48.dp)
            .pointerInput(Unit) {
                detectTapGestures { seek(snapToSteps(it.x / size.width, steps)) }
            }
            .pointerInput(Unit) {
                detectHorizontalDragGestures(
                    onDragStart = {
                        dragging = true
                        dragFraction = snapToSteps(it.x / size.width, steps)
                        drag = DragInteraction.Start().also(interaction::tryEmit)
                    },
                    onDragEnd = {
                        seek(dragFraction)
                        dragging = false
                        drag?.let { interaction.tryEmit(DragInteraction.Stop(it)) }
                    },
                    onDragCancel = {
                        dragging = false
                        drag?.let { interaction.tryEmit(DragInteraction.Cancel(it)) }
                    },
                ) { change, _ ->
                    dragFraction = snapToSteps(change.position.x / size.width, steps)
                    if (live) seek(dragFraction)
                }
            }
            // Its own layer, so a moving value redraws the line and nothing
            // around it.
            .graphicsLayer()
            .drawBehind {
                val y = size.height / 2
                if (jewel != null) {
                    val shown = if (dragging) dragFraction else followed?.value ?: fraction()
                    drawJewelSlider(y, shown, jewel, fill, steps, valueLabel?.invoke(shown), measurer)
                    return@drawBehind
                }
                val stroke = thickness.toPx()
                // Read here, in drawing, so a moving value only redraws.
                val end = size.width * (if (dragging) dragFraction else fraction().coerceIn(0f, 1f))
                drawLine(trackColor, Offset(0f, y), Offset(size.width, y), stroke, StrokeCap.Round)
                if (end > 0f) {
                    // Three soft passes of the same line make the glow: wide and
                    // faint, then medium, then a tight bright core. Each is the
                    // line's own shape, a rounded bar, which the GPU blurs
                    // itself; a blurred line is blurred on the processor.
                    drawIntoCanvas { canvas ->
                        val half = stroke / 2
                        glows.forEachIndexed { i, spread ->
                            glowPaint.color = color.copy(alpha = glowAlpha / 3f).toArgb()
                            glowPaint.maskFilter = glowFilters.of(i, glowBlur * spread)
                            canvas.nativeCanvas.drawRoundRect(-half, y - half, end + half, y + half, half, half, glowPaint)
                        }
                    }
                    drawLine(color, Offset(0f, y), Offset(end, y), stroke, StrokeCap.Round)
                }
                if (thumb > 0.dp) drawCircle(color, thumb.toPx(), Offset(end, y))
            },
    )
}

// How wide each of the glow's three passes spreads, as a share of its blur.
private val glows = floatArrayOf(2.5f, 1f, 0.3f)

// The glow's three blurs, made again only when their size changes.
private class GlowFilters {
    private val sizes = FloatArray(glows.size) { -1f }
    private val filters = arrayOfNulls<BlurMaskFilter>(glows.size)

    fun of(pass: Int, radius: Float): BlurMaskFilter {
        val kept = filters[pass]
        if (kept != null && sizes[pass] == radius) return kept
        return BlurMaskFilter(radius, BlurMaskFilter.Blur.NORMAL).also {
            filters[pass] = it
            sizes[pass] = radius
        }
    }
}
