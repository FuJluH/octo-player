package app.winters.octo.desktop.system

import app.winters.octo.desktop.window.appTextPixels
import app.winters.octo.desktop.window.useTextPixels
import app.winters.octo.desktop.ui.MarkedTitle
import androidx.compose.ui.semantics.LiveRegionMode
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.semantics.liveRegion
import androidx.compose.ui.semantics.semantics
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.BoxWithConstraints
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.aspectRatio
import androidx.compose.foundation.layout.fillMaxHeight
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.window.WindowDraggableArea
import androidx.compose.runtime.Composable
import androidx.compose.runtime.CompositionLocalProvider
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableFloatStateOf
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.mutableLongStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.produceState
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.runtime.snapshotFlow
import androidx.compose.ui.Alignment
import app.winters.octo.desktop.searchFor
import app.winters.octo.desktop.ui.windowRect
import androidx.compose.ui.unit.IntRect
import androidx.compose.ui.layout.onGloballyPositioned
import androidx.compose.ui.layout.onSizeChanged
import app.winters.octo.desktop.ui.OnTitleCapitals
import app.winters.octo.desktop.ui.TitleIconAlpha
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.ExperimentalComposeUiApi
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.painter.Painter
import androidx.compose.ui.input.key.Key
import androidx.compose.ui.input.key.KeyEventType
import androidx.compose.ui.input.key.isAltPressed
import androidx.compose.ui.input.key.isCtrlPressed
import androidx.compose.ui.input.key.isMetaPressed
import androidx.compose.ui.input.key.isShiftPressed
import androidx.compose.ui.input.key.key
import androidx.compose.ui.input.key.type
import androidx.compose.ui.input.pointer.PointerEventType
import androidx.compose.ui.input.pointer.onPointerEvent
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.DpSize
import androidx.compose.ui.unit.dp
import androidx.compose.ui.window.Window
import androidx.compose.ui.window.WindowPosition
import androidx.compose.ui.window.rememberWindowState
import app.winters.octo.design.ChromeEdge
import androidx.compose.foundation.lazy.rememberLazyListState
import app.winters.octo.design.scrollbar
import app.winters.octo.design.ControlHeight
import app.winters.octo.design.Corner
import app.winters.octo.design.DesktopType
import app.winters.octo.design.FrameSize
import app.winters.octo.design.IconAction
import app.winters.octo.design.IconSize
import app.winters.octo.design.LineSlider
import app.winters.octo.design.MenuFilm
import app.winters.octo.design.MenuShape
import app.winters.octo.design.OctoColors
import app.winters.octo.design.OctoIcons
import app.winters.octo.design.FocusVisibility
import app.winters.octo.design.ProvideWindowLook
import app.winters.octo.design.RowHeight
import app.winters.octo.design.SeparatorColor
import app.winters.octo.design.Space
import app.winters.octo.design.Txt
import app.winters.octo.desktop.AppState
import app.winters.octo.desktop.library.Cover
import app.winters.octo.desktop.library.LocalCovers
import app.winters.octo.desktop.library.lengthText
import app.winters.octo.desktop.lyrics.LyricsView
import app.winters.octo.desktop.nav.KeyPress
import app.winters.octo.desktop.nav.Shortcut
import app.winters.octo.desktop.nav.shortcutFor
import app.winters.octo.desktop.player.PlayerState
import app.winters.octo.desktop.settings.DesktopOs
import app.winters.octo.desktop.settings.WindowSpot
import app.winters.octo.desktop.ui.ImmersiveBackdrop
import app.winters.octo.desktop.ui.PlayButton
import app.winters.octo.desktop.ui.PlayScale
import app.winters.octo.desktop.ui.PlayTarget
import app.winters.octo.desktop.ui.LiveCover
import app.winters.octo.desktop.ui.OnAirButton
import app.winters.octo.desktop.ui.LiveLine
import app.winters.octo.desktop.ui.LiveLineupList
import app.winters.octo.desktop.ui.LiveTransport
import app.winters.octo.desktop.player.isLineup
import androidx.compose.ui.graphics.Shape
import app.winters.octo.desktop.ui.isOutside
import app.winters.octo.desktop.ui.rememberPosition
import app.winters.octo.desktop.window.Frame
import app.winters.octo.desktop.window.ResizeEdges
import app.winters.octo.desktop.window.roundWindowsCorners
import app.winters.octo.desktop.window.systemRoundsWindows
import androidx.compose.ui.graphics.RectangleShape
import app.winters.octo.desktop.window.screenAreas
import app.winters.octo.player.immersive.WashTuning
import app.winters.octo.desktop.player.wash.WashCover
import app.winters.octo.desktop.ui.OctoArt
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.FlowPreview
import kotlinx.coroutines.delay
import kotlinx.coroutines.flow.debounce
import kotlinx.coroutines.withContext
import java.awt.Dimension
import java.awt.event.HierarchyEvent
import java.awt.event.HierarchyListener
import androidx.compose.runtime.DisposableEffect

