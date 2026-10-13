package app.winters.octo.sound

import android.content.Context
import android.media.MediaCodecList
import android.net.Uri
import androidx.annotation.OptIn
import androidx.media3.common.C
import androidx.media3.common.MediaItem
import androidx.media3.common.MimeTypes
import androidx.media3.common.PlaybackException
import androidx.media3.common.Player
import androidx.media3.common.Tracks
import androidx.media3.common.util.UnstableApi
import androidx.media3.datasource.DefaultDataSource
import androidx.media3.exoplayer.DefaultRenderersFactory
import androidx.media3.exoplayer.ExoPlayer
import androidx.media3.exoplayer.RenderersFactory
import androidx.media3.exoplayer.analytics.AnalyticsListener
import androidx.media3.exoplayer.audio.AudioSink
import androidx.media3.exoplayer.audio.DefaultAudioSink
import androidx.media3.exoplayer.audio.ForwardingAudioSink
import androidx.media3.extractor.DefaultExtractorsFactory
import androidx.test.ext.junit.runners.AndroidJUnit4
import androidx.test.platform.app.InstrumentationRegistry
import app.winters.octo.playback.Scout
import app.winters.octo.playback.SectionEnvelope
import app.winters.octo.playback.withEntry
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Assume.assumeFalse
import org.junit.Test
import org.junit.runner.RunWith
import java.io.File
import java.util.concurrent.CountDownLatch
import java.util.concurrent.TimeUnit

// Plays real files through a real player, with its volume at 0.
@OptIn(UnstableApi::class)
@RunWith(AndroidJUnit4::class)
class AlacPlaybackTest {
    private val instrumentation = InstrumentationRegistry.getInstrumentation()
    private val context: Context = instrumentation.targetContext

    private class Run {
        var error: PlaybackException? = null
        var ended = false
        var audioOffered = false
        var audioSelected = false
        var selectedMime: String? = null
        var decoderName: String? = null
        var renderedBuffers = 0
        var tapHeardMs = 0L
        var tookMs = 0L
    }

    private fun asset(name: String): Uri {
        val file = File(context.cacheDir, "test-$name")
        instrumentation.context.assets.open(name).use { input -> file.outputStream().use { input.copyTo(it) } }
        return Uri.fromFile(file)
    }

    private fun phoneDecodes(mime: String): Boolean =
        MediaCodecList(MediaCodecList.ALL_CODECS).codecInfos.any { !it.isEncoder && it.supportedTypes.any { type -> type.equals(mime, ignoreCase = true) } }

    // Plays `uri` until it ends or fails, for at most `limitMs`.
    private fun play(uri: Uri, renderers: RenderersFactory, sound: () -> DeckSound? = { null }, limitMs: Long = 20_000): Run {
        val run = Run()
        val done = CountDownLatch(1)
        lateinit var player: ExoPlayer
        val entry = "test:1"
        val started = System.currentTimeMillis()
        instrumentation.runOnMainSync {
            player = ExoPlayer.Builder(context, renderers).build()
            player.volume = 0f
            player.addListener(object : Player.Listener {
                override fun onTracksChanged(tracks: Tracks) {
                    for (group in tracks.groups) {
                        if (group.type != C.TRACK_TYPE_AUDIO) continue
                        run.audioOffered = true
                        if (group.isSelected) {
                            run.audioSelected = true
                            run.selectedMime = group.getTrackFormat(0).sampleMimeType
                        }
                    }
                }

                override fun onPlayerError(error: PlaybackException) {
                    run.error = error
                    run.tookMs = System.currentTimeMillis() - started
                    done.countDown()
                }

                override fun onPlaybackStateChanged(playbackState: Int) {
                    if (playbackState != Player.STATE_ENDED) return
                    run.ended = true
                    run.tookMs = System.currentTimeMillis() - started
                    run.renderedBuffers = player.audioDecoderCounters?.renderedOutputBufferCount ?: 0
                    run.tapHeardMs = sound()?.reading(entry)?.heardMs ?: 0L
                    done.countDown()
                }
            })
            player.addAnalyticsListener(object : AnalyticsListener {
                override fun onAudioDecoderInitialized(eventTime: AnalyticsListener.EventTime, decoderName: String, initializedTimestampMs: Long, initializationDurationMs: Long) {
                    run.decoderName = decoderName
                }
            })
            player.setMediaItem(MediaItem.fromUri(uri).withEntry(entry))
            player.prepare()
            player.play()
        }
        done.await(limitMs, TimeUnit.MILLISECONDS)
        instrumentation.runOnMainSync { player.release() }
        return run
    }

