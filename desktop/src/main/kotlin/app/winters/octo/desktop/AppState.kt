package app.winters.octo.desktop

import app.winters.octo.animated.AnimatedArtSetting
import app.winters.octo.desktop.animated.AnimatedArtModel
import app.winters.octo.desktop.animated.KeptLoops
import app.winters.octo.desktop.animated.PowerSaving
import app.winters.octo.desktop.settings.animatedArtSetting
import app.winters.octo.subsonic.AnimatedArtAnswer
import app.winters.octo.subsonic.OCTO_ANIMATED_ART
import app.winters.octo.serverupdate.LaterStore
import app.winters.octo.serverupdate.ServerUpdateHttp
import app.winters.octo.serverupdate.ServerUpdateWatcher
import app.winters.octo.serverupdate.ownAddresses
import app.winters.octo.ui.family.streamParams as streamParamsFor
import app.winters.octo.ui.family.appPicksQuality
import app.winters.octo.subsonic.StreamQuality
import app.winters.octo.desktop.offline.DesktopOffline
import androidx.compose.runtime.Stable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateMapOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue
import androidx.compose.runtime.snapshots.Snapshot
import androidx.compose.runtime.snapshots.SnapshotApplyResult
import androidx.compose.ui.focus.FocusRequester
import app.winters.octo.design.PopupHost
import app.winters.octo.desktop.audio.SoundTarget
import app.winters.octo.desktop.health.HealthModel
import app.winters.octo.desktop.home.HomeStore
import app.winters.octo.desktop.home.KeptShelves
import app.winters.octo.desktop.library.LibraryState
import app.winters.octo.home.HomeShelfStore
import app.winters.octo.home.homeSectionOrder
import app.winters.octo.desktop.library.LibraryStore
import app.winters.octo.desktop.listening.PlayReporter
import app.winters.octo.desktop.livelists.LiveListStore
import app.winters.octo.desktop.listening.listeningFolder
import app.winters.octo.desktop.lyrics.LyricsModel
import app.winters.octo.desktop.lyrics.LyricsSources
import app.winters.octo.desktop.nav.Navigator
import app.winters.octo.desktop.nav.Page
import app.winters.octo.desktop.nav.SEEK_STEP_MS
import app.winters.octo.desktop.nav.Shortcut
import app.winters.octo.desktop.nav.VOLUME_STEP
import app.winters.octo.desktop.pages.SignInForm
import app.winters.octo.desktop.player.DEFAULT_OUTPUT
import app.winters.octo.desktop.player.DesktopPlayer
import app.winters.octo.desktop.player.SilentPlayer
import app.winters.octo.desktop.player.SleepTimer
import app.winters.octo.desktop.player.wash.WashCovers
import app.winters.octo.desktop.queue.Autoplay
import app.winters.octo.desktop.queue.QueueKeeper
import app.winters.octo.desktop.queue.ServerQueueSync
import app.winters.octo.desktop.queue.autoplaySongs
import app.winters.octo.desktop.queue.queueNameFor
import app.winters.octo.desktop.search.COMMAND_MARK
import app.winters.octo.playback.QueueSource
import kotlinx.coroutines.flow.SharingStarted
import kotlinx.coroutines.flow.stateIn
import app.winters.octo.desktop.search.Fetches
import app.winters.octo.desktop.upgrade.UpgradeModel
import app.winters.octo.desktop.downloads.DownloadsModel
import kotlinx.coroutines.delay
import app.winters.octo.desktop.search.OmniboxState
import app.winters.octo.desktop.search.SearchModel
import app.winters.octo.desktop.search.SearchFilter
import app.winters.octo.desktop.liveradio.FoundSong
import app.winters.octo.desktop.liveradio.LiveHeart
import app.winters.octo.desktop.search.FetchPhase
import app.winters.octo.ui.family.outsideActions
import app.winters.octo.playback.stoppedLine
import app.winters.octo.playback.isRadio
import app.winters.octo.desktop.server.Accounts
import app.winters.octo.desktop.server.Connection
import app.winters.octo.desktop.server.ServerFactsModel
import app.winters.octo.desktop.server.SwitchOutcome
import app.winters.octo.desktop.settings.SavedServer
import app.winters.octo.desktop.settings.key
import app.winters.octo.desktop.settings.name
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import app.winters.octo.desktop.server.userMessage
import app.winters.octo.desktop.settings.DesktopOs
import app.winters.octo.desktop.settings.FramePrefs
import app.winters.octo.desktop.settings.SettingsStore
import app.winters.octo.desktop.settings.TablePrefs
import app.winters.octo.desktop.sound.SoundController
import app.winters.octo.desktop.system.JumpListHooks
import app.winters.octo.desktop.system.jumpTargetFor
import app.winters.octo.desktop.system.openInBrowser
import app.winters.octo.desktop.update.DesktopUpdates
import app.winters.octo.lyrics.OnlineLyrics
import app.winters.octo.playback.skippedLine
import app.winters.octo.server.switchNotice
import app.winters.octo.sort.SortList
import app.winters.octo.sort.SortOrder
import app.winters.octo.subsonic.FORM_POST_EXTENSION
import app.winters.octo.subsonic.Playlist
import app.winters.octo.subsonic.Song
import app.winters.octo.subsonic.SubsonicException
import app.winters.octo.ui.family.FamilyModel
import app.winters.octo.ui.imports.ImportModel
import app.winters.octo.ui.search.withRecent
import app.winters.octo.desktop.library.PlaylistArtStore
import java.io.File
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.CoroutineStart
import kotlinx.coroutines.Job
import kotlinx.coroutines.flow.distinctUntilChanged
import kotlinx.coroutines.flow.filterIsInstance
import kotlinx.coroutines.flow.map
import kotlinx.coroutines.launch
import coil3.ImageLoader
import okhttp3.OkHttpClient
import app.winters.octo.desktop.queue.StationRefill
import app.winters.octo.playback.STATION_BATCH
import app.winters.octo.playback.isStationId
import app.winters.octo.subsonic.OCTO_STATIONS
import app.winters.octo.desktop.liveradio.LiveRadioModel
import app.winters.octo.liveradio.RadioBrowser

