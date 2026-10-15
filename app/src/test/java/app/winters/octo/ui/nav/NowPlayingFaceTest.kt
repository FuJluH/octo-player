package app.winters.octo.ui.nav

import app.winters.octo.playback.NowPlaying
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class NowPlayingFaceTest {
    private val song = NowPlaying(trackId = "t1", title = "Nightcall", artist = "Kavinsky", durationMs = 258_000)

    @Test
    fun aBreathIsSlowAndStaysBetweenFaintAndFull() {
        assertEquals(1f, pauseBreath(0.0), 1e-6f)
        assertEquals(0f, pauseBreath(PauseBreathSeconds / 2), 1e-6f)
        assertEquals(1f, pauseBreath(PauseBreathSeconds), 1e-6f)
        (0..200).map { pauseBreath(it * 0.05) }.forEach { assertTrue(it in 0f..1f) }
        assertTrue("calm, not a flicker", PauseBreathSeconds >= 2.0)
    }

    @Test
    fun thePauseRedrawsAtMostAboutTwelveTimesASecond() {
        assertTrue(PauseFrameMs >= 83)
    }

    @Test
    fun aBreathSettlesAfterAMinuteNearItsFaintest() {
        assertFalse(breathSettles(10.0))
        assertFalse("not mid-breath", breathSettles(PauseBreathLimitSeconds + 0.0))
        val settles = generateSequence(PauseBreathLimitSeconds) { it + PauseFrameMs / 1000.0 }.first { breathSettles(it) }
        assertTrue("within one breath of the limit", settles < PauseBreathLimitSeconds + PauseBreathSeconds)
        assertTrue(pauseBreath(settles) <= 0.2f)
        assertTrue(BreathRested < 0f)
    }

    @Test
    fun pausedMeansTheListenerPaused() {
        assertFalse(isPaused(song.copy(isPlaying = true, playWhenReady = true)))
        // Buffering is not a pause.
        assertFalse(isPaused(song.copy(isPlaying = false, playWhenReady = true)))
        assertTrue(isPaused(song.copy(isPlaying = false, playWhenReady = false)))
        // Nothing loaded is not paused either.
        assertFalse(isPaused(NowPlaying()))
    }

    @Test
    fun theButtonSaysTheSongAndWhetherItPlays() {
        assertEquals("Now playing: Nightcall, Kavinsky", nowPlayingWords(song))
        assertEquals("Playing", nowPlayingState(song.copy(playWhenReady = true)))
        assertEquals("Paused", nowPlayingState(song.copy(playWhenReady = false)))
        assertEquals("Shuffle your library", nowPlayingWords(NowPlaying()))
        assertEquals("", nowPlayingState(NowPlaying()))
    }

    @Test
    fun thePausedRingStaysVisibleEvenAtItsFaintest() {
        assertTrue(PausedTrackAlpha > 0f)
        assertTrue(PausedLowAlpha in 0.3f..0.6f)
        assertTrue(PausedStillAlpha < 1f)
    }
}
