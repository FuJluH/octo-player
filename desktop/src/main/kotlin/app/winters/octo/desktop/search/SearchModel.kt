package app.winters.octo.desktop.search

import androidx.compose.runtime.Stable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue
import app.winters.octo.catalog.searchKey
import app.winters.octo.discovery.AlbumShare
import app.winters.octo.discovery.albumShare
import app.winters.octo.desktop.library.LibraryIndex
import app.winters.octo.desktop.library.isOutsideSong
import app.winters.octo.desktop.server.Connection
import app.winters.octo.desktop.server.userMessage
import app.winters.octo.server.Arriving
import app.winters.octo.server.arriving
import app.winters.octo.subsonic.Album
import app.winters.octo.subsonic.Artist
import app.winters.octo.subsonic.Playlist
import app.winters.octo.subsonic.SearchResult
import app.winters.octo.subsonic.Song
import app.winters.octo.subsonic.SubsonicException
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Job
import kotlinx.coroutines.delay
import kotlinx.coroutines.launch

// Which kind of result a search shows: everything, or one kind in full.
// The same filters as the phone.
enum class SearchFilter(val label: String) {
    All("All"),
    Songs("Songs"),
    Albums("Albums"),
    Artists("Artists"),
    Playlists("Playlists"),
}

// How many of each kind a search shows, as on the phone: a few of each for
// everything, all of one kind (up to a limit) when it is picked.
data class SearchCaps(val artists: Int, val albums: Int, val songs: Int, val playlists: Int)

fun searchCaps(filter: SearchFilter): SearchCaps = when (filter) {
    SearchFilter.All -> SearchCaps(artists = 10, albums = 20, songs = 50, playlists = 10)
    SearchFilter.Songs -> SearchCaps(0, 0, songs = 1_000, playlists = 0)
    SearchFilter.Albums -> SearchCaps(0, albums = 500, 0, 0)
    SearchFilter.Artists -> SearchCaps(artists = 500, 0, 0, 0)
    SearchFilter.Playlists -> SearchCaps(0, 0, 0, playlists = 500)
}

// What the library has that matches, and whether there are more of a kind
// than shown, for its "See all".
data class LibraryResults(
    val artists: List<Artist> = emptyList(),
    val albums: List<Album> = emptyList(),
    val songs: List<Song> = emptyList(),
    val playlists: List<Playlist> = emptyList(),
    val moreArtists: Boolean = false,
    val moreAlbums: Boolean = false,
    val moreSongs: Boolean = false,
    val morePlaylists: Boolean = false,
) {
    val isEmpty get() = artists.isEmpty() && albums.isEmpty() && songs.isEmpty() && playlists.isEmpty()
}

// What the server found online, beyond the library: only from a server
// that lists octoAcquisitions, which can also fetch them into the library.
// `partAlbums` are albums found online that the library holds some of the
// songs of (Octo counts them), kept apart from the ones it holds none of,
// so the "Not in your library" heading is never over an album that partly is.
data class OutsideResults(
    val songs: List<Song> = emptyList(),
    val albums: List<Album> = emptyList(),
    val artists: List<Artist> = emptyList(),
    val partAlbums: List<Album> = emptyList(),
) {
    val isEmpty get() = notInLibraryEmpty && partAlbums.isEmpty()

    // Nothing to list under "Not in your library".
    val notInLibraryEmpty get() = songs.isEmpty() && albums.isEmpty() && artists.isEmpty()
}

data class SearchFound(val library: LibraryResults, val outside: OutsideResults)

sealed interface SearchState {
    // Too little typed to ask.
    data object Idle : SearchState
    data object Looking : SearchState

    // What is shown: the library's results, and where looking online
    // stands. The library's come from the library as last read while the
    // server is asked, and from the server's answer once it is in.
    data class Done(val found: SearchFound, val online: OnlinePhase = OnlinePhase.Done) : SearchState
    data class Failed(val message: String) : SearchState
}

// Where asking the server for what it found online stands.
sealed interface OnlinePhase {
    // Not asked: "Library songs only", or a server that finds nothing
    // online. Or answered, with what it found in the results.
    data object Done : OnlinePhase
    data object Looking : OnlinePhase
    data class Failed(val message: String) : OnlinePhase
}

