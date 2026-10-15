package app.winters.octo.design

import androidx.compose.foundation.IndicationNodeFactory
import androidx.compose.foundation.focusable
import androidx.compose.foundation.interaction.FocusInteraction
import androidx.compose.foundation.interaction.InteractionSource
import androidx.compose.runtime.Composable
import androidx.compose.runtime.Stable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberUpdatedState
import androidx.compose.runtime.setValue
import androidx.compose.runtime.staticCompositionLocalOf
import androidx.compose.runtime.DisposableEffect
import androidx.compose.runtime.derivedStateOf
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.drawWithContent
import androidx.compose.ui.focus.focusProperties
import androidx.compose.ui.focus.onFocusChanged
import androidx.compose.ui.geometry.Size
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.Shape
import androidx.compose.ui.graphics.drawOutline
import androidx.compose.ui.graphics.drawscope.ContentDrawScope
import androidx.compose.ui.graphics.drawscope.DrawScope
import androidx.compose.ui.graphics.drawscope.Stroke
import androidx.compose.ui.graphics.drawscope.translate
import androidx.compose.ui.input.key.Key
import androidx.compose.ui.input.key.KeyEventType
import androidx.compose.ui.input.key.isShiftPressed
import androidx.compose.ui.input.key.key
import androidx.compose.ui.input.key.onKeyEvent
import androidx.compose.ui.input.key.type
import androidx.compose.ui.layout.onGloballyPositioned
import androidx.compose.ui.layout.boundsInWindow
import androidx.compose.ui.node.CompositionLocalConsumerModifierNode
import androidx.compose.ui.node.DelegatableNode
import androidx.compose.ui.node.DrawModifierNode
import androidx.compose.ui.node.currentValueOf
import androidx.compose.ui.node.invalidateDraw
import androidx.compose.ui.Modifier.Node
import androidx.compose.ui.semantics.ProgressBarRangeInfo
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.progressBarRangeInfo
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.semantics.setProgress
import androidx.compose.ui.semantics.stateDescription
import androidx.compose.ui.unit.IntRect
import kotlin.math.roundToInt
import kotlinx.coroutines.launch

// What the keyboard needs from the desktop's controls: a ring round what
// has it, a way to keep some controls out of the Tab order, sliders that
// take the arrow keys, and menus opened from the Menu key.

// The ring's colour: Octo's accent, whole, which reads on the glass, the
// page and the ambience. The hairline inside it keeps it apart from a
// light cover or a white glyph.
val FocusRingColor: Color get() = OctoColors.Accent
val FocusEdgeColor = Color.Black.copy(alpha = 0.55f)

// Whether the keyboard is what the listener is using: set by a key, cleared
// by a click. Rings show only then, so a click never leaves one behind.
// A window starts as if the mouse were in use.
@Stable
class FocusVisibility(keyboard: Boolean = false) {
    var keyboard by mutableStateOf(keyboard)
}

val LocalFocusVisibility = staticCompositionLocalOf { FocusVisibility() }

// False inside something the arrow keys walk through as one stop (a table's
// rows): its own links and buttons are then left out of the Tab order.
val LocalTabStops = staticCompositionLocalOf { true }

// Keeps a control out of the Tab order when it sits inside such a list.
fun Modifier.tabStop(stop: Boolean): Modifier = if (stop) this else focusProperties { canFocus = false }

// How many focused controls want the arrow keys for themselves (a slider),
// so the window's own use of them (seeking, the volume) waits.
@Stable
class ArrowKeys {
    private var held by mutableIntStateOf(0)
    val claimed: Boolean get() = held > 0

    fun hold(on: Boolean) {
        held = (held + if (on) 1 else -1).coerceAtLeast(0)
    }
}

val LocalArrowKeys = staticCompositionLocalOf { ArrowKeys() }

// Draws the ring just inside the edge of `shape`, so nothing clips it.
fun DrawScope.drawFocusRing(shape: Shape) {
    val ring = Focus.Ring.toPx()
    val edge = Focus.Edge.toPx()
    val outer = shape.createOutline(Size(size.width - ring, size.height - ring), layoutDirection, this)
    translate(ring / 2, ring / 2) { drawOutline(outer, FocusRingColor, style = Stroke(ring)) }
    val inset = ring + edge / 2
    if (size.width > inset * 2 && size.height > inset * 2) {
        val inner = shape.createOutline(Size(size.width - inset * 2, size.height - inset * 2), layoutDirection, this)
        translate(inset, inset) { drawOutline(inner, FocusEdgeColor, style = Stroke(edge)) }
    }
}

// The ring as a click's indication: it shows while the control has the
// keyboard, and never under the pointer or a press. The desktop gives it
// to every clickable as the default, so none is left without one.
class FocusRing(private val shape: Shape) : IndicationNodeFactory {
    override fun create(interactionSource: InteractionSource): DelegatableNode = FocusRingNode(interactionSource, shape)

