package app.winters.octo.ui.home

import app.winters.octo.ui.nav.ChartsRoute
import app.winters.octo.ui.nav.HomeSectionsRoute
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.offset
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.LazyListScope
import androidx.compose.foundation.lazy.LazyRow
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.lazy.itemsIndexed
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.ExperimentalMaterial3Api
import androidx.compose.material3.Icon
import androidx.compose.material3.Text
import androidx.compose.material3.pulltorefresh.PullToRefreshBox
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.res.painterResource
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.unit.dp
import androidx.hilt.lifecycle.viewmodel.compose.hiltViewModel
import androidx.lifecycle.compose.LifecycleResumeEffect
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import androidx.navigation3.runtime.NavKey
import app.winters.octo.catalog.AlbumEntity
import app.winters.octo.catalog.TrackEntity
import app.winters.octo.design.AccentButton
import app.winters.octo.design.ButtonSize
import app.winters.octo.design.GlazeButton
import app.winters.octo.design.OctoIcons
import app.winters.octo.design.OctoColors
import app.winters.octo.design.OctoType
import app.winters.octo.design.glassPanel
import app.winters.octo.device.Access
import app.winters.octo.discovery.Station
import app.winters.octo.home.EDIT_HOME
import app.winters.octo.home.HomeSection
import app.winters.octo.ui.common.AlbumCard
import app.winters.octo.ui.common.ArtistCircle
import app.winters.octo.ui.common.LibrarySourceActions
import app.winters.octo.ui.common.ScreenTitle
import app.winters.octo.ui.common.SectionTitle
import app.winters.octo.ui.common.SongCard
import app.winters.octo.ui.common.accessButtonLabel
import app.winters.octo.ui.common.rememberAccessRequest
import app.winters.octo.ui.common.screenPadding
import app.winters.octo.ui.nav.AlbumRoute
import app.winters.octo.ui.nav.ArtistRoute
import app.winters.octo.ui.nav.FavouritesRoute
import app.winters.octo.ui.nav.HistoryRoute
import app.winters.octo.ui.nav.ServerListRoute
import app.winters.octo.discovery.isRadio
import app.winters.octo.home.mixGroup
import app.winters.octo.home.shows
import app.winters.octo.liveradio.LiveShelfEntry
import app.winters.octo.liveradio.LiveStation
import app.winters.octo.liveradio.StationAction
import app.winters.octo.liveradio.liveShelf
import app.winters.octo.ui.common.Choice
import app.winters.octo.ui.common.ChoiceRequest
import app.winters.octo.ui.common.LocalChoiceSheet
import app.winters.octo.ui.common.choiceAnchor
import app.winters.octo.ui.liveradio.FindNearCard
import app.winters.octo.ui.liveradio.KeptStationCard
import app.winters.octo.ui.nav.LiveRadioNearRoute

