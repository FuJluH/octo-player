package app.winters.octo.playback

import android.content.Context
import android.util.Log
import androidx.datastore.core.DataStore
import androidx.datastore.preferences.core.Preferences
import androidx.datastore.preferences.core.edit
import androidx.datastore.preferences.core.stringPreferencesKey
import androidx.datastore.preferences.preferencesDataStore
import app.winters.octo.catalog.CatalogDao
import app.winters.octo.catalog.LikedTrackEntity
import app.winters.octo.catalog.PlayEventEntity
import app.winters.octo.catalog.QueueItemEntity
import app.winters.octo.catalog.QueueStateEntity
import app.winters.octo.catalog.TrackEntity
import app.winters.octo.catalog.UserDao
import app.winters.octo.listening.ListenBrainzSync
import app.winters.octo.listening.ListeningSync
import dagger.hilt.android.qualifiers.ApplicationContext
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.CompletableDeferred
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.channels.Channel
import kotlinx.serialization.Serializable
import kotlinx.serialization.json.Json
import kotlinx.coroutines.flow.SharingStarted
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.map
import kotlinx.coroutines.flow.stateIn
import kotlinx.coroutines.launch
import javax.inject.Inject
import javax.inject.Singleton
import java.io.File

// Looks up songs by id, keeping the order asked for and dropping any the
// catalog no longer has. SQLite limits how many ids fit in one query.
suspend fun CatalogDao.tracksByIds(ids: List<String>): List<TrackEntity> {
    val found = ids.distinct().chunked(900).flatMap { tracksByIdsUnordered(it) }.associateBy { it.id }
    return ids.mapNotNull { found[it] }
}

@Singleton
class LikeStore @Inject constructor(
    private val userDao: UserDao,
    private val catalog: CatalogDao,
    private val listening: ListeningSync,
) {
    private val scope = CoroutineScope(SupervisorJob() + Dispatchers.Default)

    val liked: StateFlow<Set<String>> =
        userDao.likedIds().map { it.toSet() }.stateIn(scope, SharingStarted.Eagerly, emptySet())

    fun isLiked(trackId: String) = trackId in liked.value

    fun toggle(trackId: String) {
        scope.launch {
            if (userDao.isLiked(trackId)) {
                userDao.unlike(trackId)
                listening.likeChanged(trackId, liked = false)
            } else {
                val track = catalog.track(trackId) ?: return@launch
                userDao.like(LikedTrackEntity(trackId, track.relinkKey, System.currentTimeMillis()))
                listening.likeChanged(trackId, liked = true)
            }
        }
    }

    // Takes a like away. `removed` hears the like as it was, to put it back.
    fun unlike(trackId: String, removed: (LikedTrackEntity) -> Unit) {
        scope.launch {
            val row = userDao.likedRow(trackId) ?: return@launch
            userDao.unlike(trackId)
            listening.likeChanged(trackId, liked = false)
            removed(row)
        }
    }

    // Puts a like back as it was, with its own time, so it keeps its place.
    fun restore(row: LikedTrackEntity) {
        scope.launch {
            userDao.like(row)
            listening.likeChanged(row.trackId, liked = true)
        }
    }
}

// The queue as saved: songs in play order, where playback was, and the
// shuffle order so shuffle picks up exactly where it left off.
data class QueueSnapshot(
    val trackIds: List<String>,
    // Play-order positions visited in shuffle order; empty when unknown.
    val shuffleOrder: List<Int>,
    val index: Int,
    val positionMs: Long,
    val repeatMode: Int,
    val shuffle: Boolean,
    // Where each song came from (QueueSource.encoded), one per song, so a
    // station keeps going after a restart; empty when unknown.
    val sources: List<String> = emptyList(),
)

fun QueueSnapshot.toRows(now: Long): Pair<List<QueueItemEntity>, QueueStateEntity> {
    val shuffledAt = IntArray(trackIds.size) { it }
    if (shuffleOrder.size == trackIds.size) shuffleOrder.forEachIndexed { rank, position -> shuffledAt[position] = rank }
    val items = trackIds.mapIndexed { position, id -> QueueItemEntity(position, id, shuffledAt[position]) }
    return items to QueueStateEntity(0, index, positionMs, repeatMode, shuffle, now)
}

