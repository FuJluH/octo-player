package app.winters.octo.player

import org.junit.Assert.assertEquals
import org.junit.Test

class TitleButtonsTest {
    // In dp, at a density of 1: a 360 wide row 24 in from the screen's edges,
    // 48 targets, the heart 10.5 and the dots 8.5 either side of their middles.
    private val place = titleButtonsPlace(rowWidth = 360f, sideMargin = 24f, buttonSize = 48f, heartHalf = 10.5f, dotsHalf = 8.5f, nameGap = 8f)

    @Test
    fun theIconsAreAsFarApartAsTheDotsAreFromTheScreensEdge() {
        val screenRight = 360f + 24f
        val moreMiddle = place.buttonsRight - 24f
        val heartMiddle = moreMiddle - 48f
        val between = (moreMiddle - 8.5f) - (heartMiddle + 10.5f)
        val toEdge = screenRight - (moreMiddle + 8.5f)
        assertEquals(29f, between, 1e-4f)
        assertEquals(between, toEdge, 1e-4f)
    }

    @Test
    fun theNameEndsJustBeforeTheHeart() {
        val heartLeft = place.buttonsRight - 96f + (24f - 10.5f)
        assertEquals(heartLeft - 8f, place.titleWidth, 1e-4f)
    }

    @Test
    fun theButtonsSitOnTheMiddleOfBothLines() {
        // Name baseline at 30 (24 text), artist baseline at 54 (16 text).
        val center = buttonsCenter(first = 30f, last = 54f, oneLine = false, titlePx = 24f, artistPx = 16f, height = 60f)
        val titleMiddle = 30f - 0.35f * 24f
        val artistMiddle = 54f - 0.35f * 16f
        assertEquals((titleMiddle + artistMiddle) / 2, center, 1e-4f)
    }

    @Test
    fun withOneLineTheButtonsSitOnIt() {
        assertEquals(30f - 0.35f * 24f, buttonsCenter(first = 30f, last = 54f, oneLine = true, titlePx = 24f, artistPx = 16f, height = 60f), 1e-4f)
        assertEquals(30f - 0.35f * 24f, buttonsCenter(first = 30f, last = 30f, oneLine = false, titlePx = 24f, artistPx = 16f, height = 40f), 1e-4f)
    }

    @Test
    fun withNoBaselinesTheButtonsSitInTheMiddle() {
        assertEquals(30f, buttonsCenter(first = null, last = null, oneLine = false, titlePx = 24f, artistPx = 16f, height = 60f), 1e-4f)
    }
}
