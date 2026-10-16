package app.winters.octo.ui.search

import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue
import androidx.compose.runtime.snapshotFlow
import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import app.winters.octo.catalog.AlbumEntity
import app.winters.octo.catalog.ArtistEntity
import app.winters.octo.catalog.CatalogDao
import app.winters.octo.catalog.PlaylistSummary
import app.winters.octo.catalog.TrackEntity
import app.winters.octo.catalog.searchKey
import app.winters.octo.discovery.AddHint
import app.winters.octo.discovery.Discovered
import app.winters.octo.discovery.Discovery
import app.winters.octo.discovery.Downloads
import app.winters.octo.discovery.OnlineArtist
import app.winters.octo.discovery.RankedTracks
import app.winters.octo.discovery.SearchTopSongs
import app.winters.octo.discovery.searchedArtist
import app.winters.octo.discovery.showsAddHint
import app.winters.octo.playback.PlaybackConnection
import app.winters.octo.playback.PlaylistStore
import app.winters.octo.ui.common.LoadState
import app.winters.octo.ui.common.load
import dagger.hilt.android.lifecycle.HiltViewModel
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.ExperimentalCoroutinesApi
import kotlinx.coroutines.FlowPreview
import kotlinx.coroutines.delay
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.SharingStarted
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.combine
import kotlinx.coroutines.flow.debounce
import kotlinx.coroutines.flow.distinctUntilChanged
import kotlinx.coroutines.flow.map
import kotlinx.coroutines.flow.mapLatest
import kotlinx.coroutines.flow.stateIn
import kotlinx.coroutines.flow.transformLatest
import kotlinx.coroutines.flow.update
import kotlinx.coroutines.launch
import javax.inject.Inject

// How long typing has to pause before the server is asked.
private const val DISCOVER_AFTER_MS = 400L

// Which kind of result a search shows: everything, or one kind in full.
enum class SearchFilter(val label: String) {
    All("All"),
    Songs("Songs"),
    Albums("Albums"),
    Artists("Artists"),
    Playlists("Playlists"),
}

// How many of each kind a search shows. Everything at once shows a few of
// each; one kind picked shows all of it, up to a limit that keeps the list
// quick to build.
class SearchCaps(val artists: Int, val albums: Int, val songs: Int, val playlists: Int)

fun searchCaps(filter: SearchFilter): SearchCaps = when (filter) {
    SearchFilter.All -> SearchCaps(artists = 10, albums = 20, songs = 50, playlists = 10)
    SearchFilter.Songs -> SearchCaps(0, 0, songs = 1_000, playlists = 0)
    SearchFilter.Albums -> SearchCaps(0, albums = 500, 0, 0)
    SearchFilter.Artists -> SearchCaps(artists = 500, 0, 0, 0)
    SearchFilter.Playlists -> SearchCaps(0, 0, 0, playlists = 500)
}

class SearchResults(
    val artists: List<ArtistEntity>,
    val albums: List<AlbumEntity>,
    val songs: List<TrackEntity>,
    val playlists: List<PlaylistSummary> = emptyList(),
    // Whether there are more of a kind than shown, for its "See all".
    val moreArtists: Boolean = false,
    val moreAlbums: Boolean = false,
    val moreSongs: Boolean = false,
    val morePlaylists: Boolean = false,
    // Songs found online whose library song is among these songs, as the
    // library knew when they were looked up. Those are left out of the
    // songs not in the library, so no song is listed twice.
    val listedFinds: Set<String> = emptySet(),
) {
    val isEmpty get() = artists.isEmpty() && albums.isEmpty() && songs.isEmpty() && playlists.isEmpty()
}

// The finds whose library song is among the songs a search listed.
fun listedFinds(adoptions: Map<String, String>, songs: List<TrackEntity>): Set<String> {
    if (adoptions.isEmpty()) return emptySet()
    val ids = songs.mapTo(HashSet()) { it.id }
    return adoptions.filterValues { it in ids }.keys
}

// The songs found online a search shows: all but those already listed as
// library songs.
fun Discovered.without(listed: Set<String>): Discovered =
    if (listed.isEmpty() || songs.none { it.id in listed }) this else Discovered(songs.filterNot { it.id in listed }, albums, artists, partAlbums)

// What searching the server has come to.
sealed interface DiscoverState {
    // Nothing asked: no server, or too little typed.
    data object Idle : DiscoverState
    data object Loading : DiscoverState
    class Done(val found: Discovered) : DiscoverState
    data object Failed : DiscoverState
}

