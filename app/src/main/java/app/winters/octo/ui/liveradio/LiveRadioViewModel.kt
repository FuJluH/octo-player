package app.winters.octo.ui.liveradio

import android.util.Log
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue
import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import app.winters.octo.data.userMessage
import app.winters.octo.liveradio.KeptStations
import app.winters.octo.liveradio.LivePlace
import app.winters.octo.liveradio.LiveRadioStore
import app.winters.octo.liveradio.LiveSearch
import app.winters.octo.liveradio.LiveSort
import app.winters.octo.liveradio.LiveStation
import app.winters.octo.liveradio.PlaceAnswer
import app.winters.octo.liveradio.Places
import app.winters.octo.liveradio.RadioBrowser
import app.winters.octo.liveradio.StationAction
import app.winters.octo.liveradio.livePlayable
import app.winters.octo.liveradio.radiusAt
import app.winters.octo.liveradio.radiusMeters
import app.winters.octo.liveradio.usesMiles
import app.winters.octo.playback.PlaybackConnection
import app.winters.octo.playback.radioId
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

    // The country a typed code or town is looked for in.
    var country by mutableStateOf(places.localeCountry().ifBlank { "US" })

    private var loading: Job? = null

    init {
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

    fun choose(on: Boolean) {
        choosing = on
        placeProblem = null
    }

    // The phone's own position, once Android has allowed it.
    fun useLocation() {
        if (locating) return
        locating = true
        placeProblem = null
        viewModelScope.launch {
            try {
                found(places.here(), typed = false)
            } finally {
                locating = false
            }
        }
    }

    // Location was refused: typing a place still works.
    fun locationRefused() {
        placeProblem = "Octo can't use your location. Type a ZIP, postal code or town instead."
    }

    fun findTyped(text: String) {
        if (locating || text.isBlank()) return
        locating = true
        placeProblem = null
        viewModelScope.launch {
            try {
                found(places.named(text, country), typed = true)
            } finally {
                locating = false
            }
        }
    }

    private suspend fun found(answer: PlaceAnswer, typed: Boolean) {
        when (answer) {
            is PlaceAnswer.Found -> use(answer.place)
            PlaceAnswer.NoFix -> placeProblem = "The phone could not tell where it is. Check that location is on, or type a place instead."
            PlaceAnswer.NotFound -> placeProblem = if (typed) "No place found by that name. Try a ZIP or postal code." else "No place found here."
            PlaceAnswer.NoLookup -> placeProblem = "This phone can't look up places by name. Use your location instead."
        }
    }

    private suspend fun use(place: LivePlace) {
        choosing = false
        store.setPlace(place)
    }

    // Plays a station's stream, and tells the catalog it was started.
    fun play(station: LiveStation) {
        playback.playTracks(listOf(radioId(station.streamUrl, station.name, station.hls)), source = station.name)
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
        try {
            controls.addStation(station.streamUrl, station.name, null)
            feedback.done("Added ${station.name} to your server")
        } catch (e: CancellationException) {
            throw e
        } catch (e: Exception) {
            feedback.show("Could not add ${station.name}: ${e.userMessage()}")
        }
    }
}
