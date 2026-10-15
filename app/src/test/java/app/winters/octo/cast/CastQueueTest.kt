package app.winters.octo.cast

import app.winters.octo.output.RemoteMedia
import app.winters.octo.output.RemoteState
import com.google.android.gms.cast.MediaQueueItem
import com.google.android.gms.cast.MediaStatus
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

private const val NONE = MediaQueueItem.INVALID_ITEM_ID
private const val IDLE = MediaStatus.PLAYER_STATE_IDLE
private const val PLAYING = MediaStatus.PLAYER_STATE_PLAYING
private const val BUFFERING = MediaStatus.PLAYER_STATE_BUFFERING
private const val FINISHED = MediaStatus.IDLE_REASON_FINISHED
private const val INTERRUPTED = MediaStatus.IDLE_REASON_INTERRUPTED
private const val CANCELED = MediaStatus.IDLE_REASON_CANCELED
private const val ERROR = MediaStatus.IDLE_REASON_ERROR
private const val NO_REASON = MediaStatus.IDLE_REASON_NONE

// One status the receiver sends; its queue comes from the fake receiver.
private data class Step(val playerState: Int, val idleReason: Int, val currentItemId: Int, val loadingItemId: Int = NONE)

// A receiver holding a queue, giving each new item an id never used
// before. Removing the item it is playing or loading ends its media
// session, as a real one does.
private class FakeReceiver(itemIds: List<Int>) : CastQueueClient {
    val items = itemIds.toMutableList()
    val removed = mutableListOf<Int>()
    val appended = mutableListOf<RemoteMedia>()
    var sessionEnded = false
    var step: Step? = null
    private var lastId = itemIds.maxOrNull() ?: 0

    override val status: CastQueueStatus?
        get() {
            val step = step ?: return null
            if (sessionEnded) return CastQueueStatus(IDLE, INTERRUPTED, step.currentItemId, NONE, items.toList())
            return CastQueueStatus(step.playerState, step.idleReason, step.currentItemId, step.loadingItemId, items.toList())
        }

    override fun removeItems(itemIds: IntArray) {
        val on = status?.let { it.loadingItemId.takeIf { id -> id != NONE } ?: it.currentItemId }
        itemIds.forEach { id ->
            removed += id
            items.remove(id)
            if (id == on || id == step?.currentItemId) sessionEnded = true
        }
    }

    override fun append(media: RemoteMedia) {
        appended += media
        items += ++lastId
    }
}

private fun song(name: String) = RemoteMedia(url = "http://octo/$name", mimeType = "audio/flac", title = name)

class CastQueueTest {
    // Song 3 ends, the receiver goes on by itself to song 4, which it was
    // given ahead of time, and the phone gives it the song after.
    private val songChange = listOf(
        Step(PLAYING, NO_REASON, currentItemId = 3),
        Step(IDLE, FINISHED, currentItemId = 3, loadingItemId = 4),
        Step(BUFFERING, NO_REASON, currentItemId = 4),
        Step(PLAYING, NO_REASON, currentItemId = 4),
    )

    private fun replay(steps: List<Step>, receiver: FakeReceiver, giveNextAt: Int?, next: RemoteMedia?): List<RemoteState?> =
        steps.mapIndexed { i, step ->
            receiver.step = step
            if (i == giveNextAt) receiver.setNext(next)
            receiver.status?.state
        }

    @Test
    fun theSongTheReceiverGoesOnToIsKeptWheneverTheNextOneIsGiven() {
        for (at in 1 until songChange.size) {
            val receiver = FakeReceiver(listOf(3, 4))
            val states = replay(songChange, receiver, giveNextAt = at, next = song("five"))

            assertFalse("song 4 removed when the next was given at step $at", 4 in receiver.removed)
            assertFalse("the session ended when the next was given at step $at", receiver.sessionEnded)
            assertEquals(listOf(song("five")), receiver.appended)
            assertEquals(listOf(3, 4, 5), receiver.items)
            assertEquals(listOf(RemoteState.Playing, RemoteState.Loading, RemoteState.Loading, RemoteState.Playing), states)
        }
    }

    @Test
    fun whileMovingOnTheLoadingItemCountsAsTheOneItIsOn() {
        val moving = CastQueueStatus(IDLE, FINISHED, currentItemId = 3, loadingItemId = 4, itemIds = listOf(3, 4))

        assertTrue(moving.movingOn)
        assertEquals(4, moving.onItemId)
        assertEquals(emptyList<Int>(), moving.later)
        assertEquals(RemoteState.Loading, moving.state)
    }

    @Test
    fun beforeTheSongEndsTheSongGivenAheadIsReplaced() {
        val receiver = FakeReceiver(listOf(3, 4))
        receiver.step = Step(PLAYING, NO_REASON, currentItemId = 3)

        receiver.setNext(song("five"))

        assertEquals(listOf(4), receiver.removed)
        assertEquals(listOf(3, 5), receiver.items)
        assertFalse(receiver.sessionEnded)
    }

    @Test
    fun theEndOfTheQueueStillEnds() {
        val receiver = FakeReceiver(listOf(3, 4))
        val states = replay(
            listOf(Step(PLAYING, NO_REASON, currentItemId = 4), Step(IDLE, FINISHED, currentItemId = 4)),
            receiver,
            giveNextAt = 1,
            next = null,
        )

        assertEquals(listOf(RemoteState.Playing, RemoteState.Ended), states)
        assertEquals(emptyList<Int>(), receiver.removed)
        assertEquals(emptyList<RemoteMedia>(), receiver.appended)
    }

    @Test
    fun skippingOnTheReceiverToTheNextItemIsLoading() {
        val skipped = CastQueueStatus(IDLE, INTERRUPTED, currentItemId = 3, loadingItemId = 4, itemIds = listOf(3, 4))

        assertEquals(RemoteState.Loading, skipped.state)
        assertEquals(emptyList<Int>(), skipped.later)
    }

    @Test
    fun stoppedOrInterruptedWithNothingLoadingIsIdle() {
        assertEquals(RemoteState.Idle, CastQueueStatus(IDLE, INTERRUPTED, 4, NONE, listOf(3, 4)).state)
        assertEquals(RemoteState.Idle, CastQueueStatus(IDLE, CANCELED, 4, NONE, listOf(3, 4)).state)
        assertEquals(RemoteState.Idle, CastQueueStatus(IDLE, CANCELED, 3, 4, listOf(3, 4)).state)
    }

    @Test
    fun anErrorIsAFailureNotAState() {
        val failed = CastQueueStatus(IDLE, ERROR, 3, 4, listOf(3, 4))

        assertTrue(failed.failed)
        assertNull(failed.state)
    }
}
