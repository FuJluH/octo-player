package app.winters.octo.sound

import android.os.Handler
import androidx.media3.common.C
import androidx.media3.common.Format
import androidx.media3.common.MimeTypes
import androidx.media3.common.PlaybackException
import androidx.media3.common.util.UnstableApi
import androidx.media3.common.util.Util
import androidx.media3.decoder.CryptoConfig
import androidx.media3.decoder.DecoderException
import androidx.media3.decoder.DecoderInputBuffer
import androidx.media3.decoder.SimpleDecoder
import androidx.media3.decoder.SimpleDecoderOutputBuffer
import androidx.media3.exoplayer.BaseRenderer
import androidx.media3.exoplayer.RendererCapabilities
import androidx.media3.exoplayer.audio.AudioRendererEventListener
import androidx.media3.exoplayer.audio.AudioSink
import androidx.media3.exoplayer.audio.DecoderAudioRenderer
import androidx.media3.exoplayer.source.MediaSource

// The PCM format an ALAC stream decodes to: 16-bit, 24-bit (20-bit sits in
// the top of 24) or 32-bit.
@UnstableApi
fun alacPcmFormat(config: AlacConfig): Format {
    val encoding = when (config.bitDepth) {
        16 -> C.ENCODING_PCM_16BIT
        20, 24 -> C.ENCODING_PCM_24BIT
        else -> C.ENCODING_PCM_32BIT
    }
    return Util.getPcmFormat(encoding, config.channels, config.sampleRate)
}

// How well the ALAC renderer plays `format`: only ALAC with a setup it can
// read, unencrypted, into an output that takes its PCM.
@UnstableApi
fun alacSupport(format: Format, outputTakes: (Format) -> Boolean): Int {
    if (format.sampleMimeType != MimeTypes.AUDIO_ALAC) return C.FORMAT_UNSUPPORTED_TYPE
    val config = format.initializationData.firstOrNull()?.let(AlacConfig::parseOrNull) ?: return C.FORMAT_UNSUPPORTED_SUBTYPE
    if (format.cryptoType != C.CRYPTO_TYPE_NONE) return C.FORMAT_UNSUPPORTED_DRM
    if (!outputTakes(alacPcmFormat(config))) return C.FORMAT_UNSUPPORTED_SUBTYPE
    return C.FORMAT_HANDLED
}

class AlacDecoderException(message: String, cause: Throwable? = null) : DecoderException(message, cause)

private const val ALAC_BUFFERS = 16

// Media3's side of the ALAC decoder: takes a frame per input buffer and
// gives its PCM per output buffer. Frames stand alone, so a seek needs no
// reset.
// SimpleDecoder fills both arrays of buffers itself.
@Suppress("UNCHECKED_CAST")
@UnstableApi
class AlacMediaDecoder(format: Format) : SimpleDecoder<DecoderInputBuffer, SimpleDecoderOutputBuffer, AlacDecoderException>(
    arrayOfNulls<DecoderInputBuffer>(ALAC_BUFFERS) as Array<DecoderInputBuffer>,
    arrayOfNulls<SimpleDecoderOutputBuffer>(ALAC_BUFFERS) as Array<SimpleDecoderOutputBuffer>,
) {
    private val config = format.initializationData.firstOrNull()?.let(AlacConfig::parseOrNull)
        ?: throw AlacDecoderException("ALAC setup is missing or damaged")
    private val alac = AlacDecoder(config)
    // Sized for the largest frame the file says it has, within what any
    // frame of this setup could take; a bigger one grows it.
    private var frame = ByteArray(
        (format.maxInputSize.takeIf { it > 0 } ?: config.maxFrameBytes)
            .coerceIn(4_096, config.frameLength * config.channels * 4 + 64),
    )
    private val pcm = ByteArray(alac.maxOutputBytes)

    val outputFormat: Format = alacPcmFormat(config)

    init {
        setInitialInputBufferSize(frame.size)
    }

    override fun getName(): String = "OctoAlac"

    override fun createInputBuffer(): DecoderInputBuffer = DecoderInputBuffer(DecoderInputBuffer.BUFFER_REPLACEMENT_MODE_DIRECT)

    override fun createOutputBuffer(): SimpleDecoderOutputBuffer = SimpleDecoderOutputBuffer { releaseOutputBuffer(it) }

    override fun createUnexpectedDecodeException(error: Throwable): AlacDecoderException =
        AlacDecoderException("Unexpected ALAC decode error", error)

    override fun decode(inputBuffer: DecoderInputBuffer, outputBuffer: SimpleDecoderOutputBuffer, reset: Boolean): AlacDecoderException? {
        val data = inputBuffer.data ?: return AlacDecoderException("ALAC frame has no data")
        val size = data.remaining()
        if (frame.size < size) frame = ByteArray(size)
        data.get(frame, 0, size)
        val frames = try {
            alac.decode(frame, 0, size)
        } catch (e: AlacException) {
            return AlacDecoderException(e.message ?: "ALAC frame is damaged", e)
        }
        val bytes = alac.writeLittleEndian(frames, pcm)
        val out = outputBuffer.init(inputBuffer.timeUs, bytes)
        out.put(pcm, 0, bytes)
        out.flip()
        return null
    }
}

