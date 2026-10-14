package app.winters.octo.ui.nav

import androidx.hilt.lifecycle.viewmodel.compose.hiltViewModel
import app.winters.octo.ui.family.FamilyShellViewModel
import app.winters.octo.ui.family.FamilyRequestSheetHost
import app.winters.octo.ui.family.FamilyScreen
import app.winters.octo.subsonic.familyAppLink
import app.winters.octo.subsonic.parseFamilyLink
import app.winters.octo.family.FamilyOpen
import androidx.activity.compose.BackHandler
import androidx.compose.animation.AnimatedVisibility
import androidx.compose.animation.EnterExitState
import androidx.compose.animation.SharedTransitionLayout
import androidx.compose.animation.core.animateInt
import androidx.compose.animation.core.tween
import androidx.compose.animation.fadeIn
import androidx.compose.animation.fadeOut
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.WindowInsets
import androidx.compose.foundation.layout.WindowInsetsSides
import androidx.compose.foundation.layout.displayCutout
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.navigationBarsPadding
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.navigationBars
import androidx.compose.foundation.layout.only
import androidx.compose.foundation.layout.union
import androidx.compose.foundation.layout.windowInsetsPadding
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.runtime.Composable
import androidx.compose.runtime.CompositionLocalProvider
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.SideEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.key
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.lifecycle.compose.LifecycleResumeEffect
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import androidx.lifecycle.viewmodel.navigation3.rememberViewModelStoreNavEntryDecorator
import androidx.navigation3.runtime.NavKey
import androidx.navigation3.runtime.entryProvider
import androidx.navigation3.runtime.rememberNavBackStack
import androidx.navigation3.runtime.rememberSaveableStateHolderNavEntryDecorator
import androidx.navigation3.ui.NavDisplay
import app.winters.octo.ambient.AmbientBackdrop
import app.winters.octo.ambient.LocalPageArtworks
import app.winters.octo.ambient.PageArtworks
import app.winters.octo.ambient.rememberBarFilm
import app.winters.octo.design.OctoColors
import app.winters.octo.device.DeviceLibrary
import app.winters.octo.playback.PlaybackConnection
import app.winters.octo.player.PlayerArtCorner
import app.winters.octo.player.PlayerOverlay
import app.winters.octo.ui.admin.OctoAdminScreen
import app.winters.octo.ui.imports.ImportScreen
import app.winters.octo.ui.imports.ImportShellViewModel
import app.winters.octo.ui.album.AlbumScreen
import app.winters.octo.ui.artist.ArtistScreen
import app.winters.octo.ui.common.ChoiceSheet
import app.winters.octo.ui.common.ChoiceSheetHost
import app.winters.octo.ui.common.Feedback
import app.winters.octo.ui.common.FeedbackHost
import app.winters.octo.ui.common.LocalFeedback
import app.winters.octo.ui.common.LocalChoiceSheet
import app.winters.octo.ui.common.LocalHaze
import app.winters.octo.ui.common.LocalNowPlayingId
import app.winters.octo.ui.common.LocalOpenPage
import app.winters.octo.ui.common.LocalPressSpot
import app.winters.octo.ui.common.PressSpot
import app.winters.octo.ui.common.pressSpot
import app.winters.octo.ui.common.NowMark
import app.winters.octo.ui.favourites.FavouritesScreen
import app.winters.octo.ui.favourites.openingSegment
import app.winters.octo.ui.folders.FoldersScreen
import app.winters.octo.ui.genre.GenreScreen
import app.winters.octo.ui.genre.GenresScreen
import app.winters.octo.ui.history.HistoryScreen
import app.winters.octo.ui.library.health.HealthCheckScreen
import app.winters.octo.ui.library.health.LibraryHealthScreen
import app.winters.octo.ui.library.health.RecentlyRemovedScreen
import app.winters.octo.ui.home.HomeScreen
import app.winters.octo.ui.library.AlbumsScreen
import app.winters.octo.ui.library.ArtistsScreen
import app.winters.octo.ui.library.LibraryScreen
import app.winters.octo.ui.library.SongsScreen
import app.winters.octo.ui.menu.LocalSongMenu
import app.winters.octo.ui.menu.SongMenuHost
import app.winters.octo.ui.menu.SongMenuState
import app.winters.octo.ui.offline.DownloadsScreen
import app.winters.octo.ui.online.OnlineAlbumScreen
import app.winters.octo.ui.online.OnlineArtistScreen
import app.winters.octo.ui.online.ServerListScreen
import app.winters.octo.ui.playlist.LocalPlaylistSheets
import app.winters.octo.ui.playlist.PlaylistScreen
import app.winters.octo.ui.playlist.PlaylistSheets
import app.winters.octo.ui.playlist.PlaylistSheetsHost
import app.winters.octo.ui.livelists.LiveListEditScreen
import app.winters.octo.ui.livelists.LiveListScreen
import app.winters.octo.ui.playlist.PlaylistsScreen
import app.winters.octo.ui.search.SearchScreen
import app.winters.octo.ui.search.SearchShellViewModel
import app.winters.octo.ui.server.LocalShareSheet
import app.winters.octo.ui.server.RadioStationsScreen
import app.winters.octo.ui.server.ShareSheetHost
import app.winters.octo.ui.server.ShareSheetState
import app.winters.octo.ui.server.SharesScreen
import app.winters.octo.ui.settings.DisconnectPrompt
import app.winters.octo.ui.settings.DisconnectSheetHost
import app.winters.octo.ui.settings.LocalDisconnectPrompt
import app.winters.octo.ui.settings.SettingsPageScreen
import app.winters.octo.ui.settings.SettingsScreen
import app.winters.octo.ui.settings.SERVER_UPDATE_MARK
import app.winters.octo.ui.settings.rememberServerUpdateDot
import app.winters.octo.ui.signin.SignInScreen
import app.winters.octo.ui.sound.SoundScreen
import dev.chrisbanes.haze.hazeSource
import dev.chrisbanes.haze.rememberHazeState
import androidx.compose.ui.unit.dp
import androidx.navigation3.runtime.NavBackStack
import androidx.navigation3.runtime.NavEntry
import androidx.navigation3.runtime.rememberDecoratedNavEntries
import app.winters.octo.design.motionScale
import app.winters.octo.ui.downloads.DownloadsPill

