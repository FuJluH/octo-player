package app.winters.octo.ui.home

import app.winters.octo.discovery.Station
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class StationsTest {
    private val now = 1_000_000_000L

    @Test
    fun loadsWhenNeverLoaded() {
        assertTrue(stationsDue(now, loadedAt = null, failed = false, loading = false))
    }

    @Test
    fun neverLoadsTwiceAtOnce() {
        assertFalse(stationsDue(now, loadedAt = null, failed = true, loading = true))
        assertFalse(stationsDue(now, loadedAt = now - STATIONS_STALE_MS * 2, failed = false, loading = true))
    }

    @Test
    fun loadsAgainAfterAFailure() {
        assertTrue(stationsDue(now, loadedAt = now - 1_000, failed = true, loading = false))
    }

    @Test
    fun keepsAFreshList() {
        assertFalse(stationsDue(now, loadedAt = now - 1_000, failed = false, loading = false))
        assertFalse(stationsDue(now, loadedAt = now - STATIONS_STALE_MS + 1, failed = false, loading = false))
    }

    @Test
    fun loadsAgainOnceStale() {
        assertTrue(stationsDue(now, loadedAt = now - STATIONS_STALE_MS, failed = false, loading = false))
    }

    @Test
    fun aMadeForYouListSaysHowManySongs() {
        assertEquals("1 song", songCountLine(1))
        assertEquals("24 songs", songCountLine(24))
    }

    @Test
    fun aStationTheServerNoLongerHasSaysSo() {
        assertEquals("Chill mix isn't on the server any more", stationGoneLine("Chill mix"))
    }

    // A station with songs opens its list on a tap; one that is a stream has
    // nothing to show and plays.
    @Test
    fun aTapOpensASongListAndPlaysAStream() {
        assertTrue(opensOnTap(Station("or3kZ9QpLmN2xY7wV1bC0a", "Your Radio", null)))
        assertTrue(opensOnTap(Station("og1", "New Releases", null, songCount = 40)))
        assertFalse(opensOnTap(Station("rs-1", "City Radio", null, streamUrl = "https://radio.example.com/live.mp3")))
    }
}
