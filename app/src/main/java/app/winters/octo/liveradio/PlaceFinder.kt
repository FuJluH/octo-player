package app.winters.octo.liveradio

import app.winters.octo.subsonic.OCTO_PLACES
import app.winters.octo.subsonic.Place
import app.winters.octo.subsonic.SubsonicClient
import kotlinx.coroutines.withTimeoutOrNull
import kotlin.coroutines.cancellation.CancellationException

// What looking for a place gave.
sealed interface PlaceAnswer {
    data class Found(val place: LivePlace) : PlaceAnswer

    // The phone gave no position: its location is off or it found none.
    data object NoFix : PlaceAnswer

    // Nothing by that name or code, as the server or the phone said.
    data class NotFound(val by: PlaceSource) : PlaceAnswer

    // The Octo server looks places up, or may, but did not answer.
    data object ServerDown : PlaceAnswer

    // Nothing here can look up places by name.
    data object NoLookup : PlaceAnswer
}

// Where places are looked up: on the Octo server in use, by the phone's own
// place service, or nowhere.
enum class PlaceSource { Server, Phone, None }

// Whether a server's extensions include place lookups.
fun listsPlaces(extensions: Set<String>): Boolean = extensions.any { it == OCTO_PLACES || it.startsWith("$OCTO_PLACES:") }

// What the server in use does with places.
sealed interface ServerRoute {
    // It looks them up.
    data class Asks(val service: PlaceService) : ServerRoute

    // It is an Octo server that did not answer when asked what it offers:
    // places wait for it and never go to the phone's service.
    data object NotAnswering : ServerRoute

    // No server, or one that does not look places up: the phone's service
    // may.
    data object NoPlaces : ServerRoute
}

// Which way the server in use takes places. A server whose saved list of
// extensions has octoPlaces asks it. An Octo server whose saved list does
// not is asked for its list again (`readAgain`), since that list is saved
// empty when it could not be read at sign-in and kept as it was when a
// later read failed; one that does not answer is NotAnswering. Any other
// server has no places.
suspend fun serverRoute(
    signedIn: Boolean,
    octo: Boolean,
    saved: Set<String>,
    readAgain: suspend () -> Set<String>?,
    service: () -> PlaceService,
): ServerRoute = when {
    !signedIn -> ServerRoute.NoPlaces
    listsPlaces(saved) -> ServerRoute.Asks(service())
    !octo -> ServerRoute.NoPlaces
    else -> {
        val fresh = try {
            readAgain()
        } catch (e: CancellationException) {
            throw e
        } catch (e: Exception) {
            null
        }
        when {
            fresh == null -> ServerRoute.NotAnswering
            listsPlaces(fresh) -> ServerRoute.Asks(service())
            else -> ServerRoute.NoPlaces
        }
    }
}

// The words under the place choice saying where a place is looked up.
fun placeSourceLine(source: PlaceSource): String = when (source) {
    PlaceSource.Server -> "Places you type, and your town from your location, are looked up on your Octo server."
    PlaceSource.Phone -> "Places you type, and your town from your location, are looked up by your phone's place service."
    PlaceSource.None -> "This phone can't look up places by name, so use your location."
}

// One way to look places up.
interface PlaceService {
    // A place by a postal code, or a town with its state when given, in a
    // country (ISO code); null when none is known.
    suspend fun typed(asked: TypedPlace, country: String): LivePlace?

    // The town, state and country around a rounded position; null when none
    // is known.
    suspend fun around(latitude: Double, longitude: Double): LivePlace?
}

// What was typed: a postal code, a town, its state, or some of them.
data class TypedPlace(val code: String? = null, val name: String? = null, val state: String? = null) {
    val words: String get() = listOfNotNull(name, state).joinToString(", ").ifEmpty { code.orEmpty() }
}

// Reads what was typed as both apps do (parseWhere): the words with a digit
// in them are the postal code, the rest the town and its state.
fun typedPlace(text: String): TypedPlace? = parseWhere(text)?.let { TypedPlace(it.code, it.name, it.state) }

// A place as the server answered it. A reverse lookup keeps the phone's own
// rounded position; a typed one takes the server's.
internal fun Place.toLive(fallbackLabel: String, country: String, at: Pair<Double, Double>? = null): LivePlace = LivePlace(
    latitude = at?.first ?: roundedPlace(latitude),
    longitude = at?.second ?: roundedPlace(longitude),
    label = placeLabel(name, state, fallbackLabel),
    state = state.trim(),
    countryCode = this.country.trim().uppercase().ifEmpty { country.trim().uppercase() },
)

