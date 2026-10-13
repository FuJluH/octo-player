package app.winters.octo.desktop.queue

import app.winters.octo.desktop.player.SilentPlayer
import app.winters.octo.playback.QueueSource
import app.winters.octo.subsonic.Song
import kotlinx.coroutines.ExperimentalCoroutinesApi
import kotlinx.coroutines.awaitCancellation
import kotlinx.coroutines.test.TestScope
import kotlinx.coroutines.test.advanceTimeBy
import kotlinx.coroutines.test.runCurrent
import kotlinx.coroutines.test.runTest
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test
import kotlin.random.Random
import kotlinx.coroutines.flow.MutableStateFlow

@OptIn(ExperimentalCoroutinesApi::class)
class StationRefillTest {
    private val mix = QueueSource.Station("or3kZ9QpLmN2xY7wV1bC0a", "Your Radio")
    private val lined = (1..30).map { Song("s$it", "Song $it", duration = 100) }

    private class Setup(val player: SilentPlayer, val refill: StationRefill, val asked: MutableList<List<String>>)

    // A server that sends `batch` new songs each time, none of those it was told are queued.
    private fun TestScope.setUp(supported: Boolean = true, batch: Int = 3): Setup {
        val player = SilentPlayer(clock = { testScheduler.currentTime }, random = Random(1))
        val asked = mutableListOf<List<String>>()
        var next = 0
        val refill = StationRefill(player, backgroundScope, supported = { supported }) { id, after ->
            assertEquals(mix.id, id)
            asked += after
            List(batch) { Song("n${next++}", "New") }.filterNot { it.id in after }
        }
        refill.start()
        runCurrent()
        return Setup(player, refill, asked)
    }

    private fun TestScope.settle() {
        advanceTimeBy(10)
        runCurrent()
    }

    private fun Setup.coming() = player.state.value.upcoming.map { it.song.id to it.source }

    @Test
    fun aStationRunningLowGetsItsNextSongs() = runTest {
        val s = setUp()
        s.player.play(lined, 0, false, mix)
        settle()
        assertTrue("twenty nine songs still to come", s.asked.isEmpty())
        s.player.skipTo(s.player.state.value.queue[10].key)
        settle()
        assertEquals(listOf(lined.map { it.id }), s.asked)
        assertEquals(listOf("n0", "n1", "n2"), s.coming().takeLast(3).map { it.first })
        assertTrue(s.coming().all { it.second == mix })
    }

    @Test
    fun itAsksOnceForEachEndOfTheQueue() = runTest {
        val s = setUp(batch = 0)
        s.player.play(lined, 28, false, mix)
        settle()
        s.player.skipTo(s.player.state.value.queue[29].key)
        settle()
        assertEquals(1, s.asked.size)
        assertFalse("nothing came, so Autoplay may carry on", s.refill.keepsGoing(s.player.state.value))
    }

    @Test
    fun theStationCarriesOnAfterSongsQueuedBehindIt() = runTest {
        val s = setUp()
        s.player.play(lined, 0, false, mix)
        s.player.addToQueue(listOf(Song("mine", "Mine")))
        settle()
        assertTrue("thirty songs still to come", s.asked.isEmpty())
        s.player.skipTo(s.player.state.value.queue[25].key)
        settle()
        assertEquals("mine" to QueueSource.You, s.coming()[4])
        // The station's next songs follow, until a long run is ahead again.
        assertEquals(listOf("n0", "n1", "n2"), s.coming().drop(5).take(3).map { it.first })
        assertTrue(s.coming().drop(5).all { it.second == mix })
        assertEquals(20, s.coming().size)
    }

    @Test
    fun aServerThatCannotSendThemLeavesTheStationToEnd() = runTest {
        val s = setUp(supported = false)
        s.player.play(lined, 29, false, mix)
        settle()
        assertTrue(s.asked.isEmpty())
        assertFalse(s.refill.keepsGoing(s.player.state.value))
    }

    @Test
    fun aListThatIsNotAStationIsNeverToppedUp() = runTest {
        val s = setUp()
        s.player.play(lined, 29, false, QueueSource.Played("New Releases"))
        settle()
        assertTrue(s.asked.isEmpty())
        assertFalse(s.refill.keepsGoing(s.player.state.value))
    }

    @Test
    fun whileTheStationKeepsGoingAutoplayStandsDown() = runTest {
        val player = SilentPlayer(clock = { testScheduler.currentTime }, random = Random(1))
        // A server still working on the station's next songs.
        val refill = StationRefill(player, backgroundScope, supported = { true }) { _, _ -> awaitCancellation() }
        refill.start()
        val asked = mutableListOf<String>()
        Autoplay(
            player,
            MutableStateFlow(true),
            backgroundScope,
            pick = { seed, _ -> asked += seed.id; listOf(Song("auto", "Autoplay's")) },
            standsDown = refill::keepsGoing,
            standsDownChanged = refill.settled,
        ).start()
        runCurrent()
        val s = Setup(player, refill, mutableListOf())
        s.player.play(lined.take(1), 0, false, mix)
        advanceTimeBy(95_000)
        runCurrent()
        assertTrue("Autoplay leaves a station it keeps going alone", asked.isEmpty())
    }

    @Test
    fun whenTheServerHasNothingMoreAutoplayCarriesOn() = runTest {
        val s = setUp(batch = 0)
        val asked = mutableListOf<String>()
        Autoplay(
            s.player,
            MutableStateFlow(true),
            backgroundScope,
            pick = { seed, _ -> asked += seed.id; listOf(Song("auto", "Autoplay's")) },
            standsDown = s.refill::keepsGoing,
            standsDownChanged = s.refill.settled,
        ).start()
        s.player.play(lined.take(1), 0, false, mix)
        advanceTimeBy(95_000)
        runCurrent()
        assertEquals(listOf("s1"), asked)
    }
}
