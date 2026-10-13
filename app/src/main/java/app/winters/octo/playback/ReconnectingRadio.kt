package app.winters.octo.playback

import android.net.Uri
import android.os.SystemClock
import androidx.annotation.OptIn
import androidx.media3.common.C
import androidx.media3.common.util.UnstableApi
import androidx.media3.datasource.DataSource
import androidx.media3.datasource.DataSpec
import androidx.media3.datasource.TransferListener
import java.io.IOException

// A station's stream that ended on its own. A live stream never ends, so
// its connection dropped; the loader treats this like any dropped
// connection and opens the stream again, from the live edge, instead of
// moving on to the next song.
class StreamEnded : IOException("The station's stream ended")

// When each station's stream last ended on its own, shared by a deck's
// radio loads. A stream that keeps ending is let end after RADIO_RETRIES
// times in `windowMs`, and the queue moves on.
internal class RadioEnds(private val windowMs: Long = 2 * 60 * 1000L, private val now: () -> Long = SystemClock::elapsedRealtime) {
    private val ends = HashMap<String, ArrayDeque<Long>>()

    // How many times this stream ended lately.
    @Synchronized
    fun recent(stream: String): Int = prune(stream).size

    // The stream ended: true to open it again, false to let it end.
    @Synchronized
    fun ended(stream: String): Boolean {
        val times = prune(stream)
        if (times.size >= RADIO_RETRIES) {
            ends.remove(stream)
            return false
        }
        times.addLast(now())
        return true
    }

    private fun prune(stream: String): ArrayDeque<Long> {
        val times = ends.getOrPut(stream) { ArrayDeque() }
        val at = now()
        while (times.isNotEmpty() && at - times.first() > windowMs) times.removeFirst()
        return times
    }
}

// A station's stream, read through `upstream`. When a stream with no
// length (a live one) ends, that is reported as StreamEnded, so the loader
// connects again; a stream that ended lately waits a little longer before
// each new connection (radioRetryDelayMs).
@OptIn(UnstableApi::class)
internal class ReconnectingDataSource(
    private val upstream: DataSource,
    private val ends: RadioEnds,
    private val wait: (Long) -> Unit = Thread::sleep,
) : DataSource {
    private var live = false
    private var stream = ""

    override fun addTransferListener(transferListener: TransferListener) = upstream.addTransferListener(transferListener)

    override fun open(dataSpec: DataSpec): Long {
        stream = dataSpec.uri.toString()
        val lately = ends.recent(stream)
        if (lately > 0) {
            try {
                wait(radioRetryDelayMs(lately, lasting = false).coerceAtLeast(0))
            } catch (e: InterruptedException) {
                Thread.currentThread().interrupt()
                throw IOException("Stopped while waiting to connect again", e)
            }
        }
        val length = upstream.open(dataSpec)
        live = length == C.LENGTH_UNSET.toLong() && dataSpec.length == C.LENGTH_UNSET.toLong()
        return length
    }

    override fun read(buffer: ByteArray, offset: Int, length: Int): Int {
        val read = upstream.read(buffer, offset, length)
        if (read == C.RESULT_END_OF_INPUT && live && ends.ended(stream)) throw StreamEnded()
        return read
    }

    override fun getUri(): Uri? = upstream.uri

    override fun getResponseHeaders(): Map<String, List<String>> = upstream.responseHeaders

    override fun close() = upstream.close()

    class Factory(private val upstream: DataSource.Factory, private val ends: RadioEnds = RadioEnds()) : DataSource.Factory {
        override fun createDataSource(): DataSource = ReconnectingDataSource(upstream.createDataSource(), ends)
    }
}
