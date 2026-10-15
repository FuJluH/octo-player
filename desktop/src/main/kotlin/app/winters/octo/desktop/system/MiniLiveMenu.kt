package app.winters.octo.desktop.system

import app.winters.octo.desktop.window.appTextPixels
import app.winters.octo.desktop.window.useTextPixels
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.width
import androidx.compose.runtime.Composable
import androidx.compose.runtime.DisposableEffect
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.runtime.withFrameNanos
import androidx.compose.ui.Modifier
import androidx.compose.ui.input.key.Key
import androidx.compose.ui.input.key.KeyEventType
import androidx.compose.ui.input.key.key
import androidx.compose.ui.input.key.type
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.DpSize
import androidx.compose.ui.unit.dp
import androidx.compose.ui.window.Window
import androidx.compose.ui.window.WindowPosition
import androidx.compose.ui.window.rememberWindowState
import app.winters.octo.design.ChromeEdge
import app.winters.octo.design.FocusVisibility
import app.winters.octo.design.FrameSize
import app.winters.octo.design.MenuFilm
import app.winters.octo.design.MenuShape
import app.winters.octo.design.OctoColors
import app.winters.octo.design.ProvideWindowLook
import app.winters.octo.design.Space
import app.winters.octo.desktop.AppState
import app.winters.octo.desktop.player.LiveNow
import app.winters.octo.desktop.ui.LiveMenuRows
import app.winters.octo.desktop.ui.StationInfoCard
import app.winters.octo.desktop.window.roundWindowsCorners
import app.winters.octo.desktop.window.systemRoundsWindows
import app.winters.octo.desktop.settings.currentOs
import androidx.compose.ui.graphics.RectangleShape
import java.awt.event.WindowEvent
import java.awt.event.WindowFocusListener

// Where the mini player's More menu opens: the More button's bounds on the
// screen, in the system's window units.
data class MiniMenuAnchor(val left: Float, val top: Float, val bottom: Float)

// Where a menu `height` tall opens for `anchor` on a screen whose usable
// area ends at `screenBottom`: under the button when it fits there, else
// above it, and never above the top of the screen.
fun miniMenuTop(anchor: MiniMenuAnchor, height: Float, screenTop: Float, screenBottom: Float): Float =
    if (anchor.bottom + height <= screenBottom) anchor.bottom else (anchor.top - height).coerceAtLeast(screenTop)

// The mini player's More menu for a station, in a small window of its own
// so it is never cut off by the mini player's size: the same rows as the
// full player's menu, and Station info in its place when asked. It goes
// when it loses the keyboard, on Escape, or once a row is picked.
@Composable
fun MiniLiveMenu(
    app: AppState,
    live: LiveNow,
    stationId: String,
    anchor: MiniMenuAnchor,
    onTop: Boolean,
    reduceMotion: Boolean,
    find: (String) -> Unit,
    close: () -> Unit,
) {
    var info by remember { mutableStateOf(false) }
    val width: Dp = if (info) 400.dp else FrameSize.Menu
    val state = rememberWindowState(position = WindowPosition(anchor.left.dp, anchor.bottom.dp), size = DpSize(width, Dp.Unspecified))
    val keyboard = remember { FocusVisibility() }
    // Windows 11 rounds the window itself; elsewhere it is see-through round
    // the menu's rounded shape.
    val systemRounds = remember { systemRoundsWindows(currentOs()) }
    val shape = if (systemRounds) RectangleShape else MenuShape
    Window(
        onCloseRequest = close,
        state = state,
        title = "Octo station menu",
        undecorated = true,
        transparent = !systemRounds,
        resizable = false,
        alwaysOnTop = onTop,
        onPreviewKeyEvent = { event ->
            if (event.type == KeyEventType.KeyDown && event.key == Key.Escape) {
                close()
                true
            } else {
                false
            }
        },
    ) {
        remember { useTextPixels(window, if (systemRounds) appTextPixels else null) }
        LaunchedEffect(Unit) { roundWindowsCorners(window) }
        // Opens under the More button, or over it near the bottom of the
        // screen, once its height is known.
        LaunchedEffect(info) {
            state.size = DpSize(width, Dp.Unspecified)
            // Two frames: one to take the new size, one to lay it out.
            withFrameNanos { }
            withFrameNanos { }
            val screen = window.graphicsConfiguration?.bounds
            val insets = window.graphicsConfiguration?.let { java.awt.Toolkit.getDefaultToolkit().getScreenInsets(it) }
            val top = (screen?.y ?: 0) + (insets?.top ?: 0)
            val bottom = (screen?.let { it.y + it.height } ?: Int.MAX_VALUE) - (insets?.bottom ?: 0)
            val y = miniMenuTop(anchor, window.height.toFloat(), top.toFloat(), bottom.toFloat())
            state.position = WindowPosition(anchor.left.dp, y.dp)
        }
        DisposableEffect(Unit) {
            val focus = object : WindowFocusListener {
                override fun windowGainedFocus(e: WindowEvent?) = Unit
                override fun windowLostFocus(e: WindowEvent?) = close()
            }
            window.addWindowFocusListener(focus)
            onDispose { window.removeWindowFocusListener(focus) }
        }
        ProvideWindowLook(reduceMotion = reduceMotion, focus = keyboard) {
            Box(
                Modifier
                    .width(width)
                    .background(OctoColors.Background, shape)
                    .background(MenuFilm, shape)
                    .border(FrameSize.Hairline, ChromeEdge, shape),
            ) {
                Column(Modifier.padding(vertical = Space.Xs)) {
                    if (info) {
                        StationInfoCard(app, live, close)
                    } else {
                        LiveMenuRows(app, live, stationId, close, info = { info = true }, find = find)
                    }
                }
            }
        }
    }
}
