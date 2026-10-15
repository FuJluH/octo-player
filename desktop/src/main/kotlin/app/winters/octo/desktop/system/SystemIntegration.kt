package app.winters.octo.desktop.system

import app.winters.octo.desktop.pages.openFamilyLink
import app.winters.octo.subsonic.parseFamilyLink
import androidx.compose.runtime.Composable
import androidx.compose.runtime.Stable
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue
import androidx.compose.runtime.staticCompositionLocalOf
import androidx.compose.ui.graphics.painter.Painter
import androidx.compose.ui.window.ApplicationScope
import androidx.compose.ui.window.TrayState
import androidx.compose.ui.window.isTraySupported
import app.winters.octo.desktop.AppState
import app.winters.octo.desktop.drawnStationPicture
import app.winters.octo.desktop.liveSongCover
import androidx.compose.runtime.snapshotFlow
import app.winters.octo.desktop.audio.CHECK_PLAY
import app.winters.octo.desktop.settings.AppPlaces
import app.winters.octo.desktop.settings.DesktopOs
import app.winters.octo.desktop.settings.systemReducesMotion
import app.winters.octo.desktop.window.screenAreas
import app.winters.octo.desktop.discord.DiscordArt
import app.winters.octo.desktop.discord.DiscordArtwork
import app.winters.octo.desktop.discord.artQueryOf
import app.winters.octo.desktop.discord.DiscordPresence
import app.winters.octo.desktop.discord.DiscordSync
import app.winters.octo.desktop.discord.discordActivityFor
import app.winters.octo.desktop.discord.discordAppId
import app.winters.octo.desktop.discord.discordPipes
import app.winters.octo.desktop.hotkeys.GlobalShortcuts
import app.winters.octo.desktop.hotkeys.HotkeyAction
import app.winters.octo.desktop.hotkeys.HotkeyBackend
import app.winters.octo.desktop.nav.VOLUME_STEP
import app.winters.octo.desktop.ui.anyOutside
import kotlinx.coroutines.delay
import kotlinx.coroutines.flow.collectLatest
import kotlinx.coroutines.flow.combine
import kotlinx.coroutines.flow.distinctUntilChanged
import kotlinx.coroutines.flow.map
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.launch
import java.awt.Desktop
import java.awt.EventQueue
import java.awt.desktop.AppReopenedListener
import java.awt.event.WindowAdapter
import java.awt.event.WindowEvent
import app.winters.octo.desktop.family.FamilyWatch
import app.winters.octo.desktop.family.NoticeFile
import java.io.File

// The system integration, for the settings page and the now-playing bar.
val LocalSystem = staticCompositionLocalOf<SystemIntegration?> { null }

