package app.winters.octo.ui.search

import app.winters.octo.ui.common.LocalReduceMotion
import androidx.compose.animation.core.tween
import androidx.compose.animation.core.rememberInfiniteTransition
import androidx.compose.animation.core.infiniteRepeatable
import androidx.compose.animation.core.animateFloat
import androidx.compose.animation.core.RepeatMode
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.ui.semantics.LiveRegionMode
import androidx.compose.ui.semantics.liveRegion
import androidx.compose.ui.semantics.clearAndSetSemantics
import app.winters.octo.ui.common.ListRowSide
import app.winters.octo.catalog.ArtistEntity
import app.winters.octo.catalog.AlbumEntity
import app.winters.octo.discovery.OnlineArtist
import app.winters.octo.discovery.OnlineAlbum
import app.winters.octo.ui.family.TRY_AGAIN
import app.winters.octo.covers.playlistGlyph
import app.winters.octo.ui.common.phonePlaylistFooter
import app.winters.octo.ui.common.PlaylistArtwork
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.WindowInsets
import androidx.compose.foundation.layout.asPaddingValues
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.navigationBars
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.statusBarsPadding
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.LazyListScope
import androidx.compose.foundation.lazy.LazyRow
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.lazy.rememberLazyListState
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.text.KeyboardActions
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.material3.Icon
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.remember
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.input.nestedscroll.NestedScrollConnection
import androidx.compose.ui.input.nestedscroll.NestedScrollSource
import androidx.compose.ui.input.nestedscroll.nestedScroll
import androidx.compose.ui.platform.LocalSoftwareKeyboardController
import androidx.compose.ui.platform.SoftwareKeyboardController
import androidx.compose.ui.res.painterResource
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.input.ImeAction
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.hilt.lifecycle.viewmodel.compose.hiltViewModel
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import androidx.navigation3.runtime.NavKey
import app.winters.octo.design.OctoIcons
import app.winters.octo.catalog.TrackEntity
import app.winters.octo.design.GlassInput
import app.winters.octo.design.OctoColors
import app.winters.octo.design.OctoType
import app.winters.octo.discovery.Discovered
import app.winters.octo.discovery.RankedTracks
import app.winters.octo.discovery.SEARCH_TOP_SHOWN
import app.winters.octo.discovery.TOP_CHART_SHOWN
import app.winters.octo.discovery.playsText
import app.winters.octo.discovery.rankedBy
import app.winters.octo.ui.common.SelectableSongs
import app.winters.octo.ui.common.Pickable
import app.winters.octo.ui.common.AlbumCard
import app.winters.octo.ui.common.ArtistCircle
import app.winters.octo.ui.common.ArtistRow
import app.winters.octo.discovery.LIBRARY_ONLY_SETTING
import app.winters.octo.discovery.inLibraryOnly
import app.winters.octo.ui.common.LocalLibraryOnly
import app.winters.octo.ui.common.LocalSetLibraryOnly
import app.winters.octo.ui.library.FilterChip
import app.winters.octo.ui.common.QuietButton
import app.winters.octo.ui.common.ScreenTitle
import app.winters.octo.ui.common.SectionTitle
import app.winters.octo.ui.common.Segmented
import app.winters.octo.ui.common.SongLead
import app.winters.octo.ui.common.SongRow
import app.winters.octo.ui.common.rowAlbum
import app.winters.octo.ui.common.songs
import app.winters.octo.ui.liveradio.FindNearRow
import app.winters.octo.ui.nav.AlbumRoute
import app.winters.octo.ui.nav.LiveRadioNearRoute
import app.winters.octo.ui.nav.ArtistRoute
import app.winters.octo.ui.nav.OnlineAlbumRoute
import app.winters.octo.ui.nav.OnlineArtistRoute
import app.winters.octo.ui.nav.PlaylistRoute
import app.winters.octo.ui.playlist.PlaylistCover
import app.winters.octo.ui.playlist.PlaylistLine

