package app.winters.octo.server

import android.app.Activity
import android.app.Application
import android.content.Context
import android.os.Bundle
import android.os.SystemClock
import android.util.Log
import androidx.datastore.preferences.core.MutablePreferences
import androidx.datastore.preferences.core.Preferences
import androidx.datastore.preferences.core.edit
import androidx.datastore.preferences.core.intPreferencesKey
import androidx.datastore.preferences.core.longPreferencesKey
import androidx.datastore.preferences.core.stringPreferencesKey
import androidx.datastore.preferences.preferencesDataStore
import app.winters.octo.catalog.CatalogMerge
import app.winters.octo.listening.FavouriteSync
import app.winters.octo.listening.ListeningSync
import app.winters.octo.catalog.SourceDao
import app.winters.octo.data.Session
import app.winters.octo.data.SessionRepository
import app.winters.octo.data.SessionState
import app.winters.octo.data.StoredServer
import app.winters.octo.data.userMessage
import app.winters.octo.discovery.Downloads
import app.winters.octo.offline.OfflineDownloads
import app.winters.octo.playlists.PlaylistSync
import app.winters.octo.subsonic.Album
import app.winters.octo.subsonic.Library
import app.winters.octo.subsonic.Song
import app.winters.octo.subsonic.SubsonicException
import app.winters.octo.subsonic.readLibrary
import dagger.hilt.android.qualifiers.ApplicationContext
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.Job
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.async
import kotlinx.coroutines.awaitAll
import kotlinx.coroutines.cancelAndJoin
import kotlinx.coroutines.coroutineScope
import kotlinx.coroutines.delay
import kotlinx.coroutines.isActive
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.combine
import kotlinx.coroutines.flow.distinctUntilChanged
import kotlinx.coroutines.flow.filter
import kotlinx.coroutines.flow.first
import kotlinx.coroutines.flow.map
import kotlinx.coroutines.launch
import kotlinx.coroutines.sync.Mutex
import kotlinx.coroutines.sync.withLock
import okhttp3.HttpUrl.Companion.toHttpUrlOrNull
import java.util.concurrent.ConcurrentHashMap
import java.util.concurrent.atomic.AtomicInteger
import javax.inject.Inject
import javax.inject.Singleton

// When a server's library was last copied, and how much came.
data class LastSync(val sourceId: String, val at: Long, val songs: Int, val albums: Int)

private val Context.syncData by preferencesDataStore("server_sync")

// A copy older than this is made again when the app starts or comes to the
// front.
private const val STALE_MS = 6 * 60 * 60 * 1000L

// Raised whenever a copy learns to keep something new from the server, so
// the next start copies the library again whatever its age. Copies made
// before this was kept count as version 1; version 2 keeps genres, credits,
// original years, MusicBrainz ids and the other details; version 3 keeps
// each album's release types, for the artist page's shelves; version 4
// leaves out songs the server marks as outside the library, which a
// download that arrived could bring in with its album; version 5 gives
// covers a fallback for when the server answers with its stand-in picture,
// and marks only songs the server calls explicit, not every song of an
// album holding one; version 6 keeps which songs are in a family member's
// own library.
private const val ROWS_VERSION = 6

// Whose library is in place: a kept server's id, or this for the phone's
// music alone.
const val PHONE_LIBRARY = "phone"

// The source a kept server's music is kept under.
val StoredServer.sourceId: String? get() = serverUrl.toHttpUrlOrNull()?.let(::serverSourceId)

