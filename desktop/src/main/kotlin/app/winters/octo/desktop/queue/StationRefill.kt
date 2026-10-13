package app.winters.octo.desktop.queue

import app.winters.octo.desktop.player.DesktopPlayer
import app.winters.octo.desktop.player.PlayerState
import app.winters.octo.desktop.player.RepeatMode
import app.winters.octo.playback.QueueSource
import app.winters.octo.playback.stationSongsQueued
import app.winters.octo.playback.stationToTopUp
import app.winters.octo.subsonic.Song
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Job
import kotlinx.coroutines.flow.distinctUntilChanged
import kotlinx.coroutines.flow.map
import kotlinx.coroutines.launch
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow

// Keeps a station going, with the phone's rules: when few songs are left to
// come and a station's are among them, it asks the server for the
// station's next songs (`more`, given the station's songs already queued)
// and adds them at the end under the station's name. It asks once for each
// last entry of the queue. Only while `supported`: a server that cannot
// send them leaves the station to end, and Autoplay to carry on.
class StationRefill(
    private val player: DesktopPlayer,
    private val scope: CoroutineScope,
    private val supported: () -> Boolean,
    private val more: suspend (id: String, after: List<String>) -> List<Song>,
) {
    private var job: Job? = null

    // The last entry asked after, and the one that brought nothing, after
    // which Autoplay may carry on.
    @Volatile private var askedAfter: Long? = null
    @Volatile private var emptyAfter: Long? = null

    // Counts each top-up that brought nothing, so Autoplay looks again.
    private val _settled = MutableStateFlow(0)
    val settled: StateFlow<Int> = _settled.asStateFlow()

    fun start(): Job = scope.launch {
        player.state.map { due(it) }.distinctUntilChanged().collect { ask -> ask?.let(::topUp) }
    }

    // Whether this keeps the station of the song on going, so Autoplay
    // leaves it be.
    fun keepsGoing(state: PlayerState): Boolean {
        val current = state.current ?: return false
        val last = (state.upcoming.lastOrNull() ?: current).key
        return current.source is QueueSource.Station && supported() && last != emptyAfter
    }

    private data class Ask(val station: QueueSource.Station, val last: Long)

    private fun due(state: PlayerState): Ask? {
        val current = state.current ?: return null
        if (state.repeat != RepeatMode.Off || !supported()) return null
        val ahead = listOf(current) + state.upcoming
        val station = stationToTopUp(ahead.map { it.source }, 0) ?: return null
        return Ask(station, ahead.last().key)
    }

    private fun topUp(ask: Ask) {
        if (job?.isActive == true || ask.last == askedAfter) return
        askedAfter = ask.last
        val after = stationSongsQueued(player.state.value.queue, ask.station, { it.source }, { it.song.id })
        val running = scope.launch {
            val songs = runCatching { more(ask.station.id, after) }.getOrDefault(emptyList()).filterNot { it.id in after }
            val now = player.state.value
            // Only while the queue still ends where it did.
            val stillLast = (now.upcoming.lastOrNull() ?: now.current)?.key == ask.last
            if (songs.isEmpty()) {
                emptyAfter = ask.last
                _settled.value++
            }
            if (songs.isEmpty() || !stillLast) return@launch
            val ended = now.current != null && !now.playing && now.upcoming.isEmpty()
            player.addToQueue(songs, ask.station)
            if (ended) player.state.value.upcoming.firstOrNull()?.let { player.skipTo(it.key) }
        }
        job = running
        // The queue may have changed while the server answered: ask again
        // for where it ends now.
        running.invokeOnCompletion { scope.launch { due(player.state.value)?.let(::topUp) } }
    }
}
