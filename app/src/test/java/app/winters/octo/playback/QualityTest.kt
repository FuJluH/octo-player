package app.winters.octo.playback

import androidx.media3.common.C
import androidx.media3.common.Format
import androidx.media3.common.MimeTypes
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Test

class QualityTest {
    @Test
    fun theOutputsRateShowsOnlyWhenItDiffers() {
        val hiRes = audioQuality(MimeTypes.AUDIO_FLAC, null, C.ENCODING_PCM_24BIT, 96_000, 0)!!
        assertEquals("FLAC · 24-bit · 96 kHz · plays at 48 kHz", hiRes.playingAt(48_000).full)
        assertEquals("FLAC · 24-bit · 96 kHz", hiRes.playingAt(96_000).full)
        assertEquals("FLAC · 24-bit · 96 kHz", hiRes.playingAt(null).full)
    }

    @Test
    fun cdQualityFlacIsLossless() {
        val quality = audioQuality("audio/flac", "audio/flac", C.ENCODING_PCM_16BIT, 44_100, Format.NO_VALUE)!!
        assertEquals("Lossless", quality.label)
        assertEquals("FLAC · 16-bit · 44.1 kHz", quality.full)
    }

    @Test
    fun above48KilohertzIsHiRes() {
        val quality = audioQuality("audio/flac", "audio/flac", C.ENCODING_PCM_24BIT, 96_000, Format.NO_VALUE)!!
        assertEquals("Hi-Res", quality.label)
        assertEquals("FLAC · 24-bit · 96 kHz", quality.full)
    }

    @Test
    fun twentyFourBitAt48IsStillLossless() {
        val quality = audioQuality("audio/flac", "audio/flac", C.ENCODING_PCM_24BIT, 48_000, Format.NO_VALUE)!!
        assertEquals("Lossless", quality.label)
        assertEquals("FLAC · 24-bit · 48 kHz", quality.full)
    }

    @Test
    fun lossyShowsItsCodecAndBitrate() {
        val quality = audioQuality("audio/mpeg", "audio/mpeg", Format.NO_VALUE, 44_100, 320_000)!!
        assertEquals("MP3", quality.label)
        assertEquals("MP3 · 320 kbps", quality.full)
    }

    @Test
    fun lossyWithoutBitrateShowsSampleRate() {
        val quality = audioQuality("audio/opus", "audio/ogg", Format.NO_VALUE, 48_000, Format.NO_VALUE)!!
        assertEquals("Opus", quality.label)
        assertEquals("Opus · 48 kHz", quality.full)
    }

    @Test
    fun beforeTheDecoderReportsTheFileTypeIsUsed() {
        val quality = audioQuality(null, "audio/flac", Format.NO_VALUE, Format.NO_VALUE, Format.NO_VALUE)!!
        assertEquals("Lossless", quality.label)
        assertEquals("FLAC", quality.full)
    }

    // A song can arrive as another file than the one listed: once it is
    // open, the badge is the file that opened.
    @Test
    fun theFileOpenedWinsOverTheListedType() {
        val flac = audioQuality("audio/flac", "audio/mpeg", C.ENCODING_PCM_16BIT, 44_100, Format.NO_VALUE)!!
        assertEquals("Lossless", flac.label)
        assertEquals("FLAC · 16-bit · 44.1 kHz", flac.full)
        val aac = audioQuality("audio/mp4a-latm", "audio/flac", Format.NO_VALUE, 44_100, 256_000)!!
        assertEquals("AAC", aac.label)
        assertEquals("AAC · 256 kbps", aac.full)
    }

    @Test
    fun unknownTypeHasNoBadge() {
        assertNull(audioQuality(null, "audio/x-unknown", Format.NO_VALUE, Format.NO_VALUE, Format.NO_VALUE))
    }
}
