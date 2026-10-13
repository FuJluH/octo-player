package app.winters.octo.ui.home

import app.winters.octo.discovery.CHARTS_ROW
import app.winters.octo.discovery.ChartAnswer
import app.winters.octo.discovery.ChartLists
import app.winters.octo.subsonic.CHART_OVERALL
import android.os.SystemClock
import android.util.Log
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue
import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import app.winters.octo.catalog.AlbumEntity
import app.winters.octo.catalog.ArtistEntity
import app.winters.octo.catalog.CatalogDao
import app.winters.octo.catalog.FavouritesDao
import app.winters.octo.catalog.TrackEntity
import app.winters.octo.catalog.byLatestPlay
import app.winters.octo.catalog.byPlayCount
import app.winters.octo.device.DeviceLibrary
import app.winters.octo.discovery.Discovery
import app.winters.octo.discovery.Station
import app.winters.octo.favourites.PinStore
import app.winters.octo.favourites.PinnedItem
import app.winters.octo.home.Rediscovery
import app.winters.octo.home.answered
import app.winters.octo.listening.PlayHistory
import app.winters.octo.playback.PlaybackConnection
import app.winters.octo.server.ServerSync
import app.winters.octo.subsonic.SubsonicException
import app.winters.octo.ui.common.Feedback
import dagger.hilt.android.lifecycle.HiltViewModel
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.Job
import kotlinx.coroutines.flow.SharingStarted
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.combine
import kotlinx.coroutines.flow.distinctUntilChanged
import kotlinx.coroutines.flow.flowOn
import kotlinx.coroutines.flow.map
import kotlinx.coroutines.flow.stateIn
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext
import javax.inject.Inject
import kotlin.coroutines.cancellation.CancellationException

