package app.winters.octo.design

import androidx.compose.animation.core.animateDpAsState
import androidx.compose.animation.core.animateFloatAsState
import androidx.compose.animation.core.spring
import androidx.compose.foundation.gestures.detectHorizontalDragGestures
import androidx.compose.foundation.gestures.detectTapGestures
import androidx.compose.foundation.hoverable
import androidx.compose.foundation.interaction.DragInteraction
import androidx.compose.foundation.interaction.MutableInteractionSource
import androidx.compose.foundation.interaction.collectIsDraggedAsState
import androidx.compose.foundation.interaction.collectIsHoveredAsState
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.height
import androidx.compose.runtime.Composable
import androidx.compose.runtime.DisposableEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableFloatStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberUpdatedState
import androidx.compose.runtime.setValue
import androidx.compose.ui.ExperimentalComposeUiApi
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.drawBehind
import androidx.compose.ui.geometry.CornerRadius
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.geometry.Size
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.StrokeCap
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.ui.graphics.drawscope.drawIntoCanvas
import androidx.compose.ui.graphics.skiaCanvas
import androidx.compose.ui.graphics.toArgb
import androidx.compose.ui.input.pointer.PointerEventType
import androidx.compose.ui.input.pointer.PointerIcon
import androidx.compose.ui.input.pointer.onPointerEvent
import androidx.compose.ui.input.pointer.pointerHoverIcon
import androidx.compose.ui.input.pointer.pointerInput
import androidx.compose.ui.text.drawText
import androidx.compose.ui.text.rememberTextMeasurer
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.compose.animation.core.snap
import kotlin.math.roundToInt
import org.jetbrains.skia.FilterBlurMode
import org.jetbrains.skia.MaskFilter
import org.jetbrains.skia.Paint
import org.jetbrains.skia.PaintMode
import org.jetbrains.skia.PaintStrokeCap

