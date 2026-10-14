package app.winters.octo.desktop.liveradio

import androidx.compose.runtime.Stable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue
import app.winters.octo.liveradio.HeartCandidate
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

    // Looking for the song in Octo.
    data object Looking : HeartPhase

    // Starred: this song is the one on air.
    data class Starred(val song: Song) : HeartPhase
}

// The heart of the live player, which hearts the song on air: a search for
// it in Octo, and the one result that is surely it (library first) is
// starred; a song found online is starred the way any is, which has Octo
// download it. With no sure match nothing is starred, and `missed` offers
// the search instead. The heart starts empty again when the song on air
// changes, and a search that comes back after it changed stars nothing.
@Stable
class LiveHeart(
    private val scope: CoroutineScope,
    // The search; null with no server to ask.
    private val find: suspend (String) -> List<FoundSong>?,
    private val star: (Song, Boolean) -> Unit,
    // No sure match: the song on air and the search to offer.
    private val missed: (OnAir, String) -> Unit,
) {
    // The song on air the heart is for, and where it is.
    var onAir by mutableStateOf(OnAir.Nothing)
        private set
    var phase by mutableStateOf<HeartPhase>(HeartPhase.Idle)
        private set

    private var job: Job? = null

    // Whether the heart shows: only while a song with its artist is named.
    val shows: Boolean get() = onAir.named && onAir.artist.isNotBlank()

    // The song on air now; a new one empties the heart.
    fun follow(now: OnAir) {
        if (sameSong(now, onAir)) return
        job?.cancel()
        onAir = now
        phase = HeartPhase.Idle
    }

    // A press: stars the song on air, or takes back the star it gave.
    fun press() {
        val asked = onAir
        if (!shows) return
        when (val was = phase) {
            HeartPhase.Looking -> return
            is HeartPhase.Starred -> {
                star(was.song, false)
                phase = HeartPhase.Idle
                return
            }
            HeartPhase.Idle -> Unit
        }
        val query = heartQuery(asked)
        phase = HeartPhase.Looking
        job = scope.launch {
            val found = try {
                find(query).orEmpty()
            } catch (e: CancellationException) {
                throw e
            } catch (e: Exception) {
                emptyList()
            }
            if (!sameSong(asked, onAir)) return@launch
            val candidates = found.map { HeartCandidate(it.song.id, it.song.title, (it.song.displayArtist ?: it.song.artist).orEmpty(), it.inLibrary) }
            val pick = heartMatch(asked, candidates)?.let { match -> found.firstOrNull { it.song.id == match.id } }
            if (pick == null) {
                phase = HeartPhase.Idle
                missed(asked, query)
            } else {
                star(pick.song, true)
                phase = HeartPhase.Starred(pick.song)
            }
        }
    }

    private fun sameSong(a: OnAir, b: OnAir): Boolean = a.title == b.title && a.artist == b.artist
}

// The heart's words for a screen reader: "Heart Petal by Ariana Grande".
fun heartLabel(onAir: OnAir): String = "Heart " + listOf(onAir.title, onAir.artist).filter(String::isNotBlank).joinToString(" by ")

// What the notice says when no song is surely the one on air.
fun heartMissedLine(onAir: OnAir): String =
    "Couldn't find " + listOf(onAir.title, onAir.artist).filter(String::isNotBlank).joinToString(" by ") + " in Octo for sure."
