package app.winters.octo.ui.sound

import android.graphics.BlurMaskFilter
import androidx.compose.animation.core.animateDpAsState
import androidx.compose.animation.core.animateFloatAsState
import androidx.compose.animation.core.spring
import androidx.compose.foundation.ExperimentalFoundationApi
import androidx.compose.foundation.background
import androidx.compose.foundation.combinedClickable
import androidx.compose.foundation.gestures.detectHorizontalDragGestures
import androidx.compose.foundation.gestures.detectTapGestures
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxHeight
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.lazy.LazyRow
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.lazy.rememberLazyListState
import androidx.compose.foundation.selection.selectableGroup
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableFloatStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberUpdatedState
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.alpha
import androidx.compose.ui.draw.clip
import androidx.compose.ui.draw.drawBehind
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.StrokeCap
import androidx.compose.ui.graphics.drawscope.drawIntoCanvas
import androidx.compose.ui.graphics.nativeCanvas
import androidx.compose.ui.graphics.toArgb
import androidx.compose.ui.hapticfeedback.HapticFeedbackType
import androidx.compose.ui.input.pointer.pointerInput
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.platform.LocalHapticFeedback
import androidx.compose.ui.semantics.CustomAccessibilityAction
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.customActions
import androidx.compose.ui.semantics.role
import androidx.compose.ui.semantics.selected
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.semantics.stateDescription
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import app.winters.octo.design.Glaze
import app.winters.octo.design.GlazeLight
import app.winters.octo.design.GlazeSelected
import app.winters.octo.design.LineSlider
import app.winters.octo.design.OctoColors
import app.winters.octo.design.OctoType
import kotlin.math.abs
import kotlin.math.roundToInt

// A thin line between the parts of a card.
@Composable
internal fun Hairline(modifier: Modifier = Modifier) {
    val onePixel = with(LocalDensity.current) { 1.toDp() }
    Box(modifier.fillMaxWidth().height(onePixel).background(OctoColors.TextPrimary.copy(alpha = 0.08f)))
}

// One preset in the row, and whether it is the listener's own.
internal data class PresetChoice(val name: String, val own: Boolean)

// The presets in one glaze that scrolls sideways. The chosen one sits in
// the darker pill; the rest are plain names. A long press on one of the
// listener's own asks to delete it.
@OptIn(ExperimentalFoundationApi::class)
@Composable
internal fun PresetBar(
    choices: List<PresetChoice>,
    selected: String,
    onPick: (PresetChoice) -> Unit,
    onLongPress: (PresetChoice) -> Unit,
    modifier: Modifier = Modifier,
) {
    // Opens with the chosen preset in view.
    val start = choices.indexOfFirst { it.name == selected }.coerceAtLeast(0)
    val list = rememberLazyListState(initialFirstVisibleItemIndex = (start - 1).coerceAtLeast(0))
    Glaze(modifier.fillMaxWidth().height(44.dp)) {
        LazyRow(
            state = list,
            contentPadding = PaddingValues(horizontal = 4.dp),
            modifier = Modifier
                .fillMaxSize()
                .clip(CircleShape)
                .selectableGroup(),
            verticalAlignment = Alignment.CenterVertically,
        ) {
            items(choices, key = { (if (it.own) "own:" else "built:") + it.name }) { choice ->
                val chosen = choice.name == selected
                Box(
                    Modifier
                        .fillMaxHeight()
                        .padding(vertical = 4.dp)
                        .combinedClickable(
                            interactionSource = null,
                            indication = null,
                            role = Role.Button,
                            onLongClickLabel = if (choice.own) "Delete" else null,
                            onLongClick = if (choice.own) ({ onLongPress(choice) }) else null,
                        ) { onPick(choice) }
                        .semantics { this.selected = chosen },
                    contentAlignment = Alignment.Center,
                ) {
                    if (chosen) GlazeSelected(Modifier.matchParentSize())
                    Text(
                        choice.name,
                        style = OctoType.label,
                        color = if (chosen) OctoColors.Accent else OctoColors.TextPrimary,
                        maxLines = 1,
                        modifier = Modifier.padding(horizontal = 14.dp),
                    )
                }
            }
        }
    }
}