    @Test
    fun alacPlaysThroughOctosDecoderAndShaping() {
        for (name in listOf("alac16.m4a", "alac24.m4a")) {
            // Shaping kept on, as during crossfade, so the live tap hears the song.
            val renderers = OctoRenderersFactory(context, { SoundSettings() }, AlbumRun(), keepActive = { true })
            val run = play(asset(name), renderers, sound = { renderers.sound })
            assertNull("$name: ${run.error}", run.error)
            assertTrue(name, run.ended)
            assertTrue(name, run.audioSelected)
            assertEquals(name, MimeTypes.AUDIO_ALAC, run.selectedMime)
            assertEquals(name, "OctoAlac", run.decoderName)
            assertTrue("$name rendered ${run.renderedBuffers}", run.renderedBuffers > 0)
            assertTrue("$name tap heard ${run.tapHeardMs} ms", run.tapHeardMs >= 400)
        }
    }

    // The song's own loudness tags reach the audio output the shaping reads them from.
    @Test
    fun alacLoudnessTagsReachTheOutput() {
        val gains = ArrayList<ReplayGainInfo?>()
        val renderers = RenderersFactory { handler, _, audioListener, _, _ ->
            val shaping = OctoDspProcessor(settings = { SoundSettings() })
            val output = OctoAudioSink(DefaultAudioSink.Builder(context).setAudioProcessorChain(OctoProcessorChain(shaping)).build(), shaping, AlbumRun())
            val recording = object : ForwardingAudioSink(output) {
                override fun configure(config: AudioSink.AudioSinkConfig) {
                    gains += ReplayGain.read(config.format.metadata)
                    super.configure(config)
                }
            }
            arrayOf(AlacAudioRenderer(handler, audioListener, recording))
        }
        val run = play(asset("alac16.m4a"), renderers)
        assertNull("${run.error}", run.error)
        assertTrue(run.ended)
        val gain = gains.firstOrNull()
        assertNotNull(gain)
        assertEquals(-6f, gain!!.trackGain!!, 0.01f)
    }

    // Shows what happens without Octo's decoder on a phone with no ALAC
    // decoder of its own: the song runs its length with nothing chosen to
    // play its sound, and no error.
    @Test
    fun withoutItAPhoneWithNoAlacDecoderRunsSilent() {
        assumeFalse("this device has an ALAC decoder", phoneDecodes(MimeTypes.AUDIO_ALAC))
        val run = play(asset("alac16.m4a"), DefaultRenderersFactory(context))
        assertNull(run.error)
        assertTrue(run.ended)
        assertTrue(run.audioOffered)
        assertFalse(run.audioSelected)
        assertNull(run.decoderName)
    }

    // Sound no decoder on the phone can play fails the song at once as
    // unsupported, instead of running its length in silence.
    @Test
    fun soundNothingCanPlayFailsAsUnsupported() {
        assumeFalse("this device has an AC-3 decoder", phoneDecodes(MimeTypes.AUDIO_AC3))
        val renderers = OctoRenderersFactory(context, { SoundSettings() }, AlbumRun())
        val run = play(asset("ac3.m4a"), renderers)
        assertNotNull(run.error)
        assertEquals(PlaybackException.ERROR_CODE_DECODING_FORMAT_UNSUPPORTED, run.error!!.errorCode)
        assertFalse(run.ended)
        assertTrue("failed after ${run.tookMs} ms", run.tookMs < 900)
    }

    // Automix reads ahead in ALAC songs with the same decoder.
    @Test
    fun theScoutReadsAlac() {
        val scout = Scout(DefaultDataSource.Factory(context), DefaultExtractorsFactory())
        val done = CountDownLatch(1)
        var envelope: SectionEnvelope? = null
        scout.read(asset("alac16.m4a"), 200, 900, { it }) {
            envelope = it
            done.countDown()
        }
        assertTrue(done.await(20, TimeUnit.SECONDS))
        scout.release()
        assertNotNull(envelope)
        assertTrue(envelope!!.size > 0)
        assertTrue(envelope!!.startMs >= 200)
    }
}