// The library's results from the library as last read, while the server is
// asked: a song, album or artist whose words hold every word typed, in the
// library's order. The same kinds and caps as the server's answer.
fun localResults(index: LibraryIndex, query: String, filter: SearchFilter, playlists: List<Playlist>): LibraryResults {
    val caps = searchCaps(filter)
    val words = searchKey(query).split(' ').filter(String::isNotEmpty)
    fun matches(vararg texts: String?): Boolean {
        val all = searchKey(texts.filterNotNull().joinToString(" "))
        return words.all(all::contains)
    }
    val artists = if (caps.artists > 0) index.artists.filter { matches(it.name) } else emptyList()
    val albums = if (caps.albums > 0) index.albums.filter { matches(it.name, it.artist) } else emptyList()
    val songs = if (caps.songs > 0) index.songs.filter { matches(it.title, it.artist, it.album) } else emptyList()
    val key = searchKey(query)
    val named = if (caps.playlists > 0) playlists.filter { searchKey(it.name).contains(key) } else emptyList()
    return LibraryResults(
        artists = artists.take(caps.artists),
        albums = albums.take(caps.albums),
        songs = songs.take(caps.songs),
        playlists = named.take(caps.playlists),
        moreArtists = artists.size > caps.artists,
        moreAlbums = albums.size > caps.albums,
        moreSongs = songs.size > caps.songs,
        morePlaylists = named.size > caps.playlists,
    )
}

// The fresh list in the order already shown: what was shown keeps its
// place, and what is new follows, so rows on screen do not move when the
// server's answer replaces the library's own.
fun <T> inShownOrder(shown: List<T>, fresh: List<T>, key: (T) -> String): List<T> {
    if (shown.isEmpty()) return fresh
    val byKey = fresh.associateBy(key)
    val kept = shown.mapNotNull { byKey[key(it)] }
    val keptKeys = kept.mapTo(HashSet(), key)
    return kept + fresh.filterNot { key(it) in keptKeys }
}

// The server's library results, in the order the library's own were shown.
fun LibraryResults.inOrderOf(shown: LibraryResults?): LibraryResults = if (shown == null) this else copy(
    artists = inShownOrder(shown.artists, artists) { it.id },
    albums = inShownOrder(shown.albums, albums) { it.id },
    songs = inShownOrder(shown.songs, songs) { it.id },
)

// Splits what the server sent into the library's and the rest. Only a
// server that can fetch songs into the library (`outsideOn`) mixes in songs
// found online, and only once the library has been read can they be told
// apart; otherwise everything counts as the library's. An answer that
// marks anything as outside the library is taken at its word: a song or
// album it leaves unmarked is the library's even when the library, as last
// read, lacks it (the server took it in since). Only an answer with no
// marks falls back on the library. With "Library songs only"
// (`hideOutside`) what was found online is left out instead. One more of
// each kind than shown is asked for, to know whether there are more.
fun splitResults(
    sent: SearchResult,
    query: String,
    filter: SearchFilter,
    playlists: List<Playlist>,
    index: LibraryIndex?,
    outsideOn: Boolean,
    hideOutside: Boolean = false,
    // Whether the answer marks anything as outside; for the answer as it
    // came, before what was found online is taken out of it.
    marked: Boolean = sent.song.any { it.isExternal } || sent.album.any { it.isExternal },
): SearchFound {
    if (hideOutside) {
        // Songs are told apart even where they would otherwise count as the
        // library's; albums by the server's mark when the library cannot
        // say. What is left over as outside is dropped, not listed.
        val telling = outsideOn && index != null
        val kept = sent.copy(
            album = if (telling) sent.album else sent.album.filterNot { it.isExternal },
            song = sent.song.filterNot { if (marked) it.isExternal else isOutsideSong(it, index, canFetch = true) },
        )
        return splitResults(kept, query, filter, playlists, index, outsideOn, marked = marked).copy(outside = OutsideResults())
    }
    val caps = searchCaps(filter)
    val telling = outsideOn && index != null
    val (held, outsideSongs) = if (telling) sent.song.partition { index.holds(it) || marked && !it.isExternal } else sent.song to emptyList()
    // A song found online that the library already holds (under another id,
    // or another version Octo did not fold into it) is the library's own
    // copy here, once: the library's songs are only library songs, so none
    // of them reads as "not in your library" with a "+" beside it.
    val songs = if (telling) held.map { if (it.isExternal) index.copyOf(it) ?: it else it }.distinctBy { it.id } else held
    val (libraryAlbums, foundAlbums) = if (telling) sent.album.partition { index.hasAlbum(it.id) || marked && !it.isExternal } else sent.album to emptyList()
    // An album found online that is a library album by its very name and
    // artist is that album. One the library holds every song of (Octo
    // counts them) is the library's too: it opens with the library's copies.
    val namesakes = foundAlbums.associateWith { if (telling) index.namesake(it) else null }
    val unnamed = foundAlbums.filter { namesakes[it] == null }
    val shares = unnamed.associateWith(::albumShare)
    val albums = (libraryAlbums + namesakes.values.filterNotNull() + unnamed.filter { shares[it] == AlbumShare.Whole }).distinctBy { it.id }
    val partAlbums = unnamed.filter { shares[it] == AlbumShare.Part }
    val outsideAlbums = unnamed.filter { shares[it] == null || shares[it] == AlbumShare.None }
    val (artists, outsideArtists) = if (telling) sent.artist.partition { index.hasArtist(it.id) } else sent.artist to emptyList()
    val key = searchKey(query)
    val named = if (caps.playlists > 0) playlists.filter { searchKey(it.name).contains(key) } else emptyList()
    return SearchFound(
        LibraryResults(
            artists = artists.take(caps.artists),
            albums = albums.take(caps.albums),
            songs = songs.take(caps.songs),
            playlists = named.take(caps.playlists),
            moreArtists = artists.size > caps.artists,
            moreAlbums = albums.size > caps.albums,
            moreSongs = songs.size > caps.songs,
            morePlaylists = named.size > caps.playlists,
        ),
        OutsideResults(
            songs = if (caps.songs > 0) outsideSongs else emptyList(),
            albums = if (caps.albums > 0) outsideAlbums else emptyList(),
            artists = if (caps.artists > 0) outsideArtists else emptyList(),
            partAlbums = if (caps.albums > 0) partAlbums else emptyList(),
        ),
    )
}