// What the mini player's own buttons ask of the app.
class MiniActions(
    // Pin it where it is, or let it move again.
    val pin: () -> Unit,
    // Jump to another size: the bar, or the cover large.
    val resize: (width: Float, height: Float) -> Unit,
    // Show lyrics or the queue under it, or neither.
    val showPanel: (MiniPanel?) -> Unit,
    // Close it and go back to Octo's window.
    val close: () -> Unit,
    // A station's More menu, under the button whose bounds in this window
    // are given, in pixels.
    val more: (IntRect) -> Unit = {},
)

// A small window of its own that stays above the others (unless Settings
// says not): the playing song over its own colours behind dark glass, as the
// floating player looks. Drag it anywhere, resize it by its edges from a bar
// to a square with the cover large; tall enough, it shows lyrics or the
// queue. Pinned, it stays put: no dragging and no edges to pull.
// It opens where it last was, and closing it brings Octo's window back.
@OptIn(FlowPreview::class)
@Composable
fun MiniPlayerWindow(
    app: AppState,
    spot: WindowSpot,
    os: DesktopOs,
    icon: Painter?,
    onMoved: (WindowSpot) -> Unit,
    onClose: () -> Unit,
    reduceMotion: Boolean,
) {
    // Whether the keyboard is in use in this window, for its focus rings.
    val keyboard = remember { FocusVisibility() }
    val windowState = rememberWindowState(position = WindowPosition(spot.x.dp, spot.y.dp), size = DpSize(spot.width.dp, spot.height.dp))
    val settings by app.settings.state.collectAsState()
    val prefs = settings.system
    fun here(): WindowSpot {
        val at = windowState.position
        return WindowSpot(if (at is WindowPosition.Absolute) at.x.value else spot.x, if (at is WindowPosition.Absolute) at.y.value else spot.y, windowState.size.width.value, windowState.size.height.value)
    }
    fun jumpTo(width: Float, height: Float) {
        val to = resizeMiniPlayer(here(), width, height, screenAreas())
        windowState.position = WindowPosition(to.x.dp, to.y.dp)
        windowState.size = DpSize(to.width.dp, to.height.dp)
    }
    // A word on what the pin did, for a moment, since pinning changes
    // nothing to be seen until the listener tries to move it, or on what a
    // row of the station menu did.
    var pinNote by remember { mutableStateOf<String?>(null) }
    // A station's More menu, open under its button, in screen units.
    var liveMenu by remember { mutableStateOf<MiniMenuAnchor?>(null) }
    var density by remember { mutableStateOf(1f) }
    var pinClicks by remember { mutableIntStateOf(0) }
    LaunchedEffect(pinClicks) {
        if (pinClicks == 0) return@LaunchedEffect
        delay(PIN_NOTE_MS)
        pinNote = null
    }
    // Octo's own window is hidden behind the mini player, so what the
    // station menu's rows did (kept, removed, copied, added to the server,
    // or why not) is said here: any notice that comes while the menu is
    // open or soon after it closes.
    var echoUntil by remember { mutableLongStateOf(0L) }
    LaunchedEffect(Unit) {
        snapshotFlow { app.notice }.collect { line ->
            if (line != null && (liveMenu != null || System.currentTimeMillis() < echoUntil)) {
                pinNote = line
                pinClicks++
            }
        }
    }
    val actions = MiniActions(
        pin = {
            val on = !app.settings.current.system.miniPlayerPinned
            app.settings.update { it.copy(system = it.system.copy(miniPlayerPinned = on)) }
            pinNote = pinNoteFor(on)
            pinClicks++
        },
        resize = ::jumpTo,
        showPanel = { panel ->
            app.settings.update { it.copy(system = it.system.copy(miniPlayerPanel = panel?.name?.lowercase())) }
            if (panel != null) miniSizeForPanel(here()).let { (w, h) -> if (w != windowState.size.width.value || h != windowState.size.height.value) jumpTo(w, h) }
        },
        close = onClose,
        more = { rect ->
            val at = windowState.position
            if (at is WindowPosition.Absolute) {
                liveMenu = MiniMenuAnchor(at.x.value + rect.left / density, at.y.value + rect.top / density, at.y.value + rect.bottom / density)
            }
        },
    )
    val playing by app.player.state.collectAsState()
    val menuFor = liveMenu
    val live = playing.live
    if (menuFor != null && live != null) {
        MiniLiveMenu(
            app,
            live,
            playing.current?.song?.id.orEmpty(),
            menuFor,
            onTop = prefs.miniPlayerOnTop,
            reduceMotion = reduceMotion,
            find = { query ->
                liveMenu = null
                onClose()
                app.searchFor(query)
            },
            close = {
                liveMenu = null
                echoUntil = System.currentTimeMillis() + MENU_ECHO_MS
            },
        )
    }
    // The station went: so does its menu.
    LaunchedEffect(live == null) { if (live == null) liveMenu = null }
    val systemRounds = remember(os) { systemRoundsWindows(os) }
    Window(
        onCloseRequest = onClose,
        state = windowState,
        title = "Octo mini player",
        icon = icon,
        undecorated = true,
        // Windows 11 rounds the frameless window itself, with its own edge
        // and shadow, so the face fills it square; elsewhere the window is
        // see-through round the face's rounded shape.
        transparent = !systemRounds,
        alwaysOnTop = prefs.miniPlayerOnTop,
        resizable = !prefs.miniPlayerPinned,
        onPreviewKeyEvent = { event ->
            if (event.type != KeyEventType.KeyDown) return@Window false
            // Tab is the keyboard finding its way: rings show.
            if (event.key == Key.Tab) keyboard.keyboard = true
            // Esc goes back to Octo's window, as closing does.
            if (event.key == Key.Escape) {
                onClose()
                return@Window true
            }
            val press = KeyPress(event.key, event.isCtrlPressed, event.isAltPressed, event.isShiftPressed, event.isMetaPressed)
            when (val shortcut = shortcutFor(press, app.mac, typing = false)) {
                Shortcut.PlayPause, Shortcut.SeekBack, Shortcut.SeekForward, Shortcut.VolumeUp, Shortcut.VolumeDown -> app.perform(shortcut)
                Shortcut.MiniPlayer -> {
                    onClose()
                    true
                }
                else -> false
            }
        },
    ) {
        // Colour text needs a window drawn whole; a see-through one stays grey.
        remember { useTextPixels(window, if (systemRounds) appTextPixels else null) }
        val frame = remember { Frame(window, windowState) }
        density = LocalDensity.current.density
        LaunchedEffect(Unit) {
            window.minimumSize = Dimension(MINI_MIN_WIDTH.toInt(), MINI_MIN_HEIGHT.toInt())
            window.maximumSize = Dimension(MINI_MAX_WIDTH.toInt(), MINI_MAX_HEIGHT.toInt())
            // Its icons for Alt+Tab and the taskbar, each size drawn from the vector.
            if (icon == null) window.iconImages = withContext(Dispatchers.Default) { OctopusArt.windowIcons() }
        }
        // Asked again whenever the window's style can change (pinned, kept
        // on top) or its native window is made again, which drops the ask.
        if (systemRounds) {
            LaunchedEffect(prefs.miniPlayerPinned, prefs.miniPlayerOnTop) { roundWindowsCorners(window) }
            DisposableEffect(window) {
                val again = HierarchyListener { event ->
                    if (event.changeFlags and HierarchyEvent.DISPLAYABILITY_CHANGED.toLong() != 0L && window.isDisplayable) roundWindowsCorners(window)
                }
                window.addHierarchyListener(again)
                onDispose { window.removeHierarchyListener(again) }
            }
        }
        LaunchedEffect(Unit) {
            snapshotFlow { windowState.position to windowState.size }
                .debounce(500)
                .collect { (position, size) ->
                    if (position is WindowPosition.Absolute) onMoved(WindowSpot(position.x.value, position.y.value, size.width.value, size.height.value))
                }
        }
        ProvideWindowLook(reduceMotion = reduceMotion, focus = keyboard) {
            CompositionLocalProvider(LocalCovers provides app.connection?.client) {
                Box(Modifier.fillMaxSize()) {
                    MiniPlayerView(
                        app,
                        panel = prefs.miniPlayerPanel.toMiniPanel(),
                        pinned = prefs.miniPlayerPinned,
                        actions = actions,
                        note = pinNote,
                        shape = if (systemRounds) RectangleShape else MenuShape,
                        dragArea = { modifier -> if (!prefs.miniPlayerPinned) WindowDraggableArea(modifier) {} },
                    )
                    if (!prefs.miniPlayerPinned) ResizeEdges(frame, thickness = Space.Xs)
                }
            }
        }
    }
}

