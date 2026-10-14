package app.winters.octo.serverupdate

import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Job
import kotlinx.coroutines.channels.Channel
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.update
import kotlinx.coroutines.isActive
import kotlinx.coroutines.launch
import kotlinx.coroutines.withTimeoutOrNull

// The release the listener chose Later for, kept per server.
interface LaterStore {
    suspend fun dismissed(server: String): String?

    suspend fun dismiss(server: String, tag: String)
}

// Follows the server in use's update state: asks once when bound, then
// every few hours, every two seconds while an update is under way, and at
// once when asked to (the server page opening). `onFinished` runs once an
// update this app followed has brought the new release in, to read the
// server's facts again.
class ServerUpdateWatcher(
    private val scope: CoroutineScope,
    private val later: LaterStore,
    private val now: () -> Long = System::currentTimeMillis,
    private val onFinished: suspend () -> Unit = {},
) {
    private val _track = MutableStateFlow(UpdateTrack())
    val track: StateFlow<UpdateTrack> = _track

    private class Bound(val server: String, val calls: ServerUpdateCalls)

    @Volatile private var bound: Bound? = null
    private var job: Job? = null
    private val wake = Channel<Unit>(Channel.CONFLATED)

    // Follows this server, or none. Binding the server already followed
    // changes nothing; another starts afresh.
    @Synchronized
    fun bind(server: String?, calls: ServerUpdateCalls?) {
        if (server != null && server == bound?.server) return
        job?.cancel()
        job = null
        bound = null
        _track.value = UpdateTrack()
        if (server == null || calls == null) return
        val here = Bound(server, calls)
        bound = here
        job = scope.launch {
            val dismissed = runCatching { later.dismissed(server) }.getOrNull()
            _track.update { it.copy(dismissed = dismissed) }
            while (isActive) {
                val result = calls.read()
                if (bound !== here) break
                var finished = false
                _track.update { old ->
                    old.read(result, now()).also { finished = it.outcome is UpdateOutcome.Done && old.outcome !is UpdateOutcome.Done }
                }
                if (finished) runCatching { onFinished() }
                withTimeoutOrNull(_track.value.nextReadMs) { wake.receive() }
            }
        }
    }

    // Asks the server now, as the server page opens.
    fun refresh() {
        wake.trySend(Unit)
    }

    // Asks the server to bring in the newest release.
    fun updateNow() {
        val here = bound ?: return
        val track = _track.value
        val status = track.status ?: return
        val tag = status.latest?.tag ?: return
        if (!status.canUpdate || track.starting || track.watch != null) return
        _track.update { it.copy(starting = true, startProblem = null, outcome = null) }
        scope.launch {
            val result = here.calls.start(tag)
            if (bound !== here) return@launch
            _track.update { it.started(result) }
            wake.trySend(Unit)
        }
    }

    // Puts the news away until a release newer than this one.
    fun later() {
        val here = bound ?: return
        var tag: String? = null
        _track.update { it.later().also { after -> tag = after.dismissed } }
        val dismissed = tag ?: return
        scope.launch { runCatching { later.dismiss(here.server, dismissed) } }
    }

    // The listener has read how the update ended.
    fun closeOutcome() {
        _track.update { it.closeOutcome() }
    }
}
