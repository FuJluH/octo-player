package app.winters.octo.animated

import app.winters.octo.player.immersive.DarkInkArgb
import app.winters.octo.player.immersive.PlayerContrast
import app.winters.octo.player.immersive.contrastRatio
import app.winters.octo.player.immersive.overlay
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class BackdropInkTest {
    private val white = 0xFFFFFFFF.toInt()
    private val black = 0xFF000000.toInt()

    // Whatever frame of the loop shows through the fade, the words read.
    private fun readsOverAnyFrame(ink: BackdropInk) {
        val words = if (ink.dark) DarkInkArgb else white
        for (frame in listOf(white, black, 0xFF808080.toInt(), 0xFFFF0000.toInt(), 0xFF00FF00.toInt(), 0xFF0000FF.toInt())) {
            val under = overlay(ink.color, ink.scrim, frame)
            assertTrue("%06x over %06x".format(words and 0xFFFFFF, under and 0xFFFFFF), contrastRatio(words, under) >= PlayerContrast - 0.01)
        }
    }

    @Test
    fun aDarkClipGetsWhiteWords() {
        val ink = backdropInk(0x1B2A3A)
        assertFalse(ink.dark)
        assertEquals(0xFF1B2A3A.toInt(), ink.color)
        assertTrue(ink.scrim in BACKDROP_LEAST_SCRIM..1f)
        readsOverAnyFrame(ink)
    }

    @Test
    fun aLightClipGetsDarkWords() {
        val ink = backdropInk(0xF2E6C8)
        assertTrue(ink.dark)
        readsOverAnyFrame(ink)
    }

    @Test
    fun aMiddleGrayIsDarkenedUntilWordsRead() {
        val gray = 0xFF6E6E6E.toInt()
        val ink = backdropInk(gray)
        assertTrue(contrastRatio(if (ink.dark) DarkInkArgb else white, ink.color) >= PlayerContrast)
        readsOverAnyFrame(ink)
    }

    @Test
    fun aBlackClipNeedsOnlyTheLeastScrim() {
        // White words over black with a white frame under it: the fade is
        // what keeps them readable, never less than the least.
        val ink = backdropInk(black)
        assertFalse(ink.dark)
        assertTrue(ink.scrim >= BACKDROP_LEAST_SCRIM)
        readsOverAnyFrame(ink)
    }

    @Test
    fun everyColorReads() {
        for (r in 0..255 step 51) for (g in 0..255 step 51) for (b in 0..255 step 51) {
            readsOverAnyFrame(backdropInk((r shl 16) or (g shl 8) or b))
        }
    }
}
