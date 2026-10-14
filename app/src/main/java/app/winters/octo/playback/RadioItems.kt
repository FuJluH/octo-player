package app.winters.octo.playback

import android.os.Bundle
import androidx.media3.common.C
import androidx.media3.common.MediaItem
import androidx.media3.common.MediaMetadata
import androidx.media3.common.MimeTypes
import app.winters.octo.liveradio.LiveShown
import app.winters.octo.liveradio.liveShown

// Where a station's item keeps what its stream named last (its ICY
// StreamTitle, and the StreamUrl or StreamArtwork sent with it), so every
// screen reads the song on air the same way.
const val EXTRA_STREAM_TITLE = "app.winters.octo.streamTitle"
const val EXTRA_STREAM_URL = "app.winters.octo.streamUrl"

// What a station's stream named last.
data class IcyRead(val streamTitle: String?, val streamUrl: String?)

// What a station shows: its two lines (the song on air over "Artist ·
// Station", or the station's name over its tagline or where it is) and its
// cover as an artwork reference (see StationArt).
data class LiveLines(val title: String, val subtitle: String, val artwork: String, val shown: LiveShown)

// The lines a station's item shows for what its stream named last; `art`
// is the cover it shows now, whose station pictures are kept, and
// `octoCover` the cover Octo has for the song on air, when it has one.
fun liveLines(id: String, read: IcyRead?, art: StationArt? = null, octoCover: String? = null): LiveLines? {
    val shown = liveShown(id, read?.streamTitle, read?.streamUrl) ?: return null
    val base = art ?: stationArt(id) ?: return null
    val cover = base.copy(artwork = shown.onAir.artwork.trim(), cover = octoCover?.takeIf { shown.onAir.named }.orEmpty())
    return LiveLines(shown.title.take(RADIO_TITLE_MAX), shown.subtitle.take(RADIO_TITLE_MAX), cover.encode(), shown)
}

private const val RADIO_TITLE_MAX = 200

// A station, ready to play, from its radio id. A server cover in its
// details is one on the server `sourceId`.
internal fun radioItem(id: String, sourceId: String? = null): MediaItem? {
    val (stream, _) = radioOf(id) ?: return null
    val lines = liveLines(id, null, stationArt(id, sourceId = sourceId)) ?: return null
    return MediaItem.Builder()
        .setMediaId(id)
        .setUri(stream)
        .apply { if (radioIsHls(id)) setMimeType(MimeTypes.APPLICATION_M3U8) }
        .setMediaMetadata(
            MediaMetadata.Builder()
                .setIsPlayable(true)
                .setIsBrowsable(false)
                .setMediaType(MediaMetadata.MEDIA_TYPE_RADIO_STATION)
                .withLines(lines, null, null)
                .build(),
        )
        .build()
}

private fun MediaMetadata.Builder.withLines(lines: LiveLines, read: IcyRead?, extras: Bundle?): MediaMetadata.Builder =
    setTitle(lines.title)
        .setArtist(lines.subtitle)
        .setStation(lines.shown.station)
        .setArtworkUri(artworkUri(lines.artwork))
        .setExtras(
            Bundle(extras ?: Bundle.EMPTY).apply {
                putString(EXTRA_ARTWORK, lines.artwork)
                putString(EXTRA_STREAM_TITLE, read?.streamTitle)
                putString(EXTRA_STREAM_URL, read?.streamUrl)
            },
        )

// What the item's stream named last, as kept in it.
fun MediaMetadata.icyRead(): IcyRead? {
    val extras = extras ?: return null
    val title = extras.getString(EXTRA_STREAM_TITLE)
    val url = extras.getString(EXTRA_STREAM_URL)
    return if (title == null && url == null) null else IcyRead(title, url)
}

// A station in the queue with its lines and cover as the stream names them
// now (and Octo's cover for the song, `octoCover`), or null when they are
// already shown.
internal fun MediaItem.withOnAir(read: IcyRead, octoCover: String? = null): MediaItem? {
    val meta = mediaMetadata
    val lines = liveLines(mediaId, read, stationArtOf(meta.artworkRef()), octoCover) ?: return null
    if (meta.title?.toString() == lines.title && meta.artist?.toString() == lines.subtitle && meta.artworkRef() == lines.artwork) return null
    return buildUpon().setMediaMetadata(meta.buildUpon().withLines(lines, read, meta.extras).build()).build()
}

// How long a station waits before opening its stream again after it
// failed, by how many times in a row it has: a second, then two, four and
// eight. A stream that will never open (refused, gone, not audio) is not
// tried again.
fun radioRetryDelayMs(errorCount: Int, lasting: Boolean): Long =
    if (lasting || errorCount > RADIO_RETRIES) C.TIME_UNSET else 1_000L shl (errorCount - 1).coerceIn(0, 3)

// How many times in a row a station's stream is opened again before the
// player gives up on it.
const val RADIO_RETRIES = 4
