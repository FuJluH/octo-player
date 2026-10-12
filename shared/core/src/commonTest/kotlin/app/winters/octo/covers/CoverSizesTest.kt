package app.winters.octo.covers

import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Test

class CoverSizesTest {
    @Test
    fun everySizeSnapsToTheSmallestBucketAtLeastAsBig() {
        assertEquals(150, coverBucket(1))
        assertEquals(150, coverBucket(108))
        assertEquals(150, coverBucket(150))
        assertEquals(300, coverBucket(151))
        assertEquals(600, coverBucket(512))
        assertEquals(1200, coverBucket(936))
        assertEquals(1200, coverBucket(1200))
    }

    @Test
    fun sizesPastTheLargestTakeTheLargest() {
        assertEquals(1200, coverBucket(2400))
    }

    @Test
    fun theSizesOnePlayingSongIsDrawnAtNeedOnlyAFewBuckets() {
        // Mini bar, lyrics bar, palette, widget, car, notification, wash,
        // player card on a phone at 3x.
        val asked = listOf(108, 120, 128, 300, 320, 512, 512, 936)
        assertEquals(setOf(150, 300, 600, 1200), asked.map(::coverBucket).toSet())
    }

    @Test
    fun coversAheadAreFetchedAtTheLargestBucket() {
        assertEquals(CoverBuckets.last(), AheadCoverBucket)
    }

    @Test
    fun anAskIsAnsweredByItsOwnSizeThenLargerOnesSmallestFirst() {
        assertEquals(listOf(150, 300, 600, 1200), keptCoverOrder(108))
        assertEquals(listOf(600, 1200), keptCoverOrder(512))
        assertEquals(listOf(1200), keptCoverOrder(936))
    }

    @Test
    fun aSmallerCopyNeverAnswersUnlessAnySizeWillDo() {
        assertEquals(listOf(1200), keptCoverOrder(1200))
        assertEquals(listOf(1200, 600, 300, 150), keptCoverOrder(1200, anySize = true))
        assertEquals(listOf(600, 1200, 300, 150), keptCoverOrder(600, anySize = true))
    }

    @Test
    fun aLargerKeptCopyAnswersASmallerAsk() {
        val kept = setOf(1200)
        assertEquals(1200, keptCoverSize(108) { it in kept })
        assertEquals(1200, keptCoverSize(512) { it in kept })
    }

    @Test
    fun theNearestLargerCopyIsPreferred() {
        val kept = setOf(300, 1200)
        assertEquals(300, keptCoverSize(150) { it in kept })
        assertEquals(1200, keptCoverSize(400) { it in kept })
    }

    @Test
    fun onlyASmallerCopyMeansAFetch_OrAStandInWhileItComes() {
        val kept = setOf(150)
        assertNull(keptCoverSize(936) { it in kept })
        assertEquals(150, keptCoverSize(936, anySize = true) { it in kept })
    }

    @Test
    fun nothingKeptIsNothing() {
        assertNull(keptCoverSize(300, anySize = true) { false })
    }
}
