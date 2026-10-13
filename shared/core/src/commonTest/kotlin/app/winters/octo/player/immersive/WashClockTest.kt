package app.winters.octo.player.immersive

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertSame
import org.junit.Assert.assertTrue
import org.junit.Test

class WashClockTest {
    private val frame60 = 16_666_667L

    @Test
    fun framesAreDrawnOnlyAsOftenAsTheLimitAllows() {
        val clock = WashClock(30f)
        clock.start(0L)
        var drawn = 0
        // A 60 Hz screen offers a frame every 16.7 ms for a second.
        for (i in 1..60) if (clock.tick(i * frame60, 30f, BaseBpm, 1f, moving = true)) drawn++
        assertEquals(30, drawn)
    }

    // Frames drawn in one second at `limit` on a screen of `hz`.
    private fun drawnInASecond(limit: Float, hz: Double): Int {
        val clock = WashClock(limit)
        clock.start(0L)
        val frames = (hz).toInt()
        var drawn = 0
        for (i in 1..frames) if (clock.tick((i * 1_000_000_000.0 / hz).toLong(), limit, BaseBpm, 1f, moving = true)) drawn++
        return drawn
    }

    @Test
    fun theLimitHoldsOnScreensThatAreNotAWholeMultipleOfIt() {
        assertEquals(60.0, drawnInASecond(60f, 90.0).toDouble(), 1.0)
        assertEquals(90.0, drawnInASecond(90f, 120.0).toDouble(), 1.0)
        assertEquals(60.0, drawnInASecond(60f, 144.0).toDouble(), 1.0)
        assertEquals(60.0, drawnInASecond(60f, 120.0).toDouble(), 1.0)
        assertEquals(30.0, drawnInASecond(30f, 90.0).toDouble(), 1.0)
    }

    @Test
    fun aScreenAHairOffTheLimitDrawsEveryFrame() {
        assertEquals(60, drawnInASecond(60f, 60.1))
        assertEquals(59, drawnInASecond(60f, 59.9))
        assertEquals(120, drawnInASecond(120f, 120.2))
    }

    @Test
    fun aDrawnFrameFillsItsSlotUnlessAHairEarlyOrFarBehind() {
        // Late by a third of a frame (60 on 90 Hz): it keeps the slot.
        assertEquals(16_666_666L, nextSlot(0L, 22_222_222L, 60f))
        // A hair early: the drawn time.
        assertEquals(16_600_000L, nextSlot(0L, 16_600_000L, 60f))
        // Early by more than that: still the slot.
        assertEquals(16_666_666L, nextSlot(0L, 13_888_889L, 60f))
        // After a stall: half a frame behind the drawn time, no further.
        assertEquals(100_000_000L - 8_333_333L, nextSlot(0L, 100_000_000L, 60f))
    }

    @Test
    fun theDriftDoesNotDependOnTheFrameRate() {
        val slow = WashClock(30f).apply { start(0L) }
        val quick = WashClock(60f).apply { start(0L) }
        for (i in 1..120) {
            slow.tick(i * frame60, 30f, BaseBpm, 0.25f, moving = true)
            quick.tick(i * frame60, 60f, BaseBpm, 0.25f, moving = true)
        }
        // Two seconds either way: the same distance travelled.
        assertEquals(quick.motion.time, slow.motion.time, 1e-3f)
        assertTrue(quick.motion.time > 0f)
    }

    @Test
    fun betweenFramesTheClockRestsUntilNearlyDue() {
        val clock = WashClock(30f)
        clock.start(0L)
        assertTrue(clock.tick(2 * frame60, 30f, BaseBpm, 1f, moving = true))
        // Due 26.7 ms after the last drawn frame's slot (a nanosecond
        // before the frame); it wakes 6 ms before that.
        assertEquals(26_666_665L - RestMarginNanos, clock.restNanos(2 * frame60))
        // It sleeps through the 60 Hz screen's next frame, which would not
        // be drawn, and wakes before the one after, which is.
        val woken = 2 * frame60 + clock.restNanos(2 * frame60)
        assertTrue(woken > 3 * frame60 && woken < 4 * frame60)
        assertTrue(clock.tick(4 * frame60, 30f, BaseBpm, 1f, moving = true))
        // At 60 on a 60 Hz screen it barely rests, so no frame is missed.
        val quick = WashClock(60f).apply { start(0L) }
        quick.tick(frame60, 60f, BaseBpm, 1f, moving = true)
        assertTrue(quick.restNanos(frame60) < frame60 - RestMarginNanos)
        // Once past due, no rest at all.
        assertEquals(0L, clock.restNanos(10 * frame60))
    }

    @Test
    fun heldStillOnlyTheCoverFadeRuns() {
        val clock = WashClock(60f)
        clock.fade.start(0L)
        clock.fade.start(10_000L)
        assertTrue(clock.busy(moving = false))
        clock.start(0L)
        for (i in 1..40) clock.tick(i * frame60, 60f, BaseBpm, 1f, moving = false)
        assertEquals(0f, clock.motion.time)
        // 500 ms of fade in 667 ms: done, and so the clock can rest.
        assertFalse(clock.fade.running)
        assertFalse(clock.busy(moving = false))
    }

    @Test
    fun hiddenKeepsTheLastLimitRatherThanStopping() {
        // A target of none (hidden) leaves the limit where it was; the
        // caller stops asking for frames instead.
        val clock = WashClock(60f)
        clock.start(0L)
        clock.tick(frame60, 0f, BaseBpm, 1f, moving = true)
        assertEquals(60f, clock.rate.limit)
    }

    @Test
    fun aCoverArrivingMidFadeStartsFromWhatShows() {
        val fade = CoverFade()
        val swap = CoverSwap<String>()
        val blend = { old: String, new: String, mix: Float -> "$old+$new@${(mix * 100).toInt()}" }
        assertEquals("a" to "a", swap.arrive("a", fade, 0L, blend))
        assertEquals("a" to "b", swap.arrive("b", fade, 10_000L, blend))
        // Barely begun: the fade to "c" is from "a" with a little of "b",
        // never "a" alone (Brandon: on radio the cover snapped back, then
        // moved on, when the real one came in after the stand-in).
        fade.advance(50f)
        val mix = fade.mix
        assertEquals("a+b@${(mix * 100).toInt()}" to "c", swap.arrive("c", fade, 10_050L, blend))
        // A finished fade starts from the cover it ended on.
        fade.advance(1_000f)
        assertEquals("c" to "d", swap.arrive("d", fade, 20_000L, blend))
        assertSame("d", swap.new)
    }

    @Test
    fun theDollyRunsFromNinetyPercentToFull() {
        assertEquals(0.9f, dollyScale(0f), 1e-6f)
        assertEquals(0.95f, dollyScale(0.5f), 1e-6f)
        assertEquals(1f, dollyScale(1f), 1e-6f)
    }
}
