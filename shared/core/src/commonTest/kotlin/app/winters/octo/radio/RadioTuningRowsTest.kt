package app.winters.octo.radio

import app.winters.octo.discovery.LIBRARY_ONLY_SETTING
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

// How the Discovery row reads, alone and with Library songs only on.
class RadioTuningRowsTest {
    @Test
    fun discoveryShowsTheChoiceAndWhatItMeans() {
        val look = discoveryRowLook(RadioDiscovery.Lots, libraryOnly = false, where = "Playback")
        assertEquals(DiscoveryRowLook(choosable = true, value = "Lots", helper = RadioDiscovery.Lots.detail), look)
    }

    @Test
    fun libraryOnlyTakesDiscoveryOverAndSaysWhereToTurnItOff() {
        val look = discoveryRowLook(RadioDiscovery.Lots, libraryOnly = true, where = "Library settings")
        assertFalse(look.choosable)
        assertEquals(RadioDiscovery.LibraryOnly.label, look.value)
        assertTrue(look.helper.startsWith("$LIBRARY_ONLY_SETTING is on in Library settings"))
        assertTrue(look.helper.contains("Turn it off there to choose."))
    }
}