// The saved panel's name as a panel.
fun String?.toMiniPanel(): MiniPanel? = MiniPanel.entries.firstOrNull { it.name.equals(this, ignoreCase = true) }

// The mini player's face, at whatever size its window is, in the shape
// that size calls for. `dragArea` lies under the controls and moves the
// window (nothing, when pinned or drawn for a picture).
@Composable
fun MiniPlayerView(
    app: AppState,
    panel: MiniPanel?,
    pinned: Boolean,
    actions: MiniActions,
    // A short line over the bottom of it, for a moment, if any.
    note: String? = null,
    // The face's outline: rounded, unless the system rounds the window.
    shape: Shape = MenuShape,
    dragArea: @Composable (Modifier) -> Unit,
) {
    val state by app.player.state.collectAsState()
    Box(Modifier.fillMaxSize().background(OctoColors.Background, shape)) {
        MiniBackdrop(app, state, Modifier.matchParentSize())
        Box(Modifier.matchParentSize().background(MenuFilm, shape))
        dragArea(Modifier.matchParentSize())
        BoxWithConstraints(Modifier.fillMaxSize()) {
            when (miniShapeFor(maxHeight.value, panel)) {
                MiniShape.Bar -> MiniBar(app, state, pinned, actions, wide = maxWidth.value >= MINI_TIMES_WIDTH)
                MiniShape.Cover -> MiniCover(app, state, panel, pinned, actions)
                MiniShape.Panel -> MiniWithPanel(app, state, panel ?: MiniPanel.Lyrics, pinned, actions)
            }
        }
        if (note != null) MiniNote(note, Modifier.align(Alignment.BottomCenter))
        Box(Modifier.matchParentSize().border(FrameSize.Hairline, ChromeEdge, shape))
    }
}

