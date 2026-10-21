package app.winters.octo.desktop.window

import androidx.compose.ui.focus.focusProperties
import androidx.compose.ui.semantics.Role
import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.gestures.awaitEachGesture
import androidx.compose.foundation.gestures.awaitFirstDown
import androidx.compose.foundation.hoverable
import androidx.compose.foundation.interaction.MutableInteractionSource
import androidx.compose.foundation.interaction.collectIsHoveredAsState
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.BoxScope
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.RowScope
import androidx.compose.foundation.layout.fillMaxHeight
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.runtime.Composable
import androidx.compose.runtime.Stable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.input.pointer.PointerIcon
import androidx.compose.ui.input.pointer.pointerHoverIcon
import androidx.compose.ui.input.pointer.pointerInput
import androidx.compose.ui.input.pointer.positionChange
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.dp
import androidx.compose.ui.window.WindowPlacement
import androidx.compose.ui.window.WindowState
import app.winters.octo.design.Glyph
import app.winters.octo.design.OctoColors
import app.winters.octo.design.OctoIcons
import app.winters.octo.design.TooltipPopup
import app.winters.octo.design.TooltipSide
import app.winters.octo.design.rememberTooltipState
import app.winters.octo.design.tooltipTarget
import app.winters.octo.desktop.settings.WindowSpot
import java.awt.Cursor
import java.awt.Dimension
import java.awt.EventQueue
import java.awt.GraphicsEnvironment
import java.awt.MouseInfo
import java.awt.Rectangle
import java.awt.Toolkit
import java.awt.Window
import java.awt.event.ComponentAdapter
import java.awt.event.ComponentEvent
import java.awt.event.WindowAdapter
import java.awt.event.WindowEvent

val TitleBarHeight = 40.dp

// Room left of the title bar's controls for the macOS traffic lights.
val MacLightsRoom = 76.dp

// The window drawn by the app, for Windows and Linux: its own title bar,
// dragging, edges to resize by, and a maximize of its own. A window
// without the system's frame covers the taskbar when the system maximizes
// it, so here it fills the screen's usable part instead.
@Stable
class Frame(private val window: Window, private val state: WindowState) {
    var maximized by mutableStateOf(false)
        private set

    // Where the window was before it filled the screen, and the screen area
    // it fills.
    private var restoreTo: Rectangle? = null
    private var filled: Rectangle? = null

    init {
        // A filled window follows its screen: moved to another one by the
        // system, a screen unplugged, or the resolution or taskbar changed.
        window.addComponentListener(object : ComponentAdapter() {
            override fun componentMoved(e: ComponentEvent?) = refitLater()

            override fun componentResized(e: ComponentEvent?) = refitLater()
        })
        window.addWindowListener(object : WindowAdapter() {
            override fun windowActivated(e: WindowEvent?) = refitLater()
        })
        window.addPropertyChangeListener("graphicsConfiguration") { refitLater() }
    }

    fun toggleMaximized() = if (maximized) restore() else maximize()

    fun maximize() {
        if (maximized) return
        restoreTo = window.bounds
        fill(usableArea())
        maximized = true
    }

    private fun fill(area: Rectangle) {
        filled = area
        window.bounds = area
    }

    // Back to the size and place it had, or onto the screen it is on now
    // when most of that place is on no screen any more.
    fun restore() {
        if (!maximized) return
        restoreTo?.let { before ->
            val min = window.minimumSize
            val spot = restoreSpot(before.toSpot(), screenAreas(), usableArea().toArea(), min.width.toFloat(), min.height.toFloat())
            window.bounds = Rectangle(spot.x.toInt(), spot.y.toInt(), spot.width.toInt(), spot.height.toInt())
        }
        maximized = false
    }

    // Fills the screen again only when its usable area changed, so bounds
    // the system rounds a little never set it off again and again.
    private fun refitLater() {
        if (!maximized) return
        EventQueue.invokeLater {
            if (!maximized) return@invokeLater
            val area = usableArea()
            if (area != filled) fill(area)
        }
    }

    fun minimize() {
        state.isMinimized = true
    }

    // The bounds to keep when the window closes: the size it returns to.
    fun lastFloatingBounds(): Rectangle = if (maximized) restoreTo ?: window.bounds else window.bounds

    // The screen the window is mostly on, less the taskbar or panels.
    private fun usableArea(): Rectangle {
        val config = window.graphicsConfiguration ?: GraphicsEnvironment.getLocalGraphicsEnvironment().defaultScreenDevice.defaultConfiguration
        val bounds = config.bounds
        val insets = Toolkit.getDefaultToolkit().getScreenInsets(config)
        return Rectangle(bounds.x + insets.left, bounds.y + insets.top, bounds.width - insets.left - insets.right, bounds.height - insets.top - insets.bottom)
    }

