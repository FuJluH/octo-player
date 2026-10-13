package app.winters.octo.sound

import androidx.media3.common.C
import androidx.media3.common.Format
import androidx.media3.common.MimeTypes
import androidx.media3.common.PlaybackException
import app.winters.octo.playback.PlayFailure
import app.winters.octo.playback.playFailureOf
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test

class AlacRendererTest {
    private val setup = byteArrayOf(
        0, 0, 16, 0, 0, 16, 40, 10, 14, 2, 0, 255.toByte(),
        0, 0, 0, 0, 0, 0, 0, 0, 0, 0, 0xAC.toByte(), 0x44,
    )

    private fun alac(init: ByteArray? = setup): Format = Format.Builder()
        .setSampleMimeType(MimeTypes.AUDIO_ALAC)
        .setChannelCount(2)
        .setSampleRate(44_100)
        .setInitializationData(listOfNotNull(init))
        .build()

    @Test
    fun alacWithItsSetupIsPlayed() {
        assertEquals(C.FORMAT_HANDLED, alacSupport(alac()) { true })
    }

    @Test
    fun itDecodesToPcmTheOutputTakes() {
        val asked = ArrayList<Format>()
        alacSupport(alac()) { asked.add(it); true }
        val pcm = asked.single()
        assertEquals(MimeTypes.AUDIO_RAW, pcm.sampleMimeType)
        assertEquals(C.ENCODING_PCM_16BIT, pcm.pcmEncoding)
        assertEquals(2, pcm.channelCount)
        assertEquals(44_100, pcm.sampleRate)
        // An output that cannot take it leaves the song to another renderer.
        assertEquals(C.FORMAT_UNSUPPORTED_SUBTYPE, alacSupport(alac()) { false })
    }

    @Test
    fun deeperAlacDecodesToWiderPcm() {
        val twentyFour = AlacConfig.parse(setup.copyOf().also { it[5] = 24 })
        assertEquals(C.ENCODING_PCM_24BIT, alacPcmFormat(twentyFour).pcmEncoding)
        val twenty = AlacConfig.parse(setup.copyOf().also { it[5] = 20 })
        assertEquals(C.ENCODING_PCM_24BIT, alacPcmFormat(twenty).pcmEncoding)
        val thirtyTwo = AlacConfig.parse(setup.copyOf().also { it[5] = 32 })
        assertEquals(C.ENCODING_PCM_32BIT, alacPcmFormat(thirtyTwo).pcmEncoding)
    }

    @Test
    fun otherSoundIsLeftToThePhonesDecoders() {
        val aac = Format.Builder().setSampleMimeType(MimeTypes.AUDIO_AAC).build()
        assertEquals(C.FORMAT_UNSUPPORTED_TYPE, alacSupport(aac) { true })
        assertEquals(C.FORMAT_UNSUPPORTED_SUBTYPE, alacSupport(alac(init = null)) { true })
        assertEquals(C.FORMAT_UNSUPPORTED_SUBTYPE, alacSupport(alac(init = ByteArray(10))) { true })
    }

    // The unplayable-audio renderer rates any sound just below a decoder
    // that can play it, so it only gets a song nothing else can play.
    @Test
    fun soundNothingCanPlayFailsAsUnsupported() {
        assertEquals(C.FORMAT_EXCEEDS_CAPABILITIES, unplayableAudioSupport(MimeTypes.AUDIO_ALAC))
        assertEquals(C.FORMAT_EXCEEDS_CAPABILITIES, unplayableAudioSupport(MimeTypes.AUDIO_AC3))
        assertEquals(C.FORMAT_EXCEEDS_CAPABILITIES, unplayableAudioSupport("audio/x-unknown"))
        assertTrue(unplayableAudioSupport(MimeTypes.AUDIO_FLAC) < C.FORMAT_HANDLED)
        assertEquals(C.FORMAT_UNSUPPORTED_TYPE, unplayableAudioSupport(MimeTypes.VIDEO_H264))
        assertEquals(C.FORMAT_UNSUPPORTED_TYPE, unplayableAudioSupport(MimeTypes.APPLICATION_ID3))
        assertEquals(C.FORMAT_UNSUPPORTED_TYPE, unplayableAudioSupport(null))
        // Its failure reads like any other file the phone cannot play.
        assertEquals(PlayFailure.Unsupported, playFailureOf(PlaybackException.ERROR_CODE_DECODING_FORMAT_UNSUPPORTED))
    }
}
