package app.winters.octo.desktop.search

import app.winters.octo.subsonic.Acquisition
import app.winters.octo.desktop.lruMap
import app.winters.octo.subsonic.AcquisitionStage
import app.winters.octo.subsonic.SubsonicClient
import app.winters.octo.subsonic.SubsonicException
import app.winters.octo.ui.downloads.AskedSong
import app.winters.octo.ui.downloads.stillAsked
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Job
import kotlinx.coroutines.delay
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.update
import kotlinx.coroutines.isActive
import kotlinx.coroutines.launch
import java.util.concurrent.ConcurrentHashMap

// Where fetching one song into the library has got to, as the "+" button
// shows it: the plus, a ring filling, a check, or an alert.
sealed interface FetchPhase {
    data object None : FetchPhase
    data object Queued : FetchPhase
    data class Downloading(val progress: Float?) : FetchPhase
    data object Adding : FetchPhase
    data object Done : FetchPhase
    data class Failed(val reason: String) : FetchPhase
}

// What the server's word for a download means, as on the phone. A finished
// download is "adding" until the server has taken it into the library.
fun phaseOf(acquisition: Acquisition): FetchPhase = when (acquisition.stage) {
    AcquisitionStage.Queued, AcquisitionStage.Searching, AcquisitionStage.Unknown -> FetchPhase.Queued
    AcquisitionStage.Downloading -> FetchPhase.Downloading(acquisition.fraction)
    AcquisitionStage.Verifying, AcquisitionStage.Importing -> FetchPhase.Adding
    AcquisitionStage.Done -> FetchPhase.Done
    AcquisitionStage.Failed -> FetchPhase.Failed(acquisition.error?.trim()?.takeIf(String::isNotEmpty) ?: "the server did not say why")
}

// The words a screen reader says for a phase.
fun phaseText(phase: FetchPhase): String = when (phase) {
    FetchPhase.None -> "Not in your library"
    FetchPhase.Queued -> "Queued"
    is FetchPhase.Downloading -> phase.progress?.let { "Downloading, ${(it * 100).toInt()} percent" } ?: "Downloading"
    FetchPhase.Adding -> "Adding to your library"
    FetchPhase.Done -> "In your library"
    is FetchPhase.Failed -> "Could not add it: ${phase.reason}"
}

// How often to ask how the downloads are going while any is on its way.
const val FETCH_POLL_MS = 2_000L

// How many songs brought in keep their library id remembered here.
private const val LANDED_KEPT = 4096

// How many asks keep their row shown: checks and alerts stay for the last
// few hundred, which is more than a screen lists at once.
private const val PhasesKept = 512

// Has an Octo server fetch songs found online into the library: starring a
// find asks for it, and the server's octoAcquisitions list says how each is
// going. Only used when the server lists that extension.
class Fetches(
    private val client: SubsonicClient,
    private val scope: CoroutineScope,
    // Called when a song has arrived, so the library is read again.
    private val onArrived: () -> Unit = {},
    // Called when a song was asked for, so the downloads drawer looks now.
    private val onAsked: () -> Unit = {},
    private val pollMs: Long = FETCH_POLL_MS,
    private val clock: () -> Long = System::currentTimeMillis,
) {
    private val _phases = MutableStateFlow<Map<String, FetchPhase>>(emptyMap())

    // Each song asked for, by its id on the server.
    val phases: StateFlow<Map<String, FetchPhase>> = _phases

    private var watch: Job? = null

    // The library's own id for each song brought in, once the server names
    // it, so the song plays from the file it fetched rather than streaming
    // from where it was found. The last few thousand: a song taken in long
    // ago plays from its file by its own listing, not through this.
    private val landed = lruMap<String, String>(LANDED_KEPT)

    // When each song was asked for, once the server took the ask. Only the
    // asks still on their way, and the last few settled ones, are kept.
    private val askedAt = ConcurrentHashMap<String, Long>()

    fun phase(id: String): FetchPhase = phases.value[id] ?: FetchPhase.None

    // The library copy of a song asked for here, if it has landed.
    fun landedId(id: String): String? = landed[id]

    // Asks the server to fetch a song. A failed one can be asked again.
    fun request(id: String) {
        val now = phase(id)
        if (now != FetchPhase.None && now !is FetchPhase.Failed) return
        askedAt.remove(id)
        _phases.update { it + (id to FetchPhase.Queued) }
        scope.launch {
            try {
                client.star(listOf(id))
                askedAt[id] = clock()
                onAsked()
                follow()
            } catch (e: SubsonicException) {
                _phases.update { it + (id to FetchPhase.Failed("the server could not be asked")) }
            }
        }
    }

    // Asks how things are going until nothing is on its way.
    private fun follow() {
        if (watch?.isActive == true) return
        watch = scope.launch {
            while (isActive && _phases.value.values.any { it.inFlight }) {
                poll()
                delay(pollMs)
            }
        }
    }

    // One look at the server's list. Each song asked for takes the newest
    // entry with its id. One the list does not show is no longer on its way
    // once it is not still taken as asked for (stillAsked), so it can be
    // asked for again; until the server took the ask it stays queued.
    suspend fun poll() {
        val since = clock()
        val list = try {
            client.acquisitions()
        } catch (e: SubsonicException) {
            return
        }
        val now = clock()
        var arrived = false
        // Built once, eagerly: a mapped view would work out each song again
        // on every read, and keep this look's list alive while it is read.
        val settled = ArrayList<String>()
        _phases.update { phases ->
            trimmed(
                buildMap(phases.size) {
                    phases.forEach { (id, phase) ->
                        if (!phase.inFlight) {
                            put(id, phase)
                            return@forEach
                        }
                        val entry = list.filter { it.id == id }.maxByOrNull { it.startedAt.orEmpty() }
                        if (entry == null) {
                            val ended = askedAt[id]?.takeIf { !stillAsked(AskedSong(id, it), since, now) }
                            if (ended == null) put(id, phase) else { settled += id; put(id, FetchPhase.None) }
                            return@forEach
                        }
                        val next = phaseOf(entry)
                        if (next == FetchPhase.Done) {
                            arrived = true
                            entry.libraryId?.takeIf(String::isNotBlank)?.let { library -> landed[id] = library }
                        }
                        put(id, next)
                    }
                },
            )
        }
        settled.forEach { askedAt.remove(it) }
        if (arrived) onArrived()
    }

    // Songs asked for over a long listen each left their row in the phases
    // and their ask time behind. The rows are trimmed to the last few asks:
    // a screen reads a missing row as FetchPhase.None, which is what an old
    // settled song means anyway, so only the newest checks and alerts stay
    // where a screen can still show them.
    private fun trimmed(phases: Map<String, FetchPhase>): Map<String, FetchPhase> {
        if (phases.size <= PhasesKept) return phases
        val live = phases.filterValues { it.inFlight }
        if (live.size >= PhasesKept) return live
        val room = PhasesKept - live.size
        val kept = phases.entries.reversed().asSequence().filter { !it.value.inFlight }.take(room).map { it.key }.toSet()
        phases.keys.filterNot { it in live.keys || it in kept }.forEach { askedAt.remove(it) }
        return buildMap(live.size + room) {
            putAll(live)
            kept.forEach { put(it, phases.getValue(it)) }
        }
    }

    private val FetchPhase.inFlight: Boolean
        get() = this == FetchPhase.Queued || this is FetchPhase.Downloading || this == FetchPhase.Adding
}