// The whole app: one back stack per tab, the screens, and the floating
// bar over them. A change in openPlayer brings up the full player.
@Composable
fun MainShell(library: DeviceLibrary, playback: PlaybackConnection, feedback: Feedback, openPlayer: Int = 0) {
    val now by playback.now.collectAsStateWithLifecycle()
    val haze = rememberHazeState()
    // What the full player frosts, for the menus that open over it.
    val playerHaze = rememberHazeState()
    // Called once each, always in this order.
    val stacks = listOf(
        rememberNavBackStack(HomeRoute),
        rememberNavBackStack(SearchRoute),
        rememberNavBackStack(LibraryRoute),
        rememberNavBackStack(SettingsRoute),
    )
    var selected by rememberSaveable { mutableIntStateOf(0) }
    val stack = stacks[selected]
    // Whether this change of page is a change of tab, which moves
    // differently from going deeper or back.
    val tabSeen = remember { intArrayOf(selected) }
    val changingTab = tabSeen[0] != selected
    SideEffect { tabSeen[0] = selected }
    val motion = motionScale()
    // Every tab's pages, each tab keeping its own pages' state and view
    // models while another tab is in front, so coming back to a tab finds
    // it as it was left instead of building it again from empty.
    val tabPages = stacks.mapIndexed { index, tabStack ->
        key(index) {
            rememberDecoratedNavEntries(
                backStack = tabStack,
                entryDecorators = listOf(
                    rememberSaveableStateHolderNavEntryDecorator(),
                    rememberViewModelStoreNavEntryDecorator(),
                ),
                entryProvider = remember(tabStack) { pagesFor(tabStack) },
            )
        }
    }
    val open: (NavKey) -> Unit = { stack.add(it) }
    // A notice tapped or a family link opened: the Family screen, or the
    // join form filled in, on the Settings tab.
    val familyHub = hiltViewModel<FamilyShellViewModel>().hub
    val familyOpen by familyHub.opens.collectAsStateWithLifecycle()
    LaunchedEffect(familyOpen) {
        val what = familyOpen ?: return@LaunchedEffect
        familyHub.opened()
        selected = stacks.lastIndex
        stacks.last().add(
            when (what) {
                FamilyOpen.Family -> FamilyRoute
                is FamilyOpen.Join -> FamilyJoinRoute(familyAppLink(what.link))
            },
        )
    }
    // A list shared to Octo: Import, on the Settings tab, which sends it.
    val importInbox = hiltViewModel<ImportShellViewModel>().inbox
    val shared by importInbox.pending.collectAsStateWithLifecycle()
    LaunchedEffect(shared) {
        if (shared == null) return@LaunchedEffect
        selected = stacks.lastIndex
        if (stacks.last().lastOrNull() != ImportRoute) stacks.last().add(ImportRoute)
    }
    val back: () -> Unit = { stack.removeLastOrNull() }
    val hasTrack = now.trackId != null
    // The bar's small player, and the full one over everything.
    var barPlayer by rememberSaveable { mutableStateOf(false) }
    var playerOpen by rememberSaveable { mutableStateOf(false) }
    // A search asked for elsewhere (the live player's "Find this song in
    // Octo"): the Search tab, at its top, with the player closed.
    val searchAsks = hiltViewModel<SearchShellViewModel>().asks
    val searchAsked by searchAsks.asked.collectAsStateWithLifecycle()
    val searchSeen = rememberSaveable { intArrayOf(searchAsked) }
    LaunchedEffect(searchAsked) {
        if (searchAsked == searchSeen[0]) return@LaunchedEffect
        searchSeen[0] = searchAsked
        playerOpen = false
        barPlayer = false
        val searchTab = 1
        selected = searchTab
        val tab = stacks[searchTab]
        while (tab.size > 1) tab.removeAt(tab.lastIndex)
    }
    // When the queue empties, both fold away.
    LaunchedEffect(hasTrack) {
        if (!hasTrack) {
            barPlayer = false
            playerOpen = false
        }
    }
    // Asked for by a home screen widget. It shows once a song is loaded.
    LaunchedEffect(openPlayer) {
        if (openPlayer > 0) playerOpen = true
    }
    val barActions = BarActions(
        onSelect = { index ->
            barPlayer = false
            if (index == selected) {
                // Tapping the current tab goes back to its top.
                while (stack.size > 1) stack.removeAt(stack.lastIndex)
            } else {
                selected = index
            }
        },
        // With nothing loaded, the round button shuffles the library.
        onRoundButton = { if (hasTrack) barPlayer = true else playback.togglePlayPause() },
        onShowTabs = { barPlayer = false },
        onOpenPlayer = { playerOpen = true },
        onPrevious = playback::previous,
        onPlayPause = playback::togglePlayPause,
        onNext = playback::next,
    )

    // Access can be changed in system settings while the app is away.
    LifecycleResumeEffect(Unit) {
        library.refresh()
        onPauseOrDispose { }
    }

    // A newer Octo for the server, marked on the Settings tab.
    val serverUpdateWaits = rememberServerUpdateDot()

    val songMenu = remember { SongMenuState() }
    val playlistSheets = remember { PlaylistSheets() }
    val disconnectPrompt = remember { DisconnectPrompt() }
    val choiceSheet = remember { ChoiceSheet() }
    val shareSheet = remember { ShareSheetState() }
    val pressSpot = remember { PressSpot() }
    // The covers of open album and artist pages, and the bar's film, for the
    // artwork's glow.
    val pageArtworks = remember { PageArtworks() }
    val barFilm = rememberBarFilm(now)
    // Going to a page from the song menu also closes the player.
    val openFromMenu: (NavKey) -> Unit = { key ->
        playerOpen = false
        stack.add(key)
    }
    // A live list's options can open its editor.
    playlistSheets.editLiveList = { id -> openFromMenu(LiveListEditRoute(id)) }

    CompositionLocalProvider(
        LocalHaze provides haze,
        LocalPressSpot provides pressSpot,
        LocalSongMenu provides songMenu,
        LocalPlaylistSheets provides playlistSheets,
        LocalDisconnectPrompt provides disconnectPrompt,
        LocalChoiceSheet provides choiceSheet,
        LocalShareSheet provides shareSheet,
        LocalFeedback provides feedback,
        LocalPageArtworks provides pageArtworks,
        LocalOpenPage provides open,
        LocalNowPlayingId provides NowMark(now.trackId, now.isPlaying),
    ) {
        SharedTransitionLayout {
            // Any press marks where a menu it opens should float.
            Box(Modifier.fillMaxSize().background(OctoColors.Background).pressSpot(pressSpot, wholeArea = true)) {
                // The glow sits under the pages and is part of what the bar
                // frosts. It rests while the full player covers it.
                Box(Modifier.fillMaxSize().hazeSource(haze)) {
                    AmbientBackdrop(stack.lastOrNull(), now, pageArtworks, awake = !playerOpen)
                    NavDisplay(
                        entries = tabPages[selected],
                        onBack = { stack.removeLastOrNull() },
                        // Turned sideways, pages keep clear of the camera cutout and
                        // a side navigation bar; the glow still fills the screen.
                        modifier = Modifier.fillMaxSize().windowInsetsPadding(SideInsets),
                        transitionSpec = { if (changingTab) tabMotion(motion) else pushMotion(motion) },
                        popTransitionSpec = { if (changingTab) tabMotion(motion) else popMotion(motion) },
                        predictivePopTransitionSpec = { gestureMotion(motion) },
                    )
                }
                // Back from the top of another tab goes Home rather than out.
                BackHandler(enabled = selected != 0 && stack.size == 1) { selected = 0 }

                // The bar steps aside while the full player is open; the artwork
                // flies between the two.
                AnimatedVisibility(
                    visible = !playerOpen,
                    enter = fadeIn(tween(300)),
                    exit = fadeOut(tween(300)),
                    modifier = Modifier.align(Alignment.BottomCenter),
                ) {
                    // The mirror of the player's card: a soft square while it
                    // flies back, a circle once it lands.
                    val corner by transition.animateInt(label = "capsule art corners") {
                        if (it == EnterExitState.Visible) 50 else PlayerArtCorner
                    }
                    BottomBar(
                        haze = haze,
                        selected = selected,
                        now = now,
                        positionMs = playback::positionMs,
                        playerShown = barPlayer && hasTrack,
                        actions = barActions,
                        artModifier = Modifier.sharedElement(rememberSharedContentState(ArtKey), this),
                        artShape = RoundedCornerShape(percent = corner),
                        film = barFilm.value,
                        marks = if (serverUpdateWaits) mapOf(stacks.lastIndex to SERVER_UPDATE_MARK) else emptyMap(),
                    )
                }
                // Songs on their way: a small pill above the bar, on the
                // right, that opens the server downloads sheet when tapped.
                AnimatedVisibility(
                    visible = !playerOpen,
                    enter = fadeIn(tween(300)),
                    exit = fadeOut(tween(300)),
                    modifier = Modifier.align(Alignment.BottomEnd),
                ) {
                    DownloadsPill(haze, Modifier.navigationBarsPadding().padding(end = 20.dp, bottom = BarBottomGap + BarHeight + 10.dp))
                }
                AnimatedVisibility(
                    visible = playerOpen && hasTrack,
                    enter = fadeIn(tween(400)),
                    exit = fadeOut(tween(300)),
                ) {
                    PlayerOverlay(
                        backdrop = playerHaze,
                        artModifier = Modifier.sharedElement(rememberSharedContentState(ArtKey), this),
                        onClose = { playerOpen = false },
                        onOpenArtist = { id ->
                            playerOpen = false
                            stack.add(ArtistRoute(id))
                        },
                        onOpenAlbum = { id ->
                            playerOpen = false
                            stack.add(AlbumRoute(id))
                        },
                    )
                }
                // Over the player, the menus frost the player rather than the page.
                SongMenuHost(songMenu, onOpen = openFromMenu, backdrop = if (playerOpen && hasTrack) playerHaze else haze)
                PlaylistSheetsHost(playlistSheets)
                DisconnectSheetHost(disconnectPrompt)
                ChoiceSheetHost(choiceSheet)
                ShareSheetHost(shareSheet)
                FamilyRequestSheetHost()
                app.winters.octo.ui.downloads.ServerDownloadsHost()
                // Above the sheets, so an undo stays reachable while one is open.
                FeedbackHost(feedback)
            }
        }
    }
}