    // Moves the window with the pointer, from where a drag started. A drag
    // on a filled window first brings it back to its size under the pointer.
    fun dragBy(startPointer: java.awt.Point, startWindow: java.awt.Point) {
        val now = MouseInfo.getPointerInfo()?.location ?: return
        window.setLocation(startWindow.x + now.x - startPointer.x, startWindow.y + now.y - startPointer.y)
    }

    fun startDrag(): Pair<java.awt.Point, java.awt.Point>? {
        val pointer = MouseInfo.getPointerInfo()?.location ?: return null
        if (maximized) {
            val wide = window.width
            val back = restoreTo ?: Rectangle(window.x, window.y, 1280, 800)
            maximized = false
            // Keep the pointer at the same share across the title bar.
            val share = (pointer.x - window.x).toDouble() / wide
            window.bounds = Rectangle((pointer.x - back.width * share).toInt(), window.y, back.width, back.height)
        }
        return pointer to window.location
    }

    // Resizes from an edge or corner while dragged: `dx`/`dy` say which
    // sides move (-1 the left or top, 1 the right or bottom). The size stays
    // between the window's least and most.
    fun resize(from: Rectangle, startPointer: java.awt.Point, dx: Int, dy: Int) {
        val now = MouseInfo.getPointerInfo()?.location ?: return
        window.bounds = resizedBounds(from, now.x - startPointer.x, now.y - startPointer.y, dx, dy, window.minimumSize, window.maximumSize)
    }

    val bounds: Rectangle get() = window.bounds

    // Whether the system says it is maximized, for a window with the system frame.
    val systemMaximized: Boolean get() = state.placement == WindowPlacement.Maximized
}

// A window's bounds once an edge or corner has moved by `mx`/`my`: `dx`/`dy`
// say which sides move (-1 the left or top, 1 the right or bottom). The
// size stays between `min` and `max`, and the side not dragged stays put.
fun resizedBounds(from: Rectangle, mx: Int, my: Int, dx: Int, dy: Int, min: Dimension, max: Dimension): Rectangle {
    fun keep(size: Int, least: Int, most: Int) = size.coerceIn(least, maxOf(least, most))
    var x = from.x
    var y = from.y
    var w = from.width
    var h = from.height
    if (dx > 0) w = keep(from.width + mx, min.width, max.width)
    if (dx < 0) {
        w = keep(from.width - mx, min.width, max.width)
        x = from.x + from.width - w
    }
    if (dy > 0) h = keep(from.height + my, min.height, max.height)
    if (dy < 0) {
        h = keep(from.height - my, min.height, max.height)
        y = from.y + from.height - h
    }
    return Rectangle(x, y, w, h)
}

// The usable part of every screen, without taskbars and menu bars, with the
// main screen first.
fun screenAreas(): List<ScreenArea> = runCatching {
    val toolkit = Toolkit.getDefaultToolkit()
    val system = GraphicsEnvironment.getLocalGraphicsEnvironment()
    mainFirst(system.screenDevices.toList(), system.defaultScreenDevice).map { device ->
        val config = device.defaultConfiguration
        val b = config.bounds
        val i = toolkit.getScreenInsets(config)
        ScreenArea((b.x + i.left).toFloat(), (b.y + i.top).toFloat(), (b.width - i.left - i.right).toFloat(), (b.height - i.top - i.bottom).toFloat())
    }
}.getOrDefault(emptyList())

private fun Rectangle.toSpot() = WindowSpot(x.toFloat(), y.toFloat(), width.toFloat(), height.toFloat())

private fun Rectangle.toArea() = ScreenArea(x.toFloat(), y.toFloat(), width.toFloat(), height.toFloat())

// The draggable part of the title bar: drag to move, double click to fill
// the screen or come back.
fun Modifier.dragsWindow(frame: Frame): Modifier = pointerInput(frame) {
    var lastDown = 0L
    awaitEachGesture {
        val down = awaitFirstDown(requireUnconsumed = false)
        val now = System.currentTimeMillis()
        if (now - lastDown < 400) {
            frame.toggleMaximized()
            lastDown = 0L
            return@awaitEachGesture
        }
        lastDown = now
        var start: Pair<java.awt.Point, java.awt.Point>? = null
        while (true) {
            val event = awaitPointerEvent()
            val change = event.changes.firstOrNull { it.id == down.id } ?: break
            if (!change.pressed) break
            if (change.positionChange() != androidx.compose.ui.geometry.Offset.Zero) {
                if (start == null) start = frame.startDrag()
                start?.let { frame.dragBy(it.first, it.second) }
                change.consume()
            }
        }
    }
}

