package app.winters.octo.player

import androidx.compose.animation.core.FastOutSlowInEasing
import app.winters.octo.ui.common.pulseAt
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test

class FramePacingTest {
    @Test
    fun aLineMovesOnEachHalfPixel() {
        // A 3:20 song along a 1440 pixel line: half a pixel every 69 ms.
        assertEquals(69L, progressStepMs(200_000, 1_440f))
        // The ring round the bar's button, about 616 pixels round.
        assertEquals(162L, progressStepMs(200_000, 616f))
    }

    @Test
    fun aQuickLineOrNoLengthMovesOnEveryFrame() {
        // A 20 s song along a wide line moves more than half a pixel a frame.
        assertEquals(0L, progressStepMs(20_000, 1_440f))
        assertEquals(0L, progressStepMs(200_000, 0f))
        assertEquals(0L, progressStepMs(0, 1_440f))
    }

    @Test
    fun aLongSongStillMovesEverySecond() {
        assertEquals(1_000L, progressStepMs(3 * 60 * 60_000L, 100f))
    }

    @Test
    fun theMeshTakesFewerFramesAsItSlows() {
        assertEquals(29L, meshFrameMs(1f))
        assertEquals(62L, meshFrameMs(0.5f))
        // Paused it slows to 0.15 of its pace: 10 frames a second.
        assertEquals(96L, meshFrameMs(0.15f))
        assertEquals(96L, meshFrameMs(0f))
    }

    @Test
    fun thePulseRunsDownAndBackLikeAReversingTween() {
        assertEquals(1f, pulseAt(0, 0.35f, 1_100), 1e-6f)
        assertEquals(0.35f, pulseAt(1_100, 0.35f, 1_100), 1e-6f)
        assertEquals(1f, pulseAt(2_200, 0.35f, 1_100), 1e-6f)
        // The same distance from either end reads the same.
        assertEquals(pulseAt(400, 0.35f, 1_100), pulseAt(1_800, 0.35f, 1_100), 1e-6f)
        // Eased the way a tween is by default, both ways.
        assertEquals(1f - 0.65f * FastOutSlowInEasing.transform(0.25f), pulseAt(275, 0.35f, 1_100), 1e-5f)
        assertEquals(1f - 0.65f * FastOutSlowInEasing.transform(0.6f), pulseAt(2_200 - 660, 0.35f, 1_100), 1e-5f)
        assertTrue(pulseAt(660, 0.35f, 1_100) < 1f - 0.65f * 0.5f)
        assertEquals(1f, pulseAt(500, 0.35f, 0), 1e-6f)
    }
}