@Composable
fun SearchScreen(onOpen: (NavKey) -> Unit, vm: SearchViewModel = hiltViewModel()) {
    val results by vm.results.collectAsStateWithLifecycle()
    val signedIn by vm.signedIn.collectAsStateWithLifecycle()
    val discover by vm.discover.collectAsStateWithLifecycle()
    val recent by vm.recent.collectAsStateWithLifecycle()
    val addHint by vm.addHint.collectAsStateWithLifecycle()
    val anyTop by vm.topSongs.collectAsStateWithLifecycle()
    val anyChart by vm.chart.collectAsStateWithLifecycle()
    // "Library songs only" leaves out what the server found online.
    val libraryOnly = LocalLibraryOnly.current
    val setLibraryOnly = LocalSetLibraryOnly.current
    val top = if (libraryOnly) anyTop?.inLibraryOnly() else anyTop
    val chart = if (libraryOnly) anyChart?.inLibraryOnly() else anyChart
    val bottom = WindowInsets.navigationBars.asPaddingValues().calculateBottomPadding() + 120.dp
    val keyboard = LocalSoftwareKeyboardController.current
    val list = rememberLazyListState()
    val hider = rememberKeyboardHider(keyboard)
    // Opening a result keeps the search among the recent ones.
    val open: (NavKey) -> Unit = { key ->
        vm.keepSearch()
        onOpen(key)
    }
    val filter = vm.filter
    val pick: (SearchFilter) -> Unit = {
        vm.filter = it
        list.requestScrollToItem(0)
    }

    Column(Modifier.fillMaxSize().statusBarsPadding().padding(top = 8.dp)) {
        ScreenTitle("Search")
        GlassInput(
            value = vm.text,
            onValueChange = { vm.text = it },
            placeholder = "Songs, albums, artists",
            keyboardOptions = KeyboardOptions(imeAction = ImeAction.Search),
            keyboardActions = KeyboardActions(onSearch = { keyboard?.hide() }),
            modifier = Modifier.padding(horizontal = 20.dp),
            trailing = if (vm.text.isEmpty()) null else ({ ClearButton { vm.text = "" } }),
        )
        Segmented(
            options = SearchFilter.entries.map { it.label },
            selected = filter.ordinal,
            onSelect = { pick(SearchFilter.entries[it]) },
            modifier = Modifier.padding(start = 20.dp, end = 20.dp, top = 12.dp),
        )
        if (signedIn) {
            FilterChip(LIBRARY_ONLY_SETTING, libraryOnly, Modifier.padding(start = 20.dp, top = 10.dp)) { setLibraryOnly(!libraryOnly) }
        }
        val found = results
        // What the server found, of the kinds the filter shows, less any
        // song the library results already list.
        val online = if (libraryOnly) DiscoverState.Idle else discover.only(filter).without(found?.listedFinds.orEmpty())
        // Nothing to show online: not looking, or looked and found nothing.
        val nothingOnline = online is DiscoverState.Idle || (online is DiscoverState.Done && online.found.isEmpty)
        when {
            // Before anything is typed: the way to live radio near the
            // listener, the last searches and the chart.
            vm.text.isBlank() -> RecentList(
                recent,
                hider,
                onSearch = {
                    keyboard?.hide()
                    vm.searchAgain(it)
                },
                onForget = vm::forget,
                onForgetAll = vm::forgetAll,
                before = { item(key = "live-near") { FindNearRow(onClick = { onOpen(LiveRadioNearRoute) }, modifier = Modifier.padding(bottom = 8.dp)) } },
            ) {
                chart?.let { list ->
                    rankedSection(
                        "chart", "Popular right now", list, TOP_CHART_SHOWN, vm.chartOpen, { vm.chartOpen = it },
                        withArtist = true, top = recent.isNotEmpty(),
                    ) { vm.playRanked(list, it) }
                }
                if (recent.isEmpty() && chart == null) {
                    item(key = "hint") { Hint(if (signedIn) "Search your music and discover more" else "Search the music on your phone") }
                }
            }
            found == null -> Hint(if (signedIn) "Search your music and discover more" else "Search the music on your phone")
            found.isEmpty && nothingOnline -> Hint("No results for \"${vm.text.trim()}\"")
            // Songs from the library and from the server can be picked together.
            else -> SelectableSongs(pickableResults(found, online, top)) {
                val query = vm.text.trim()
                LazyColumn(
                    Modifier.fillMaxSize().nestedScroll(hider),
                    state = list,
                    contentPadding = PaddingValues(top = 12.dp, bottom = bottom),
                ) {
                    val shown = Shown(found, online, query, addHint, open, vm::playSong, vm::playFound, vm::retryOnline, vm::addHintSeen)
                    if (filter == SearchFilter.All) {
                        everything(shown, pick) {
                            top?.let { list ->
                                rankedSection(
                                    "top", "Top songs", list, SEARCH_TOP_SHOWN, vm.topOpen, { vm.topOpen = it },
                                    withArtist = false, top = true,
                                ) { vm.playRanked(list, it) }
                            }
                        }
                    } else {
                        oneKind(shown, filter)
                    }
                }
            }
        }
    }
}