// Everything that ties Octo into the operating system: the media controls
// and media keys, the tray icon and its menu, notifications, the mini
// player, files and links handed over by later launches or dropped on the
// window, and pausing when the machine goes to sleep.
@Stable
class SystemIntegration(
    private val app: AppState,
    places: AppPlaces,
    val os: DesktopOs,
    private val instance: SingleInstance?,
    // Started with --tray (at sign-in, when asked to): the window waits in
    // the tray until opened from there.
    startInTray: Boolean = false,
    // Where global shortcuts are claimed; the system's own unless a test
    // hands in a pretend one.
    hotkeys: HotkeyBackend? = null,
) : AutoCloseable {
    val controls: SystemMediaControls = when (os) {
        DesktopOs.Windows -> NativeMediaControls.load("System media controls") ?: NoMediaControls()
        DesktopOs.Mac -> NativeMediaControls.load("Now Playing") ?: NoMediaControls()
        DesktopOs.Linux -> LinuxMediaControls(app.player::positionMs)
    }

    private val serverCovers = ServerCovers(
        app.http,
        { app.connection?.client },
        File(places.cache, "now-playing"),
        images = { app.coverImages?.invoke() },
        drawn = { name, stream -> app.drawnStationPicture(name, stream) },
    )

    private val session = MediaSession(
        player = app.player,
        controls = controls,
        // A station's song on air shows its cover from Octo once found there.
        covers = object : CoverSource by serverCovers {
            override suspend fun live(now: NowPlaying): CoverArt? =
                app.liveSongCover(now.title, now.artist)?.let { serverCovers.load(it) } ?: serverCovers.live(now)
        },
        scope = app.scope,
        others = ::otherEvent,
    )

    private val sleepWatch = if (os == DesktopOs.Linux) LinuxSleepWatch() else null

    val trayAvailable: Boolean = runCatching { isTraySupported }.getOrDefault(false)
    val trayState = TrayState()
    // The tray's icon, drawn from the vector at the size the tray asks for.
    val trayIcon: Painter? = OctoIconPainter(FlatShape)

    private val notifier: Notifier? = when {
        os == DesktopOs.Linux -> LinuxNotifier(null)
        trayAvailable -> TrayNotifier(trayState)
        else -> null
    }
    private val notices = NowPlayingNotices()

    val notificationsAvailable: Boolean get() = notifier != null

    // The song in the listener's Discord status, in a build that carries
    // Octo's Discord application; null otherwise.
    val discord: DiscordPresence? = discordAppId()?.let { id -> DiscordPresence(DiscordSync(id, discordPipes(os))) }

    // Whether Discord is open and showing Octo's status, for the settings page.
    var discordConnected by mutableStateOf(false)
        private set

    // Keys that reach Octo from any app (Windows only for now).
    val shortcuts = if (hotkeys != null) GlobalShortcuts(app.settings, app.scope, os, ::onShortcut, hotkeys) else GlobalShortcuts(app.settings, app.scope, os, ::onShortcut)

    // Whether the media keys reach Octo, for the settings page.
    var mediaKeysWork by mutableStateOf(false)
        private set

    // The main window: shown or hidden in the tray, and in front or not.
    var windowVisible by mutableStateOf(!(startInTray && trayAvailable))
        private set
    private var windowInFront = true

    var miniPlayerOpen by mutableStateOf(app.settings.current.system.miniPlayerOpen)
        private set

    // Set by the window: bring it forward, and quit the app.
    var focusWindow: () -> Unit = {}
    var quit: () -> Unit = {}

    // Closing the window keeps Octo in the tray, when there is a tray.
    val closesToTray: Boolean get() = trayAvailable && app.settings.current.system.closeToTray

    // The Windows taskbar button, jump list and starting at sign-in.
    val shell = ShellIntegration(app, os, places.config)

    // Family requests told as notifications, and a family link offered from
    // the clipboard.
    val family = FamilyWatch(app, NoticeFile(File(places.config, "family-notices.json")), show = { notice -> notifier?.show(notice.title, notice.text) })

    fun start(launchArgs: List<String>) {
        session.start { works -> mediaKeysWork = works }
        app.scope.launch { snapshotFlow { app.liveHeart.match }.collect { if (it != null) session.refreshCover() } }
        shell.start()
        family.start()
        startDiscord()
        shortcuts.start()
        // The system bus can be slow to answer, so it is reached off the window's thread.
        sleepWatch?.let { watch -> app.scope.launch(Dispatchers.IO) { watch.start { event -> app.scope.launch { session.handle(event) } } } }
        app.scope.launch {
            app.player.state.collect { state ->
                val notice = notices.noticeFor(nowPlayingOf(state), app.settings.current.system.nowPlayingNotices, windowVisible && windowInFront)
                notice?.let { (title, text) -> notifier?.show(title, text) }
            }
        }
        instance?.onLaunch { args -> app.scope.launch { arrived(args) } }
        // octo:// links open the installed app (macOS knows from the app's details).
        if (System.getProperty(CHECK_PLAY) == null) installedProgram()?.let { program ->
            app.scope.launch(Dispatchers.IO) {
                when (os) {
                    DesktopOs.Windows -> registerLinksOnWindows(program)
                    DesktopOs.Linux -> registerWithLinuxDesktop(program, linuxApplicationsFolder())
                    DesktopOs.Mac -> Unit
                }
            }
        }
        listenToMac()
        open(parseLaunchArgs(launchArgs))
    }

    // A later launch handed its command line over. One that only plays
    // from the jump list, or starts in the tray, leaves the window be.
    private fun arrived(args: List<String>) {
        if (launchWantsWindow(args)) raise()
        open(parseLaunchArgs(args))
    }

    // On macOS files and links come as events, not on the command line, and
    // a click on the Dock icon should bring a hidden window back. Quitting
    // from the menu or with Cmd+Q goes through the app's own quit, which
    // saves and lets go of everything, before macOS ends it.
    private fun listenToMac() {
        if (os != DesktopOs.Mac || !Desktop.isDesktopSupported()) return
        val desktop = Desktop.getDesktop()
        runCatching { desktop.setOpenFileHandler { event -> app.scope.launch { open(parseLaunchArgs(event.files.map { it.path })) } } }
        runCatching { desktop.setOpenURIHandler { event -> app.scope.launch { raise(); open(parseLaunchArgs(listOf(event.uri.toString()))) } } }
        runCatching { desktop.addAppEventListener(AppReopenedListener { app.scope.launch { raise() } }) }
        runCatching {
            desktop.setQuitHandler { _, response ->
                EventQueue.invokeLater {
                    try {
                        quit()
                    } finally {
                        response.performQuit()
                    }
                }
            }
        }
    }

    // Plays opened files as one-off songs, or follows a link.
    fun open(requests: List<LaunchRequest>) {
        for (request in requests) {
            when (request) {
                is LaunchRequest.OpenFiles -> app.play(request.files.map(::openedFileSong))
                is LaunchRequest.OpenLink -> {
                    // A family link joins this computer to the family.
                    parseFamilyLink(request.link)?.let { link ->
                        app.openFamilyLink(link)
                        continue
                    }
                    val page = pageForLink(request.link)
                    val play = playLinkOf(request.link)
                    when {
                        play != null -> shell.play(play.first, play.second)
                        page == null -> app.notice = "Octo doesn't know that link."
                        app.connection == null -> app.notice = "Sign in to open that link."
                        else -> {
                            app.fullPlayer = false
                            app.navigator.go(page)
                        }
                    }
                }
            }
        }
    }

    fun openFiles(files: List<File>) = open(listOf(LaunchRequest.OpenFiles(files)))

    private fun otherEvent(event: SystemEvent) {
        when (event) {
            SystemEvent.Raise -> raise()
            SystemEvent.Quit -> quit()
            is SystemEvent.SetVolume -> app.setVolume(event.volume)
            is SystemEvent.OpenUri -> open(parseLaunchArgs(listOf(event.uri)))
            else -> {}
        }
    }

    fun raise() {
        windowVisible = true
        focusWindow()
    }

    fun hideWindow() {
        windowVisible = false
    }

    fun toggleMiniPlayer() = setMiniPlayer(!miniPlayerOpen)

    // The mini player stands in for the window: opening it puts the window
    // away, and closing it brings the window back.
    fun setMiniPlayer(open: Boolean) {
        if (open == miniPlayerOpen) return
        miniPlayerOpen = open
        app.settings.update { it.copy(system = it.system.copy(miniPlayerOpen = open)) }
        if (open) hideWindow() else raise()
    }

    // Tells Discord what plays, as it changes and every few seconds (a seek
    // moves the times), while the listener has it on.
    private fun startDiscord() {
        val presence = discord ?: return
        presence.onConnected = { connected -> app.scope.launch { discordConnected = connected } }
        presence.start()
        val art = DiscordArt()
        // The song the status last moved to, and when, so a new song can
        // wait a moment for its pictures.
        var song: Long? = null
        var songSince = 0L
        fun tell() {
            val prefs = app.settings.current.discord
            val state = app.player.state.value
            val now = nowPlayingOf(state)
            val clock = System.currentTimeMillis()
            // A station naming no song has no pictures to look up.
            val query = now?.takeUnless { it.live && !it.liveNamed }?.let { artQueryOf(it) }
            val pictures = query?.let { art.known(it) } ?: DiscordArtwork()
            val shown = discordActivityFor(now, app.player.positionMs(), clock, prefs, pictures)
            if (now?.entryKey != song) {
                song = now?.entryKey
                songSince = clock
                // Told again once the wait is over, found or not.
                if (shown != null) app.scope.launch {
                    delay(PICTURE_HOLD_MS)
                    tell()
                }
            }
            // A new song waits a moment for its pictures, as Cider waits for
            // its artwork, so its status goes out once and whole rather than
            // with Octo's icon first (Discord then takes seconds to change it).
            val holding = shown != null && query != null && clock - songSince < PICTURE_HOLD_MS && art.pending(query, prefs)
            if (!holding) presence.want(prefs.on, shown)
            // A picture not looked for yet is fetched once, then the status is told again.
            // Only for a song that shows: a file kept private never has its names sent anywhere.
            if (shown != null && query != null && art.wants(query, prefs)) {
                app.scope.launch {
                    art.look(query, prefs)
                    tell()
                }
            }
            // The next song's pictures, ahead of time, so they are there when it starts.
            val next = state.upcoming.firstOrNull()?.song
            if (shown != null && next != null && (!isOpenedFile(next.id) || prefs.openedFiles)) {
                val ahead = artQueryOf(next)
                if (art.wants(ahead, prefs)) app.scope.launch { art.look(ahead, prefs) }
            }
        }
        app.scope.launch { app.player.state.collect { tell() } }
        app.scope.launch { app.settings.state.map { it.discord }.distinctUntilChanged().collect { tell() } }
        // Kept in step while a song plays and the status is on; otherwise
        // nothing moves, so nothing is looked at.
        app.scope.launch {
            combine(app.player.state.map { it.playing }, app.settings.state.map { it.discord.on }) { playing, on -> playing && on }
                .distinctUntilChanged()
                .collectLatest { moving ->
                    while (moving) {
                        delay(DISCORD_CHECK_MS)
                        tell()
                    }
                }
        }
    }

    // A global shortcut was pressed.
    private fun onShortcut(action: HotkeyAction) {
        val player = app.player
        when (action) {
            HotkeyAction.PlayPause -> player.togglePlay()
            HotkeyAction.Next -> player.next()
            HotkeyAction.Previous -> player.previous()
            HotkeyAction.VolumeUp -> app.setVolume((player.state.value.volume + VOLUME_STEP).coerceAtMost(1f))
            HotkeyAction.VolumeDown -> app.setVolume((player.state.value.volume - VOLUME_STEP).coerceAtLeast(0f))
            HotkeyAction.ShowHide -> if (windowVisible && windowInFront) putWindowAway() else raise()
            HotkeyAction.MiniPlayer -> toggleMiniPlayer()
            HotkeyAction.Like -> player.state.value.current?.song?.let { song ->
                if (!isOpenedFile(song.id) && !app.anyOutside(listOf(song))) app.setStarred(listOf(song), !app.isStarred(song))
            }
        }
    }

    // Hides the window in the tray where there is one, and to the taskbar
    // where there is not, so it can always be found again.
    private fun putWindowAway() {
        if (trayAvailable) {
            hideWindow()
        } else {
            (mainWindow as? java.awt.Frame)?.let { it.extendedState = it.extendedState or java.awt.Frame.ICONIFIED }
        }
    }

    fun onTray(action: TrayAction) {
        when (action) {
            TrayAction.PlayPause -> app.player.togglePlay()
            TrayAction.Next -> app.player.next()
            TrayAction.Previous -> app.player.previous()
            TrayAction.ShowWindow -> raise()
            TrayAction.MiniPlayer -> toggleMiniPlayer()
            TrayAction.Quit -> quit()
        }
    }

    private var mainWindow: java.awt.Window? = null

    // Whether the system asks for less motion, read once, for the mini player.
    private val systemCalm by lazy { systemReducesMotion(os) }

    // Follows the window's focus, for the notices, and takes on its
    // taskbar button.
    fun watch(window: java.awt.Window) {
        mainWindow = window
        shell.attach(window)
        window.addWindowFocusListener(object : WindowAdapter() {
            override fun windowGainedFocus(e: WindowEvent?) {
                windowInFront = true
                app.windowCameBack()
                family.offerClipboard()
            }

            override fun windowLostFocus(e: WindowEvent?) {
                windowInFront = false
            }
        })
    }

    // The tray icon and the mini player, which live beside the main window.
    @Composable
    fun ApplicationScope.Surfaces(windowIcon: Painter?) {
        val state by app.player.state.collectAsState()
        val now = nowPlayingOf(state)
        val icon = trayIcon ?: windowIcon
        if (trayAvailable && icon != null) {
            OctoTray(icon, trayState, now, miniPlayerOpen, ::onTray)
        }
        if (miniPlayerOpen) {
            val spot = placeMiniPlayer(app.settings.current.system.miniPlayer, screenAreas())
            val settings by app.settings.state.collectAsState()
            MiniPlayerWindow(
                app = app,
                spot = spot,
                os = os,
                icon = windowIcon,
                onMoved = { moved -> app.settings.update { it.copy(system = it.system.copy(miniPlayer = moved)) } },
                onClose = { setMiniPlayer(false) },
                reduceMotion = settings.appearance.calmMotion || systemCalm,
            )
        }
    }

    // The listener for later launches goes first, so a launch made while
    // quitting starts its own Octo instead of being taken and lost.
    override fun close() {
        runCatching { instance?.close() }
        runCatching { shell.close() }
        runCatching { session.close() }
        runCatching { sleepWatch?.close() }
        runCatching { notifier?.close() }
        runCatching { discord?.close() }
        runCatching { shortcuts.close() }
    }
}

// How often the Discord status is checked against the player (for seeks).
private const val DISCORD_CHECK_MS = 3_000L

// How long a new song's Discord status waits for its pictures at most.
private const val PICTURE_HOLD_MS = 1_500L
