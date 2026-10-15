package app.winters.octo.design

import androidx.compose.ui.graphics.Color
import androidx.compose.ui.unit.dp
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

// Colours keep each channel to 1/255.
private const val Byte = 1f / 255f + 1e-4f

class TokensTest {
    // Every token duration, read from the object so a new one is covered too.
    private val durations: List<Int> = OctoDuration::class.java.declaredFields
        .filter { it.type == Int::class.javaPrimitiveType && java.lang.reflect.Modifier.isStatic(it.modifiers) && !it.name.startsWith("$") }
        .map { it.getInt(null) }

    @Test
    fun theDurationsAreTheSpecsSet() {
        assertTrue(durations.containsAll(listOf(80, 140, 160, 180, 200, 300)))
    }

    @Test
    fun reducedMotionScalesEveryDuration() {
        assertTrue(durations.size >= 6)
        for (base in durations) {
            assertEquals(base, MotionScale.Full.ms(base))
            assertEquals(Math.round(base * 0.5f), MotionScale.Reduced.ms(base))
            assertTrue("$base should be shorter when reduced", MotionScale.Reduced.ms(base) < base)
        }
    }

    @Test
    fun aDurationMultiplierScalesEveryDurationByItself() {
        val slow = MotionScale(duration = 2f)
        for (base in durations) assertEquals(base * 2, slow.ms(base))
    }

    @Test
    fun reducedMotionStopsEveryTravelAndGrowth() {
        val reduced = MotionScale.Reduced
        assertTrue(reduced.still)
        assertEquals(0.dp, reduced.travel(OctoPress.LiftMedium))
        assertEquals(1f, reduced.scale(OctoPress.Pop), 0f)
        assertEquals(1f, reduced.scale(OctoPress.Scale), 0f)
        assertEquals(OctoPress.Pop, MotionScale.Full.scale(OctoPress.Pop), 1e-6f)
        assertEquals(1.dp, MotionScale.Full.travel(OctoPress.LiftSmall))
    }

    @Test
    fun theSystemAnimatorScaleOnlyCountsWhenOff() {
        // Compose already stretches animations by a non-zero animator scale.
        assertEquals(MotionScale.Full, MotionScale.of(systemAnimatorScale = 1f, reduce = false))
        assertEquals(MotionScale.Full, MotionScale.of(systemAnimatorScale = 1.5f, reduce = false))
        assertEquals(MotionScale.Reduced, MotionScale.of(systemAnimatorScale = 0f, reduce = false))
        assertEquals(MotionScale.Reduced, MotionScale.of(systemAnimatorScale = 1f, reduce = true))
    }

    @Test
    fun theCurvesStartAtZeroAndEndAtOne() {
        val curves = listOf(
            OctoEasing.Spring, OctoEasing.Overshoot, OctoEasing.Bounce,
            OctoEasing.Smooth, OctoEasing.Snappy, OctoEasing.EaseIn, OctoEasing.Sweep,
        )
        for (curve in curves) {
            assertEquals(0f, curve.transform(0f), 1e-3f)
            assertEquals(1f, curve.transform(1f), 1e-3f)
        }
        // The overshoot goes past the end before it settles.
        assertTrue((1..99).any { OctoEasing.Overshoot.transform(it / 100f) > 1f })
    }

    @Test
    fun wordsAreBlackOnALightFillAndWhiteOnADarkOne() {
        assertEquals(Color.Black, contentColorFor(Color.White))
        assertEquals(Color.White, contentColorFor(Color.Black))
        // Octo's accent is light enough for black words; the accent button's
        // darker fill and the tonal fill take white.
        assertEquals(Color.Black, contentColorFor(OctoColors.Accent))
        assertEquals(Color.White, contentColorFor(AccentFill))
        assertEquals(Color.White, contentColorFor(OctoColors.AccentTonal))
    }

    @Test
    fun everyAccentKeepsTheSameWordsAndOnlyTheAccentFamilyMoves() {
        try {
            for (choice in app.winters.octo.theme.FixedAccents) {
                OctoColors.useAccent(Color(choice.argb!!))
                assertEquals(choice.label, Color(choice.argb!!), OctoColors.Accent)
                assertEquals(choice.label, Color.Black, contentColorFor(OctoColors.Accent))
                assertEquals(choice.label, Color.White, contentColorFor(AccentFill))
                assertEquals(choice.label, Color.White, contentColorFor(OctoColors.AccentTonal))
                assertEquals(choice.label, Color.White, contentColorFor(OctoColors.AccentSelected))
                // The words stay in Octo's blue grey whatever the accent.
                assertEquals(OctoAccent, OctoColors.TextSecondary)
                assertEquals(OctoAccent.copy(alpha = 0.8f), OctoColors.TextMuted)
            }
        } finally {
            OctoColors.useAccent(OctoAccent)
        }
        assertEquals(Color(0xFFADC4CC), OctoColors.AccentHover)
    }

