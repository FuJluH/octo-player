package app.winters.octo.desktop.liveradio

import app.winters.octo.liveradio.LivePlace
import app.winters.octo.liveradio.LiveRadiusKm
import app.winters.octo.liveradio.LiveRadiusMiles
import app.winters.octo.liveradio.LiveStation
import app.winters.octo.liveradio.MILE_METERS
import app.winters.octo.liveradio.liveStreamKey
import app.winters.octo.liveradio.located
import app.winters.octo.liveradio.parseWhere
import app.winters.octo.desktop.library.CoverOrder
import app.winters.octo.playback.radioDetailsOf
import app.winters.octo.playback.radioId
import app.winters.octo.playback.radioOf
import app.winters.octo.subsonic.Place
import app.winters.octo.subsonic.RadioStation
import app.winters.octo.subsonic.Song
import java.util.Locale
import kotlin.math.roundToInt

// What the Where field asks for: a postal code, or a city's name with its
// state when one was typed after a comma, in an ISO country.
data class WhereAsked(val code: String? = null, val name: String? = null, val state: String? = null, val country: String)

// The Where field's words as a place to look up, or null when nothing was
// typed, read as both apps read them (parseWhere): the words with a digit
// are a postal code ("55401", "SW1A 1AA", the 78701 of "Austin, TX 78701"),
// the rest a city with its state after the first comma.
fun whereOf(text: String, country: String): WhereAsked? {
    val parts = parseWhere(text) ?: return null
    return WhereAsked(code = parts.code, name = parts.name, state = parts.state, country = country.trim().uppercase())
}

// How a place lookup went: where it is, or why it could not be found.
sealed interface PlaceAnswer {
    data class Found(val place: LivePlace) : PlaceAnswer
    data class Problem(val words: String) : PlaceAnswer
}

const val UNKNOWN_PLACE = "Your server does not know that place. Try a postal code or a nearby city."
const val NO_POSTAL_LOOKUP = "Your server cannot look up postal codes. Type a city and its state instead, like Austin, Texas."

// Where the asked place is. With `lookup` (a server that lists octoPlaces)
// the server finds it; without one, a city goes to the catalog as it is,
// by its state (the city itself when no state was typed) and country, with
// no coordinates, and a postal code cannot be used.
suspend fun resolvePlace(asked: WhereAsked, lookup: (suspend (WhereAsked) -> Place?)?): PlaceAnswer {
    if (lookup != null) {
        val place = lookup(asked) ?: return PlaceAnswer.Problem(UNKNOWN_PLACE)
        val label = listOf(place.name, place.state).filter { it.isNotBlank() }.joinToString(", ").ifEmpty { asked.code ?: asked.name.orEmpty() }
        return PlaceAnswer.Found(
            LivePlace(place.latitude, place.longitude, label, state = place.state, countryCode = place.country.ifBlank { asked.country }.uppercase()),
        )
    }
    val name = asked.name ?: return PlaceAnswer.Problem(NO_POSTAL_LOOKUP)
    val label = listOfNotNull(name, asked.state).joinToString(", ")
    return PlaceAnswer.Found(LivePlace(0.0, 0.0, label, state = asked.state ?: name, countryCode = asked.country))
}

// The countries that measure roads in miles.
private val MileCountries = setOf("US", "GB", "LR", "MM")

// Whether distances read in miles for a country (an ISO code).
fun usesMiles(country: String): Boolean = country.trim().uppercase() in MileCountries

// This computer's own country, as an ISO code; the United States when the
// system names none.
fun systemCountry(locale: Locale = Locale.getDefault()): String = locale.country.trim().uppercase().ifEmpty { "US" }

// The radius choices, in miles or kilometers.
fun radiusChoices(miles: Boolean): List<Int> = if (miles) LiveRadiusMiles else LiveRadiusKm

// A radius choice, by its place in the list, in meters.
fun radiusMeters(index: Int, miles: Boolean): Double {
    val choices = radiusChoices(miles)
    val value = choices[index.coerceIn(choices.indices)]
    return if (miles) value * MILE_METERS else value * 1000.0
}

// A radius choice in words: "25 mi", "40 km".
fun radiusLabel(value: Int, miles: Boolean): String = if (miles) "$value mi" else "$value km"

// How far a station is: "3 mi", "12 km", "Under 1 mi".
fun distanceText(meters: Double, miles: Boolean): String {
    val amount = if (miles) meters / MILE_METERS else meters / 1000.0
    val unit = if (miles) "mi" else "km"
    return if (amount < 1) "Under 1 $unit" else "${amount.roundToInt()} $unit"
}

// Where a station is, in a row: how far, or "In <state>" when the catalog
// files it under the state without placing it.
fun whereText(station: LiveStation, miles: Boolean): String? =
    station.distanceMeters?.let { distanceText(it, miles) }
        ?: station.state.ifBlank { station.country }.takeIf { it.isNotBlank() }?.let { "In $it" }

// A station's sound: "MP3 128 kbps", "AAC+", "HLS".
fun soundText(station: LiveStation): String? {
    val codec = station.codec.trim().uppercase().takeUnless { it.isEmpty() || it == "UNKNOWN" } ?: if (station.hls) "HLS" else null
    val rate = station.bitrate.takeIf { it > 0 }?.let { "$it kbps" }
    return listOfNotNull(codec, rate).joinToString(" ").ifEmpty { null }
}

