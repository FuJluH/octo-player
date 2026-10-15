package app.winters.octo.animated

import androidx.compose.runtime.Composable
import androidx.compose.runtime.State
import androidx.compose.runtime.produceState
import app.winters.octo.subsonic.AnimatedArt
import app.winters.octo.subsonic.AnimatedArtAnswer
import kotlinx.coroutines.CompletableDeferred
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.CoroutineStart
import kotlinx.coroutines.Deferred
import kotlinx.coroutines.async
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow

// How many albums' answers are kept, newest use last.
private const val KEPT = 512

// How long an album the server could not answer for is left alone.
const val NOT_NOW_PAUSE_MS = 2 * 60_000L

// How long a server that has animated art off, or does not offer it, is
// left alone before it is asked again.
const val SERVER_OFF_PAUSE_MS = 30 * 60_000L

// How long a server that could not say whether it offers animated art is
// left alone.
const val SERVER_UNKNOWN_PAUSE_MS = 60_000L

// What is known of an album's animated art right now.
sealed interface KnownArt {
    data class Has(val art: AnimatedArt) : KnownArt

    data object HasNone : KnownArt

    data object Unknown : KnownArt
}

// The animated art of the albums asked about this session, for one server.
// Each album is asked once (two asks at the same time share one call), and
// its answer is kept, "none" too. An answer the server could not give just
// now is not kept, and the album is left alone for a while. Nothing is
// asked of a server that does not list octoAnimatedArt, or has it off.
class AnimatedArtBook(
    private val scope: CoroutineScope,
    // Whether the server lists octoAnimatedArt; null when it could not be asked.
    private val offered: suspend () -> Boolean?,
    private val ask: suspend (albumId: String) -> AnimatedArtAnswer,
    private val now: () -> Long = { System.currentTimeMillis() },
) {
    private val lock = Any()
    private val known = object : LinkedHashMap<String, AnimatedArt?>(64, 0.75f, true) {
        override fun removeEldestEntry(eldest: MutableMap.MutableEntry<String, AnimatedArt?>?) = size > KEPT
    }
    private val asking = HashMap<String, Deferred<AnimatedArt?>>()
    private val leftAlone = HashMap<String, Long>()

    // Whether the server offers animated art, and until when that holds.
    private var offeredAnswer: Boolean? = null
    private var offeredUntil = 0L
    private var offeredCheck: Deferred<Boolean>? = null

    // Counts up each time an answer arrives, for views that follow the book.
    private val _version = MutableStateFlow(0)
    val version: StateFlow<Int> = _version.asStateFlow()

    // What is known of the album right now, without asking.
    fun peek(albumId: String): KnownArt = synchronized(lock) {
        if (!known.containsKey(albumId)) KnownArt.Unknown else known[albumId]?.let { KnownArt.Has(it) } ?: KnownArt.HasNone
    }

    // Keeps the art getAlbum came with. getAlbum without art says nothing,
    // so only art is kept.
    fun note(albumId: String, art: AnimatedArt?) {
        if (art == null || art.isEmpty) return
        synchronized(lock) {
            known[albumId] = art
            offeredAnswer = true
            offeredUntil = Long.MAX_VALUE
        }
        _version.value++
    }

    // The album's animated art, asking the server when it is not known yet;
    // null when the album has none or the server cannot say.
    suspend fun art(albumId: String): AnimatedArt? {
        if (albumId.isBlank()) return null
        when (val held = peek(albumId)) {
            is KnownArt.Has -> return held.art
            KnownArt.HasNone -> return null
            KnownArt.Unknown -> Unit
        }
        return asked(albumId)?.await()
    }

    // Asks about these albums now, without waiting, so their art is ready
    // when they come up (the next song's, say).
    fun ahead(albumIds: List<String>) {
        for (id in albumIds.distinct()) {
            if (id.isBlank() || peek(id) != KnownArt.Unknown) continue
            scope.async(start = CoroutineStart.UNDISPATCHED) { runCatching { asked(id)?.await() } }
        }
    }

    // The one call for the album, started if none is running; null while
    // the album or the server is left alone.
    private suspend fun asked(albumId: String): Deferred<AnimatedArt?>? {
        if (!serverOffers()) return null
        val started: CompletableDeferred<AnimatedArt?>
        synchronized(lock) {
            asking[albumId]?.let { return it }
            if ((leftAlone[albumId] ?: 0L) > now()) return null
            started = CompletableDeferred()
            asking[albumId] = started
        }
        scope.async(start = CoroutineStart.UNDISPATCHED) {
            val answer = runCatching { ask(albumId) }.getOrDefault(AnimatedArtAnswer.NotNow)
            val art = keep(albumId, answer)
            started.complete(art)
        }
        return started
    }

    private fun keep(albumId: String, answer: AnimatedArtAnswer): AnimatedArt? {
        val art = (answer as? AnimatedArtAnswer.Found)?.art
        synchronized(lock) {
            asking.remove(albumId)
            when (answer) {
                is AnimatedArtAnswer.Found -> known[albumId] = answer.art
                AnimatedArtAnswer.None -> known[albumId] = null
                AnimatedArtAnswer.Off -> {
                    offeredAnswer = false
                    offeredUntil = now() + SERVER_OFF_PAUSE_MS
                }
                AnimatedArtAnswer.NotNow -> leftAlone[albumId] = now() + NOT_NOW_PAUSE_MS
            }
            if (leftAlone.size > KEPT) leftAlone.entries.removeAll { it.value <= now() }
        }
        _version.value++
        return art
    }

    // Whether the server offers animated art, asked once and kept for a
    // while; a server that could not be asked is asked again a minute later.
    private suspend fun serverOffers(): Boolean {
        val running: Deferred<Boolean>?
        val fresh = CompletableDeferred<Boolean>()
        synchronized(lock) {
            if (offeredUntil > now()) return offeredAnswer == true
            running = offeredCheck
            if (running == null) offeredCheck = fresh
        }
        if (running != null) return running.await()
        scope.async(start = CoroutineStart.UNDISPATCHED) {
            val listed = runCatching { offered() }.getOrNull()
            synchronized(lock) {
                offeredAnswer = listed
                offeredUntil = when (listed) {
                    true -> Long.MAX_VALUE
                    false -> now() + SERVER_OFF_PAUSE_MS
                    null -> now() + SERVER_UNKNOWN_PAUSE_MS
                }
                offeredCheck = null
            }
            fresh.complete(listed == true)
        }
        return fresh.await()
    }
}

// The album's animated art as it becomes known: what the book holds at
// once, then the server's answer. Null for no album.
@Composable
fun AnimatedArtBook.artOf(albumId: String?): State<AnimatedArt?> {
    val held = albumId?.let { (peek(it) as? KnownArt.Has)?.art }
    return produceState(held, this, albumId) {
        value = albumId?.let { art(it) }
    }
}
