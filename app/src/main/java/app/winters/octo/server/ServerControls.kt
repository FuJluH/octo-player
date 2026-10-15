package app.winters.octo.server

import app.winters.octo.ui.family.offersRemoveOn
import android.util.Log
import app.winters.octo.catalog.CatalogDao
import app.winters.octo.catalog.SourceDao
import app.winters.octo.data.Session
import app.winters.octo.data.SessionRepository
import app.winters.octo.data.SessionState
import app.winters.octo.data.accountId
import app.winters.octo.subsonic.NowPlayingEntry
import app.winters.octo.subsonic.RadioStationDetails
import app.winters.octo.subsonic.Share
import app.winters.octo.subsonic.SubsonicException
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.Job
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.delay
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.SharingStarted
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.combine
import kotlinx.coroutines.flow.distinctUntilChangedBy
import kotlinx.coroutines.flow.stateIn
import kotlinx.coroutines.flow.update
import kotlinx.coroutines.launch
import javax.inject.Inject
import javax.inject.Singleton

private const val DAY_MS = 24 * 60 * 60 * 1000L

// How long a shared link lasts.
enum class ShareExpiry(val label: String, val lengthMs: Long?) {
    Never("Never", null),
    Day("1 day", DAY_MS),
    Week("1 week", 7 * DAY_MS),
    Month("1 month", 30 * DAY_MS),
}

// When a link made now stops working, in milliseconds since 1970, or null
// for never.
fun shareExpiresAt(expiry: ShareExpiry, now: Long): Long? = expiry.lengthMs?.let { now + it }

// Whether a failure means the server does not share at all: sharing is
// switched off (error 50 or 70), or the call is not there (HTTP 501).
fun sharingUnavailable(e: Throwable): Boolean = when (e) {
    is SubsonicException.NotFound -> true
    is SubsonicException.Server -> e.code == 50 || e.code == 70
    is SubsonicException.NotSubsonic -> e.message.orEmpty().contains("HTTP 501")
    else -> false
}

// A server album id from a library song's album, when the song came from
// that server's album list: "<source>:<album id>". Albums the copy made up
// from loose songs ("album:...") are not on the server.
fun serverAlbumIdOf(sourceId: String, albumId: String): String? =
    albumId.removePrefix("$sourceId:").takeIf { albumId.startsWith("$sourceId:") && !it.startsWith("album:") && it.isNotEmpty() }

// How far a library scan has come.
sealed interface ScanState {
    data object Idle : ScanState
    data class Scanning(val count: Long) : ScanState
    data object Finished : ScanState
    data class Failed(val message: String) : ScanState
}

// Who is listening now, as shown: other people, and this account on other
// players. The phone's own entry is left out.
fun othersListening(entries: List<NowPlayingEntry>, username: String, ourClient: String): List<NowPlayingEntry> =
    entries.filterNot { it.username.equals(username, ignoreCase = true) && it.playerName.orEmpty().startsWith(ourClient, ignoreCase = true) }

// Whether a radio station belongs to Octo itself: a station Octo makes from
// your listening carries its own id as its cover. The server still has the
// final say, refusing to change one.
fun looksGenerated(station: RadioStationDetails, isOcto: Boolean): Boolean = isOcto && station.coverArt == station.id

