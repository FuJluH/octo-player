package app.winters.octo.playback

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

private fun encode(text: String): String = URLEncoder.encode(text, Charsets.UTF_8.name())

private fun decode(text: String): String = runCatching { URLDecoder.decode(text, Charsets.UTF_8.name()) }.getOrDefault("")
