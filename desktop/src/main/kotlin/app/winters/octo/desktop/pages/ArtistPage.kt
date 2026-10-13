package app.winters.octo.desktop.pages

import app.winters.octo.design.LocalReduceMotion
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.BoxWithConstraints
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.offset
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.widthIn
import androidx.compose.foundation.lazy.rememberLazyListState
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.produceState
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.layout.ContentScale
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.text.style.TextOverflow
import app.winters.octo.design.ControlHeight
import app.winters.octo.design.DesktopType
import app.winters.octo.design.FrameSize
import app.winters.octo.design.OctoColors
import app.winters.octo.design.OctoIcons
import app.winters.octo.design.PageSize
import app.winters.octo.design.PageType
import app.winters.octo.design.Space
import app.winters.octo.design.TextAction
import app.winters.octo.design.Txt
import app.winters.octo.design.artworkRim
import app.winters.octo.catalog.groupAlbums
import app.winters.octo.desktop.AppState
import app.winters.octo.desktop.artistSongs
import app.winters.octo.desktop.library.LocalCovers
import app.winters.octo.desktop.library.SongColumn
import app.winters.octo.desktop.library.appearsOn
import app.winters.octo.covers.coverBucket
import app.winters.octo.desktop.library.coverRequest
import app.winters.octo.desktop.library.librarySongs
import app.winters.octo.desktop.library.monogramOf
import app.winters.octo.desktop.library.songsAlbumByAlbum
import app.winters.octo.desktop.library.sortAlbums
import app.winters.octo.desktop.nav.Page
import app.winters.octo.desktop.nav.Visit
import app.winters.octo.desktop.server.Connection
import app.winters.octo.desktop.server.userMessage
import app.winters.octo.desktop.startArtistRadio
import app.winters.octo.desktop.ui.ArtistMenu
import app.winters.octo.desktop.ui.Load
import app.winters.octo.desktop.ui.LoadingLine
import app.winters.octo.desktop.ui.PageSide
import app.winters.octo.desktop.ui.SongTable
import app.winters.octo.desktop.ui.rememberListState
import app.winters.octo.desktop.ui.rememberLoad
import app.winters.octo.desktop.ui.rememberOutside
import app.winters.octo.desktop.ui.rowHeightFor
import app.winters.octo.desktop.ui.show
import app.winters.octo.discovery.cleanBiography
import app.winters.octo.sort.SortList
import app.winters.octo.subsonic.Album
import app.winters.octo.subsonic.Artist
import app.winters.octo.subsonic.Song
import app.winters.octo.subsonic.SubsonicException
import coil3.compose.AsyncImage
import coil3.compose.LocalPlatformContext
import coil3.request.ImageRequest
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.async
import kotlinx.coroutines.coroutineScope
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext

// What an artist page shows, as the server answers for them: their own
// albums newest first, their most played songs, artists like them, their
// picture (the server's own, or one it found online) and biography.
class ArtistView(
    val name: String,
    val coverArt: String?,
    val albums: List<Album>,
    val top: List<Song>,
    val similar: List<Artist>,
    val picture: String?,
    val about: String?,
)

// How many top songs show before "Show all".
private const val TOP_SHOWN = 5

// An artist: their picture (or their first letter), Play (every song, album
// by album), Shuffle, the heart, Start radio and More; their biography; top
// songs; their releases on shelves by kind (Albums, Singles and EPs,
// Compilations, Live, Appears on) when the server says, else one Albums
// shelf; artists like them; and every song as a table at the foot, read
// once it is scrolled to.
@Composable
fun ArtistPage(app: AppState, visit: Visit, id: String, name: String) {
    val connection = app.connection ?: return
    val loaded = rememberLoad(connection, id) { loadArtist(connection, id) }
    val list = rememberListState(app.navigator, visit)
    loaded.show(Modifier.padding(horizontal = PageSide)) { artist -> ArtistBody(app, id, name, artist, list) }
}

private suspend fun loadArtist(connection: Connection, id: String): ArtistView = coroutineScope {
    val artist = connection.client.artist(id)
    val info = async { runCatching { connection.client.artistInfo(id, similar = 12) }.getOrNull() }
    val byId = connection.supports("topSongsByArtistId")
    val top = async {
        try {
            connection.client.topSongs(artist.name, 10, if (byId) id else null)
        } catch (e: SubsonicException) {
            emptyList()
        }
    }
    val found = info.await()
    ArtistView(
        artist.name,
        artist.coverArt,
        sortAlbums(artist.album, SortList.ArtistAlbums.default),
        top.await(),
        found?.similarArtist.orEmpty().filter { it.id.isNotEmpty() },
        found?.largeImageUrl?.takeIf(String::isNotBlank),
        found?.biography?.let(::cleanBiography),
    )
}

