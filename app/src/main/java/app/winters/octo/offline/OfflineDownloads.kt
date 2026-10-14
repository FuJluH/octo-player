package app.winters.octo.offline

import app.winters.octo.ui.family.offlineCopiesAllowed
import app.winters.octo.ui.family.OFFLINE_COPIES_OFF
import app.winters.octo.ui.common.Feedback
import app.winters.octo.family.family
import app.winters.octo.family.FamilyHub
import android.content.Context
import android.net.ConnectivityManager
import android.net.Network
import android.os.Environment
import android.util.Log
import androidx.annotation.OptIn
import androidx.core.net.toUri
import androidx.media3.common.C
import androidx.media3.common.util.UnstableApi
import androidx.media3.datasource.DataSpec
import androidx.media3.datasource.HttpDataSource
import app.winters.octo.catalog.CatalogDao
import app.winters.octo.catalog.CatalogMerge
import app.winters.octo.data.SessionRepository
import app.winters.octo.data.SessionState
import app.winters.octo.playback.StreamUnavailable
import app.winters.octo.playback.Streams
import app.winters.octo.playback.bitrateOf
import app.winters.octo.playback.compareQuality
import app.winters.octo.playback.streamRequest
import app.winters.octo.playback.streamUri
import dagger.hilt.android.qualifiers.ApplicationContext
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.ExperimentalCoroutinesApi
import kotlinx.coroutines.FlowPreview
import kotlinx.coroutines.Job
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.channels.Channel
import kotlinx.coroutines.delay
import kotlinx.coroutines.ensureActive
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.SharingStarted
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.combine
import kotlinx.coroutines.flow.debounce
import kotlinx.coroutines.flow.distinctUntilChanged
import kotlinx.coroutines.flow.first
import kotlinx.coroutines.flow.flatMapLatest
import kotlinx.coroutines.flow.flowOf
import kotlinx.coroutines.flow.map
import kotlinx.coroutines.flow.stateIn
import kotlinx.coroutines.launch
import kotlinx.coroutines.sync.Mutex
import kotlinx.coroutines.sync.withLock
import kotlinx.coroutines.withContext
import java.io.File
import java.io.FileOutputStream
import java.io.IOException
import java.util.concurrent.ConcurrentHashMap
import javax.inject.Inject
import javax.inject.Singleton

// How often a running download writes how far it has got.
private const val PROGRESS_EVERY_MS = 500L

// How long rule changes settle before the downloads follow them.
private const val RULES_SETTLE_MS = 1_500L

// How many times a download that broke off with a connection is tried again
// before it is marked failed, and how long between tries.
private const val TRIES = 3
private const val RETRY_AFTER_MS = 5_000L

// How long the file of a download removed by hand is set aside, so the
// removal can be taken back. A little longer than the undo line stays up.
private const val UNDO_KEEP_MS = 10_000L

// A download let go of, with its file set aside while it can still come back.
private data class SetAside(val row: DownloadEntity, val file: File?)

// Whether a removal can be taken back: every finished download kept its
// file. Unfinished ones only need to wait in line again.
fun canRestore(removed: List<Pair<DownloadStatus, Boolean>>): Boolean =
    removed.isNotEmpty() && removed.none { (state, fileKept) -> state == DownloadStatus.Done && !fileKept }