    @Test
    fun theSwitchFromWhiteToBlackWordsIsAtAbout58Percent() {
        // Greys either side of the threshold.
        val below = (0..255).map { Color(it, it, it) }.last { perceivedLightness(it) <= LightFillThreshold }
        val above = (0..255).map { Color(it, it, it) }.first { perceivedLightness(it) > LightFillThreshold }
        assertEquals(Color.White, contentColorFor(below))
        assertEquals(Color.Black, contentColorFor(above))
        assertEquals(0.58f, perceivedLightness(above), 0.01f)
        // Mid grey is about 53.6% light to the eye.
        assertEquals(0.536f, perceivedLightness(Color(128, 128, 128)), 0.005f)
    }

    @Test
    fun theAccentFamilyIsDerivedFromTheAccent() {
        val accent = OctoColors.Accent
        // Selected row: 40% of the accent out of black.
        assertEquals(accent.red * 0.4f, OctoColors.AccentSelected.red, Byte)
        assertEquals(accent.green * 0.4f, OctoColors.AccentSelected.green, Byte)
        assertEquals(accent.blue * 0.4f, OctoColors.AccentSelected.blue, Byte)
        // Tonal: a tenth of the accent in rgb(30 30 30).
        val grey = 30f / 255f
        assertEquals(grey + (accent.red - grey) * 0.1f, OctoColors.AccentTonal.red, Byte)
        assertEquals(grey + (accent.blue - grey) * 0.1f, OctoColors.AccentTonal.blue, Byte)
        // The ring is the accent at 70%, the menu press the selected row at 55%.
        assertEquals(accent.copy(alpha = 0.7f), OctoColors.FocusRing)
        assertEquals(OctoColors.AccentSelected.copy(alpha = 0.55f), OctoColors.MenuPress)
        // The destructive words are the signal red, softened.
        assertEquals(OctoColors.SignalRed.copy(alpha = 0.85f), OctoColors.Destructive)
    }

    @Test
    fun theTextHierarchyIsWhiteAtFallingOpacities() {
        val levels = listOf(OctoInk.Primary, OctoInk.Secondary, OctoInk.Tertiary, OctoInk.Quaternary, OctoInk.Quinary)
        // Colours keep their opacity to 1/255.
        listOf(0.85f, 0.55f, 0.25f, 0.10f, 0.05f).zip(levels).forEach { (want, color) -> assertEquals(want, color.alpha, 0.003f) }
        assertTrue(levels.all { it.red == 1f && it.green == 1f && it.blue == 1f })
    }

    @Test
    fun theRadiiAreTheSpecs() {
        assertEquals(listOf(10.dp, 6.dp, 12.dp), listOf(OctoRadius.Chrome, OctoRadius.ChromeSmall, OctoRadius.Row))
        assertEquals(listOf(3.dp, 6.dp, 8.dp, 12.dp), listOf(OctoRadius.ArtXs, OctoRadius.ArtS, OctoRadius.ArtM, OctoRadius.ArtL))
        assertEquals(12.dp, OctoRadius.Dialog)
    }

    @Test
    fun anIconGesturePeaksAt45PercentAndRestsAtEitherEnd() {
        assertEquals(0f, accentStrength(0f), 0f)
        assertEquals(0f, accentStrength(1f), 0f)
        assertEquals(1f, accentStrength(AccentPeak), 1e-3f)
        assertTrue(accentStrength(0.2f) < 1f && accentStrength(0.8f) < 1f)
        assertEquals(1.2f, accentPose(IconAccent.Pulse, AccentPeak).scale, 1e-3f)
        assertEquals(4f, accentPose(IconAccent.SlideForward, AccentPeak).dx, 1e-3f)
        assertEquals(-4f, accentPose(IconAccent.SlideBack, AccentPeak).dx, 1e-3f)
        // Reduced motion keeps every icon still.
        for (accent in IconAccent.entries) assertEquals(AccentPose.Rest, accentPose(accent, AccentPeak, distance = 0f))
    }

    @Test
    fun theTabsThePillPassesFlashAndTheOneItLandsOnDoesNot() {
        // Moving from tab 0 to tab 3, halfway across tab 1.
        assertEquals(GearShiftTint, gearShiftTint(1, pill = 1f, selected = 3), 1e-6f)
        assertEquals(GearShiftTint / 2f, gearShiftTint(2, pill = 1.5f, selected = 3), 1e-6f)
        assertEquals(0f, gearShiftTint(3, pill = 3f, selected = 3), 0f)
        assertEquals(0f, gearShiftTint(0, pill = 2f, selected = 3), 0f)
    }

    @Test
    fun aSliderSnapsToItsSteps() {
        assertEquals(0.25f, snapToSteps(0.3f, 4), 1e-6f)
        assertEquals(0.5f, snapToSteps(0.4f, 4), 1e-6f)
        assertEquals(0.3f, snapToSteps(0.3f, 0), 1e-6f)
        assertEquals(1f, snapToSteps(1.4f, 0), 1e-6f)
        assertFalse(snapToSteps(-1f, 3) < 0f)
    }
}
