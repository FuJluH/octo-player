package app.winters.octo.desktop.pages

import app.winters.octo.desktop.ui.StationPicture
import app.winters.octo.desktop.ui.PlaylistPicture
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.BoxWithConstraints
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.layout.widthIn
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.LazyListScope
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.runtime.key
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import app.winters.octo.desktop.AppState
import app.winters.octo.desktop.home.AlbumShelf
import app.winters.octo.desktop.home.SHELF_SIZE
import app.winters.octo.desktop.home.pinnedFirst
import app.winters.octo.home.EDIT_HOME
import app.winters.octo.home.HomeSection
import app.winters.octo.home.homeSectionOrder
import app.winters.octo.home.shows
import app.winters.octo.desktop.home.yourPlaylists
import app.winters.octo.desktop.library.Cover
import app.winters.octo.desktop.library.LibraryState
import app.winters.octo.desktop.nav.Page
import app.winters.octo.desktop.nav.Visit
import app.winters.octo.desktop.queue.ResumeOffer
import app.winters.octo.desktop.server.userMessage
import app.winters.octo.desktop.ui.FailedLine
import app.winters.octo.desktop.ui.LoadingLine
import app.winters.octo.desktop.ui.LocalBottomRoom
import app.winters.octo.desktop.ui.LocalKeyColour
import app.winters.octo.desktop.ui.MediaCard
import app.winters.octo.desktop.ui.PageTitle
import app.winters.octo.desktop.ui.ShelfCardWidth
import app.winters.octo.desktop.ui.pagePadding
import app.winters.octo.desktop.ui.playlistMenu
import app.winters.octo.desktop.ui.rememberListState
import app.winters.octo.design.ControlHeight
import app.winters.octo.design.scrollbar
import app.winters.octo.design.Corner
import app.winters.octo.design.DesktopType
import app.winters.octo.design.FrameSize
import app.winters.octo.design.GlazeCapsule
import app.winters.octo.design.IconSize
import app.winters.octo.design.OctoColors
import app.winters.octo.design.OctoIcons
import app.winters.octo.design.OctoType
import app.winters.octo.design.Space
import app.winters.octo.design.Spinner
import app.winters.octo.design.TextAction
import app.winters.octo.design.Txt
import app.winters.octo.subsonic.Album
import app.winters.octo.subsonic.Playlist
import app.winters.octo.subsonic.RadioStation
import app.winters.octo.subsonic.SubsonicException
import kotlinx.coroutines.launch
import app.winters.octo.desktop.ui.PlayBadge
import app.winters.octo.desktop.home.octoLists
import app.winters.octo.home.mixGroup
import app.winters.octo.desktop.liveradio.FIND_STATIONS_NEAR
import app.winters.octo.desktop.liveradio.LIVE_RADIO
import app.winters.octo.desktop.liveradio.ShelfStation
import app.winters.octo.desktop.liveradio.liveShelf
import app.winters.octo.desktop.playShelf
import app.winters.octo.desktop.ui.FindStationsArt
import app.winters.octo.desktop.ui.StationArt
import app.winters.octo.desktop.ui.liveStationMenu

