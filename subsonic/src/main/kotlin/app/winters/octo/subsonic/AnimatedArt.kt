package app.winters.octo.subsonic

import kotlinx.serialization.Serializable
import okhttp3.HttpUrl
import okhttp3.HttpUrl.Companion.toHttpUrlOrNull

// The OpenSubsonic extension an Octo server lists while its owner has
// animated art on: Apple Music's animated album covers, through
// getAnimatedArt and an `animatedArt` field on getAlbum.
const val OCTO_ANIMATED_ART = "octoAnimatedArt"

// One looping clip of an album's animated art: its HLS playlist, a still
// of its first frame, the color it sits on ("rrggbb"), and its size. The
// addresses are either whole (Apple's own) or relative to the server, such
// as "animated/<token>/square.m3u8" when the server passes the clips on
// itself; `resolvedOn` makes them whole.
@Serializable
data class AnimatedClip(
    val video: String = "",
    val poster: String? = null,
    val color: String? = null,
    val width: Int = 0,
    val height: Int = 0,
) {
    // The color as 0xRRGGBB, or null when the server named none or it is
    // not six hex digits.
    val colorRgb: Int?
        get() = color?.trim()?.removePrefix("#")?.takeIf { it.length == 6 }?.toIntOrNull(16)

    // The clip with whole addresses, relative ones put under `base` (the
    // server's address, with any path it has). Null when the video address
    // is not one a player can open.
    fun resolvedOn(base: HttpUrl): AnimatedClip? {
        val videoUrl = resolveArtAddress(video, base) ?: return null
        return copy(video = videoUrl.toString(), poster = poster?.let { resolveArtAddress(it, base)?.toString() })
    }
}

// An album's animated art: the square loop that plays in place of the
// cover, and the tall one that fills the player. Either can be missing.
@Serializable
data class AnimatedArt(
    val square: AnimatedClip? = null,
    val tall: AnimatedClip? = null,
) {
    val isEmpty: Boolean get() = square?.video.isNullOrBlank() && tall?.video.isNullOrBlank()

    // Both clips with whole addresses; a clip whose address cannot be made
    // whole is dropped.
    fun resolvedOn(base: HttpUrl): AnimatedArt = AnimatedArt(square?.resolvedOn(base), tall?.resolvedOn(base))
}

// What the server said about an album's animated art.
sealed interface AnimatedArtAnswer {
    // The album has animated art.
    data class Found(val art: AnimatedArt) : AnimatedArtAnswer

    // The album has none, or the server's owner hid it.
    data object None : AnimatedArtAnswer

    // The server has animated art off.
    data object Off : AnimatedArtAnswer

    // The server could not say just now (Apple Music did not answer, or the
    // server was out of reach). Worth asking again later, never worth keeping.
    data object NotNow : AnimatedArtAnswer
}

// What the server's error says: off, or Apple Music out of reach (both
// are code 0), or the album unknown.
internal fun animatedArtAnswerFor(error: SubsonicException): AnimatedArtAnswer = when (error) {
    is SubsonicException.Server ->
        when {
            error.code == 0 && error.message.orEmpty().contains("is off", ignoreCase = true) -> AnimatedArtAnswer.Off
            error.code == 0 -> AnimatedArtAnswer.NotNow
            else -> AnimatedArtAnswer.None
        }
    is SubsonicException.NotFound -> AnimatedArtAnswer.None
    else -> AnimatedArtAnswer.NotNow
}

// A whole address for one the server gave: as it is when it is already
// whole, else under the server's address. Only http and https.
internal fun resolveArtAddress(address: String, base: HttpUrl): HttpUrl? {
    val trimmed = address.trim()
    if (trimmed.isEmpty()) return null
    trimmed.toHttpUrlOrNull()?.let { return it }
    if (trimmed.contains("://")) return null
    val (path, query) = trimmed.removePrefix("/").split('?', limit = 2).let { it[0] to it.getOrNull(1) }
    // Added after the base's own path, ending in a slash or not.
    return base.newBuilder()
        .query(null)
        .fragment(null)
        .addPathSegments(path)
        .encodedQuery(query)
        .build()
}
