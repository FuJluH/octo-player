package app.winters.octo.playback

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

class RadioItemsTest {
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

    @Test
    fun theStreamsSongGoesOverTheStationsName() {
        assertEquals(RadioLines("Nina Simone - Feeling Good", "KEXP"), radioLines("  Nina Simone - Feeling Good ", "KEXP"))
    }

    @Test
    fun withNoSongTheStationShowsOverRadio() {
        listOf(null, "", "   ", " - ", "KEXP", "kexp").forEach {
            assertEquals("$it", RadioLines("KEXP", RADIO_ARTIST), radioLines(it, "KEXP"))
        }
        // A station with no name shows its address.
        assertEquals(RadioLines("http://host/live", RADIO_ARTIST), radioLines(null, "", "http://host/live"))
        assertEquals(RadioLines("Song", RADIO_ARTIST), radioLines("Song", ""))
    }

    @Test
    fun aVeryLongTitleIsCut() {
        assertEquals(200, radioLines("x".repeat(500), "KEXP").title.length)
    }

    @Test
    fun aStationRetriesWithGrowingWaitsThenGivesUp() {
        assertEquals(listOf(1_000L, 2_000L, 4_000L, 8_000L), (1..RADIO_RETRIES).map { radioRetryDelayMs(it, lasting = false) })
        assertEquals(androidx.media3.common.C.TIME_UNSET, radioRetryDelayMs(RADIO_RETRIES + 1, lasting = false))
        assertEquals(androidx.media3.common.C.TIME_UNSET, radioRetryDelayMs(1, lasting = true))
    }

    @Test
    fun aDroppedConnectionIsWorthTryingAgainAndABadStreamIsNot() {
        assertFalse(lastingRadioError(java.io.IOException("connection reset")))
        assertFalse(lastingRadioError(java.net.SocketTimeoutException()))
        assertTrue(lastingRadioError(java.io.FileNotFoundException()))
        assertTrue(lastingRadioError(androidx.media3.common.ParserException.createForMalformedContainer("not audio", null)))
    }

    @Test
    fun aStationIsOpenedAgainAFewTimesAWhile() {
        val drops = RadioDrops(max = 3, windowMs = 120_000)
        assertTrue(drops.allow(0))
        assertTrue(drops.allow(10_000))
        assertTrue(drops.allow(20_000))
        assertFalse(drops.allow(30_000))
        // Once the first drop is two minutes old, one more is allowed.
        assertTrue(drops.allow(121_000))
    }

    @Test
    fun theSongIsReadFromTheStreamsIcyMetadata() {
        val icy = androidx.media3.extractor.metadata.icy.IcyInfo(byteArrayOf(), "Khruangbin - Maria También", null)
        assertEquals(IcyTitle("Khruangbin - Maria También"), icyTitleOf(androidx.media3.common.Metadata(icy)))
        // ICY metadata that names no song, and metadata that is not ICY at all.
        assertEquals(IcyTitle(null), icyTitleOf(androidx.media3.common.Metadata(androidx.media3.extractor.metadata.icy.IcyInfo(byteArrayOf(), null, "https://x"))))
        assertNull(icyTitleOf(androidx.media3.common.Metadata()))
    }
}
