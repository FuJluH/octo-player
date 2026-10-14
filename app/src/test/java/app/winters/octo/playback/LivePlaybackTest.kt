package app.winters.octo.playback

import androidx.media3.common.Player
import app.winters.octo.liveradio.LiveLineup
import app.winters.octo.liveradio.listenedFor
import app.winters.octo.liveradio.liveLineup
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

// A station as the session and the queue play it: no seeking, Back and
// Next through its lineup and never past the ends, and how long the
// listener has been on it.
class LivePlaybackTest {
    private val a = radioId("http://s/a", "A")
    private val b = radioId("http://s/b", "B")
    private val c = radioId("http://s/c", "C")

    private val songCommands = setOf(
        Player.COMMAND_PLAY_PAUSE,
        Player.COMMAND_PREPARE,
        Player.COMMAND_STOP,
        Player.COMMAND_SEEK_IN_CURRENT_MEDIA_ITEM,
        Player.COMMAND_SEEK_BACK,
        Player.COMMAND_SEEK_FORWARD,
        Player.COMMAND_SEEK_TO_DEFAULT_POSITION,
        Player.COMMAND_SEEK_TO_MEDIA_ITEM,
        Player.COMMAND_SEEK_TO_NEXT,
        Player.COMMAND_SEEK_TO_NEXT_MEDIA_ITEM,
        Player.COMMAND_SEEK_TO_PREVIOUS,
        Player.COMMAND_SEEK_TO_PREVIOUS_MEDIA_ITEM,
        Player.COMMAND_SET_SHUFFLE_MODE,
        Player.COMMAND_SET_REPEAT_MODE,
        Player.COMMAND_GET_TIMELINE,
    )

    @Test
    fun aStationOffersNoSeekingAndBackAndNextOnlyWhereThereIsAStation() {
        val middle = liveCommands(songCommands, LiveLineup(listOf(a, b, c), 1))
        listOf(Player.COMMAND_SEEK_IN_CURRENT_MEDIA_ITEM, Player.COMMAND_SEEK_BACK, Player.COMMAND_SEEK_FORWARD).forEach { assertFalse("$it", it in middle) }
        listOf(Player.COMMAND_SEEK_TO_NEXT, Player.COMMAND_SEEK_TO_NEXT_MEDIA_ITEM, Player.COMMAND_SEEK_TO_PREVIOUS, Player.COMMAND_SEEK_TO_PREVIOUS_MEDIA_ITEM)
            .forEach { assertTrue("$it", it in middle) }
        // Playing, stopping, choosing a station and the song settings stay.
        listOf(Player.COMMAND_PLAY_PAUSE, Player.COMMAND_STOP, Player.COMMAND_SEEK_TO_MEDIA_ITEM, Player.COMMAND_SET_SHUFFLE_MODE).forEach { assertTrue("$it", it in middle) }

        val first = liveCommands(songCommands, LiveLineup(listOf(a, b, c), 0))
        assertFalse(Player.COMMAND_SEEK_TO_PREVIOUS in first)
        assertFalse(Player.COMMAND_SEEK_TO_PREVIOUS_MEDIA_ITEM in first)
        assertTrue(Player.COMMAND_SEEK_TO_NEXT in first)
        val last = liveCommands(songCommands, LiveLineup(listOf(a, b, c), 2))
        assertFalse(Player.COMMAND_SEEK_TO_NEXT in last)
        assertTrue(Player.COMMAND_SEEK_TO_PREVIOUS in last)
        val alone = liveCommands(songCommands, LiveLineup(listOf(a), 0))
        assertTrue(alone.none { it in setOf(Player.COMMAND_SEEK_TO_NEXT, Player.COMMAND_SEEK_TO_PREVIOUS, Player.COMMAND_SEEK_TO_NEXT_MEDIA_ITEM, Player.COMMAND_SEEK_TO_PREVIOUS_MEDIA_ITEM) })
    }