@OptIn(ExperimentalMaterial3Api::class)
@Composable
fun HomeScreen(onOpen: (NavKey) -> Unit, vm: HomeViewModel = hiltViewModel()) {
    val access by vm.library.access.collectAsStateWithLifecycle()
    val recent by vm.recent.collectAsStateWithLifecycle()
    val librarySongs by vm.librarySongs.collectAsStateWithLifecycle()
    val accessDismissed by vm.accessDismissed.collectAsStateWithLifecycle()
    val recentlyPlayed by vm.recentlyPlayed.collectAsStateWithLifecycle()
    val mostPlayed by vm.mostPlayed.collectAsStateWithLifecycle()
    val pinned by vm.pinned.collectAsStateWithLifecycle()
    val favouriteAlbums by vm.favouriteAlbums.collectAsStateWithLifecycle()
    val rediscovery by vm.rediscovery.collectAsStateWithLifecycle()
    val sections by vm.sections.collectAsStateWithLifecycle()
    val keptStations by vm.keptStations.collectAsStateWithLifecycle()
    val sheet = LocalChoiceSheet.current
    // The Live radio shelf: the way to stations near the listener, then the
    // server's stations and the ones kept on this phone.
    val liveRadio: LazyListScope.(String) -> Unit = { title ->
        liveRadioShelf(
            title,
            liveShelf(vm.stations.filter { it.streamUrl != null }, keptStations.stations),
            vm.startingStation,
            onFindNear = { onOpen(LiveRadioNearRoute) },
            onPlay = vm::playLive,
            onKeptMenu = { station ->
                sheet.show(ChoiceRequest(station.name, listOf(Choice(StationAction.Remove.label)), selected = -1) { vm.removeKept(station) })
            },
        )
    }

    LifecycleResumeEffect(Unit) {
        vm.onShown()
        onPauseOrDispose { }
    }

    PullToRefreshBox(
        isRefreshing = vm.refreshing,
        onRefresh = vm::refresh,
        modifier = Modifier.fillMaxSize(),
    ) {
        LazyColumn(Modifier.fillMaxSize(), contentPadding = screenPadding()) {
            val layout = homeLayout(access, accessDismissed, librarySongs)
            item { ScreenTitle("Home") }
            if (layout.askAccess) item(key = "access") { AccessCard(access, vm) }
            item(key = "resume") { ResumeCard() }
            item(key = "whats-new") { WhatsNewCard() }
            when {
                layout.empty -> {
                    item(key = "empty") { EmptyCard(offerAccess = !layout.askAccess) }
                    // An empty library is where the charts and live radio
                    // help most: music to start from.
                    songShelf("Charts", vm.charts, vm::play, onTitle = { onOpen(ChartsRoute) })
                    if (sections?.shows(HomeSection.InternetRadio) != false) liveRadio(HomeSection.InternetRadio.title)
                }
                layout.shelves -> {
                    // The shelves in the order kept in Settings, the hidden
                    // ones left out, then a way to change them. Nothing is
                    // drawn until the order is read.
                    val order = sections
                    order?.filter { it.shown }.orEmpty().forEach { entry ->
                        val title = entry.section.title
                        when (entry.section) {
                            HomeSection.Pinned -> pinnedShelf(pinned, onOpen)
                            HomeSection.RecentlyPlayed -> shelf(title, recentlyPlayed, onOpen, onTitle = { onOpen(HistoryRoute()) })
                            HomeSection.MadeForYou -> stationShelf(title, vm.madeForYou, vm.startingStation, onOpen, vm::playStation)
                            HomeSection.Stations -> stationShelf(title, vm.stations.filter { it.streamUrl == null }, vm.startingStation, onOpen, vm::playStation)
                            HomeSection.InternetRadio -> liveRadio(title)
                            HomeSection.YearMixes, HomeSection.GenreMixes, HomeSection.ArtistMixes, HomeSection.CountryMixes ->
                                stationShelf(title, vm.mixes[entry.section.mixGroup].orEmpty(), vm.startingStation, onOpen, vm::playStation)
                            HomeSection.RecentlyAdded -> shelf(title, recent.orEmpty(), onOpen)
                            HomeSection.MostPlayed -> songShelf(title, mostPlayed, vm::play, onTitle = { onOpen(HistoryRoute(mostPlayed = true)) })
                            HomeSection.FavoriteAlbums -> shelf(title, favouriteAlbums, onOpen, onTitle = { onOpen(FavouritesRoute(albums = true)) })
                            HomeSection.Charts -> songShelf(title, vm.charts, vm::play, onTitle = { onOpen(ChartsRoute) })
                            HomeSection.Artists -> artistShelf(vm, onOpen)
                            HomeSection.SomethingDifferent -> shelf(title, vm.surprise, onOpen)
                            HomeSection.NotPlayedLately -> shelf(title, rediscovery.notPlayedLately, onOpen)
                            HomeSection.NeverFinished -> shelf(title, rediscovery.neverFinished, onOpen)
                            HomeSection.NeverPlayed -> shelf(title, rediscovery.neverPlayed, onOpen)
                        }
                    }
                    if (order != null) moving(key = "edit-home") {
                        Box(Modifier.fillMaxWidth().padding(top = 32.dp, bottom = 8.dp), contentAlignment = Alignment.Center) {
                            GlazeButton(EDIT_HOME, onClick = { onOpen(HomeSectionsRoute) }, size = ButtonSize.Small)
                        }
                    }
                }
            }
        }
    }
}

