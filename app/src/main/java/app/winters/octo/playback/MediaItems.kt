package app.winters.octo.playback

import android.content.Context
import android.graphics.Bitmap
import android.net.Uri
import android.os.Bundle
import androidx.annotation.OptIn
import androidx.media3.common.C
import androidx.media3.common.MediaItem
import androidx.media3.common.MediaMetadata
import androidx.media3.common.util.BitmapLoader
import androidx.media3.common.util.UnstableApi
import app.winters.octo.catalog.TrackEntity
import app.winters.octo.sound.ReplayGainInfo
import app.winters.octo.sound.storedReplayGain
import com.google.common.util.concurrent.ListenableFuture
import com.google.common.util.concurrent.MoreExecutors
import java.util.concurrent.Callable
import java.util.concurrent.Executors

private const val ART_SCHEME = "octo-art"

// Where the app keeps a song's artwork reference, so screens can draw it.
const val EXTRA_ARTWORK = "app.winters.octo.artwork"
const val EXTRA_ALBUM_ID = "app.winters.octo.albumId"
const val EXTRA_ARTIST_ID = "app.winters.octo.artistId"
const val EXTRA_MIME = "app.winters.octo.mime"
const val EXTRA_ALBUM_ORDER = "app.winters.octo.albumOrder"

// The song's beats a minute from its tags or its server, when known.
const val EXTRA_BPM = "app.winters.octo.bpm"

// Android's own key for an explicit song (MediaConstants.METADATA_KEY_IS_EXPLICIT),
// so a car's screen marks it too, and the value that says it is.
const val EXTRA_IS_EXPLICIT = "android.media.IS_EXPLICIT"
private const val ATTRIBUTE_PRESENT = 1L

// A song's stored loudness, for when the sound itself carries no tags.
private const val EXTRA_TRACK_GAIN = "app.winters.octo.trackGain"
private const val EXTRA_TRACK_PEAK = "app.winters.octo.trackPeak"
private const val EXTRA_ALBUM_GAIN = "app.winters.octo.albumGain"
private const val EXTRA_ALBUM_PEAK = "app.winters.octo.albumPeak"

// Artwork for the lock screen and notification, in a form the playback
// service can turn back into a picture.
internal fun artworkUri(ref: String?): Uri? = ref?.let { Uri.fromParts(ART_SCHEME, it, null) }

// A song from the catalog, ready to play.
fun TrackEntity.toMediaItem(): MediaItem = toMediaItem(uri, mimeType)

// A song from the catalog, playing from one of its copies: where that copy
// is, what the player will receive from it, how loud the song is when its
// source says, and its tempo when any copy knows it. `sniffed` leaves the
// type off the player's item, so the player goes by the bytes that come: a
// find can arrive as another file than the one listed. The listed type
// still names the song until it opens.
fun TrackEntity.toMediaItem(
    uri: String?,
    mimeType: String?,
    loudness: ReplayGainInfo? = null,
    bpm: Int? = null,
    sniffed: Boolean = false,
): MediaItem =
    MediaItem.Builder()
        .setMediaId(id)
        .setUri(uri)
        .setMimeType(playerMimeType(mimeType, sniffed))
        .setMediaMetadata(
            MediaMetadata.Builder()
                .setTitle(title)
                .setArtist(artist)
                .setAlbumTitle(album)
                .setTrackNumber(trackNo)
                .setDiscNumber(discNo)
                .setReleaseYear(year)
                .setDurationMs(durationMs)
                .setArtworkUri(artworkUri(artwork))
                .setIsPlayable(true)
                .setIsBrowsable(false)
                .setMediaType(MediaMetadata.MEDIA_TYPE_MUSIC)
                .setExtras(
                    Bundle().apply {
                        putString(EXTRA_ARTWORK, artwork)
                        putString(EXTRA_ALBUM_ID, albumId)
                        putString(EXTRA_ARTIST_ID, artistId)
                        putString(EXTRA_MIME, mimeType)
                        putInt(EXTRA_ALBUM_ORDER, albumOrder)
                        if (explicit == true) putLong(EXTRA_IS_EXPLICIT, ATTRIBUTE_PRESENT)
                        if (bpm != null && tagBpm(bpm) != null) putInt(EXTRA_BPM, bpm)
                        loudness?.trackGain?.let { putFloat(EXTRA_TRACK_GAIN, it) }
                        loudness?.trackPeak?.let { putFloat(EXTRA_TRACK_PEAK, it) }
                        loudness?.albumGain?.let { putFloat(EXTRA_ALBUM_GAIN, it) }
                        loudness?.albumPeak?.let { putFloat(EXTRA_ALBUM_PEAK, it) }
                    },
                )
                .build(),
        )
        .build()

