package app.winters.octo.desktop.pages

import app.winters.octo.design.Spinner
import app.winters.octo.design.GlazeCapsule
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.heightIn
import androidx.compose.ui.semantics.LiveRegionMode
import androidx.compose.ui.semantics.clearAndSetSemantics
import androidx.compose.ui.semantics.liveRegion
import androidx.compose.ui.semantics.semantics
import app.winters.octo.desktop.search.OnlinePhase
import app.winters.octo.desktop.ui.rowHeightFor
import app.winters.octo.ui.family.TRY_AGAIN
import app.winters.octo.ui.search.LIBRARY_SONGS_SHOWN
import app.winters.octo.ui.search.ONLINE_SONGS_SHOWN
import app.winters.octo.ui.search.OutsideLook
import app.winters.octo.ui.search.WAITING_ROWS
import app.winters.octo.ui.search.moreSongsThanShown
import app.winters.octo.ui.search.outsideLine
import app.winters.octo.ui.search.outsideLook
import app.winters.octo.ui.search.songsShown
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
import app.winters.octo.desktop.library.SongColumn
import app.winters.octo.desktop.nav.Page
import app.winters.octo.desktop.nav.Visit
import app.winters.octo.desktop.search.SearchFilter
import app.winters.octo.desktop.search.SearchFound
import app.winters.octo.desktop.search.SearchState
import app.winters.octo.desktop.ui.FailedLine
import app.winters.octo.desktop.ui.LoadingLine
import app.winters.octo.desktop.ui.LocalBottomRoom
import app.winters.octo.desktop.ui.PageTitle
import app.winters.octo.desktop.ui.SectionTitle
import app.winters.octo.desktop.ui.ShelfCardWidth
import app.winters.octo.desktop.ui.SongTable
import app.winters.octo.desktop.ui.onRightClick
import app.winters.octo.desktop.ui.pagePadding
import app.winters.octo.desktop.ui.playlistMenu
import app.winters.octo.desktop.ui.rememberListState
import app.winters.octo.subsonic.Song

