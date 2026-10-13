package app.winters.octo.sound

import android.content.Context
import android.os.Handler
import androidx.media3.common.util.UnstableApi
import androidx.media3.exoplayer.DefaultRenderersFactory
import androidx.media3.exoplayer.Renderer
import androidx.media3.exoplayer.audio.AudioRendererEventListener
import androidx.media3.exoplayer.audio.AudioSink
import androidx.media3.exoplayer.audio.DefaultAudioSink
import androidx.media3.exoplayer.mediacodec.MediaCodecSelector

// Builds a deck's renderers with Octo's shaping in the audio path. Every
// audio output it builds gets its own shaping step, reading the shared
// settings. The output always takes 16-bit sound, because the player only
// runs these steps on 16-bit sound; the shaping turns it into floats itself.
// `keepActive` keeps the shaping step running with nothing to shape (for
// crossfade), and `sound` is the latest shaping step, for the crossfade to
// drive.
@UnstableApi
class OctoRenderersFactory(
    context: Context,
    private val settings: () -> SoundSettings,
    private val albums: AlbumRun,
    private val keepActive: () -> Boolean = { false },
) : DefaultRenderersFactory(context) {
    @Volatile var sound: DeckSound? = null
        private set

    // ALAC plays through Octo's own decoder first, so it plays the same on
    // every phone whether or not the phone has one. Then the phone's
    // decoders. Last, a renderer that fails a song whose sound none of them
    // can play, so it is skipped and reported instead of playing silence.
    override fun buildAudioRenderers(
        context: Context,
        extensionRendererMode: Int,
        mediaCodecSelector: MediaCodecSelector,
        enableDecoderFallback: Boolean,
        audioSink: AudioSink,
        eventHandler: Handler,
        eventListener: AudioRendererEventListener,
        out: ArrayList<Renderer>,
    ) {
        out.add(AlacAudioRenderer(eventHandler, eventListener, audioSink))
        super.buildAudioRenderers(context, extensionRendererMode, mediaCodecSelector, enableDecoderFallback, audioSink, eventHandler, eventListener, out)
        out.add(UnplayableAudioRenderer())
    }

    override fun buildAudioSink(
        context: Context,
        enableFloatOutput: Boolean,
        enableAudioOutputPlaybackParams: Boolean,
    ): AudioSink {
        val shaping = OctoDspProcessor(keepActive, LiveTapFeed(), settings = settings)
        sound = shaping
        val sink = DefaultAudioSink.Builder(context)
            .setEnableFloatOutput(false)
            .setEnableAudioOutputPlaybackParameters(enableAudioOutputPlaybackParams)
            .setAudioProcessorChain(OctoProcessorChain(shaping))
            .build()
        return OctoAudioSink(sink, shaping, albums)
    }
}
