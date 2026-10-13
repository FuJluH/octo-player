package app.winters.octo.liveradio

import org.junit.Assert.assertEquals
import org.junit.Assert.assertNotEquals
import org.junit.Assert.assertNull
import org.junit.Test

class LiveWordsTest {
    @Test
    fun httpAndHttpsAndTheHostsCaseAndAnEndingSlashMatch() {
        val key = liveStreamKey("http://Stream.Example.com/live/")
        assertEquals(key, liveStreamKey("https://stream.example.com/live"))
        assertEquals(key, liveStreamKey("  HTTPS://STREAM.EXAMPLE.COM/live  "))
        assertEquals("stream.example.com/live", key)
    }

    @Test
    fun thePathKeepsItsCase() {
        assertNotEquals(liveStreamKey("https://host/Live"), liveStreamKey("https://host/live"))
        assertEquals("host:8000/Stream?type=.mp3", liveStreamKey("http://HOST:8000/Stream?type=.mp3"))
    }

    @Test
    fun otherSchemesStayApart() {
        assertNotEquals(liveStreamKey("rtsp://host/live"), liveStreamKey("http://host/live"))
        assertEquals("host/live", liveStreamKey("host/live/"))
    }

    @Test
    fun aCodeOnItsOwn() {
        assertEquals(WhereParts(code = "55401"), parseWhere(" 55401 "))
        assertEquals(WhereParts(code = "SW1A 1AA"), parseWhere("sw1a  1aa"))
    }

    @Test
    fun aTownWithItsState() {
        assertEquals(WhereParts(name = "Austin", state = "Texas"), parseWhere("Austin, Texas"))
        assertEquals(WhereParts(name = "Saint Paul"), parseWhere("Saint Paul"))
        assertEquals(WhereParts(name = "Austin"), parseWhere("Austin,"))
    }

    @Test
    fun theWordWithADigitIsTheCodeAndTheRestTheTownAndState() {
        assertEquals(WhereParts(code = "78701", name = "Austin", state = "TX"), parseWhere("Austin, TX 78701"))
        assertEquals(WhereParts(code = "10001", state = "NY"), parseWhere("10001, NY"))
        assertEquals(WhereParts(code = "M5V 2T6", name = "Toronto", state = "ON"), parseWhere("Toronto, ON M5V 2T6"))
    }

    @Test
    fun nothingToLookUp() {
        assertNull(parseWhere("   "))
        assertNull(parseWhere(", Texas"))
    }
}
