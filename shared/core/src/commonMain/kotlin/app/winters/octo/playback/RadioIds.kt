package app.winters.octo.playback

import java.net.URLDecoder
import java.net.URLEncoder

// An internet radio station in the queue. Its id carries everything needed
// to play it, so nothing about it is stored anywhere else:
//
//   radio:<url-encoded stream address>:<url-encoded station name>[:hls][:<details>]
//
// Encoding turns every ':' into %3A, so the parts split cleanly. The name
// may be empty; ":hls" marks a stream sent as HLS whose address does not
// say so (the part is empty when it is not, and details follow). Details
// are what the player shows about the station (logo, codec, place,
// website), url-encoded as `key=value&...`; an id without them still
// plays. The player opens the address as it is; a live stream has no
// length, so it never crossfades and never counts as a play.
const val RADIO_PREFIX = "radio:"
private const val HLS_MARK = "hls"

fun isRadio(id: String) = id.startsWith(RADIO_PREFIX)

fun radioId(streamUrl: String, name: String = "", hls: Boolean = false, details: RadioDetails = RadioDetails()): String {
    val base = RADIO_PREFIX + encode(streamUrl.trim()) + ":" + encode(name.trim())
    val shown = details.encoded()
    return when {
        shown.isNotEmpty() -> base + ":" + (if (hls) HLS_MARK else "") + ":" + encode(shown)
        hls -> "$base:$HLS_MARK"
        else -> base
    }
}

// What the player shows about a station besides its name: its logo (an
// address, or a server cover art id in `coverArt`), how it streams, where it
// is, its website, its genres and its Radio Browser id.
data class RadioDetails(
    val logo: String = "",
    val coverArt: String = "",
    val codec: String = "",
    val bitrate: Int = 0,
    val country: String = "",
    val countryCode: String = "",
    val state: String = "",
    val homepage: String = "",
    val tags: List<String> = emptyList(),
    val uuid: String = "",
) {
    internal fun encoded(): String = listOf(
        "logo" to logo,
        "cover" to coverArt,
        "codec" to codec,
        "kbps" to if (bitrate > 0) bitrate.toString() else "",
        "country" to country,
        "cc" to countryCode,
        "state" to state,
        "home" to homepage,
        "tags" to tags.joinToString(","),
        "uuid" to uuid,
    ).filter { it.second.isNotBlank() }.joinToString("&") { (key, value) -> key + "=" + encode(value.trim()) }

    internal companion object {
        fun decoded(text: String): RadioDetails {
            val values = text.split('&').mapNotNull { pair ->
                val key = pair.substringBefore('=', "")
                if (key.isEmpty()) null else key to decode(pair.substringAfter('='))
            }.toMap()
            return RadioDetails(
                logo = values["logo"].orEmpty(),
                coverArt = values["cover"].orEmpty(),
                codec = values["codec"].orEmpty(),
                bitrate = values["kbps"]?.toIntOrNull() ?: 0,
                country = values["country"].orEmpty(),
                countryCode = values["cc"].orEmpty(),
                state = values["state"].orEmpty(),
                homepage = values["home"].orEmpty(),
                tags = values["tags"].orEmpty().split(',').map(String::trim).filter(String::isNotEmpty),
                uuid = values["uuid"].orEmpty(),
            )
        }
    }
}

// What a station's id says about it beyond its address and name; empty
// details when it says nothing more.
fun radioDetailsOf(id: String): RadioDetails {
    if (!isRadio(id)) return RadioDetails()
    val part = id.removePrefix(RADIO_PREFIX).split(':').getOrNull(3) ?: return RadioDetails()
    return RadioDetails.decoded(decode(part))
}

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
