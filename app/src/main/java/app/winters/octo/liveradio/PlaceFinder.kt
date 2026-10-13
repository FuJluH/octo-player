package app.winters.octo.liveradio

import app.winters.octo.subsonic.OCTO_PLACES
import app.winters.octo.subsonic.Place
import app.winters.octo.subsonic.SubsonicClient
import kotlin.coroutines.cancellation.CancellationException

// What looking for a place gave.
sealed interface PlaceAnswer {
    data class Found(val place: LivePlace) : PlaceAnswer

    // The phone gave no position: its location is off or it found none.
    data object NoFix : PlaceAnswer

    // Nothing by that name or code, as the server or the phone said.
    data class NotFound(val by: PlaceSource) : PlaceAnswer

    // The server lists place lookups but did not answer.
    data object ServerDown : PlaceAnswer

    // Nothing here can look up places by name.
    data object NoLookup : PlaceAnswer
}

// Where places are looked up: on the Octo server in use, by the phone's own
// place service, or nowhere.
enum class PlaceSource { Server, Phone, None }

// Whether a server's extensions include place lookups.
fun listsPlaces(extensions: Set<String>): Boolean = extensions.any { it == OCTO_PLACES || it.startsWith("$OCTO_PLACES:") }

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

// What was typed: a postal code, or a town and maybe its state.
data class TypedPlace(val code: String? = null, val name: String? = null, val state: String? = null) {
    val words: String get() = code ?: listOfNotNull(name, state).joinToString(", ")
}

// Reads what was typed: anything with a digit in it is a postal code (US
// ZIPs, UK and Canadian codes); otherwise a town, with its state after the
// last comma when one is written, like "Austin, Texas".
fun typedPlace(text: String): TypedPlace? {
    val words = text.trim().replace(Regex("\\s+"), " ")
    if (words.isEmpty()) return null
    if (words.any { it.isDigit() }) return TypedPlace(code = words.uppercase())
    val comma = words.lastIndexOf(',')
    if (comma < 0) return TypedPlace(name = words)
    val name = words.substring(0, comma).trim().trimEnd(',').trim()
    val state = words.substring(comma + 1).trim()
    return when {
        name.isEmpty() -> TypedPlace(name = state)
        state.isEmpty() -> TypedPlace(name = name)
        else -> TypedPlace(name = name, state = state)
    }
}

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

// Finds places: on the server when it looks them up, otherwise by the
// phone's place service. Only one is asked for any lookup, so with an Octo
// server that lists octoPlaces nothing goes to the phone's service.
class PlaceFinder(
    private val server: () -> PlaceService?,
    private val phone: () -> PlaceService?,
) {
    fun source(): PlaceSource = when {
        server() != null -> PlaceSource.Server
        phone() != null -> PlaceSource.Phone
        else -> PlaceSource.None
    }

    suspend fun typed(text: String, country: String): PlaceAnswer {
        val asked = typedPlace(text) ?: return PlaceAnswer.NotFound(source())
        val fromServer = server()
        if (fromServer != null) {
            return try {
                fromServer.typed(asked, country)?.let { PlaceAnswer.Found(it) } ?: PlaceAnswer.NotFound(PlaceSource.Server)
            } catch (e: CancellationException) {
                throw e
            } catch (e: Exception) {
                PlaceAnswer.ServerDown
            }
        }
        val fromPhone = phone() ?: return PlaceAnswer.NoLookup
        return runCatchingPlace { fromPhone.typed(asked, country) }?.let { PlaceAnswer.Found(it) } ?: PlaceAnswer.NotFound(PlaceSource.Phone)
    }

    // A position already rounded, named by its town, state and country when
    // they can be had; when they cannot, it is searched by its radius alone.
    suspend fun around(latitude: Double, longitude: Double): PlaceAnswer {
        val service = server() ?: phone()
        val named = service?.let { runCatchingPlace { it.around(latitude, longitude) } }
        return PlaceAnswer.Found(named ?: LivePlace(latitude, longitude, "Your location"))
    }

    private suspend fun runCatchingPlace(call: suspend () -> LivePlace?): LivePlace? = try {
        call()
    } catch (e: CancellationException) {
        throw e
    } catch (e: Exception) {
        null
    }
}

// To two decimals, about a kilometer.
fun roundedPlace(value: Double): Double = Math.round(value * 100) / 100.0

// Why a place could not be used, in words; null when it was found.
fun placeProblemLine(answer: PlaceAnswer, typed: Boolean): String? = when (answer) {
    is PlaceAnswer.Found -> null
    PlaceAnswer.NoFix -> "The phone could not tell where it is. Check that location is on, or type a place instead."
    is PlaceAnswer.NotFound -> when {
        answer.by == PlaceSource.Server -> "Your Octo server does not know that place. Try a postal code or a nearby town."
        typed -> "No place found by that name. Try a ZIP or postal code."
        else -> "No place found here."
    }
    PlaceAnswer.ServerDown -> "Your Octo server did not answer. Try again in a moment."
    PlaceAnswer.NoLookup -> "This phone can't look up places by name. Use your location instead."
}
