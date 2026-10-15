package app.winters.octo.ui.sound

import org.junit.Assert.assertEquals
import org.junit.Test

class SoundReadingsTest {
    @Test
    fun readingsAreShortAndPlain() {
        assertEquals("+3.5 dB", readDb(3.5f))
        assertEquals("-2 dB", readDb(-2f))
        assertEquals("0 dB", readDb(-0.01f))
        assertEquals("62 Hz, +3 dB", describeNode(62f, 3f))
        assertEquals("1k", shortHz(1_000f))
        assertEquals("16k", shortHz(16_000f))
        assertEquals("1.2 kHz", readHz(1_200f))
        assertEquals("Center", readBalance(0.004f))
        assertEquals("30% left", readBalance(-0.3f))
    }
}