// Home: picking up where another device left off, what was played lately,
// the lists Octo made for the listener and its stations, what came in, what
// is played most, favorites, playlists, then albums worth going back to.
// Every shelf is one row that fills the width, with See all where a full
// list exists.
@Composable
fun HomePage(app: AppState, visit: Visit) {
    val connection = app.connection ?: return
    val store = app.home ?: return
    // The shelves read before show at once; they are refreshed behind them.
    LaunchedEffect(store) {
        store.refresh()
        app.refreshPlaylistsIfOld()
        app.liveRadio.checkAdmin()
    }
    val library = app.library?.state?.collectAsState()?.value
    val index = (library as? LibraryState.Ready)?.index
    LaunchedEffect(store, index) { index?.let(store::rediscover) }
    val settings by app.settings.state.collectAsState()
    val listener = app.connection?.client?.username.orEmpty()
    val isOcto = app.connection?.isOcto == true
    val playlists = remember(app.playlists, settings.frame.pinnedPlaylists, listener, isOcto) {
        pinnedFirst(yourPlaylists(app.playlists, listener, isOcto), settings.frame.pinnedPlaylists)
    }
    // Octo's mixes by group, for the shelves of mixes.
    val mixes = remember(app.playlists, listener, isOcto) { octoLists(app.playlists, listener, isOcto).toMap() }
    // The server shelves show as the server last gave them until it answers.
    val shelves = store.shelves
    val forYou = shelves.madeForYou
    val stored = settings.appearance.homeSections
    val sections = remember(stored) { homeSectionOrder(stored) }
    // Stations shown again are asked for then.
    LaunchedEffect(store, sections.shows(HomeSection.Stations), sections.shows(HomeSection.InternetRadio)) { store.sectionsChanged() }
    // The Live radio shelf: the server's streams and the stations kept here.
    val live = remember(shelves.live, settings.liveRadio.kept) { liveShelf(shelves.live, app.liveRadio.kept(settings.liveRadio).stations) }
    val home = store.data
    val failure = store.failure
    val found = store.rediscovered
    val list = rememberListState(app.navigator, visit)
    var starting by remember { mutableStateOf<String?>(null) }
    fun open(shelf: AlbumShelf): () -> Unit = { app.navigator.go(Page.Shelf(shelf)) }
    LazyColumn(Modifier.scrollbar(list, LocalBottomRoom.current), state = list, contentPadding = pagePadding(LocalBottomRoom.current)) {
        item(key = "title") { PageTitle("Home") }
        app.queueSync.offer?.let { offer -> item(key = "resume") { ResumeCard(app, offer) } }
        when {
            home == null && failure != null -> item(key = "failed") { FailedLine("Couldn't read Home from your server. $failure", store::retry) }
            home == null -> item(key = "loading") { LoadingLine() }
            home.isEmpty && shelves.stations.isEmpty() && playlists.isEmpty() && forYou.isEmpty() && (found == null || found.isEmpty) -> {
                item(key = "empty") {
                    Column(verticalArrangement = Arrangement.spacedBy(Space.M)) {
                        NothingHere("No music yet", "Music on your server shows up here on its own. Once some is there, look again.")
                        GlazeCapsule(null, "Look again", {
                            store.retry()
                            app.library?.load()
                        })
                    }
                }
                // An empty library is where the charts help most: songs to start from.
                app.search?.charts?.let { chartsRow(app, it, store) }
            }
            else -> {
                // The shelves in the order saved in Settings, the hidden ones
                // left out, then a way to change them.
                sections.filter { it.shown }.forEach { entry ->
                    when (entry.section) {
                        HomeSection.RecentlyPlayed -> albums(app, entry.section.title, home.recentlyPlayed) { app.navigator.go(Page.History) }
                        HomeSection.MadeForYou -> if (forYou.isNotEmpty()) {
                            moving(key = "shelf:foryou") { ShelfRow(entry.section.title, forYou, { it.id }, null) { PlaylistCard(app, it) } }
                        }
                        HomeSection.Stations -> if (shelves.stations.isNotEmpty()) {
                            moving(key = "shelf:stations") {
                                ShelfRow(entry.section.title, shelves.stations, { it.id }, null) { station ->
                                    StationCard(app, station, starting == station.id) {
                                        if (starting != null) return@StationCard
                                        starting = station.id
                                        app.scope.launch {
                                            try {
                                                app.playStation(connection.client.playlist(station.id).entry, 0, false, station.id, station.name)
                                            } catch (e: SubsonicException.NotFound) {
                                                store.stationGone(station.id)
                                                app.notice = "${station.name} isn't on the server any more."
                                            } catch (e: SubsonicException) {
                                                app.notice = "Couldn't start ${station.name}: ${e.userMessage()}"
                                            } finally {
                                                starting = null
                                            }
                                        }
                                    }
                                }
                            }
                        }
                        HomeSection.YearMixes, HomeSection.GenreMixes, HomeSection.ArtistMixes, HomeSection.CountryMixes ->
                            mixes[entry.section.mixGroup]?.takeIf { it.isNotEmpty() }?.let { lists ->
                                moving(key = "shelf:${entry.section.id}") { ShelfRow(entry.section.title, lists, { it.id }, null) { PlaylistCard(app, it) } }
                            }
                        HomeSection.Charts -> app.search?.charts?.let { chartsRow(app, it, store) }
                        HomeSection.RecentlyAdded -> albums(app, entry.section.title, home.recentlyAdded) { app.navigator.go(Page.RecentlyAdded) }
                        HomeSection.MostPlayed ->
                            albums(app, entry.section.title, home.mostPlayed, whole = home.mostPlayed.size < SHELF_SIZE, seeAll = open(AlbumShelf.MostPlayed))
                        HomeSection.FavoriteAlbums -> {
                            albums(app, entry.section.title, home.favourites) {
                                app.navigator.go(Page.Favourites)
                                app.navigator.keepTab(app.navigator.current, "Albums")
                            }
                            // The listener's playlists go with their favorite albums.
                            if (playlists.isNotEmpty()) {
                                moving(key = "shelf:playlists") { ShelfRow("Your playlists", playlists, { it.id }, null) { PlaylistCard(app, it) } }
                            }
                        }
                        HomeSection.NotPlayedLately -> found?.let {
                            albums(app, AlbumShelf.NotPlayedLately.title, it.notPlayedLately, whole = it.notPlayedLately.size < SHELF_SIZE, seeAll = open(AlbumShelf.NotPlayedLately))
                        }
                        HomeSection.NeverFinished -> found?.let {
                            albums(app, AlbumShelf.NeverFinished.title, it.neverFinished, whole = it.neverFinished.size < SHELF_SIZE, seeAll = open(AlbumShelf.NeverFinished))
                        }
                        HomeSection.NeverPlayed -> found?.let {
                            albums(app, AlbumShelf.NeverPlayed.title, it.neverPlayed, whole = it.neverPlayed.size < SHELF_SIZE, seeAll = open(AlbumShelf.NeverPlayed))
                        }
                        // Always shown, since it opens with the way to find stations.
                        HomeSection.InternetRadio -> moving(key = "shelf:live") {
                            ShelfRow(entry.section.title, listOf<ShelfStation?>(null) + live, { it?.streamUrl ?: "find" }, { app.navigator.go(Page.LiveRadio) }) { station ->
                                if (station == null) FindStationsCard(app) else LiveShelfCard(app, station, live)
                            }
                        }
                        // Shelves only the phone draws.
                        HomeSection.Pinned, HomeSection.Artists, HomeSection.SomethingDifferent -> Unit
                    }
                }
                moving(key = "edit-home") {
                    Box(Modifier.fillMaxWidth().padding(top = Space.Section), contentAlignment = Alignment.Center) {
                        GlazeCapsule(null, EDIT_HOME, {
                            showSection("Settings", "look")
                            app.navigator.go(Page.Settings)
                        })
                    }
                }
            }
        }
    }
}

