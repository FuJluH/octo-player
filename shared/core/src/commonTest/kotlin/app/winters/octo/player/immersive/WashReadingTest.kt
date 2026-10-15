package app.winters.octo.player.immersive

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class WashReadingTest {
    private fun rgb(r: Int, g: Int, b: Int) = (0xFF shl 24) or (r shl 16) or (g shl 8) or b

    private val page = rgb(0x0C, 0x0C, 0x0D)
    private val accent = rgb(0x97, 0xB1, 0xB9)
    private val white = rgb(255, 255, 255)

    // A cover of one colour, prepared as the wash prepares covers.
    private fun prepared(argb: Int, tuning: WashTuning = WashTuning()) = IntArray(64 * 64) { prepareColor(argb, tuning) }

    @Test
    fun thePeakIsTheBrightestFewAsTheFinalPassLeavesThem() {
        // Mostly black, with 5% of it bright green: the green is the peak,
        // dimmed by the final pass.
        val pixels = IntArray(1000) { if (it % 20 == 0) rgb(0, 200, 0) else rgb(0, 0, 0) }
        val peak = washPeak(pixels, step = 1)
        assertEquals((200 * FinalGain).toInt().toFloat(), (peak shr 8 and 0xFF).toFloat(), 1f)
        // A single bright pixel in a thousand is blurred away: no peak.
        val speck = IntArray(1000) { if (it == 500) rgb(255, 255, 255) else rgb(10, 10, 10) }
        assertEquals(rgb(9, 9, 9), washPeak(speck, step = 1))
    }

    @Test
    fun aDarkCoverShowsAsMuchAsAsked() {
        val navy = washPeak(prepared(rgb(0x10, 0x18, 0x30)))
        assertEquals(0.9f, readableAlpha(navy, page, accent, 4.5, 0.9f), 1e-6f)
    }

    @Test
    fun aBrightCoverShowsFainterSoTheWordsStillRead() {
        for (cover in listOf(rgb(255, 224, 0), rgb(0, 255, 0), rgb(0xF4, 0xEE, 0xDC), rgb(255, 255, 255), rgb(0, 255, 255))) {
            val peak = washPeak(prepared(cover))
            val alpha = readableAlpha(peak, page, accent, 4.5, 0.9f)
            val behind = overlay(peak, alpha, page)
            assertTrue("accent on ${Integer.toHexString(cover)} at $alpha", contrastRatio(accent, behind) >= 4.5)
            // White titles read easily.
            assertTrue(contrastRatio(white, behind) >= 7.0)
            // And it is the most that reads: a little more would not.
            if (alpha < 0.9f) assertFalse(contrastRatio(accent, overlay(peak, alpha + 0.02f, page)) >= 4.5)
        }
        // Yellow and green, the brightest covers once prepared, still show.
        assertTrue(readableAlpha(washPeak(prepared(rgb(255, 224, 0))), page, accent, 4.5, 0.9f) > 0.25f)
    }

    @Test
    fun overlayMixesChannelByChannel() {
        assertEquals(page, overlay(white, 0f, page))
        assertEquals(white, overlay(white, 1f, page))
        assertEquals(rgb(134, 134, 134), overlay(white, 0.5f, page))
    }

    // A 512 square, prepared, of `ground` with a disc of `shape` in the
    // middle a third across, as the made-up covers are.
    private fun square(ground: Int, shape: Int, tuning: WashTuning = WashTuning()): IntArray {
        val g = prepareColor(ground, tuning)
        val s = prepareColor(shape, tuning)
        return IntArray(512 * 512) { i ->
            val x = i % 512 - 256
            val y = i / 512 - 256
            if (x * x + y * y < 90 * 90) s else g
        }
    }

    // The words' colour, as ARGB, and what they sit on at worst.
    private fun worst(ink: WashInk, range: WashRange): Double {
        val words = if (ink.dark) DarkInkArgb else white
        return minOf(contrastRatio(words, overlay(range.low, ink.show, page)), contrastRatio(words, overlay(range.high, ink.show, page)))
    }

    @Test
    fun theRangeIsTheDarkestAndBrightestPatch() {
        val range = washRange(square(rgb(0x3A, 0xA6, 0xA0), rgb(0x1B, 0x2A, 0x4A)), 512)
        assertTrue(relativeLuminance(range.high) > 0.3)
        assertTrue(relativeLuminance(range.low) < 0.05)
        // A lone bright pixel is blurred away.
        val speck = IntArray(512 * 512) { if (it == 1000) white else rgb(10, 10, 10) }
        assertEquals(rgb(10, 10, 10), washRange(speck, 512).high)
        assertEquals(WashRange(rgb(1, 2, 3), rgb(200, 200, 200)), WashRange.of(rgb(200, 200, 200), rgb(1, 2, 3)))
    }

    @Test
    fun aCoverLightInPlacesAndDarkInOthersGetsWhiteWordsAndADim() {
        // The teal cover with a navy disc: its main colour is light, yet the
        // wash is dark in places, so dark words would vanish there.
        val range = washRange(square(rgb(0x3A, 0xA6, 0xA0), rgb(0x1B, 0x2A, 0x4A)), 512).scaled(FinalGain)
        val ink = inkOver(range, page)
        assertFalse(ink.dark)
        assertTrue(ink.show < 1f)
        assertTrue(worst(ink, range) >= 4.5)
    }

    @Test
    fun everyCoverReadsWhicheverWordsItGets() {
        val covers = listOf(
            rgb(0x10, 0x18, 0x30) to rgb(0x8A, 0x1C, 0x3C),
            rgb(0x3A, 0xA6, 0xA0) to rgb(0x1B, 0x2A, 0x4A),
            rgb(0xFF, 0xE0, 0x00) to rgb(0xFF, 0x8A, 0x00),
            rgb(0xFF, 0xFF, 0xFF) to rgb(0xF2, 0xEA, 0xD8),
            rgb(0x00, 0xFF, 0x40) to rgb(0xB0, 0xFF, 0x00),
        )
        for (tuning in listOf(WashTuning(), WashTuning(brightnessCap = 1f), WashTuning(contrast = 2f, saturation = 3f, brightnessCap = 1f))) {
            for ((ground, shape) in covers) {
                val range = washRange(square(ground, shape, tuning), 512).scaled(FinalGain)
                val ink = inkOver(range, page)
                assertTrue("${Integer.toHexString(ground)} at $tuning: $ink", worst(ink, range) >= 4.5)
            }
        }
    }

    @Test
    fun wordsGoDarkOverAWashLightAllOver() {
        // A pale cover with no cap: light everywhere, so dark words, and the
        // wash shows whole.
        val range = washRange(square(rgb(0xF4, 0xEE, 0xDC), rgb(0xF2, 0xEA, 0xD8), WashTuning(contrast = 1f, saturation = 1f, brightnessCap = 1f)), 512)
        assertEquals(WashInk(dark = true, show = 1f), inkOver(range, page))
        // A dark one keeps white words over the whole of it.
        assertEquals(WashInk(dark = false, show = 1f), inkOver(WashRange.of(rgb(0x10, 0x18, 0x30), rgb(0x40, 0x10, 0x20)), page))
    }

    @Test
    fun theChoicesAreThePhones() {
        assertEquals(listOf(30, 60, 90, 120), FpsChoices)
        assertEquals(20..100, BrightnessCapRange)
        assertEquals(5..100, SpeedRange)
    }

    @Test
    fun quietIconsShowSoftlyWhereTheyStillRead() {
        val white = 0xFFFFFFFF.toInt()
        val black = 0xFF000000.toInt()
        assertEquals(0.7f, quietAlpha(black, white, 0.7f), 0f)
        assertTrue(contrastRatio(overlay(white, 0.7f, black), black) >= 4.5)
    }

    @Test
    fun overABackgroundAtTheWordsLimitQuietIconsShowMore() {
        val white = 0xFFFFFFFF.toInt()
        // A grey white words just read on.
        val grey = 0xFF767676.toInt()
        val alpha = quietAlpha(grey, white, 0.7f)
        assertTrue(alpha > 0.7f)
        assertTrue(contrastRatio(overlay(white, alpha, grey), grey) >= 4.5 || alpha == 1f)
    }

    @Test
    fun darkWordsQuietIconsReadOnTheBrightestCover() {
        val dark = DarkInkArgb
        val light = 0xFFF0F0F0.toInt()
        val alpha = quietAlpha(light, dark, 0.7f)
        assertTrue(contrastRatio(overlay(dark, alpha, light), light) >= 4.5)
    }
}