// A line that glows along the part already filled, for song progress and
// volume, as on the phone. The line thickens and a thumb shows under the
// pointer. By default the value is only sent when the drag ends, so
// scrubbing a song does not stutter it; `live` sends it all along, for
// volume. `wheelStep`, when set, lets the mouse wheel move it by that much.
// `onRelease` hears when a change is done (a click, a drag let go, a wheel
// notch). `hoverLabel`, when set, shows what a click would pick, in a small
// pill above the pointer: the time to seek to, for a song. `look` Jewel
// draws it as the settings slider instead, filled with `fill`; `steps` snaps
// it to that many equal steps and marks them, and `valueLabel` puts the
// value in a bubble above the thumb while dragging. `label` names it for
// the keyboard and screen readers, which then move it by `keyStep` with the
// arrow keys, and `reading` says its value in words.
@OptIn(ExperimentalComposeUiApi::class)
@Composable
fun LineSlider(
    fraction: () -> Float,
    onSeek: (Float) -> Unit,
    modifier: Modifier = Modifier,
    live: Boolean = false,
    wheelStep: Float? = null,
    color: Color = Color.White,
    trackColor: Color = Color.White.copy(alpha = 0.22f),
    onRelease: () -> Unit = {},
    hoverLabel: ((Float) -> String)? = null,
    look: SliderLook = SliderLook.Glow,
    fill: Color = OctoColors.Accent,
    steps: Int = 0,
    valueLabel: ((Float) -> String)? = null,
    interactionSource: MutableInteractionSource? = null,
    label: String? = null,
    keyStep: Float = if (steps > 0) 1f / steps else 0.05f,
    reading: ((Float) -> String)? = null,
) {
    var dragging by remember { mutableStateOf(false) }
    var dragFraction by remember { mutableFloatStateOf(0f) }
    // Where the pointer is over the line, from 0 to 1, or below 0 when off it.
    var pointerFraction by remember { mutableFloatStateOf(-1f) }
    val seek by rememberUpdatedState(onSeek)
    val release by rememberUpdatedState(onRelease)
    val current by rememberUpdatedState(fraction)
    val hoverWords by rememberUpdatedState(hoverLabel)
    val interaction = interactionSource ?: remember { MutableInteractionSource() }
    val hovered by interaction.collectIsHoveredAsState()
    // A drag started by someone else on the same interactions (a preview)
    // shows as one too.
    val draggedElsewhere by interaction.collectIsDraggedAsState()
    val held = dragging || draggedElsewhere
    var drag by remember { mutableStateOf<DragInteraction.Start?>(null) }

    val still = motionScale().still
    val thickness by animateDpAsState(if (held || hovered) 5.dp else 3.dp, if (still) snap() else spring(0.6f, 300f), label = "track")
    val thumb = thumbSize(hovered, held)
    val glowAlpha by animateFloatAsState(if (held) 0.7f else 0.35f, if (still) snap() else spring(1f, 200f), label = "glow")
    val glowPaint = remember {
        Paint().apply {
            isAntiAlias = true
            mode = PaintMode.STROKE
            strokeCap = PaintStrokeCap.ROUND
        }
    }
    // The sliders in the settings pages come and go; the paint's own copy of
    // what it draws is kept on the graphics side, so a slider that leaves
    // hands it back there rather than leaving it for the collector.
    DisposableEffect(glowPaint) {
        onDispose { glowPaint.close() }
    }
    val jewel = if (look == SliderLook.Jewel) rememberJewelLook(hovered, held) else null
    val followed = if (look == SliderLook.Jewel) rememberFollowedFraction(fraction, dragging) else null
    val measurer = rememberTextMeasurer()

    Box(
        modifier
            .height(if (look == SliderLook.Jewel) 22.dp else 24.dp)
            .then(
                if (label != null) {
                    Modifier.adjustable(label, fraction, { seek(snapToSteps(it, steps)) }, keyStep, reading ?: { "${(it * 100).roundToInt()}%" }, onDone = { release() }, shape = CircleShape)
                } else {
                    Modifier
                },
            )
            .hoverable(interaction)
            .pointerHoverIcon(PointerIcon.Hand)
            .onPointerEvent(PointerEventType.Move) { event ->
                pointerFraction = (event.changes.first().position.x / size.width).coerceIn(0f, 1f)
            }
            .onPointerEvent(PointerEventType.Exit) { pointerFraction = -1f }
            .then(
                if (wheelStep != null) {
                    Modifier.onPointerEvent(PointerEventType.Scroll) { event ->
                        val delta = event.changes.firstOrNull()?.scrollDelta?.y ?: 0f
                        if (delta != 0f) {
                            seek(snapToSteps(current() - delta * wheelStep, steps))
                            release()
                        }
                    }
                } else {
                    Modifier
                },
            )
            .pointerInput(Unit) {
                detectTapGestures {
                    seek(snapToSteps(it.x / size.width, steps))
                    release()
                }
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
                        release()
                    },
                    onDragCancel = {
                        dragging = false
                        drag?.let { interaction.tryEmit(DragInteraction.Cancel(it)) }
                        release()
                    },
                ) { change, _ ->
                    dragFraction = snapToSteps(change.position.x / size.width, steps)
                    pointerFraction = dragFraction
                    if (live) seek(dragFraction)
                }
            }
            .drawBehind {
                val y = size.height / 2
                if (jewel != null) {
                    val shown = if (dragging) dragFraction else followed?.value ?: current()
                    drawJewelSlider(y, shown, jewel, fill, steps, valueLabel?.invoke(shown), measurer)
                    return@drawBehind
                }
                val stroke = thickness.toPx()
                // Read here, while drawing, so a moving value only redraws.
                val end = size.width * (if (dragging) dragFraction else current().coerceIn(0f, 1f))
                drawLine(trackColor, Offset(0f, y), Offset(size.width, y), stroke, StrokeCap.Round)
                if (end > 0f) {
                    // Soft passes of the same line make the glow: wide and
                    // faint, then a tighter one. Garnish, not a light.
                    drawIntoCanvas { canvas ->
                        for (spread in floatArrayOf(2.5f, 1f)) {
                            glowPaint.color = color.copy(alpha = glowAlpha / 3f).toArgb()
                            glowPaint.strokeWidth = stroke
                            glowPaint.maskFilter = MaskFilter.makeBlur(FilterBlurMode.NORMAL, 4f * spread)
                            canvas.skiaCanvas.drawLine(0f, y, end, y, glowPaint)
                        }
                    }
                    drawLine(color, Offset(0f, y), Offset(end, y), stroke, StrokeCap.Round)
                }
                if (thumb > 0.dp) drawCircle(color, thumb.toPx(), Offset(end, y))
                // What a click here would pick, above the pointer.
                val at = if (dragging) dragFraction else pointerFraction
                val words = hoverWords
                if (words != null && at >= 0f && (hovered || dragging)) {
                    val text = measurer.measure(words(at), OctoType.caption.copy(fontSize = 11.sp, color = Color.White, fontFeatureSettings = "tnum"))
                    val padX = 7.dp.toPx()
                    val padY = 2.dp.toPx()
                    val w = text.size.width + padX * 2
                    val h = text.size.height + padY * 2
                    val left = (size.width * at - w / 2).coerceIn(-w / 2, size.width - w / 2)
                    val top = y - 10.dp.toPx() - h
                    drawRoundRect(Color.Black.copy(alpha = 0.72f), Offset(left, top), Size(w, h), CornerRadius(h / 2))
                    drawText(text, topLeft = Offset(left + padX, top + padY))
                }
            },
    )
}