// What a search shows and what its rows do: the library's results, what the
// server found online (already narrowed to the filter's kinds), and the
// line between them.
private class Shown(
    val found: SearchResults,
    val online: DiscoverState,
    val query: String,
    val hint: Boolean,
    val onOpen: (NavKey) -> Unit,
    val onPlay: (TrackEntity) -> Unit,
    val onPlayFound: (TrackEntity) -> Unit,
    val onRetry: () -> Unit,
    val onHintSeen: () -> Unit,
) {
    val finds: Discovered? = (online as? DiscoverState.Done)?.found

    // Whether the server is asked at all, so library songs keep the add
    // button's space and their lengths line up with the finds'.
    val wanted: Boolean = online !is DiscoverState.Idle

    // Where looking online stands for one kind, by how many of it came back.
    fun look(count: Int): OutsideLook = outsideLook(
        wanted = wanted,
        looking = online is DiscoverState.Loading,
        failed = online is DiscoverState.Failed,
        songs = count,
    )
}

// A few of every kind, each kind one list: the library's first, then what
// the server found online. Songs come right under the artists, so songs
// found online are on the first screen whatever the library holds: a few
// library songs, then a few finds, or, while the server looks, a line that
// says so over rows that hold their place. An artist the library lacks
// joins the row of library artists, or, when there is none, gets a row of
// its own lower down, so nothing above the songs moves when it arrives.
private fun LazyListScope.everything(
    shown: Shown,
    onSeeAll: (SearchFilter) -> Unit,
    afterSongs: LazyListScope.() -> Unit = {},
) {
    val found = shown.found
    val finds = shown.finds
    var first = true
    fun title(text: String, more: Boolean, kind: SearchFilter, key: String = text) {
        val top = !first
        first = false
        item(key = "title:$key") {
            KindTitle(text, top, onSeeAll = if (more) ({ onSeeAll(kind) }) else null)
        }
    }
    val onlineArtists = finds?.artists.orEmpty()
    if (found.artists.isNotEmpty()) {
        title("Artists", found.moreArtists, SearchFilter.Artists)
        item(key = "artists") { ArtistCircles(found.artists, onlineArtists, shown.onOpen) }
    }
    val onlineSongs = finds?.songs.orEmpty()
    val look = shown.look(onlineSongs.size)
    if (songsShown(found.songs.size, look)) {
        title("Songs", moreSongsThanShown(found.songs.size, onlineSongs.size), SearchFilter.Songs)
        items(found.songs.take(LIBRARY_SONGS_SHOWN), key = { it.id }) { track -> SongRow(track, offerAdd = shown.wanted) { shown.onPlay(track) } }
        outsideRows(shown, look, "songs", onlineSongs.take(ONLINE_SONGS_SHOWN))
    }
    afterSongs()
    val onlineAlbums = finds?.let { it.partAlbums + it.albums }.orEmpty()
    if (found.albums.isNotEmpty() || onlineAlbums.isNotEmpty()) {
        title("Albums", found.moreAlbums, SearchFilter.Albums)
        item(key = "albums") {
            LazyRow(
                contentPadding = PaddingValues(horizontal = 20.dp),
                horizontalArrangement = Arrangement.spacedBy(14.dp),
            ) {
                items(found.albums, key = { it.id }) { album ->
                    AlbumCard(album, onClick = { shown.onOpen(AlbumRoute(album.id)) })
                }
                items(onlineAlbums, key = { "online:${it.id}" }) { album ->
                    AlbumCard(album, onClick = { shown.onOpen(OnlineAlbumRoute(album.id)) })
                }
            }
        }
    }
    if (found.playlists.isNotEmpty()) {
        title("Playlists", found.morePlaylists, SearchFilter.Playlists)
        playlistRows(found, shown.onOpen)
    }
    if (found.artists.isEmpty() && onlineArtists.isNotEmpty()) {
        title("Artists", more = false, SearchFilter.Artists, key = "online-artists")
        item(key = "online-artists") { ArtistCircles(emptyList(), onlineArtists, shown.onOpen) }
    }
}

