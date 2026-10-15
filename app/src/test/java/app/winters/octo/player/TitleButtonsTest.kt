package app.winters.octo.player

import androidx.compose.ui.unit.dp
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test

class TitleButtonsTest {
    // In dp, at a density of 1: a 360 wide row 24 in from the screen's edges,
    // 48 targets, the heart 11.7 and the dots 8.3 either side of their middles.
    private val place = titleButtonsPlace(rowWidth = 360f, sideMargin = 24f, buttonSize = 48f, heartHalf = 11.7f, dotsHalf = 8.3f)

    @Test
    fun theIconsAreAsFarApartAsTheDotsAreFromTheScreensEdge() {
        val screenRight = 360f + 24f
        val moreMiddle = place.buttonsRight - 24f
        val heartMiddle = moreMiddle - 48f
        val between = (moreMiddle - 8.3f) - (heartMiddle + 11.7f)
        val toEdge = screenRight - (moreMiddle + 8.3f)
        assertEquals(28f, between, 1e-4f)
        assertEquals(between, toEdge, 1e-4f)
    }

    @Test
    fun theNameEndsAtTheHeartsTarget() {
        assertEquals(place.buttonsRight - 96f, place.titleWidth, 1e-4f)
    }

    @Test
    fun theButtonsSitOnTheMiddleOfTheCapitals() {
        assertEquals(30f - 17.5f / 2, capMiddle(baseline = 30f, capHeight = 17.5f), 1e-4f)
    }

    @Test
    fun theHeartStandsAboutASixthTallerThanTheCapitals() {
        val icons = TitleIcons(17.5.dp)
        val heartTall = 176f / 256f * icons.size.value + SecondaryStroke.value
        assertEquals(1.15f * 17.5f, heartTall, 1e-3f)
        // Drawn at the bottom row's weight, lighter than a bold title's stems
        // but no hairline.
        assertEquals(1.375f, SecondaryStroke.value, 1e-4f)
        assertTrue(icons.dotsHalf < icons.heartHalf)
        assertEquals(8f / 256f * icons.size.value, icons.heartLift.value, 1e-4f)
    }

    @Test
    fun theIconsStayAStepQuieterThanTheName() {
        assertEquals(0.7f, TitleIconAlpha, 0f)
    }
}
