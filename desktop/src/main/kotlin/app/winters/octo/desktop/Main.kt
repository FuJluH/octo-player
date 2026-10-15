package app.winters.octo.desktop

import app.winters.octo.animated.LoopShelf
import app.winters.octo.desktop.animated.LOOP_SHELF_BYTES
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.runtime.CompositionLocalProvider
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.runtime.snapshotFlow
import androidx.compose.runtime.withFrameNanos
import androidx.compose.ui.Modifier
import androidx.compose.ui.input.key.Key
import androidx.compose.ui.input.key.KeyEventType
import androidx.compose.ui.input.key.isAltPressed
import androidx.compose.ui.input.key.isCtrlPressed
import androidx.compose.ui.input.key.isMetaPressed
import androidx.compose.ui.input.key.isShiftPressed
import androidx.compose.ui.input.key.key
import androidx.compose.ui.input.key.type
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.unit.Density
import androidx.compose.ui.unit.DpSize
import androidx.compose.ui.unit.dp
import androidx.compose.ui.window.Window
import androidx.compose.ui.window.WindowPlacement
import androidx.compose.ui.window.WindowPosition
import androidx.compose.ui.window.application
import androidx.compose.ui.window.rememberWindowState
import app.winters.octo.design.ArrowKeys
import app.winters.octo.design.FocusVisibility
import app.winters.octo.design.LocalTyping
import app.winters.octo.design.ProvideWindowLook
import app.winters.octo.design.TypingState
import app.winters.octo.desktop.audio.CHECK_PLAY
import app.winters.octo.desktop.audio.checkSound
import app.winters.octo.desktop.audio.openPlayer
import app.winters.octo.desktop.library.coverLoader
import app.winters.octo.desktop.library.followCoversAhead
import app.winters.octo.desktop.nav.KeyPress
import app.winters.octo.desktop.nav.shortcutFor
import app.winters.octo.desktop.settings.AppPlaces
import app.winters.octo.desktop.settings.DesktopOs
import app.winters.octo.desktop.settings.SettingsStore
import app.winters.octo.server.NEW_MUSIC_LOOK_MS
import app.winters.octo.desktop.settings.WindowSpot
import app.winters.octo.desktop.settings.currentOs
import app.winters.octo.desktop.settings.systemReducesMotion
import app.winters.octo.desktop.settings.systemTextScale
import app.winters.octo.desktop.settings.textScale
import app.winters.octo.desktop.system.AudioDropZone
import app.winters.octo.desktop.system.LocalSystem
import app.winters.octo.desktop.system.SingleInstance
import app.winters.octo.desktop.system.SystemIntegration
import app.winters.octo.desktop.system.letRunningOctoComeForward
import app.winters.octo.desktop.system.preloadStartClasses
import app.winters.octo.desktop.system.startsInTray
import app.winters.octo.desktop.system.useAppNatives
import app.winters.octo.desktop.ui.ListFocus
import app.winters.octo.desktop.ui.LocalListFocus
import app.winters.octo.desktop.ui.LocalSoftwareDrawing
import app.winters.octo.desktop.ui.LocalWindowShown
import app.winters.octo.desktop.ui.Opening
import app.winters.octo.desktop.ui.Shell
import app.winters.octo.desktop.update.DesktopUpdates
import app.winters.octo.desktop.window.Frame
import app.winters.octo.desktop.window.MIN_HEIGHT
import app.winters.octo.desktop.window.MIN_WIDTH
import app.winters.octo.desktop.window.keepsSpot
import app.winters.octo.desktop.window.placeWindow
import app.winters.octo.desktop.window.roundWindowsCorners
import app.winters.octo.desktop.window.appTextPixels
import app.winters.octo.desktop.window.systemTextPixels
import app.winters.octo.desktop.window.useTextPixels
import app.winters.octo.design.TextLook
import app.winters.octo.desktop.window.screenAreas
import app.winters.octo.desktop.window.seeThroughMacTitleBar
import app.winters.octo.subsonic.OCTO_TRANSITIONS
import coil3.PlatformContext
import coil3.SingletonImageLoader
import coil3.compose.setSingletonImageLoaderFactory
import kotlinx.coroutines.delay
import kotlinx.coroutines.launch
import java.awt.Dimension
import java.awt.event.WindowAdapter
import java.awt.event.WindowEvent
import java.io.File
import javax.swing.SwingUtilities
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.FlowPreview
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.flow.debounce
import kotlinx.coroutines.flow.first
import kotlinx.coroutines.withTimeoutOrNull
import org.jetbrains.skiko.GraphicsApi
import app.winters.octo.desktop.system.OctopusArt
import app.winters.octo.desktop.system.OctopusPainter
import java.awt.image.BufferedImage
import java.util.concurrent.CompletableFuture
import kotlinx.coroutines.withContext

