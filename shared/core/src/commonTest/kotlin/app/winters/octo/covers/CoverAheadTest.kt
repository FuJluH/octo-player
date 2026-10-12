package app.winters.octo.covers

import kotlinx.coroutines.CompletableDeferred
import kotlinx.coroutines.ExperimentalCoroutinesApi
import kotlinx.coroutines.test.runCurrent
import kotlinx.coroutines.test.runTest
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

@OptIn(ExperimentalCoroutinesApi::class)
class CoverAheadTest {
    @Test
    fun theCoversWantedAreFetchedTogetherAndMarkedUrgent() = runTest {
        val lanes = CoverLanes()
        val started = mutableListOf<String>()
        val gate = CompletableDeferred<Unit>()
        val ahead = CoverAhead(backgroundScope, lanes) { started += it; gate.await() }
        ahead.want(listOf("mf-now", "mf-next", "mf-after"))
        runCurrent()
        // All three under way at once, none waiting for another.
        assertEquals(listOf("mf-now", "mf-next", "mf-after"), started)
        assertTrue(lanes.isUrgent("mf-now") && lanes.isUrgent("mf-after"))
        gate.complete(Unit)
    }

    @Test
    fun aCoverNoLongerWantedStopsAndIsNoLongerUrgent() = runTest {
        val lanes = CoverLanes()
        val finished = mutableListOf<String>()
        val gate = CompletableDeferred<Unit>()
        val ahead = CoverAhead(backgroundScope, lanes) { gate.await(); finished += it }
        ahead.want(listOf("mf-1", "mf-2", "mf-3"))
        runCurrent()
        ahead.want(listOf("mf-2", "mf-3", "mf-4"))
        runCurrent()
        assertFalse(lanes.isUrgent("mf-1"))
        gate.complete(Unit)
        runCurrent()
        assertEquals(setOf("mf-2", "mf-3", "mf-4"), finished.toSet())
        assertEquals(3, finished.size)
    }

    @Test
    fun aCoverStillWantedIsNotStartedAgain() = runTest {
        val started = mutableListOf<String>()
        val gate = CompletableDeferred<Unit>()
        val ahead = CoverAhead(backgroundScope) { started += it; gate.await() }
        ahead.want(listOf("mf-1", "mf-2"))
        runCurrent()
        ahead.want(listOf("mf-1", "mf-2", "mf-3"))
        runCurrent()
        assertEquals(listOf("mf-1", "mf-2", "mf-3"), started)
        gate.complete(Unit)
    }

    @Test
    fun aCoverFetchedLatelyIsNotFetchedAgain() = runTest {
        val started = mutableListOf<String>()
        val ahead = CoverAhead(backgroundScope) { started += it }
        ahead.want(listOf("mf-1", "mf-2", "mf-3"))
        runCurrent()
        // The next song starts: one new cover comes into view.
        ahead.want(listOf("mf-2", "mf-3", "mf-4"))
        runCurrent()
        assertEquals(listOf("mf-1", "mf-2", "mf-3", "mf-4"), started)
    }

    @Test
    fun aFailedFetchIsTriedAgainOnTheNextChange() = runTest {
        var tries = 0
        val ahead = CoverAhead(backgroundScope) { tries++; if (tries == 1) error("no connection") }
        ahead.want(listOf("mf-1"))
        runCurrent()
        ahead.want(listOf("mf-1", "mf-2"))
        runCurrent()
        assertEquals(3, tries)
    }

    @Test
    fun stoppingLeavesNothingUrgent() = runTest {
        val lanes = CoverLanes()
        val ahead = CoverAhead(backgroundScope, lanes) { CompletableDeferred<Unit>().await() }
        ahead.want(listOf("mf-1"))
        runCurrent()
        ahead.stop()
        assertFalse(lanes.isUrgent("mf-1"))
    }
}
