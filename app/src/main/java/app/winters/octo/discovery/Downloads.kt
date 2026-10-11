package app.winters.octo.discovery

import android.app.Activity
import android.app.Application
import android.content.Context
import android.os.Bundle
import app.winters.octo.admin.AdminUnavailable
import app.winters.octo.admin.DownloadRecord
import app.winters.octo.admin.OctoAdmin
import app.winters.octo.catalog.CatalogDao
import app.winters.octo.catalog.FIND_PREFIX
import app.winters.octo.catalog.OnlineDao
import app.winters.octo.catalog.OnlineSongEntity
import app.winters.octo.catalog.TrackEntity
import app.winters.octo.catalog.isFind
import app.winters.octo.data.Session
import app.winters.octo.data.SessionRepository
import app.winters.octo.data.SessionState
import app.winters.octo.data.accountId
import app.winters.octo.server.ServerSync
import app.winters.octo.server.serverSourceId
import app.winters.octo.server.sourceId
import app.winters.octo.subsonic.Acquisition
import app.winters.octo.subsonic.OCTO_ACQUISITIONS
import app.winters.octo.subsonic.SubsonicException
import app.winters.octo.ui.common.Feedback
import app.winters.octo.ui.downloads.AskedSong
import dagger.Lazy
import dagger.hilt.android.qualifiers.ApplicationContext
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.Job
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.delay
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.SharingStarted
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.combine
import kotlinx.coroutines.flow.distinctUntilChanged
import kotlinx.coroutines.flow.drop
import kotlinx.coroutines.flow.filter
import kotlinx.coroutines.flow.first
import kotlinx.coroutines.flow.map
import kotlinx.coroutines.flow.stateIn
import kotlinx.coroutines.flow.update
import kotlinx.coroutines.launch
import okhttp3.HttpUrl
import java.util.concurrent.atomic.AtomicInteger
import javax.inject.Inject
import javax.inject.Singleton

// When to look for downloads in the library after asking for one, away
// from home: the server does not say when a download is done, so the
// library is copied again a little later, and once more for slow ones.
private val CHECK_AFTER_MS = listOf(2 * 60_000L, 8 * 60_000L)

// After this long a download that never arrived can be asked for again.
private const val GIVE_UP_MS = 24 * 60 * 60_000L

// On the home network, how often to look at what Octo has finished, for how
// long, and how many times to copy the library for one finished song while
// the server takes it in.
private const val WATCH_EVERY_MS = 20_000L
private const val WATCH_FOR_MS = 30 * 60_000L
private const val SYNCS_PER_SONG = 3

// Finds that have not come up for this long are let go.
private const val FORGET_MS = 30L * 24 * 60 * 60_000L

// How long a server that could not say how its downloads are going is
// believed, before it is asked again (it may have been updated meanwhile).
private const val RECHECK_SUPPORT_MS = 10 * 60_000L

enum class DownloadState { None, Requested, Done }

