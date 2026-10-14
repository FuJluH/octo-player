package app.winters.octo.desktop.liveradio

import androidx.compose.runtime.Stable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue
import app.winters.octo.desktop.search.FetchPhase
import app.winters.octo.liveradio.HeartCandidate
import app.winters.octo.liveradio.LiveSongButton
import app.winters.octo.liveradio.liveSongButton
import app.winters.octo.liveradio.OnAir
import app.winters.octo.liveradio.heartMatch
import app.winters.octo.liveradio.heartQuery
import app.winters.octo.subsonic.Song
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Job
import kotlinx.coroutines.launch

// A song a search for the song on air found: in the library, or found
// online by Octo.
data class FoundSong(val song: Song, val inLibrary: Boolean)

// Where the live heart is for the song on air.
sealed interface HeartPhase {
    data object Idle : HeartPhase

    // Pressed while the song is still being looked for in Octo.
    data object Looking : HeartPhase

    // Starred: this song is the one on air.
    data class Starred(val song: Song) : HeartPhase
}

// The song a station has on air, found in Octo: one search each time the
// song changes (a song heard before is not searched again), and the one
// result that is surely it, library first. Its cover is the player's cover
// for the song, and the button beside the song acts on it: a song in the
// library is hearted (`star`), one found online is added (`add`, which has
// Octo download it), and with no sure match nothing is starred: `missed`
// opens the search instead. A press while the search runs waits for its
// answer. The button starts afresh when the song on air changes, and an
// answer that comes back after it changed is kept for that song only.
@Stable
class LiveHeart(
    private val scope: CoroutineScope,
    // The search; null with no server to ask.
    private val find: suspend (String) -> List<FoundSong>?,
    private val star: (Song, Boolean) -> Unit,
    // No sure match: the song on air and the search to open.
    private val missed: (OnAir, String) -> Unit,
    // Brings a song found online into the library.
    private val add: (Song) -> Unit = { star(it, true) },
    // Whether a song asked for has landed in the library.
    private val landed: (Song) -> Boolean = { false },
) {
    // The song on air the heart is for, and where it is.
    var onAir by mutableStateOf(OnAir.Nothing)
        private set
    var phase by mutableStateOf<HeartPhase>(HeartPhase.Idle)
        private set

    // The song in Octo that is surely the one on air, once found.
    var match by mutableStateOf<FoundSong?>(null)
        private set

    // Whether the search for the song on air has answered.
    var looked by mutableStateOf(false)
        private set

    // Answers by song, the most recent last; a search that failed is not
    // kept, so it is asked again.
    private val answers = object : LinkedHashMap<String, FoundSong?>(16, 0.75f, true) {
        override fun removeEldestEntry(eldest: MutableMap.MutableEntry<String, FoundSong?>) = size > KEPT_ANSWERS
    }
    private var job: Job? = null
    private var pressed = false

    // Whether the search for the song on air answered (it did not fail).
    private var answered = false

    // Whether the heart shows: only while a song with its artist is named.
    val shows: Boolean get() = onAir.named && onAir.artist.isNotBlank()

    // The song on air now; a new one empties the heart and is looked for.
    fun follow(now: OnAir) {
        if (sameSong(now, onAir)) return
        job?.cancel()
        onAir = now
        phase = HeartPhase.Idle
        pressed = false
        match = null
        looked = false
        answered = false
        if (!shows) return
        val key = keyOf(now)
        if (synchronized(answers) { answers.containsKey(key) }) {
            match = synchronized(answers) { answers[key] }
            looked = true
            answered = true
            return
        }
        lookUp(now)
    }

    private fun lookUp(asked: OnAir) {
        job = scope.launch {
            val found = try {
                find(heartQuery(asked))
            } catch (e: CancellationException) {
                throw e
            } catch (e: Exception) {
                null
            }
            val candidates = found.orEmpty().map { HeartCandidate(it.song.id, it.song.title, (it.song.displayArtist ?: it.song.artist).orEmpty(), it.inLibrary) }
            val pick = heartMatch(asked, candidates)?.let { sure -> found.orEmpty().firstOrNull { it.song.id == sure.id } }
            if (found != null) synchronized(answers) { answers[keyOf(asked)] = pick }
            if (!sameSong(asked, onAir)) return@launch
            match = pick
            looked = true
            answered = found != null
            if (pressed) {
                pressed = false
                settle()
            }
        }
    }

    // A press: hearts or adds the song on air, or takes back a heart
    // (`starredNow`: the library's song is a favorite already).
    fun press(starredNow: Boolean = false) {
        if (!shows) return
        val found = match
        if (phase == HeartPhase.Idle && answered && found != null && found.inLibrary && starredNow) {
            star(found.song, false)
            return
        }
        when (val was = phase) {
            HeartPhase.Looking -> return
            is HeartPhase.Starred -> {
                // A song on its way into the library waits there.
                if (match?.inLibrary != true && !landed(was.song)) return
                star(was.song, false)
                phase = HeartPhase.Idle
                return
            }
            HeartPhase.Idle -> Unit
        }
        if (answered) return settle()
        // Still looking, or the last search failed: wait for an answer.
        phase = HeartPhase.Looking
        pressed = true
        if (job?.isActive != true) lookUp(onAir)
    }

    // The button beside the song on air: the heart, the add button, the
    // plus that searches, or none. `fetch` is how the match's download goes,
    // `starredNow` whether the library has it as a favorite.
    fun button(fetch: FetchPhase, starredNow: Boolean): LiveSongButton {
        val found = match
        val asked = phase is HeartPhase.Starred
        val inFlight = fetch == FetchPhase.Queued || fetch is FetchPhase.Downloading || fetch == FetchPhase.Adding
        return liveSongButton(
            onAir,
            found?.let { HeartCandidate(it.song.id, it.song.title, (it.song.displayArtist ?: it.song.artist).orEmpty(), it.inLibrary) },
            looked,
            starred = starredNow || asked,
            inLibrary = fetch == FetchPhase.Done,
            adding = inFlight || (asked && found?.inLibrary == false),
        )
    }

    private fun settle() {
        val pick = match
        if (pick == null) {
            phase = HeartPhase.Idle
            missed(onAir, heartQuery(onAir))
        } else {
            if (pick.inLibrary) star(pick.song, true) else add(pick.song)
            phase = HeartPhase.Starred(pick.song)
        }
    }

    private fun keyOf(song: OnAir): String = song.artist.lowercase() + "\u0000" + song.title.lowercase()

    private fun sameSong(a: OnAir, b: OnAir): Boolean = a.title == b.title && a.artist == b.artist

    private companion object {
        const val KEPT_ANSWERS = 64
    }
}