// How long a notice said in passing stays up.
const val PASSING_NOTICE_MS = 6_000L

// The panel that can open on the right of the main area.
enum class SidePanel(val key: String) {
    Queue("queue"),
    Lyrics("lyrics"),
    Info("info"),

    // The downloads drawer, on a server that keeps a log of its downloads.
    Downloads("downloads"),
    ;

    companion object {
        fun of(key: String?) = entries.firstOrNull { it.key == key }
    }
}

// Everything the window shares: the settings, the server, the player,
// where the listener is, and the actions every page offers on songs.
@Stable
class AppState(
    val settings: SettingsStore,
    val accounts: Accounts,
    val http: OkHttpClient,
    val scope: CoroutineScope,
    val os: DesktopOs,
    val player: DesktopPlayer = SilentPlayer(scope = scope, volume = settings.current.playback.volume),
    // The online lyrics library; tests give one at a pretend address.
    lyricsLibrary: OnlineLyrics = OnlineLyrics(http),
    // The saved server, read from the password store before the window
    // opens, since the store can keep the caller waiting.
    restored: Connection? = accounts.restore(),
    // Where each account's plays and queue are kept, or null to keep none
    // (the screenshot tests).
    private val listeningRoot: File? = null,
    // Looking for new versions of Octo; none in the tests and screenshots.
    val updates: DesktopUpdates? = null,
    // Where Home's server shelves are kept for each account, or null to
    // keep none (the tests and screenshots).
    homeShelves: File? = null,
    // Opens a web page for the Import page; the screenshots open none.
    browse: (String) -> Unit = { openInBrowser(it) },
    // The live radio catalog; tests give one at a pretend address.
    radioCatalog: RadioBrowser = RadioBrowser(catalogHttp(http), liveRadioAgent()),
) {
    // Opens a web page in the listener's browser.
    val openUrl: (String) -> Unit = browse

    // The Sound page's settings, kept on the engine; none for the silent player.
    val sound: SoundController? = (player as? SoundTarget)?.let { SoundController(it, settings, scope) }

    // The sleep timer: a countdown with a fade, or stop after some songs.
    val sleep = SleepTimer(player, scope)

    // The lyrics of the song playing, for the side panel and the full player.
    val lyrics = LyricsModel(player, LyricsSources({ connection }, http, lyricsLibrary, settings, player.lengths), settings, scope)

    val navigator = Navigator()
    val popups = PopupHost()
    val searchFocus = FocusRequester()

    // Whether the keyboard is in the side panel, where Escape closes it.
    var panelHasKeyboard by mutableStateOf(false)

    // Bumped by the search shortcut, so a Search page already open brings
    // its field back into view.
    var searchAsks by mutableStateOf(0)
        private set

    var connection by mutableStateOf<Connection?>(null)
        private set

    // The kept server being switched to, while it is asked whether it
    // answers; none otherwise.
    var switching by mutableStateOf<SavedServer?>(null)
        private set

    // The sign-in page's fields, started from the server signed in to last.
    var signInForm by mutableStateOf(SignInForm(accounts.last))
        private set
    var library by mutableStateOf<LibraryStore?>(null)
        private set
    var fetches by mutableStateOf<Fetches?>(null)
        private set

    // "Find higher quality" on an Octo server; null on any other.
    var upgrades by mutableStateOf<UpgradeModel?>(null)
        private set

    // The downloads drawer on an Octo server; null on any other.
    var downloads by mutableStateOf<DownloadsModel?>(null)
        private set
    var search by mutableStateOf<SearchModel?>(null)
        private set
    var home by mutableStateOf<HomeStore?>(null)
        private set

    // The Library health page's report, its fixes and what the server lets
    // this user do to its files (deleting from disk too), for this sign-in.
    val health = HealthModel({ connection?.client }, scope)

    // The Import page, on an Octo server.
    val imports = ImportModel({ connection?.client }, scope, openUrl = browse)

    // Live radio near the listener, from the Radio Browser catalog, and the
    // stations kept on this computer.
    val liveRadio = LiveRadioModel(settings, radioCatalog, { connection }, scope)

    // The live player's heart, for the song a station has on air.
    val liveHeart = LiveHeart(
        scope,
        find = { query -> search?.search(query, SearchFilter.Songs)?.let { found -> found.library.songs.map { FoundSong(it, true) } + found.outside.songs.map { FoundSong(it, false) } } },
        star = { song, on -> setStarred(listOf(fetches?.landedId(song.id)?.let { id -> song.copy(id = id) } ?: song), on) },
        missed = { _, query -> searchFor(query) },
        // Octo downloads a song found online once asked; a family member
        // who saves songs saves it instead.
        add = { song ->
            val fetching = fetches
            if (fetching != null && outsideActions(family.me).addLabel == null) fetching.request(song.id) else setStarred(listOf(song), true)
        },
        landed = { song -> fetches?.phase(song.id) == FetchPhase.Done },
    )

    // Family, on an Octo server with it on: the account's abilities, which song actions and
    // the Family page follow.
    val family = FamilyModel({ connection?.client }, { connection?.family == true }, scope)

    // The animated art kept with downloaded albums.
    private val keptLoops: KeptLoops = KeptLoops(http) { offline.folder }

    // Songs kept on this computer to play without a connection.
    val offline = DesktopOffline(
        settings,
        http,
        scope,
        File(System.getProperty("user.home"), "Music${File.separator}Octo offline"),
        { connection },
        { library?.index?.songs },
        family,
        { words -> notice = words },
        keptLoops,
        askArt = { artAsker() },
    )

    // How to ask the server in use about an album's animated art, for the
    // albums kept here; none when it offers none or the setting is Off.
    private fun artAsker(): (suspend (String) -> AnimatedArtAnswer)? {
        val now = connection ?: return null
        if (settings.current.appearance.animatedArtSetting == AnimatedArtSetting.Off || !now.supports(OCTO_ANIMATED_ART)) return null
        return { id -> now.client.animatedArt(id) }
    }

    // Animated album covers on the server in use, and their loop files.
    val animated = AnimatedArtModel(http, scope, { connection }, keptLoops, PowerSaving(os).also { it.start(scope) })

    // What a stream asks the server for: this app's own quality without a
    // family, or when this device is left to the app; otherwise the file as
    // it is, and the server applies the account's choice.
    fun streamParams(): Map<String, String> {
        val quality = StreamQuality.entries.firstOrNull { it.name == settings.current.playback.streamQuality } ?: StreamQuality.Original
        return streamParamsFor(appPicksQuality(connection?.family == true, family.deviceMode), quality)
    }


    // How the kept servers answer, and the scan and user of the one in use,
    // for Settings > Servers.
    val serverFacts = ServerFactsModel(accounts, { connection }, scope)

    // A newer Octo for the server in use, for its admin, and updating it.
    // Once an update followed here is in, the server's facts are read again.
    val serverUpdate = ServerUpdateWatcher(
        scope,
        object : LaterStore {
            override suspend fun dismissed(server: String): String? = settings.current.serverUpdateLater[server]

            override suspend fun dismiss(server: String, tag: String) {
                settings.update { it.copy(serverUpdateLater = it.serverUpdateLater + (server to tag)) }
            }
        },
        onFinished = { serverFacts.refresh() },
    )

    // Asked only at the server's own addresses, signed as every other call.
    private val serverUpdateCalls = ServerUpdateHttp(http) { connection?.let { ownAddresses(it.client, it.headers) } }

    private fun followServerUpdate(connection: Connection?) {
        serverUpdate.bind(connection?.takeIf { it.isOcto }?.server?.id, serverUpdateCalls)
    }

    // Octo's dashboard on the server in use, for what the app leaves to it.
    fun openDashboard() {
        val base = connection?.client?.baseUrl ?: return
        openUrl(base.newBuilder().encodedPath("/admin/").query(null).build().toString())
    }

    // The user's playlists, for the sidebar and "Add to playlist".
    var playlists by mutableStateOf<List<Playlist>>(emptyList())
        private set

    private val keptShelves = homeShelves?.let { HomeShelfStore(it, KeptShelves.serializer()) }

    var sidePanel by mutableStateOf(SidePanel.of(settings.current.sidePanel))
        private set

    var fullPlayer by mutableStateOf(false)

    // What the full player shows beside the cover: the lyrics, the queue,
    // or nothing.
    var playerPanel by mutableStateOf<SidePanel?>(SidePanel.Lyrics)
        private set

    fun togglePlayerPanel(panel: SidePanel) {
        playerPanel = if (playerPanel == panel) null else panel
    }

    // The app's image loader, for what needs a cover outside a picture on
    // screen (the background, the system's player). Main sets it; with none
    // they download covers themselves.
    var coverImages: (() -> ImageLoader)? = null

    // Covers made ready for the full player's background.
    val washCovers = WashCovers(http, images = { coverImages?.invoke() })

    // Playlists' designed covers; Main gives them a folder in the cache.
    val playlistArt = PlaylistArtStore(http)

    // One quiet line at the top of the main area, for something the
    // listener should know once (never a stack of toasts).
    var notice by mutableStateOf<String?>(null)

    // Hearts set or cleared here, shown before the server's lists catch up.
    private val starOverrides = mutableStateMapOf<String, Boolean>()

    // Ratings set here, from 0 (none) to 5 stars, shown the same way. The
    // menus read and set them through ratingOf and setRating (SongActions.kt).
    internal val ratingOverrides = mutableStateMapOf<String, Int>()

    // The search box at the top of the sidebar: open or not, and its line.
    val omnibox = OmniboxState()

    // Keeps a search that led somewhere, as the phone does.
    fun rememberSearch(text: String) =
        settings.update { it.copy(recentSearches = withRecent(it.recentSearches, text)) }

    fun forgetSearches() = settings.update { it.copy(recentSearches = emptyList()) }

    // Opens the search box with the keyboard in it, for commands only with
    // `commands`.
    fun openSearch(commands: Boolean = false) {
        fullPlayer = false
        if (commands) search?.type(COMMAND_MARK)
        omnibox.open = true
        omnibox.highlight = 0
        runCatching { searchFocus.requestFocus() }
    }

    // Opens or closes the mini player; the system side sets it.
    var toggleMiniPlayer: (() -> Unit)? = null

    // The Windows jump list, told what is played; null where there is none.
    // The system side sets it.
    var jumpList: JumpListHooks? = null

    // Songs that could not play this run, by id, with why, for their rows.
    val failedSongs = mutableStateMapOf<String, String>()

    // The engine's own words for the notice's last failure, shown on asking.
    var noticeDetail by mutableStateOf<String?>(null)

    // Plays reach the server and this computer's play log; the queue is
    // kept on disk and on the server.
    val plays = PlayReporter(player, settings, { connection }, listeningRoot, scope)
    val queueKeeper = QueueKeeper(player, scope)
    val queueSync = ServerQueueSync(player, settings, { connection }, scope)

    val mac: Boolean get() = os == DesktopOs.Mac

    // The filter field of the page on screen, when it has one (the song
    // lists' filter bar sets it while shown), so the find shortcut can go
    // there before the sidebar's search.
    var pageFilterFocus: FocusRequester? = null

    // Playlists as last read or changed here, for their pages, so an edit
    // shows at once and goes back if the server refuses it. Each is kept
    // with the server it came from. See PlaylistActions.kt.
    internal val playlistViews = mutableStateMapOf<String, PlaylistView>()

    // How many edits of each playlist are on their way to the server. A
    // fresh read is not shown until none are, so it cannot undo one.
    internal val playlistSaves = mutableStateMapOf<String, Int>()

    // ---- The queue's edits and Autoplay (see QueueActions.kt) ----

    // A word the notice line offers beside its text, like Undo after a
    // queue edit; shown only while the notice is still the one it came with.
    var noticeAction by mutableStateOf<NoticeAction?>(null)

    // Keeps a station going, on a server that sends a station's next songs.
    val stationRefill = StationRefill(
        player,
        scope,
        supported = { connection?.supports(OCTO_STATIONS) == true },
        more = { id, after -> connection?.client?.stationSongs(id, STATION_BATCH, after).orEmpty() },
    ).also { it.start() }

    // Keeps music playing when the queue runs out, when the listener wants it.
    val autoplay = Autoplay(
        player,
        settings.state.map { it.playback.autoplay }.stateIn(scope, SharingStarted.Eagerly, settings.current.playback.autoplay),
        scope,
        pick = { seed, exclude ->
            val recent = player.state.value.queue.takeLast(30)
            val before = recent.map { it.song }
            // The listener's own songs keep Autoplay near their taste.
            val anchors = recent.filter { it.source != QueueSource.Autoplay && it.song.id != seed.id }.map { it.song }.takeLast(10).reversed()
            withContext(Dispatchers.Default) {
                autoplaySongs(
                    seed, exclude, connection?.client, library?.index, before, anchors,
                    rating = { ratingOf(it) }, tuning = settings.current.playback.radioTuning,
                    libraryOnly = settings.current.libraryOnly,
                )
            }
        },
        standsDown = stationRefill::keepsGoing,
        standsDownChanged = stationRefill.settled,
    ).also { it.start() }

    // ---- End of the queue's edits ----

    // The account's live lists: songs picked by rules, kept on this
    // computer (see LiveListActions.kt).
    val liveLists = LiveListStore(scope)

    // A song whose details the Info tab shows instead of the playing one's,
    // until it is let go.
    var infoSong by mutableStateOf<Song?>(null)

    // The real lengths of songs whose listing was wrong, learned by playing
    // them, as screen state so rows already showing pick them up.
    var realLengths by mutableStateOf<Map<String, Long>>(emptyMap())
        private set

    // A song's real length in whole seconds, once playing it found its
    // listing wrong; null while the listing stands.
    fun realSeconds(song: Song): Int? = realLengths[song.id]?.let { ((it + 500) / 1_000).toInt() }

    init {
        scope.launch { player.lengths.corrected.collect { realLengths = it } }
        if (listeningRoot != null) {
            plays.start()
            queueKeeper.start()
        }
        queueSync.start()
        watchProblems()
        followLive()
        followAnimatedArt()
        restored?.let(::signedIn)
    }

    // A song that could not play says so in the one notice line, and its
    // rows are marked, rather than it being skipped in silence.
    private fun watchProblems() {
        scope.launch {
            player.state.map { it.problem }.distinctUntilChanged().collect { problem ->
                if (problem == null) return@collect
                val song = problem.song
                if (song != null) failedSongs[song.id] = problem.words
                // A station that fails stops there; a song is skipped.
                notice = when {
                    song == null -> problem.words
                    isRadio(song.id) -> stoppedLine(song.title, problem.words)
                    else -> skippedLine(song.title, problem.words)
                }
                noticeDetail = problem.detail
            }
        }
    }

    // Each song's album and the next one's are asked about as it starts,
    // and the next song's loop is fetched ahead.
    private fun followAnimatedArt() {
        scope.launch {
            player.state.map { it.current?.song?.albumId to it.upcoming.firstOrNull()?.song?.albumId }.distinctUntilChanged().collect { (playing, next) ->
                animated.songChanged(playing, next, settings.current.appearance.animatedArtSetting)
            }
        }
    }

    // Puts plays and the queue away before Octo quits.
    fun beforeQuit() {
        plays.flush()
        if (listeningRoot != null) queueKeeper.saveNow()
        liveLists.saveNow()
    }

    // Signed in to a server: its library, search, Home, queue and live lists.
    // `page` is where the window starts over. The new server, its notice and
    // the fresh start all show at once: nothing (a frame, another thread)
    // can see the new server without its notice, or the old notice with it.
    fun signedIn(connection: Connection, note: String? = null, page: Page = Page.Home) {
        val views = viewsOf(connection)
        val old = upgrades
        val oldDownloads = downloads
        together {
            show(connection, views)
            notice = note
            noticeDetail = null
            starOverrides.clear()
            ratingOverrides.clear()
            failedSongs.clear()
            playlistViews.clear()
            playlistSaves.clear()
            infoSong = null
            // Back and forward start afresh for this account.
            navigator.startOver(page)
        }
        old?.close()
        oldDownloads?.close()
        startReading(views)
        startListening(connection)
    }

    // The pages' view of the server, read afresh through this connection.
    private fun useConnection(connection: Connection) {
        val views = viewsOf(connection)
        val old = upgrades
        val oldDownloads = downloads
        together { show(connection, views) }
        old?.close()
        oldDownloads?.close()
        startReading(views)
    }

    // Follows the library read of the server in use.
    private var libraryWatch: Job? = null

    // What the pages read a server through: its library, finds, search and
    // Home. Made before any of it shows, and read only after.
    private class ServerViews(
        val library: LibraryStore,
        val fetches: Fetches?,
        val search: SearchModel,
        val home: HomeStore,
        val upgrades: UpgradeModel?,
        val downloads: DownloadsModel?,
    )

    private fun viewsOf(connection: Connection): ServerViews {
        val store = LibraryStore(connection.client, scope)
        return ServerViews(
            store,
            if (connection.acquires) Fetches(connection.client, scope, onArrived = { store.load() }, onAsked = { downloads?.wake() }) else null,
            SearchModel(connection, { store.index }, { playlists }, scope, { settings.current.libraryOnly }, store::takeIn),
            HomeStore(connection, scope, kept = keptShelves, sections = { homeSectionOrder(settings.current.appearance.homeSections) }),
            // Any Octo server: whether it can look for FLACs is asked live,
            // since the extensions saved at sign-in may be older than it.
            // How the looking goes is the drawer's to show; only a refusal
            // stays in the notice.
            if (connection.isOcto) {
                UpgradeModel(
                    connection.client, scope, reload = { store.load() }, notify = { notice = it },
                    asked = ::upgradeAsked, done = ::upgradeDone,
                )
            } else {
                null
            },
            // The same for the downloads drawer.
            if (connection.isOcto) DownloadsModel(connection.client, scope, ended = { replaceEnded(it) }) else null,
        )
    }

    // Songs the server took on for a higher quality copy: said in passing,
    // with the drawer one click away when there is one.
    private fun upgradeAsked(line: String) {
        val drawer = downloads?.takeIf { it.supported == true }
        drawer?.wake()
        passingNotice(line, drawer?.let { NoticeAction(line, "Show downloads") { showSidePanel(SidePanel.Downloads) } })
    }

    // Some are done: the drawer says how each went. Without one, said in
    // passing, never left at the top of the page.
    private fun upgradeDone(line: String) {
        val drawer = downloads?.takeIf { it.supported == true }
        if (drawer != null) drawer.wake() else passingNotice(line)
    }

    // A notice that leaves on its own a few seconds later, unless another
    // took its place meanwhile.
    fun passingNotice(line: String, action: NoticeAction? = null) {
        notice = line
        noticeDetail = null
        noticeAction = action
        scope.launch {
            delay(PASSING_NOTICE_MS)
            if (notice == line) {
                notice = null
                if (noticeAction?.text == line) noticeAction = null
            }
        }
    }

    // Opens the downloads drawer on a song's download, or on the list when
    // the server has not listed it yet.
    fun followDownload(id: String) {
        val drawer = downloads?.takeIf { it.supported == true } ?: return
        if (!drawer.showLogOf(id)) drawer.showList()
        showSidePanel(SidePanel.Downloads)
    }

    // Opens the downloads drawer on Find songs for one song.
    fun findSongs(song: Song) {
        val drawer = downloads?.takeIf { it.supported == true } ?: return
        drawer.find(song.id, song.title)
        showSidePanel(SidePanel.Downloads)
    }

    private fun show(connection: Connection, views: ServerViews) {
        this.connection = connection
        library = views.library
        fetches = views.fetches
        upgrades = views.upgrades
        downloads = views.downloads
        search = views.search
        home = views.home
        health.forget()
        imports.forget()
        family.forget()
        serverFacts.forget()
        liveRadio.forget()
        followServerUpdate(connection)
        animated.follow(connection)
        // The family decides what adding an outside song does and who picks
        // the stream quality, so it is read before the first song plays.
        if (connection.family) scope.launch { family.plan() }
        offline.poke()
    }

    private fun startReading(views: ServerViews) {
        views.library.load()
        // Kept songs are checked against each read of the library, such as
        // the one after a song's file is swapped for a better copy.
        libraryWatch?.cancel()
        libraryWatch = scope.launch {
            views.library.state.filterIsInstance<LibraryState.Ready>().collect { offline.poke() }
        }
        views.upgrades?.start()
        views.downloads?.start()
        // Whether songs can be deleted from disk, for every song menu.
        if (connection?.isOcto == true) health.askServer()
        refreshPlaylists()
    }

    // Makes the changes all show at once. Should another thread have written
    // one of the same values meanwhile, they are made again directly, so
    // nothing is lost; each change here can safely run twice.
    private fun together(change: () -> Unit) {
        val snapshot = Snapshot.takeMutableSnapshot()
        try {
            snapshot.enter(change)
            if (snapshot.apply() !is SnapshotApplyResult.Success) change()
        } finally {
            snapshot.dispose()
        }
    }

    // This account's queue comes back, its waiting plays are sent, and a
    // queue saved on another device may be offered.
    private fun startListening(connection: Connection) {
        val folder = listeningRoot?.let { listeningFolder(it, connection.server) }
        queueKeeper.folder = folder
        queueSync.folder = folder
        queueSync.reset()
        liveLists.open(folder?.let { File(it, LiveListStore.FILE_NAME) })
        scope.launch {
            if (folder != null) {
                queueKeeper.restore()?.let {
                    queueSync.restored(it)
                    queueSync.putBack()
                }
            }
            queueSync.check(force = true)
        }
        plays.signedIn()
    }

    // Leaves the server in use: what was playing counts, the queue and live
    // lists are kept in its own folder for next time, and the player stops.
    private fun leaveServer() {
        plays.flush()
        if (listeningRoot != null) queueKeeper.saveNow()
        queueKeeper.folder = null
        queueSync.folder = null
        queueSync.reset()
        liveLists.saveNow()
        liveLists.open(null)
        player.clear()
    }

    // Signs out of the server in use. It stays in the list of servers,
    // without its password, and the sign-in page opens.
    fun signOut() {
        leaveServer()
        // The server is forgotten at once; the password store is left to
        // finish off the window's thread.
        scope.launch(start = CoroutineStart.UNDISPATCHED) { accounts.signOut() }
        signedOut()
    }

    private fun signedOut() {
        val form = SignInForm(accounts.last)
        libraryWatch?.cancel()
        libraryWatch = null
        upgrades?.close()
        downloads?.close()
        together {
            signInForm = form
            connection = null
            library = null
            fetches = null
            upgrades = null
            downloads = null
            search = null
            home = null
            health.forget()
            family.forget()
            serverFacts.forget()
            liveRadio.forget()
            followServerUpdate(null)
            animated.follow(null)
            playlists = emptyList()
            fullPlayer = false
            navigator.startOver()
        }
    }

    // Fills the sign-in page with a kept server, asking for its password.
    fun fillSignIn(server: SavedServer, note: String? = null) {
        signInForm = SignInForm(server).also { form -> note?.let { form.result = false to it } }
    }

    // Makes another kept server the one in use. It is asked first, so one out
    // of reach leaves everything as it was and says why. Then what was
    // playing stops, its queue kept on its own server's side for next time,
    // and the library, queue, live lists and covers become the new server's.
    // `done` hears how it went (a server whose password is not kept asks
    // for it there).
    fun switchTo(id: String, page: Page = Page.Home, done: (SwitchOutcome) -> Unit = {}) {
        val target = accounts.find(id) ?: return
        if (switching != null || id == connection?.server?.id) return
        switching = target
        scope.launch {
            val outcome = try {
                accounts.switchTo(id)
            } finally {
                switching = null
            }
            when (outcome) {
                is SwitchOutcome.Done -> arrive(outcome.connection, page)
                is SwitchOutcome.Failed -> notice = outcome.message
                is SwitchOutcome.NeedsPassword -> Unit
            }
            done(outcome)
        }
    }

    // Moves the window over to another server's connection, saying so in
    // the notice line, and plainly when music was stopped for it.
    fun arrive(connection: Connection, page: Page = Page.Home, note: String? = null) {
        val from = this.connection?.server
        val playing = player.state.value.let { it.current != null && it.playing }
        if (from != null) leaveServer()
        val words = switchNotice(connection.server.name, from?.name, playing)
        signedIn(connection, listOfNotNull(words, note).joinToString(" ").ifEmpty { null }, page)
    }

    // A kept server's connection changed (its address, headers or way of
    // signing in were edited). The same account keeps playing; another
    // account on it is a switch.
    fun reconnected(connection: Connection) {
        val now = this.connection
        if (now != null && now.server.key == connection.server.key) useConnection(connection) else arrive(connection, Page.Settings)
    }

    // Signs out of a kept server that is not the one in use; the one in use
    // signs out as above.
    fun signOutOf(id: String) {
        if (id == connection?.server?.id) return signOut()
        scope.launch(start = CoroutineStart.UNDISPATCHED) { accounts.signOut(id) }
    }

    // Takes a server off the list. Its songs and playlists stay on the
    // server; with `forgetHere`, this computer's plays, queue and live lists
    // for it are deleted too, otherwise they stay in case it is added again.
    fun removeServer(id: String, forgetHere: Boolean) {
        val server = accounts.find(id) ?: return
        val inUse = id == connection?.server?.id
        if (inUse) leaveServer()
        scope.launch(start = CoroutineStart.UNDISPATCHED) {
            accounts.remove(id)
            if (forgetHere && listeningRoot != null) {
                withContext(Dispatchers.IO) { runCatching { listeningFolder(listeningRoot, server).deleteRecursively() } }
            }
        }
        if (inUse) signedOut()
    }

    fun refreshPlaylists() {
        val client = connection?.client ?: return
        val home = home
        scope.launch {
            try {
                playlists = client.playlists()
                playlistsReadAt = System.currentTimeMillis()
                home?.playlistsAnswered(playlists)
            } catch (e: SubsonicException) {
                // The sidebar keeps what it had.
            }
        }
    }

    // Takes a playlist out of the sidebar's list at once.
    internal fun dropPlaylist(id: String) {
        playlists = playlists.filterNot { it.id == id }
    }

    // When the sidebar's playlists were last read.
    private var playlistsReadAt = 0L

    // The window is in front again: playlists may have been deleted or
    // made on another device, and Octo makes its mixes and stations anew
    // now and then, so a list older than a minute is read again.
    fun windowCameBack(now: Long = System.currentTimeMillis()) = refreshPlaylistsIfOld(now)

    // Home is opened: the lists Octo makes for the listener are made on the
    // server when playlists are asked for, so a first sign-in can read them
    // a moment before they exist. A list older than a minute is read again.
    fun refreshPlaylistsIfOld(now: Long = System.currentTimeMillis()) {
        if (now - playlistsReadAt >= PLAYLISTS_FRESH_MS) refreshPlaylists()
    }

    fun toggleSidePanel(panel: SidePanel) = showSidePanel(if (sidePanel == panel) null else panel)

    // Opens the panel on a tab, or closes it with null.
    fun showSidePanel(panel: SidePanel?) {
        sidePanel = panel
        settings.update { it.copy(sidePanel = panel?.key) }
    }

    fun showInfo(song: Song?) {
        infoSong = song
        showSidePanel(SidePanel.Info)
    }

    // The frame's own settings, changed as the listener drags and folds it.
    fun updateFrame(change: (FramePrefs) -> FramePrefs) =
        settings.update { it.copy(frame = change(it.frame)) }

    // One song table's own columns and widths, changed from its heading.
    fun updateTable(id: String, change: (TablePrefs) -> TablePrefs) =
        settings.update { it.copy(tables = it.tables + (id to change(it.tables[id] ?: TablePrefs()))) }

    fun isPinned(playlistId: String) = playlistId in settings.current.frame.pinnedPlaylists

    fun setPinned(playlistId: String, pinned: Boolean) = updateFrame { frame ->
        frame.copy(pinnedPlaylists = if (pinned) (frame.pinnedPlaylists - playlistId) + playlistId else frame.pinnedPlaylists - playlistId)
    }

    // Playing and queueing.

    // `source` names the list for the queue ("OK Computer"); without one,
    // the page it was played from names it (queueNameFor).
    fun play(songs: List<Song>, start: Int = 0, shuffle: Boolean = false, source: String? = null) {
        if (songs.isEmpty()) return
        // A station's page plays the station, which keeps going.
        val page = navigator.current.page
        if (source == null && page is Page.Playlist && isStationId(page.id)) {
            playlists.firstOrNull { it.id == page.id && (it.octoGroup == null || it.octoGroup == "station") }
                ?.let { return playStation(songs, start, shuffle, page.id, it.name) }
        }
        val listName = { id: String -> playlists.firstOrNull { it.id == id }?.name ?: liveLists.byId(id)?.name }
        val name = source ?: queueNameFor(navigator.current.page, songs, listName)
        player.play(songs, if (shuffle) (songs.indices).random() else start, shuffle, QueueSource.Played(name))
        jumpList?.let { list -> jumpTargetFor(navigator.current.page, songs, listName)?.let(list::played) }
    }

    // Plays a station's songs from one of them, under its name; as they run
    // low, more of its kind are added. Shuffled, its songs are put in a new
    // order, so the songs added later still come after them.
    fun playStation(songs: List<Song>, start: Int, shuffle: Boolean, id: String, name: String) {
        if (songs.isEmpty()) return
        val order = if (shuffle) songs.shuffled() else songs
        player.play(order, if (shuffle) 0 else start, false, QueueSource.Station(id, name))
    }

    fun playNext(songs: List<Song>) = player.playNext(songs)

    fun addToQueue(songs: List<Song>) = player.addToQueue(songs)

    fun setVolume(volume: Float) {
        player.setVolume(volume)
        settings.update { it.copy(playback = it.playback.copy(volume = volume.coerceIn(0f, 1f))) }
    }

    // Plays to another output, remembered for the next run.
    fun selectOutput(id: String) {
        player.selectOutput(id)
        settings.update { it.copy(playback = it.playback.copy(outputDevice = id.takeUnless { it == DEFAULT_OUTPUT })) }
    }

    // Favourites, as server stars. A heart set or cleared here shows from
    // the overrides until the next library read brings the server's own,
    // so the library is not read or sorted again for it.

    fun isStarred(song: Song): Boolean = starOverrides[song.id] ?: (song.starred != null)

    fun setStarred(songs: List<Song>, starred: Boolean) {
        val client = connection?.client ?: return
        val ids = songs.map { it.id }.distinct()
        ids.forEach { starOverrides[it] = starred }
        scope.launch {
            try {
                if (starred) client.star(ids) else client.unstar(ids)
                // Kept Liked songs follow.
                offline.poke()
            } catch (e: SubsonicException) {
                ids.forEach { starOverrides.remove(it) }
                notice = "Couldn't change favorites: ${e.userMessage()}"
            }
        }
    }

    fun isAlbumStarred(id: String, starred: String?): Boolean = starOverrides["album:$id"] ?: (starred != null)

    fun isArtistStarred(id: String, starred: String?): Boolean = starOverrides["artist:$id"] ?: (starred != null)

    // Albums and artists as favourites. Only for what is in the library: on
    // Octo, starring an album found online would download it.
    fun setAlbumStarred(id: String, starred: Boolean) = starWhole("album:$id", starred) { client ->
        if (starred) client.starAlbums(listOf(id)) else client.unstarAlbums(listOf(id))
    }

    fun setArtistStarred(id: String, starred: Boolean) = starWhole("artist:$id", starred) { client ->
        if (starred) client.starArtists(listOf(id)) else client.unstarArtists(listOf(id))
    }

    private fun starWhole(key: String, starred: Boolean, call: suspend (app.winters.octo.subsonic.SubsonicClient) -> Unit) {
        val client = connection?.client ?: return
        starOverrides[key] = starred
        scope.launch {
            try {
                call(client)
            } catch (e: SubsonicException) {
                starOverrides.remove(key)
                notice = "Couldn't change favorites: ${e.userMessage()}"
            }
        }
    }

    // Playlists.

    fun addToPlaylist(playlistId: String, songs: List<Song>) {
        val client = connection?.client ?: return
        val formPost = connection?.server?.extensions?.any { it.startsWith("$FORM_POST_EXTENSION:") } == true
        scope.launch {
            try {
                client.updatePlaylist(playlistId, songIdsToAdd = songs.map { it.id }, formPost = formPost)
                refreshPlaylists()
            } catch (e: SubsonicException) {
                notice = "Couldn't add to the playlist: ${e.userMessage()}"
            }
        }
    }

    fun createPlaylist(name: String, songs: List<Song>, then: (String?) -> Unit = {}) {
        val client = connection?.client ?: return
        val formPost = connection?.server?.extensions?.any { it.startsWith("$FORM_POST_EXTENSION:") } == true
        scope.launch {
            try {
                val made = client.createPlaylist(name.trim(), songs.map { it.id }, formPost)
                refreshPlaylists()
                then(made?.id)
            } catch (e: SubsonicException) {
                notice = "Couldn't make the playlist: ${e.userMessage()}"
                then(null)
            }
        }
    }

    // Songs of an album, for the menus on album cards.
    suspend fun albumSongs(id: String): List<Song> = connection?.client?.album(id)?.song.orEmpty()

    // Whether the listener can change a playlist: their own, and not one
    // the server keeps for itself.
    fun canEdit(playlist: Playlist): Boolean =
        !playlist.readonly && (playlist.owner == null || playlist.owner == connection?.client?.username)

    // Whether the server takes playlist changes in a form body.
    internal val formPost: Boolean
        get() = connection?.server?.extensions?.any { it.startsWith("$FORM_POST_EXTENSION:") } == true

    // Sort orders kept between runs.

    var songOrder by mutableStateOf(SortList.Songs.decode(settings.current.songSort))
        private set

    fun sortSongs(order: SortOrder) {
        songOrder = order
        settings.update { it.copy(songSort = SortList.Songs.encode(order)) }
    }

    var albumOrder by mutableStateOf(SortList.Albums.decode(settings.current.albumSort))
        private set

    fun sortAlbums(order: SortOrder) {
        albumOrder = order
        settings.update { it.copy(albumSort = SortList.Albums.encode(order)) }
    }

    // The window's keyboard shortcuts.
    fun perform(shortcut: Shortcut): Boolean {
        when (shortcut) {
            Shortcut.PlayPause -> player.togglePlay()
            // A live station has no place to move to.
            Shortcut.SeekBack -> if (player.state.value.live == null) player.seekTo(player.positionMs() - SEEK_STEP_MS) else return false
            Shortcut.SeekForward -> if (player.state.value.live == null) player.seekTo(player.positionMs() + SEEK_STEP_MS) else return false
            Shortcut.VolumeUp -> setVolume(player.state.value.volume + VOLUME_STEP)
            Shortcut.VolumeDown -> setVolume(player.state.value.volume - VOLUME_STEP)
            Shortcut.Search -> if (connection != null) openSearch() else return false
            // The list's own filter when the page has one, else the search box.
            Shortcut.Filter -> when {
                connection == null -> return false
                pageFilterFocus != null && !fullPlayer -> runCatching { pageFilterFocus?.requestFocus() }.getOrElse { openSearch() }
                else -> openSearch()
            }
            Shortcut.Commands -> if (connection != null) openSearch(commands = true) else return false
            Shortcut.Lyrics -> if (connection != null) toggleSidePanel(SidePanel.Lyrics) else return false
            Shortcut.Queue -> if (connection != null) toggleSidePanel(SidePanel.Queue) else return false
            Shortcut.Info -> if (connection != null) toggleSidePanel(SidePanel.Info) else return false
            Shortcut.Sidebar -> if (connection != null) updateFrame { it.copy(sidebarRail = !it.sidebarRail) } else return false
            Shortcut.MiniPlayer -> toggleMiniPlayer?.invoke() ?: return false
            Shortcut.Settings -> {
                if (connection == null) return false
                fullPlayer = false
                navigator.go(Page.Settings)
            }
            Shortcut.Back -> navigator.back()
            Shortcut.Forward -> navigator.forward()
            Shortcut.CloseLayer -> when {
                popups.open -> popups.close()
                fullPlayer -> fullPlayer = false
                // Escape in the side panel closes it.
                sidePanel != null && panelHasKeyboard -> showSidePanel(null)
                else -> return false
            }
        }
        return true
    }
}

// How long the sidebar's playlists count as fresh when the window comes back.
const val PLAYLISTS_FRESH_MS = 60_000L

// What the app calls itself to the radio catalog: "Octo/1.7.0 (desktop)".
fun liveRadioAgent(version: String? = System.getProperty("octo.version")): String =
    "Octo/${version?.trim()?.takeIf(String::isNotEmpty) ?: "dev"} (desktop)"

// The app's connections, naming the app to the catalog as liveRadioAgent
// does, over the name every other host hears.
private fun catalogHttp(http: OkHttpClient): OkHttpClient {
    val agent = liveRadioAgent()
    return http.newBuilder().addNetworkInterceptor { chain -> chain.proceed(chain.request().newBuilder().header("User-Agent", agent).build()) }.build()
}
