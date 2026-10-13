package app.winters.octo.playback

import android.media.MediaCodec
import android.media.MediaFormat
import android.net.Uri
import android.os.Handler
import android.os.Looper
import android.os.SystemClock
import android.util.Log
import androidx.annotation.OptIn
import androidx.media3.common.MimeTypes
import androidx.media3.common.util.UnstableApi
import androidx.media3.datasource.DataSource
import androidx.media3.extractor.ExtractorsFactory
import androidx.media3.inspector.MediaExtractorCompat
import app.winters.octo.sound.AlacConfig
import app.winters.octo.sound.AlacDecoder
import java.nio.ByteBuffer
import java.nio.ByteOrder
import java.util.concurrent.Executors
import java.util.concurrent.Future
import kotlin.math.max

// The scout gives up on a stretch after this long and the plan does without it.
const val SCOUT_BUDGET_MS = 20_000L

// How much of a song the scout listens to: the end of the playing song and
// the start of the next.
const val TAIL_SCOUT_MS = 60_000L
const val HEAD_SCOUT_MS = 30_000L

// How long one wait on the decoder may take.
private const val CODEC_WAIT_US = 10_000L

// Decodes stretches of songs into their envelopes and analyses them, the
// way the player would read them, on threads of their own (two at a time,
// so the next song's start never waits on the playing song's end). Each
// can be cancelled, and each gives up after SCOUT_BUDGET_MS.
@OptIn(UnstableApi::class)
class Scout(private val sources: DataSource.Factory, private val extractors: ExtractorsFactory) {
    private val worker = Executors.newFixedThreadPool(2) { runnable ->
        Thread(runnable, "octo-scout").apply {
            isDaemon = true
            priority = Thread.MIN_PRIORITY
        }
    }
    private val main = Handler(Looper.getMainLooper())

    // Once released, every stretch still being read stops at its next step.
    @Volatile private var released = false

    // A stretch being read; cancel() stops it and keeps its answer from coming.
    class Job internal constructor() {
        @Volatile var cancelled = false
            private set
        internal var future: Future<*>? = null

        fun cancel() {
            cancelled = true
            future?.cancel(false)
        }
    }

    // Reads `uri` from `fromMs` to `toMs`, analyses what it heard there,
    // and hands the analysis (or null, when it could not) to `done` on the
    // main thread.
    fun <T : Any> read(uri: Uri, fromMs: Long, toMs: Long, analyze: (SectionEnvelope) -> T, done: (T?) -> Unit): Job =
        run({ cancelled ->
            val started = SystemClock.elapsedRealtime()
            try {
                decodeSection(uri, fromMs, toMs) { cancelled() || released || SystemClock.elapsedRealtime() - started > SCOUT_BUDGET_MS }?.let(analyze)
            } catch (e: NotSeekable) {
                Log.i("Octo", "automix: not scouting ${uri.lastPathSegment}: ${e.message}")
                null
            } catch (e: Exception) {
                Log.i("Octo", "automix: scouting ${uri.lastPathSegment} failed: $e")
                null
            }
        }, done)

    // Runs `work` on a scout thread and hands its answer to `done` on the
    // main thread, unless the job was cancelled first.
    fun <T : Any> run(work: (cancelled: () -> Boolean) -> T?, done: (T?) -> Unit): Job {
        val job = Job()
        job.future = worker.submit {
            if (job.cancelled) return@submit
            val answer = try {
                work { job.cancelled }
            } catch (e: Exception) {
                Log.i("Octo", "automix: $e")
                null
            }
            if (!job.cancelled) main.post { if (!job.cancelled) done(answer) }
        }
        return job
    }

    fun release() {
        released = true
        worker.shutdownNow()
    }

    private fun decodeSection(uri: Uri, fromMs: Long, toMs: Long, stop: () -> Boolean): SectionEnvelope? {
        val extractor = MediaExtractorCompat(extractors, sources)
        try {
            extractor.setDataSource(uri, 0)
            val track = (0 until extractor.trackCount).firstOrNull {
                extractor.getTrackFormat(it).getString(MediaFormat.KEY_MIME)?.startsWith("audio/") == true
            } ?: return null
            extractor.selectTrack(track)
            val format = extractor.getTrackFormat(track)
            if (fromMs > 0) extractor.seekTo(fromMs * 1_000, MediaExtractorCompat.SEEK_TO_PREVIOUS_SYNC)
            val stretch = Stretch(fromMs, toMs)
            // ALAC goes through Octo's own decoder, as it does when it plays.
            if (format.getString(MediaFormat.KEY_MIME) == MimeTypes.AUDIO_ALAC) {
                readAlac(extractor, format, stretch, stop)
            } else {
                readWithCodec(extractor, format, stretch, stop)
            }
            if (stop()) return null
            return stretch.envelope()
        } finally {
            extractor.release()
        }
    }

