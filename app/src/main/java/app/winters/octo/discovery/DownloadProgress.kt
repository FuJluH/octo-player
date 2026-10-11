package app.winters.octo.discovery

import app.winters.octo.catalog.FIND_PREFIX
import app.winters.octo.catalog.OnlineSongEntity
import app.winters.octo.catalog.SongIdentity
import app.winters.octo.subsonic.Acquisition
import app.winters.octo.subsonic.AcquisitionStage
import app.winters.octo.ui.downloads.AskedSong
import app.winters.octo.ui.downloads.stillAsked
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.Job
import kotlinx.coroutines.channels.Channel
import kotlinx.coroutines.coroutineScope
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.update
import kotlinx.coroutines.launch
import kotlinx.coroutines.withTimeoutOrNull
import kotlin.math.max

// How often to ask the server how its downloads are going: often while a
// song downloading is on screen, less often otherwise, and seldom while the
// app is in the background.
const val POLL_WATCHED_MS = 2_000L
const val POLL_MS = 5_000L
const val POLL_AWAY_MS = 30_000L

// How many times, and how far apart, to bring a finished song into the
// library while the server takes it in.
const val ARRIVAL_TRIES = 3
const val ARRIVAL_RETRY_MS = 20_000L

// A download the server has not listed for this long is no longer followed.
const val UNSEEN_MS = 10 * 60_000L

// What a find's download button shows.
sealed interface DownloadPhase {
    data object None : DownloadPhase

    // Asked for: waiting its turn on the server, or looking for a source.
    data object Queued : DownloadPhase

    // On its way, with how far from 0 to 1, or null when not known.
    data class Downloading(val progress: Float?) : DownloadPhase

    // Downloaded, and being checked and put into the library.
    data object Adding : DownloadPhase

    data object Done : DownloadPhase

    data class Failed(val reason: String) : DownloadPhase
}

// What the server's word for a download means here. A finished download
// is still being added until the song really is in the library.
fun phaseOf(acquisition: Acquisition): DownloadPhase = when (acquisition.stage) {
    AcquisitionStage.Queued, AcquisitionStage.Searching, AcquisitionStage.Unknown -> DownloadPhase.Queued
    AcquisitionStage.Downloading -> DownloadPhase.Downloading(acquisition.fraction)
    AcquisitionStage.Verifying, AcquisitionStage.Importing, AcquisitionStage.Done -> DownloadPhase.Adding
    AcquisitionStage.Failed -> DownloadPhase.Failed(acquisition.error?.trim()?.takeIf(String::isNotEmpty) ?: "the server did not say why")
}

// What one find shows: the library has the last word, then the server's
// news. A download the server's newest list does not show is queued only
// while it is still taken as asked for (stillAsked), and otherwise not on
// its way, so it can be asked for again. `listedSince` is when that list
// was asked for, `album` whether the song was asked for with its album,
// and `lists` whether the server lists its downloads at all: one that does
// not is only ever asked about through the library, so its downloads stay
// queued until they arrive or are given up.
fun phaseFor(
    row: OnlineSongEntity,
    live: DownloadPhase?,
    now: Long,
    listedSince: Long? = null,
    album: Boolean = false,
    lists: Boolean = true,
): DownloadPhase = when (stateOf(row, now)) {
    DownloadState.Done -> DownloadPhase.Done
    DownloadState.None -> DownloadPhase.None
    DownloadState.Requested -> live ?: if (!lists || stillAsked(askOf(row, album), listedSince, now)) DownloadPhase.Queued else DownloadPhase.None
}

// A find asked for, as the shared rule reads it.
fun askOf(row: OnlineSongEntity, album: Boolean = false): AskedSong =
    AskedSong(row.id.removePrefix(FIND_PREFIX), row.requestedAt, album)

// The finds among `rows` asked for with their whole album: requestAlbum
// gives every song of an album one time, which a song asked for alone
// never shares with another song of its album.
fun askedWithAlbum(rows: List<OnlineSongEntity>): Set<String> =
    rows.filter { it.requestedAt > 0 && !it.albumId.isNullOrEmpty() }
        .groupBy { it.albumId to it.requestedAt }
        .values.filter { it.size > 1 }
        .flatMapTo(HashSet()) { group -> group.map { it.id } }

// The plain state, for places that only need to know whether a download
// can be asked for. A failed one can be asked for again.
val DownloadPhase.state: DownloadState
    get() = when (this) {
        DownloadPhase.Done -> DownloadState.Done
        DownloadPhase.None, is DownloadPhase.Failed -> DownloadState.None
        else -> DownloadState.Requested
    }