// How long the pin's word stays.
private const val PIN_NOTE_MS = 2_400L

// How long after the station menu closes its rows' notices still show here:
// adding a station to the server answers once the server has.
private const val MENU_ECHO_MS = 15_000L

// What the pin did, in words.
fun pinNoteFor(pinned: Boolean): String = if (pinned) "Pinned in place" else "Unpinned. Drag it anywhere"

// A line in a dark capsule, over whatever is under it.
@Composable
private fun MiniNote(text: String, modifier: Modifier) {
    Box(
        modifier
            .padding(bottom = Space.S)
            .background(OctoColors.Background.copy(alpha = 0.92f), CircleShape)
            .border(FrameSize.Hairline, ChromeEdge, CircleShape)
            .padding(horizontal = Space.M, vertical = Space.Xs)
            .semantics { liveRegion = LiveRegionMode.Polite },
    ) {
        Txt(text, DesktopType.meta, OctoColors.TextPrimary, maxLines = 1)
    }
}

// From this wide the bar shows the times beside its progress line.
private const val MINI_TIMES_WIDTH = 460f

// The playing song's colours, held still, behind the glass: the full
// player's wash, dimmed as the window's ambience is. None when the
// listener turned the ambience off.
@Composable
private fun MiniBackdrop(app: AppState, state: PlayerState, modifier: Modifier) {
    val settings by app.settings.state.collectAsState()
    val look = settings.appearance
    if (!look.ambientGlow) return
    val wash = look.wash
    val tuning = WashTuning(wash.contrast, wash.saturation / 100f, wash.brightnessCap / 100f)
    val song = state.current?.song
    val connection = app.connection
    val cover by produceState<WashCover?>(null, song?.coverArt, song == null, connection, tuning) {
        if (song == null || connection == null) {
            value = withContext(Dispatchers.Default) { OctoArt.cover(tuning) }
        } else {
            app.washCovers.follow(connection.client, song.coverArt, tuning).collect { value = it }
        }
    }
    ImmersiveBackdrop(cover, look.glowStrength, bpm = 0f, fps = 1, speed = 0f, moving = false, modifier = modifier, quiet = song == null)
}