fun queueFromRows(items: List<QueueItemEntity>, state: QueueStateEntity?): QueueSnapshot? {
    if (items.isEmpty() || state == null) return null
    val ordered = items.sortedBy { it.position }
    return QueueSnapshot(
        trackIds = ordered.map { it.trackId },
        shuffleOrder = ordered.sortedBy { it.shuffledPosition }.map { it.position },
        index = state.currentIndex.coerceIn(0, ordered.lastIndex),
        positionMs = state.positionMs.coerceAtLeast(0),
        repeatMode = state.repeatMode,
        shuffle = state.shuffle,
    )
}

// Where a saved queue picks up once the songs gone from the library are
// dropped: `found` says which saved songs are still here, in saved order.
// The saved song at the place it was, or when that song is gone, the first
// song from its start.
fun restorePoint(found: List<Boolean>, savedIndex: Int, positionMs: Long): Pair<Int, Long> {
    if (found.getOrNull(savedIndex) != true) return 0 to 0L
    return found.take(savedIndex).count { it } to positionMs.coerceAtLeast(0)
}

// The saved shuffle order with the songs that are gone left out, so the
// rest still play in the order they would have.
fun restoredShuffle(order: List<Int>, found: List<Boolean>): IntArray? {
    if (order.size != found.size || order.sorted() != found.indices.toList()) return null
    val newIndex = IntArray(found.size)
    var kept = 0
    found.forEachIndexed { i, here -> newIndex[i] = if (here) kept++ else -1 }
    return order.filter { found[it] }.map { newIndex[it] }.toIntArray()
}

// The queue in use is the saved queue (its rows in the catalog); each other
// account's waits in `parked` until its server is in use again. Every read
// and write runs one at a time in the order asked, so a save asked for
// before a hand-over lands before it, never over the queue handed over.
@Singleton
class QueueStore internal constructor(
    private val rows: QueueRows,
    private val parked: ParkedQueues,
) {
    @Inject constructor(userDao: UserDao, @ApplicationContext context: Context) :
        this(CatalogQueueRows(userDao, File(context.filesDir, "queue-sources")), ParkedQueues(context.parkedQueueData))

    private val scope = CoroutineScope(SupervisorJob() + Dispatchers.IO)
    private val work = Channel<suspend () -> Unit>(Channel.UNLIMITED)

    init {
        scope.launch {
            for (step in work) {
                try {
                    step()
                } catch (e: CancellationException) {
                    throw e
                } catch (e: Exception) {
                    Log.w("Octo", "queue store: ${e.javaClass.simpleName}")
                }
            }
        }
    }

    // Saving runs on its own scope so it finishes even while the service stops.
    fun save(snapshot: QueueSnapshot) {
        work.trySend { rows.write(snapshot) }
    }

    suspend fun load(): QueueSnapshot? = inTurn { rows.read() }

    // Another account's queue becomes the one in use. The queue of `from`
    // (as it was left, else as saved) waits for it, and the one `to` left
    // comes back. With nothing waiting for `to`, the queue is emptied,
    // unless `keepWhenNone`, when it stays as it is and nothing waits.
    // Answers whether the queue in use changed.
    suspend fun handOver(from: String, left: QueueSnapshot?, to: String, keepWhenNone: Boolean): Boolean = inTurn {
        val coming = parked.take(to)
        if (coming == null && keepWhenNone) return@inTurn false
        parked.put(from, left ?: rows.read())
        rows.write(coming ?: QueueSnapshot(emptyList(), emptyList(), 0, 0, 0, false))
        true
    }

    // Forgets the queue kept for a server taken off the list.
    suspend fun forget(account: String) = inTurn { parked.put(account, null) }

    private suspend fun <T> inTurn(block: suspend () -> T): T {
        val answer = CompletableDeferred<T>()
        work.send {
            try {
                answer.complete(block())
            } catch (e: Throwable) {
                answer.completeExceptionally(e)
            }
        }
        return answer.await()
    }
}