// The window's own buttons: minimize, maximize or restore, and close. Over
// the full player they take its `ink`, a step quieter until hovered.
@Composable
fun RowScope.WindowButtons(frame: Frame, onClose: () -> Unit, ink: Color? = null) {
    WindowButton(OctoIcons.Minimize, "Minimize", ink = ink) { frame.minimize() }
    WindowButton(if (frame.maximized) OctoIcons.Restore else OctoIcons.Maximize, if (frame.maximized) "Restore" else "Maximize", ink = ink) { frame.toggleMaximized() }
    WindowButton(OctoIcons.Close, "Close", danger = true, ink = ink, onClick = onClose)
}

@Composable
private fun WindowButton(
    icon: androidx.compose.ui.graphics.vector.ImageVector,
    description: String,
    danger: Boolean = false,
    ink: Color? = null,
    onClick: () -> Unit,
) {
    val interaction = remember { MutableInteractionSource() }
    val hovered by interaction.collectIsHoveredAsState()
    val tip = rememberTooltipState()
    Box(
        Modifier
            .width(46.dp)
            .fillMaxHeight()
            .hoverable(interaction)
            .background(
                when {
                    hovered && danger -> Color(0xFFC42B1C)
                    hovered -> (ink ?: Color.White).copy(alpha = 0.08f)
                    else -> Color.Transparent
                },
            )
            // Like a system title bar's, these are not Tab stops: the keyboard
            // has Alt+Space and Alt+F4.
            .focusProperties { canFocus = false }
            .tooltipTarget(tip)
            .clickable(interactionSource = interaction, indication = null, role = Role.Button, onClick = onClick)
            .semantics { contentDescription = description },
        contentAlignment = Alignment.Center,
    ) {
        val tint = when {
            hovered && danger -> Color.White
            ink != null -> ink.copy(alpha = if (hovered) 1f else 0.7f)
            hovered -> Color.White
            else -> OctoColors.TextSecondary
        }
        Glyph(icon, size = 16.dp, tint = tint)
        TooltipPopup(tip, description, TooltipSide.Bottom)
    }
}

// Invisible strips along the window's edges and corners that resize it.
@Composable
fun BoxScope.ResizeEdges(frame: Frame, thickness: Dp = 5.dp) {
    if (frame.maximized) return
    val corner = thickness * 3
    @Composable
    fun edge(modifier: Modifier, dx: Int, dy: Int, cursor: Int) {
        Box(
            modifier
                .pointerHoverIcon(PointerIcon(Cursor(cursor)))
                .pointerInput(frame, dx, dy) {
                    awaitEachGesture {
                        val down = awaitFirstDown(requireUnconsumed = false)
                        val from = frame.bounds
                        val pointer = MouseInfo.getPointerInfo()?.location ?: return@awaitEachGesture
                        down.consume()
                        while (true) {
                            val event = awaitPointerEvent()
                            val change = event.changes.firstOrNull { it.id == down.id } ?: break
                            if (!change.pressed) break
                            frame.resize(from, pointer, dx, dy)
                            change.consume()
                        }
                    }
                },
        )
    }
    edge(Modifier.align(Alignment.CenterStart).width(thickness).fillMaxHeight(), -1, 0, Cursor.W_RESIZE_CURSOR)
    edge(Modifier.align(Alignment.CenterEnd).width(thickness).fillMaxHeight(), 1, 0, Cursor.E_RESIZE_CURSOR)
    edge(Modifier.align(Alignment.TopCenter).height(thickness).fillMaxWidth(), 0, -1, Cursor.N_RESIZE_CURSOR)
    edge(Modifier.align(Alignment.BottomCenter).height(thickness).fillMaxWidth(), 0, 1, Cursor.S_RESIZE_CURSOR)
    edge(Modifier.align(Alignment.TopStart).size(corner), -1, -1, Cursor.NW_RESIZE_CURSOR)
    edge(Modifier.align(Alignment.TopEnd).size(corner), 1, -1, Cursor.NE_RESIZE_CURSOR)
    edge(Modifier.align(Alignment.BottomStart).size(corner), -1, 1, Cursor.SW_RESIZE_CURSOR)
    edge(Modifier.align(Alignment.BottomEnd).size(corner), 1, 1, Cursor.SE_RESIZE_CURSOR)
}

// A bar of the title bar's height.
@Composable
fun TitleStrip(modifier: Modifier = Modifier, content: @Composable RowScope.() -> Unit) {
    Row(modifier.fillMaxWidth().height(TitleBarHeight), verticalAlignment = Alignment.CenterVertically, content = content)
}
