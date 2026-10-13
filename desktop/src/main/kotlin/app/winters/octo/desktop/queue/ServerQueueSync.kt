package app.winters.octo.desktop.queue

import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue
import app.winters.octo.desktop.player.DesktopPlayer
import app.winters.octo.desktop.player.PlayerState
import app.winters.octo.desktop.player.SavedQueue
import app.winters.octo.desktop.server.Connection
import app.winters.octo.desktop.settings.SettingsStore
import app.winters.octo.desktop.system.isOpenedFile
import app.winters.octo.playback.isRadio
import app.winters.octo.desktop.system.readSaved
import app.winters.octo.desktop.system.saveWhole
import app.winters.octo.server.RemoteQueue
import app.winters.octo.server.ServerQueue
import app.winters.octo.server.remoteQueueOf
import app.winters.octo.server.shouldOfferResume
import app.winters.octo.server.trimmed
import app.winters.octo.subsonic.INDEX_BASED_QUEUE
import app.winters.octo.subsonic.SubsonicException
import kotlinx.coroutines.CoroutineDispatcher
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.Job
import kotlinx.coroutines.delay
import kotlinx.coroutines.flow.distinctUntilChanged
import kotlinx.coroutines.flow.drop
import kotlinx.coroutines.flow.map
import kotlinx.coroutines.launch
import kotlinx.coroutines.sync.Mutex
import kotlinx.coroutines.sync.withLock
import kotlinx.coroutines.withContext
import kotlinx.serialization.Serializable
import kotlinx.serialization.json.Json
import java.io.File

// How long the queue has to stay put before it is saved on the server.
private const val SAVE_AFTER_MS = 10_000L

// Coming back to the window more often than this asks the server only once.
private const val CHECK_EVERY_MS = 30_000L

// The queue as the server should keep it: server songs in the order they
// play (songs opened from files and live radio are left out), the current one's place,
// and where in it. When the current song is not on the server, the next
// one that is takes its place, from its start. Null when none is.
fun serverQueueOf(state: PlayerState, positionMs: Long): ServerQueue? {
    val current = state.current ?: return null
    val order = state.played + current + state.upcoming
    val currentRank = state.played.size
    val kept = order.withIndex().filter { !isOpenedFile(it.value.song.id) && !isRadio(it.value.song.id) }
    if (kept.isEmpty()) return null
    val ids = kept.map { it.value.song.id }
    val exact = kept.indexOfFirst { it.index == currentRank }
    if (exact >= 0) return ServerQueue(ids, exact, positionMs.coerceAtLeast(0))
    val next = kept.indexOfFirst { it.index > currentRank }
    return ServerQueue(ids, if (next >= 0) next else kept.lastIndex, 0)
}

// An offer to carry on from another device: its name, and the song it was on.
class ResumeOffer(val device: String?, val title: String, val artist: String?, internal val remote: RemoteQueue)

// When this account last saved a queue on the server, the server's own
// time for that save, and the newest offer answered.
@Serializable
private data class SyncMarks(val savedAt: Long = 0, val ownStamp: Long? = null, val answeredAt: Long = 0)

private val json = Json { ignoreUnknownKeys = true }