// The bar: the cover on the left, the song and the window's buttons, and
// under them the transport, the progress line, the heart and the volume.
@Composable
private fun MiniBar(app: AppState, state: PlayerState, pinned: Boolean, actions: MiniActions, wide: Boolean) {
    val song = state.current?.song
    Row(Modifier.fillMaxSize().padding(Space.L), horizontalArrangement = Arrangement.spacedBy(Space.L), verticalAlignment = Alignment.CenterVertically) {
        MiniArt(app, state, Modifier.fillMaxHeight().aspectRatio(1f), Corner.ArtMShape, small = true)
        Column(Modifier.weight(1f).fillMaxHeight(), verticalArrangement = Arrangement.SpaceBetween) {
            Row(verticalAlignment = Alignment.Top) {
                SongWords(state, Modifier.weight(1f))
                WindowButtons(pinned, bar = true, actions)
            }
            Row(Modifier.fillMaxWidth(), verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(Space.Xxs)) {
                Transport(app, state)
                Progress(app, state, Modifier.weight(1f).padding(horizontal = Space.Xs), times = wide)
                Heart(app, state)
                LiveMore(state, actions)
                VolumeButton(app, state.volume)
            }
        }
    }
}

// The cover large, with the window's buttons over its top, then the song,
// the progress line, the transport between the lyrics and queue buttons,
// and the volume.
@Composable
private fun MiniCover(app: AppState, state: PlayerState, panel: MiniPanel?, pinned: Boolean, actions: MiniActions) {
    val song = state.current?.song
    Column(Modifier.fillMaxSize().padding(Space.Xl), verticalArrangement = Arrangement.spacedBy(Space.M)) {
        BoxWithConstraints(Modifier.fillMaxWidth().weight(1f), contentAlignment = Alignment.Center) {
            val side = minOf(maxWidth, maxHeight)
            Box(Modifier.size(side)) {
                MiniArt(app, state, Modifier.fillMaxSize(), Corner.ArtLShape)
                // A soft shade at the top, so the buttons read on any cover.
                Box(Modifier.fillMaxWidth().height(ControlHeight.L + Space.Xl).background(TopShade, Corner.ArtLShape))
                Box(Modifier.align(Alignment.TopEnd).padding(Space.Xs)) { WindowButtons(pinned, bar = false, actions) }
            }
        }
        // The heart (and a station's More) on the middle of the title's
        // capitals, a step quieter than it.
        Row(verticalAlignment = Alignment.Top) {
            SongWords(state, Modifier.weight(1f))
            OnTitleCapitals(DesktopType.emphasis) {
                Row(verticalAlignment = Alignment.CenterVertically) {
                    Heart(app, state, quiet = TitleIconAlpha)
                    LiveMore(state, actions, quiet = TitleIconAlpha)
                }
            }
        }
        Progress(app, state, Modifier.fillMaxWidth(), times = true)
        Row(Modifier.fillMaxWidth(), verticalAlignment = Alignment.CenterVertically) {
            if (state.live == null) PanelButton(MiniPanel.Lyrics, panel, actions) else Spacer(Modifier.size(ControlHeight.S))
            Spacer(Modifier.weight(1f))
            Transport(app, state)
            Spacer(Modifier.weight(1f))
            if (state.live == null || state.queue.size > 1) PanelButton(MiniPanel.Queue, panel, actions)
        }
        VolumeLine(app, state.volume)
    }
}