// The library's artists, then those found online, in one row.
@Composable
private fun ArtistCircles(library: List<ArtistEntity>, online: List<OnlineArtist>, onOpen: (NavKey) -> Unit) {
    LazyRow(
        contentPadding = PaddingValues(horizontal = 20.dp),
        horizontalArrangement = Arrangement.spacedBy(14.dp),
    ) {
        items(library, key = { it.id }) { artist ->
            ArtistCircle(artist) { onOpen(ArtistRoute(artist.id)) }
        }
        items(online, key = { "online:${it.id}" }) { artist ->
            ArtistCircle(artist) { onOpen(OnlineArtistRoute(artist.id)) }
        }
    }
}

// All of one kind, as one list: rows for songs, artists and playlists, and
// covers two to a row for albums, the library's first and then those found
// online, with the line about looking online after them.
private fun LazyListScope.oneKind(shown: Shown, filter: SearchFilter) {
    val found = shown.found
    val finds = shown.finds
    when (filter) {
        SearchFilter.Artists -> {
            items(found.artists, key = { it.id }) { artist -> ArtistRow(artist) { shown.onOpen(ArtistRoute(artist.id)) } }
            val online = finds?.artists.orEmpty()
            items(online, key = { "online:${it.id}" }) { artist -> ArtistRow(artist) { shown.onOpen(OnlineArtistRoute(artist.id)) } }
            outsideRows(shown, shown.look(online.size), "artists", emptyList())
        }
        SearchFilter.Albums -> {
            val online = finds?.let { it.partAlbums + it.albums }.orEmpty()
            val cards = found.albums.map { AlbumItem.Library(it) } + online.map { AlbumItem.Online(it) }
            items(cards.chunked(2), key = { pair -> pair.first().key }) { pair ->
                Row(
                    Modifier.fillMaxWidth().padding(horizontal = 20.dp, vertical = 9.dp),
                    horizontalArrangement = Arrangement.spacedBy(14.dp),
                ) {
                    pair.forEach { card ->
                        when (card) {
                            is AlbumItem.Library -> AlbumCard(card.album, onClick = { shown.onOpen(AlbumRoute(card.album.id)) }, modifier = Modifier.weight(1f), width = null)
                            is AlbumItem.Online -> AlbumCard(card.album, onClick = { shown.onOpen(OnlineAlbumRoute(card.album.id)) }, modifier = Modifier.weight(1f), width = null)
                        }
                    }
                    if (pair.size == 1) Spacer(Modifier.weight(1f))
                }
            }
            outsideRows(shown, shown.look(online.size), "albums", emptyList())
        }
        SearchFilter.Playlists -> playlistRows(found, shown.onOpen)
        else -> {
            items(found.songs, key = { it.id }) { track -> SongRow(track, offerAdd = shown.wanted) { shown.onPlay(track) } }
            val online = finds?.songs.orEmpty()
            outsideRows(shown, shown.look(online.size), "songs", online)
        }
    }
}

// A library album or one found online, for the grid of albums.
private sealed interface AlbumItem {
    val key: String

    class Library(val album: AlbumEntity) : AlbumItem {
        override val key get() = album.id
    }

    class Online(val album: OnlineAlbum) : AlbumItem {
        override val key get() = "online:${album.id}"
    }
}

private fun LazyListScope.playlistRows(found: SearchResults, onOpen: (NavKey) -> Unit) {
    items(found.playlists, key = { "playlist:${it.id}" }) { playlist ->
        PlaylistLine(playlist.name, songs(playlist.songCount), onClick = { onOpen(PlaylistRoute(playlist.id)) }, onServer = playlist.onServer) {
            PlaylistArtwork(playlist.id, playlist.name, playlist.covers, 56.dp, footer = phonePlaylistFooter(playlist.songCount), glyph = playlistGlyph(playlist.octoNotice, null)) {
                PlaylistCover(playlist.covers, 56.dp)
            }
        }
    }
}