// A shelf of albums, left out when it has none. `whole` says the shelf
// already holds every album its See all page would, so See all is left
// out when they all fit.
private fun LazyListScope.albums(app: AppState, title: String, albums: List<Album>, whole: Boolean = false, seeAll: (() -> Unit)?) {
    if (albums.isEmpty()) return
    moving(key = "shelf:$title") { ShelfRow(title, albums, { it.id }, seeAll, whole) { AlbumCard(app, it) } }
}

// A part of Home that glides to its new place when the shelves are
// reordered or one is shown or hidden.
internal fun LazyListScope.moving(key: String, content: @Composable () -> Unit) {
    item(key = key) { Box(Modifier.animateItem()) { content() } }
}

// A shelf: its name, See all at the right when it leads to more, and one
// row of cards filling the width, as many as fit. No arrows and no
// sideways scrolling: the rest is behind See all.
@Composable
private fun <T> ShelfRow(title: String, items: List<T>, id: (T) -> Any, seeAll: (() -> Unit)?, whole: Boolean = false, card: @Composable (T) -> Unit) {
    BoxWithConstraints(Modifier.fillMaxWidth()) {
        val fit = (maxWidth / ShelfCardWidth).toInt().coerceAtLeast(1)
        val width = maxWidth / fit
        Column(Modifier.fillMaxWidth()) {
            // As tall with See all as without, so shelves keep one rhythm.
            Row(Modifier.fillMaxWidth().padding(top = Space.Xxl, bottom = Space.Xs).heightIn(min = ControlHeight.L), verticalAlignment = Alignment.CenterVertically) {
                Txt(title, DesktopType.section, modifier = Modifier.weight(1f).padding(start = Space.M))
                if (seeAll != null && !(whole && items.size <= fit)) TextAction("See all", seeAll)
            }
            Row {
                items.take(fit).forEach { item -> key(id(item)) { Box(Modifier.width(width)) { card(item) } } }
            }
        }
    }
}

