package app.winters.octo.playback

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

// A station as the phone's player shows and opens it: the song its stream
// names, and how it is opened again after a drop.
class RadioItemsTest {
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
