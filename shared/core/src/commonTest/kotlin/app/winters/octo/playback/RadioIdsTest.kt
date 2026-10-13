package app.winters.octo.playback

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

class RadioIdsTest {
    @Test
    fun aStationRoundTrips() {
        val id = radioId("https://stream.example:8443/fip.mp3?type=http&x=1", "FIP: Jazz & more")
        assertTrue(isRadio(id))
        assertEquals("https://stream.example:8443/fip.mp3?type=http&x=1" to "FIP: Jazz & more", radioOf(id))
    }

    @Test
    fun colonsAreEncodedSoThePartsSplitCleanly() {
        val id = radioId("http://a:b@host:8000/live", "One: Two")
        assertEquals(2, id.removePrefix(RADIO_PREFIX).split(':').size)
    }

    @Test
    fun theNameMayBeEmpty() {
        val id = radioId(" http://host/live ")
        assertEquals("http://host/live" to "", radioOf(id))
    }

    @Test
    fun otherIdsAreNotStations() {
        assertFalse(isRadio("find:abc"))
        assertFalse(isRadio("device:12"))
        assertNull(radioOf("device:12"))
        // A station id with no address is not playable.
        assertNull(radioOf("radio::name"))
    }

    @Test
    fun anHlsStationSaysSoInItsId() {
        val id = radioId("https://fip.example/live", "FIP", hls = true)
        assertTrue(radioIsHls(id))
        // The address and name read as before.
        assertEquals("https://fip.example/live" to "FIP", radioOf(id))
        assertFalse(radioIsHls(radioId("https://fip.example/live", "FIP")))
        assertFalse(radioIsHls("device:12"))
    }
}
