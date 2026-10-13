package app.winters.octo.playback

import android.util.Log
import androidx.annotation.OptIn
import androidx.media3.common.MediaItem
import androidx.media3.common.Player
import androidx.media3.common.util.UnstableApi
import app.winters.octo.discovery.Discovery
import app.winters.octo.output.OutputSwitch
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Job
import kotlinx.coroutines.launch
import javax.inject.Inject
import javax.inject.Singleton

// Keeps a station going: when the queue ends with a station's songs and few
// of them are left to come, it asks the server for the station's next songs
// and adds them under the station's name. The service attaches its player
// and calls `check` whenever the song or the queue changes. Autoplay stands
// down for a station's songs while this keeps them going.
@OptIn(UnstableApi::class)
@Singleton
class StationRefill @Inject constructor(
    private val discovery: Discovery,
    private val playable: PlayableSongs,
) {
    private var player: OutputSwitch? = null
    private var scope: CoroutineScope? = null
    private var job: Job? = null

    // The last entry of the queue a top-up was asked after, so it asks once
    // for each, and the one that brought nothing, after which Autoplay may
    // carry on.
    private var askedAfter: String? = null
    private var emptyAfter: String? = null

    // Told when a top-up brought nothing, so Autoplay can look again.
    private var settled: () -> Unit = {}

    fun attach(player: OutputSwitch, scope: CoroutineScope, settled: () -> Unit = {}) {
        this.player = player
        this.scope = scope
        this.settled = settled
        askedAfter = null
        emptyAfter = null
    }

    fun detach() {
        job?.cancel()
        job = null
        player = null
        scope = null
        settled = {}
        askedAfter = null
        emptyAfter = null
    }

    // Whether the song is a station's that this keeps going, so Autoplay
    // leaves it be.
    fun keepsGoing(item: MediaItem?): Boolean =
        item?.queueSource is QueueSource.Station && discovery.keepsStationsGoing && item.entryId != emptyAfter

    fun check() {
        val player = player ?: return
        if (job?.isActive == true || !discovery.keepsStationsGoing || player.repeatMode != Player.REPEAT_MODE_OFF) return
        val items = List(player.mediaItemCount) { player.getMediaItemAt(it) }
        val current = player.currentMediaItemIndex
        if (current !in items.indices) return
        // The song on and those to come, in the order they will play, so a
        // shuffled queue counts what is really left.
        val ahead = (listOf(current) + upcoming(player)).map(items::get)
        val station = stationToTopUp(ahead.map { it.queueSource }, 0) ?: return
        val last = ahead.last().entryId ?: return
        if (last == askedAfter) return
        askedAfter = last
        val after = stationSongsQueued(items, station, { it.queueSource }, { it.mediaId })
        job = scope?.launch { topUp(player, station, last, after) }
    }

    // The entry that plays last, in play order.
    private fun lastToPlay(player: OutputSwitch): String? {
        val current = player.currentMediaItemIndex
        if (player.mediaItemCount == 0 || current < 0) return null
        return player.getMediaItemAt(upcoming(player).lastOrNull() ?: current).entryId
    }

    private suspend fun topUp(player: OutputSwitch, station: QueueSource.Station, last: String, after: List<String>) {
        val songs = try {
            discovery.stationMore(station.id, after)
        } catch (e: CancellationException) {
            throw e
        } catch (e: Exception) {
            Log.w("Octo", "station top-up failed: ${e.javaClass.simpleName}")
            emptyList()
        }
        val items = playable.items(songs.map { it.id }.filterNot { it in after }).map { it.withSource(station) }
        // Only while the queue still ends as it did.
        val stillLast = lastToPlay(player) == last
        if (items.isEmpty() || !stillLast) {
            if (items.isEmpty()) {
                emptyAfter = last
                settled()
            }
            Log.i("Octo", "station top-up: nothing added")
            return
        }
        val first = player.mediaItemCount
        player.addMediaItems(first, items)
        // The last song already ended while the server answered: carry on.
        if (player.playbackState == Player.STATE_ENDED) {
            player.seekTo(first, 0)
            player.play()
        }
        Log.i("Octo", "station top-up: added ${items.size}")
    }
}