@Composable
private fun ArtistBody(app: AppState, id: String, fallbackName: String, artist: ArtistView, list: androidx.compose.foundation.lazy.LazyListState) {
    val name = artist.name.ifEmpty { fallbackName }
    val index = rememberIndex(app)
    // Top songs found online are left out with "Library songs only" on.
    val settings by app.settings.state.collectAsState()
    val topOutside = rememberOutside(app, artist.top)
    val top = remember(artist, topOutside, settings.libraryOnly) { librarySongs(artist.top, topOutside, settings.libraryOnly) }
    val own = remember(artist) { artist.albums.mapTo(HashSet()) { it.id } }
    // Albums by others they are on, from the library's songs, worked out
    // away from the window's thread.
    val appears by produceState(emptyList<Album>(), index, id) {
        value = index?.let { withContext(Dispatchers.Default) { appearsOn(it, id, own) } }.orEmpty()
    }
    val groups = remember(artist, appears) { groupAlbums(artist.albums + appears) { it.id in own } }
    val scope = rememberCoroutineScope()
    // Every song, read once the foot of the page is reached: from the
    // library when it has been read, else album by album from the server.
    var all by remember(id) { mutableStateOf<Load<List<Song>>?>(null) }
    suspend fun everySong(): List<Song> = when (val ready = all) {
        is Load.Ready -> ready.data
        else -> index?.let { withContext(Dispatchers.Default) { songsAlbumByAlbum(it.songs, artist.albums) } }?.takeIf { it.isNotEmpty() } ?: app.artistSongs(id)
    }
    fun readAll() {
        if (all is Load.Loading || all is Load.Ready) return
        all = Load.Loading
        scope.launch {
            all = try {
                Load.Ready(everySong())
            } catch (e: SubsonicException) {
                Load.Failed(e.userMessage())
            }
        }
    }
    fun playAll(shuffle: Boolean) {
        scope.launch {
            val songs = try {
                everySong()
            } catch (e: SubsonicException) {
                emptyList()
            }
            if (songs.isEmpty()) app.notice = "Couldn't find songs by $name" else app.play(songs, shuffle = shuffle)
        }
    }
    var topAll by remember(id) { mutableStateOf(false) }
    var similarAll by remember(id) { mutableStateOf(false) }
    val spots = remember(id) { HashMap<String, Int>() }
    val still = LocalReduceMotion.current
    fun jump(key: String) {
        spots[key]?.let { at -> scope.launch { if (still) list.scrollToItem(at) else list.animateScrollToItem(at) } }
    }
    val songs = (all as? Load.Ready)?.data.orEmpty()
    val songCount = artist.albums.sumOf { it.songCount }
    val seconds = artist.albums.sumOf { it.duration }
    BoxWithConstraints {
        val columns = cardColumns(maxWidth)
        val artistColumns = cardColumns(maxWidth, PageSize.ArtistCard)
        SongTable(
            app,
            songs,
            listOf(SongColumn.Number, SongColumn.Title, SongColumn.Album, SongColumn.Year, SongColumn.Plays, SongColumn.Favourite, SongColumn.Length),
            list,
            id = "artist-all",
            empty = {
                if (artist.albums.isNotEmpty()) when (val state = all) {
                    is Load.Failed -> NextStep("Couldn't read their songs", state.message, "Try again" to { all = null; readAll() })
                    is Load.Ready -> NextStep("No songs by $name", "The server lists no songs on their albums.")
                    else -> {
                        LaunchedEffect(Unit) { readAll() }
                        LoadingLine("Reading their songs")
                    }
                }
            },
        ) {
            val page = PageItems(this, spots)
            page.item("head") {
                EntityHeader(
                    "Artist",
                    name,
                    picture = { ArtistPicture(name, artist.coverArt, artist.picture, it) },
                    facts = listOfNotNull(
                        Fact(if (artist.albums.size == 1) "1 album" else "${artist.albums.size} albums"),
                        songCount.takeIf { it > 0 }?.let { Fact(songsLine(it, seconds)) },
                    ),
                ) {
                    PlayAndShuffle({ playAll(false) }, { playAll(true) }, enabled = artist.albums.isNotEmpty())
                    val starred = app.isArtistStarred(id, index?.artists?.firstOrNull { it.id == id }?.starred)
                    HeaderIcon(if (starred) OctoIcons.Liked else OctoIcons.Like, if (starred) "Remove from favorites" else "Add to favorites", { app.setArtistStarred(id, !starred) })
                    HeaderIcon(OctoIcons.Radio, "Start radio", { app.startArtistRadio(id, name) })
                    MoreButton(app, "More for this artist") { close -> ArtistMenu(app, id, name, index?.artists?.firstOrNull { it.id == id }?.starred, close) }
                }
            }
            page.item("jump") {
                JumpLinks(
                    buildList {
                        if (top.isNotEmpty()) add("Top songs" to { jump("top-title") })
                        groups.forEach { (group, _) -> add(group.title to { jump("group-${group.name}") }) }
                        if (artist.similar.isNotEmpty()) add("Similar artists" to { jump("similar-title") })
                        if (artist.albums.isNotEmpty()) add("All songs" to { jump("all-title") })
                    },
                )
            }
            artist.about?.let { about -> page.item("about") { Biography(about) } }
            if (top.isNotEmpty()) {
                page.item("top-title") {
                    GroupTitle(
                        "Top songs",
                        action = when {
                            top.size <= TOP_SHOWN -> null
                            topAll -> "Show fewer"
                            else -> "Show all ${top.size}"
                        },
                    ) { topAll = !topAll }
                }
                page.item("top") { TopSongs(app, if (topAll) top else top.take(TOP_SHOWN)) }
            }
            if (groups.isEmpty()) {
                page.item("no-albums") {
                    NextStep(
                        "No albums by $name on this server",
                        "Their songs may be on albums filed under another artist.",
                        "Search for $name" to {
                            app.navigator.go(Page.Search)
                            app.search?.type(name)
                        },
                    )
                }
            }
            groups.forEach { (group, albums) ->
                page.item("group-${group.name}") { GroupTitle(group.title, albums.size) }
                page.cards("group-${group.name}-cards", albums, columns) { AlbumCard(app, it) }
            }
            if (artist.similar.isNotEmpty()) {
                page.item("similar-title") {
                    GroupTitle(
                        "Similar artists",
                        action = when {
                            artist.similar.size <= artistColumns -> null
                            similarAll -> "Show fewer"
                            else -> "Show all ${artist.similar.size}"
                        },
                    ) { similarAll = !similarAll }
                }
                page.cards("similar", if (similarAll) artist.similar else artist.similar.take(artistColumns), artistColumns) { ArtistCard(app, it) }
            }
            if (artist.albums.isNotEmpty()) page.item("all-title") { GroupTitle("All songs", songs.size.takeIf { it > 0 } ?: songCount.takeIf { it > 0 }) }
        }
    }
}

