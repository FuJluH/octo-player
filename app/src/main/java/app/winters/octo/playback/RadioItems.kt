package app.winters.octo.playback

import androidx.media3.common.C
import androidx.media3.common.MediaItem
import androidx.media3.common.MediaMetadata
import androidx.media3.common.MimeTypes
import java.net.URLDecoder
import java.net.URLEncoder

// An internet radio station in the queue. Its id carries everything needed
// to play it, so nothing about it is stored anywhere else:
//
//   radio:<url-encoded stream address>:<url-encoded station name>[:hls]
//
// Encoding turns every ':' into %3A, so the parts split cleanly. The name
// may be empty; ":hls" marks a stream sent as HLS whose address does not
// say so. The player opens the address as it is; a live stream has no
// length, so it never crossfades and never counts as a play.
const val RADIO_PREFIX = "radio:"
private const val HLS_MARK = "hls"

// What a station shows while its stream names no song.
const val RADIO_ARTIST = "Radio"

fun isRadio(id: String) = id.startsWith(RADIO_PREFIX)

fun radioId(streamUrl: String, name: String = "", hls: Boolean = false): String =
    RADIO_PREFIX + encode(streamUrl.trim()) + ":" + encode(name.trim()) + if (hls) ":$HLS_MARK" else ""

// Whether a station's id says it streams as HLS.
fun radioIsHls(id: String): Boolean = isRadio(id) && id.removePrefix(RADIO_PREFIX).split(':').getOrNull(2) == HLS_MARK

// The station's stream address and name, or null when the id is not one.
fun radioOf(id: String): Pair<String, String>? {
    if (!isRadio(id)) return null
    val parts = id.removePrefix(RADIO_PREFIX).split(':')
    val stream = parts.getOrNull(0)?.let(::decode)?.takeIf(String::isNotBlank) ?: return null
    return stream to (parts.getOrNull(1)?.let(::decode).orEmpty())
}

// A station, ready to play.
internal fun radioItem(id: String): MediaItem? {
    val (stream, name) = radioOf(id) ?: return null
    return MediaItem.Builder()
        .setMediaId(id)
        .setUri(stream)
        .apply { if (radioIsHls(id)) setMimeType(MimeTypes.APPLICATION_M3U8) }
        .setMediaMetadata(
            MediaMetadata.Builder()
                .setTitle(name.ifEmpty { stream })
                .setArtist(RADIO_ARTIST)
                .setIsPlayable(true)
                .setIsBrowsable(false)
                .setMediaType(MediaMetadata.MEDIA_TYPE_RADIO_STATION)
                .build(),
        )
        .build()
}

// The two lines a station shows: the song its stream names (ICY
// StreamTitle) over the station's name, or, while it names none, the
// station's name over "Radio". A title that is only the station's own name,
// or only punctuation, names no song.
data class RadioLines(val title: String, val artist: String)

fun radioLines(streamTitle: String?, stationName: String, streamUrl: String = ""): RadioLines {
    val station = stationName.trim()
    val song = streamTitle?.trim()?.take(RADIO_TITLE_MAX)?.trim()
        ?.takeIf { title -> title.any { it.isLetterOrDigit() } && !title.equals(station, ignoreCase = true) }
    return if (song == null) {
        RadioLines(station.ifEmpty { streamUrl }, RADIO_ARTIST)
    } else {
        RadioLines(song, station.ifEmpty { RADIO_ARTIST })
    }
}

private const val RADIO_TITLE_MAX = 200

// A station in the queue with its two lines as the stream names them now,
// or null when they are already shown.
internal fun MediaItem.withRadioLines(streamTitle: String?): MediaItem? {
    val (stream, name) = radioOf(mediaId) ?: return null
    val lines = radioLines(streamTitle, name, stream)
    val meta = mediaMetadata
    if (meta.title?.toString() == lines.title && meta.artist?.toString() == lines.artist) return null
    return buildUpon().setMediaMetadata(meta.buildUpon().setTitle(lines.title).setArtist(lines.artist).build()).build()
}

// How long a station waits before opening its stream again after it
// failed, by how many times in a row it has: a second, then two, four and
// eight. A stream that will never open (refused, gone, not audio) is not
// tried again.
fun radioRetryDelayMs(errorCount: Int, lasting: Boolean): Long =
    if (lasting || errorCount > RADIO_RETRIES) C.TIME_UNSET else 1_000L shl (errorCount - 1).coerceIn(0, 3)

// How many times in a row a station's stream is opened again before the
// player gives up on it.
const val RADIO_RETRIES = 4

private fun encode(text: String): String = URLEncoder.encode(text, Charsets.UTF_8.name())

private fun decode(text: String): String = runCatching { URLDecoder.decode(text, Charsets.UTF_8.name()) }.getOrDefault("")
