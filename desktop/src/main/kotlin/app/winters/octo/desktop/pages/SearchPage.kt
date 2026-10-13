package app.winters.octo.desktop.pages

import app.winters.octo.desktop.ui.MarkedTitle
import app.winters.octo.design.Corner
import app.winters.octo.design.FrameSize
import app.winters.octo.desktop.ui.PlaylistPicture
import androidx.compose.ui.semantics.Role
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.LazyListScope
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.lazy.itemsIndexed
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.runtime.remember
import androidx.compose.runtime.withFrameNanos
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.unit.dp
import app.winters.octo.design.GlassField
import app.winters.octo.design.GlazeSegments
import app.winters.octo.design.Glyph
import app.winters.octo.design.OctoColors
import app.winters.octo.design.OctoIcons
import app.winters.octo.design.OctoType
import app.winters.octo.design.Space
import app.winters.octo.design.Txt
import app.winters.octo.design.hoverLift
import app.winters.octo.desktop.AppState
import app.winters.octo.desktop.library.Cover
import app.winters.octo.desktop.library.SongColumn
import app.winters.octo.desktop.library.lengthText
import app.winters.octo.desktop.nav.Page
import app.winters.octo.desktop.nav.Visit
import app.winters.octo.desktop.search.FetchPhase
import app.winters.octo.desktop.search.SearchFilter
import app.winters.octo.desktop.search.SearchFound
import app.winters.octo.desktop.search.SearchState
import app.winters.octo.desktop.ui.DOUBLE_CLICK_MS
import app.winters.octo.desktop.ui.FailedLine
import app.winters.octo.desktop.ui.FetchButton
import app.winters.octo.desktop.ui.LoadingLine
import app.winters.octo.desktop.ui.LocalBottomRoom
import app.winters.octo.desktop.ui.LocalPointer
import app.winters.octo.desktop.ui.PageTitle
import app.winters.octo.desktop.ui.SectionTitle
import app.winters.octo.desktop.ui.ShelfCardWidth
import app.winters.octo.desktop.ui.SongMenu
import app.winters.octo.desktop.ui.SongTable
import app.winters.octo.desktop.ui.onRightClick
import app.winters.octo.desktop.ui.pagePadding
import app.winters.octo.desktop.ui.playlistMenu
import app.winters.octo.desktop.ui.rememberListState
import app.winters.octo.discovery.knownLengthMs
import app.winters.octo.discovery.PartlyInLibraryText
import app.winters.octo.subsonic.Song

// Not in the library, in the phone app's words.
const val NotInLibraryText = "Not in your library"

// Search: the same filters as the phone, then the library's
// artists, albums, songs and playlists, and, from an Octo server that can
// fetch music, what it found online with a "+" to add each song.
@Composable
fun SearchPage(app: AppState, visit: Visit) {
    val model = app.search ?: return
    val list = rememberListState(app.navigator, visit)
    val state = model.state
    val found = (state as? SearchState.Done)?.found
    // The library's songs are a song table like every other list; the rest
    // of the page goes above and below it.
    SongTable(
        app,
        found?.library?.songs.orEmpty(),
        listOf(SongColumn.Number, SongColumn.Title, SongColumn.Artist, SongColumn.Album, SongColumn.Favourite, SongColumn.Length),
        list,
        id = "search",
        footer = { if (found != null) after(app, found) },
    ) {
        // The field itself is at the top of the sidebar, on every page.
        item(key = "filters") {
            Column(verticalArrangement = Arrangement.spacedBy(Space.L)) {
                PageTitle("Search", detail = model.text.takeIf(String::isNotBlank)?.let { "Results for \"$it\"" })
                GlazeSegments(SearchFilter.entries, model.filter, { it.label }, model::pick)
            }
        }
        when (state) {
            SearchState.Idle -> {
                item(key = "idle") { Txt("Type at least two letters in the search field.", OctoType.bodySmall, OctoColors.TextMuted, Modifier.padding(top = Space.Page)) }
                item(key = "live-radio") { LiveRadioSearchRow(app) }
                topChart(app, model.tops)
            }
            SearchState.Looking -> item(key = "looking") { LoadingLine("Searching") }
            is SearchState.Failed -> item(key = "failed") { FailedLine(state.message, model::again) }
            is SearchState.Done -> {
                if (asksForRadio(model.text)) item(key = "live-radio") { LiveRadioSearchRow(app) }
                before(app, state.found)
            }
        }
    }
}

