package app.winters.octo.playback

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

// A station as the phone's player shows and opens it: the song its stream
// names, which loader opens it, and how it is opened again after a drop.
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
    fun aStreamThatEndsIsOpenedAgainAFewTimesAWhile() {
        var clock = 0L
        val ends = RadioEnds(windowMs = 120_000, now = { clock })
        repeat(RADIO_RETRIES) {
            assertTrue(ends.ended("http://s/a"))
            clock += 10_000
        }
        assertEquals(RADIO_RETRIES, ends.recent("http://s/a"))
        // Once more in the same while: it is let end, and the queue moves on.
        assertFalse(ends.ended("http://s/a"))
        assertEquals(0, ends.recent("http://s/a"))
        // Another station keeps its own count.
        assertTrue(ends.ended("http://s/b"))
        // Ends older than the window are forgotten.
        clock += 200_000
        assertEquals(0, ends.recent("http://s/b"))
    }

    @Test
    fun aStationGoesToTheLoaderForItsKind() {
        assertEquals(RadioLoader.None, radioLoader("device:12"))
        assertEquals(RadioLoader.Stream, radioLoader(radioId("http://s/live.mp3", "One")))
        assertEquals(RadioLoader.Hls, radioLoader(radioId("http://s/live", "Two", hls = true)))
        assertEquals(RadioLoader.Hls, radioLoader(radioId("https://s/master.M3U8?token=1", "Three")))
    }

    @Test
    fun newWordsForTheSameItemsLeaveABlendAlone() {
        val items = listOf("radio:a:b" to "q:1")
        assertTrue(wordsOnly(items, listOf("radio:a:b" to "q:1")))
        assertFalse(wordsOnly(items, listOf("radio:c:d" to "q:1")))
        assertFalse(wordsOnly(items, listOf("radio:a:b" to null)))
        assertFalse(wordsOnly(emptyList(), emptyList()))
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
