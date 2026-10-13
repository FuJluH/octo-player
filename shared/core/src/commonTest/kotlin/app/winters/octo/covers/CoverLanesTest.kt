package app.winters.octo.covers

import kotlinx.coroutines.CompletableDeferred
import kotlinx.coroutines.ExperimentalCoroutinesApi
import kotlinx.coroutines.launch
import kotlinx.coroutines.test.TestScope
import kotlinx.coroutines.test.advanceUntilIdle
import kotlinx.coroutines.test.runTest
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

@OptIn(ExperimentalCoroutinesApi::class)
class CoverLanesTest {
    // A download that holds its lane until let go.
    private class Held {
        val go = CompletableDeferred<Unit>()
        suspend fun hold() = go.await()
    }

    // Asks for `cover` through `lanes`, noting when it starts downloading.
    private fun TestScope.ask(lanes: CoverLanes, cover: String, started: MutableList<String>, held: Held? = null) =
        launch {
            lanes.pass(cover) {
                started += cover
                held?.hold()
            }
        }

    @Test
    fun onlyAFewCoversDownloadAtOnce() = runTest {
        val lanes = CoverLanes(lanes = 4)
        val started = mutableListOf<String>()
        val held = Held()
        for (i in 1..6) ask(lanes, "al-$i", started, held)
        advanceUntilIdle()
        assertEquals(4, started.size)
        assertEquals(2, lanes.queued)
        held.go.complete(Unit)
        advanceUntilIdle()
        assertEquals(6, started.size)
    }

    @Test
    fun theNewestAskGoesFirst() = runTest {
        val lanes = CoverLanes(lanes = 1)
        val started = mutableListOf<String>()
        val first = Held()
        ask(lanes, "row-0", started, first)
        advanceUntilIdle()
        for (cover in listOf("row-1", "row-2", "row-3")) {
            ask(lanes, cover, started)
            advanceUntilIdle()
        }
        first.go.complete(Unit)
        advanceUntilIdle()
        assertEquals(listOf("row-0", "row-3", "row-2", "row-1"), started)
    }

    @Test
    fun anUrgentCoverGoesPastTheQueue() = runTest {
        val lanes = CoverLanes(lanes = 1)
        val started = mutableListOf<String>()
        val held = Held()
        ask(lanes, "grid-1", started, held)
        ask(lanes, "grid-2", started)
        ask(lanes, "grid-3", started)
        advanceUntilIdle()
        lanes.setUrgent(listOf("mf-playing"))
        ask(lanes, "mf-playing", started)
        advanceUntilIdle()
        assertEquals(listOf("grid-1", "mf-playing"), started)
        assertEquals(2, lanes.queued)
        held.go.complete(Unit)
    }

    @Test
    fun aWaitingCoverThatTurnsUrgentGoesAtOnce() = runTest {
        val lanes = CoverLanes(lanes = 1)
        val started = mutableListOf<String>()
        val held = Held()
        ask(lanes, "grid-1", started, held)
        ask(lanes, "mf-next", started)
        advanceUntilIdle()
        assertEquals(listOf("grid-1"), started)
        lanes.setUrgent(listOf("mf-next"))
        advanceUntilIdle()
        assertEquals(listOf("grid-1", "mf-next"), started)
        assertEquals(0, lanes.queued)
        held.go.complete(Unit)
    }

    @Test
    fun anAskWhosePictureWentAwayGivesUpItsTurn() = runTest {
        val lanes = CoverLanes(lanes = 1)
        val started = mutableListOf<String>()
        val held = Held()
        ask(lanes, "grid-1", started, held)
        ask(lanes, "grid-2", started)
        val gone = ask(lanes, "grid-3", started)
        advanceUntilIdle()
        gone.cancel()
        advanceUntilIdle()
        assertEquals(1, lanes.queued)
        held.go.complete(Unit)
        advanceUntilIdle()
        assertEquals(listOf("grid-1", "grid-2"), started)
    }

    @Test
    fun aLaneIsGivenBackWhenItsDownloadFails() = runTest {
        val lanes = CoverLanes(lanes = 1)
        val started = mutableListOf<String>()
        launch { runCatching { lanes.pass("grid-1") { error("no connection") } } }
        advanceUntilIdle()
        ask(lanes, "grid-2", started)
        advanceUntilIdle()
        assertEquals(listOf("grid-2"), started)
    }

    @Test
    fun aSmallAskWaitsForALargerDownloadOfTheSameCoverAndReadsItsCopy() = runTest {
        val downloads = CoverDownloads()
        val kept = mutableSetOf<Int>()
        val fetched = mutableListOf<Int>()
        val big = CompletableDeferred<Unit>()
        fun keptCopy(px: Int) = keptCoverSize(px) { it in kept }
        val large = launch {
            downloads.get("mf-1", 1200, { keptCopy(1200) }) {
                fetched += 1200
                big.await()
                kept += 1200
                1200
            }
        }
        advanceUntilIdle()
        var small: Int? = null
        launch {
            small = downloads.get("mf-1", 150, { keptCopy(150) }) {
                fetched += 150
                kept += 150
                150
            }
        }
        advanceUntilIdle()
        assertNull(small)
        big.complete(Unit)
        advanceUntilIdle()
        large.join()
        assertEquals(1200, small)
        assertEquals(listOf(1200), fetched)
    }

    @Test
    fun aLargerAskDoesNotWaitForASmallerDownload() = runTest {
        val downloads = CoverDownloads()
        val fetched = mutableListOf<Int>()
        val small = CompletableDeferred<Unit>()
        launch { downloads.get("mf-1", 150, { null }) { fetched += 150; small.await(); 150 } }
        advanceUntilIdle()
        var large: Int? = null
        launch { large = downloads.get("mf-1", 1200, { null }) { fetched += 1200; 1200 } }
        advanceUntilIdle()
        assertEquals(1200, large)
        assertEquals(listOf(150, 1200), fetched)
        small.complete(Unit)
    }

    @Test
    fun aKeptCopyAnswersWithoutADownload() = runTest {
        val downloads = CoverDownloads()
        var fetched = false
        val got = downloads.get("mf-1", 300, { 1200 }) { fetched = true; 300 }
        assertEquals(1200, got)
        assertTrue(!fetched)
    }

    @Test
    fun whenTheDownloadWaitedForFailsTheAskDownloadsItself() = runTest {
        val downloads = CoverDownloads()
        val gate = CompletableDeferred<Unit>()
        val fetched = mutableListOf<Int>()
        launch { downloads.get("mf-1", 1200, { null }) { fetched += 1200; gate.await(); null } }
        advanceUntilIdle()
        var small: Int? = null
        launch { small = downloads.get("mf-1", 150, { null }) { fetched += 150; 150 } }
        advanceUntilIdle()
        gate.complete(Unit)
        advanceUntilIdle()
        assertEquals(150, small)
        assertEquals(listOf(1200, 150), fetched)
    }
}
