package app.winters.octo.cast

import android.os.Handler
import android.os.Looper
import android.util.Log
import androidx.core.net.toUri
import app.winters.octo.output.CastAudioTypes
import app.winters.octo.output.OutputDevice
import app.winters.octo.output.RemoteMedia
import app.winters.octo.output.RemoteOutput
import app.winters.octo.output.RemoteState
import app.winters.octo.output.RemoteStatus
import com.google.android.gms.cast.Cast
import com.google.android.gms.cast.CastStatusCodes
import com.google.android.gms.cast.MediaInfo
import com.google.android.gms.cast.MediaLoadRequestData
import com.google.android.gms.cast.MediaMetadata
import com.google.android.gms.cast.MediaQueueData
import com.google.android.gms.cast.MediaQueueItem
import com.google.android.gms.cast.MediaSeekOptions
import com.google.android.gms.cast.MediaStatus
import com.google.android.gms.cast.framework.CastSession
import com.google.android.gms.cast.framework.media.RemoteMediaClient
import com.google.android.gms.common.images.WebImage

// How often the device's state is passed on, besides when it changes.
private const val TICK_MS = 1_000L

// How long ahead of a song's end the device starts loading the next one.
private const val PRELOAD_SECONDS = 15.0

// Answers to a load that are not failures: replaced by a newer load, or
// cut short by one.
private val NOT_FAILURES = setOf(CastStatusCodes.SUCCESS, CastStatusCodes.REPLACED, CastStatusCodes.CANCELED, CastStatusCodes.INTERRUPTED)

// A Cast device (or speaker group) music is playing on, through the
// standard receiver. The phone hands it the song that is on, plus the next
// one as a second queue item so it can load it ahead and go straight on.
class CastOutput(
    private val session: CastSession,
    override val device: OutputDevice,
    // Ends the Cast session, stopping the receiver when asked to.
    private val endSession: (stopPlaying: Boolean) -> Unit,
) : RemoteOutput {
    private val client: RemoteMediaClient? = session.remoteMediaClient
    private val main = Handler(Looper.getMainLooper())
    private var listener: RemoteOutput.Listener? = null
    private var closed = false

    override val takesNext: Boolean = true

    override fun accepts(mimeType: String): Boolean = mimeType.lowercase() in CastAudioTypes

    private val callback = object : RemoteMediaClient.Callback() {
        override fun onStatusUpdated() = report()
    }

    private val volumeWatch = object : Cast.Listener() {
        override fun onVolumeChanged() = reportVolume()
    }

    // Passes the state on every second too, so an end missed while a
    // command was settling is seen on the next tick.
    private val tick = object : Runnable {
        override fun run() {
            report()
            if (!closed) main.postDelayed(this, TICK_MS)
        }
    }

    init {
        client?.registerCallback(callback)
        session.addCastListener(volumeWatch)
        main.postDelayed(tick, TICK_MS)
    }

    override fun load(media: RemoteMedia, startMs: Long, play: Boolean, next: RemoteMedia?) {
        val client = client ?: return
        val queue = MediaQueueData.Builder()
            .setItems(listOfNotNull(queueItem(media), next?.let(::queueItem)))
            .setStartIndex(0)
            .setStartTime(startMs)
            .setRepeatMode(MediaStatus.REPEAT_MODE_REPEAT_OFF)
            .build()
        val request = MediaLoadRequestData.Builder()
            .setQueueData(queue)
            .setAutoplay(play)
            .setCurrentTime(startMs)
            .build()
        client.load(request).setResultCallback { result ->
            val code = result.status.statusCode
            if (code !in NOT_FAILURES) listener?.onFailed("load refused ($code)")
        }
    }

    private val queue = object : CastQueueClient {
        override val status: CastQueueStatus?
            get() = client?.mediaStatus?.forQueue()

        override fun removeItems(itemIds: IntArray) {
            client?.queueRemoveItems(itemIds, null)
        }

        override fun append(media: RemoteMedia) {
            client?.queueAppendItem(queueItem(media), null)
        }
    }

    // Replaces whatever is queued after the song the device is on with `next`.
    override fun setNext(next: RemoteMedia?) = queue.setNext(next)

    override fun play() {
        client?.play()
    }

    override fun pause() {
        client?.pause()
    }

    override fun seek(positionMs: Long) {
        client?.seek(MediaSeekOptions.Builder().setPosition(positionMs).build())
    }

    override fun stop() {
        client?.stop()
    }

    override fun setVolume(level: Float) {
        runCatching { session.volume = level.coerceIn(0f, 1f).toDouble() }
    }

    override fun setMuted(muted: Boolean) {
        runCatching { session.isMute = muted }
    }

    override fun listen(listener: RemoteOutput.Listener?) {
        this.listener = listener
        if (listener != null) reportVolume()
    }

    override fun close(stopPlaying: Boolean) {
        if (closed) return
        closed = true
        listener = null
        main.removeCallbacks(tick)
        client?.unregisterCallback(callback)
        session.removeCastListener(volumeWatch)
        endSession(stopPlaying)
    }

    private fun report() {
        val listener = listener ?: return
        val client = client ?: return
        val status = client.mediaStatus ?: return
        val queueStatus = status.forQueue()
        if (queueStatus.failed) {
            listener.onFailed("playback error")
            return
        }
        val state = queueStatus.state ?: return
        val info = status.mediaInfo
        listener.onStatus(
            RemoteStatus(
                state = state,
                positionMs = client.approximateStreamPosition.takeIf { state != RemoteState.Idle && state != RemoteState.Ended },
                durationMs = client.streamDuration.takeIf { it > 0 },
                url = info?.contentUrl ?: info?.contentId,
            ),
        )
    }

    private fun reportVolume() {
        val listener = listener ?: return
        runCatching { listener.onVolume(session.volume.toFloat(), session.isMute) }
            .onFailure { Log.i("Octo", "cast: volume unknown") }
    }

    private fun queueItem(media: RemoteMedia): MediaQueueItem {
        val metadata = MediaMetadata(MediaMetadata.MEDIA_TYPE_MUSIC_TRACK).apply {
            putString(MediaMetadata.KEY_TITLE, media.title)
            media.artist?.let { putString(MediaMetadata.KEY_ARTIST, it) }
            media.album?.let { putString(MediaMetadata.KEY_ALBUM_TITLE, it) }
            media.coverUrl?.let { addImage(WebImage(it.toUri())) }
        }
        val info = MediaInfo.Builder(media.url)
            .setContentUrl(media.url)
            .setContentType(media.mimeType)
            .setStreamType(if (media.live) MediaInfo.STREAM_TYPE_LIVE else MediaInfo.STREAM_TYPE_BUFFERED)
            .setMetadata(metadata)
            .apply { media.durationMs?.let(::setStreamDuration) }
            .build()
        return MediaQueueItem.Builder(info)
            .setAutoplay(true)
            .setPreloadTime(PRELOAD_SECONDS)
            .build()
    }
}
