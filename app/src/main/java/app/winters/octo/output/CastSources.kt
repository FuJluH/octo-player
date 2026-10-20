package app.winters.octo.output

import app.winters.octo.playback.StreamRef
import app.winters.octo.playback.StreamRequest
import app.winters.octo.playback.isOpenedFile
import app.winters.octo.playback.parseStreamUri
import app.winters.octo.playback.radioOf

// Where a song in the queue plays from, as another device sees it.
sealed interface CastSource {
    // A server song: the device fetches it from the server, by an address
    // signed for it.
    data class Server(val ref: StreamRef) : CastSource

    // A file on the phone (a song in the library or a download): the phone
    // serves it to the device itself.
    data class PhoneFile(val uri: String) : CastSource

    // A web address the device opens as it is: a radio station, which never
    // ends, or anything else already on the web.
    data class Web(val url: String, val live: Boolean) : CastSource

    // Cannot play on another device.
    data class Skipped(val why: SkipReason) : CastSource
}

enum class SkipReason {
    // Opened from another app: Octo may only read it for as long as that
    // app allows, and only for itself.
    OpenedFile,

    // Nowhere a device could fetch it from.
    Unservable,
}

// Sorts a queue song by where a device would fetch it from, by its id and
// the address the queue holds for it.
fun castSourceOf(mediaId: String, uri: String?): CastSource {
    if (isOpenedFile(mediaId)) return CastSource.Skipped(SkipReason.OpenedFile)
    radioOf(mediaId)?.let { (stream, _) ->
        return if (isWeb(stream)) CastSource.Web(stream, live = true) else CastSource.Skipped(SkipReason.Unservable)
    }
    val address = uri?.takeIf { it.isNotBlank() } ?: return CastSource.Skipped(SkipReason.Unservable)
    parseStreamUri(address)?.let { return CastSource.Server(it) }
    return when {
        address.startsWith("content://") || address.startsWith("file://") -> CastSource.PhoneFile(address)
        address.startsWith("/") -> CastSource.PhoneFile("file://$address")
        isWeb(address) -> CastSource.Web(address, live = false)
        else -> CastSource.Skipped(SkipReason.Unservable)
    }
}

private fun isWeb(address: String) = address.startsWith("http://", ignoreCase = true) || address.startsWith("https://", ignoreCase = true)

// The types the Cast default receiver plays. ALAC inside MP4 is not one of
// them, but it cannot be told apart from AAC by type alone.
val CastAudioTypes = setOf(
    "audio/mpeg", "audio/mp3", "audio/mp4", "audio/x-m4a", "audio/m4a", "audio/aac",
    "audio/flac", "audio/x-flac", "audio/ogg", "audio/opus", "audio/wav", "audio/x-wav",
    "audio/wave", "audio/webm",
)

// A file's type from its name, for when nothing else says.
fun mimeFromName(name: String?): String? = when (name?.substringAfterLast('.', "")?.lowercase()) {
    "mp3" -> "audio/mpeg"
    "flac" -> "audio/flac"
    "m4a", "mp4", "m4b" -> "audio/mp4"
    "aac" -> "audio/aac"
    "ogg", "oga" -> "audio/ogg"
    "opus" -> "audio/opus"
    "wav" -> "audio/wav"
    "webm" -> "audio/webm"
    "aif", "aiff" -> "audio/aiff"
    "wma" -> "audio/x-ms-wma"
    "ape" -> "audio/x-ape"
    "wv" -> "audio/x-wavpack"
    "dsf" -> "audio/x-dsf"
    else -> null
}

// The ending a served address gets, for devices that go by a file's name.
fun extensionFor(mimeType: String): String = when (mimeType.lowercase()) {
    "audio/mpeg", "audio/mp3" -> "mp3"
    "audio/flac", "audio/x-flac" -> "flac"
    "audio/mp4", "audio/x-m4a", "audio/m4a" -> "m4a"
    "audio/aac" -> "aac"
    "audio/ogg" -> "ogg"
    "audio/opus" -> "opus"
    "audio/wav", "audio/x-wav", "audio/wave" -> "wav"
    "audio/webm" -> "webm"
    "image/jpeg" -> "jpg"
    "image/png" -> "png"
    else -> ""
}

// A server song as the device should get it: the file as it is when the
// device plays that type, otherwise an MP3 the server makes on the way,
// which every device plays.
fun requestForDevice(preferred: StreamRequest, originalType: String?, accepts: (String) -> Boolean): StreamRequest {
    val type = preferred.mimeType(originalType) ?: return preferred
    return if (accepts(type)) preferred else StreamRequest(DEVICE_MP3_KBPS)
}

// A server song once the server has said what it sends (`answered`, asked
// only for a file as it is): that type, or the listed one when it named
// none, and an MP3 made on the way when the device does not play it. A
// song asked for as it is can come as another file than listed.
fun deviceMediaFor(request: StreamRequest, listed: String?, answered: String?, accepts: (String) -> Boolean): Pair<StreamRequest, String?> {
    if (request.maxKbps != null) return request to request.mimeType(listed)
    val type = answered ?: listed
    return if (type == null || accepts(type)) request to type else StreamRequest(DEVICE_MP3_KBPS) to "audio/mpeg"
}

const val DEVICE_MP3_KBPS = 320