// Server songs kept on the phone as real files, one at a time, in the order
// asked for. Asked for by hand, or kept in step with rules: Liked songs, and
// chosen playlists. The queue lives in the database, so it carries on when
// the app starts again. No foreground service: downloads run while the app
// is alive, and pick up where they were next time.
@OptIn(UnstableApi::class, FlowPreview::class, ExperimentalCoroutinesApi::class)
@Singleton
class OfflineDownloads @Inject constructor(
    @ApplicationContext private val context: Context,
    private val dao: DownloadDao,
    private val catalog: CatalogDao,
    private val merge: CatalogMerge,
    private val sessions: SessionRepository,
    private val streams: Streams,
    private val settings: OfflineSettings,
    private val saved: StreamCache,
    // A family member whose account has offline copies off gets none from
    // that server; files already on the phone stay.
    private val family: FamilyHub,
    private val feedback: Feedback,
) {
    private val scope = CoroutineScope(SupervisorJob() + Dispatchers.IO)
    private val lock = Mutex()
    private val wake = Channel<Unit>(Channel.CONFLATED)
    private var started = false

    // The download running now, so removing it can stop it.
    @Volatile private var running: Pair<String, Job>? = null
    private val tries = ConcurrentHashMap<String, Int>()

    // The "Download on Wi-Fi only" setting as it is now.
    @Volatile private var wifiOnly = OfflinePrefs().wifiOnly

    // What the rules want, as last worked out.
    @Volatile private var lastWanted: Map<String, Set<String>>? = null

    // Every download, by library song.
    val byTrack: StateFlow<Map<String, DownloadEntity>> = dao.allFlow()
        .map { rows -> rows.associateBy { it.trackId } }
        .stateIn(scope, SharingStarted.Eagerly, emptyMap())

    // Library songs downloaded and ready to play.
    val done: StateFlow<Set<String>> = byTrack
        .map { rows -> rows.filterValues { it.state == DownloadStatus.Done }.keys }
        .distinctUntilChanged()
        .stateIn(scope, SharingStarted.Eagerly, emptySet())

    // The downloads page: the server in use's downloads.
    val rows: Flow<List<DownloadRow>> = combine(dao.rows(), sessions.state) { rows, state ->
        val source = (state as? SessionState.SignedIn)?.session?.sourceId
        rows.filter { it.sourceId == source }
    }

    fun start() {
        if (started) return
        started = true
        scope.launch {
            // Files set aside by a removal the app closed on before it was final.
            asideDir().listFiles()?.forEach { it.delete() }
            dao.requeueInterrupted()
            // The saved songs open in the background, not when a song first plays.
            saved.refreshUsed()
            watchRules()
        }
        scope.launch { runQueue() }
        // A new connection, a changed setting or a sign-in may let waiting downloads go.
        context.getSystemService(ConnectivityManager::class.java).registerDefaultNetworkCallback(
            object : ConnectivityManager.NetworkCallback() {
                override fun onAvailable(network: Network) = poke()
                override fun onCapabilitiesChanged(network: Network, caps: android.net.NetworkCapabilities) = poke()
            },
        )
        scope.launch {
            settings.prefs.map { it.wifiOnly }.distinctUntilChanged().collect {
                wifiOnly = it
                poke()
            }
        }
        scope.launch { sessions.state.collect { poke() } }
    }

    // Downloads these library songs, the ones that can be: on a server and
    // not on the phone.
    fun download(trackIds: List<String>) {
        scope.launch {
            lock.withLock {
                val held = heldByTrack()
                val manual = trackIds.distinct().associateWith { held[it].orEmpty() + Reasons.MANUAL }
                val (fresh, known) = manual.entries.partition { it.key !in held }
                known.forEach { (trackId, reasons) -> setReasons(trackId, reasons) }
                add(fresh.associate { it.key to it.value })
            }
            poke()
        }
    }

    fun downloadAlbum(albumId: String) {
        scope.launch { download(catalog.albumTrackIds(albumId)) }
    }

    fun downloadPlaylist(playlistId: String) {
        scope.launch { download(dao.playlistTrackIds(playlistId)) }
    }

    // Lets go of a download asked for by hand. One a rule also keeps stays.
    // When the download itself goes, `gone` hears a way to bring it back,
    // as long as its file could be set aside for a moment.
    fun remove(trackId: String, gone: (restore: () -> Unit) -> Unit = {}) {
        scope.launch {
            val aside = lock.withLock {
                val reasons = heldByTrack()[trackId] ?: return@withLock null
                val left = reasons - Reasons.MANUAL
                if (left.isEmpty()) {
                    setAside(trackId)
                } else {
                    setReasons(trackId, left)
                    null
                }
            } ?: return@launch
            // The set aside files go for good once the undo has passed.
            scope.launch {
                delay(UNDO_KEEP_MS)
                lock.withLock { aside.forEach { it.file?.delete() } }
            }
            if (canRestore(aside.map { it.row.state to (it.file != null) })) gone { restore(aside) }
        }
    }

    // Takes back a removal: finished files move back, anything unfinished
    // waits to download again. One asked for again meanwhile just stays
    // wanted by hand.
    private fun restore(aside: List<SetAside>) {
        scope.launch {
            lock.withLock {
                val rows = aside
                    .filter { dao.get(it.row.sourceId, it.row.serverId) == null }
                    .map { (row, file) ->
                        when {
                            row.state == DownloadStatus.Done && file != null && file.renameTo(File(row.path)) -> row
                            row.state == DownloadStatus.Failed -> row
                            else -> row.copy(state = DownloadStatus.Queued, progress = 0f, path = "", sizeBytes = 0)
                        }
                    }
                if (rows.isNotEmpty()) dao.upsert(rows)
                val held = heldByTrack()
                aside.map { it.row.trackId }.distinct().forEach { trackId ->
                    held[trackId]?.let { setReasons(trackId, it + Reasons.MANUAL) }
                }
            }
            poke()
        }
    }

    // Removes a song's downloads, moving each finished file aside rather
    // than deleting it. A file that cannot be moved is deleted.
    private suspend fun setAside(trackId: String): List<SetAside> = dao.forTrack(trackId).map { row ->
        running?.let { (key, job) -> if (key == key(row)) job.cancel() }
        dao.delete(row.sourceId, row.serverId)
        val file = File(row.path).takeIf { row.path.isNotEmpty() && it.exists() }
        val kept = file?.let { File(asideDir(), "${System.nanoTime()}-${it.name}") }?.takeIf { file.renameTo(it) }
        if (file != null && kept == null) file.delete()
        SetAside(row, kept)
    }

    // Stops keeping anything: the rules are switched off and every file goes.
    fun removeAll() {
        scope.launch {
            settings.clearRules()
            lock.withLock {
                dao.all().forEach { deleteRow(it) }
            }
        }
    }

    // Tries a failed download again.
    fun retry(trackId: String) {
        scope.launch {
            dao.forTrack(trackId).filter { it.state == DownloadStatus.Failed }.forEach {
                tries.remove(key(it))
                dao.setState(it.sourceId, it.serverId, DownloadStatus.Queued, 0f)
            }
            poke()
        }
    }

    // Deletes the downloads of a server taken off the list, files and all.
    suspend fun forgetSource(sourceId: String) {
        lock.withLock { dao.all().filter { it.sourceId == sourceId }.forEach { deleteRow(it) } }
    }

    fun setKeepLiked(on: Boolean) {
        scope.launch { settings.setKeepLiked(on) }
    }

    fun setPlaylistKept(playlistId: String, kept: Boolean) {
        scope.launch { settings.setPlaylistKept(playlistId, kept) }
    }

    // After each copy of the server's library: downloads follow their songs
    // to new ids, and songs a rule wants that have just arrived download.
    suspend fun afterSync() {
        refreshSwapped()
        lastWanted?.let { applyRules(it) }
        poke()
    }

    // A download whose server file is now another one (the server swapped
    // it for a better copy, say, under the same id) downloads again. Until
    // it has, the song streams, so the old file never plays. Downloads made
    // before the server's size was noted have it noted here.
    private suspend fun refreshSwapped() = merge.betweenRebuilds {
        val source = serverInUse() ?: return@betweenRebuilds
        lock.withLock {
            for (file in dao.doneFiles(source)) {
                when (checkDownload(file)) {
                    KeptCopyCheck.Keep -> Unit
                    KeptCopyCheck.Note -> file.serverSize?.let { dao.noteFileSize(file.sourceId, file.serverId, it) }
                    KeptCopyCheck.Refetch -> dao.setState(file.sourceId, file.serverId, DownloadStatus.Queued, 0f)
                }
            }
        }
    }

    // The finished downloads of these library songs whose files are there.
    // One whose file has gone waits to download again.
    suspend fun playableCopies(trackIds: List<String>): Map<String, DownloadEntity> = withContext(Dispatchers.IO) {
        val rows = trackIds.distinct().chunked(900).flatMap { dao.doneFor(it) }
        val (present, gone) = rows.partition { it.path.isNotEmpty() && File(it.path).isFile }
        if (gone.isNotEmpty()) {
            gone.forEach { dao.setState(it.sourceId, it.serverId, DownloadStatus.Queued, 0f) }
            poke()
        }
        present.associateBy { it.trackId }
    }

    private fun poke() {
        wake.trySend(Unit)
    }

    // Rules

    private suspend fun watchRules() {
        settings.prefs.map { it.keepLiked to it.keptPlaylists }
            .distinctUntilChanged()
            .flatMapLatest { (keepLiked, playlists) ->
                val liked = if (keepLiked) dao.likedIds() else flowOf(emptyList())
                val members = if (playlists.isEmpty()) flowOf(emptyList()) else dao.playlistMembers(playlists.toList())
                combine(liked, members) { likedIds, songs -> wantedByRules(keepLiked, likedIds, songs) }
            }
            .debounce(RULES_SETTLE_MS)
            .collect { wanted ->
                lastWanted = wanted
                applyRules(wanted)
                poke()
            }
    }

    // Never while the library is being rebuilt, when song ids are changing.
    private suspend fun applyRules(wanted: Map<String, Set<String>>) = merge.betweenRebuilds {
        lock.withLock {
            dao.relink()
            val held = heldByTrack()
            val fresh = wanted.keys.filter { it !in held }
            val downloadable = fresh.chunked(900).flatMap { dao.downloadable(it) }.toSet()
            val plan = planDownloads(held, wanted, downloadable)
            if (plan.isEmpty) return@withLock
            plan.remove.forEach { delete(it) }
            plan.change.forEach { (trackId, reasons) -> setReasons(trackId, reasons) }
            add(plan.add)
        }
    }

    // The downloads of the server in use. Another kept server's files stay
    // as they are until it is in use again: its songs are not in the
    // library meanwhile, and would look unwanted.
    private suspend fun heldByTrack(): Map<String, Set<String>> {
        val source = serverInUse() ?: return emptyMap()
        return dao.all().filter { it.sourceId == source }.groupBy { it.trackId }.mapValues { (_, rows) -> rows.flatMapTo(HashSet()) { it.reasons } }
    }

    private fun serverInUse(): String? = (sessions.state.value as? SessionState.SignedIn)?.session?.sourceId

    private suspend fun setReasons(trackId: String, reasons: Set<String>) {
        dao.forTrack(trackId).forEach { dao.setReason(it.sourceId, it.serverId, Reasons.join(reasons)) }
    }

    // Queues new downloads, each from the best copy on the server.
    private suspend fun add(wanted: Map<String, Set<String>>) {
        if (wanted.isEmpty()) return
        val downloadable = wanted.keys.chunked(900).flatMap { dao.downloadable(it) }.toSet()
        val copies = downloadable.toList().chunked(900).flatMap { dao.serverCopies(it) }.groupBy { it.mergedId }
        val now = System.currentTimeMillis()
        val refused = refusedSource()
        val rows = wanted.filterKeys { it in downloadable }.mapNotNull { (trackId, reasons) ->
            val copy = copies[trackId]?.reduce { best, next -> if (compareQuality(next, best) > 0) next else best } ?: return@mapNotNull null
            DownloadEntity(
                trackId = trackId,
                sourceId = copy.sourceId,
                serverId = copy.nativeId,
                path = "",
                sizeBytes = 0,
                format = null,
                state = DownloadStatus.Queued,
                progress = 0f,
                addedAt = now,
                reason = Reasons.join(reasons),
                title = copy.title,
                artist = copy.artist,
            )
        }
        val (kept, held) = rows.partition { it.sourceId != refused }
        if (held.isNotEmpty()) feedback.show(OFFLINE_COPIES_OFF)
        kept.chunked(500).forEach { dao.upsert(it) }
    }

    // The server in use, when its family plan has offline copies off for
    // this account; null when new downloads may go.
    private suspend fun refusedSource(): String? {
        val session = (sessions.state.value as? SessionState.SignedIn)?.session ?: return null
        if (!session.family) return null
        return session.sourceId.takeUnless { offlineCopiesAllowed(family.plan()) }
    }

    private suspend fun delete(trackId: String) {
        dao.forTrack(trackId).forEach { deleteRow(it) }
    }

    private suspend fun deleteRow(row: DownloadEntity) {
        running?.let { (key, job) -> if (key == key(row)) job.cancel() }
        dao.delete(row.sourceId, row.serverId)
        if (row.path.isNotEmpty()) File(row.path).delete()
    }

    // The queue

    private suspend fun runQueue() {
        while (true) {
            val next = if (canDownloadNow()) serverInUse()?.let { dao.nextQueued(it) } else null
            if (next == null) {
                wake.receive()
                continue
            }
            val job = scope.launch { fetch(next) }
            running = key(next) to job
            job.join()
            running = null
        }
    }

    private suspend fun canDownloadNow(): Boolean {
        if (sessions.state.value !is SessionState.SignedIn) return false
        return if (settings.prefs.first().wifiOnly) streams.onWifi() else streams.online()
    }

    private suspend fun fetch(row: DownloadEntity) {
        val key = key(row)
        val copy = dao.serverCopy(row.sourceId, row.serverId)
        if (copy == null) {
            dao.setState(row.sourceId, row.serverId, DownloadStatus.Failed, 0f)
            return
        }
        dao.setState(row.sourceId, row.serverId, DownloadStatus.Downloading, 0f)
        val request = streamRequest(copy.mimeType, bitrateOf(copy), settings.prefs.first().downloadQuality)
        val ref = streams.refFor(copy).pin(request)
        val dir = downloadDir()
        val format = request.mimeType(copy.mimeType)
        val target = File(dir, downloadFileName(copy.artist, copy.title, row.sourceId, row.serverId, format))
        val part = File(dir, target.name + ".part")
        try {
            val size = copyInto(streamUri(ref), part) { progress ->
                dao.setState(row.sourceId, row.serverId, DownloadStatus.Downloading, progress)
            }
            if (dao.get(row.sourceId, row.serverId) == null) {
                part.delete()
                return
            }
            if (target.exists()) target.delete()
            if (!part.renameTo(target)) throw IOException("Could not save the file")
            dao.finish(row.sourceId, row.serverId, target.absolutePath, size, format, copy.sizeBytes?.takeIf { it > 0 })
            // A song downloaded again under a new name lets its old file go.
            if (row.path.isNotEmpty() && row.path != target.absolutePath) File(row.path).delete()
            tries.remove(key)
        } catch (e: CancellationException) {
            part.delete()
            throw e
        } catch (e: IOException) {
            part.delete()
            Log.w("Octo", "download failed: ${e.javaClass.simpleName}")
            val tried = (tries[key] ?: 0) + 1
            tries[key] = tried
            when {
                // No connection: it waits for one, however long that takes.
                e is StreamUnavailable || !streams.online() -> {
                    tries.remove(key)
                    dao.setState(row.sourceId, row.serverId, DownloadStatus.Queued, 0f)
                }
                // The server said no; asking again will not change that.
                e is HttpDataSource.InvalidResponseCodeException || tried >= TRIES ->
                    dao.setState(row.sourceId, row.serverId, DownloadStatus.Failed, 0f)
                else -> {
                    dao.setState(row.sourceId, row.serverId, DownloadStatus.Queued, 0f)
                    delay(RETRY_AFTER_MS)
                }
            }
        }
    }

    // Reads a server song into a file, telling how far it has got. Returns
    // how many bytes were written.
    private suspend fun copyInto(uri: String, file: File, onProgress: suspend (Float) -> Unit): Long = withContext(Dispatchers.IO) {
        val source = streams.downloadSource()
        try {
            val length = source.open(DataSpec(uri.toUri()))
            var written = 0L
            var reported = 0L
            val buffer = ByteArray(64 * 1024)
            FileOutputStream(file).use { out ->
                while (true) {
                    ensureActive()
                    val read = source.read(buffer, 0, buffer.size)
                    if (read == C.RESULT_END_OF_INPUT) break
                    out.write(buffer, 0, read)
                    written += read
                    val now = System.currentTimeMillis()
                    if (now - reported >= PROGRESS_EVERY_MS) {
                        reported = now
                        // Leaving Wi-Fi pauses a download that waits for it.
                        if (wifiOnly && !streams.onWifi()) throw StreamUnavailable("Off Wi-Fi")
                        if (length > 0) onProgress((written.toFloat() / length).coerceIn(0f, 0.99f))
                    }
                }
            }
            written
        } finally {
            source.close()
        }
    }

    // App storage on the phone's music drive, which other apps and the
    // phone's music library do not look in, or inside the app if there is
    // no such drive.
    private fun downloadDir(): File {
        val base = context.getExternalFilesDir(Environment.DIRECTORY_MUSIC) ?: File(context.filesDir, "music")
        val dir = File(base, "Octo")
        dir.mkdirs()
        File(dir, ".nomedia").takeIf { !it.exists() }?.createNewFile()
        return dir
    }

    // Where removed files wait out their undo.
    private fun asideDir(): File = File(downloadDir(), ".removed").apply { mkdirs() }

    private fun key(row: DownloadEntity) = "${row.sourceId}|${row.serverId}"
}
