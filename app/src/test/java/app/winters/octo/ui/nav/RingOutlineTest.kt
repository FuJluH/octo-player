package app.winters.octo.ui.nav

import androidx.compose.ui.geometry.Offset
import org.junit.Assert.assertEquals
import org.junit.Test
import kotlin.math.PI

class RingOutlineTest {
    private fun assertNear(expected: Offset, actual: Offset) {
        assertEquals("x of $actual", expected.x, actual.x, 1e-3f)
        assertEquals("y of $actual", expected.y, actual.y, 1e-3f)
    }

    @Test
    fun theLengthIsTheStraightsAndOneWholeCircleOfCorners() {
        val outline = RingOutline(46f, 46f, 13f)
        val straights = 4 * (46f - 2 * 13f)
        assertEquals(straights + 2 * PI.toFloat() * 13f, outline.length, 1e-3f)
    }

    @Test
    fun theWalkStartsAtTheTopsMiddleAndGoesClockwise() {
        val outline = RingOutline(46f, 46f, 13f)
        assertNear(Offset(23f, 0f), outline.pointAt(0f))
        // A quarter of a square's walk is the middle of its right side.
        assertNear(Offset(46f, 23f), outline.pointAt(0.25f))
        assertNear(Offset(23f, 46f), outline.pointAt(0.5f))
        assertNear(Offset(0f, 23f), outline.pointAt(0.75f))
        assertNear(Offset(23f, 0f), outline.pointAt(1f))
    }

    @Test
    fun aCornerIsHalfWayRoundItsQuarterTurnAtItsMiddle() {
        val outline = RingOutline(46f, 46f, 13f)
        val toCornerMiddle = (23f - 13f) + PI.toFloat() * 13f / 4f
        val d = 13f * (1f - kotlin.math.sqrt(0.5f))
        assertNear(Offset(46f - d, d), outline.pointAt(toCornerMiddle / outline.length))
    }

    @Test
    fun aRoundedRectangleWalksItsLongSidesLonger() {
        val outline = RingOutline(80f, 40f, 10f)
        val top = 2 * (80f - 20f)
        val sides = 2 * (40f - 20f)
        assertEquals(top + sides + 2 * PI.toFloat() * 10f, outline.length, 1e-3f)
        // Half way round is the bottom's middle whatever the shape.
        assertNear(Offset(40f, 40f), outline.pointAt(0.5f))
    }

    @Test
    fun theRadiusIsHeldToHalfTheShortSideSoACircleWalksRound() {
        val outline = RingOutline(40f, 40f, 99f)
        assertEquals(20f, outline.radius, 0f)
        assertEquals(2 * PI.toFloat() * 20f, outline.length, 1e-3f)
        assertNear(Offset(40f, 20f), outline.pointAt(0.25f))
    }

    @Test
    fun aSquareCornerHasNoTurns() {
        val outline = RingOutline(10f, 10f, 0f)
        assertEquals(40f, outline.length, 1e-4f)
        assertNear(Offset(10f, 0f), outline.pointAt(5f / 40f))
        assertEquals(5, outline.pieces.size)
    }

    @Test
    fun fractionsOutsideTheWalkStayOnIt() {
        val outline = RingOutline(46f, 46f, 13f)
        assertNear(outline.pointAt(0f), outline.pointAt(-1f))
        assertNear(outline.pointAt(1f), outline.pointAt(2f))
    }
}
