package app.winters.octo.playback

import androidx.media3.common.MediaItem
import androidx.media3.common.MediaMetadata

// A station, ready to play, from its radio id.
internal fun radioItem(id: String): MediaItem? {
    val (stream, name) = radioOf(id) ?: return null
    return MediaItem.Builder()
        .setMediaId(id)
        .setUri(stream)
        .setMediaMetadata(
            MediaMetadata.Builder()
                .setTitle(name.ifEmpty { stream })
                .setArtist("Radio")
                .setIsPlayable(true)
                .setIsBrowsable(false)
                .setMediaType(MediaMetadata.MEDIA_TYPE_RADIO_STATION)
                .build(),
        )
        .build()
}