// How long to wait before asking the server again.
fun pollDelayMs(downloadingOnScreen: Boolean, foreground: Boolean): Long = when {
    !foreground -> POLL_AWAY_MS
    downloadingOnScreen -> POLL_WATCHED_MS
    else -> POLL_MS
}

// The server's entry for a find: the one starred with its id, or else one
// with the same title and artist, as songs of an album asked for at once
// may carry the album's id. An entry without an artist is matched by its
// title and kind of recording alone. The newest wins when there are several.
fun acquisitionFor(find: OnlineSongEntity, list: List<Acquisition>): Acquisition? {
    val byId = list.filter { it.id.isNotEmpty() && FIND_PREFIX + it.id == find.id }
    val candidates = byId.ifEmpty {
        list.filter {
            it.title.isNotBlank() &&
                if (it.artist.isBlank()) SongIdentity.sameTitle(it.title, find.title).isSame else sameRecording(it.title, it.artist, find.title, find.artist)
        }
    }
    return candidates.maxByOrNull { it.startedAt.orEmpty() }
}

// What following downloads needs from the rest of the app.
interface AcquisitionHost {
    // Finds asked for that are not in the library yet.
    suspend fun waiting(): List<OnlineSongEntity>

    // What the server is downloading, or null when it cannot say. Throws
    // when the server cannot be reached right now.
    suspend fun acquisitions(): List<Acquisition>?

    // Brings one finished song into the library by its server id, and
    // answers the library song it became.
    suspend fun takeIn(libraryId: String): String?

    // Links a find to the library song it became.
    suspend fun adopt(findId: String, trackId: String)

    // Copies the library again and waits for it; songs that arrived are
    // adopted along the way.
    suspend fun syncAndWait()
}

// Follows the downloads asked for on a server that says how they are going,
// until none is left waiting. Only while the app runs.
class ProgressWatch(private val host: AcquisitionHost, private val clock: () -> Long = System::currentTimeMillis) {
    private val _live = MutableStateFlow<Map<String, DownloadPhase>>(emptyMap())

    // What the server last said about each find it is downloading.
    val live: StateFlow<Map<String, DownloadPhase>> = _live

    private val _listedSince = MutableStateFlow<Long?>(null)

    // When the newest list that came back was asked for, or null before
    // any did: a find asked for before then that `live` leaves out is not
    // on that list.
    val listedSince: StateFlow<Long?> = _listedSince

    private val lock = Any()
    private val highest = HashMap<String, Float>()
    private val tries = HashMap<String, Int>()
    private val triedAt = HashMap<String, Long>()
    private val lastSeen = HashMap<String, Acquisition>()
    private val passedOver = HashMap<String, Acquisition>()
    private val unseenSince = HashMap<String, Long>()
    private val onScreen = HashMap<String, Int>()
    private val wake = Channel<Unit>(Channel.CONFLATED)

    // Whether the app is in front. Coming back asks at once.
    @Volatile
    var foreground: Boolean = true
        set(value) {
            val back = value && !field
            field = value
            if (back) wake()
        }

    // Asks the server again now, not at the next turn.
    fun wake() {
        wake.trySend(Unit)
    }

    // A find's button is on screen until the answer is called.
    fun show(findId: String): () -> Unit {
        synchronized(lock) { onScreen[findId] = (onScreen[findId] ?: 0) + 1 }
        if (_live.value[findId] is DownloadPhase.Downloading) wake()
        return {
            synchronized(lock) {
                val left = (onScreen[findId] ?: 1) - 1
                if (left > 0) onScreen[findId] = left else onScreen.remove(findId)
            }
        }
    }

    // A find asked for again starts afresh: a failure the server still
    // lists is passed over, and its progress starts from nothing.
    fun retry(findId: String) {
        synchronized(lock) {
            lastSeen[findId]?.takeIf { it.stage == AcquisitionStage.Failed }?.let { passedOver[findId] = it }
            highest.remove(findId)
            tries.remove(findId)
            triedAt.remove(findId)
            unseenSince.remove(findId)
        }
        _live.update { it - findId }
        wake()
    }

