package app.winters.octo.player

import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Test

class DisplayModesTest {
    private val fhd60 = ScreenMode(1, 1080, 2400, 60f)
    private val fhd90 = ScreenMode(2, 1080, 2400, 90f)
    private val fhd120 = ScreenMode(3, 1080, 2400, 120f)
    private val qhd60 = ScreenMode(4, 1440, 3200, 60f)
    private val qhd144 = ScreenMode(5, 1440, 3200, 144f)
    private val all = listOf(fhd60, fhd90, fhd120, qhd60, qhd144)
    private val fastest = Float.POSITIVE_INFINITY

    @Test
    fun theFastestModeAtTheCurrentSizeIsPicked() {
        assertEquals(3, pickScreenMode(all, fhd60, emptyList(), fastest))
        // Already there: asked for again, so it is held.
        assertEquals(3, pickScreenMode(all, fhd120, emptyList(), fastest))
    }

    @Test
    fun aFasterModeAtAnotherSizeIsNeverPicked() {
        assertEquals(3, pickScreenMode(all, fhd90, emptyList(), fastest))
        assertEquals(5, pickScreenMode(all, qhd60, emptyList(), fastest))
    }

    @Test
    fun equalRatesPreferTheCurrentModeThenTheFirstListed() {
        val twin = ScreenMode(6, 1080, 2400, 120f)
        val modes = listOf(fhd60, fhd120, twin)
        assertEquals(6, pickScreenMode(modes, twin, emptyList(), fastest))
        assertEquals(3, pickScreenMode(modes, fhd60, emptyList(), fastest))
        // 119.88 and 120 are the same rate.
        val near = ScreenMode(7, 1080, 2400, 119.88f)
        assertEquals(7, pickScreenMode(listOf(fhd60, near, fhd120), fhd60, emptyList(), fastest))
    }

    @Test
    fun aDisplayWithOneModeOrOneRateGetsNoRequest() {
        assertNull(pickScreenMode(listOf(fhd60), fhd60, emptyList(), fastest))
        val twin = ScreenMode(6, 1080, 2400, 60f)
        assertNull(pickScreenMode(listOf(fhd60, twin), fhd60, emptyList(), fastest))
        // The only faster mode is at another size.
        assertNull(pickScreenMode(listOf(fhd60, qhd144), fhd60, emptyList(), fastest))
    }

    @Test
    fun noNeedMeansNoRequest() {
        assertNull(pickScreenMode(all, fhd60, emptyList(), 0f))
    }

    @Test
    fun aSetRateGetsTheSlowestModeThatReachesIt() {
        assertEquals(2, pickScreenMode(all, fhd60, emptyList(), 90f))
        assertEquals(3, pickScreenMode(all, fhd60, emptyList(), 120f))
        // Past the fastest: the fastest.
        assertEquals(3, pickScreenMode(all, fhd60, emptyList(), 240f))
        // 60 or less is what the display falls back to anyway.
        assertNull(pickScreenMode(all, fhd120, emptyList(), 60f))
        assertNull(pickScreenMode(all, fhd120, emptyList(), 30f))
    }

    @Test
    fun onlyRatesTheDisplaySwitchesToSmoothlyCountWhenItNamesThem() {
        assertEquals(2, pickScreenMode(all, fhd60, listOf(90f), fastest))
        // The current rate always counts.
        assertNull(pickScreenMode(all, fhd60, listOf(48f), fastest))
        assertEquals(3, pickScreenMode(all, fhd60, listOf(90f, 120f), fastest))
    }

    @Test
    fun thePlayerAsksForTheFastestOnlyWhileSungWordsMove() {
        assertEquals(fastest, playerRefreshNeed(playing = true, lyricsShown = true, calm = false, powerSave = false, movingBackgroundFps = null), 0f)
        assertEquals(fastest, playerRefreshNeed(playing = true, lyricsShown = true, calm = false, powerSave = false, movingBackgroundFps = 30), 0f)
        // Paused lyrics hold still: only the moving background is left.
        assertEquals(30f, playerRefreshNeed(playing = false, lyricsShown = true, calm = false, powerSave = false, movingBackgroundFps = 30), 0f)
    }

    @Test
    fun withoutLyricsOnlyTheMovingBackgroundCounts() {
        // Playing, the progress line alone needs no fast screen.
        assertEquals(0f, playerRefreshNeed(playing = true, lyricsShown = false, calm = false, powerSave = false, movingBackgroundFps = null), 0f)
        assertEquals(60f, playerRefreshNeed(playing = true, lyricsShown = false, calm = false, powerSave = false, movingBackgroundFps = 60), 0f)
        assertEquals(90f, playerRefreshNeed(playing = false, lyricsShown = false, calm = false, powerSave = false, movingBackgroundFps = 90), 0f)
        assertEquals(0f, playerRefreshNeed(playing = false, lyricsShown = false, calm = false, powerSave = false, movingBackgroundFps = null), 0f)
    }

    @Test
    fun batterySaverAndReduceMotionAskForNothing() {
        assertEquals(0f, playerRefreshNeed(playing = true, lyricsShown = true, calm = false, powerSave = true, movingBackgroundFps = 120), 0f)
        assertEquals(0f, playerRefreshNeed(playing = true, lyricsShown = true, calm = true, powerSave = false, movingBackgroundFps = 120), 0f)
    }
}
