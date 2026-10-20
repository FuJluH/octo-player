package app.winters.octo.desktop.ui

import org.junit.Test
import java.util.concurrent.CountDownLatch
import java.util.concurrent.TimeUnit
import java.util.concurrent.atomic.AtomicBoolean
import kotlin.test.assertEquals
import kotlin.test.assertFalse
import kotlin.test.assertTrue

class LateCloseTest {
    private class Thing : AutoCloseable {
        val closed = AtomicBoolean(false)
        val done = CountDownLatch(1)

        override fun close() {
            closed.set(true)
            done.countDown()
        }
    }

    @Test
    fun aThingClosesOnlyOnceAWholeFrameHasBeenDrawnSince() {
        val thing = Thing()
        LateClose.close(thing)
        // The frame under way when it came in may still draw it.
        LateClose.frameDrawn()
        assertFalse(thing.closed.get())
        LateClose.frameDrawn()
        assertTrue(thing.closed.get())
    }

    @Test
    fun withNoWindowDrawingItClosesAfterAMoment() {
        val thing = Thing()
        LateClose.close(thing)
        assertTrue(thing.done.await(5, TimeUnit.SECONDS))
    }

    @Test
    fun aSharedThingWaitsForItsLastUser() {
        val thing = Thing()
        val shared = Shared(thing)
        val inUse = CountDownLatch(1)
        val letGo = CountDownLatch(1)
        val worker = Thread {
            shared.use {
                inUse.countDown()
                letGo.await()
            }
        }
        worker.start()
        inUse.await()
        shared.release()
        repeat(3) { LateClose.frameDrawn() }
        assertFalse(thing.closed.get(), "closed while a worker still used it")
        letGo.countDown()
        worker.join()
        repeat(3) { LateClose.frameDrawn() }
        assertTrue(thing.closed.get())
        // Once let go, it is not handed out again.
        assertEquals(null, shared.use { "used" })
    }
}