// Plays ALAC on any phone, through the same audio output (and so the same
// shaping, loudness and taps) as every other song.
@UnstableApi
class AlacAudioRenderer(
    eventHandler: Handler?,
    eventListener: AudioRendererEventListener?,
    audioSink: AudioSink,
) : DecoderAudioRenderer<AlacMediaDecoder>(eventHandler, eventListener, audioSink) {
    override fun getName(): String = "OctoAlacRenderer"

    override fun supportsFormatInternal(format: Format): Int = alacSupport(format, ::sinkSupportsFormat)

    override fun createDecoder(format: Format, cryptoConfig: CryptoConfig?): AlacMediaDecoder = AlacMediaDecoder(format)

    override fun getOutputFormat(decoder: AlacMediaDecoder): Format = decoder.outputFormat
}

// How the unplayable-audio renderer rates `format`: any audio, just below
// a decoder that can play it, so it is only chosen when nothing else can
// play the song's sound.
fun unplayableAudioSupport(mimeType: String?): Int =
    if (MimeTypes.isAudio(mimeType)) C.FORMAT_EXCEEDS_CAPABILITIES else C.FORMAT_UNSUPPORTED_TYPE

// No phone decoder can play this song's sound.
class NoAudioDecoderException(mimeType: String?) : Exception("No decoder on this phone plays ${mimeType ?: "this audio"}")

// Takes the sound no other renderer can play and fails the song with
// "format unsupported", so it is reported and skipped like any song that
// cannot play. Without it the player picks no audio at all and runs the
// song's length in silence.
@UnstableApi
class UnplayableAudioRenderer : BaseRenderer(C.TRACK_TYPE_AUDIO) {
    private var format: Format? = null

    override fun getName(): String = "OctoUnplayableAudio"

    override fun supportsFormat(format: Format): Int = RendererCapabilities.create(unplayableAudioSupport(format.sampleMimeType))

    override fun onStreamChanged(formats: Array<Format>, startPositionUs: Long, offsetUs: Long, mediaPeriodId: MediaSource.MediaPeriodId) {
        format = formats.firstOrNull()
    }

    override fun render(positionUs: Long, elapsedRealtimeUs: Long) {
        val format = format
        throw createRendererException(
            NoAudioDecoderException(format?.sampleMimeType),
            format,
            PlaybackException.ERROR_CODE_DECODING_FORMAT_UNSUPPORTED,
        )
    }

    override fun isReady(): Boolean = false

    override fun isEnded(): Boolean = false

    override fun onDisabled() {
        format = null
    }
}