// Downloading songs found online into the library. On Octo, starring a find
// makes the server download it. Once a later copy of the library shows the
// song, the find is linked to it (not liked). A server that says
// how its downloads are going is asked every few seconds while any is on
// its way; others are checked on the admin pages or on a timer.
@Singleton
class Downloads @Inject constructor(
    @ApplicationContext context: Context,
    private val sessions: SessionRepository,
    private val online: OnlineDao,
    private val catalog: CatalogDao,
    private val sync: Lazy<ServerSync>,
    private val admin: OctoAdmin,
    private val feedback: Feedback,
    private val hint: AddHint,
    // The server downloads sheet, told when a song is asked for so its
    // list looks now. Lazy: it only follows, and nothing here waits on it.
    private val serverDownloads: Lazy<app.winters.octo.data.ServerDownloads>,
) {
    private val scope = CoroutineScope(SupervisorJob() + Dispatchers.IO)
    private var checks: Job? = null

    // Whether the server is being asked how its downloads are going.
    @Volatile
    private var following = false

    // Whether each server says how its downloads are going, and when it was asked.
    private val support = HashMap<String, Pair<Boolean, Long>>()

    private val arrivals = Arrivals()

    private val tracker = ProgressWatch(
        object : AcquisitionHost {
            override suspend fun waiting(): List<OnlineSongEntity> = watchedWaiting()

            override suspend fun acquisitions(): List<Acquisition>? {
                val session = session() ?: return null
                return try {
                    session.client.acquisitions()
                } catch (e: SubsonicException.Unreachable) {
                    throw e
                } catch (e: SubsonicException) {
                    // An older server without the call: back to the old ways.
                    noteSupport(session, false)
                    null
                }
            }

            override suspend fun takeIn(libraryId: String): String? = sync.get().takeInSong(libraryId)

            override suspend fun adopt(findId: String, trackId: String) {
                val find = online.song(findId) ?: return
                if (find.adoptedId.isNotEmpty()) return
                val track = catalog.tracksByIdsUnordered(listOf(trackId)).firstOrNull() ?: return
                adoptAs(find.id, track)
            }

            override suspend fun syncAndWait() {
                sync.get().syncNowAndWait()
            }
        },
    )

    // Every find asked for, and how its download is going.
    val phases: StateFlow<Map<String, DownloadPhase>> = combine(online.requestedFlow(), tracker.live) { rows, live ->
        val now = System.currentTimeMillis()
        rows.associate { it.id to phaseFor(it, live[it.id], now) }
    }.stateIn(scope, SharingStarted.Eagerly, emptyMap())

    // Finds asked for, by id, and whether each has arrived.
    val states: StateFlow<Map<String, DownloadState>> = phases
        .map { phases -> phases.mapValues { (_, phase) -> phase.state } }
        .stateIn(scope, SharingStarted.Eagerly, emptyMap())

    // Each find now in the library, by the library song it became. Null
    // until first read, so a row can tell a song that was already in the
    // library from one that arrives while it is shown.
    val adoptions: StateFlow<Map<String, String>?> = online.requestedFlow()
        .map(::adoptionsOf)
        .stateIn(scope, SharingStarted.Eagerly, null)

    // Songs asked for from this phone on the server in use that have not
    // reached the library, for the downloads pill.
    val asked: StateFlow<List<AskedSong>> = combine(online.requestedFlow(), sessions.state) { rows, state ->
        askedSongs(rows, (state as? SessionState.SignedIn)?.session?.sourceId)
    }.distinctUntilChanged().stateIn(scope, SharingStarted.Eagerly, emptyList())

    private val _arrived = MutableStateFlow(0)

    // Goes up by one each time downloads join the library, so pages that
    // hold what the server said can ask again.
    val arrived: StateFlow<Int> = _arrived

    init {
        (context.applicationContext as? Application)?.registerActivityLifecycleCallbacks(ForegroundCallbacks())
        tracker.foreground = false
        scope.launch { announceArrivals() }
        scope.launch { announceAlbumFailures() }
        scope.launch { resume() }
        // Another kept server in use: the last one's are no longer asked
        // about, and this one's own carry on being followed.
        scope.launch {
            sessions.state.filter { it !is SessionState.Loading }.map { it.accountId }.distinctUntilChanged().drop(1).collect {
                synchronized(this@Downloads) { checks?.cancel() }
                resume()
            }
        }
    }

    fun state(trackId: String): DownloadState = states.value[trackId] ?: DownloadState.None

    // A find's button is on screen until the answer is called, so its
    // progress is asked for more often. A button on screen also means the
    // app is in front.
    fun showing(trackId: String): () -> Unit {
        tracker.foreground = true
        return tracker.show(trackId)
    }

    // Asks the server to download one find. Answers whether it was asked.
    // A download that failed is asked for again the same way.
    suspend fun request(track: TrackEntity): Boolean {
        if (!isFind(track.id)) return false
        val client = client() ?: return false
        return try {
            client.star(listOf(track.id.removePrefix(FIND_PREFIX)))
            online.setRequested(track.id, System.currentTimeMillis())
            hint.added()
            arrivals.askedSong(track.id, track.title)
            tracker.retry(track.id)
            serverDownloads.get().wake()
            follow()
            true
        } catch (e: SubsonicException) {
            false
        }
    }

    // Asks the server to download a whole album found online, and follows
    // the songs from it that are listed.
    suspend fun requestAlbum(albumId: String, songs: List<TrackEntity>, title: String = ""): Boolean {
        val client = client() ?: return false
        return try {
            client.starAlbums(listOf(albumId))
            val now = System.currentTimeMillis()
            val finds = songs.filter { isFind(it.id) }
            finds.forEach { online.setRequested(it.id, now) }
            hint.added()
            val coming = finds.filter { state(it.id) != DownloadState.Done }
            arrivals.askedAlbum(title.ifBlank { coming.firstOrNull()?.album.orEmpty() }, coming.map { it.id })
            coming.forEach { tracker.retry(it.id) }
            serverDownloads.get().wake()
            follow()
            true
        } catch (e: SubsonicException) {
            false
        }
    }

    // A pull on a page: asks the server how its downloads are going now.
    suspend fun refreshProgress() {
        if (following) {
            tracker.wake()
            return
        }
        if (watchedWaiting().isNotEmpty() && reportsProgress()) follow()
    }

    // Runs after each copy of the server's library: a download that has
    // arrived is linked to its library song, and old finds are let go.
    suspend fun afterSync() {
        val client = client() ?: return
        val now = System.currentTimeMillis()
        val kept = sessions.servers.value.servers.mapNotNull { it.sourceId }
        online.prune(serverSourceId(client.primaryUrl), kept + serverSourceId(client.primaryUrl), now - FORGET_MS)
        val waiting = online.waiting().ifEmpty { return }
        val candidates = waiting.flatMap { titleKeys(it.title) }.distinct().chunked(900).flatMap { catalog.tracksWithKeys(it) }
        val adopted = adoptions(waiting, candidates.filter { !isFind(it.id) })
        for (find in waiting) adopted[find.id]?.let { adoptAs(find.id, it) }
    }

    // A find became this library song: the two are linked. Downloading is
    // not liking, so the song is not hearted; that stays the listener's call.
    private suspend fun adoptAs(findId: String, track: TrackEntity) {
        online.adopt(findId, track.id)
    }

    // Follows the downloads asked for: by asking the server how they are
    // going when it can say; otherwise by copying the library again once
    // Octo lists one as finished when its admin pages can be reached, or a
    // little later, and once more after that for slow ones.
    private fun follow() {
        synchronized(this) {
            if (following) {
                tracker.wake()
                return
            }
            checks?.cancel()
            checks = scope.launch {
                if (reportsProgress()) {
                    following = true
                    val done = try {
                        tracker.run()
                    } finally {
                        following = false
                    }
                    if (done) return@launch
                }
                val base = admin.locate()
                if (base != null) watch(base) else checkOnTimer()
            }
        }
    }

    // Downloads asked for before the app last closed carry on being
    // followed, on a server that says how they are going.
    private suspend fun resume() {
        if (sessions.state.first { it !is SessionState.Loading } !is SessionState.SignedIn) return
        if (watchedWaiting().isNotEmpty() && reportsProgress()) follow()
    }

    // The songs asked for lately on the server in use: another kept
    // server's are followed once it is in use again.
    private suspend fun watchedWaiting(): List<OnlineSongEntity> {
        val here = session()?.sourceId ?: return emptyList()
        val now = System.currentTimeMillis()
        return online.waiting().filter { it.sourceId == here && now - it.requestedAt < GIVE_UP_MS }
    }

    // Whether the signed-in server says how its downloads are going: from
    // what it listed at sign-in, or by asking, since it may have been
    // updated since.
    private suspend fun reportsProgress(): Boolean {
        val session = session() ?: return false
        if ("$OCTO_ACQUISITIONS:1" in session.extensions) return true
        val now = System.currentTimeMillis()
        synchronized(support) {
            support[session.sourceId]?.let { (yes, at) -> if (yes || now - at < RECHECK_SUPPORT_MS) return yes }
        }
        // Noted only when the server itself said.
        val yes = session.client.supportsIfKnown(OCTO_ACQUISITIONS) ?: return false
        noteSupport(session, yes)
        return yes
    }

    private fun noteSupport(session: Session, yes: Boolean) {
        synchronized(support) { support[session.sourceId] = yes to System.currentTimeMillis() }
    }

    // One quiet line when a song asked for in this run reaches the library,
    // or when the last song of an album asked for does.
    private suspend fun announceArrivals() {
        var known: Set<String>? = null
        online.requestedFlow().collect { rows ->
            val adopted = rows.filter { it.adoptedId.isNotEmpty() }.mapTo(HashSet()) { it.id }
            val before = known
            known = adopted
            val landed = if (before == null) emptySet() else adopted - before
            if (landed.isEmpty()) return@collect
            _arrived.update { it + 1 }
            landed.forEach { id -> arrivals.landed(id)?.let(feedback::done) }
        }
    }

    // An album whose last song failed is settled too.
    private suspend fun announceAlbumFailures() {
        var failed = emptySet<String>()
        tracker.live.collect { live ->
            val now = live.filterValues { it is DownloadPhase.Failed }.keys
            (now - failed).forEach { id -> arrivals.failed(id)?.let(feedback::show) }
            failed = now
        }
    }

    private suspend fun checkOnTimer() {
        var waited = 0L
        for (at in CHECK_AFTER_MS) {
            delay(at - waited)
            waited = at
            sync.get().syncNow()
        }
    }

    // Until every download asked for has arrived, or for half an hour.
    private suspend fun watch(base: HttpUrl) {
        val syncs = HashMap<String, Int>()
        val until = System.currentTimeMillis() + WATCH_FOR_MS
        while (System.currentTimeMillis() < until) {
            delay(WATCH_EVERY_MS)
            val waiting = watchedWaiting().ifEmpty { return }
            val finished = try {
                admin.downloads(base)
            } catch (e: AdminUnavailable) {
                continue
            }
            val due = waiting.filter { find -> finished.any { downloadMatches(find, it) } }
                .filter { (syncs[it.id] ?: 0) < SYNCS_PER_SONG }
            if (due.isNotEmpty()) {
                due.forEach { syncs[it.id] = (syncs[it.id] ?: 0) + 1 }
                sync.get().syncNow()
            }
        }
    }

    private fun session(): Session? = (sessions.state.value as? SessionState.SignedIn)?.session

    private fun client() = session()?.client

    // Whether any of the app's screens is in front: the server is asked
    // less often while none is.
    private inner class ForegroundCallbacks : Application.ActivityLifecycleCallbacks {
        private val started = AtomicInteger(0)

        override fun onActivityStarted(activity: Activity) {
            if (started.incrementAndGet() == 1) tracker.foreground = true
        }

        override fun onActivityStopped(activity: Activity) {
            if (started.decrementAndGet() <= 0) {
                started.set(0)
                tracker.foreground = false
            }
        }

        override fun onActivityCreated(activity: Activity, savedInstanceState: Bundle?) = Unit
        override fun onActivityResumed(activity: Activity) = Unit
        override fun onActivityPaused(activity: Activity) = Unit
        override fun onActivitySaveInstanceState(activity: Activity, outState: Bundle) = Unit
        override fun onActivityDestroyed(activity: Activity) = Unit
    }
}

