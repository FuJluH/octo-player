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

    fun attach(player: OutputSwitch, scope: CoroutineScope) {
        this.player = player
        this.scope = scope
    }

    fun detach() {
        job?.cancel()
        job = null
        player = null
        scope = null
    }

    // Whether the song is a station's that this keeps going, so Autoplay
    // leaves it be.
    fun keepsGoing(item: MediaItem?): Boolean =
        item?.queueSource is QueueSource.Station && discovery.keepsStationsGoing && item.entryId != emptyAfter

    fun check() {
        val player = player ?: return
        if (job?.isActive == true || !discovery.keepsStationsGoing || player.repeatMode != Player.REPEAT_MODE_OFF) return
        val items = List(player.mediaItemCount) { player.getMediaItemAt(it) }
        val station = stationToTopUp(items.map { it.queueSource }, player.currentMediaItemIndex) ?: return
        val last = items.last().entryId ?: return
        if (last == askedAfter) return
        askedAfter = last
        val after = stationSongsQueued(items, station, { it.queueSource }, { it.mediaId })
        job = scope?.launch { topUp(player, station, last, after) }
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
        // Only while the station still ends the queue as it did.
        val stillLast = player.mediaItemCount > 0 && player.getMediaItemAt(player.mediaItemCount - 1).entryId == last
        if (items.isEmpty() || !stillLast) {
            if (items.isEmpty()) emptyAfter = last
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
