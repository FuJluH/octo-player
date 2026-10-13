package app.winters.octo.playback

import android.os.SystemClock
import androidx.annotation.OptIn
import androidx.media3.common.MediaItem
import androidx.media3.common.Metadata
import androidx.media3.common.Player
import androidx.media3.common.util.UnstableApi
import androidx.media3.extractor.metadata.icy.IcyInfo
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.launch

// How many times a station's stream may end on its own and be opened again
// within `windowMs` before the queue is let move on.
internal class RadioDrops(private val max: Int = 3, private val windowMs: Long = 2 * 60 * 1000L) {
    private val times = ArrayDeque<Long>()

    fun allow(now: Long): Boolean {
        while (times.isNotEmpty() && now - times.first() > windowMs) times.removeFirst()
        if (times.size >= max) return false
        times.addLast(now)
        return true
    }
}

// The song a stream names in its ICY metadata; its title is null when the
// stream names none.
internal data class IcyTitle(val title: String?)

// The ICY part of some metadata, or null when it has none.
@OptIn(UnstableApi::class)
internal fun icyTitleOf(metadata: Metadata): IcyTitle? =
    (0 until metadata.length()).map(metadata::get).filterIsInstance<IcyInfo>().lastOrNull()?.let { IcyTitle(it.title) }

// Watches the station that plays. The song its stream names becomes the
// item's title, with the station's name under it, so the player, the
// notification and the lock screen all show it. A live stream never ends
// on its own, so one that does lost its connection: it is opened again, a
// few times, rather than moving on to the next song.
@OptIn(UnstableApi::class)
internal class RadioWatch(
    private val player: Player,
    private val scope: CoroutineScope,
    private val now: () -> Long = SystemClock::elapsedRealtime,
) : Player.Listener {
    private val drops = RadioDrops()
    private var last: MediaItem? = player.currentMediaItem

    override fun onMetadata(metadata: Metadata) {
        val icy = icyTitleOf(metadata) ?: return
        val item = player.currentMediaItem ?: return
        if (!isRadio(item.mediaId)) return
        val updated = item.withRadioLines(icy.title) ?: return
        val index = player.currentMediaItemIndex
        scope.launch {
            // Still the same station in the same place.
            if (player.currentMediaItemIndex == index && player.currentMediaItem?.entryId == item.entryId) {
                player.replaceMediaItem(index, updated)
            }
        }
    }

    override fun onMediaItemTransition(mediaItem: MediaItem?, reason: Int) {
        val before = last
        last = mediaItem
        if (reason != Player.MEDIA_ITEM_TRANSITION_REASON_AUTO || before == null || !isRadio(before.mediaId)) return
        val entry = before.entryId ?: return
        if (!drops.allow(now())) return
        scope.launch {
            val index = (0 until player.mediaItemCount).firstOrNull { player.getMediaItemAt(it).entryId == entry } ?: return@launch
            player.seekToDefaultPosition(index)
            player.prepare()
        }
    }

    override fun onPlaybackStateChanged(playbackState: Int) {
        if (playbackState != Player.STATE_ENDED) return
        val item = player.currentMediaItem ?: return
        if (!isRadio(item.mediaId) || !drops.allow(now())) return
        scope.launch {
            if (player.currentMediaItem?.entryId != item.entryId) return@launch
            player.seekToDefaultPosition(player.currentMediaItemIndex)
            player.prepare()
        }
    }
}