// A kind's name over its results, with "See all" when there are more.
@Composable
private fun KindTitle(text: String, spaced: Boolean, onSeeAll: (() -> Unit)?) {
    Row(
        Modifier.fillMaxWidth().padding(top = if (spaced) 12.dp else 0.dp, end = 10.dp),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        SectionTitle(text, Modifier.weight(1f))
        if (onSeeAll != null) QuietButton("See all", onSeeAll)
    }
}

// The last searches, while the field is empty: a tap searches again, the
// cross forgets one. `before` comes above them and `after` below.
@Composable
private fun RecentList(
    recent: List<String>,
    hider: NestedScrollConnection,
    onSearch: (String) -> Unit,
    onForget: (String) -> Unit,
    onForgetAll: () -> Unit,
    before: LazyListScope.() -> Unit = {},
    after: LazyListScope.() -> Unit = {},
) {
    LazyColumn(Modifier.fillMaxSize().nestedScroll(hider), contentPadding = PaddingValues(top = 12.dp, bottom = 140.dp)) {
        before()
        if (recent.isNotEmpty()) {
            item(key = "recent:title") {
                Row(Modifier.fillMaxWidth().padding(end = 10.dp), verticalAlignment = Alignment.CenterVertically) {
                    SectionTitle("Recent searches", Modifier.weight(1f))
                    QuietButton("Clear all", onForgetAll)
                }
            }
        }
        items(recent, key = { "recent:$it" }) { query ->
            Row(
                Modifier
                    .fillMaxWidth()
                    .clickable(role = Role.Button, onClickLabel = "Search again") { onSearch(query) }
                    .height(48.dp)
                    .padding(start = 20.dp, end = 8.dp)
                    .animateItem(),
                verticalAlignment = Alignment.CenterVertically,
            ) {
                Text(
                    query,
                    style = OctoType.body,
                    color = OctoColors.TextPrimary,
                    maxLines = 1,
                    overflow = TextOverflow.Ellipsis,
                    modifier = Modifier.weight(1f),
                )
                CrossButton("Remove $query") { onForget(query) }
            }
        }
        after()
    }
}

// Empties the field.
@Composable
private fun ClearButton(onClick: () -> Unit) = CrossButton("Clear search", onClick)

@Composable
private fun CrossButton(description: String, onClick: () -> Unit) {
    Box(
        Modifier
            .size(40.dp)
            .clip(CircleShape)
            .clickable(role = Role.Button, onClick = onClick)
            .semantics { contentDescription = description },
        contentAlignment = Alignment.Center,
    ) {
        Icon(painterResource(OctoIcons.Close), contentDescription = null, tint = OctoColors.TextMuted, modifier = Modifier.size(20.dp))
    }
}

// Puts the keyboard away as soon as a list is dragged.
@Composable
private fun rememberKeyboardHider(keyboard: SoftwareKeyboardController?): NestedScrollConnection = remember(keyboard) {
    object : NestedScrollConnection {
        override fun onPreScroll(available: Offset, source: NestedScrollSource): Offset {
            if (source == NestedScrollSource.UserInput && available.y != 0f) keyboard?.hide()
            return Offset.Zero
        }
    }
}

// The server's finds of the kinds a filter shows. Playlists are only ever
// the listener's own, so that filter shows none.
private fun DiscoverState.only(filter: SearchFilter): DiscoverState {
    if (filter == SearchFilter.Playlists) return DiscoverState.Idle
    if (this !is DiscoverState.Done || filter == SearchFilter.All) return this
    val found = found
    return DiscoverState.Done(
        Discovered(
            songs = if (filter == SearchFilter.Songs) found.songs else emptyList(),
            albums = if (filter == SearchFilter.Albums) found.albums else emptyList(),
            artists = if (filter == SearchFilter.Artists) found.artists else emptyList(),
            partAlbums = if (filter == SearchFilter.Albums) found.partAlbums else emptyList(),
        ),
    )
}

