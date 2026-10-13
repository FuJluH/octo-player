package app.winters.octo.desktop.liveradio

import androidx.compose.runtime.Stable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue
import app.winters.octo.desktop.server.Connection
import app.winters.octo.desktop.server.userMessage
import app.winters.octo.desktop.settings.LiveRadioPrefs
import app.winters.octo.desktop.settings.SettingsStore
import app.winters.octo.liveradio.KeptStations
import app.winters.octo.liveradio.LivePlace
import app.winters.octo.liveradio.LiveSort
import app.winters.octo.liveradio.LiveStation
import app.winters.octo.liveradio.RadioBrowser
import app.winters.octo.subsonic.OCTO_PLACES
import app.winters.octo.subsonic.Place
import app.winters.octo.subsonic.RadioStationDetails
import app.winters.octo.subsonic.SubsonicException
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Job
import kotlinx.coroutines.launch

// What the Live radio page shows under its controls.
sealed interface LiveFind {
    // No place asked about yet.
    data object NoPlace : LiveFind

    data object Finding : LiveFind

    data class Found(val place: LivePlace, val stations: List<LiveStation>) : LiveFind

    // The place could not be found, in words.
    data class Problem(val words: String) : LiveFind

    // The catalog did not answer.
    data class CatalogDown(val place: LivePlace) : LiveFind
}

// Live radio near the listener: the place they asked about, the stations
// the catalog has around it, the stations they kept here, and whether they
// may add stations to the server in use. The place, radius, order and kept
// stations are saved in the settings.
@Stable
class LiveRadioModel(
    private val settings: SettingsStore,
    private val catalog: RadioBrowser,
    private val connection: () -> Connection?,
    private val scope: CoroutineScope,
    // This computer's country, which picks miles or kilometers and is the
    // Where field's country until another is chosen.
    val homeCountry: String = systemCountry(),
) {
    var find by mutableStateOf<LiveFind>(LiveFind.NoPlace)
        private set

    // Whether the signed-in user is an admin of the server in use, which
    // may add, change and delete its stations; null until asked.
    var admin by mutableStateOf<Boolean?>(null)
        private set

    // The server's own stations with their home pages, once read; null
    // until then, or when they could not be read.
    var serverStations by mutableStateOf<List<RadioStationDetails>?>(null)
        private set

    // A place being looked up, and the stations being searched for; apart,
    // so a new radius or order never cancels a lookup before its place is
    // saved.
    private var lookupJob: Job? = null
    private var searchJob: Job? = null
    private var adminFor: Connection? = null

    val prefs: LiveRadioPrefs get() = settings.current.liveRadio

    // Distances in miles or kilometers, by this computer's country.
    val miles: Boolean get() = usesMiles(homeCountry)

    // The country the Where field looks in.
    fun country(prefs: LiveRadioPrefs = this.prefs): String = prefs.country.ifBlank { homeCountry }

    fun kept(prefs: LiveRadioPrefs = this.prefs): KeptStations = KeptStations.decoded(prefs.kept)

    // The page opened: the saved place is searched again, unless its
    // stations are already showing, and the server is asked who the user is.
    fun open() {
        checkAdmin()
        val place = prefs.place ?: return
        if (find is LiveFind.NoPlace) search(place)
    }

    // Looks up what the listener typed in Where, in `country`, then the
    // stations around it. Nothing typed changes nothing.
    fun lookUp(where: String, country: String) {
        val asked = whereOf(where, country) ?: return
        lookupJob?.cancel()
        searchJob?.cancel()
        find = LiveFind.Finding
        lookupJob = scope.launch {
            val inUse = connection()
            val lookup: (suspend (WhereAsked) -> Place?)? = if (inUse?.supports(OCTO_PLACES) == true) {
                { a -> inUse.client.place(a.code, a.name, a.state, a.country) }
            } else {
                null
            }
            val answer = try {
                resolvePlace(asked, lookup)
            } catch (e: SubsonicException) {
                PlaceAnswer.Problem("Couldn't ask your server where that is. ${e.userMessage()}")
            }
            when (answer) {
                is PlaceAnswer.Problem -> find = LiveFind.Problem(answer.words)
                is PlaceAnswer.Found -> {
                    settings.update { it.copy(liveRadio = it.liveRadio.copy(where = where.trim(), country = asked.country, place = answer.place)) }
                    find = stationsAround(answer.place)
                }
            }
        }
    }

    // A wider or narrower circle, by its place in the choices.
    fun setRadius(index: Int) {
        if (index == prefs.radius) return
        settings.update { it.copy(liveRadio = it.liveRadio.copy(radius = index)) }
        prefs.place?.let(::search)
    }

    fun setSort(sort: LiveSort) {
        if (sort == prefs.sort) return
        settings.update { it.copy(liveRadio = it.liveRadio.copy(sort = sort)) }
        prefs.place?.let(::search)
    }

    // Asks the catalog again, after it did not answer.
    fun retry() {
        prefs.place?.let(::search)
    }

    // Searches the saved place again. While a lookup runs, it searches its
    // own place once found, with the radius and order as they are then.
    private fun search(place: LivePlace) {
        if (lookupJob?.isActive == true) return
        searchJob?.cancel()
        find = LiveFind.Finding
        searchJob = scope.launch { find = stationsAround(place) }
    }

    private suspend fun stationsAround(place: LivePlace): LiveFind = try {
        val now = prefs
        LiveFind.Found(place, catalog.near(place, radiusMeters(now.radius, miles), now.sort, ::livePlayable))
    } catch (e: CancellationException) {
        throw e
    } catch (e: Exception) {
        LiveFind.CatalogDown(place)
    }

    fun keep(station: LiveStation) = settings.update { it.copy(liveRadio = it.liveRadio.copy(kept = kept(it.liveRadio).keep(station).encoded())) }

    fun drop(uuid: String) = settings.update { it.copy(liveRadio = it.liveRadio.copy(kept = kept(it.liveRadio).drop(uuid).encoded())) }

    // Tells the catalog a station was started, as its keepers ask.
    fun started(uuid: String) {
        if (uuid.isBlank()) return
        scope.launch { catalog.started(uuid) }
    }

    // Asks the server in use, once, whether the user is an admin there.
    fun checkAdmin() {
        val inUse = connection() ?: return
        if (adminFor === inUse && admin != null) return
        adminFor = inUse
        scope.launch {
            val name = inUse.client.username
            val answer = try {
                name.isNotBlank() && inUse.client.user(name).adminRole
            } catch (e: SubsonicException) {
                false
            }
            if (adminFor === inUse) admin = answer
        }
    }

    // Reads the server's stations again: true when they were read.
    suspend fun readServerStations(): Boolean {
        val inUse = connection() ?: return false
        return try {
            val stations = inUse.client.radioStationDetails()
            if (connection() === inUse) serverStations = stations
            true
        } catch (e: SubsonicException) {
            false
        }
    }

    // Whether the server in use already streams this address.
    fun onServer(streamUrl: String): Boolean = serverStations.orEmpty().any { streamKey(it.streamUrl) == streamKey(streamUrl) }

    // Everything known came from the server last in use.
    fun forget() {
        admin = null
        adminFor = null
        serverStations = null
    }
}
