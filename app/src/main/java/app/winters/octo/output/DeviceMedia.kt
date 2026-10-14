package app.winters.octo.output

import android.content.Context
import android.graphics.Bitmap
import android.util.Log
import androidx.annotation.OptIn
import androidx.core.net.toUri
import androidx.media3.common.MediaItem
import androidx.media3.common.util.UnstableApi
import app.winters.octo.catalog.ArtworkRef
import app.winters.octo.connection.ConnectionSecurity
import app.winters.octo.playback.EXTRA_MIME
import app.winters.octo.playback.Streams
import app.winters.octo.playback.artworkBitmap
import app.winters.octo.playback.artworkRef
import app.winters.octo.playback.entryId
import app.winters.octo.playback.extra
import app.winters.octo.playback.stationArtOf
import app.winters.octo.playback.streamUri
import dagger.hilt.android.qualifiers.ApplicationContext
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import java.io.ByteArrayOutputStream
import javax.inject.Inject
import javax.inject.Singleton

// How big a cover a device gets, in pixels across.
private const val COVER_PX = 600

// Turns queue songs into what a TV or speaker fetches: server songs by an
// address signed for them, phone files and covers from the phone's own
// small server, and radio as it is. The phone's server runs only while
// casting, and serves only the songs in the cast queue.
@OptIn(UnstableApi::class)
@Singleton
class DeviceMedia @Inject constructor(
    @ApplicationContext private val context: Context,
    private val streams: Streams,
    private val security: ConnectionSecurity,
) : MediaForDevice {
    @Volatile private var server: MediaServer? = null

    // Starts the phone's server on the Wi-Fi. Answers whether it could:
    // without a Wi-Fi address, phone files cannot be cast.
    fun begin(): Boolean {
        if (server?.running == true) return true
        val address = localNetworkAddress(context) ?: return false
        return try {
            server = MediaServer(address).also { it.start() }
            true
        } catch (e: Exception) {
            Log.w("Octo", "cast: the phone's media server could not start: ${e.javaClass.simpleName}")
            false
        }
    }

    // Stops the server; nothing handed out before can be fetched again.
    fun end() {
        server?.stop()
        server = null
    }

    // Serves only these queue entries, and their covers, from now on.
    fun keepOnly(keys: Set<String>) {
        server?.keepOnly(keys + keys.map(::coverKey))
    }

    override fun canPlay(item: MediaItem, output: RemoteOutput): Boolean = when (val source = sourceOf(item)) {
        is CastSource.Skipped -> false
        is CastSource.PhoneFile -> output.accepts(phoneType(item, source.uri))
        else -> true
    }

    override suspend fun make(item: MediaItem, output: RemoteOutput): RemoteMedia? = withContext(Dispatchers.IO) {
        val key = item.entryId ?: item.mediaId
        val meta = item.mediaMetadata
        suspend fun song(url: String, type: String, seekable: Boolean, live: Boolean = false) = RemoteMedia(
            url = url,
            mimeType = type,
            title = meta.title?.toString() ?: meta.displayTitle?.toString() ?: "Unknown song",
            artist = meta.artist?.toString(),
            album = meta.albumTitle?.toString(),
            coverUrl = coverFor(key, meta.artworkRef()),
            durationMs = meta.durationMs?.takeIf { !live },
            seekable = seekable,
            live = live,
        )
        try {
            when (val source = sourceOf(item)) {
                is CastSource.Server -> {
                    val request = requestForDevice(streams.deviceRequest(source.ref), source.ref.mimeType, output::accepts)
                    val type = request.mimeType(source.ref.mimeType) ?: meta.extra(EXTRA_MIME) ?: "audio/mpeg"
                    // A file as it is can be sought in; one made on the way cannot.
                    val seekable = request.maxKbps == null
                    if (security.reachableByOtherDevices()) {
                        streams.deviceAddress(source.ref, request)?.let { song(it, type, seekable) }
                    } else {
                        val relay = RelayedContent(streams::downloadSource, streamUri(source.ref.pin(request)).toUri(), type)
                        server?.offer(key, relay, extensionFor(type))?.let { song(it, type, seekable) }
                    }
                }
                is CastSource.PhoneFile -> {
                    val type = phoneType(item, source.uri)
                    if (!output.accepts(type)) return@withContext null
                    server?.offer(key, PhoneFileContent(context, source.uri.toUri(), type), extensionFor(type))?.let { song(it, type, seekable = true) }
                }
                is CastSource.Web -> {
                    val type = meta.extra(EXTRA_MIME) ?: mimeFromName(source.url.substringBefore('?')) ?: "audio/mpeg"
                    song(source.url, type, seekable = !source.live, live = source.live)
                }
                is CastSource.Skipped -> null
            }
        } catch (e: Exception) {
            Log.w("Octo", "cast: could not get a song ready: ${e.javaClass.simpleName}")
            null
        }
    }

    private fun sourceOf(item: MediaItem): CastSource = castSourceOf(item.mediaId, item.localConfiguration?.uri?.toString())

    private fun phoneType(item: MediaItem, uri: String): String =
        item.mediaMetadata.extra(EXTRA_MIME)
            ?: runCatching { context.contentResolver.getType(uri.toUri()) }.getOrNull()?.takeIf { it.startsWith("audio/") }
            ?: mimeFromName(uri)
            ?: "audio/mpeg"

    // A cover for the device's screen: the server's own address for a
    // server cover it can reach, otherwise a small copy the phone serves.
    private suspend fun coverFor(key: String, ref: String?): String? {
        val art = ArtworkRef.decode(ref)
        if (art == null && stationArtOf(ref) == null) return null
        if (art is ArtworkRef.Server && security.reachableByOtherDevices()) {
            streams.client()?.let { return it.coverArtUrl(art.coverId, COVER_PX).toString() }
        }
        val server = server ?: return null
        val bitmap = artworkBitmap(context, ref, COVER_PX) ?: return null
        val bytes = ByteArrayOutputStream().use { out ->
            bitmap.compress(Bitmap.CompressFormat.JPEG, 88, out)
            out.toByteArray()
        }
        return server.offer(coverKey(key), ServedBytes("image/jpeg", bytes), "jpg")
    }

    private fun coverKey(key: String) = "cover:$key"
}
