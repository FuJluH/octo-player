package app.winters.octo.desktop.pages

import androidx.compose.foundation.layout.BoxWithConstraints
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.padding
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import app.winters.octo.animated.AnimatedArtSetting
import app.winters.octo.animated.onAlbumPage
import app.winters.octo.desktop.animated.AnimatedCover
import app.winters.octo.desktop.settings.animatedArtSetting
import app.winters.octo.desktop.ui.LocalWindowShown
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import app.winters.octo.design.Corner
import app.winters.octo.design.DesktopType
import app.winters.octo.design.OctoColors
import app.winters.octo.design.OctoIcons
import app.winters.octo.design.TextAction
import app.winters.octo.design.Txt
import app.winters.octo.desktop.AppState
import app.winters.octo.desktop.SidePanel
import app.winters.octo.desktop.library.Cover
import app.winters.octo.desktop.library.LibraryShare
import app.winters.octo.desktop.library.SongColumn
import app.winters.octo.desktop.library.askableSongs
import app.winters.octo.desktop.library.discHeadings
import app.winters.octo.desktop.library.formatSummary
import app.winters.octo.desktop.library.libraryShareOf
import app.winters.octo.desktop.library.librarySongs
import app.winters.octo.desktop.library.sortAlbums
import app.winters.octo.desktop.search.FetchPhase
import app.winters.octo.desktop.nav.Page
import app.winters.octo.desktop.nav.Visit
import app.winters.octo.desktop.ui.AlbumMenu
import app.winters.octo.desktop.ui.LinkText
import app.winters.octo.desktop.ui.PageSide
import app.winters.octo.desktop.ui.SongTable
import app.winters.octo.desktop.ui.rememberOutside
import app.winters.octo.desktop.ui.rememberListState
import app.winters.octo.desktop.ui.rememberLoad
import app.winters.octo.desktop.ui.show
import app.winters.octo.discovery.ONLY_MY_SONGS
import app.winters.octo.sort.SortList
import app.winters.octo.subsonic.Album
import app.winters.octo.subsonic.AlbumWithSongs
import app.winters.octo.subsonic.Song
import app.winters.octo.subsonic.SubsonicException
import kotlinx.coroutines.async
import kotlinx.coroutines.coroutineScope
import kotlinx.coroutines.flow.MutableStateFlow

// An album and the artist's other albums, as the page shows them.
class AlbumView(val album: AlbumWithSongs, val others: List<Album>)

// An album: a compact header (cover, names, year, genre, songs, length and
// format), Play, Shuffle, the heart, Add to queue and More, then its songs
// in album order with a heading for each disc (named as the album names
// them), and the artist's other albums at the foot.
@Composable
fun AlbumPage(app: AppState, visit: Visit, id: String) {
    val connection = app.connection ?: return
    val loaded = rememberLoad(connection, id) {
        coroutineScope {
            val album = connection.client.album(id)
            val others = async {
                val artistId = album.artistId?.takeIf(String::isNotEmpty) ?: return@async emptyList()
                try {
                    sortAlbums(connection.client.artist(artistId).album.filter { it.id != id }, SortList.ArtistAlbums.default)
                } catch (e: SubsonicException) {
                    emptyList()
                }
            }
            AlbumView(album, others.await())
        }
    }
    val list = rememberListState(app.navigator, visit)
    loaded.show(Modifier.padding(horizontal = PageSide)) { view ->
        val album = view.album
        val whole = album.song
        // Octo lists every song of an album, those the library lacks too:
        // they play through Octo like the rest, and the table marks them.
        // "Library songs only", or this page's "Only my songs", leaves them
        // out before the table and Play count them.
        val outside = rememberOutside(app, whole)
        val settings by app.settings.state.collectAsState()
        var onlyMine by remember(album.id) { mutableStateOf(false) }
        val songs = remember(whole, outside, settings.libraryOnly, onlyMine) { librarySongs(whole, outside, settings.libraryOnly || onlyMine) }
        val headings = remember(album, songs) { discHeadings(songs, album.discTitles) }
        val fetches = app.fetches
        val phases by remember(fetches) { fetches?.phases ?: MutableStateFlow(emptyMap()) }.collectAsState()
        val share = remember(whole, outside, phases, fetches) { libraryShareOf(whole, outside, phases, canFetch = fetches != null) }
        // The format of the files in the library, not of the streams.
        val format = remember(album, outside) { formatSummary(songs.filterNot { it.id in outside }) }
        // An album found online is not in the library: no heart, since on
        // Octo a star would fetch the whole album.
        val inLibrary = app.library?.index?.hasAlbum(album.id) ?: true
        val artistName = album.displayArtist ?: album.artist
        BoxWithConstraints {
            val columns = cardColumns(maxWidth)
            SongTable(
                app,
                songs,
                listOf(SongColumn.Number, SongColumn.Title, SongColumn.Artist, SongColumn.Plays, SongColumn.Favourite, SongColumn.Length),
                list,
                id = "album",
                covers = false,
                number = { index, song -> song.track?.toString() ?: "${index + 1}" },
                groupTitle = { index -> headings.getOrNull(index) },
                empty = {
                    NextStep(
                        "This album has no songs",
                        "Your server lists the album but has no songs for it. A rescan on the server may bring them back.",
                        *listOfNotNull(album.artistId?.takeIf(String::isNotEmpty)?.let { artist -> "Go to $artistName" to { app.navigator.go(Page.Artist(artist, album.artist)) } }).toTypedArray(),
                    )
                },
                footer = {
                    if (view.others.isNotEmpty()) {
                        val page = PageItems(this, HashMap())
                        page.item("more-title") {
                            GroupTitle("More by $artistName", action = if (view.others.size > columns) "See all" else null) {
                                album.artistId?.let { app.navigator.go(Page.Artist(it, album.artist)) }
                            }
                        }
                        page.cards("more", view.others.take(columns), columns) { AlbumCard(app, it) }
                    }
                },
            ) {
                item(key = "head") {
                    EntityHeader(
                        "Album",
                        album.name,
                        picture = { modifier -> AlbumArt(app, album, modifier, online = !inLibrary) },
                        // No line at all for an album with no artist, rather than an empty one.
                        subtitle = artistName?.takeIf(String::isNotBlank)?.let { name -> { LinkText(name, album.artistId) { app.navigator.go(Page.Artist(it, album.artist)) } } },
                        facts = albumFacts(app, album, songs.size, songs.sumOf { it.duration }, format),
                        note = share?.let {
                            {
                                LibraryNote(
                                    it,
                                    follow = if (app.downloads?.supported == true && onTheWay(whole, outside, phases)) ({ app.downloads?.showList(); app.showSidePanel(SidePanel.Downloads) }) else null,
                                    // The setting already leaves them out; the toggle is for this album alone.
                                    onlyMine = if (settings.libraryOnly || outside.isEmpty()) null else onlyMine,
                                    onOnlyMine = { onlyMine = !onlyMine },
                                ) {
                                    askableSongs(whole, outside, phases).forEach { song -> fetches?.request(song.id) }
                                }
                            }
                        },
                    ) {
                        PlayAndShuffle({ app.play(songs) }, { app.play(songs, shuffle = true) }, enabled = songs.isNotEmpty())
                        if (inLibrary) {
                            val starred = app.isAlbumStarred(album.id, album.starred ?: app.library?.index?.albums?.firstOrNull { it.id == album.id }?.starred)
                            HeaderIcon(if (starred) OctoIcons.Liked else OctoIcons.Like, if (starred) "Remove from favorites" else "Add to favorites", { app.setAlbumStarred(album.id, !starred) })
                        }
                        HeaderIcon(OctoIcons.AddToQueue, "Add to queue", { app.addToQueue(songs) }, enabled = songs.isNotEmpty())
                        MoreButton(app, "More for this album") { close -> AlbumMenu(app, album.asAlbum(), close, outside = !inLibrary) }
                    }
                }
            }
        }
    }
}