@HiltViewModel
class SearchViewModel @Inject constructor(
    private val dao: CatalogDao,
    private val discovery: Discovery,
    private val playback: PlaybackConnection,
    private val recents: RecentSearches,
    playlists: PlaylistStore,
    private val downloads: Downloads,
    private val hint: AddHint,
    private val tops: SearchTopSongs,
    asks: SearchAsks,
) : ViewModel() {
    var text by mutableStateOf("")
    var filter by mutableStateOf(SearchFilter.All)

    init {
        // Words asked for from elsewhere in the app become the search.
        viewModelScope.launch {
            asks.query.collect { words ->
                if (words != null) {
                    text = words
                    filter = SearchFilter.All
                    asks.took(words)
                }
            }
        }
    }

    // Whether the artist's top songs, and the chart, show every song or
    // only the first few.
    var topOpen by mutableStateOf(false)
    var chartOpen by mutableStateOf(false)

    // Goes up each time the server is asked anew, so the library is too.
    private val rounds = MutableStateFlow(0)

    // Goes up each time the listener asks the server again after it failed.
    private val retries = MutableStateFlow(0)

    // Null until at least two characters are typed. One more than shown is
    // asked for, to know whether there are more. A song that joins the
    // library while the results are shown stays where it is, among the songs
    // not in the library, until the next search, rather than moving under
    // the listener's finger. The server's own songs that the library takes
    // in during a search join these once they are in (see discover).
    @OptIn(FlowPreview::class, ExperimentalCoroutinesApi::class)
    val results: StateFlow<SearchResults?> = combine(
        snapshotFlow { text }.debounce(150).map { searchKey(it) }.distinctUntilChanged(),
        snapshotFlow { filter },
        playlists.playlists,
        rounds,
    ) { q, filter, lists, _ -> Triple(q, filter, lists) }
        .mapLatest { (q, filter, lists) ->
            if (q.length < 2) {
                null
            } else {
                val caps = searchCaps(filter)
                val artists = if (caps.artists > 0) dao.searchArtists(q, caps.artists + 1) else emptyList()
                val albums = if (caps.albums > 0) dao.searchAlbums(q, caps.albums + 1) else emptyList()
                val songs = if (caps.songs > 0) dao.searchTracks(q, caps.songs + 1) else emptyList()
                val named = if (caps.playlists > 0) lists.filter { searchKey(it.name).contains(q) } else emptyList()
                val shown = songs.take(caps.songs)
                SearchResults(
                    artists.take(caps.artists),
                    albums.take(caps.albums),
                    shown,
                    named.take(caps.playlists),
                    moreArtists = artists.size > caps.artists,
                    moreAlbums = albums.size > caps.albums,
                    moreSongs = songs.size > caps.songs,
                    morePlaylists = named.size > caps.playlists,
                    listedFinds = listedFinds(downloads.adoptions.value.orEmpty(), shown),
                )
            }
        }
        .stateIn(viewModelScope, SharingStarted.WhileSubscribed(5_000), null)

    // Whether a server is signed in, so there is more to discover.
    val signedIn: StateFlow<Boolean> =
        discovery.available.stateIn(viewModelScope, SharingStarted.WhileSubscribed(5_000), false)

    // The last searches that led somewhere, newest first.
    val recent: StateFlow<List<String>> =
        recents.all.stateIn(viewModelScope, SharingStarted.WhileSubscribed(5_000), emptyList())

    // Songs, albums and artists the server has beyond the library. It says
    // it is looking as soon as the text changes, and asks once typing
    // pauses; new text cancels the question before it.
    @OptIn(ExperimentalCoroutinesApi::class)
    val discover: StateFlow<DiscoverState> =
        combine(snapshotFlow { text.trim() }, discovery.server, retries) { q, server, retry -> server?.let { q.takeIf { searchKey(it).length >= 2 }?.let { Triple(q, server, retry) } } }
            .distinctUntilChanged()
            .transformLatest { asked ->
                // Another server in use asks it anew, and so does Try again.
                val q = asked?.first
                if (q == null) {
                    emit(DiscoverState.Idle)
                    return@transformLatest
                }
                emit(DiscoverState.Loading)
                delay(DISCOVER_AFTER_MS)
                rounds.update { it + 1 }
                val state = load { discovery.search(q) }
                emit(
                    when (state) {
                        is LoadState.Ready -> state.data?.let { DiscoverState.Done(it) } ?: DiscoverState.Idle
                        is LoadState.Failed -> DiscoverState.Failed
                        LoadState.Loading -> DiscoverState.Loading
                    },
                )
                // Songs the server has that the library had not copied yet
                // show among the library's once they are taken in, a moment
                // after the rest.
                val found = (state as? LoadState.Ready)?.data ?: return@transformLatest
                val tookIn = try {
                    discovery.takeIn(found)
                } catch (e: CancellationException) {
                    throw e
                } catch (e: Exception) {
                    false
                }
                if (tookIn) rounds.update { it + 1 }
            }
            .stateIn(viewModelScope, SharingStarted.WhileSubscribed(5_000), DiscoverState.Idle)

    // The top songs of the artist a search names, from the library's artists
    // or those found online, on the server that ranks them; null while
    // there are none. Only for everything at once.
    @OptIn(FlowPreview::class, ExperimentalCoroutinesApi::class)
    val topSongs: StateFlow<RankedTracks?> = combine(
        snapshotFlow { text.trim() }.debounce(150),
        snapshotFlow { filter },
        results,
        discover,
        discovery.server,
    ) { q, filter, found, online, server ->
        if (filter != SearchFilter.All || found == null || server == null) {
            null
        } else {
            namedArtist(q, found.artists, (online as? DiscoverState.Done)?.found?.artists.orEmpty())?.let { it to server }
        }
    }
        .distinctUntilChanged()
        .transformLatest { asked ->
            topOpen = false
            emit(null)
            val named = asked?.first ?: return@transformLatest
            emit(tops.forArtist(named.name, named.libraryId, named.serverId))
        }
        .stateIn(viewModelScope, SharingStarted.WhileSubscribed(5_000), null)

    // The chart of the moment, for the search before anything is typed,
    // from the server in use: another one asks for its own.
    @OptIn(ExperimentalCoroutinesApi::class)
    val chart: StateFlow<RankedTracks?> = discovery.server
        .transformLatest { server ->
            emit(null)
            if (server != null) emit(tops.chart())
        }
        .stateIn(viewModelScope, SharingStarted.WhileSubscribed(5_000), null)

    // Whether this visit has counted the line saying what the plus does.
    @Volatile
    private var hintCounted = false

    // Whether the line shows under songs not in the library.
    val addHint: StateFlow<Boolean> = hint.state
        .map { showsAddHint(it, hintCounted) }
        .stateIn(viewModelScope, SharingStarted.WhileSubscribed(5_000), false)

    // The line came on screen: one showing, however many searches follow.
    fun addHintSeen() {
        if (hintCounted) return
        hintCounted = true
        viewModelScope.launch { hint.shown() }
    }

    // Keeps what was typed among the recent searches, once it led to a
    // result being opened or played.
    fun keepSearch() {
        val query = text
        viewModelScope.launch { recents.add(query) }
    }

    // Asks the server again after it could not be reached.
    fun retryOnline() {
        retries.update { it + 1 }
    }

    fun searchAgain(query: String) {
        text = query
    }

    fun forget(query: String) {
        viewModelScope.launch { recents.remove(query) }
    }

    fun forgetAll() {
        viewModelScope.launch { recents.clear() }
    }

    // Plays the found songs from the one tapped.
    fun playSong(track: TrackEntity) {
        val songs = results.value?.songs ?: return
        keepSearch()
        playback.playTracks(songs.map { it.id }, songs.indexOf(track).coerceAtLeast(0))
    }

    // Plays a ranked list from the song tapped.
    fun playRanked(list: RankedTracks, index: Int) {
        if (list.artist != null) keepSearch()
        playback.playTracks(list.songs.map { it.track.id }, index.coerceAtLeast(0))
    }

    // Plays the songs found online from the one tapped.
    fun playFound(track: TrackEntity) {
        val songs = (discover.value as? DiscoverState.Done)?.found?.songs ?: return
        keepSearch()
        playback.playTracks(songs.map { it.id }, songs.indexOf(track).coerceAtLeast(0))
    }
}

// The artist a search names: a library artist, or one the server found.
internal data class NamedArtist(val name: String, val libraryId: String? = null, val serverId: String? = null)

// The artist `query` names whole, the library's first, then the server's
// finds; none when it names nobody.
internal fun namedArtist(query: String, library: List<ArtistEntity>, online: List<OnlineArtist>): NamedArtist? {
    searchedArtist(query, library) { it.name }?.let { return NamedArtist(it.name, libraryId = it.id) }
    searchedArtist(query, online) { it.name }?.let { return NamedArtist(it.name, serverId = it.id) }
    return null
}
