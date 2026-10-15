package app.winters.octo.animated

import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test

class FullScreenLookTest {
    // An Oppo CPH2841, 1440 x 3168 px, and a 3:4 loop.
    private val widthShare = 1440f / 3168f
    private val shape = 0.75f

    @Test
    fun theLoopFillsTwoThirdsOfTheScreen() {
        // 1.1 x 1440 x 4/3 = 2112 px from 16 px above the top edge.
        assertEquals(2112f / 3168f - 0.005f, fullScreenLoopBottom(shape, widthShare), 0.0005f)
    }

    @Test
    fun theMeltIsDoneByTheLoopsOwnBottomEdge() {
        val end = fullScreenMeltEnd(shape, widthShare)
        assertEquals(fullScreenLoopBottom(shape, widthShare), end, 0f)
        assertTrue(end < FULL_SCREEN_MELT_TO)
        // A screen where the loop reaches further keeps the set end.
        assertEquals(FULL_SCREEN_MELT_TO, fullScreenMeltEnd(shape, 0.6f), 0f)
    }

    @Test
    fun theMeltIsASmoothstep() {
        val end = 0.68f
        assertEquals(1f, fullScreenLoopAlpha(0.3f, end), 0f)
        assertEquals(1f, fullScreenLoopAlpha(FULL_SCREEN_MELT_FROM, end), 0f)
        assertEquals(0.5f, fullScreenLoopAlpha((FULL_SCREEN_MELT_FROM + end) / 2, end), 0.0001f)
        assertEquals(0f, fullScreenLoopAlpha(end, end), 0f)
        val rows = (0..100).map { fullScreenLoopAlpha(it / 100f, end) }
        assertTrue(rows.zipWithNext().all { (a, b) -> b <= a })
    }
}