@HiltViewModel
class HomeViewModel @Inject constructor(
    private val dao: CatalogDao,
    history: PlayHistory,
    private val playback: PlaybackConnection,
    private val discovery: Discovery,
    val library: DeviceLibrary,
    private val prefs: HomePrefs,
    private val feedback: Feedback,
    serverSync: ServerSync,
    pins: PinStore,
    favourites: FavouritesDao,
    private val chartLists: ChartLists,
    keptFiles: KeptShelvesFiles,
) : ViewModel() {
    // What is pinned to the front of Home, in its order.
    val pinned: StateFlow<List<PinnedItem>> =
        pins.items.stateIn(viewModelScope, SharingStarted.WhileSubscribed(5_000), emptyList())

    // The latest favourite albums, newest favourite first.
    val favouriteAlbums: StateFlow<List<AlbumEntity>> =
        favourites.likedAlbums().map { rows -> rows.sortedByDescending { it.likedAt }.take(20).map { it.album } }
            .stateIn(viewModelScope, SharingStarted.WhileSubscribed(5_000), emptyList())

    // Both follow the play history, here and on the server, so a song that
    // just counted shows up.
    val recentlyPlayed: StateFlow<List<AlbumEntity>> =
        history.albums.map { byLatestPlay(it, 20) }
            .stateIn(viewModelScope, SharingStarted.WhileSubscribed(5_000), emptyList())

    val mostPlayed: StateFlow<List<TrackEntity>> =
        history.tracks.map { byPlayCount(it, 20) }
            .stateIn(viewModelScope, SharingStarted.WhileSubscribed(5_000), emptyList())

    // Albums worth going back to, from the library's own plays: not played
    // in six months, never finished, never played.
    val rediscovery: StateFlow<Rediscovery<AlbumEntity>> =
        combine(dao.albums(), history.tracks) { albums, played -> homeRediscovery(albums, played, System.currentTimeMillis()) }
            .flowOn(Dispatchers.Default)
            .stateIn(viewModelScope, SharingStarted.WhileSubscribed(5_000), Rediscovery())

    val recent: StateFlow<List<AlbumEntity>?> =
        dao.recentAlbums(20).stateIn(viewModelScope, SharingStarted.WhileSubscribed(5_000), null)

    // Every song in the library, phone and server together. Null until read.
    val librarySongs: StateFlow<Int?> =
        dao.libraryTrackCount().stateIn(viewModelScope, SharingStarted.WhileSubscribed(5_000), null)

    // Whether the phone access card was put away with "Not now". Null until read.
    val accessDismissed: StateFlow<Boolean?> =
        prefs.accessDismissed.stateIn(viewModelScope, SharingStarted.WhileSubscribed(5_000), null)

    // Picked once, then again on a pull, when the library changes size, or
    // after a server copy (which can change the music without changing the count).
    var surprise by mutableStateOf<List<AlbumEntity>>(emptyList())
        private set
    var artists by mutableStateOf<List<ArtistEntity>>(emptyList())
        private set
    var refreshing by mutableStateOf(false)
        private set

    // The signed-in server's stations, kept through a failed load. Each of
    // these three server shelves starts as the server last gave it, read
    // from the app's cache, and changes only when an answer differs.
    var stations by mutableStateOf<List<Station>>(emptyList())
        private set

    // The lists Octo made for the listener, kept through a failed load.
    var madeForYou by mutableStateOf<List<Station>>(emptyList())
        private set

    // The first songs of the server's chart of the moment, for Home's Charts
    // row; empty on a server without charts, kept through a failed load.
    var charts by mutableStateOf<List<TrackEntity>>(emptyList())
        private set

    // The station, or Made for you list, whose songs are on the way, if any.
    var startingStation by mutableStateOf<String?>(null)
        private set

    private var offersStations = false
    private var stationsJob: Job? = null
    private var chartsJob: Job? = null

    // The server whose shelves are shown, and where each server's are kept.
    // Writes go one at a time, in the order they were made.
    private var shelvesFrom: String? = null
    private val kept = keptFiles.store
    private val keeping = Dispatchers.IO.limitedParallelism(1)
    private var stationsLoadedAt: Long? = null
    private var stationsFailed = false

    init {
        viewModelScope.launch {
            combine(dao.libraryTrackCount(), serverSync.last.map { it?.at }) { count, syncedAt -> count to syncedAt }
                .distinctUntilChanged()
                .collect { reroll() }
        }
        // A new sign-in or another kept server shows the shelves it gave
        // last time at once, or none, and asks it again; signing out, or a
        // server without stations, drops them. The server can turn out to be
        // Octo after start, once its extensions are read again.
        viewModelScope.launch {
            discovery.stationsFrom.collect { server ->
                offersStations = server != null
                stationsJob?.cancel()
                chartsJob?.cancel()
                stationsLoadedAt = null
                stationsFailed = false
                shelvesFrom = server
                val last = server?.let { withContext(Dispatchers.IO) { kept.read(it) } } ?: KeptShelves()
                stations = answered(stations, last.stations)
                madeForYou = answered(madeForYou, last.madeForYou)
                charts = answered(charts, last.charts)
                if (server != null) {
                    loadStations()
                    loadCharts()
                }
            }
        }
    }

    // Home is on screen again: ask for the stations if the last try failed
    // or the list is getting old.
    fun onShown() {
        val loading = stationsJob?.isActive == true
        if (offersStations && stationsDue(SystemClock.elapsedRealtime(), stationsLoadedAt, stationsFailed, loading)) {
            loadStations()
        }
    }

    // Plays what a station has lined up today. Taps while one is on the
    // way are ignored.
    fun playStation(station: Station) {
        if (startingStation != null) return
        startingStation = station.id
        viewModelScope.launch {
            try {
                val songs = withContext(Dispatchers.IO) { discovery.stationSongs(station.id) }
                if (songs.isEmpty()) feedback.show("Nothing is playing on ${station.name} right now")
                playback.playTracks(songs.map { it.id }, 0)
            } catch (e: CancellationException) {
                throw e
            } catch (e: SubsonicException.NotFound) {
                // Made anew on the server since the list was read: off Home,
                // and the list read again.
                stations = stations.filterNot { it.id == station.id }
                madeForYou = madeForYou.filterNot { it.id == station.id }
                stationsLoadedAt = null
                loadStations()
                feedback.show(stationGoneLine(station.name))
            } catch (e: Exception) {
                Log.w("Octo", "station failed to start: ${e.javaClass.simpleName}")
                feedback.show("Could not start ${station.name}")
            } finally {
                startingStation = null
            }
        }
    }

    // "Not now" on the phone access card, kept for next time.
    fun dismissAccess() {
        viewModelScope.launch { prefs.dismissAccess() }
    }

    // Plays a shelf of songs as shown, starting at the one tapped.
    fun play(tracks: List<TrackEntity>, index: Int) = playback.playTracks(tracks.map { it.id }, index)

    // A server without charts empties the row; one that did not answer
    // leaves it as it is.
    private fun loadCharts() {
        chartsJob = viewModelScope.launch {
            val got = when (val answer = chartLists.answer(CHART_OVERALL)) {
                is ChartAnswer.Got -> answer.list.songs.take(CHARTS_ROW).map { it.track }
                ChartAnswer.None -> emptyList()
                ChartAnswer.Failed -> return@launch
            }
            charts = answered(charts, got)
            keepShelves()
        }
    }

    fun refresh() {
        viewModelScope.launch {
            refreshing = true
            library.rescan()
            reroll()
            refreshing = false
        }
        if (offersStations) loadStations()
    }

    // Runs in the background so no other shelf waits on the server. The
    // stations and Made for you are read apart, so one failing never hides
    // the other; either failing asks again when Home comes back. Each
    // answer replaces its shelf only when it differs from what is shown.
    private fun loadStations() {
        if (stationsJob?.isActive == true) return
        stationsJob = viewModelScope.launch {
            var failed = false
            var answers = 0
            try {
                val got = withContext(Dispatchers.IO) { discovery.stations() }
                stations = answered(stations, got)
                answers++
            } catch (e: CancellationException) {
                throw e
            } catch (e: Exception) {
                failed = true
                Log.w("Octo", "stations failed to load: ${e.javaClass.simpleName}")
            }
            try {
                val got = withContext(Dispatchers.IO) { discovery.madeForYou() }
                madeForYou = answered(madeForYou, got)
                answers++
            } catch (e: CancellationException) {
                throw e
            } catch (e: Exception) {
                failed = true
                Log.w("Octo", "made for you failed to load: ${e.javaClass.simpleName}")
            }
            if (!failed) stationsLoadedAt = SystemClock.elapsedRealtime()
            stationsFailed = failed
            if (answers > 0) keepShelves()
        }
    }

    // Keeps the server shelves as shown for the server in use, for the
    // next start or a switch back to it.
    private fun keepShelves() {
        val server = shelvesFrom ?: return
        val shelves = KeptShelves(stations, madeForYou, charts)
        viewModelScope.launch(keeping) { kept.write(server, shelves) }
    }

    private suspend fun reroll() {
        surprise = dao.randomAlbums(20)
        artists = dao.randomArtists(16)
    }
}
