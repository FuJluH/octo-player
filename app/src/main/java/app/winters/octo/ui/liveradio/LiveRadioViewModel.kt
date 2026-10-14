package app.winters.octo.ui.liveradio

import android.util.Log
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue
import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import app.winters.octo.data.userMessage
import app.winters.octo.liveradio.AddResult
import app.winters.octo.liveradio.KeptStations
import app.winters.octo.liveradio.ServerAdds
import app.winters.octo.liveradio.addResultLine
import app.winters.octo.liveradio.stationActions
import app.winters.octo.liveradio.LivePlace
import app.winters.octo.liveradio.LiveRadioStore
import app.winters.octo.liveradio.LiveSearch
import app.winters.octo.liveradio.LiveSort
import app.winters.octo.liveradio.LiveStation
import app.winters.octo.liveradio.PlaceAnswer
import app.winters.octo.liveradio.PlaceSource
import app.winters.octo.liveradio.Places
import app.winters.octo.liveradio.placeProblemLine
import app.winters.octo.liveradio.RadioBrowser
import app.winters.octo.liveradio.StationAction
import app.winters.octo.liveradio.livePlayable
import app.winters.octo.liveradio.radiusAt
import app.winters.octo.liveradio.radiusMeters
import app.winters.octo.liveradio.usesMiles
import app.winters.octo.playback.PlaybackConnection
import app.winters.octo.liveradio.lineupOf
import app.winters.octo.liveradio.radioId
import app.winters.octo.server.ServerControls
import app.winters.octo.ui.common.Feedback
import dagger.hilt.android.lifecycle.HiltViewModel
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.Job
import kotlinx.coroutines.flow.SharingStarted
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.stateIn
import kotlinx.coroutines.launch
import javax.inject.Inject

// What the list of stations shows.
sealed interface LiveResults {
    // No place chosen yet.
    data object NoPlace : LiveResults

    data object Loading : LiveResults

    // The stations this phone can play, and how many it cannot.
    data class Ready(val stations: List<LiveStation>, val hidden: Int) : LiveResults

    data object Offline : LiveResults

    // The catalog did not answer.
    data object CatalogDown : LiveResults
}