// A button that works only while it is held down, lifting under the finger.
@Composable
internal fun HoldButton(text: String, enabled: Boolean, onHold: (Boolean) -> Unit, modifier: Modifier = Modifier) {
    var held by remember { mutableStateOf(false) }
    val hold by rememberUpdatedState(onHold)
    val usable by rememberUpdatedState(enabled)
    Glaze(
        modifier
            .height(48.dp)
            .alpha(if (enabled || held) 1f else 0.6f)
            // Keyed on nothing, so a press is not cut short when holding it
            // changes what the button is showing.
            .pointerInput(Unit) {
                detectTapGestures(
                    onPress = {
                        if (!usable) return@detectTapGestures
                        held = true
                        hold(true)
                        try {
                            tryAwaitRelease()
                        } finally {
                            held = false
                            hold(false)
                        }
                    },
                )
            }
            .semantics {
                role = Role.Button
                contentDescription = text
            },
        light = if (held) GlazeLight.Lifted else GlazeLight.Rest,
    ) {
        Text(text, style = OctoType.label, color = OctoColors.TextPrimary, modifier = Modifier.padding(horizontal = 24.dp))
    }
}

// A labelled value on the white line slider, with its reading beside it.
// The value moves in `step`s and is sent all along the drag.
@Composable
internal fun ValueSlider(
    label: String,
    value: Float,
    range: ClosedFloatingPointRange<Float>,
    reading: String,
    onChange: (Float) -> Unit,
    modifier: Modifier = Modifier,
    step: Float = 0.5f,
    enabled: Boolean = true,
    // Maps a value to its place on the line and back, for scales that are
    // not even, like frequency.
    toFraction: (Float) -> Float = { (it - range.start) / (range.endInclusive - range.start) },
    fromFraction: (Float) -> Float = { range.start + it * (range.endInclusive - range.start) },
) {
    val current by rememberUpdatedState(value)
    val change by rememberUpdatedState(onChange)
    Row(modifier.fillMaxWidth().alpha(if (enabled) 1f else 0.5f), verticalAlignment = Alignment.CenterVertically) {
        Text(label, style = OctoType.bodySmall, color = OctoColors.TextSecondary, modifier = Modifier.width(76.dp))
        LineSlider(
            fraction = { toFraction(current).coerceIn(0f, 1f) },
            onSeek = { fraction ->
                if (!enabled) return@LineSlider
                val picked = (fromFraction(fraction) / step).roundToInt() * step
                val clean = picked.coerceIn(range.start, range.endInclusive)
                if (clean != current) change(clean)
            },
            live = true,
            modifier = Modifier
                .weight(1f)
                .semantics {
                    contentDescription = label
                    stateDescription = reading
                    customActions = listOf(
                        CustomAccessibilityAction("More") { change((current + step).coerceAtMost(range.endInclusive)); true },
                        CustomAccessibilityAction("Less") { change((current - step).coerceAtLeast(range.start)); true },
                    )
                },
        )
        Text(
            reading,
            style = OctoType.bodySmall.copy(fontFeatureSettings = "tnum"),
            color = OctoColors.TextPrimary,
            maxLines = 1,
            modifier = Modifier.padding(start = 12.dp).width(64.dp),
        )
    }
}

// How close to the middle the balance snaps to centre.
private const val CentreDetent = 0.05f