// Just the id: what the app sends to the service, which fills in the rest.
// `source` is the list it is played from, as QueueSource.encoded words.
fun songRequest(trackId: String, source: String? = null): MediaItem {
    val request = MediaItem.Builder().setMediaId(trackId)
    if (source != null) {
        request.setRequestMetadata(MediaItem.RequestMetadata.Builder().setExtras(Bundle().apply { putString(EXTRA_SOURCE, source) }).build())
    }
    return request.build()
}

// Turns artwork references back into pictures for the lock screen and
// notification; anything else goes to the standard loader.
@OptIn(UnstableApi::class)
class OctoArtLoader(private val context: Context, private val fallback: BitmapLoader) : BitmapLoader {
    private val worker = MoreExecutors.listeningDecorator(Executors.newSingleThreadExecutor())

    override fun supportsMimeType(mimeType: String) = fallback.supportsMimeType(mimeType)

    override fun decodeBitmap(data: ByteArray): ListenableFuture<Bitmap> = fallback.decodeBitmap(data)

    override fun loadBitmap(uri: Uri): ListenableFuture<Bitmap> {
        if (uri.scheme != ART_SCHEME) return fallback.loadBitmap(uri)
        val ref = uri.schemeSpecificPart
        return worker.submit(
            Callable { artworkBitmap(context, ref, 512) ?: throw IllegalArgumentException("No artwork") },
        )
    }
}

// Reads the artwork reference a song was sent with.
fun MediaMetadata.artworkRef(): String? = (extras ?: Bundle.EMPTY).getString(EXTRA_ARTWORK)

fun MediaMetadata.extra(key: String): String? = (extras ?: Bundle.EMPTY).getString(key)

// Whether a song was sent marked explicit.
fun MediaMetadata.isExplicit(): Boolean = (extras ?: Bundle.EMPTY).getLong(EXTRA_IS_EXPLICIT, 0L) == ATTRIBUTE_PRESENT

// The tempo a song was sent with, if any copy of it knew one.
fun MediaMetadata.tagBpm(): Double? = tagBpm((extras ?: Bundle.EMPTY).getInt(EXTRA_BPM, 0))

// A stored tempo the automix analysis can use: none for a missing or
// nonsense value.
fun tagBpm(stored: Int?): Double? = stored?.takeIf { it in 1..999 }?.toDouble()

// The loudness a song was sent with, if its source knew it.
fun MediaMetadata.storedLoudness(): ReplayGainInfo? {
    val extras = extras ?: return null
    fun value(key: String) = if (extras.containsKey(key)) extras.getFloat(key) else null
    return storedReplayGain(value(EXTRA_TRACK_GAIN), value(EXTRA_TRACK_PEAK), value(EXTRA_ALBUM_GAIN), value(EXTRA_ALBUM_PEAK))
}

// How long a song is: what a Media3 player measured of its sound
// (C.TIME_UNSET while it has not), else `listedMs`.
fun songLengthMs(listedMs: Long, playerMs: Long): Long =
    playingLengthMs(listedMs, playerMs.takeIf { it != C.TIME_UNSET })

// The type the player's item names: the listed one, or none for a song
// whose bytes may be another file than listed, so the player goes by them.
fun playerMimeType(listed: String?, sniffed: Boolean): String? = if (sniffed) null else listed
