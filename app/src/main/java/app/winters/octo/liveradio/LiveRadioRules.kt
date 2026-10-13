package app.winters.octo.liveradio

import app.winters.octo.discovery.Station
import kotlin.math.roundToInt

// The countries whose people measure road distances in miles.
private val MilesCountries = setOf("US", "GB", "LR", "MM")

// Whether distances are shown in miles for a locale's country, km otherwise.
fun usesMiles(countryCode: String): Boolean = countryCode.trim().uppercase() in MilesCountries

// The radius choices in the listener's units, and the one that counts as
// usual.
fun radiusChoices(miles: Boolean): List<Int> = if (miles) LiveRadiusMiles else LiveRadiusKm

// A radius choice by its place in the list, kept in range.
fun radiusAt(miles: Boolean, index: Int): Int {
    val choices = radiusChoices(miles)
    return choices[index.coerceIn(0, choices.lastIndex)]
}

fun radiusMeters(miles: Boolean, index: Int): Double {
    val radius = radiusAt(miles, index)
    return if (miles) radius * MILE_METERS else radius * 1000.0
}

// A radius as a chip shows it, like "25 mi" or "40 km".
fun radiusLabel(miles: Boolean, radius: Int): String = if (miles) "$radius mi" else "$radius km"

// The words for no stations inside the circle.
fun noStationsLine(miles: Boolean, radius: Int): String =
    "No stations within $radius ${if (miles) "miles" else "km"}. Try a wider circle."

// How far a station is, like "3.2 mi" or "12 km"; or, when the catalog has
// no place for it, the state or country it is filed under, like "In Texas".
fun whereLine(station: LiveStation, miles: Boolean): String {
    val meters = station.distanceMeters
    if (meters != null) {
        val amount = if (miles) meters / MILE_METERS else meters / 1000.0
        val unit = if (miles) "mi" else "km"
        return when {
            amount < 0.1 -> "Right here"
            amount < 10 -> "${(amount * 10).roundToInt() / 10.0} $unit"
            else -> "${amount.roundToInt()} $unit"
        }
    }
    val area = station.state.ifBlank { station.country }
    return if (area.isBlank()) "" else "In $area"
}

// The stream's kind and size, like "MP3 128 kbps".
fun streamLine(station: LiveStation): String = listOfNotNull(
    station.codec.trim().uppercase().takeIf { it.isNotEmpty() && it != "UNKNOWN" },
    station.bitrate.takeIf { it > 0 }?.let { "$it kbps" },
).joinToString(" ")

// A station's second line: where it is, then its first few tags.
fun detailLine(station: LiveStation, miles: Boolean): String =
    listOf(whereLine(station, miles), station.tags.take(3).joinToString(", ")).filter { it.isNotBlank() }.joinToString(" · ")

// The audio kinds the player opens, by the catalog's codec names, and the
// decoder each needs on the phone. Ogg streams carry Vorbis as a rule.
private val CodecDecoders = mapOf(
    "MP3" to "audio/mpeg",
    "AAC" to "audio/mp4a-latm",
    "AAC+" to "audio/mp4a-latm",
    "OGG" to "audio/vorbis",
    "OPUS" to "audio/opus",
    "FLAC" to "audio/flac",
)

// Whether this phone can play a station: an HLS stream always can, any
// other only when each kind it lists is one the player opens and the phone
// has a decoder for. A station with no kind given is tried; one that also
// carries video, or a kind the player cannot open, is not.
fun livePlayable(station: LiveStation, decoders: Set<String>): Boolean {
    if (station.hls) return true
    val kinds = station.codec.split(',').map { it.trim().uppercase() }.filter { it.isNotEmpty() && it != "UNKNOWN" }
    if (kinds.isEmpty()) return true
    return kinds.all { kind -> CodecDecoders[kind]?.let { it in decoders } == true }
}

// What a station's menu offers: keeping it on this phone or letting it go,
// and, when `addable` (an admin, and a station the server lacks), adding it
// to the server for everyone.
enum class StationAction(val label: String) {
    Keep("Keep"),
    Remove("Remove"),
    AddToServer("Add to your server"),
}

fun stationActions(kept: Boolean, addable: Boolean): List<StationAction> = buildList {
    add(if (kept) StationAction.Remove else StationAction.Keep)
    if (addable) add(StationAction.AddToServer)
}

// One card on the Live radio shelf.
sealed interface LiveShelfEntry {
    val key: String

    // A station added to the server; `kept` is the same stream kept on this
    // phone, which says whether it streams as HLS.
    data class Server(val station: Station, val kept: LiveStation? = null) : LiveShelfEntry {
        override val key: String get() = "server:${station.id}"
        val hls: Boolean get() = kept?.hls == true
    }

    // A station kept on this phone.
    data class Kept(val station: LiveStation) : LiveShelfEntry {
        override val key: String get() = "kept:${station.uuid}"
    }
}

// The Live radio shelf: the server's stations first, then the ones kept on
// this phone, each stream once (by liveStreamKey). A server station that is
// also kept carries what the kept one knows.
fun liveShelf(server: List<Station>, kept: List<LiveStation>): List<LiveShelfEntry> {
    val seen = HashSet<String>()
    val keptByStream = kept.associateBy { liveStreamKey(it.streamUrl) }
    val fromServer = server.filter { it.streamUrl != null && seen.add(liveStreamKey(it.streamUrl)) }
        .map { LiveShelfEntry.Server(it, keptByStream[liveStreamKey(it.streamUrl!!)]) }
    val fromPhone = kept.filter { seen.add(liveStreamKey(it.streamUrl)) }.map { LiveShelfEntry.Kept(it) }
    return fromServer + fromPhone
}

// The stations kept after a backup is restored: those kept now, then the
// backup's that are not, in the backup's order.
fun restoredKept(current: KeptStations, backup: List<LiveStation>): KeptStations {
    val have = current.stations.mapTo(HashSet()) { it.uuid }
    return KeptStations(current.stations + backup.filter { have.add(it.uuid) }.map { it.copy(distanceMeters = null) })
}

// A place as the page names it: its town (or what was typed) and its state,
// each once.
fun placeLabel(town: String?, state: String?, fallback: String): String {
    val parts = listOfNotNull(town?.trim()?.takeIf { it.isNotEmpty() }, state?.trim()?.takeIf { it.isNotEmpty() }).distinct()
    return if (parts.isEmpty()) fallback else parts.joinToString(", ")
}

// The words under the list for stations this phone cannot play.
fun hiddenLine(count: Int): String? = when {
    count <= 0 -> null
    count == 1 -> "1 station is left out because this phone cannot play its stream."
    else -> "$count stations are left out because this phone cannot play their streams."
}