// Places looked up on an Octo server that lists octoPlaces (getPlace).
class ServerPlaces(private val client: SubsonicClient) : PlaceService {
    override suspend fun typed(asked: TypedPlace, country: String): LivePlace? =
        client.place(asked.code, asked.name, asked.state, country)?.toLive(asked.words, country)

    override suspend fun around(latitude: Double, longitude: Double): LivePlace? =
        client.place(null, null, null, "", latitude, longitude)?.toLive("Your location", "", latitude to longitude)
}

// How long the server, or the phone's service, gets to name a place.
const val PLACE_WAIT_MS = 15_000L

// Finds places: on the server when it looks them up (or, as an Octo server,
// may), otherwise by the phone's place service. Only one is asked for any
// lookup, so with an Octo server nothing goes to the phone's service.
class PlaceFinder(
    private val route: suspend () -> ServerRoute,
    private val phone: () -> PlaceService?,
    private val waitMs: Long = PLACE_WAIT_MS,
) {
    suspend fun source(): PlaceSource = when (route()) {
        is ServerRoute.Asks, ServerRoute.NotAnswering -> PlaceSource.Server
        ServerRoute.NoPlaces -> if (phone() != null) PlaceSource.Phone else PlaceSource.None
    }

    suspend fun typed(text: String, country: String): PlaceAnswer {
        val asked = typedPlace(text) ?: return PlaceAnswer.NotFound(source())
        when (val way = route()) {
            is ServerRoute.Asks -> return try {
                val found = withTimeoutOrNull(waitMs) { Answer(way.service.typed(asked, country)) } ?: return PlaceAnswer.ServerDown
                found.place?.let { PlaceAnswer.Found(it) } ?: PlaceAnswer.NotFound(PlaceSource.Server)
            } catch (e: CancellationException) {
                throw e
            } catch (e: Exception) {
                PlaceAnswer.ServerDown
            }
            ServerRoute.NotAnswering -> return PlaceAnswer.ServerDown
            ServerRoute.NoPlaces -> Unit
        }
        val fromPhone = phone() ?: return PlaceAnswer.NoLookup
        return quietly { fromPhone.typed(asked, country) }?.let { PlaceAnswer.Found(it) } ?: PlaceAnswer.NotFound(PlaceSource.Phone)
    }

    // A position already rounded, named by its town, state and country when
    // they can be had; when they cannot (or the server does not answer in
    // time), it is searched by its radius alone.
    suspend fun around(latitude: Double, longitude: Double): PlaceAnswer {
        val service = when (val way = route()) {
            is ServerRoute.Asks -> way.service
            ServerRoute.NotAnswering -> null
            ServerRoute.NoPlaces -> phone()
        }
        val named = service?.let { quietly { it.around(latitude, longitude) } }
        return PlaceAnswer.Found(named ?: LivePlace(latitude, longitude, "Your location"))
    }

    // A lookup, or null when it fails or takes too long.
    private suspend fun quietly(call: suspend () -> LivePlace?): LivePlace? = try {
        withTimeoutOrNull(waitMs) { call() }
    } catch (e: CancellationException) {
        throw e
    } catch (e: Exception) {
        null
    }

    // An answer that may be "none", told apart from no answer in time.
    private class Answer(val place: LivePlace?)
}

// Why a place could not be used, in words; null when it was found.
fun placeProblemLine(answer: PlaceAnswer, typed: Boolean): String? = when (answer) {
    is PlaceAnswer.Found -> null
    PlaceAnswer.NoFix -> "The phone could not tell where it is. Check that location is on, or type a place instead."
    is PlaceAnswer.NotFound -> when {
        answer.by == PlaceSource.Server -> "Your Octo server does not know that place. Try a postal code or a nearby town."
        typed -> "No place found by that name. Try a ZIP or postal code."
        else -> "No place found here."
    }
    PlaceAnswer.ServerDown -> "Your server is not answering. Try again in a moment."
    PlaceAnswer.NoLookup -> "This phone can't look up places by name. Use your location instead."
}

// To two decimals, about a kilometer.
fun roundedPlace(value: Double): Double = Math.round(value * 100) / 100.0