// Their most played songs as a small table of their own, as tall as its
// rows, so the page scrolls past it.
@Composable
private fun TopSongs(app: AppState, songs: List<Song>) {
    val settings by app.settings.state.collectAsState()
    val height = ControlHeight.M + FrameSize.Hairline + rowHeightFor(settings.density) * songs.size
    SongTable(
        app,
        songs,
        listOf(SongColumn.Number, SongColumn.Title, SongColumn.Album, SongColumn.Plays, SongColumn.Favourite, SongColumn.Length),
        rememberLazyListState(),
        Modifier.height(height),
        id = "artist",
        padding = androidx.compose.foundation.layout.PaddingValues(),
    )
}

// The biography, a few lines at first; "Read more" shows the rest.
@Composable
private fun Biography(text: String) {
    var open by remember(text) { mutableStateOf(false) }
    var clipped by remember(text) { mutableStateOf(false) }
    Column(Modifier.widthIn(max = PageSize.Reading).padding(bottom = Space.S)) {
        androidx.compose.foundation.text.BasicText(
            text,
            style = DesktopType.body.copy(color = OctoColors.TextSecondary),
            maxLines = if (open) Int.MAX_VALUE else 3,
            overflow = TextOverflow.Ellipsis,
            onTextLayout = { if (!open) clipped = it.hasVisualOverflow },
        )
        if (clipped || open) {
            // Pulled back by the action's own padding, so its words line up
            // with the text's.
            TextAction(if (open) "Read less" else "Read more", { open = !open }, Modifier.offset(x = -Space.L))
        }
    }
}

// The artist's picture, round: the server's own, or one it found online,
// over their first letter, which shows whenever there is no picture (or
// while it loads), so the page never waits on one.
@Composable
private fun ArtistPicture(name: String, coverArt: String?, url: String?, modifier: Modifier) {
    val client = LocalCovers.current
    val context = LocalPlatformContext.current
    Box(modifier.clip(CircleShape).background(OctoColors.BackgroundTertiary), contentAlignment = Alignment.Center) {
        Txt(monogramOf(name), PageType.monogram, OctoColors.TextMuted)
        val px = with(LocalDensity.current) { PageSize.HeaderArt.roundToPx() }
        val request = remember(client, coverArt, url, px) {
            when {
                coverArt != null && client != null -> coverRequest(context, client, coverArt, coverBucket(px)).build()
                url != null -> ImageRequest.Builder(context).data(url).build()
                else -> null
            }
        }
        if (request != null) AsyncImage(model = request, contentDescription = null, contentScale = ContentScale.Crop, modifier = Modifier.fillMaxSize())
        Box(Modifier.matchParentSize().artworkRim(CircleShape))
    }
}
