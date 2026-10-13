package app.winters.octo.playback

import app.winters.octo.catalog.relinkKey
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNotEquals
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

class StoresTest {
    @Test
    fun halfTheSongCountsAsAPlay() {
        assertTrue(countsAsPlay(playedMs = 90_000, durationMs = 180_000))
        assertFalse(countsAsPlay(playedMs = 89_000, durationMs = 180_000))
    }

    @Test
    fun fourMinutesCountsForLongSongs() {
        assertTrue(countsAsPlay(playedMs = 240_000, durationMs = 1_200_000))
        assertFalse(countsAsPlay(playedMs = 239_000, durationMs = 1_200_000))
    }

    @Test
    fun shortClipsNeverCount() {
        assertFalse(countsAsPlay(playedMs = 29_000, durationMs = 29_000))
    }

    @Test
    fun queueRoundTripsWithShuffleOrder() {
        val snapshot = QueueSnapshot(
            trackIds = listOf("device:1", "device:2", "device:3"),
            shuffleOrder = listOf(2, 0, 1),
            index = 1,
            positionMs = 42_000,
            repeatMode = 2,
            shuffle = true,
        )
        val (items, state) = snapshot.toRows(now = 0)
        assertEquals(snapshot, queueFromRows(items, state))
    }

    // A queue parked for another account keeps where each song came from,
    // so a station played there keeps going when it comes back.
    @Test
    fun aParkedQueueKeepsWhereEachSongCameFrom() {
        val snapshot = QueueSnapshot(listOf("a", "b"), emptyList(), 0, 0, 0, false, listOf("station:or1:Your Radio", "autoplay"))
        assertEquals(snapshot, decodeQueue(encodeQueue(snapshot)))
        assertEquals(emptyList<String>(), decodeQueue(encodeQueue(snapshot.copy(sources = emptyList())))!!.sources)
    }

    @Test
    fun emptyQueueRestoresAsNothing() {
        assertNull(queueFromRows(emptyList(), null))
    }

    @Test
    fun relinkKeyIgnoresCaseAndAccentsButNotLength() {
        val a = relinkKey("Beyoncé", "Lemonade", 1, 3, "Hold Up", 221_400)
        val b = relinkKey("beyonce", "lemonade", 1, 3, "hold up", 221_900)
        assertEquals(a, b)
        assertNotEquals(a, relinkKey("Beyoncé", "Lemonade", 1, 3, "Hold Up", 230_000))
    }
}