// The server's finds, less the songs the library results already list.
private fun DiscoverState.without(listed: Set<String>): DiscoverState =
    if (this is DiscoverState.Done && listed.isNotEmpty()) DiscoverState.Done(found.without(listed)) else this

// Under the library's results of a kind: while the server looks, a line
// saying so over rows that hold the finds' place; when it found songs, the
// same line, quieter, the first few times a line saying what the plus does,
// then the songs; when it found none, or could not be asked, a line that
// says so plainly, with Try again for the second.
private fun LazyListScope.outsideRows(shown: Shown, look: OutsideLook, kind: String, songs: List<TrackEntity>) {
    when (look) {
        OutsideLook.Off -> Unit
        OutsideLook.Looking -> {
            item(key = "outside:$kind:line") { OutsideLine(look, shown.query, kind) }
            items(WAITING_ROWS, key = { "outside:$kind:waiting:$it" }) { WaitingRow(round = kind == "artists", n = it) }
        }
        OutsideLook.NoneFound -> item(key = "outside:$kind:line") { OutsideLine(look, shown.query, kind) }
        OutsideLook.Failed -> item(key = "outside:$kind:line") { OutsideLine(look, shown.query, kind, shown.onRetry) }
        OutsideLook.Found -> {
            // The line stays where it said it was looking, quieter, over
            // the finds that took the waiting rows' places.
            if (songs.isNotEmpty()) item(key = "outside:$kind:line") { OutsideLine(look, shown.query, kind) }
            if (shown.hint && songs.isNotEmpty()) item(key = "outside:hint") { AddHintLine(shown.onHintSeen) }
            items(songs, key = { "discover:${it.id}" }) { track ->
                SongRow(track, offerAdd = true) { shown.onPlayFound(track) }
            }
        }
    }
}

// The line between the library's results and the server's, on the rows'
// lines: its mark centred where their covers are, its words where their
// titles start. A small spinner while the server looks, a warning mark
// when it could not be asked, the plus over the finds.
@Composable
private fun OutsideLine(look: OutsideLook, query: String, kind: String, onRetry: (() -> Unit)? = null) {
    val text = outsideLine(look, query, kind) ?: return
    Row(
        Modifier.fillMaxWidth().heightIn(min = 48.dp).padding(start = ListRowSide, end = 10.dp),
        verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.spacedBy(12.dp),
    ) {
        Box(Modifier.size(44.dp), contentAlignment = Alignment.Center) {
            when (look) {
                OutsideLook.Looking -> CircularProgressIndicator(color = OctoColors.Accent, strokeWidth = 2.dp, modifier = Modifier.size(18.dp))
                OutsideLook.Failed -> Icon(painterResource(OctoIcons.Info), contentDescription = null, tint = OctoColors.SignalOrange, modifier = Modifier.size(18.dp))
                OutsideLook.Found -> Icon(painterResource(OctoIcons.NotInLibrary), contentDescription = null, tint = OctoColors.TextMuted, modifier = Modifier.size(18.dp))
                else -> Icon(painterResource(OctoIcons.Search), contentDescription = null, tint = OctoColors.TextMuted, modifier = Modifier.size(18.dp))
            }
        }
        Text(
            text,
            style = OctoType.bodySmall,
            color = when (look) {
                OutsideLook.Failed -> OctoColors.TextPrimary
                OutsideLook.Found -> OctoColors.TextMuted
                else -> OctoColors.TextSecondary
            },
            modifier = Modifier.weight(1f).semantics { liveRegion = LiveRegionMode.Polite },
        )
        if (onRetry != null) QuietButton(TRY_AGAIN, onRetry)
    }
}