// A short header (the cover small, the song, the window's buttons), the
// progress line and the transport, then lyrics or the queue below a
// hairline.
@Composable
private fun MiniWithPanel(app: AppState, state: PlayerState, panel: MiniPanel, pinned: Boolean, actions: MiniActions) {
    val song = state.current?.song
    Column(Modifier.fillMaxSize().padding(top = Space.L, start = Space.L, end = Space.L)) {
        Row(Modifier.fillMaxWidth().height(FrameSize.PlayerThumb), horizontalArrangement = Arrangement.spacedBy(Space.L), verticalAlignment = Alignment.CenterVertically) {
            MiniArt(app, state, Modifier.size(FrameSize.PlayerThumb), Corner.ArtMShape, small = true)
            SongWords(state, Modifier.weight(1f))
            WindowButtons(pinned, bar = false, actions)
        }
        Progress(app, state, Modifier.fillMaxWidth().padding(top = Space.M), times = true)
        Row(Modifier.fillMaxWidth().padding(vertical = Space.Xs), verticalAlignment = Alignment.CenterVertically) {
            if (state.live == null) PanelButton(MiniPanel.Lyrics, panel, actions)
            Heart(app, state)
            LiveMore(state, actions)
            Spacer(Modifier.weight(1f))
            Transport(app, state)
            Spacer(Modifier.weight(1f))
            VolumeButton(app, state.volume)
            if (state.live == null || state.queue.size > 1) PanelButton(MiniPanel.Queue, panel, actions)
        }
        Box(Modifier.fillMaxWidth().height(FrameSize.Hairline).background(SeparatorColor))
        Box(Modifier.fillMaxWidth().weight(1f)) {
            when {
                state.live != null && isLineup(state.queue.map { it.song }) -> LiveLineupList(app, state)
                panel == MiniPanel.Lyrics && state.live == null -> LyricsView(app, Modifier.fillMaxSize())
                else -> UpNext(app, state)
            }
        }
    }
}

private val TopShade = Brush.verticalGradient(listOf(Color.Black.copy(alpha = 0.45f), Color.Transparent))

// The playing song's cover, or a station's picture.
@Composable
private fun MiniArt(app: AppState, state: PlayerState, modifier: Modifier, shape: Shape, small: Boolean = false) {
    val live = state.live
    if (live != null) LiveCover(app, live, modifier, shape, small = small)
    else Cover(state.current?.song?.coverArt, modifier, shape = shape, placeholder = OctoIcons.Songs, retry = true)
}

// The song's title and artist, or that nothing plays. A station shows the
// song on air (or itself) and "Artist · Station" (or its tagline).
@Composable
private fun SongWords(state: PlayerState, modifier: Modifier) {
    val song = state.current?.song
    val live = state.live
    Column(modifier, verticalArrangement = Arrangement.spacedBy(Space.Xxs)) {
        if (song == null) {
            Txt("Nothing playing", DesktopType.emphasis, OctoColors.TextMuted)
        } else if (live != null) {
            Txt(song.title, DesktopType.emphasis, OctoColors.TextPrimary)
            Txt(live.shown.subtitle, DesktopType.meta, OctoColors.TextSecondary)
        } else {
            MarkedTitle(song, DesktopType.emphasis) { Txt(song.title, DesktopType.emphasis, OctoColors.TextPrimary, it) }
            Txt((song.displayArtist ?: song.artist).orEmpty(), DesktopType.meta, OctoColors.TextSecondary)
        }
    }
}

// The pin, the size, and back to Octo, quiet until wanted.
@Composable
private fun WindowButtons(pinned: Boolean, bar: Boolean, actions: MiniActions) {
    Row(horizontalArrangement = Arrangement.spacedBy(Space.Xxs), verticalAlignment = Alignment.CenterVertically) {
        val quiet = OctoColors.TextSecondary
        IconAction(if (pinned) OctoIcons.Pinned else OctoIcons.Pin, if (pinned) "Unpin so it can move" else "Pin it in place", actions.pin, size = ControlHeight.Xs, iconSize = IconSize.Inline, active = pinned, tint = if (pinned) OctoColors.TextPrimary else quiet)
        if (bar) {
            IconAction(OctoIcons.Expand, "Show the cover large", { actions.resize(MINI_SQUARE_WIDTH, MINI_SQUARE_HEIGHT) }, size = ControlHeight.Xs, iconSize = IconSize.Inline, tint = quiet)
        } else {
            IconAction(OctoIcons.Collapse, "Make it a bar", { actions.resize(MINI_WIDTH, MINI_HEIGHT) }, size = ControlHeight.Xs, iconSize = IconSize.Inline, tint = quiet)
        }
        IconAction(OctoIcons.Close, "Back to Octo", actions.close, size = ControlHeight.Xs, iconSize = IconSize.Inline, tint = quiet)
    }
}

