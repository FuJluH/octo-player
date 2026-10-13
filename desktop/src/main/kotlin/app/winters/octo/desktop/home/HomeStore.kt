package app.winters.octo.desktop.home

import androidx.compose.runtime.Stable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue
import app.winters.octo.desktop.library.LibraryIndex
import app.winters.octo.desktop.server.Connection
import app.winters.octo.desktop.server.userMessage
import app.winters.octo.desktop.settings.key
import app.winters.octo.home.DefaultHomeSections
import app.winters.octo.home.HomeSection
import app.winters.octo.home.HomeSectionEntry
import app.winters.octo.home.HomeShelfStore
import app.winters.octo.home.Rediscovery
import app.winters.octo.home.answered
import app.winters.octo.home.rediscovery
import app.winters.octo.home.shows
import app.winters.octo.subsonic.Album
import app.winters.octo.subsonic.Playlist
import app.winters.octo.subsonic.SubsonicException
import app.winters.octo.subsonic.TopSongs
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.Job
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext

// Home's shelves, kept for the session so going back to Home finds them
// in place, with its scroll. Each visit refreshes them quietly behind what
// is showing. The server shelves (stations, Made for you, the chart) start
// as this server last gave them, from `kept`, and change only when an
// answer differs; each answer is kept there for next time. `sections` is
// Home's order as saved: hidden stations are not asked for.
@Stable
class HomeStore(
    private val connection: Connection,
    private val scope: CoroutineScope,
    private val clock: () -> Long = System::currentTimeMillis,
    private val kept: HomeShelfStore<KeptShelves>? = null,
    private val sections: () -> List<HomeSectionEntry> = { DefaultHomeSections },
) {
    var data by mutableStateOf<HomeData?>(null)
        private set

    var shelves by mutableStateOf(kept?.read(connection.server.key) ?: KeptShelves())
        private set

    // Why the first read failed, while there is nothing to show.
    var failure by mutableStateOf<String?>(null)
        private set

    // The rediscovery shelves, from the library last worked through.
    var rediscovered by mutableStateOf<Rediscovery<Album>?>(null)
        private set

    private var job: Job? = null
    private var worked: LibraryIndex? = null

    // Writes go one at a time, in the order they were made.
    private val keeping = Dispatchers.IO.limitedParallelism(1)

    // Whether the last read that finished asked for Octo's stations and for
    // the live streams.
    private var stationsAsked = false
    private var liveAsked = false

    fun refresh() {
        if (job?.isActive == true) return
        val wantStations = sections().shows(HomeSection.Stations)
        val wantLive = sections().shows(HomeSection.InternetRadio)
        job = scope.launch {
            try {
                val loaded = loadHome(connection, stations = wantStations, live = wantLive)
                data = loaded
                stationsAsked = wantStations
                liveAsked = wantLive
                loaded.stations?.let { stations -> keep(shelves.copy(stations = answered(shelves.stations, stations))) }
                loaded.live?.let { live -> keep(shelves.copy(live = answered(shelves.live, live))) }
                failure = null
            } catch (e: SubsonicException) {
                // A failed refresh keeps what is showing.
                if (data == null) failure = e.userMessage()
            }
        }
    }

    // Works out the rediscovery shelves from a library, away from the
    // window's thread, once for each time the library is read.
    fun rediscover(index: LibraryIndex) {
        if (index === worked) return
        worked = index
        scope.launch {
            val shelves = withContext(Dispatchers.Default) { rediscovery(index.albums, listeningOf(index), clock(), SHELF_SIZE) }
            if (worked === index) rediscovered = shelves
        }
    }

    // Home's sections were changed: stations or live streams shown again are
    // asked for now, even while a read without them is still running.
    fun sectionsChanged() {
        val shown = sections()
        val stationsNow = shown.shows(HomeSection.Stations) && !stationsAsked
        val liveNow = shown.shows(HomeSection.InternetRadio) && !liveAsked
        if (!stationsNow && !liveNow) return
        job?.cancel()
        refresh()
    }

    // A live stream was added to the server: read again now, even while a
    // read is running.
    fun liveChanged() {
        job?.cancel()
        refresh()
    }

    // The server's playlists as just read: the Made for you lists among them.
    fun playlistsAnswered(playlists: List<Playlist>) {
        keep(shelves.copy(madeForYou = answered(shelves.madeForYou, madeForYou(playlists))))
    }

    // The server's chart of the moment as just read, or null when the server
    // has no charts.
    fun chartAnswered(top: TopSongs?) {
        keep(shelves.copy(chart = answered(shelves.chart, top?.let(::homeChart))))
    }

    // A station the server no longer has (Octo makes its stations anew now
    // and then): off the shelf at once, and the shelves read again.
    fun stationGone(id: String) {
        keep(shelves.copy(stations = shelves.stations.filterNot { station -> station.id == id }))
        refresh()
    }

    // Shows the server shelves and keeps them for next time; an equal set
    // changes nothing.
    private fun keep(next: KeptShelves) {
        if (next == shelves) return
        shelves = next
        val store = kept ?: return
        val server = connection.server.key
        scope.launch(keeping) { store.write(server, next) }
    }

    // Tried again by hand, after a failure or on an empty Home: everything
    // read afresh.
    fun retry() {
        job?.cancel()
        data = null
        failure = null
        refresh()
    }
}
