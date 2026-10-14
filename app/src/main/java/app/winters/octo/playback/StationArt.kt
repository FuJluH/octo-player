package app.winters.octo.playback

import app.winters.octo.catalog.ArtworkRef
import app.winters.octo.covers.CoverSpec
import app.winters.octo.covers.coverPalette
import app.winters.octo.liveradio.LIVE_RADIO_LINE
import app.winters.octo.liveradio.liveStreamKey
import java.net.URLDecoder
import java.net.URLEncoder

// A live station's cover, as one artwork reference, best first: the cover
// of the song on air as Octo has it (`cover`, an artwork reference), the
// artwork the station sends with the song, then the station's own pictures
// (its logo, a cover kept on the server), each tried in turn. Under them
// all, the cover drawn from the station's name shows at once and stays
// whenever none of them can be had.
//
//   station-art:<name>|<key>|<cover>|<artwork>|<logo>|<logo>...
//
// Each part is url-encoded, so none holds a "|". `key` tells stations
// apart for the drawn cover's colours. A logo is a web address or an
// artwork reference (a server cover).
data class StationArt(
    val name: String,
    val key: String,
    val artwork: String = "",
    val logos: List<String> = emptyList(),
    val cover: String = "",
) {
    fun encode(): String =
        STATION_ART_PREFIX + (listOf(name, key, cover, artwork) + logos.filter(String::isNotBlank)).joinToString("|") { encode(it) }

    // Every picture to try, best first.
    val pictures: List<String> get() = listOf(cover, artwork).filter(String::isNotBlank) + logos

    // What the drawn cover shows: the station's name over "Live radio".
    fun drawnSpec(): CoverSpec = CoverSpec(key, name, LIVE_RADIO_LINE, null, coverPalette(emptyList(), key))
}

const val STATION_ART_PREFIX = "station-art:"

fun stationArtOf(ref: String?): StationArt? {
    if (ref == null || !ref.startsWith(STATION_ART_PREFIX)) return null
    val parts = ref.removePrefix(STATION_ART_PREFIX).split('|').map(::decode)
    if (parts.size < 4) return null
    return StationArt(parts[0], parts[1], parts[3], parts.drop(4).filter(String::isNotBlank), parts[2])
}

// The cover a station's id shows, with `artwork` from what it has on air.
// A server cover id in its details becomes a cover on that server
// (`sourceId`), tried after the logo.
fun stationArt(id: String, artwork: String = "", sourceId: String? = null): StationArt? {
    val (stream, name) = radioOf(id) ?: return null
    val details = radioDetailsOf(id)
    val server = details.coverArt.takeIf { it.isNotBlank() && sourceId != null }?.let { ArtworkRef.Server(sourceId!!, it).encode() }
    return StationArt(name.ifBlank { stream }, liveStreamKey(stream), artwork.trim(), listOfNotNull(details.logo.trim().takeIf(String::isNotEmpty), server))
}

// Whether a picture in a station's cover is a web address, fetched as it
// is, rather than an artwork reference.
fun isWebPicture(picture: String): Boolean =
    picture.startsWith("https://", ignoreCase = true) || picture.startsWith("http://", ignoreCase = true)

private fun encode(text: String): String = URLEncoder.encode(text, Charsets.UTF_8.name())

private fun decode(text: String): String = runCatching { URLDecoder.decode(text, Charsets.UTF_8.name()) }.getOrDefault("")