    // Asks the server until nothing is left waiting. Answers false at once
    // when the server cannot say how its downloads are going.
    suspend fun run(): Boolean = coroutineScope {
        var arriving: Job? = null
        var answer: Boolean? = null
        while (answer == null) {
            when (val poll = poll(canArrive = arriving?.isActive != true)) {
                Poll.Unsupported -> {
                    arriving?.join()
                    answer = false
                }
                // Songs still being brought in may need another look.
                Poll.Idle -> {
                    val job = arriving?.takeIf { it.isActive }
                    if (job != null) job.join() else answer = true
                }
                is Poll.Asked -> {
                    if (poll.due.isNotEmpty()) {
                        arriving = launch {
                            arrive(poll.due)
                            wake()
                        }
                    }
                    withTimeoutOrNull(nextDelayMs()) { wake.receive() }
                }
            }
        }
        answer
    }

    private sealed interface Poll {
        data object Unsupported : Poll
        data object Idle : Poll
        class Asked(val due: List<Pair<OnlineSongEntity, Acquisition>>) : Poll
    }

    // One question to the server, and what it means for each find.
    private suspend fun poll(canArrive: Boolean): Poll {
        val waiting = host.waiting()
        if (waiting.isEmpty()) {
            _live.value = emptyMap()
            return Poll.Idle
        }
        val askedAt = clock()
        val list = try {
            host.acquisitions() ?: return Poll.Unsupported
        } catch (e: CancellationException) {
            throw e
        } catch (e: Exception) {
            // Out of reach for now: ask again at the next turn.
            return Poll.Asked(emptyList())
        }
        val now = clock()
        val next = HashMap<String, DownloadPhase>()
        val due = mutableListOf<Pair<OnlineSongEntity, Acquisition>>()
        var pending = false
        val withAlbum = askedWithAlbum(waiting)
        synchronized(lock) {
            for (find in waiting) {
                val skip = passedOver[find.id]
                val entry = acquisitionFor(find, if (skip == null) list else list.filter { it != skip })
                if (entry == null) {
                    val since = unseenSince.getOrPut(find.id) { now }
                    if (now - since < UNSEEN_MS || stillAsked(askOf(find, find.id in withAlbum), askedAt, now)) pending = true
                    continue
                }
                unseenSince.remove(find.id)
                lastSeen[find.id] = entry
                next[find.id] = steady(find.id, phaseOf(entry))
                when (entry.stage) {
                    AcquisitionStage.Failed -> Unit
                    AcquisitionStage.Done -> {
                        val tried = tries[find.id] ?: 0
                        val last = triedAt[find.id]
                        if (canArrive && tried < ARRIVAL_TRIES && (last == null || now - last >= ARRIVAL_RETRY_MS)) {
                            tries[find.id] = tried + 1
                            triedAt[find.id] = now
                            due += find to entry
                        }
                        if ((tries[find.id] ?: 0) < ARRIVAL_TRIES) pending = true
                        // In the server's library, and brought in as often as it will be:
                        // in the library, whether or not a copy of it here has been linked yet.
                        else if (due.none { it.first.id == find.id }) next[find.id] = DownloadPhase.Done
                    }
                    else -> pending = true
                }
            }
        }
        _live.value = next
        _listedSince.value = askedAt
        return if (pending || due.isNotEmpty()) Poll.Asked(due) else Poll.Idle
    }

    // Progress never goes back: a lower or unknown figure keeps the highest
    // one seen for this find.
    private fun steady(findId: String, phase: DownloadPhase): DownloadPhase {
        if (phase !is DownloadPhase.Downloading) return phase
        val best = max(highest[findId] ?: 0f, phase.progress ?: 0f)
        if (phase.progress == null && findId !in highest) return phase
        highest[findId] = best
        return DownloadPhase.Downloading(best)
    }

    // Songs the server finished: each one it names is brought in at once,
    // then the whole library is copied again, which adopts the rest.
    private suspend fun arrive(due: List<Pair<OnlineSongEntity, Acquisition>>) {
        for ((find, entry) in due) {
            val libraryId = entry.libraryId?.takeIf(String::isNotBlank) ?: continue
            try {
                host.takeIn(libraryId)?.let { host.adopt(find.id, it) }
            } catch (e: CancellationException) {
                throw e
            } catch (e: Exception) {
                // The full copy below still finds it.
            }
        }
        try {
            host.syncAndWait()
        } catch (e: CancellationException) {
            throw e
        } catch (e: Exception) {
            // Tried again at the next finished answer.
        }
    }

    private fun nextDelayMs(): Long {
        val live = _live.value
        val shown = synchronized(lock) { onScreen.keys.toSet() }
        return pollDelayMs(live.any { (id, phase) -> phase is DownloadPhase.Downloading && id in shown }, foreground)
    }
}
