package app.winters.octo.sound

import app.winters.octo.playback.LiveTap
import java.util.concurrent.ConcurrentLinkedQueue
import java.util.concurrent.Executors
import java.util.concurrent.ScheduledExecutorService
import java.util.concurrent.ScheduledFuture
import java.util.concurrent.TimeUnit

// Room for about 2.7 s of 48 kHz stereo between the audio thread and the
// worker; anything that does not fit is dropped.
const val TAP_RING_SAMPLES = 1 shl 18

// How often the worker takes what the audio thread left for it.
const val TAP_DRAIN_MS = 100L

// How much of a song the tap must hear before its level counts, and after
// which, once read, the tap has what it needs from the song.
const val TAP_LEVEL_HEARD_MS = 20_000L

// What a deck's LiveTap knows about the song it is playing: how much of it
// has been heard, its body level, and its tempo when that is trusted.
data class TapReading(val heardMs: Long, val bodyLevelDb: Double?, val tempoPrior: Double?)

// Feeds a deck's sound to a LiveTap without slowing the audio thread down:
// the audio thread only copies samples into a ring, and a worker thread
// takes them from there into the tap of the song they belong to. A new
// song (or a new format) starts a new tap exactly where its first sample
// is in the ring.
//
// The crossfade reads each song's tap a few seconds in, to plan its blend,
// and again once the tap has heard enough for its level to count
// (TAP_LEVEL_HEARD_MS). Once read with that much heard, the rest of the
// song is not fed to the tap (its analysis would go unread); the next song
// is.
class LiveTapFeed(private val worker: ScheduledExecutorService = sharedWorker) {
    private val ring = FloatArray(TAP_RING_SAMPLES)

    // Absolute sample counts: written by the audio thread, read by the worker.
    @Volatile private var written = 0L
    @Volatile private var read = 0L

    private class Start(val at: Long, val entryId: String?, val sampleRate: Int, val channels: Int)

    private val starts = ConcurrentLinkedQueue<Start>()
    private val lock = Any()
    private var tap: LiveTap? = null
    private var tapEntry: String? = null
    private var task: ScheduledFuture<*>? = null

    // Songs begun so far, and the one whose tap was read (from then on its
    // samples are left out).
    @Volatile private var begun = 0
    @Volatile private var readAt = -1

    // Audio thread: the samples from here on are the start of this song.
    fun begin(entryId: String?, sampleRate: Int, channels: Int) {
        starts += Start(written, entryId, sampleRate, channels)
        begun++
        if (task == null) task = worker.scheduleWithFixedDelay(::drain, TAP_DRAIN_MS, TAP_DRAIN_MS, TimeUnit.MILLISECONDS)
    }

    // Audio thread: interleaved samples heard by the listener.
    fun push(samples: FloatArray, count: Int) {
        if (readAt == begun) return
        val w = written
        if (count > TAP_RING_SAMPLES - (w - read)) return
        var at = (w and (TAP_RING_SAMPLES - 1).toLong()).toInt()
        var left = count
        var from = 0
        while (left > 0) {
            val n = minOf(left, TAP_RING_SAMPLES - at)
            System.arraycopy(samples, from, ring, at, n)
            from += n
            left -= n
            at = 0
        }
        written = w + count
    }

    // Stops the worker for this feed; a later begin starts it again.
    fun close() {
        task?.cancel(false)
        task = null
    }

    // Worker: takes every sample written so far into its song's tap.
    fun drain() {
        synchronized(lock) {
            val end = written
            var r = read
            while (r < end) {
                val start = starts.peek()
                if (start != null && start.at <= r) {
                    starts.poll()
                    tap = LiveTap(start.sampleRate, start.channels)
                    tapEntry = start.entryId
                    continue
                }
                val stop = if (start != null && start.at < end) start.at else end
                val current = tap
                var left = (stop - r).toInt()
                var at = (r and (TAP_RING_SAMPLES - 1).toLong()).toInt()
                while (left > 0) {
                    val n = minOf(left, TAP_RING_SAMPLES - at)
                    current?.push(ring, at, n)
                    left -= n
                    at = 0
                }
                r = stop
                read = r
            }
            // A song that starts with no samples yet.
            while (true) {
                val start = starts.peek() ?: break
                if (start.at > r) break
                starts.poll()
                tap = LiveTap(start.sampleRate, start.channels)
                tapEntry = start.entryId
            }
        }
    }

    // Any thread: what the tap knows about this queue entry, or null when
    // it is not the song this deck is playing. `tagBpm`, the song's tag
    // tempo, picks the octave of the tempo heard.
    fun reading(entryId: String?, tagBpm: Double? = null): TapReading? = synchronized(lock) {
        val songs = begun
        drain()
        val current = tap ?: return null
        if (tapEntry != entryId) return null
        // Read with enough heard: no more of this song is fed in, unless
        // another has begun in the meantime.
        if (starts.isEmpty() && current.heardMs() >= TAP_LEVEL_HEARD_MS) readAt = songs
        TapReading(current.heardMs(), current.bodyLevelDb(), current.tempoPrior(tagBpm))
    }

    companion object {
        val sharedWorker: ScheduledExecutorService = Executors.newSingleThreadScheduledExecutor { runnable ->
            Thread(runnable, "octo-live-tap").apply {
                isDaemon = true
                priority = Thread.MIN_PRIORITY
            }
        }
    }
}
