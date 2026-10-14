package app.winters.octo.playback

import androidx.annotation.OptIn
import androidx.media3.common.Metadata
import androidx.media3.common.Player
import androidx.media3.common.util.UnstableApi
import androidx.media3.extractor.metadata.icy.IcyInfo
import app.winters.octo.liveradio.icyArtworkField
import app.winters.octo.liveradio.OnAir
import app.winters.octo.liveradio.SongLookup
import app.winters.octo.liveradio.icyFields
import app.winters.octo.liveradio.liveShown
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.launch
import java.nio.ByteBuffer
import java.nio.charset.CharacterCodingException
import java.nio.charset.CodingErrorAction

// The ICY part of some metadata, or null when it has none.
@OptIn(UnstableApi::class)
internal fun icyReadOf(metadata: Metadata): IcyRead? =
    (0 until metadata.length()).map(metadata::get).filterIsInstance<IcyInfo>().lastOrNull()?.let { icyReadOf(it.rawMetadata, it.title, it.url) }

// What one ICY block names, read from the block as the stream sent it, so a
// quote inside a value stays in it and every field is there. A block with
// no StreamTitle in it keeps the title and address the player read.
internal fun icyReadOf(raw: ByteArray?, title: String?, url: String?): IcyRead {
    val fields = raw?.takeIf { it.isNotEmpty() }?.let { icyFields(icyText(it)) }.orEmpty()
    if ("StreamTitle" !in fields) return IcyRead(title, url ?: icyArtworkField(fields))
    return IcyRead(fields["StreamTitle"], icyArtworkField(fields) ?: url)
}

// A block's words: UTF-8 when it reads as such, else Latin-1, as older
// stations send them.
private fun icyText(bytes: ByteArray): String = try {
    Charsets.UTF_8.newDecoder()
        .onMalformedInput(CodingErrorAction.REPORT)
        .onUnmappableCharacter(CodingErrorAction.REPORT)
        .decode(ByteBuffer.wrap(bytes))
        .toString()
} catch (e: CharacterCodingException) {
    String(bytes, Charsets.ISO_8859_1)
}

// Watches the station that plays: the song its stream names becomes the
// item's title, with "Artist · Station" under it and the song's artwork as
// its cover, so the player, the notification and the lock screen all show
// it. Each new song is looked up through Octo once (`look`, kept per song,
// so `known` answers a song heard before at once); the cover Octo has for
// it then takes the cover's place, without holding up the title. (A
// stream that drops is opened again by its loader: see ReconnectingRadio.)
@OptIn(UnstableApi::class)
internal class RadioWatch(
    private val player: Player,
    private val scope: CoroutineScope,
    private val known: (OnAir) -> SongLookup? = { null },
    private val look: suspend (OnAir) -> SongLookup? = { null },
) : Player.Listener {
    override fun onMetadata(metadata: Metadata) {
        val icy = icyReadOf(metadata) ?: return
        val item = player.currentMediaItem ?: return
        if (!isRadio(item.mediaId)) return
        val air = liveShown(item.mediaId, icy.streamTitle, icy.streamUrl)?.onAir ?: return
        val kept = if (air.named) known(air) else null
        val index = player.currentMediaItemIndex
        item.withOnAir(icy, kept?.cover)?.let { updated -> replace(index, item, updated) }
        if (!air.named || kept != null) return
        scope.launch {
            val found = try {
                look(air)
            } catch (e: CancellationException) {
                throw e
            } catch (e: Exception) {
                null
            } ?: return@launch
            // Still the same song on the same station.
            val now = player.currentMediaItem ?: return@launch
            if (now.entryId != item.entryId || now.mediaMetadata.icyRead() != icy) return@launch
            now.withOnAir(icy, found.cover)?.let { updated -> replace(player.currentMediaItemIndex, now, updated) }
        }
    }

    private fun replace(index: Int, item: androidx.media3.common.MediaItem, updated: androidx.media3.common.MediaItem) {
        scope.launch {
            // Still the same station in the same place.
            if (player.currentMediaItemIndex == index && player.currentMediaItem?.entryId == item.entryId) {
                player.replaceMediaItem(index, updated)
            }
        }
    }
}