// How long typing has to pause before the server is asked.
const val SEARCH_AFTER_MS = 250L

// Octo holds back songs found online when a search asks for 12 songs or
// fewer, so a search always asks for more than that.
private const val MIN_SONGS = 40

// The search page's state: what is typed, the filter, and what came back.
// New text cancels the question before it.
@Stable
class SearchModel(
    private val connection: Connection,
    private val index: () -> LibraryIndex?,
    private val playlists: () -> List<Playlist>,
    private val scope: CoroutineScope,
    // Whether "Library songs only" is on.
    private val libraryOnly: () -> Boolean = { false },
    // Takes the server's own music a search found that the library lacks
    // into the library (LibraryStore.takeIn), answering whether any of it
    // is in now.
    private val takeIn: suspend (Arriving) -> Boolean = { false },
) {
    var text by mutableStateOf("")
        private set
    var filter by mutableStateOf(SearchFilter.All)
        private set
    var state by mutableStateOf<SearchState>(SearchState.Idle)
        private set

    // The top songs of an artist searched for, and the chart for an empty search.
    val tops = SearchTops(connection, scope)

    // The Charts page: the charts the server's country has, and their songs.
    val charts = Charts(connection, scope)

    private var job: Job? = null

    fun type(value: String) {
        text = value
        ask(pause = true)
    }

    fun pick(value: SearchFilter) {
        if (value == filter) return
        filter = value
        ask(pause = false)
    }

    fun again() = ask(pause = false)

    private fun ask(pause: Boolean) {
        job?.cancel()
        tops.forget()
        val query = text.trim()
        if (searchKey(query).length < 2) {
            state = SearchState.Idle
            return
        }
        val filter = filter
        val online = connection.acquires && !libraryOnly()
        // The library as last read answers at once, with the server's finds
        // still to come; with no library read yet, the page waits for the
        // server.
        val local = index()?.let { localResults(it, query, filter, playlists()) }
        state = if (local != null) SearchState.Done(SearchFound(local, OutsideResults()), if (online) OnlinePhase.Looking else OnlinePhase.Done) else SearchState.Looking
        job = scope.launch {
            if (pause) delay(SEARCH_AFTER_MS)
            val sent = try {
                ask(query, filter)
            } catch (e: SubsonicException) {
                state = if (local != null && online) SearchState.Done(SearchFound(local, OutsideResults()), OnlinePhase.Failed(e.userMessage())) else if (local != null) SearchState.Done(SearchFound(local, OutsideResults())) else SearchState.Failed(e.userMessage())
                return@launch
            }
            val shown = (state as? SearchState.Done)?.found?.library
            state = SearchState.Done(split(sent, query, filter).let { it.copy(library = it.library.inOrderOf(shown)) }.also { tops.follow(query, it, filter) })
            // Music the server took in since the library was read is taken
            // in now; once it is, the same answer is split again, so it
            // lists as the library's everywhere.
            val index = index() ?: return@launch
            val arriving = arriving(sent, { index.hasSong(it.id) }, { index.hasAlbum(it.id) }, findsOnline = connection.acquires)
            if (!arriving.isEmpty && takeIn(arriving)) {
                val before = (state as? SearchState.Done)?.found?.library
                state = SearchState.Done(split(sent, query, filter).let { it.copy(library = it.library.inOrderOf(before)) })
            }
        }
    }

    suspend fun search(query: String, filter: SearchFilter): SearchFound = split(ask(query, filter), query, filter)

    private suspend fun ask(query: String, filter: SearchFilter): SearchResult {
        val caps = searchCaps(filter)
        return if (caps.artists + caps.albums + caps.songs == 0) {
            SearchResult()
        } else {
            connection.client.search(
                query,
                artists = if (caps.artists > 0) caps.artists + 1 else 0,
                albums = if (caps.albums > 0) caps.albums + 1 else 0,
                songs = if (caps.songs > 0) maxOf(caps.songs + 1, MIN_SONGS) else 0,
            )
        }
    }

    private fun split(sent: SearchResult, query: String, filter: SearchFilter): SearchFound =
        splitResults(sent, query, filter, playlists(), index(), connection.acquires, hideOutside = libraryOnly())
}
