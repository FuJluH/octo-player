package app.winters.octo.ui.imports

import androidx.compose.runtime.Stable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue
import app.winters.octo.subsonic.IMPORT_FILE_MAX_BYTES
import app.winters.octo.subsonic.ImportActions
import app.winters.octo.subsonic.ImportAnswer
import app.winters.octo.subsonic.ImportListDetail
import app.winters.octo.subsonic.ImportOverview
import app.winters.octo.subsonic.ImportServiceLink
import app.winters.octo.subsonic.ImportServices
import app.winters.octo.subsonic.OCTO_IMPORTS
import app.winters.octo.subsonic.OCTO_IMPORTS_FILES
import app.winters.octo.subsonic.SubsonicClient
import app.winters.octo.subsonic.SubsonicException
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Job
import kotlinx.coroutines.delay
import kotlinx.coroutines.isActive
import kotlinx.coroutines.launch

// The Import view's state, for the server in use, on the phone and the
// desktop alike: the server's overview, the services to get music from and
// where a "Get my music" visit stands, the list opened, and the last thing
// the server said. The server does the work; this asks it, every few
// seconds while the view is open and something moves.
@Stable
class ImportModel(
    private val client: () -> SubsonicClient?,
    private val scope: CoroutineScope,
    private val openUrl: (String) -> Unit = {},
    private val busyPollMs: Long = IMPORTS_BUSY_POLL_MS,
    private val idlePollMs: Long = IMPORTS_IDLE_POLL_MS,
) {
    var overview by mutableStateOf<ImportOverview?>(null)
        private set

    // The services to get music from, on a server that lists them (octoImports
    // version 2); null on an older one, which shows the link and the lists alone.
    var services by mutableStateOf<ImportServices?>(null)
        private set

    // Where a "Get my music" visit stands.
    var step by mutableStateOf<ImportStep>(ImportStep.Choose)
        private set

    // Whether the server lists octoImports version 2, or null until it said.
    private var filesKnown: Boolean? = null

    // Why the server could not be read, or that it has no imports.
    var problem by mutableStateOf<String?>(null)
        private set

    var openId by mutableStateOf<String?>(null)
        private set
    var detail by mutableStateOf<ImportListDetail?>(null)
        private set

    // What the server said about the last thing asked, in its own words.
    var said by mutableStateOf<String?>(null)
        private set
    var working by mutableStateOf(false)
        private set

    private var watching: Job? = null

    // While the page shows: read now, then again soon while anything moves.
    fun watch() {
        if (watching?.isActive == true) return
        watching = scope.launch {
            while (isActive) {
                refresh()
                delay(if (overview?.moving() == true) busyPollMs else idlePollMs)
            }
        }
    }

    fun stop() {
        watching?.cancel()
        watching = null
    }

    // Another server: nothing of this one's stays.
    fun forget() {
        stop()
        overview = null
        services = null
        filesKnown = null
        step = ImportStep.Choose
        problem = null
        openId = null
        detail = null
        said = null
    }

    suspend fun refresh() {
        val client = client() ?: return
        try {
            overview = client.imports()
            problem = null
            readServices(client)
        } catch (e: SubsonicException.Unreachable) {
            problem = "Octo can't reach the server right now."
        } catch (e: SubsonicException) {
            // An Octo from before imports passes the call on to Navidrome, which does not know it.
            problem = if (overview == null) "This server has no imports yet. Update Octo on the server to use it." else e.message
        }
        val id = openId ?: return
        runCatching { client.importList(id) }.onSuccess { if (openId == id) detail = it }
    }

    // The services, once the server says it has them. Asked once a server;
    // a server that could not say is asked again next time.
    private suspend fun readServices(client: SubsonicClient) {
        if (filesKnown == null) filesKnown = client.supportsIfKnown(OCTO_IMPORTS, OCTO_IMPORTS_FILES)
        if (filesKnown != true || services != null) return
        try {
            services = client.importServices()
        } catch (e: SubsonicException) {
            // Asked again on the next read.
        }
    }

    // ---- Get my music ---------------------------------------------------------------------

    // A service's tile tapped: its export page opens.
    fun choose(service: ImportServiceLink) {
        if (step is ImportStep.Sending) return
        said = null
        openExport(service)
    }

    // Opens the service's export page on TuneMyMusic in the browser and
    // waits for the file. Any other address is refused.
    fun openExport(service: ImportServiceLink) {
        val url = tuneMyMusicUrl(service.exportUrl)
        if (url == null) {
            said = NOT_TUNEMYMUSIC
            step = ImportStep.Choose
            return
        }
        openUrl(url)
        step = ImportStep.Waiting(service)
    }

    // Waits for a file with no service picked: one saved earlier.
    fun useAFile() {
        if (step is ImportStep.Sending) return
        said = null
        step = ImportStep.Waiting(null)
    }

    // Back to the grid.
    fun backToServices() {
        if (step is ImportStep.Sending) return
        step = ImportStep.Choose
    }

    // Sends a list file to the server. The server's words show either way;
    // a refused file leaves the wait open to try another.
    fun sendFile(name: String, bytes: ByteArray) {
        val refused = when {
            !isImportFileName(name) -> NOT_A_LIST_FILE
            bytes.isEmpty() -> FILE_EMPTY
            bytes.size > IMPORT_FILE_MAX_BYTES -> FILE_TOO_BIG
            else -> null
        }
        if (refused != null) {
            said = refused
            return
        }
        send(name) { it.importFile(name, bytes) }
    }

    // Sends a typed or pasted list to the server.
    fun sendText(text: String, name: String = PASTED_LIST_NAME) {
        if (text.isBlank()) return
        val called = name.ifBlank { PASTED_LIST_NAME }
        send(called) { it.importText(called, text) }
    }

    // Something that went wrong before a file could be sent, like a file
    // that could not be read, in words to show.
    fun tell(words: String) {
        said = words
    }

    private fun send(name: String, call: suspend (SubsonicClient) -> ImportAnswer) {
        val client = client() ?: return
        if (step is ImportStep.Sending) return
        val waiting = step.service
        step = ImportStep.Sending(waiting, name)
        said = null
        scope.launch {
            try {
                val answer = call(client)
                if (answer.ok) {
                    // The overview read after the send says whether the new lists wait for approval.
                    refresh()
                    step = ImportStep.Sent(answer.message, overview?.approvalLine())
                    return@launch
                } else {
                    said = answer.message.ifBlank { "The server could not read that file." }
                    step = ImportStep.Waiting(waiting)
                }
            } catch (e: SubsonicException) {
                said = e.message ?: "Octo could not reach the server."
                step = ImportStep.Waiting(waiting)
            }
            refresh()
        }
    }

    fun keepPlaylist(id: String, on: Boolean) = act(ImportActions.PLAYLIST, mapOf("id" to id, "on" to on.toString()))
    fun getMissing(id: String, on: Boolean) = act(ImportActions.FETCH, mapOf("id" to id, "on" to on.toString()))
    fun getSongs(id: String, keys: List<String>) = act(ImportActions.SONGS, mapOf("id" to id), keys)
    fun readList(id: String) = act(ImportActions.REFRESH, mapOf("id" to id))
    fun pause() = act(ImportActions.PAUSE)
    fun resume() = act(ImportActions.RESUME)
    fun retry(keys: List<String> = emptyList()) = act(ImportActions.RETRY, keys = keys)
    fun skip(key: String) = act(ImportActions.SKIP, keys = listOf(key))
    fun clearFinished() = act(ImportActions.CLEAR)

    fun remove(id: String) {
        if (openId == id) close()
        act(ImportActions.REMOVE, mapOf("id" to id))
    }

    // A public playlist or album by its link; the new list opens.
    fun addLink(url: String) = act(ImportActions.ADD_LINK, mapOf("url" to url.trim())) { answer -> answer.listId?.let(::open) }

    fun open(id: String) {
        if (openId != id) detail = null
        openId = id
        scope.launch { refresh() }
    }

    fun close() {
        openId = null
        detail = null
    }

    private fun act(
        action: String,
        params: Map<String, String> = emptyMap(),
        keys: List<String> = emptyList(),
        then: (app.winters.octo.subsonic.ImportAnswer) -> Unit = {},
    ) {
        val client = client() ?: return
        scope.launch {
            working = true
            try {
                val answer = client.importAction(action, params, keys)
                said = answer.message
                if (answer.ok) then(answer)
            } catch (e: SubsonicException) {
                said = e.message ?: "Octo could not reach the server."
            } finally {
                working = false
            }
            refresh()
        }
    }
}
