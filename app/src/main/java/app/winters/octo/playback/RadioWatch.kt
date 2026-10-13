package app.winters.octo.playback

import androidx.annotation.OptIn
import androidx.media3.common.Metadata
import androidx.media3.common.Player
import androidx.media3.common.util.UnstableApi
import androidx.media3.extractor.metadata.icy.IcyInfo
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.launch

// The song a stream names in its ICY metadata; its title is null when the
// stream names none.
internal data class IcyTitle(val title: String?)

// The ICY part of some metadata, or null when it has none.
@OptIn(UnstableApi::class)
internal fun icyTitleOf(metadata: Metadata): IcyTitle? =
    (0 until metadata.length()).map(metadata::get).filterIsInstance<IcyInfo>().lastOrNull()?.let { IcyTitle(it.title) }

// Watches the station that plays: the song its stream names becomes the
// item's title, with the station's name under it, so the player, the
// notification and the lock screen all show it. (A stream that drops is
// opened again by its loader: see ReconnectingRadio.)
@OptIn(UnstableApi::class)
internal class RadioWatch(
    private val player: Player,
    private val scope: CoroutineScope,
) : Player.Listener {
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
}