    override fun equals(other: Any?): Boolean = other is FocusRing && other.shape == shape

    override fun hashCode(): Int = shape.hashCode()
}

private class FocusRingNode(private val interactions: InteractionSource, private val shape: Shape) :
    Node(), DrawModifierNode, CompositionLocalConsumerModifierNode {
    private var focused = false

    override fun onAttach() {
        coroutineScope.launch {
            var count = 0
            interactions.interactions.collect { interaction ->
                when (interaction) {
                    is FocusInteraction.Focus -> count++
                    is FocusInteraction.Unfocus -> count--
                    else -> return@collect
                }
                focused = count > 0
                invalidateDraw()
            }
        }
    }

    override fun ContentDrawScope.draw() {
        drawContent()
        if (focused && currentValueOf(LocalFocusVisibility).keyboard) drawFocusRing(shape)
    }
}

// The ring for something focusable that is not a click (a list, a slider):
// put it before the focusable, so it hears the focus below it.
fun Modifier.focusOutline(shape: Shape, visibility: FocusVisibility): Modifier {
    var focused by mutableStateOf(false)
    return onFocusChanged { focused = it.isFocused }
        .drawWithContent {
            drawContent()
            if (focused && visibility.keyboard) drawFocusRing(shape)
        }
}

// The same, reading the window's visibility itself.
@Composable
fun Modifier.focusOutline(shape: Shape): Modifier {
    val visibility = LocalFocusVisibility.current
    return then(remember(shape, visibility) { Modifier.focusOutline(shape, visibility) })
}

// A value along a line, for the keyboard and screen readers: focusable,
// named `label`, reading `value` from 0 to 1 (as `reading` says it), moved
// by `step` with the arrow keys, ten steps with Page Up and Page Down, and
// to either end with Home and End. `onDone` hears when a key's change is
// made, as a drag's end would be. The value is read in whole hundredths,
// so a song's position does not redraw it every frame.
@Composable
fun Modifier.adjustable(
    label: String,
    value: () -> Float,
    onSet: (Float) -> Unit,
    step: Float = 0.05f,
    reading: (Float) -> String = { "${(it * 100).roundToInt()}%" },
    onDone: () -> Unit = {},
    shape: Shape = Corner.ControlShape,
): Modifier {
    val arrows = LocalArrowKeys.current
    var holding by remember { mutableStateOf(false) }
    val read by rememberUpdatedState(value)
    val hundredths by remember { derivedStateOf { (read().coerceIn(0f, 1f) * 100).roundToInt() } }
    val set by rememberUpdatedState(onSet)
    val done by rememberUpdatedState(onDone)
    DisposableEffect(arrows) { onDispose { if (holding) arrows.hold(false) } }
    fun to(target: Float): Boolean {
        set(target.coerceIn(0f, 1f))
        done()
        return true
    }
    val shown = hundredths / 100f
    val words = reading(shown)
    return this
        .semantics {
            contentDescription = label
            stateDescription = words
            progressBarRangeInfo = ProgressBarRangeInfo(shown, 0f..1f)
            setProgress { target -> to(target) }
        }
        .onFocusChanged {
            if (it.isFocused != holding) {
                holding = it.isFocused
                arrows.hold(it.isFocused)
            }
        }
        .onKeyEvent { event ->
            if (event.type != KeyEventType.KeyDown) return@onKeyEvent false
            val now = read()
            when (event.key) {
                Key.DirectionRight, Key.DirectionUp -> to(now + step)
                Key.DirectionLeft, Key.DirectionDown -> to(now - step)
                Key.PageUp -> to(now + step * 10)
                Key.PageDown -> to(now - step * 10)
                Key.MoveHome -> to(0f)
                Key.MoveEnd -> to(1f)
                else -> false
            }
        }
        .focusOutline(shape)
        .focusable()
}

// Opens a menu from the keyboard: the Menu key, or Shift+F10, while the
// control (or something in it) has the keyboard. `open` gets the control's
// bounds in the window, to open the menu under it.
@Composable
fun Modifier.menuKey(open: (IntRect) -> Unit): Modifier {
    var bounds by remember { mutableStateOf(IntRect.Zero) }
    val action by rememberUpdatedState(open)
    return this
        .onGloballyPositioned { spot ->
            val r = spot.boundsInWindow()
            bounds = IntRect(r.left.roundToInt(), r.top.roundToInt(), r.right.roundToInt(), r.bottom.roundToInt())
        }
        .onKeyEvent { event ->
            val asks = event.type == KeyEventType.KeyDown && (event.key == Key.Menu || (event.key == Key.F10 && event.isShiftPressed))
            if (asks) action(bounds)
            asks
        }
}