    @Test
    fun backAndNextStepThroughTheLineupAndStopAtTheEnds() {
        val lineup = LiveLineup(listOf(a, b, c), 1)
        assertEquals(2, liveSeekTarget(Player.COMMAND_SEEK_TO_NEXT, 2, lineup))
        assertEquals(2, liveSeekTarget(Player.COMMAND_SEEK_TO_NEXT_MEDIA_ITEM, 0, lineup))
        assertEquals(0, liveSeekTarget(Player.COMMAND_SEEK_TO_PREVIOUS, 1, lineup))
        assertEquals(0, liveSeekTarget(Player.COMMAND_SEEK_TO_PREVIOUS_MEDIA_ITEM, 1, lineup))
        // No wrapping round, whatever index repeat would have asked for.
        assertNull(liveSeekTarget(Player.COMMAND_SEEK_TO_NEXT, 0, LiveLineup(listOf(a, b, c), 2)))
        // "Previous" on the first station does not start it again.
        assertNull(liveSeekTarget(Player.COMMAND_SEEK_TO_PREVIOUS, 0, LiveLineup(listOf(a, b, c), 0)))
        // Nothing seeks within a station.
        assertNull(liveSeekTarget(Player.COMMAND_SEEK_IN_CURRENT_MEDIA_ITEM, 1, lineup))
        assertNull(liveSeekTarget(Player.COMMAND_SEEK_BACK, 1, lineup))
        assertNull(liveSeekTarget(Player.COMMAND_SEEK_FORWARD, 1, lineup))
        // A station chosen in the list is gone to; the one on stays on.
        assertEquals(0, liveSeekTarget(Player.COMMAND_SEEK_TO_MEDIA_ITEM, 0, lineup))
        assertNull(liveSeekTarget(Player.COMMAND_SEEK_TO_MEDIA_ITEM, 1, lineup))
        assertNull(liveSeekTarget(Player.COMMAND_SEEK_TO_MEDIA_ITEM, 7, lineup))
    }

    @Test
    fun aQueueOfStationsIsTheLineupAndAStationAmongSongsStandsAlone() {
        assertEquals(LiveLineup(listOf(a, b, c), 2), liveLineup(listOf(a, b, c), 2))
        val mixed = liveLineup(listOf("song-1", a, "song-2"), 1)!!
        assertEquals(listOf(a), mixed.ids)
        assertFalse(mixed.shows)
        assertNull(liveLineup(listOf("song-1", a), 0))
    }

    @Test
    fun whatTheAppShowsForTheStationOnNow() {
        val read = IcyRead("Nina Simone - Feeling Good", null)
        val live = liveNowOf(b, read, listOf(a, b, c), 1, since = 5L)!!
        assertEquals("Feeling Good", live.shown.title)
        assertEquals("Nina Simone · B", live.shown.subtitle)
        assertEquals(LiveLineup(listOf(a, b, c), 1), live.lineup)
        assertTrue(live.lineup.hasNext && live.lineup.hasPrevious)
        assertEquals(5L, live.since)
        assertNull(liveNowOf("song-1", read, listOf("song-1"), 0, null))
        assertNull(liveNowOf(null, read, emptyList(), 0, null))
    }

    @Test
    fun theListenedTimeCountsFromPlayingAndStartsAfreshForEachStationAndAfterStop() {
        var clock = 1_000L
        val live = LiveClock { clock }
        // Connecting: not counting yet.
        assertNull(live.heard("q:1", playing = false, playWhenReady = true))
        clock = 3_000
        assertEquals(3_000L, live.heard("q:1", playing = true, playWhenReady = true))
        // A moment of buffering does not reset it.
        clock = 50_000
        assertEquals(3_000L, live.heard("q:1", playing = false, playWhenReady = true))
        assertEquals("0:47", listenedFor(clock - 3_000L))
        // Stop, then Play: afresh.
        assertNull(live.heard("q:1", playing = false, playWhenReady = false))
        clock = 60_000
        assertEquals(60_000L, live.heard("q:1", playing = true, playWhenReady = true))
        // Another station: afresh.
        clock = 70_000
        assertEquals(70_000L, live.heard("q:2", playing = true, playWhenReady = true))
        assertNull(live.heard(null, playing = true, playWhenReady = true))
        assertEquals("1:02:03", listenedFor(3_723_000))
    }
}