// Live radio near you: stations from the Radio Browser catalog around a
// place, played straight from their streams, kept on the phone, or, by an
// admin, added to the server.
@HiltViewModel
class LiveRadioViewModel @Inject constructor(
    private val catalog: RadioBrowser,
    private val store: LiveRadioStore,
    private val places: Places,
    private val playback: PlaybackConnection,
    private val controls: ServerControls,
    private val feedback: Feedback,
) : ViewModel() {
    // Miles in the countries that use them, km everywhere else.
    val miles: Boolean = usesMiles(places.localeCountry())

    val admin: StateFlow<Boolean> = controls.admin

    val kept: StateFlow<KeptStations> = store.kept.stateIn(viewModelScope, SharingStarted.WhileSubscribed(5_000), KeptStations())

    // The last place, radius and order; null until read.
    var search by mutableStateOf<LiveSearch?>(null)
        private set

    var results by mutableStateOf<LiveResults>(LiveResults.NoPlace)
        private set

    // Whether the place is being chosen again.
    var choosing by mutableStateOf(false)
        private set

    var locating by mutableStateOf(false)
        private set

    // Why the last place could not be found, in words.
    var placeProblem by mutableStateOf<String?>(null)
        private set

    // Where a place is looked up: on the Octo server or by the phone. Read
    // when the page opens, and again after each lookup.
    var placeSource by mutableStateOf<PlaceSource?>(null)
        private set

    // Android said not to ask for location again: only its settings can
    // allow it now.
    var locationBlocked by mutableStateOf(false)
        private set

    // The server's stations' stream addresses, so a station it has is not
    // offered to it again.
    private var serverStreams by mutableStateOf<Set<String>>(emptySet())

    val adds = ServerAdds(
        admin = { controls.admin.value },
        streams = { serverStreams },
        add = { station -> controls.addStation(station.streamUrl, station.name, null) },
        why = { it.userMessage() },
    )

    // The country a typed code or town is looked for in.
    var country by mutableStateOf(places.localeCountry().ifBlank { "US" })

    private var loading: Job? = null
    private var finding: Job? = null

    init {
        viewModelScope.launch { placeSource = places.source() }
        // An admin's menu leaves out the stations the server has.
        viewModelScope.launch {
            controls.admin.collect { admin ->
                serverStreams = if (admin) {
                    runCatching { controls.stations().map { it.streamUrl }.filter { it.isNotBlank() }.toSet() }.getOrDefault(serverStreams)
                } else {
                    emptySet()
                }
            }
        }
        viewModelScope.launch {
            store.search.collect { saved ->
                val changed = saved != search
                search = saved
                if (saved.place == null) results = LiveResults.NoPlace
                if (changed && saved.place != null) load()
                saved.place?.countryCode?.takeIf { it.isNotBlank() }?.let { if (!choosing) country = it }
            }
        }
    }

    fun load() {
        val now = search ?: return
        val place = now.place ?: return
        loading?.cancel()
        loading = viewModelScope.launch {
            if (!places.online()) {
                results = LiveResults.Offline
                return@launch
            }
            results = LiveResults.Loading
            results = try {
                val all = catalog.near(place, radiusMeters(miles, now.radiusIndex), now.sort)
                val decoders = places.decoders
                val playable = all.filter { livePlayable(it, decoders) }
                LiveResults.Ready(playable, all.size - playable.size)
            } catch (e: CancellationException) {
                throw e
            } catch (e: Exception) {
                Log.w("Octo", "radio catalog failed: ${e.javaClass.simpleName}")
                if (places.online()) LiveResults.CatalogDown else LiveResults.Offline
            }
        }
    }

    fun radius(): Int = radiusAt(miles, search?.radiusIndex ?: 0)

    fun setRadius(index: Int) {
        viewModelScope.launch { store.setRadius(index) }
    }

    fun setSort(sort: LiveSort) {
        viewModelScope.launch { store.setSort(sort) }
    }

    // Choosing a place again, or not: Cancel also stops a lookup under way.
    fun choose(on: Boolean) {
        if (!on) {
            finding?.cancel()
            locating = false
        }
        choosing = on
        placeProblem = null
    }

    // The phone's own position, once Android has allowed it.
    fun useLocation() {
        locationBlocked = false
        find { found(places.here(), typed = false) }
    }

    // Location was refused: typing a place still works. `forGood` when
    // Android will not ask again, so the way is through its settings.
    fun locationRefused(forGood: Boolean) {
        locationBlocked = forGood
        placeProblem = if (forGood) {
            "Location is off for Octo. Allow it in Android's settings, or type a ZIP, postal code or town instead."
        } else {
            "Octo can't use your location. Type a ZIP, postal code or town instead."
        }
    }

    fun findTyped(text: String) {
        if (text.isBlank()) return
        find { found(places.named(text, country), typed = true) }
    }

    // One lookup at a time; Cancel stops it.
    private fun find(lookup: suspend () -> Unit) {
        if (locating) return
        locating = true
        placeProblem = null
        finding = viewModelScope.launch {
            try {
                lookup()
                placeSource = places.source()
            } finally {
                locating = false
            }
        }
    }

    private suspend fun found(answer: PlaceAnswer, typed: Boolean) {
        placeProblem = placeProblemLine(answer, typed)
        if (answer is PlaceAnswer.Found) use(answer.place)
    }

    private suspend fun use(place: LivePlace) {
        choosing = false
        store.setPlace(place)
    }

    // What a station's menu offers.
    fun actions(station: LiveStation): List<StationAction> =
        stationActions(kept.value.has(station.uuid), addable = adds.offers(station))

    // Plays a station's stream, with the rest of the list it is in (the
    // stations found, or the ones kept) in its order for Back and Next, and
    // tells the catalog it was started.
    fun play(list: List<LiveStation>, station: LiveStation) {
        val (ids, start) = lineupOf(list, list.indexOf(station).coerceAtLeast(0), { it.streamUrl }, { it.radioId() })
        playback.playLineup(ids.ifEmpty { listOf(station.radioId()) }, start, source = LIVE_NEAR_TITLE)
        viewModelScope.launch { catalog.started(station.uuid) }
    }

    fun act(station: LiveStation, action: StationAction) {
        viewModelScope.launch {
            when (action) {
                StationAction.Keep -> {
                    store.keep(station)
                    feedback.done("Kept ${station.name} on Live radio")
                }
                StationAction.Remove -> {
                    store.drop(station.uuid)
                    feedback.undoable("Removed ${station.name}") { viewModelScope.launch { store.keep(station) } }
                }
                StationAction.AddToServer -> addToServer(station)
            }
        }
    }

    private suspend fun addToServer(station: LiveStation) {
        val result = adds.addToServer(station)
        val line = addResultLine(result, station.name)
        if (result == AddResult.Added) {
            serverStreams = serverStreams + station.streamUrl
            feedback.done(line)
        } else {
            feedback.show(line)
        }
    }
}