// Keeps a copy of each kept server's library beside the phone's music:
// copied after signing in, at app start or on coming to the front when the
// last copy is old, and when asked. In between, while the app is in front,
// music the server took in since is brought in album by album (look), and
// a search brings in what it finds that the copy lacks (takeInArriving).
// Only the server in use joins the library (CatalogMerge); the
// others' copies wait for a switch, which then needs no new copy unless it
// is old. Removing a server takes its copy away. Two accounts on one
// address share one copy, made again when the other one is in use.
@Singleton
class ServerSync @Inject constructor(
    @ApplicationContext private val context: Context,
    private val sessions: SessionRepository,
    private val sources: SourceDao,
    private val merge: CatalogMerge,
    private val listening: ListeningSync,
    private val favourites: FavouriteSync,
    private val downloads: Downloads,
    private val playlists: PlaylistSync,
    private val offline: OfflineDownloads,
) {
    private val scope = CoroutineScope(SupervisorJob() + Dispatchers.Default)
    private val dropLock = Mutex()
    private var job: Job? = null
    private var started = false

    // One take-in or look at a time, so two never put in the same rows.
    private val takeInLock = Mutex()

    // When each kept server was last looked at for new music, by its id,
    // on the clock that counts time since the phone started.
    private val lookedAt = ConcurrentHashMap<String, Long>()

    // Whether any of the app's screens is in front, and the looks made
    // while one is.
    @Volatile private var foreground = false
    private var looks: Job? = null

    private val _syncing = MutableStateFlow(false)
    val syncing: StateFlow<Boolean> = _syncing

    // Why the last copy failed, in words; null once one works.
    private val _problem = MutableStateFlow<String?>(null)
    val problem: StateFlow<String?> = _problem

    // Whose library the screens show now: the id of the server in use once
    // its music has joined, or PHONE_LIBRARY. Null until the first is in place.
    private val _ready = MutableStateFlow<String?>(null)
    val ready: StateFlow<String?> = _ready

    // The last copy of the server in use.
    val last: Flow<LastSync?> = combine(sessions.state, context.syncData.data) { state, p ->
        val session = (state as? SessionState.SignedIn)?.session ?: return@combine null
        LastSync(
            sourceId = p[sourceKey(session.id)] ?: return@combine null,
            at = p[syncedAtKey(session.id)] ?: return@combine null,
            songs = p[songsKey(session.id)] ?: 0,
            albums = p[albumsKey(session.id)] ?: 0,
        )
    }.distinctUntilChanged()

    fun start() {
        if (started) return
        started = true
        (context.applicationContext as? Application)?.registerActivityLifecycleCallbacks(ForegroundCallbacks())
        scope.launch {
            // The kept servers are known once the saved sign-in is read.
            sessions.state.first { it !is SessionState.Loading }
            takeInOneServersRecord()
            sessions.state
                .filter { it !is SessionState.Loading }
                .map { (it as? SessionState.SignedIn)?.session }
                .distinctUntilChanged { a, b -> a?.id == b?.id && a?.sourceId == b?.sourceId }
                .collect { session -> arrived(session) }
        }
    }

    // Another server (or none) is in use: a copy of the last one stops, the
    // library becomes the new one's, and its copy is made again when old.
    private suspend fun arrived(session: Session?) {
        synchronized(this) { job }?.cancelAndJoin()
        _problem.value = null
        dropUnkept()
        val want = session?.sourceId.orEmpty()
        if (context.syncData.data.first()[LIBRARY] != want) {
            merge.rebuild()
            context.syncData.edit { it[LIBRARY] = want }
        }
        _ready.value = session?.id ?: PHONE_LIBRARY
        if (session == null) return
        if (stale(session)) {
            syncNow()
        } else if (foreground) {
            scope.launch { quietly { look(session) } }
        }
    }

    // Whether the server's copy should be made again: never made, made by an
    // older version, old, or made for another account on the same address.
    private suspend fun stale(session: Session): Boolean {
        val p = context.syncData.data.first()
        val at = p[syncedAtKey(session.id)] ?: return true
        return p[rowsKey(session.id)] != ROWS_VERSION ||
            p[copyOfKey(session.sourceId)] != session.id ||
            System.currentTimeMillis() - at > STALE_MS
    }

    // Starts a copy unless one is already running.
    fun syncNow() {
        synchronized(this) {
            if (job?.isActive == true) return
            job = scope.launch { sync() }
        }
    }

    // Starts a copy unless one is already running, and waits for it to end.
    // Answers why it failed, in words, or null when it worked.
    suspend fun syncNowAndWait(): String? {
        syncNow()
        synchronized(this) { job }?.join()
        return _problem.value
    }

    // Copies the library afresh, stopping a copy already running: for when
    // what the copy should hold has changed, like the chosen music folder.
    fun syncAgain() {
        scope.launch {
            synchronized(this@ServerSync) { job }?.cancelAndJoin()
            syncNow()
        }
    }

    // Signs out of the server in use. Its music leaves the library; its copy
    // stays for signing in again. Nothing on the server changes.
    fun disconnect() {
        scope.launch {
            synchronized(this@ServerSync) { job }?.cancelAndJoin()
            sessions.signOut()
        }
    }

    // Takes a kept server off the list, and its copy of the library with it
    // (unless another kept account shares the address). Nothing on the
    // server changes.
    suspend fun remove(id: String): StoredServer? {
        if (sessions.state.value.let { it is SessionState.SignedIn && it.session.id == id }) {
            synchronized(this) { job }?.cancelAndJoin()
        }
        val gone = sessions.remove(id) ?: return null
        dropUnkept()
        context.syncData.edit { p -> listOf(syncedAtKey(id), songsKey(id), albumsKey(id), rowsKey(id), sourceKey(id), scanKey(id)).forEach { p.remove(it) } }
        lookedAt.remove(id)
        return gone
    }

    // Puts one song from the server into the library at once, with the rest
    // of its album as the server has it now, ahead of the next full copy:
    // for a download that just finished. Answers the library song it
    // became, or null when the server could not give it.
    suspend fun takeInSong(serverId: String): String? {
        val session = signedIn() ?: return null
        val song = try {
            session.client.song(serverId)
        } catch (e: SubsonicException) {
            return null
        }
        takeInLock.withLock { takeIn(session, listOf(song), listOfNotNull(song.albumId?.takeIf(String::isNotEmpty))) }
        return sources.libraryLinks(session.sourceId, listOf(serverId)).firstOrNull()?.trackId
    }

    // Takes in music a search found on the server that the library does not
    // have yet (see Arriving), with the albums it is on, ahead of the next
    // full copy. It goes on to the end even when the one asking stops
    // waiting, so the next search finds it in place. A copy already running
    // brings it all, so that is waited for instead. Answers whether any of
    // it is in the library now.
    suspend fun takeInArriving(arriving: Arriving): Boolean {
        if (arriving.isEmpty) return false
        val session = signedIn() ?: return false
        return scope.async {
            takeInLock.withLock {
                synchronized(this@ServerSync) { job }?.join()
                if (signedIn()?.sourceId != session.sourceId) return@withLock false
                takeIn(session, arriving.songs, arriving.albumIds())
                val songIds = arriving.songs.map { it.id }
                val albumIds = arriving.albums.map { it.id }
                (songIds.isNotEmpty() && sources.libraryLinks(session.sourceId, songIds).isNotEmpty()) ||
                    (albumIds.isNotEmpty() && sources.knownAlbums(session.sourceId, albumIds).isNotEmpty())
            }
        }.await()
    }

    // Puts server songs and albums into the library ahead of the next full
    // copy: each album in `albumIds` read as the server has it now, with
    // all its songs, and each of `songs` too (alone when its album could
    // not be read). `listed` gives an album's details as the server's album
    // lists give them, where known, so the next look sees the same counts.
    // Only what the library lacks goes in, then the library is merged
    // again; the next full copy puts everything right. Answers whether
    // anything went in. Callers hold takeInLock.
    private suspend fun takeIn(
        session: Session,
        songs: List<Song>,
        albumIds: List<String>,
        listed: Map<String, Album> = emptyMap(),
    ): Boolean {
        val client = session.client
        val sourceId = session.sourceId
        val read = coroutineScope {
            albumIds.distinct().map { id ->
                async {
                    try {
                        client.album(id)
                    } catch (e: SubsonicException) {
                        null
                    }
                }
            }.awaitAll().filterNotNull()
        }
        val all = (read.flatMap { it.song } + songs).filterNot { it.isExternal }.distinctBy { it.id }
        if (all.isEmpty()) return false
        val rows = buildServerCatalog(sourceId, Library(all, read.map { listed[it.id] ?: it.asListed() }, emptyList()))
        val wanted = rowsToTakeIn(
            rows,
            haveSongs = all.map { it.id }.chunked(900).flatMap { sources.libraryLinks(sourceId, it) }.mapTo(HashSet()) { it.serverId },
            haveAlbums = sources.knownAlbums(sourceId, rows.albums.map { it.nativeId }).toSet(),
            readAlbums = read.mapTo(HashSet()) { it.id },
            haveArtists = sources.knownArtists(rows.artists.map { it.id }).toSet(),
        )
        if (wanted.tracks.isEmpty() && wanted.albums.isEmpty()) return false
        sources.insertArtists(wanted.artists)
        sources.insertAlbums(wanted.albums)
        sources.insertTracks(wanted.tracks)
        merge.rebuild()
        return true
    }

    // Brings the server in use up to date while the app is in front: copies
    // it whole when its copy is old (the same rule as at start), and
    // otherwise looks for new music. Either at most once a
    // NEW_MUSIC_LOOK_MS, so a copy that keeps failing is not tried on and on.
    private suspend fun freshen() {
        val session = signedIn() ?: return
        // Until the server's music is in place, arrived() decides.
        if (_ready.value != session.id) return
        if (!stale(session)) return look(session)
        val now = SystemClock.elapsedRealtime()
        if (!newMusicLookDue(lookedAt[session.id], now)) return
        lookedAt[session.id] = now
        syncNow()
    }

    // One look at the server for music the copy lacks (see
    // lookForNewMusic): new albums, and albums with songs added, are taken
    // in; too many at once copies the whole library instead. Never while a
    // copy runs, and never twice within NEW_MUSIC_LOOK_MS.
    private suspend fun look(session: Session) {
        if (synchronized(this) { job }?.isActive == true) return
        val now = SystemClock.elapsedRealtime()
        if (!newMusicLookDue(lookedAt[session.id], now)) return
        lookedAt[session.id] = now
        takeInLock.withLock {
            if (signedIn()?.id != session.id) return
            val seen = context.syncData.data.first()[scanKey(session.id)]
            val look = try {
                lookForNewMusic(session.client, seen) { ids ->
                    ids.chunked(900).flatMap { sources.albumSongCounts(session.sourceId, it) }.associate { it.serverId to it.songCount }
                }
            } catch (e: CancellationException) {
                throw e
            } catch (e: Exception) {
                Log.w("Octo", "new music look failed: ${e.javaClass.simpleName}")
                return
            }
            when (val found = look.found) {
                NewMusic.None -> Unit
                is NewMusic.TakeIn -> {
                    val ids = found.albums.map { it.id }
                    takeIn(session, emptyList(), ids, found.albums.associateBy { it.id })
                    Log.i("Octo", "new music look: took in ${found.albums.size} albums")
                    // An album the server would not give is left for the
                    // next look, which then reads on whatever the scan says.
                    val kept = sources.albumSongCounts(session.sourceId, ids).associate { it.serverId to it.songCount }
                    if (found.albums.any { kept[it.id] != it.songCount }) return
                }
                NewMusic.CopyAll -> {
                    // The copy notes the server's scan itself.
                    syncNow()
                    return
                }
            }
            val scan = look.scan
            if (scan != null && scan != seen) context.syncData.edit { it[scanKey(session.id)] = scan }
        }
    }

    private fun signedIn(): Session? = (sessions.state.value as? SessionState.SignedIn)?.session

    // A look that goes wrong is only noted; the next one tries again.
    private suspend fun quietly(block: suspend () -> Unit) {
        try {
            block()
        } catch (e: CancellationException) {
            throw e
        } catch (e: Exception) {
            Log.w("Octo", "new music look failed: ${e.javaClass.simpleName}")
        }
    }

    private suspend fun sync() {
        val session = (sessions.state.value as? SessionState.SignedIn)?.session ?: return
        val client = session.client
        val sourceId = session.sourceId
        _syncing.value = true
        try {
            val started = SystemClock.elapsedRealtime()
            // When the server last read its folders, before the copy, so a
            // look afterwards reads on only once it has read them again.
            val scan = lastScanOf(client)
            val catalog = buildServerCatalog(sourceId, client.readLibrary())
            sources.replaceSource(sourceId, catalog.tracks, catalog.albums, catalog.artists)
            val library = merge.rebuild()
            // Brings likes and stars together, and sends any plays still waiting.
            listening.afterSync()
            // The same for favourite albums and artists.
            favourites.afterSync()
            // Songs downloaded since the last copy join the library as liked.
            downloads.afterSync()
            // Brings the server's playlists and the phone's copies together.
            playlists.afterSync()
            // Downloads follow their songs, and songs kept downloaded that just arrived start.
            offline.afterSync()
            context.syncData.edit { p ->
                p[sourceKey(session.id)] = sourceId
                p[syncedAtKey(session.id)] = System.currentTimeMillis()
                p[songsKey(session.id)] = catalog.tracks.size
                p[albumsKey(session.id)] = catalog.albums.size
                p[rowsKey(session.id)] = ROWS_VERSION
                p[copyOfKey(sourceId)] = session.id
                if (scan != null) p[scanKey(session.id)] = scan else p.remove(scanKey(session.id))
            }
            lookedAt[session.id] = SystemClock.elapsedRealtime()
            _problem.value = null
            // Counts only, like the phone scan's line.
            Log.i(
                "Octo",
                "server sync: ${catalog.tracks.size} tracks, ${catalog.albums.size} albums, " +
                    "${catalog.artists.size} artists, ${SystemClock.elapsedRealtime() - started} ms; " +
                    "library ${library.tracks.size} tracks, ${library.albums.size} albums, ${library.artists.size} artists",
            )
        } catch (e: CancellationException) {
            throw e
        } catch (e: Exception) {
            _problem.value = e.userMessage()
            Log.w("Octo", "server sync failed: ${e.javaClass.simpleName}")
        } finally {
            _syncing.value = false
        }
    }

    // Removes the music of every server no longer kept. A signed-out server
    // is still kept, so signing in again needs no new copy.
    private suspend fun dropUnkept() = dropLock.withLock {
        val kept = sessions.servers.value.servers.mapNotNullTo(HashSet()) { it.sourceId }
        val gone = sources.sourceIds().filter { isServerSource(it) && it !in kept }
        // Their songs are no library songs already; the rows just go.
        gone.forEach { sources.deleteSource(it) }
        if (gone.isNotEmpty()) context.syncData.edit { p -> gone.forEach { p.remove(copyOfKey(it)) } }
        // Playlists kept with a server that is gone stay, only on the phone.
        playlists.keepOnly(kept)
    }

    // An older version kept one record of its one server's copy. It belongs
    // to the kept account on that address, the one in use first.
    private suspend fun takeInOneServersRecord() {
        val kept = sessions.servers.value
        context.syncData.edit { p ->
            val source = p[SOURCE_ID] ?: return@edit
            val owner = (listOfNotNull(kept.inUse) + kept.servers).firstOrNull { it.sourceId == source }
            if (owner != null && p[syncedAtKey(owner.id)] == null) {
                p[sourceKey(owner.id)] = source
                p[SYNCED_AT]?.let { p[syncedAtKey(owner.id)] = it }
                p[songsKey(owner.id)] = p[SONGS] ?: 0
                p[albumsKey(owner.id)] = p[ALBUMS] ?: 0
                p[ROWS]?.let { p[rowsKey(owner.id)] = it }
                p[copyOfKey(source)] = owner.id
                // The library the older version merged holds that server.
                if (p[LIBRARY] == null) p[LIBRARY] = source
            }
            p.forgetOneServersRecord()
        }
    }

    private fun MutablePreferences.forgetOneServersRecord() {
        listOf<Preferences.Key<*>>(SOURCE_ID, SYNCED_AT, SONGS, ALBUMS, ROWS).forEach { remove(it) }
    }

    // The app came to the front: the server in use is brought up to date
    // now and every NEW_MUSIC_LOOK_MS while it stays there. Nothing is
    // asked while no screen is showing.
    private fun cameToFront() {
        foreground = true
        synchronized(this) {
            looks?.cancel()
            looks = scope.launch {
                while (isActive) {
                    quietly { freshen() }
                    delay(NEW_MUSIC_LOOK_MS)
                }
            }
        }
    }

    private fun wentAway() {
        foreground = false
        synchronized(this) {
            looks?.cancel()
            looks = null
        }
    }

    private inner class ForegroundCallbacks : Application.ActivityLifecycleCallbacks {
        private val started = AtomicInteger(0)

        override fun onActivityStarted(activity: Activity) {
            if (started.incrementAndGet() == 1) cameToFront()
        }

        override fun onActivityStopped(activity: Activity) {
            if (started.decrementAndGet() <= 0) {
                started.set(0)
                wentAway()
            }
        }

        override fun onActivityCreated(activity: Activity, savedInstanceState: Bundle?) = Unit
        override fun onActivityResumed(activity: Activity) = Unit
        override fun onActivityPaused(activity: Activity) = Unit
        override fun onActivitySaveInstanceState(activity: Activity, outState: Bundle) = Unit
        override fun onActivityDestroyed(activity: Activity) = Unit
    }

    private companion object {
        // The server source the library was last merged with, "" for none.
        val LIBRARY = stringPreferencesKey("library_server")

        // Each kept server's last copy, by its id.
        fun sourceKey(id: String) = stringPreferencesKey("source_id@$id")
        fun syncedAtKey(id: String) = longPreferencesKey("synced_at@$id")
        fun songsKey(id: String) = intPreferencesKey("songs@$id")
        fun albumsKey(id: String) = intPreferencesKey("albums@$id")
        fun rowsKey(id: String) = intPreferencesKey("rows_version@$id")

        // When the server last read its folders, as it said at the last copy
        // or look.
        fun scanKey(id: String) = stringPreferencesKey("last_scan@$id")

        // Which account's copy an address's rows are.
        fun copyOfKey(sourceId: String) = stringPreferencesKey("copy_of@$sourceId")

        // Where an older version kept its one server's record.
        val SOURCE_ID = stringPreferencesKey("source_id")
        val SYNCED_AT = longPreferencesKey("synced_at")
        val SONGS = intPreferencesKey("songs")
        val ALBUMS = intPreferencesKey("albums")
        val ROWS = intPreferencesKey("rows_version")
    }
}