// A part of Home that glides to its new place when the shelves are
// reordered or one is shown or hidden.
private fun LazyListScope.moving(key: String, content: @Composable () -> Unit) {
    item(key = key) { Box(Modifier.animateItem()) { content() } }
}

// A row of the library's artists, picked at random.
private fun LazyListScope.artistShelf(vm: HomeViewModel, onOpen: (NavKey) -> Unit) {
    if (vm.artists.isEmpty()) return
    val title = HomeSection.Artists.title
    moving(key = "title:$title") { SectionTitle(title, Modifier.padding(top = 18.dp)) }
    moving(key = "row:$title") {
        LazyRow(
            contentPadding = PaddingValues(horizontal = 20.dp),
            horizontalArrangement = Arrangement.spacedBy(14.dp),
        ) {
            items(vm.artists, key = { it.id }) { artist ->
                ArtistCircle(artist) { onOpen(ArtistRoute(artist.id)) }
            }
        }
    }
}

private fun LazyListScope.shelf(
    title: String,
    albums: List<AlbumEntity>,
    onOpen: (NavKey) -> Unit,
    onTitle: (() -> Unit)? = null,
) {
    if (albums.isEmpty()) return
    moving(key = "title:$title") { ShelfTitle(title, onTitle) }
    moving(key = "row:$title") {
        LazyRow(
            contentPadding = PaddingValues(horizontal = 20.dp),
            horizontalArrangement = Arrangement.spacedBy(14.dp),
        ) {
            items(albums, key = { it.id }) { album ->
                AlbumCard(album, onClick = { onOpen(AlbumRoute(album.id)) })
            }
        }
    }
}

// A row of songs; tapping one plays the row from that song.
private fun LazyListScope.songShelf(
    title: String,
    tracks: List<TrackEntity>,
    onPlay: (List<TrackEntity>, Int) -> Unit,
    onTitle: (() -> Unit)? = null,
) {
    if (tracks.isEmpty()) return
    moving(key = "title:$title") { ShelfTitle(title, onTitle) }
    moving(key = "row:$title") {
        LazyRow(
            contentPadding = PaddingValues(horizontal = 20.dp),
            horizontalArrangement = Arrangement.spacedBy(14.dp),
        ) {
            itemsIndexed(tracks, key = { _, track -> track.id }) { index, track ->
                SongCard(track, onClick = { onPlay(tracks, index) })
            }
        }
    }
}

// A shelf's name. One that leads to a page of its own is a button, with a
// chevron saying so.
@Composable
private fun ShelfTitle(title: String, onClick: (() -> Unit)?) {
    if (onClick == null) {
        SectionTitle(title, Modifier.padding(top = 18.dp))
        return
    }
    Row(
        Modifier
            .padding(top = 18.dp)
            .clickable(role = Role.Button, onClickLabel = "Open $title", onClick = onClick),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        SectionTitle(title)
        // Drawn into the title's own end margin, close to the words.
        Icon(
            painterResource(OctoIcons.Chevron),
            contentDescription = null,
            tint = OctoColors.TextMuted,
            modifier = Modifier.offset(x = (-16).dp).size(22.dp),
        )
    }
}