// A row that holds a find's place while the server looks: the shape of a
// song row (or an artist's, round), in the faint fill of an empty cover,
// its lines a little longer or shorter from row to row.
@Composable
private fun WaitingRow(round: Boolean, n: Int) {
    Row(
        Modifier.fillMaxWidth().heightIn(min = if (round) 64.dp else 56.dp).padding(horizontal = ListRowSide, vertical = 4.dp).clearAndSetSemantics {},
        verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.spacedBy(12.dp),
    ) {
        // Breathing slowly, unless motion is reduced.
        val breath = if (LocalReduceMotion.current) 1f else rememberInfiniteTransition(label = "waiting").animateFloat(
            initialValue = 1f,
            targetValue = 0.45f,
            animationSpec = infiniteRepeatable(tween(900), RepeatMode.Reverse),
            label = "breath",
        ).value
        val fill = OctoColors.TextPrimary.copy(alpha = 0.10f * breath)
        Box(Modifier.size(if (round) 48.dp else 44.dp).background(fill, if (round) CircleShape else RoundedCornerShape(6.dp)))
        Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(7.dp)) {
            Box(Modifier.fillMaxWidth(listOf(0.55f, 0.42f, 0.62f, 0.48f)[n % 4]).height(11.dp).background(fill, RoundedCornerShape(4.dp)))
            Box(Modifier.fillMaxWidth(listOf(0.35f, 0.3f, 0.4f, 0.26f)[n % 4]).height(9.dp).background(fill, RoundedCornerShape(4.dp)))
        }
    }
}

// What the plus does, in a muted line under the title. Counted as seen once
// it is on screen.
@Composable
private fun AddHintLine(onSeen: () -> Unit) {
    LaunchedEffect(Unit) { onSeen() }
    Text(
        "Tap + to add a song to your library.",
        style = OctoType.caption,
        color = OctoColors.TextMuted,
        modifier = Modifier.fillMaxWidth().padding(start = 20.dp, end = 20.dp, bottom = 2.dp),
    )
}

@Composable
private fun Hint(text: String) {
    Text(
        text,
        style = OctoType.bodySmall,
        color = OctoColors.TextMuted,
        modifier = Modifier.fillMaxWidth().padding(horizontal = 20.dp, vertical = 24.dp),
    )
}

// Every song shown, library ones first, each once, for picking several.
@Composable
private fun pickableResults(found: SearchResults, online: DiscoverState, top: RankedTracks?): List<Pickable> {
    val discovered = (online as? DiscoverState.Done)?.found?.songs.orEmpty()
    return remember(found, discovered, top) {
        (found.songs + discovered + top?.songs.orEmpty().map { it.track }).distinctBy { it.id }.map { Pickable(it.id, it) }
    }
}

// A ranked list: its title, with "Show all" when it has more than `shown`,
// a quiet line saying what it is ranked by, and its songs, each with its
// place and cover, and a check for one in the library or a plus that adds
// it. A tap plays the list from that song.
private fun LazyListScope.rankedSection(
    key: String,
    title: String,
    list: RankedTracks,
    shown: Int,
    open: Boolean,
    onOpen: (Boolean) -> Unit,
    withArtist: Boolean,
    top: Boolean,
    onPlay: (Int) -> Unit,
) {
    item(key = "$key:title") {
        Row(
            Modifier.fillMaxWidth().padding(top = if (top) 12.dp else 0.dp, end = 10.dp),
            verticalAlignment = Alignment.CenterVertically,
        ) {
            SectionTitle(title, Modifier.weight(1f))
            when {
                list.songs.size <= shown -> Unit
                open -> QuietButton("Show fewer") { onOpen(false) }
                else -> QuietButton("Show all") { onOpen(true) }
            }
        }
    }
    val about = listOfNotNull(list.artist.takeUnless { withArtist }, rankedBy(list.source)).joinToString(" · ")
    if (about.isNotEmpty()) {
        item(key = "$key:about") {
            Text(
                about,
                style = OctoType.caption,
                color = OctoColors.TextMuted,
                modifier = Modifier.fillMaxWidth().padding(start = 20.dp, end = 20.dp, bottom = 4.dp),
            )
        }
    }
    val rows = if (open) list.songs else list.songs.take(shown)
    items(rows, key = { "$key:${it.track.id}" }) { ranked ->
        SongRow(
            ranked.track,
            SongLead.Ranked(ranked.rank),
            subtitle = { shownTrack ->
                listOfNotNull(
                    shownTrack.artist.takeIf { withArtist && it.isNotEmpty() },
                    rowAlbum(shownTrack).ifEmpty { null },
                    ranked.plays?.let(::playsText),
                ).joinToString(" • ")
            },
            // As every phone song row: a song not in the library has the add
            // button at the end, and library songs keep that space so the
            // lengths line up.
            offerAdd = true,
        ) { onPlay(list.songs.indexOf(ranked)) }
    }
}