// Whether a search looks for radio, which the Live radio page finds.
fun asksForRadio(text: String): Boolean {
    val words = text.lowercase().split(Regex("[^a-z]+")).filter { it.isNotEmpty() }
    return words.any { it == "radio" || it == "station" || it == "stations" || it == "fm" }
}

private fun seeAll(app: AppState, more: Boolean): String? = if (more && app.search?.filter == SearchFilter.All) "See all" else null

// Above the songs: nothing found, or the artists and albums, and the songs'
// heading.
private fun LazyListScope.before(app: AppState, found: SearchFound) {
    val model = app.search ?: return
    val library = found.library
    if (library.isEmpty && found.outside.isEmpty) {
        item(key = "nothing") { NothingHere("Nothing found", "Try other words, or fewer of them.") }
        return
    }
    if (library.artists.isNotEmpty()) {
        item(key = "artists") {
            SectionTitle("Artists", action = seeAll(app, library.moreArtists)) { model.pick(SearchFilter.Artists) }
            CardRow(library.artists.size) { i -> ArtistCard(app, library.artists[i]) }
        }
    }
    artistTopSongs(app, model.tops)
    if (library.albums.isNotEmpty()) {
        item(key = "albums") {
            SectionTitle("Albums", action = seeAll(app, library.moreAlbums)) { model.pick(SearchFilter.Albums) }
            CardRow(library.albums.size) { i -> AlbumCard(app, library.albums[i]) }
        }
    }
    // Albums found online that the library holds some of: each card says how
    // much, and opening one plays the library's copies and adds the rest.
    val partly = found.outside.partAlbums
    if (partly.isNotEmpty()) {
        item(key = "part-albums") {
            SectionTitle(PartlyInLibraryText)
            Txt("Found online by your server. Open one to play the songs you have and add the rest.", OctoType.caption, OctoColors.TextMuted, Modifier.padding(bottom = 8.dp))
            CardRow(partly.size) { i -> AlbumCard(app, partly[i], outside = true) }
        }
    }
    if (library.songs.isNotEmpty()) {
        item(key = "songs-title") { SectionTitle("Songs", action = seeAll(app, library.moreSongs)) { model.pick(SearchFilter.Songs) } }
    }
}

// Below the songs: the playlists, then what the server found online.
private fun LazyListScope.after(app: AppState, found: SearchFound) {
    val model = app.search ?: return
    val library = found.library
    val outside = found.outside
    if (library.playlists.isNotEmpty()) {
        item(key = "playlists-title") { SectionTitle("Playlists", action = seeAll(app, library.morePlaylists)) { model.pick(SearchFilter.Playlists) } }
        items(library.playlists, key = { "pl:${it.id}" }) { playlist ->
            Row(
                Modifier.fillMaxWidth().height(44.dp).hoverLift(RoundedCornerShape(8.dp)).onRightClick(playlistMenu(app, playlist)).clickable(role = Role.Button) { app.navigator.go(Page.Playlist(playlist.id)) }.padding(horizontal = 10.dp),
                verticalAlignment = Alignment.CenterVertically,
                horizontalArrangement = Arrangement.spacedBy(12.dp),
            ) {
                PlaylistPicture(app, playlist, Modifier.size(FrameSize.PlaylistCover), Corner.ArtSShape)
                Txt(playlist.name, OctoType.bodySmall, modifier = Modifier.weight(1f))
                Txt("${playlist.songCount} songs", OctoType.caption, OctoColors.TextMuted)
            }
        }
    }
    if (!outside.notInLibraryEmpty) {
        item(key = "outside-title") {
            Column {
                SectionTitle(NotInLibraryText)
                Txt("Found online by your server. Press + to add a song to your library.", OctoType.caption, OctoColors.TextMuted, Modifier.padding(bottom = 8.dp))
            }
        }
        if (outside.songs.isNotEmpty()) {
            itemsIndexed(outside.songs, key = { i, s -> "out:$i:${s.id}" }) { index, song -> OutsideSong(app, outside.songs, index, song) }
        }
        if (outside.albums.isNotEmpty()) {
            item(key = "out-albums") {
                Txt("Albums", OctoType.label, OctoColors.TextSecondary, Modifier.padding(top = 16.dp, bottom = 4.dp))
                CardRow(outside.albums.size) { i -> AlbumCard(app, outside.albums[i], outside = true) }
            }
        }
        if (outside.artists.isNotEmpty()) {
            item(key = "out-artists") {
                Txt("Artists", OctoType.label, OctoColors.TextSecondary, Modifier.padding(top = 16.dp, bottom = 4.dp))
                CardRow(outside.artists.size) { i -> ArtistCard(app, outside.artists[i], outside = true) }
            }
        }
    }
}