// Controls for the signed-in server beyond its library: shared links, a
// library scan, radio stations, and who is listening. Each is offered only
// when the server supports it; what the server refuses is remembered for
// the session.
@Singleton
class ServerControls @Inject constructor(
    private val sessions: SessionRepository,
    private val sources: SourceDao,
    private val catalog: CatalogDao,
    private val sync: ServerSync,
) {
    private val scope = CoroutineScope(SupervisorJob() + Dispatchers.IO)

    // Whether the signed-in user may run admin tasks, like a scan.
    private val _admin = MutableStateFlow(false)
    val admin: StateFlow<Boolean> = _admin

    // The kept servers that said they do not share, by id, for this run.
    private val noSharing = MutableStateFlow<Set<String>>(emptySet())

    // Whether links can be shared: a server is signed in and has not said no.
    val sharing: StateFlow<Boolean> = combine(sessions.state, noSharing) { state, refused ->
        state is SessionState.SignedIn && state.session.id !in refused
    }.stateIn(scope, SharingStarted.Eagerly, false)

    private val _scan = MutableStateFlow<ScanState>(ScanState.Idle)
    val scan: StateFlow<ScanState> = _scan
    private var scanJob: Job? = null

    // Stations each kept server refused to change, by its id and theirs,
    // for this run; a switch back finds them still marked.
    private val refusedStations = MutableStateFlow<Map<String, Set<String>>>(emptyMap())
    val readOnly: StateFlow<Set<String>> = combine(sessions.state, refusedStations) { state, refused ->
        refused[state.accountId].orEmpty()
    }.stateIn(scope, SharingStarted.Eagerly, emptySet())

    private fun markReadOnly(account: String, ids: Collection<String>) =
        refusedStations.update { it + (account to it[account].orEmpty() + ids) }

    init {
        // Each server in use asks once whether the user is an admin there.
        scope.launch {
            sessions.state.distinctUntilChangedBy { (it as? SessionState.SignedIn)?.session }.collect { state ->
                _admin.value = false
                scanJob?.cancel()
                _scan.value = ScanState.Idle
                val session = (state as? SessionState.SignedIn)?.session ?: return@collect
                val name = session.client.username
                if (name.isBlank()) return@collect
                _admin.value = try {
                    session.client.user(name).adminRole
                } catch (e: SubsonicException) {
                    false
                }
            }
        }
    }

    private fun session(): Session? = (sessions.state.value as? SessionState.SignedIn)?.session

    // The server's id for a library song on it, for sharing.
    suspend fun serverSongId(trackId: String): String? {
        val session = session() ?: return null
        return sources.copies(trackId).filter { it.sourceId == session.sourceId }.minOfOrNull { it.nativeId }
    }

    // The server's id of a song a family member can take out of their own
    // library: its copy the server marks as theirs, or on a server that marks
    // no song at all, its copy there. Null when there is none to offer.
    suspend fun removableId(trackId: String): String? {
        val session = session() ?: return null
        val copies = sources.copies(trackId).filter { it.sourceId == session.sourceId }
        if (copies.isEmpty()) return null
        val marks = sources.marksPersonal(session.sourceId)
        return copies.filter { offersRemoveOn(it.personal, marks) }.minOfOrNull { it.nativeId }
    }

    // The server's id for a library album, when its songs came from one
    // album there.
    suspend fun serverAlbumId(albumId: String): String? {
        val session = session() ?: return null
        val trackIds = catalog.albumTrackIds(albumId)
        if (trackIds.isEmpty()) return null
        val albums = trackIds.chunked(900).flatMap { sources.copiesOf(it) }
            .filter { it.sourceId == session.sourceId }
            .mapNotNull { serverAlbumIdOf(session.sourceId, it.albumId) }
        // The album most of its songs are in on the server.
        return albums.groupingBy { it }.eachCount().maxByOrNull { it.value }?.key
    }

    // Makes a link. Throws SubsonicException when the server cannot; one
    // that does not share is remembered, and sharing is offered no more.
    suspend fun share(ids: List<String>, description: String?, expiry: ShareExpiry): Share {
        val session = session() ?: throw SubsonicException.Server(0, "No server signed in")
        return remembering(session) {
            session.client.createShare(ids, description, shareExpiresAt(expiry, System.currentTimeMillis()))
        }
    }

    suspend fun shares(): List<Share> {
        val session = session() ?: return emptyList()
        return remembering(session) { session.client.shares() }
    }

    suspend fun deleteShare(id: String) {
        session()?.client?.deleteShare(id)
    }

    private suspend fun <T> remembering(session: Session, call: suspend () -> T): T = try {
        call()
    } catch (e: SubsonicException) {
        if (sharingUnavailable(e)) noSharing.update { it + session.id }
        throw e
    }

    // Asks the server to scan its folders, then follows it every 2 seconds.
    // When it is done, the library here is copied again.
    fun startScan() {
        if (_scan.value is ScanState.Scanning) return
        val session = session() ?: return
        scanJob?.cancel()
        scanJob = scope.launch {
            try {
                var status = session.client.startScan()
                _scan.value = ScanState.Scanning(status.count)
                // Some servers answer before the scan has begun, so until it
                // has been seen running, "not scanning" is believed only twice.
                var seenRunning = status.scanning
                var quiet = 0
                while (true) {
                    delay(SCAN_POLL_MS)
                    status = session.client.scanStatus()
                    if (status.scanning) {
                        seenRunning = true
                        quiet = 0
                        _scan.value = ScanState.Scanning(status.count)
                    } else if (seenRunning || ++quiet >= 2) {
                        break
                    }
                }
                _scan.value = ScanState.Finished
                sync.syncNow()
            } catch (e: CancellationException) {
                throw e
            } catch (e: SubsonicException) {
                Log.w("Octo", "scan failed: ${e.javaClass.simpleName}")
                _scan.value = ScanState.Failed(
                    if (e is SubsonicException.Server && e.code == 50) "Only an admin can scan this server." else "The scan could not start just now.",
                )
            }
        }
    }

    // Who else is listening right now.
    suspend fun listening(): List<NowPlayingEntry> {
        val session = session() ?: return emptyList()
        return othersListening(session.client.nowPlaying(), session.client.username, OUR_CLIENT_NAME)
    }

    // The server's radio stations, and which of them cannot be changed.
    suspend fun stations(): List<RadioStationDetails> {
        val session = session() ?: return emptyList()
        val stations = session.client.radioStationDetails()
        val generated = stations.filter { looksGenerated(it, session.isOcto) }.map { it.id }
        if (generated.isNotEmpty()) markReadOnly(session.id, generated)
        return stations
    }

    // Adds a station to the server in use: false when no server is signed
    // in, so nothing was asked.
    suspend fun addStation(streamUrl: String, name: String, homepage: String?): Boolean {
        val client = session()?.client ?: return false
        client.createRadioStation(streamUrl, name, homepage)
        return true
    }

    suspend fun updateStation(id: String, streamUrl: String, name: String, homepage: String?) = refusing(id) {
        session()?.client?.updateRadioStation(id, streamUrl, name, homepage)
    }

    suspend fun deleteStation(id: String) = refusing(id) { session()?.client?.deleteRadioStation(id) }

    // A station the server will not change (Octo's own answer error 70,
    // "read-only") is marked so, and its edit actions go away. Any other
    // refusal leaves the station as it was.
    private suspend fun refusing(id: String, call: suspend () -> Unit) {
        try {
            call()
        } catch (e: SubsonicException) {
            if (refusedAsReadOnly(e)) session()?.let { markReadOnly(it.id, listOf(id)) }
            throw e
        }
    }

    private companion object {
        const val SCAN_POLL_MS = 2_000L
    }
}

// Whether a refused change to a station says the station is read-only:
// error 70, which Octo answers for its own stations. "Not authorized"
// (error 50) is about the account, not the station.
fun refusedAsReadOnly(e: SubsonicException): Boolean = e is SubsonicException.NotFound