    private fun readWithCodec(extractor: MediaExtractorCompat, format: MediaFormat, stretch: Stretch, stop: () -> Boolean) {
        val decoder = MediaCodec.createDecoderByType(format.getString(MediaFormat.KEY_MIME)!!)
        try {
            decoder.configure(format, null, null, 0)
            decoder.start()

            val info = MediaCodec.BufferInfo()
            var rate = 0
            var channels = 0
            var floats = false
            var inputDone = false
            var shorts = ShortArray(0)
            var samples = FloatArray(0)
            while (!stop()) {
                if (!inputDone) {
                    val index = decoder.dequeueInputBuffer(CODEC_WAIT_US)
                    if (index >= 0) {
                        val buffer = decoder.getInputBuffer(index)!!
                        val size = extractor.readSampleData(buffer, 0)
                        if (size < 0) {
                            decoder.queueInputBuffer(index, 0, 0, 0, MediaCodec.BUFFER_FLAG_END_OF_STREAM)
                            inputDone = true
                        } else {
                            decoder.queueInputBuffer(index, 0, size, extractor.sampleTime, 0)
                            extractor.advance()
                        }
                    }
                }
                val index = decoder.dequeueOutputBuffer(info, CODEC_WAIT_US)
                if (index == MediaCodec.INFO_OUTPUT_FORMAT_CHANGED) {
                    val out = decoder.outputFormat
                    val newRate = out.getInteger(MediaFormat.KEY_SAMPLE_RATE)
                    val newChannels = out.getInteger(MediaFormat.KEY_CHANNEL_COUNT)
                    // A stretch that changes its format halfway is not worth the trouble.
                    if (stretch.started && (newRate != rate || newChannels != channels)) break
                    rate = newRate
                    channels = newChannels
                    floats = out.containsKey(MediaFormat.KEY_PCM_ENCODING) &&
                        out.getInteger(MediaFormat.KEY_PCM_ENCODING) == android.media.AudioFormat.ENCODING_PCM_FLOAT
                    continue
                }
                if (index < 0) continue
                val buffer = decoder.getOutputBuffer(index)!!.order(ByteOrder.nativeOrder())
                buffer.position(info.offset)
                buffer.limit(info.offset + info.size)
                if (rate == 0) {
                    val out = decoder.outputFormat
                    rate = out.getInteger(MediaFormat.KEY_SAMPLE_RATE)
                    channels = out.getInteger(MediaFormat.KEY_CHANNEL_COUNT)
                }
                val count = if (floats) info.size / 4 else info.size / 2
                if (samples.size < count) samples = FloatArray(count)
                if (floats) {
                    buffer.asFloatBuffer().get(samples, 0, count)
                } else {
                    if (shorts.size < count) shorts = ShortArray(count)
                    buffer.asShortBuffer().get(shorts, 0, count)
                    for (i in 0 until count) samples[i] = shorts[i] / 32_768f
                }
                val startMs = info.presentationTimeUs / 1_000.0
                decoder.releaseOutputBuffer(index, false)
                val full = stretch.add(samples, count, rate, channels, startMs)
                if (full || info.flags and MediaCodec.BUFFER_FLAG_END_OF_STREAM != 0) break
            }
        } finally {
            try {
                decoder.stop()
            } catch (_: Exception) {
            }
            decoder.release()
        }
    }

    private fun readAlac(extractor: MediaExtractorCompat, format: MediaFormat, stretch: Stretch, stop: () -> Boolean) {
        val setup = format.getByteBuffer("csd-0") ?: return
        val alac = AlacDecoder(AlacConfig.parse(ByteArray(setup.remaining()).also { setup.duplicate().get(it) }))
        val samples = FloatArray(alac.samples.size)
        var frame = ByteArray(4_096)
        while (!stop()) {
            val size = extractor.sampleSize
            if (size < 0) break
            if (size > frame.size) frame = ByteArray(size.toInt())
            val read = extractor.readSampleData(ByteBuffer.wrap(frame), 0)
            if (read < 0) break
            val startMs = extractor.sampleTime / 1_000.0
            extractor.advance()
            val frames = alac.decode(frame, 0, read)
            alac.toFloats(frames, samples)
            if (stretch.add(samples, frames * alac.channels, alac.config.sampleRate, alac.channels, startMs)) break
        }
    }
}

// Collects a stretch's decoded sound, from `fromMs` to `toMs`, into its
// envelope.
private class Stretch(private val fromMs: Long, private val toMs: Long) {
    private var builder: EnvelopeBuilder? = null

    val started: Boolean get() = builder != null

    // Takes `count` interleaved samples starting at `startMs`, and says
    // whether the stretch is now complete.
    fun add(samples: FloatArray, count: Int, rate: Int, channels: Int, startMs: Double): Boolean {
        val frames = count / max(1, channels)
        // Frames before the stretch (a seek lands on the frame before) are left out.
        val skip = if (startMs < fromMs) ((fromMs - startMs) * rate / 1_000).toInt().coerceAtMost(frames) else 0
        if (frames > skip) {
            val b = builder ?: EnvelopeBuilder(rate, channels, max(fromMs.toDouble(), startMs).toLong()).also { builder = it }
            b.push(samples, skip * channels, (frames - skip) * channels)
        }
        val endMs = startMs + frames * 1_000.0 / rate
        return endMs >= toMs
    }

    fun envelope(): SectionEnvelope? = builder?.build()?.takeIf { it.size > 0 }
}