// A row of cards, as many as fit on one line.
@Composable
private fun CardRow(count: Int, card: @Composable (Int) -> Unit) {
    androidx.compose.foundation.layout.BoxWithConstraints(Modifier.fillMaxWidth()) {
        val fit = (maxWidth / ShelfCardWidth).toInt().coerceAtLeast(1)
        Row(Modifier.fillMaxWidth()) {
            (0 until minOf(fit, count)).forEach { i -> Box(Modifier.width(ShelfCardWidth)) { card(i) } }
        }
    }
}

// A song the server found online: a click plays it and the finds after it,
// as on the phone, a right click opens its menu, and the "+" has the server
// add it to the library. The second click of a double click does not start
// it over.
@Composable
private fun OutsideSong(app: AppState, songs: List<Song>, index: Int, song: Song) {
    val outside = true
    val pointer = LocalPointer.current
    val clicks = androidx.compose.runtime.remember { longArrayOf(0L) }
    Row(
        Modifier
            .fillMaxWidth()
            .height(52.dp)
            .hoverLift(RoundedCornerShape(8.dp))
            .onRightClick { app.popups.showAt(pointer.point) { close -> SongMenu(app, listOf(song), close, outside = outside) } }
            .clickable(role = Role.Button) {
                val now = System.currentTimeMillis()
                if (now - clicks[0] >= DOUBLE_CLICK_MS) app.play(songs, index)
                clicks[0] = now
            }
            .padding(horizontal = 8.dp),
        verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.spacedBy(12.dp),
    ) {
        Cover(song.coverArt, Modifier.size(38.dp), shape = RoundedCornerShape(6.dp), online = outside, placeholder = OctoIcons.Songs)
        Column(Modifier.weight(1f)) {
            MarkedTitle(song, OctoType.bodySmall) { Txt(song.title, OctoType.bodySmall, modifier = it) }
            Txt(listOfNotNull(song.displayArtist ?: song.artist, song.album).joinToString(" · "), OctoType.caption, OctoColors.TextMuted)
        }
        Txt(lengthText(app.realSeconds(song) ?: (knownLengthMs(song) / 1000).toInt()), OctoType.caption, OctoColors.TextMuted, Modifier.width(52.dp))
        FetchButton(app, song)
        FetchProblem(app, song)
    }
}

// Why the server couldn't add a song found online, beside its "+".
@Composable
private fun FetchProblem(app: AppState, song: Song) {
    val fetches = app.fetches ?: return
    val phases by fetches.phases.collectAsState()
    val phase = phases[song.id] as? FetchPhase.Failed ?: return
    Txt("Couldn't add it: ${phase.reason}. Press to try again.", OctoType.caption, OctoColors.TextMuted, Modifier.width(180.dp), maxLines = 2)
}