// Back, play and next; for a station, Back, Play or Stop, and Next station.
@Composable
private fun Transport(app: AppState, state: PlayerState) {
    val song = state.current?.song
    state.live?.let { live -> return LiveTransport(app, state, live, playSize = PlayTarget, stepSize = ControlHeight.S, stepIcon = IconSize.Toolbar, tint = OctoColors.TextPrimary, gap = Space.Xxs) }
    Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(Space.Xxs)) {
        IconAction(OctoIcons.Previous, "Previous", app.player::previous, size = ControlHeight.S, iconSize = IconSize.Toolbar, enabled = song != null)
        PlayButton(state.playing, enabled = song != null, size = PlayTarget, glyph = IconSize.Toolbar * PlayScale, waiting = state.buffering) { app.player.togglePlay() }
        IconAction(OctoIcons.Next, "Next", app.player::next, size = ControlHeight.S, iconSize = IconSize.Toolbar, enabled = song != null)
    }
}

// Where the song is, to drag; with the time played and the length when
// there is room.
@Composable
private fun Progress(app: AppState, state: PlayerState, modifier: Modifier, times: Boolean) {
    if (state.live != null) return LiveLine(app, OctoColors.TextPrimary, OctoColors.TextMuted, modifier, times = times)
    var lineLength by remember { mutableFloatStateOf(0f) }
    val position by rememberPosition(app.player, lineLength)
    val duration = state.durationMs
    Row(modifier, verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(Space.S)) {
        if (times) Txt(lengthText((position / 1000).toInt()).ifEmpty { "0:00" }, TimeStyle, OctoColors.TextMuted, Modifier.width(TimeWidth))
        LineSlider(
            fraction = { if (duration > 0) position.toFloat() / duration else 0f },
            onSeek = { app.player.seekTo((it * duration).toLong()) },
            modifier = Modifier.weight(1f).onSizeChanged { lineLength = it.width.toFloat() },
            hoverLabel = { lengthText((it * duration / 1000).toInt()).ifEmpty { "0:00" } },
        )
        if (times) Txt(lengthText((duration / 1000).toInt()).ifEmpty { "0:00" }, TimeStyle, OctoColors.TextMuted, Modifier.width(TimeWidth), align = TextAlign.End)
    }
}

private val TimeStyle = DesktopType.meta.copy(fontFeatureSettings = "tnum")
private val TimeWidth: Dp = Space.Wide

// A station's More button: its menu opens in a window of its own. `quiet`
// is how strongly its dots show.
@Composable
private fun LiveMore(state: PlayerState, actions: MiniActions, quiet: Float = 1f) {
    if (state.live == null) return
    var anchor by remember { mutableStateOf(IntRect.Zero) }
    Box(Modifier.onGloballyPositioned { anchor = it.windowRect() }) {
        IconAction(OctoIcons.More, "More", { actions.more(anchor) }, size = ControlHeight.S, iconSize = IconSize.Toolbar, tint = OctoColors.TextPrimary.copy(alpha = quiet))
    }
}

// The heart, for a song in the library. `quiet` is how strongly it shows
// until it is filled.
@Composable
private fun Heart(app: AppState, state: PlayerState, quiet: Float = 1f) {
    val song = state.current?.song ?: return
    state.live?.let { live -> return OnAirButton(app, live, ControlHeight.S, IconSize.Toolbar, OctoColors.TextPrimary, quiet) }
    if (isOpenedFile(song.id) || isOutside(app, song)) return
    val starred = app.isStarred(song)
    IconAction(
        if (starred) OctoIcons.Liked else OctoIcons.Like,
        if (starred) "Remove from favorites" else "Add to favorites",
        { app.setStarred(listOf(song), !starred) },
        size = ControlHeight.S,
        iconSize = IconSize.Toolbar,
        tint = if (starred) OctoColors.TextPrimary else OctoColors.TextPrimary.copy(alpha = quiet),
    )
}