// A station's first few tags, for its row.
fun tagsText(station: LiveStation): String? = station.tags.take(3).joinToString(", ").ifEmpty { null }

// What the desktop plays: these codecs, and HLS streams of any.
val LivePlayableCodecs = setOf("MP3", "AAC", "AAC+", "OGG", "OPUS", "FLAC")

// A station that lists several kinds ("MP3,AAC") plays when every one of
// them does; one with no kind given, or only UNKNOWN, is left out.
fun livePlayable(station: LiveStation): Boolean {
    if (station.hls) return true
    val kinds = station.codec.split(',').map { it.trim().uppercase() }.filter { it.isNotEmpty() }
    return kinds.isNotEmpty() && kinds.all { it in LivePlayableCodecs }
}

// The line under the stations when some were left out as unplayable.
fun hiddenStationsLine(count: Int): String? = when {
    count <= 0 -> null
    count == 1 -> "1 station is left out because Octo can't play its stream on this computer."
    else -> "$count stations are left out because Octo can't play their streams on this computer."
}

const val NO_STATIONS_AROUND = "No stations within %s. Try a wider circle."
const val CATALOG_DOWN = "The radio catalog is not answering right now."

// The page's line when nothing was found: within the radius, or in the
// state for a place without coordinates.
fun nothingFound(place: LivePlace, radius: Int, miles: Boolean): String =
    if (place.located) {
        NO_STATIONS_AROUND.format(if (miles) "$radius miles" else "$radius km")
    } else {
        "No stations listed in ${place.state.ifBlank { place.label }}. Try a nearby city with its state."
    }

// A live station as a song for the player: its id carries the stream, the
// name and what the player shows about it, as on the phone.
fun liveSong(id: String): Song {
    val (stream, name) = radioOf(id) ?: return Song(id = id, artist = LIVE_RADIO)
    return Song(id = id, title = name.ifBlank { stream }, artist = LIVE_RADIO, coverArt = radioDetailsOf(id).coverArt.ifBlank { null })
}

fun liveSong(name: String, streamUrl: String): Song = liveSong(radioId(streamUrl, name))

// What a station's drawn cover is made from, the same on every card and in
// the player: its name, "Live radio", and its colors from its stream.
fun liveCoverOrder(name: String, streamUrl: String): CoverOrder =
    CoverOrder("live:${streamKey(streamUrl)}", name.ifBlank { streamUrl }, LIVE_RADIO, null, emptyList())

const val LIVE_RADIO = "Live radio"
const val LIVE_RADIO_NEAR = "Live radio near you"
const val FIND_STATIONS_NEAR = "Find stations near you"

// A stream address as stations are matched by, the same in both apps.
fun streamKey(url: String): String = liveStreamKey(url)

// One card on Home's Live radio shelf: a station added to the server, or
// one kept on this computer (`kept`), or both when they stream the same.
data class ShelfStation(
    val name: String,
    val streamUrl: String,
    val logo: String = "",
    val coverArt: String? = null,
    val serverId: String? = null,
    val kept: LiveStation? = null,
    val homepage: String = "",
)

// Whether a station from the server is one of Octo's own (songs it lines
// up, with its id as its cover) rather than a stream added to it.
fun isOctoStation(station: RadioStation, isOcto: Boolean): Boolean = isOcto && station.coverArt == station.id

// The streams added to the server, of all its stations.
fun liveStationsOf(stations: List<RadioStation>, isOcto: Boolean): List<RadioStation> =
    stations.filter { !isOctoStation(it, isOcto) && it.streamUrl.isNotBlank() }

// The Live radio shelf: the server's streams, then the stations kept here,
// each stream once. A kept station the server also has lends it its logo.
fun liveShelf(server: List<RadioStation>, kept: List<LiveStation>): List<ShelfStation> {
    val byStream = kept.associateBy { streamKey(it.streamUrl) }
    val seen = HashSet<String>()
    val fromServer = server.filter { it.streamUrl.isNotBlank() && seen.add(streamKey(it.streamUrl)) }.map { station ->
        val mine = byStream[streamKey(station.streamUrl)]
        ShelfStation(station.name.ifBlank { station.streamUrl }, station.streamUrl, mine?.favicon.orEmpty(), station.coverArt, station.id, mine, station.homePageUrl.orEmpty())
    }
    val fromHere = kept.filter { seen.add(streamKey(it.streamUrl)) }.map { ShelfStation(it.name, it.streamUrl, it.favicon, kept = it) }
    return fromServer + fromHere
}

// What a live station's menu offers.
enum class LiveAction { Play, Keep, Remove, AddToServer }

// A station's menu: play it, keep it here or take it off, and for an admin,
// add it to the server when the server does not have it yet.
fun liveActions(kept: Boolean, admin: Boolean, onServer: Boolean): List<LiveAction> = listOfNotNull(
    LiveAction.Play,
    if (kept) LiveAction.Remove else LiveAction.Keep,
    LiveAction.AddToServer.takeIf { admin && !onServer },
)

// A menu row's words.
fun liveActionLabel(action: LiveAction): String = when (action) {
    LiveAction.Play -> "Play"
    LiveAction.Keep -> "Keep"
    LiveAction.Remove -> "Remove"
    LiveAction.AddToServer -> "Add to your server"
}
