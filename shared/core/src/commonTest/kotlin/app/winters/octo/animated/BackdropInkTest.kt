package app.winters.octo.animated

import app.winters.octo.player.immersive.DarkInkArgb
import app.winters.octo.player.immersive.contrastRatio
import app.winters.octo.player.immersive.overlay
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class BackdropInkTest {
    private val white = 0xFFFFFFFF.toInt()
    private val blueGray = 0xFF97B1B9.toInt()

    // Every color of the fill, dimmed as the ink says, keeps the contrast
    // each thing over it needs.
    private fun readsOn(ink: FillInk, vararg colors: Int) {
        for (color in colors) {
            val under = dimmed(color, ink.gain)
            val name = "%06x".format(under and 0xFFFFFF)
            if (ink.dark) {
                assertTrue(name, contrastRatio(DarkInkArgb, under) >= 8.0)
                assertTrue(name, contrastRatio(overlay(DarkInkArgb, 0.6f, under), under) >= 4.5)
                assertTrue(name, contrastRatio(overlay(DarkInkArgb, 0.45f, under), under) >= 3.0)
            } else {
                assertTrue(name, contrastRatio(white, under) >= 8.0)
                assertTrue(name, contrastRatio(blueGray, under) >= 4.5)
                assertTrue(name, contrastRatio(overlay(blueGray, 0.8f, under), under) >= 4.5)
                assertTrue(name, contrastRatio(overlay(white, 0.45f, under), under) >= 3.0)
            }
        }
    }

    @Test
    fun aDarkFillKeepsItsColorUnderWhiteWords() {
        val ink = fillInk(0xFF0A0F14.toInt(), 0xFF141B22.toInt())
        assertFalse(ink.dark)
        assertEquals(1f, ink.gain)
        readsOn(ink, 0xFF0A0F14.toInt(), 0xFF141B22.toInt())
    }

    @Test
    fun aBrownFillIsDimmedJustEnough() {
        val low = 0xFF2A1A12.toInt()
        val high = 0xFF8A5A3C.toInt()
        val ink = fillInk(low, high)
        assertFalse(ink.dark)
        assertTrue(ink.gain < 1f && ink.gain > 0.2f)
        readsOn(ink, low, high)
        // A little brighter and its brightest part would not read.
        val brighter = dimmed(high, ink.gain + 0.05f)
        assertTrue(contrastRatio(white, brighter) < 8.0 || contrastRatio(overlay(blueGray, 0.8f, brighter), brighter) < 4.5)
    }

    @Test
    fun aPaleFillIsDimmedUnderWhiteWords() {
        // The player's quiet icons, dark at 45%, would not keep 3:1 even on
        // white, so its words are white and a pale fill is dimmed for them.
        val pale = fillInk(0xFFE8E0D0.toInt(), 0xFFF6F2EA.toInt())
        assertFalse(pale.dark)
        readsOn(pale, 0xFFE8E0D0.toInt(), 0xFFF6F2EA.toInt())
        assertFalse(fillInk(white, white).dark)
        // Where only the words count, a pale fill keeps its color under dark ones.
        val wordsOnly = fillInk(0xFFE8E0D0.toInt(), 0xFFF6F2EA.toInt(), listOf(InkNeed(alpha = 1f, contrast = 8.0)))
        assertTrue(wordsOnly.dark)
        assertEquals(1f, wordsOnly.gain)
    }

    @Test
    fun aFillLightAndDarkInPlacesGetsWhiteWords() {
        val ink = fillInk(0xFF101820.toInt(), 0xFFF0F0F0.toInt())
        assertFalse(ink.dark)
        readsOn(ink, 0xFF101820.toInt(), 0xFFF0F0F0.toInt())
    }

    @Test
    fun everyFillReads() {
        for (r in 0..255 step 51) for (g in 0..255 step 51) for (b in 0..255 step 51) {
            val color = 0xFF000000.toInt() or (r shl 16) or (g shl 8) or b
            readsOn(fillInk(color, color), color)
        }
    }
}