// A playlist, opening its page, with the playlist menu on a right click.
@Composable
private fun PlaylistCard(app: AppState, playlist: Playlist) {
    val songs = if (playlist.songCount == 1) "1 song" else "${playlist.songCount} songs"
    MediaCard(
        playlist.name,
        if (app.isPinned(playlist.id)) "Pinned · $songs" else songs,
        playlist.coverArt,
        onOpen = { app.navigator.go(Page.Playlist(playlist.id)) },
        onMenu = playlistMenu(app, playlist),
        picture = { modifier, shape -> PlaylistPicture(app, playlist, modifier, shape) },
    )
}

// A station Octo runs: a click opens the songs it has lined up, and the
// play button on its cover plays the station, which keeps going.
@Composable
private fun StationCard(app: AppState, station: RadioStation, starting: Boolean, onPlay: () -> Unit) {
    MediaCard(
        station.name,
        "Station",
        station.coverArt ?: station.id,
        onOpen = { app.navigator.go(Page.Playlist(station.id)) },
        badge = { if (starting) Spinner(size = IconSize.Transport) else PlayBadge(ControlHeight.L, "Play ${station.name}", onPlay) },
        picture = { modifier, shape -> StationPicture(app, station, modifier, shape) },
    )
}

// The first card on the Live radio shelf: the way to the Live radio page.
@Composable
private fun FindStationsCard(app: AppState) {
    MediaCard(
        FIND_STATIONS_NEAR,
        LIVE_RADIO,
        null,
        onOpen = { app.navigator.go(Page.LiveRadio) },
        picture = { modifier, shape -> FindStationsArt(modifier, shape) },
    )
}

// A live station on the shelf: a click or its play button plays it, with
// the shelf's other stations around it for Back and Next. One kept here has
// its menu on a right click.
@Composable
private fun LiveShelfCard(app: AppState, station: ShelfStation, shelf: List<ShelfStation>) {
    val kept = station.kept
    val play = { app.playShelf(station, shelf) }
    MediaCard(
        station.name,
        if (station.serverId != null) "On your server" else "Kept here",
        null,
        onOpen = play,
        onMenu = kept?.let { liveStationMenu(app, it, kept = true, play = play) },
        badge = { PlayBadge(ControlHeight.L, "Play ${station.name}", play) },
        picture = { modifier, shape -> StationArt(app, station.logo, station.name, station.streamUrl, modifier, shape, station.coverArt) },
    )
}

// A queue saved on another device (the phone, most often), offered once:
// Resume loads it paused where it was left; Not now puts it away. Kept
// narrow enough that its buttons stay near its words, and in line with the
// covers below.
@Composable
private fun ResumeCard(app: AppState, offer: ResumeOffer) {
    val key = LocalKeyColour.current
    Row(
        Modifier.padding(start = Space.M).widthIn(max = FrameSize.CardMax).fillMaxWidth().padding(top = Space.M, bottom = Space.Xs)
            .settingsSurface(Corner.PanelShape, key).padding(Space.L),
        verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.spacedBy(Space.L),
    ) {
        Cover(offer.remote.current?.coverArt, Modifier.size(FrameSize.PlayerCover), shape = Corner.ArtMShape, placeholder = OctoIcons.Songs)
        Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(Space.Xxs)) {
            Txt(offer.device?.let { "Pick up where you left off on $it" } ?: "Pick up where you left off", OctoType.caption, OctoColors.TextMuted)
            Txt(offer.title, OctoType.label)
            offer.artist?.let { Txt(it, OctoType.bodySmall, OctoColors.TextSecondary) }
        }
        GlazeCapsule(null, "Not now", { app.queueSync.dismiss(offer) })
        GlazeCapsule(OctoIcons.Play, "Resume", { app.queueSync.take(offer) }, lit = true)
    }
}
