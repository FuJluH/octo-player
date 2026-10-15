package app.winters.octo.theme

import app.winters.octo.covers.hueDistance
import app.winters.octo.covers.toLch
import app.winters.octo.player.immersive.contrastRatio
import kotlin.math.roundToInt
import org.junit.Test
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue

class AccentsTest {
    // The accent mixed into black, as the filled button draws it.
    private fun intoBlack(argb: Int, amount: Double): Int {
        fun ch(shift: Int) = ((argb shr shift and 0xFF) * (1 - amount)).roundToInt()
        return (0xFF shl 24) or (ch(16) shl 16) or (ch(8) shl 8) or ch(0)
    }

    private val white = 0xFFFFFFFF.toInt()

    @Test
    fun everyFixedAccentReadsAtAaWhereverItIsDrawn() {
        for (choice in FixedAccents) {
            val accent = choice.argb!!
            assertTrue("${choice.label} on the page", contrastRatio(accent, AccentPageArgb) >= 4.5)
            assertTrue("${choice.label} on a raised surface", contrastRatio(accent, AccentSurfaceArgb) >= 4.5)
            // The page's dark ink on an accent fill is the same pair as the page under the accent.
            assertTrue("dark ink on ${choice.label}", contrastRatio(AccentPageArgb, accent) >= 4.5)
            // A filled button (45% into black) and a selected row (60% into black) carry white words.
            assertTrue("white on a ${choice.label} button", contrastRatio(white, intoBlack(accent, 0.45)) >= 4.5)
            assertTrue("white on a ${choice.label} selected row", contrastRatio(white, intoBlack(accent, 0.60)) >= 4.5)
        }
    }

    @Test
    fun octoIsTheDefaultAndKeepsItsColour() {
        assertEquals(AccentChoice.Octo, AccentChoice.entries.first())
        assertEquals(0xFF97B1B9.toInt(), OctoAccentArgb)
        assertEquals(OctoAccentArgb, accentArgb(AccentChoice.Octo, art = 0xFFFF0000.toInt()))
    }

    @Test
    fun theChoicesHaveDistinctNamesAndColours() {
        assertEquals(AccentChoice.entries.size, AccentChoice.entries.map { it.label }.distinct().size)
        assertEquals(FixedAccents.size, FixedAccents.map { it.argb }.distinct().size)
        assertTrue(FixedAccents.size in 8..10)
    }

    @Test
    fun aCoverGivesAReadableAccentOfItsOwnHue() {
        for (cover in listOf(0xFFE01010, 0xFF1030C0, 0xFFFFE000, 0xFF0A4010, 0xFF300040, 0xFFFFC0E0)) {
            val argb = cover.toInt()
            val accent = accentFromArt(argb)
            assertTrue("a colourful cover %08X gives an accent".format(argb), accent != null)
            accent!!
            assertTrue("accent from %08X".format(argb), accentReads(accent))
            assertTrue("hue kept for %08X".format(argb), hueDistance(toLch(argb).h, toLch(accent).h) < 12)
        }
    }

    @Test
    fun aGreyCoverOrNoCoverKeepsOctosAccent() {
        assertNull(accentFromArt(0xFF808080.toInt()))
        assertNull(accentFromArt(0xFF101010.toInt()))
        assertEquals(OctoAccentArgb, accentArgb(AccentChoice.FromArt, art = null))
        assertEquals(OctoAccentArgb, accentArgb(AccentChoice.FromArt, art = 0xFF7A7A7A.toInt()))
    }

    @Test
    fun aVividCoverIsCalmedToTheAccentsLightness() {
        val accent = accentArgb(AccentChoice.FromArt, art = 0xFFFF0000.toInt())
        val lch = toLch(accent)
        assertTrue("lightness ${lch.l}", lch.l in 0.74..0.80)
        assertTrue("chroma ${lch.c}", lch.c <= 0.125)
    }
}