// The sides a sideways phone keeps for its cutout and navigation bar.
private val SideInsets: WindowInsets
    @Composable get() = WindowInsets.displayCutout.union(WindowInsets.navigationBars).only(WindowInsetsSides.Horizontal)

// One key for whichever song is on, so a song change mid-flight cannot
// break the hand-off.
private const val ArtKey = "now-playing-art"

// The app's pages, each opening further pages in, and going back within,
// the tab it belongs to.
private fun pagesFor(stack: NavBackStack<NavKey>): (NavKey) -> NavEntry<NavKey> {
    val open: (NavKey) -> Unit = { stack.add(it) }
    val back: () -> Unit = { stack.removeLastOrNull() }
    return entryProvider {
        entry<HomeRoute> { HomeScreen(open) }
        entry<SearchRoute> { SearchScreen(open) }
        entry<LibraryRoute> { LibraryScreen(open) }
        entry<SettingsRoute> { SettingsScreen(open) }
        entry<SettingsPageRoute> { SettingsPageScreen(it.page, it.highlight, open, back) }
        entry<AlbumRoute> { AlbumScreen(it.id, open, back) }
        entry<ArtistRoute> { ArtistScreen(it.id, open, back) }
        entry<OnlineAlbumRoute> { OnlineAlbumScreen(it.id, open, back) }
        entry<OnlineArtistRoute> { OnlineArtistScreen(it.id, open, back) }
        entry<ServerListRoute> { ServerListScreen(it, back) }
        entry<AlbumsRoute> { AlbumsScreen(open, back) }
        entry<ArtistsRoute> { ArtistsScreen(open, back) }
        entry<SongsRoute> { SongsScreen(back, open) }
        entry<GenresRoute> { GenresScreen(open, back) }
        entry<GenreRoute> { GenreScreen(it.name, open, back) }
        entry<FoldersRoute> { FoldersScreen(back) }
        entry<PlaylistsRoute> { PlaylistsScreen(open, back) }
        // Liked songs and Favourites are one page; the way in picks the part.
        entry<LikedRoute> { FavouritesScreen(open, back, openingSegment(it)) }
        entry<FavouritesRoute> { FavouritesScreen(open, back, openingSegment(it)) }
        entry<DownloadsRoute> { DownloadsScreen(back) }
        entry<PlaylistRoute> { PlaylistScreen(it.id, back) }
        entry<LiveListRoute> { LiveListScreen(it.id, back) }
        // Once saved, a new live list's screen takes the editor's place.
        entry<LiveListEditRoute> { route ->
            LiveListEditScreen(route.id, route.start, back, onSaved = { saved ->
                stack.removeLastOrNull()
                if (route.id == null) open(LiveListRoute(saved))
            })
        }
        entry<SignInRoute> { SignInScreen(back) }
        entry<EditConnectionRoute> { SignInScreen(back, editing = true) }
        entry<ServerFormRoute> { route -> SignInScreen(back, form = route.form, serverId = route.id, note = route.note) }
        entry<OctoAdminRoute> { OctoAdminScreen(back) }
        entry<ImportRoute> { ImportScreen(back) }
        entry<FamilyRoute> { FamilyScreen(back, onImport = { open(ImportRoute) }) }
        entry<FamilyJoinRoute> { route -> SignInScreen(back, join = parseFamilyLink(route.link)) }
        entry<ChartsRoute> { app.winters.octo.ui.charts.ChartsScreen(back) }
        entry<SoundRoute> { SoundScreen(back) }
        entry<HomeSectionsRoute> { app.winters.octo.ui.settings.HomeSectionsPage(back) }
        entry<SharesRoute> { SharesScreen(back) }
        entry<RadioStationsRoute> { RadioStationsScreen(back, open) }
        entry<LiveRadioNearRoute> { app.winters.octo.ui.liveradio.LiveRadioScreen(back) }
        entry<HistoryRoute> { HistoryScreen(it.mostPlayed, back) }
        entry<LibraryHealthRoute> { LibraryHealthScreen(open, back) }
        entry<HealthCheckRoute> { HealthCheckScreen(it.check, back) }
        entry<HealthTrashRoute> { RecentlyRemovedScreen(back) }
    }
}