// Left and right balance: a line that glows from the centre out to the
// chosen side, with a small mark at the centre it snaps back to.
@Composable
internal fun BalanceSlider(value: Float, onChange: (Float) -> Unit, modifier: Modifier = Modifier) {
    val haptics = LocalHapticFeedback.current
    val current by rememberUpdatedState(value)
    val change by rememberUpdatedState(onChange)
    var dragging by remember { mutableStateOf(false) }
    var dragValue by remember { mutableFloatStateOf(0f) }
    val thickness by animateDpAsState(if (dragging) 8.dp else 3.5.dp, spring(0.5f, 200f), label = "balance track")
    val thumb by animateDpAsState(if (dragging) 9.dp else 4.dp, spring(0.5f, 200f), label = "balance thumb")
    val glowAlpha by animateFloatAsState(if (dragging) 0.8f else 0.4f, spring(1f, 200f), label = "balance glow")
    val glowPaint = remember { android.graphics.Paint(android.graphics.Paint.ANTI_ALIAS_FLAG).apply { strokeCap = android.graphics.Paint.Cap.ROUND } }

    // A position on the line as a balance, snapping to the centre, with a
    // tick as it lands there.
    fun pick(x: Float, width: Float): Float {
        val raw = ((x / width) * 2f - 1f).coerceIn(-1f, 1f)
        val snapped = if (abs(raw) < CentreDetent) 0f else (raw * 20f).roundToInt() / 20f
        if (snapped == 0f && dragValue != 0f) haptics.performHapticFeedback(HapticFeedbackType.SegmentTick)
        return snapped
    }

    Row(modifier.fillMaxWidth(), verticalAlignment = Alignment.CenterVertically) {
        Text("L", style = OctoType.caption, color = OctoColors.TextMuted)
        Box(
            Modifier
                .weight(1f)
                .padding(horizontal = 12.dp)
                .height(48.dp)
                .semantics {
                    contentDescription = "Balance"
                    stateDescription = readBalance(current)
                    customActions = listOf(
                        CustomAccessibilityAction("More to the left") { change((current - 0.1f).coerceAtLeast(-1f)); true },
                        CustomAccessibilityAction("More to the right") { change((current + 0.1f).coerceAtMost(1f)); true },
                        CustomAccessibilityAction("Center") { change(0f); true },
                    )
                }
                .pointerInput(Unit) {
                    detectTapGestures(onDoubleTap = { change(0f) })
                }
                .pointerInput(Unit) {
                    detectHorizontalDragGestures(
                        onDragStart = {
                            dragging = true
                            dragValue = current
                        },
                        onDragEnd = { dragging = false },
                        onDragCancel = { dragging = false },
                    ) { input, _ ->
                        dragValue = pick(input.position.x, size.width.toFloat())
                        change(dragValue)
                    }
                }
                .drawBehind {
                    val y = size.height / 2
                    val stroke = thickness.toPx()
                    val centre = size.width / 2
                    val end = centre + (if (dragging) dragValue else current) * centre
                    drawLine(Color.White.copy(alpha = 0.24f), Offset(0f, y), Offset(size.width, y), stroke, StrokeCap.Round)
                    if (end != centre) {
                        drawIntoCanvas { canvas ->
                            for (spread in floatArrayOf(2.5f, 1f, 0.3f)) {
                                glowPaint.color = Color.White.copy(alpha = glowAlpha / 3f).toArgb()
                                glowPaint.strokeWidth = stroke
                                glowPaint.maskFilter = BlurMaskFilter(12f * spread, BlurMaskFilter.Blur.NORMAL)
                                canvas.nativeCanvas.drawLine(centre, y, end, y, glowPaint)
                            }
                        }
                        drawLine(Color.White, Offset(centre, y), Offset(end, y), stroke, StrokeCap.Round)
                    }
                    // The centre mark.
                    drawLine(Color.White.copy(alpha = 0.5f), Offset(centre, y - 7.dp.toPx()), Offset(centre, y + 7.dp.toPx()), 1.dp.toPx())
                    drawCircle(Color.White, thumb.toPx(), Offset(end, y))
                },
        )
        Text("R", style = OctoType.caption, color = OctoColors.TextMuted)
    }
}

// A balance in words: Centre, 30% left, 100% right.
internal fun readBalance(value: Float): String {
    val percent = (abs(value) * 100).roundToInt()
    return when {
        percent == 0 -> "Center"
        value < 0 -> "$percent% left"
        else -> "$percent% right"
    }
}