// Where the queue in use is saved.
interface QueueRows {
    suspend fun read(): QueueSnapshot?

    suspend fun write(snapshot: QueueSnapshot)
}

// The saved queue's rows in the catalog, and where each song came from in a
// small file beside them, one word a line.
private class CatalogQueueRows(private val userDao: UserDao, private val sourcesFile: File) : QueueRows {
    override suspend fun read(): QueueSnapshot? {
        val saved = queueFromRows(userDao.queueItems(), userDao.queueState()) ?: return null
        val sources = runCatching { sourcesFile.readLines() }.getOrDefault(emptyList())
        return if (sources.size == saved.trackIds.size) saved.copy(sources = sources) else saved
    }

    override suspend fun write(snapshot: QueueSnapshot) {
        val (items, state) = snapshot.toRows(System.currentTimeMillis())
        userDao.saveQueue(items, state)
        runCatching {
            if (snapshot.sources.size == snapshot.trackIds.size && snapshot.sources.isNotEmpty()) {
                sourcesFile.writeText(snapshot.sources.joinToString("\n") { it.replace('\n', ' ') })
            } else {
                sourcesFile.delete()
            }
        }
    }
}

private val Context.parkedQueueData by preferencesDataStore("parked_queues")

// The queues of accounts not in use, one per account.
class ParkedQueues(private val data: DataStore<Preferences>) {
    // Takes the queue waiting for an account, which then waits no more.
    suspend fun take(account: String): QueueSnapshot? {
        var found: QueueSnapshot? = null
        data.edit { p ->
            found = p[keyOf(account)]?.let(::decodeQueue)
            p.remove(keyOf(account))
        }
        return found
    }

    suspend fun put(account: String, queue: QueueSnapshot?) {
        data.edit { p -> if (queue == null || queue.trackIds.isEmpty()) p.remove(keyOf(account)) else p[keyOf(account)] = encodeQueue(queue) }
    }

    private fun keyOf(account: String) = stringPreferencesKey("queue@$account")
}

@Serializable
private class StoredQueue(
    val trackIds: List<String>,
    val shuffleOrder: List<Int> = emptyList(),
    val index: Int = 0,
    val positionMs: Long = 0,
    val repeatMode: Int = 0,
    val shuffle: Boolean = false,
    val sources: List<String> = emptyList(),
)

private val queueJson = Json { ignoreUnknownKeys = true }

fun encodeQueue(queue: QueueSnapshot): String = queueJson.encodeToString(
    StoredQueue.serializer(),
    StoredQueue(queue.trackIds, queue.shuffleOrder, queue.index, queue.positionMs, queue.repeatMode, queue.shuffle, queue.sources),
)

fun decodeQueue(text: String): QueueSnapshot? = runCatching {
    val stored = queueJson.decodeFromString(StoredQueue.serializer(), text)
    QueueSnapshot(stored.trackIds, stored.shuffleOrder, stored.index, stored.positionMs, stored.repeatMode, stored.shuffle, stored.sources)
}.getOrNull()

@Singleton
class PlayStore @Inject constructor(
    private val userDao: UserDao,
    private val catalog: CatalogDao,
    private val listening: ListeningSync,
    private val listenBrainz: ListenBrainzSync,
) {
    private val scope = CoroutineScope(SupervisorJob() + Dispatchers.IO)

    // A song began to play.
    fun started(trackId: String) {
        listening.nowPlaying(trackId)
        listenBrainz.nowPlaying(trackId)
    }

    fun record(trackId: String, startedAt: Long, playedMs: Long, durationMs: Long) {
        if (!countsAsPlay(playedMs, durationMs)) return
        scope.launch {
            val key = catalog.track(trackId)?.relinkKey ?: ""
            userDao.addPlay(PlayEventEntity(trackId = trackId, relinkKey = key, startedAt = startedAt, playedMs = playedMs, durationMs = durationMs))
        }
        listening.played(trackId, startedAt)
        listenBrainz.played(trackId, startedAt)
    }
}