// The window's icons, one drawn from the vector for each size Windows may
// ask for, made beside the start so they are ready when the window shows.
private fun windowIconsAhead(): CompletableFuture<List<BufferedImage>> =
    CompletableFuture.supplyAsync { runCatching { OctopusArt.windowIcons() }.getOrDefault(emptyList()) }

// What the window runs once the app is made.
private class Opened(val app: AppState, val system: SystemIntegration, val updates: DesktopUpdates)

// How long the window waits for its first frame before the app is made in
// any case (a window starting in the tray draws none).
private const val FIRST_FRAME_WAIT_MS = 500L

// The most the app waits for the opening's octopus to come in before it is
// made in any case (it lands in about 0.4 s).
private const val OPENING_WAIT_MS = 700L

@OptIn(FlowPreview::class)
fun main(args: Array<String>) {
    // Before anything touches JNA.
    useAppNatives()
    // The start's classes, read ahead beside everything below.
    preloadStartClasses()
    val places = AppPlaces.forSystem()
    // One Octo at a time: launching it again hands the files and links to
    // the running one, which comes forward, and ends here.
    val claim = SingleInstance.claim(places.config, args.toList(), beforeHandover = ::letRunningOctoComeForward)
    if (claim is SingleInstance.Claim.HandedOver) return
    val instance = (claim as? SingleInstance.Claim.First)?.instance
    val settings = SettingsStore(File(places.config, SettingsStore.FILE_NAME), SettingsStore.APP_WRITE_DELAY_MS)
    val os = currentOs()
    // Text smoothed as the system smooths its own, decided before any text
    // style is first read.
    appTextPixels = systemTextPixels(os)
    TextLook.colour = appTextPixels != null
    // The slow part (the HTTP client, the password store, the audio engine
    // and the rest) starts now on threads of its own; the window shows
    // while it runs, and the app is made once it is in.
    val startup = Startup(settings, places, os)
    // The system's own "Animation effects" (or Reduce motion), read again
    // whenever the window comes forward, so a change applies without a restart.
    var systemCalm by mutableStateOf(false)
    // The system's text size, read the same way.
    var systemText by mutableStateOf(1f)
    val icons = windowIconsAhead()
    val octopus = OctopusPainter()
    val inTray = startsInTray(args.toList())
    // The opening comes in quietly when the listener asked for calm motion.
    val calmStart = settings.current.appearance.calmMotion

    application {
        // The app, once made; until then the window shows its first frame.
        var opened by remember { mutableStateOf<Opened?>(null) }
        val ready = opened
        // The opening's octopus is far enough in, and later gone.
        var entered by remember { mutableStateOf(false) }
        var openingGone by remember { mutableStateOf(false) }
        val spot = remember { placeWindow(settings.current.window, screenAreas()) }
        // Windows and Linux get the app's own glass frame unless the
        // listener asked for the system's; macOS keeps its own lights.
        val custom = remember { os != DesktopOs.Mac && !settings.current.systemTitleBar }
        val windowState = rememberWindowState(
            placement = if (spot.maximized && !custom) WindowPlacement.Maximized else WindowPlacement.Floating,
            position = WindowPosition(spot.x.dp, spot.y.dp),
            size = DpSize(spot.width.dp, spot.height.dp),
        )
        val typing = remember { TypingState() }
        val lists = remember { ListFocus() }
        // Whether the keyboard is moving about (rings show), and whether a
        // focused control holds the arrow keys (a slider).
        val keyboard = remember { FocusVisibility() }
        val arrows = remember { ArrowKeys() }
        var frame by remember { mutableStateOf<Frame?>(null) }
        // Where the window last was at its own size, for the next run.
        var floating by remember { mutableStateOf(spot.copy(maximized = false)) }
        fun maximizedNow() = frame?.maximized ?: (windowState.placement == WindowPlacement.Maximized)
        fun keepPlace() = settings.update { it.copy(window = floating.copy(maximized = maximizedNow())) }
        fun close() {
            keepPlace()
            val made = opened
            made?.app?.beforeQuit()
            settings.flush()
            if (made != null) {
                // A ready update goes in now when the listener chose that.
                made.updates.onQuit()
                made.system.close()
                made.app.player.close()
            }
            exitApplication()
        }
        // Closing the window quits, or with the setting on, leaves Octo
        // playing in the tray.
        fun closeWindow() {
            val system = opened?.system
            if (system == null || !system.closesToTray) return close()
            keepPlace()
            system.hideWindow()
        }
        // Makes the app from what Startup got ready, on the window's thread.
        fun open(parts: StartupParts): Opened {
            systemCalm = parts.systemCalm
            systemText = parts.systemText
            val scope = CoroutineScope(SupervisorJob() + Dispatchers.Main)
            var made: AppState? = null
            // Server songs are signed with whoever is signed in when they
            // queue, and name this computer to the server; a find fetched
            // into the library plays from its file.
            val player = openPlayer(
                settings,
                scope,
                { made?.connection?.client },
                { made?.connection?.headers.orEmpty() + parts.accounts.security.deviceHeaders() },
                { id -> made?.fetches?.landedId(id) },
                transitions = { made?.connection?.supports(OCTO_TRANSITIONS) == true },
                params = { made?.streamParams() ?: mapOf("format" to "raw") },
                kept = { id -> made?.offline?.localFile(id) },
                opened = parts.engine,
            )
            val app = AppState(settings, parts.accounts, parts.http, scope, os, player.player, restored = parts.restored, listeningRoot = places.config, updates = parts.updates, homeShelves = File(places.cache, "home")).also {
                made = it
                player.problem?.let { problem -> it.notice = problem }
            }
            app.playlistArt.folder = File(places.cache, "playlist-art")
            app.animated.shelf = LoopShelf(File(places.cache, "loops"), LOOP_SHELF_BYTES)
            app.coverImages = { SingletonImageLoader.get(PlatformContext.INSTANCE) }
            // Kept songs carry on fetching, and play from this computer.
            app.offline.start()
            val system = SystemIntegration(app, places, os, instance, inTray).also { app.toggleMiniPlayer = it::toggleMiniPlayer }
            return Opened(app, system, parts.updates)
        }
        if (ready != null) {
            System.getProperty(CHECK_PLAY)?.let { path ->
                LaunchedEffect(ready) {
                    checkSound(ready.app, File(path)) {
                        ready.system.close()
                        ready.app.player.close()
                        exitApplication()
                    }
                }
            }
            LaunchedEffect(ready) {
                // The covers of the song on and the next ones, ready ahead.
                launch { followCoversAhead(ready.app.player, { ready.app.connection?.client }, { SingletonImageLoader.get(PlatformContext.INSTANCE) }) }
                ready.system.quit = ::close
                ready.system.start(args.toList())
                ready.updates.start(ready.app.scope)
            }
        }
        // Covers load only once the app is made, so the client is ready.
        setSingletonImageLoaderFactory { context -> coverLoader(context, startup.now().http, places.cache) }

        Window(
            onCloseRequest = ::closeWindow,
            state = windowState,
            // Before the app is made: shown, unless it starts in the tray.
            visible = ready?.system?.windowVisible ?: !inTray,
            title = "Octo",
            undecorated = custom,
            onPreviewKeyEvent = { event ->
                val made = opened ?: return@Window false
                val app = made.app
                val system = made.system
                if (event.type != KeyEventType.KeyDown) return@Window false
                // Tab, the Menu key, and the arrows in a list, a menu or a
                // slider are the keyboard finding its way: rings show.
                val finding = event.key == Key.Tab || event.key == Key.Menu || (event.key == Key.F10 && event.isShiftPressed) ||
                    (event.key in WalkKeys && (lists.active || arrows.claimed || app.popups.open))
                if (finding) keyboard.keyboard = true
                // New keys for a global shortcut, being pressed in Settings.
                if (system.shortcuts.recording != null) {
                    return@Window system.shortcuts.pressed((event.nativeKeyEvent as? java.awt.event.KeyEvent)?.keyCode ?: 0, event.isCtrlPressed, event.isAltPressed, event.isShiftPressed, event.isMetaPressed)
                }
                val press = KeyPress(event.key, event.isCtrlPressed, event.isAltPressed, event.isShiftPressed, event.isMetaPressed)
                val shortcut = shortcutFor(press, app.mac, typing.active, lists.active, arrows = arrows.claimed || app.popups.open) ?: return@Window false
                app.perform(shortcut)
            },
        ) {
            // Before the window first draws, so its surfaces know their pixels.
            remember { useTextPixels(window, appTextPixels) }
            LaunchedEffect(Unit) {
                val drawn = withContext(Dispatchers.IO) { icons.get() }
                if (drawn.isNotEmpty()) window.iconImages = drawn
            }
            val own = remember { if (custom) Frame(window, windowState) else null }
            LaunchedEffect(Unit) {
                frame = own
                window.minimumSize = Dimension(MIN_WIDTH.toInt(), MIN_HEIGHT.toInt())
                if (os == DesktopOs.Mac) seeThroughMacTitleBar(window)
                if (own != null && os == DesktopOs.Windows) roundWindowsCorners(window)
                if (own != null && spot.maximized) own.maximize()
                // The first frame on screen, then the app: making it and
                // drawing it keep this thread busy a while.
                withTimeoutOrNull(FIRST_FRAME_WAIT_MS) {
                    withFrameNanos { }
                    withFrameNanos { }
                }
                val parts = startup.parts()
                // The octopus comes in while that work runs. Making the app
                // holds this thread, so it waits for the octopus to land
                // rather than freeze it part way; a tray start draws nothing
                // and never waits.
                if (!inTray) withTimeoutOrNull(OPENING_WAIT_MS) { snapshotFlow { entered }.first { it } }
                opened = open(parts)
            }
            if (ready != null) {
                LaunchedEffect(ready) {
                    val app = ready.app
                    val system = ready.system
                    system.watch(window)
                    // Music the server took in is looked for now and then
                    // while Octo runs, and on coming back to it; the library
                    // decides whether a look is due.
                    launch {
                        while (true) {
                            delay(NEW_MUSIC_LOOK_MS)
                            app.library?.look()
                        }
                    }
                    // Coming back to Octo is when a queue from the phone is worth a look.
                    window.addWindowFocusListener(object : WindowAdapter() {
                        override fun windowGainedFocus(e: WindowEvent?) {
                            app.queueSync.check()
                            app.library?.look()
                            Thread {
                                val calm = systemReducesMotion(os)
                                val text = systemTextScale(os)
                                SwingUtilities.invokeLater {
                                    systemCalm = calm
                                    systemText = text
                                }
                            }.apply { isDaemon = true }.start()
                        }
                    })
                    system.focusWindow = {
                        windowState.isMinimized = false
                        window.isVisible = true
                        window.toFront()
                        window.requestFocus()
                    }
                }
            }
            // Remembers the window's own size and place as it changes, and
            // saves it once it settles, so a crash does not lose it.
            LaunchedEffect(Unit) {
                snapshotFlow { Triple(windowState.position, windowState.size, maximizedNow() || windowState.placement != WindowPlacement.Floating) to windowState.isMinimized }
                    .debounce(700)
                    .collect { (where, minimized) ->
                        val (position, size, filled) = where
                        if (position is WindowPosition.Absolute && keepsSpot(minimized, filled, position.x.value, position.y.value)) {
                            floating = WindowSpot(position.x.value, position.y.value, size.width.value, size.height.value)
                        }
                        keepPlace()
                    }
            }
            // Whether the window fell back to drawing without the graphics card.
            var software by remember { mutableStateOf(false) }
            LaunchedEffect(Unit) {
                fun check() {
                    software = window.renderApi == GraphicsApi.SOFTWARE_FAST || window.renderApi == GraphicsApi.SOFTWARE_COMPAT
                }
                check()
                window.onRenderApiChanged(::check)
            }
            Box(Modifier.fillMaxSize()) {
            if (ready != null) {
                val app = ready.app
                val system = ready.system
                val look by app.settings.state.collectAsState()
                // Every word grows with the text size; nothing else does.
                val density = LocalDensity.current
                val words = textScale(look.appearance.textSize, systemText)
                ProvideWindowLook(reduceMotion = look.appearance.calmMotion || systemCalm, focus = keyboard, arrows = arrows) {
                    CompositionLocalProvider(
                        LocalDensity provides Density(density.density, density.fontScale * words),
                        LocalTyping provides typing,
                        LocalSystem provides system,
                        LocalListFocus provides lists,
                        LocalWindowShown provides (system.windowVisible && !windowState.isMinimized),
                        LocalSoftwareDrawing provides software,
                    ) {
                        AudioDropZone(system::openFiles) { Shell(app, own, ::closeWindow) }
                    }
                }
            }
            // Over the app until it has drawn, then fading away.
            if (!openingGone) {
                Opening(octopus, calm = calmStart, leaving = ready != null, onEntered = { entered = true }, onGone = { openingGone = true })
            }
            }
        }
        if (ready != null) with(ready.system) { Surfaces(null) }
    }
}

// The keys that walk a list or a menu.
private val WalkKeys = setOf(Key.DirectionUp, Key.DirectionDown, Key.DirectionLeft, Key.DirectionRight, Key.PageUp, Key.PageDown, Key.MoveHome, Key.MoveEnd)