// The server's stations, or the lists it made for the listener; tapping
// one opens what it has lined up, its play button plays it.
private fun LazyListScope.stationShelf(
    title: String,
    stations: List<Station>,
    starting: String?,
    onOpen: (NavKey) -> Unit,
    onPlay: (Station) -> Unit,
) {
    if (stations.isEmpty()) return
    moving(key = "title:$title") { SectionTitle(title, Modifier.padding(top = 18.dp)) }
    moving(key = "row:$title") {
        LazyRow(
            contentPadding = PaddingValues(horizontal = 20.dp),
            horizontalArrangement = Arrangement.spacedBy(14.dp),
        ) {
            items(stations, key = { it.id }) { station ->
                StationCard(
                    station,
                    starting = station.id == starting,
                    onOpen = { onOpen(ServerListRoute(station.id, station.name, station.artwork, radio = station.isRadio)) },
                    onPlay = { onPlay(station) },
                )
            }
        }
    }
}

// Live radio: always there, led by the card to stations near the listener,
// then the server's stations and those kept on this phone. A server station
// or a kept one plays at a tap; a long press on a kept one offers to remove it.
private fun LazyListScope.liveRadioShelf(
    title: String,
    entries: List<LiveShelfEntry>,
    starting: String?,
    onFindNear: () -> Unit,
    onPlay: (List<LiveShelfEntry>, Int) -> Unit,
    onKeptMenu: (LiveStation) -> Unit,
) {
    moving(key = "title:$title") { SectionTitle(title, Modifier.padding(top = 18.dp)) }
    moving(key = "row:$title") {
        LazyRow(
            contentPadding = PaddingValues(horizontal = 20.dp),
            horizontalArrangement = Arrangement.spacedBy(14.dp),
        ) {
            item(key = "find-near") { FindNearCard(onFindNear) }
            itemsIndexed(entries, key = { _, it -> it.key }) { index, entry ->
                when (entry) {
                    is LiveShelfEntry.Server -> StationCard(
                        entry.station,
                        starting = entry.station.id == starting,
                        onOpen = { onPlay(entries, index) },
                        onPlay = { onPlay(entries, index) },
                    )
                    is LiveShelfEntry.Kept -> KeptStationCard(
                        entry.station,
                        onPlay = { onPlay(entries, index) },
                        onLongPress = { onKeptMenu(entry.station) },
                        modifier = Modifier.choiceAnchor(LocalChoiceSheet.current),
                    )
                }
            }
        }
    }
}

// A quiet ask for the music on the phone, above everything else. "Not now"
// puts it away for good; the empty Library pages still offer access.
@Composable
private fun AccessCard(access: Access, vm: HomeViewModel) {
    val requestAccess = rememberAccessRequest(vm.library, access)
    Column(
        Modifier
            .padding(horizontal = 20.dp)
            .padding(bottom = 12.dp)
            .fillMaxWidth()
            .glassPanel(RoundedCornerShape(20.dp))
            .padding(20.dp),
        verticalArrangement = Arrangement.spacedBy(6.dp),
    ) {
        Text("Music on this phone", style = OctoType.bodySmall, color = OctoColors.TextPrimary)
        Text(
            "Allow access to play the music already on your phone here too.",
            style = OctoType.caption,
            color = OctoColors.TextSecondary,
        )
        Row(Modifier.padding(top = 10.dp), horizontalArrangement = Arrangement.spacedBy(12.dp)) {
            AccentButton(if (access == Access.DeniedForever) accessButtonLabel(access) else "Allow", onClick = requestAccess)
            GlazeButton("Not now", onClick = vm::dismissAccess)
        }
    }
}

// A library with no songs at all, from anywhere. `offerAccess` is off
// while the access card above already asks.
@Composable
private fun EmptyCard(offerAccess: Boolean) {
    Column(Modifier.padding(horizontal = 20.dp), verticalArrangement = Arrangement.spacedBy(6.dp)) {
        Text("No music yet", style = OctoType.headline, color = OctoColors.TextPrimary)
        Text(
            "Songs on this phone and on your server show up here on their own.",
            style = OctoType.bodySmall,
            color = OctoColors.TextMuted,
        )
        LibrarySourceActions(Modifier.padding(top = 12.dp), offerAccess = offerAccess)
    }
}