// The library song each find arrived as: the first with the same title, the
// same kind of recording and the same artist, of about the same length when
// both are known. Finds not in the library yet are left out.
fun adoptions(waiting: List<OnlineSongEntity>, library: List<TrackEntity>): Map<String, TrackEntity> {
    val byTitle = TitleIndex(library, { it.title }, { it.artist })
    return waiting.mapNotNull { find ->
        byTitle.candidates(find.title, find.artist).firstOrNull { sameSong(find.title, find.artist, find.durationMs, it) }?.let { find.id to it }
    }.toMap()
}

// Whether a song Octo finished downloading is the one asked for: the same
// recording by the same artist.
fun downloadMatches(find: OnlineSongEntity, record: DownloadRecord): Boolean =
    sameRecording(record.title, record.artist, find.title, find.artist)

// The finds asked for on server `sourceId` that have not reached the
// library, by the id the server lists them under. None while signed out.
fun askedSongs(rows: List<OnlineSongEntity>, sourceId: String?): List<AskedSong> =
    if (sourceId == null) emptyList()
    else rows.filter { it.sourceId == sourceId && it.requestedAt > 0 && it.adoptedId.isEmpty() }
        .map { AskedSong(it.id.removePrefix(FIND_PREFIX), it.requestedAt) }

fun stateOf(row: OnlineSongEntity, now: Long): DownloadState = when {
    row.adoptedId.isNotEmpty() -> DownloadState.Done
    row.requestedAt > 0 && now - row.requestedAt < GIVE_UP_MS -> DownloadState.Requested
    else -> DownloadState.None
}