// Search: the same filters as the phone, then the artists, songs, albums
// and playlists, each kind one list with the library's first and, from an
// Octo server that can fetch music, what it found online right after, with
// a "+" to add each song.
@Composable
fun SearchPage(app: AppState, visit: Visit) {
    val model = app.search ?: return
    val list = rememberListState(app.navigator, visit)
    val state = model.state
    val done = state as? SearchState.Done
    val found = done?.found
    val online = done?.online ?: OnlinePhase.Done
    // The songs are a song table like every other list: the library's, then
    // those found online, each row saying which. The rest of the page goes
    // above and below it.
    SongTable(
        app,
        found?.let { tableSongs(it, model.filter) }.orEmpty(),
        listOf(SongColumn.Number, SongColumn.Title, SongColumn.Artist, SongColumn.Album, SongColumn.Favourite, SongColumn.Length),
        list,
        id = "search",
        marksAlways = app.wantsOnline(),
        footer = { if (found != null) after(app, found, online) },
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
                before(app, state.found, state.online)
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

// The songs in the table: "All" shows a few of the library's and a few
// found online, a filter all of both.
private fun tableSongs(found: SearchFound, filter: SearchFilter): List<Song> =
    if (filter == SearchFilter.All) found.library.songs.take(LIBRARY_SONGS_SHOWN) + found.outside.songs.take(ONLINE_SONGS_SHOWN)
    else found.library.songs + found.outside.songs

// Where looking online stands for one kind, by how many of it came back.
private fun look(online: OnlinePhase, wanted: Boolean, count: Int): OutsideLook = outsideLook(
    wanted = wanted,
    looking = online == OnlinePhase.Looking,
    failed = online is OnlinePhase.Failed,
    songs = count,
)

// Whether the server is asked for what it found online at all.
private fun AppState.wantsOnline(): Boolean = connection?.acquires == true && !settings.current.libraryOnly

// Above the songs: nothing found, or the artists (the library's, then
// those found online, when the library has some) and the songs' heading.
private fun LazyListScope.before(app: AppState, found: SearchFound, online: OnlinePhase) {
    val model = app.search ?: return
    val library = found.library
    val outside = found.outside
    if (library.isEmpty && outside.isEmpty && online == OnlinePhase.Done) {
        item(key = "nothing") { NothingHere("Nothing found", "Try other words, or fewer of them.") }
        return
    }
    if (library.artists.isNotEmpty()) {
        item(key = "artists") {
            SectionTitle("Artists", action = seeAll(app, library.moreArtists)) { model.pick(SearchFilter.Artists) }
            CardRow(library.artists.size + outside.artists.size) { i ->
                if (i < library.artists.size) ArtistCard(app, library.artists[i]) else ArtistCard(app, outside.artists[i - library.artists.size], outside = true)
            }
        }
    }
    val songsLook = look(online, app.wantsOnline(), outside.songs.size)
    val shownSongs = model.filter == SearchFilter.All || model.filter == SearchFilter.Songs
    if (shownSongs && songsShown(library.songs.size, songsLook)) {
        val more = moreSongsThanShown(library.songs.size + if (library.moreSongs) 1 else 0, outside.songs.size)
        item(key = "songs-title") { SectionTitle("Songs", action = seeAll(app, more)) { model.pick(SearchFilter.Songs) } }
    }
}

// Below the songs: while the server looks, a line saying so over rows that
// hold the finds' place, or a plain line when it found none or could not be
// asked; then the artist's top songs, the albums (the library's, then those
// found online), the playlists, and artists found online when the library
// has none.
private fun LazyListScope.after(app: AppState, found: SearchFound, online: OnlinePhase) {
    val model = app.search ?: return
    val library = found.library
    val outside = found.outside
    val wanted = app.wantsOnline()
    // A page that found nothing anywhere says so once, above.
    if (library.isEmpty && outside.isEmpty && online == OnlinePhase.Done) return
    when (model.filter) {
        SearchFilter.All, SearchFilter.Songs -> outsideLine(app, look(online, wanted, outside.songs.size), "songs", online, waiting = true)
        SearchFilter.Albums -> outsideLine(app, look(online, wanted, outside.albums.size + outside.partAlbums.size), "albums", online, waiting = false)
        SearchFilter.Artists -> outsideLine(app, look(online, wanted, outside.artists.size), "artists", online, waiting = false)
        SearchFilter.Playlists -> Unit
    }
    artistTopSongs(app, model.tops)
    val albums = library.albums.size + outside.partAlbums.size + outside.albums.size
    if (albums > 0) {
        item(key = "albums") {
            SectionTitle("Albums", action = seeAll(app, library.moreAlbums)) { model.pick(SearchFilter.Albums) }
            CardRow(albums) { i ->
                val part = i - library.albums.size
                val rest = part - outside.partAlbums.size
                when {
                    i < library.albums.size -> AlbumCard(app, library.albums[i])
                    part < outside.partAlbums.size -> AlbumCard(app, outside.partAlbums[part], outside = true)
                    else -> AlbumCard(app, outside.albums[rest], outside = true)
                }
            }
        }
    }
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
    if (library.artists.isEmpty() && outside.artists.isNotEmpty()) {
        item(key = "out-artists") {
            SectionTitle("Artists")
            CardRow(outside.artists.size) { i -> ArtistCard(app, outside.artists[i], outside = true) }
        }
    }
}

// The line between the library's results of a kind and the server's: a
// small spinner while it looks (over rows that hold the songs' place, for
// songs), a warning mark and Try again when it could not be asked, a plain
// line when it found none. Nothing once finds are listed.
private fun LazyListScope.outsideLine(app: AppState, look: OutsideLook, kind: String, online: OnlinePhase, waiting: Boolean) {
    val model = app.search ?: return
    val text = outsideLine(look, model.text, kind) ?: return
    item(key = "outside-line") {
        Row(
            Modifier.fillMaxWidth().heightIn(min = 44.dp).padding(horizontal = 10.dp).semantics { liveRegion = LiveRegionMode.Polite },
            verticalAlignment = Alignment.CenterVertically,
            horizontalArrangement = Arrangement.spacedBy(10.dp),
        ) {
            when (look) {
                OutsideLook.Looking -> Spinner(size = 16.dp, color = OctoColors.Accent)
                OutsideLook.Failed -> Glyph(OctoIcons.Info, size = 18.dp, tint = OctoColors.SignalOrange)
                else -> Glyph(OctoIcons.Search, size = 18.dp, tint = OctoColors.TextMuted)
            }
            Txt(
                text + ((online as? OnlinePhase.Failed)?.message?.let { ". $it" } ?: ""),
                OctoType.bodySmall,
                if (look == OutsideLook.Failed) OctoColors.TextPrimary else OctoColors.TextSecondary,
                Modifier.weight(1f),
                maxLines = 2,
            )
            if (look == OutsideLook.Failed) GlazeCapsule(null, TRY_AGAIN, model::again)
        }
    }
    if (waiting && look == OutsideLook.Looking) {
        items(WAITING_ROWS, key = { "outside-waiting:$it" }) { WaitingRow(app) }
    }
}

// A row that holds a find's place while the server looks: the shape of a
// song row in the table, in the faint fill of an empty cover.
@Composable
private fun WaitingRow(app: AppState) {
    val settings by app.settings.state.collectAsState()
    val fill = OctoColors.TextPrimary.copy(alpha = 0.06f)
    Row(
        Modifier.fillMaxWidth().height(rowHeightFor(settings.density)).padding(horizontal = 10.dp).clearAndSetSemantics {},
        verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.spacedBy(16.dp),
    ) {
        Box(Modifier.width(20.dp).height(10.dp).background(fill, RoundedCornerShape(4.dp)))
        Box(Modifier.size(rowHeightFor(settings.density) - 14.dp).background(fill, RoundedCornerShape(6.dp)))
        Box(Modifier.weight(0.34f).height(10.dp).background(fill, RoundedCornerShape(4.dp)))
        Box(Modifier.weight(0.22f).height(10.dp).background(fill, RoundedCornerShape(4.dp)))
        Box(Modifier.weight(0.22f).height(10.dp).background(fill, RoundedCornerShape(4.dp)))
        Spacer(Modifier.weight(0.22f))
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