// Keeps the play queue on the server, as the phone does, so the phone (or
// another app) can carry on from it, and offers to carry on from a queue
// saved elsewhere. Saves a short while after the queue or the song
// changes, and at a pause. On unless switched off in Settings.
class ServerQueueSync(
    private val player: DesktopPlayer,
    private val settings: SettingsStore,
    private val connection: () -> Connection?,
    private val scope: CoroutineScope,
    private val io: CoroutineDispatcher = Dispatchers.IO,
    private val saveAfterMs: Long = SAVE_AFTER_MS,
    private val now: () -> Long = System::currentTimeMillis,
) {
    // The signed-in account's folder, or null while signed out.
    @Volatile var folder: File? = null

    // A queue from another device to offer on Home, if there is one.
    var offer by mutableStateOf<ResumeOffer?>(null)
        private set

    private val saving = Mutex()
    private var pending: Job? = null
    private var lastSent: ServerQueue? = null
    private var lastCheck = 0L

    // A queue put back (from disk, or taken from an offer) is not a change,
    // so it is not saved over a newer queue from elsewhere.
    private var baseline: Pair<List<String>, Int>? = null

    private val on: Boolean get() = settings.current.listening.syncQueue

    fun start(): Job = scope.launch {
        launch {
            player.state
                .map { state -> state.current?.let { Placing((state.played + it + state.upcoming).map { e -> e.song.id }, state.played.size) } }
                .distinctUntilChanged()
                .drop(1)
                .collect { placing -> if (placing != null) changed(placing) }
        }
        launch {
            player.state.map { it.playing }.distinctUntilChanged().drop(1).collect { playing -> if (!playing) paused() }
        }
    }

    // What was put back is where things stand, not something new to save.
    fun restored(saved: SavedQueue) {
        baseline = saved.order.map { saved.songs[it].id } to saved.order.indexOf(saved.index)
    }

    // The queue the player holds now was put back from this computer, not
    // played: a pause before anything changes sends nothing, so it never
    // lands over a newer queue on a server just switched to.
    fun putBack() {
        lastSent = serverQueueOf(player.state.value, player.positionMs())?.trimmed()
    }

    // A server was signed in to, or signed out of.
    fun reset() {
        pending?.cancel()
        lastSent = null
        lastCheck = 0
        offer = null
    }

    // The window came forward, or Octo signed in: look for a queue saved
    // elsewhere. Asks the server at most every half minute.
    fun check(force: Boolean = false) {
        val at = now()
        if (!force && at - lastCheck < CHECK_EVERY_MS) return
        lastCheck = at
        scope.launch {
            val found = withContext(io) { runCatching { lookForOffer() }.getOrNull() }
            offer = found
        }
    }

    // Loads an offered queue, paused where the other device left it.
    fun take(offer: ResumeOffer) {
        val remote = offer.remote
        val saved = SavedQueue(remote.songs, remote.songs.indices.toList(), remote.index, remote.positionMs)
        restored(saved)
        player.restore(saved)
        answered(offer)
    }

    // Not now: the same queue is not offered again.
    fun dismiss(offer: ResumeOffer) = answered(offer)

    private fun answered(offer: ResumeOffer) {
        if (this.offer === offer) this.offer = null
        val at = offer.remote.changedAt ?: return
        scope.launch(io) { updateMarks { it.copy(answeredAt = maxOf(it.answeredAt, at)) } }
    }

    private data class Placing(val ids: List<String>, val index: Int)

    private fun changed(placing: Placing) {
        if (baseline == placing.ids to placing.index) return
        baseline = null
        pending?.cancel()
        pending = scope.launch {
            delay(saveAfterMs)
            save(exact = false)
        }
    }

    private fun paused() {
        baseline = null
        pending?.cancel()
        pending = scope.launch { save(exact = true) }
    }

    // A save after a change is skipped when only the position moved; a
    // save at a pause is skipped only when nothing did.
    private suspend fun save(exact: Boolean) {
        if (!on) return
        val server = connection() ?: return
        val state = player.state.value
        val queue = serverQueueOf(state, player.positionMs())?.trimmed() ?: return
        withContext(io) {
            saving.withLock {
                val sent = lastSent
                if (sent == queue || (!exact && sent?.ids == queue.ids && sent.index == queue.index)) return@withLock
                val byIndex = server.supports(INDEX_BASED_QUEUE)
                try {
                    if (byIndex) server.client.savePlayQueueByIndex(queue.ids, queue.index, queue.positionMs)
                    else server.client.savePlayQueue(queue.ids, queue.index, queue.positionMs)
                } catch (e: SubsonicException) {
                    return@withLock
                }
                lastSent = queue
                // The server's time for this save is how this computer knows
                // its own queue later, whatever the other devices are called.
                val stamp = runCatching { remote(server) }.getOrNull()?.changedAt
                updateMarks { it.copy(savedAt = now(), ownStamp = stamp ?: it.ownStamp) }
            }
        }
    }

    private suspend fun lookForOffer(): ResumeOffer? {
        if (!on) return null
        val server = connection() ?: return null
        val found = try {
            remote(server)
        } catch (e: SubsonicException) {
            return null
        }
        val marks = readMarks()
        val current = found?.current ?: return null
        if (!shouldOfferResume(found, marks.savedAt, marks.answeredAt, marks.ownStamp)) return null
        // Octo on another device calls itself Octo too; that says nothing.
        val device = found.changedBy?.trim()?.takeIf { it.isNotEmpty() && !it.equals("Octo", ignoreCase = true) }
        return ResumeOffer(device, current.title, current.displayArtist ?: current.artist, found)
    }

    private suspend fun remote(server: Connection): RemoteQueue? =
        if (server.supports(INDEX_BASED_QUEUE)) server.client.playQueueByIndex()?.let(::remoteQueueOf)
        else server.client.playQueue()?.let(::remoteQueueOf)

    private val marksFile get() = folder?.let { File(it, "queue-sync.json") }

    @Synchronized
    private fun readMarks(): SyncMarks =
        marksFile?.let(::readSaved)?.let { runCatching { json.decodeFromString(SyncMarks.serializer(), it) }.getOrNull() } ?: SyncMarks()

    @Synchronized
    private fun updateMarks(change: (SyncMarks) -> SyncMarks) {
        val file = marksFile ?: return
        saveWhole(file, json.encodeToString(SyncMarks.serializer(), change(readMarks())))
    }
}
