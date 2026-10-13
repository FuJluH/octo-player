package app.winters.octo.playback

import org.junit.Assert.assertEquals
import org.junit.Test

class PlayAheadTest {
    private val queue = listOf("a", "b", "c", "d", "e")

    @Test
    fun inQueueOrderTheNextTwoFollowTheSongOn() {
        assertEquals(listOf("c", "d"), nextInPlayOrder(queue, at = 1, repeatAll = false, count = 2))
    }

    @Test
    fun shuffledTheNextTwoFollowThePlayOrderNotTheQueue() {
        // The queue a..e shuffled to play d, a, e, b, c; a is on.
        val playOrder = listOf("d", "a", "e", "b", "c")
        assertEquals(listOf("e", "b"), nextInPlayOrder(playOrder, at = 1, repeatAll = false, count = 2))
    }

    @Test
    fun withoutRepeatTheEndOfTheQueueIsTheEnd() {
        assertEquals(listOf("e"), nextInPlayOrder(queue, at = 3, repeatAll = false, count = 2))
        assertEquals(emptyList<String>(), nextInPlayOrder(queue, at = 4, repeatAll = false, count = 2))
    }

    @Test
    fun repeatAllWrapsRoundToTheStart() {
        assertEquals(listOf("e", "a"), nextInPlayOrder(queue, at = 3, repeatAll = true, count = 2))
        assertEquals(listOf("a", "b"), nextInPlayOrder(queue, at = 4, repeatAll = true, count = 2))
    }

    @Test
    fun repeatAllNeverComesBackToTheSongOn() {
        val two = listOf("a", "b")
        assertEquals(listOf("b"), nextInPlayOrder(two, at = 0, repeatAll = true, count = 2))
        assertEquals(emptyList<String>(), nextInPlayOrder(listOf("a"), at = 0, repeatAll = true, count = 2))
    }

    @Test
    fun withNothingOnTheQueuePlaysFromItsStart() {
        assertEquals(listOf("a", "b"), nextInPlayOrder(queue, at = -1, repeatAll = false, count = 2))
    }

    @Test
    fun noneAreAskedForNoneAreGiven() {
        assertEquals(emptyList<String>(), nextInPlayOrder(queue, at = 0, repeatAll = true, count = 0))
        assertEquals(emptyList<String>(), nextInPlayOrder(emptyList<String>(), at = 0, repeatAll = true, count = 2))
    }

    @Test
    fun thePlayersOwnStepsAreFollowed_ShuffledAndRepeating() {
        // A player's shuffled order over queue positions: 3, 0, 4, 1, 2,
        // wrapping round as with repeat all.
        val order = listOf(3, 0, 4, 1, 2)
        val next = { position: Int -> order[(order.indexOf(position) + 1) % order.size] }
        assertEquals(listOf(4, 1), nextInPlayOrder(current = 0, count = 2, next = next))
        assertEquals(listOf(3, 0), nextInPlayOrder(current = 2, count = 2, next = next))
    }

    @Test
    fun thePlayersEndStopsTheSteps() {
        val next = { position: Int -> if (position < 4) position + 1 else null }
        assertEquals(listOf(4), nextInPlayOrder(current = 3, count = 2, next = next))
    }

    @Test
    fun aStepThatLoopsSoonerStops() {
        // Two songs repeating: after b comes a, which is on.
        val next = { position: Int -> 1 - position }
        assertEquals(listOf(1), nextInPlayOrder(current = 0, count = 2, next = next))
    }
}