// Lyrics or the queue: shows it under the player (growing the window when
// it has no room), or hides it again.
@Composable
private fun PanelButton(which: MiniPanel, shown: MiniPanel?, actions: MiniActions) {
    val open = shown == which
    val (icon, words) = when (which) {
        MiniPanel.Lyrics -> OctoIcons.Lyrics to if (open) "Hide lyrics" else "Lyrics"
        MiniPanel.Queue -> OctoIcons.Queue to if (open) "Hide the queue" else "Queue"
    }
    IconAction(icon, words, { actions.showPanel(if (open) null else which) }, size = ControlHeight.S, iconSize = IconSize.Toolbar, active = open)
}

// The speaker: the wheel turns the volume, a click mutes and unmutes.
@OptIn(ExperimentalComposeUiApi::class)
@Composable
private fun VolumeButton(app: AppState, volume: Float) {
    val before = remember { mutableFloatStateOf(0.8f) }
    val muted = volume <= 0.001f
    Box(
        Modifier.onPointerEvent(PointerEventType.Scroll) { event ->
            val dy = event.changes.firstOrNull()?.scrollDelta?.y ?: 0f
            if (dy != 0f) app.setVolume(app.player.state.value.volume - dy * 0.05f)
        },
    ) {
        IconAction(
            if (muted) OctoIcons.VolumeDown else OctoIcons.VolumeUp,
            if (muted) "Unmute" else "Mute (the wheel turns it up or down)",
            {
                if (muted) {
                    app.setVolume(before.floatValue.takeIf { it > 0.01f } ?: 0.8f)
                } else {
                    before.floatValue = volume
                    app.setVolume(0f)
                }
            },
            size = ControlHeight.S,
            iconSize = IconSize.Toolbar,
        )
    }
}

// The volume as a line to drag, with the speaker to mute.
@Composable
private fun VolumeLine(app: AppState, volume: Float) {
    Row(Modifier.fillMaxWidth(), verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(Space.S)) {
        VolumeButton(app, volume)
        LineSlider(fraction = { app.player.state.value.volume }, onSeek = app::setVolume, modifier = Modifier.weight(1f), live = true, wheelStep = 0.05f)
    }
}

// The songs still to come; a click plays one.
@Composable
private fun UpNext(app: AppState, state: PlayerState) {
    val upcoming = state.upcoming
    if (upcoming.isEmpty()) {
        Box(Modifier.fillMaxSize(), contentAlignment = Alignment.Center) {
            Txt("Nothing up next", DesktopType.meta, OctoColors.TextMuted)
        }
        return
    }
    val list = rememberLazyListState()
    LazyColumn(Modifier.fillMaxSize().scrollbar(list), list) {
        item { Txt("UP NEXT", DesktopType.label, OctoColors.TextMuted, Modifier.padding(top = Space.M, bottom = Space.Xs, start = Space.Xs)) }
        items(upcoming.take(UP_NEXT_LIMIT), key = { it.key }) { entry ->
            Row(
                Modifier.fillMaxWidth().height(RowHeight.Regular).clickable(role = Role.Button) { app.player.skipTo(entry.key) }.padding(horizontal = Space.Xs),
                verticalAlignment = Alignment.CenterVertically,
                horizontalArrangement = Arrangement.spacedBy(Space.M),
            ) {
                Cover(entry.song.coverArt, Modifier.size(FrameSize.PlaylistCover), shape = Corner.ArtSShape, placeholder = OctoIcons.Songs)
                Column(Modifier.weight(1f)) {
                    MarkedTitle(entry.song, DesktopType.table) { Txt(entry.song.title, DesktopType.table, OctoColors.TextPrimary, it) }
                    Txt((entry.song.displayArtist ?: entry.song.artist).orEmpty(), DesktopType.meta, OctoColors.TextSecondary)
                }
            }
        }
    }
}

// The queue lists this many songs; the main window has the rest.
private const val UP_NEXT_LIMIT = 100