// The album's cover in its header, with its square animated loop over it
// when it has one and the setting plays it, held while the page is under
// the full player or the window is away.
@Composable
private fun AlbumArt(app: AppState, album: AlbumWithSongs, modifier: Modifier, online: Boolean) {
    val settings by app.settings.state.collectAsState()
    val setting = settings.appearance.animatedArtSetting
    LaunchedEffect(album.id, album.animatedArt) { app.animated.note(album.id, album.animatedArt) }
    val art = if (setting == AnimatedArtSetting.Off) null else album.animatedArt ?: app.animated.artOf(album.id).value
    AnimatedCover(
        app.animated,
        album.id,
        setting.onAlbumPage(art),
        seen = LocalWindowShown.current && !app.fullPlayer,
        shape = Corner.ArtLShape,
        modifier = modifier,
    ) { Cover(album.coverArt, it, shape = Corner.ArtLShape, online = online) }
}

// How much of an album is in the library, under its facts, with a way to
// add the rest and, while songs are on their way, to follow them in the
// downloads drawer. "Only my songs" (`onlyMine`, when offered) hides the
// rest on this page.
@Composable
private fun LibraryNote(
    share: LibraryShare,
    follow: (() -> Unit)? = null,
    onlyMine: Boolean? = null,
    onOnlyMine: () -> Unit = {},
    addRest: () -> Unit,
) {
    Row(verticalAlignment = Alignment.CenterVertically) {
        Txt(share.line, DesktopType.meta, OctoColors.TextSecondary)
        share.action?.let { TextAction(it, addRest, icon = OctoIcons.AddToLibrary) }
        follow?.let { TextAction("Show downloads", it, icon = OctoIcons.Downloading) }
        onlyMine?.let { on -> TextAction(ONLY_MY_SONGS, onOnlyMine, icon = OctoIcons.Library, checked = on) }
    }
}

// Whether any of the album's songs found online is being fetched now.
private fun onTheWay(songs: List<Song>, outside: Set<String>, phases: Map<String, FetchPhase>): Boolean =
    songs.any { it.id in outside && phases[it.id].let { phase -> phase == FetchPhase.Queued || phase is FetchPhase.Downloading || phase == FetchPhase.Adding } }

// The line under an album's name: year, genre (opening the genre), how
// many songs and how long, and the format.
private fun albumFacts(app: AppState, album: AlbumWithSongs, count: Int, seconds: Int, format: String?): List<Fact> {
    val genre = (album.genres.firstOrNull() ?: album.genre)?.trim()?.takeIf(String::isNotEmpty)
    return listOfNotNull(
        (album.year ?: album.releaseDate?.year)?.takeIf { it > 0 }?.let { Fact(it.toString()) },
        genre?.let { Fact(it) { app.navigator.go(Page.Genre(it)) } },
        Fact(songsLine(count, seconds)),
        format?.let(::Fact),
    )
}

// The album as a card or menu takes it.
fun AlbumWithSongs.asAlbum() = Album(
    id = id,
    name = name,
    artist = artist,
    artistId = artistId,
    displayArtist = displayArtist,
    coverArt = coverArt,
    songCount = songCount,
    duration = duration,
    year = year,
    genre = genre,
    starred = starred,
    isCompilation = isCompilation,
    discTitles = discTitles,
    releaseTypes = releaseTypes,
)
