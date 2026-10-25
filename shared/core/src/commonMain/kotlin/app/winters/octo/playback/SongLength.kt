package app.winters.octo.playback

import app.winters.octo.subsonic.Song
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.update
import kotlin.math.abs

// A length the player measured is believed from one second to a day.
// Anything outside that is a placeholder or a stream's nonsense.
private const val SHORTEST_MEASURED_MS = 1_000L
private const val LONGEST_MEASURED_MS = 24 * 60 * 60_000L

// How far a measured length may be from the listed one and still agree
// with it: listings carry whole seconds.
const val LENGTH_SLACK_MS = 1_000L

// The player's own measure of a song's length, when it is one to believe:
// a length a song can have, which the song has not already played past (a
// stream that only measured its first part).
fun measuredLengthMs(playerMs: Long?, positionMs: Long = 0): Long? {
    val ms = playerMs ?: return null
    if (ms < SHORTEST_MEASURED_MS || ms > LONGEST_MEASURED_MS) return null
    if (positionMs > ms + LENGTH_SLACK_MS) return null
    return ms
}

// How long the song playing is: the player's measure of the sound once it
// has a believable one, else the listed length (0 when that is unknown),
// stretched to where the song has played to when it has played past it.
// Everything timed by the song (the scrub bar, the time left, the end of
// the song, the scrobble) uses this.
fun playingLengthMs(listedMs: Long, playerMs: Long?, positionMs: Long = 0): Long {
    measuredLengthMs(playerMs, positionMs)?.let { return it }
    val listed = listedMs.coerceAtLeast(0)
    return if (listed > 0 && positionMs > listed) positionMs else listed
}

// What a song's listed length should be corrected to, or null when the
// listing is right: a believable measure more than a second away from the
// listed length, or any believable measure when none was listed.
fun correctedLengthMs(listedMs: Long, playerMs: Long?): Long? {
    val measured = measuredLengthMs(playerMs) ?: return null
    if (listedMs > 0 && abs(measured - listedMs) <= LENGTH_SLACK_MS) return null
    return measured
}

// The song listed with this length, in the whole seconds a listing has.
fun Song.withLengthMs(ms: Long): Song = copy(duration = ((ms + 500) / 1_000).toInt())

// How many songs' corrected lengths are kept at once: a listen through a
// big library learns more songs than a run has room for, and a length
// learned long ago is found again by playing the song.
private const val CORRECTED_KEPT = 4096

// The length learned, the first learned going when too many have gathered.
// A map's own order is the order things were put in it, so cutting its
// front drops what was learned first and keeps what plays now.
private fun learned(kept: Map<String, Long>, id: String, ms: Long): Map<String, Long> {
    val grown = kept + (id to ms)
    if (grown.size <= CORRECTED_KEPT) return grown
    val past = grown.size - CORRECTED_KEPT
    return buildMap(CORRECTED_KEPT) {
        var dropping = past
        for ((key, value) in grown) {
            if (dropping > 0) dropping-- else put(key, value)
        }
    }
}

// The real lengths of songs whose listing was wrong, learned by playing
// them, by song id. Rows, the queue and the next play of a song read their
// length through here, so a song shows the length of its sound everywhere
// once it has played. The last few thousand learned are kept.
class RealLengths {
    private val _corrected = MutableStateFlow<Map<String, Long>>(emptyMap())
    val corrected: StateFlow<Map<String, Long>> = _corrected

    // Takes the player's measure of a song listed at `listedMs`. Answers
    // the length its listing should have when it is wrong, else null.
    fun learn(id: String, listedMs: Long, playerMs: Long?): Long? {
        val ms = correctedLengthMs(listedMs, playerMs) ?: return null
        if (_corrected.value[id] != ms) _corrected.update { learned(it, id, ms) }
        return ms
    }

    // A song's length as it should show: the real one when its listing was
    // found wrong, else the listed one.
    fun lengthMs(id: String, listedMs: Long): Long = _corrected.value[id] ?: listedMs

    // The song with its real length, when its listing was found wrong.
    fun applyTo(song: Song): Song {
        val ms = _corrected.value[song.id] ?: return song
        val fixed = song.withLengthMs(ms)
        return if (fixed.duration == song.duration) song else fixed
    }
}
