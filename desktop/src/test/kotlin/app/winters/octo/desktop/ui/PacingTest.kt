package app.winters.octo.desktop.ui

import org.junit.Assert.assertEquals
import org.junit.Test

class PacingTest {
    @Test
    fun aLineStepsEachHalfPixelAtMostASecondApart() {
        // 4:44 over 440 px: half a pixel every 322 ms.
        assertEquals(322L, progressStepMs(284_000, 440f))
        // A short song on a long line moves every frame.
        assertEquals(0L, progressStepMs(10_000, 1_000f))
        // A long song on a short line waits no more than a second.
        assertEquals(1_000L, progressStepMs(3_600_000, 100f))
        assertEquals(1_000L, progressStepMs(0, 440f))
    }

    @Test
    fun aTimeInSecondsTurnsOnTheSecond() {
        assertEquals(1_005L, msToNextSecond(0))
        assertEquals(6L, msToNextSecond(64_999))
        assertEquals(905L, msToNextSecond(65_100))
    }

    @Test
    fun thePulseEasesDownAndBack() {
        assertEquals(1f, pulseAt(0, 0.35f, 1_100), 0f)
        assertEquals(0.35f, pulseAt(1_100, 0.35f, 1_100), 1e-4f)
        assertEquals(1f, pulseAt(2_200, 0.35f, 1_100), 1e-4f)
        assertEquals(pulseAt(500, 0.35f, 1_100), pulseAt(1_700, 0.35f, 1_100), 1e-4f)
    }
}
