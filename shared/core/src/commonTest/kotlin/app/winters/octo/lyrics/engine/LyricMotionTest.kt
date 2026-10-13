package app.winters.octo.lyrics.engine

import org.junit.Assert.assertArrayEquals
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test
import kotlin.math.PI
import kotlin.math.ceil
import kotlin.math.sin
import kotlin.math.sqrt

class LyricMotionTest {
    // ---- Layout ----

    @Test
    fun theFocusLineIsCentredAtItsAnchor() {
        val heights = doubleArrayOf(50.0, 60.0, 70.0, 80.0)
        val above = heightsAbove(heights)
        val view = 1000.0
        val focus = 2
        val y = DoubleArray(4) { targetY(it, focus, above, heights, view) }
        assertEquals(FOCUS_AT * 1000, y[focus] + heights[focus] / 2, 1e-9)
        // The others stack right against it.
        assertEquals(y[2] - 60.0, y[1], 1e-9)
        assertEquals(y[1] - 50.0, y[0], 1e-9)
        assertEquals(y[2] + 70.0, y[3], 1e-9)
    }

    // ---- The ripple ----

    @Test
    fun theRippleMatchesTheWorkedExample() {
        // Six lines on screen, focus on line 2.
        val targets = doubleArrayOf(100.0, 200.0, 300.0, 400.0, 500.0, 600.0)
        val delays = cascadeDelays(targets, focus = 2, viewHeight = 1000.0, stepScale = 1.0)
        val expected = doubleArrayOf(0.0, 0.05, 0.10, 0.150, 0.198, 0.243)
        expected.indices.forEach { assertEquals("line $it", expected[it], delays[it], 0.001) }
        // Three lines below the focus starts about 0.14 s after it.
        assertEquals(0.14, delays[5] - delays[2], 0.005)
    }

    @Test
    fun linesOffScreenDoNotWaitOrPushTheOthersBack() {
        val targets = doubleArrayOf(-300.0, -100.0, 100.0, 200.0, 1200.0)
        val delays = cascadeDelays(targets, focus = 2, viewHeight = 1000.0, stepScale = 1.0)
        assertArrayEquals(doubleArrayOf(0.0, 0.0, 0.0, 0.05, 0.0), delays, 1e-12)
    }

    @Test
    fun theRippleSettingScalesTheStep() {
        val targets = doubleArrayOf(100.0, 200.0, 300.0)
        assertEquals(0.2, cascadeDelays(targets, 0, 1000.0, 2.0)[1] * 2, 1e-9)
        assertArrayEquals(DoubleArray(3), cascadeDelays(targets, 0, 1000.0, 0.0), 0.0)
    }

    // ---- Fades ----

    @Test
    fun opacityAndBlurFollowTheLinesState() {
        assertEquals(1.0, opacityTarget(LineStatus.Active, false), 0.0)
        assertEquals(0.55, opacityTarget(LineStatus.Upcoming, false), 0.0)
        assertEquals(0.0, opacityTarget(LineStatus.Passed, false), 0.0)
        assertEquals(PASSED_SHOWN_OPACITY, opacityTarget(LineStatus.Passed, true), 0.0)
        assertEquals(0.0, blurTarget(LineStatus.Active, 3), 0.0)
        assertEquals(1.0, blurTarget(LineStatus.Upcoming, 1), 1e-12)
        assertEquals(MAX_BLUR, blurTarget(LineStatus.Passed, 9), 0.0)
    }

    @Test
    fun fadesSettleTheSameAtAnyFrameRateAndSnapWhenClose() {
        var sixty = 0.0
        var oneTwenty = 0.0
        repeat(6) { sixty = settle(sixty, 1.0, 1.0 / 60, 0.0) }
        repeat(12) { oneTwenty = settle(oneTwenty, 1.0, 1.0 / 120, 0.0) }
        assertEquals(sixty, oneTwenty, 1e-12)
        assertEquals(1.0, settle(0.999, 1.0, 1.0 / 60, OPACITY_SNAP), 0.0)
    }

    @Test
    fun blurIsDrawnInQuarterStepsAndNotAtAllWhenTiny() {
        assertEquals(1.25, shownBlur(1.2), 0.0)
        assertEquals(0.0, shownBlur(0.09), 0.0)
        assertEquals(5.0, shownBlur(4.95), 0.0)
    }

    // ---- The word fill ----

    @Test
    fun theMaskIsTwoWordsWideWithHalfALineOfSoftEdge() {
        val shape = maskShape(wordWidth = 100.0, lineHeight = 40.0, softness = 1.0)
        val f = 0.5 * 40 / 100
        assertEquals(f, shape.edge, 1e-12)
        assertEquals(2 + f, shape.size, 1e-12)
        val v = f / (2 + f)
        assertEquals((1 - v) / 2, shape.brightStop, 1e-12)
        assertEquals((1 - v) / 2 + v, shape.darkStop, 1e-12)
        // The soft edge is half a line high wide, whatever the word's width.
        assertEquals(20.0, (shape.darkStop - shape.brightStop) * shape.size * 100.0, 1e-9)
        val wide = maskShape(400.0, 40.0, 1.0)
        assertEquals(20.0, (wide.darkStop - wide.brightStop) * wide.size * 400.0, 1e-9)
    }

    @Test
    fun theMaskSlidesFromAllDarkToAllBright() {
        val shape = maskShape(100.0, 40.0, 1.0)
        val width = shape.size * 100.0
        // Nothing sung: the dark part starts where the word does.
        val none = maskLeft(0.0, 50.0, 100.0, shape, rtl = false)
        assertEquals(50.0, none + shape.darkStop * width, 1e-9)
        // All sung: the bright part runs to the word's end.
        val all = maskLeft(1.0, 50.0, 100.0, shape, rtl = false)
        assertEquals(150.0, all + shape.brightStop * width, 1e-9)
        // Half: the soft edge straddles the middle.
        val half = maskLeft(0.5, 50.0, 100.0, shape, rtl = false)
        assertEquals(100.0, half + (shape.brightStop + shape.darkStop) / 2 * width, 1e-9)
    }

    @Test
    fun rightToLeftWordsFillFromTheRight() {
        val shape = maskShape(100.0, 40.0, 1.0)
        val width = shape.size * 100.0
        // Mirrored mask: dark on the left, bright on the right.
        val none = maskLeft(0.0, 50.0, 100.0, shape, rtl = true)
        assertEquals(150.0, none + shape.brightStop * width, 1e-9)
        val all = maskLeft(1.0, 50.0, 100.0, shape, rtl = true)
        assertEquals(50.0, all + shape.darkStop * width, 1e-9)
    }

    @Test
    fun noSoftnessGivesAHardEdge() {
        val shape = maskShape(100.0, 40.0, 0.0)
        assertEquals(2.0, shape.size, 0.0)
        assertEquals(0.5, shape.brightStop, 0.0)
        assertEquals(0.5, shape.darkStop, 0.0)
    }

    @Test
    fun aWordIsSungEvenlyFromStartToEnd() {
        assertEquals(0.0, wordProgress(0.9, 1.0, 2.0), 0.0)
        assertEquals(0.25, wordProgress(1.25, 1.0, 2.0), 1e-12)
        assertEquals(1.0, wordProgress(2.5, 1.0, 2.0), 0.0)
    }

    // ---- Brightness ----

    @Test
    fun brightnessFollowsTheLinesSize() {
        assertEquals(Brightness(1.0, 0.4), brightness(1.0))
        assertEquals(Brightness(0.3, 0.3), brightness(0.0))
        assertEquals(Brightness(0.66, 0.36), brightness(0.51))
        // Past either end of the spring's swing, it holds.
        assertEquals(Brightness(1.0, 0.4), brightness(1.03))
        assertEquals(TouchedBrightness, Brightness(1.0, 0.85))
    }

    @Test
    fun brightnessMovesInSteps() {
        // Tiny changes round to the same pair, so nothing redraws.
        assertEquals(brightness(0.520), brightness(0.525))
    }

    // ---- Lift and emphasis ----

    @Test
    fun wordsRiseOverAtLeastASecondAndStayUp() {
        assertEquals(0.0, liftEm(0.5, 1.0, 1.2, false, 1.0), 0.0)
        assertEquals(-0.05, liftEm(2.0, 1.0, 1.2, false, 1.0), 1e-12)
        assertEquals(-0.10, liftEm(9.0, 1.0, 1.2, true, 1.0), 1e-12)
        assertEquals(-0.10, liftEm(9.0, 1.0, 1.2, false, 2.0), 1e-12)
        // Halfway through its second of rising, eased out: past halfway up.
        assertTrue(liftEm(1.5, 1.0, 1.2, false, 1.0) < -0.025)
    }

    @Test
    fun heldWordsBloomByHowLongTheyAreHeld() {
        assertNull(emphasisFor(0.99, 4, false, 1.0, 1.0))
        val two = emphasisFor(2.0, 4, false, 1.0, 1.0)!!
        assertEquals(0.6, two.amount, 1e-9)
        assertEquals(0.5 * (2.0 / 3).let { it * it * it }, two.glow, 1e-9)
        assertEquals(two.glow * 0.3, two.glowRadiusEm, 1e-9)
        assertEquals(2.0, two.run, 0.0)
        val three = emphasisFor(3.0, 4, false, 1.0, 1.0)!!
        assertEquals(sqrt(1.5) * 0.6, three.amount, 1e-9)
        assertEquals(0.5, three.glow, 1e-9)
    }

    private fun words(vararg seconds: Double): List<SyncWord> {
        var t = 0.0
        return seconds.map { d -> SyncWord("w", t, t + d, true).also { t += d } }
    }

    @Test
    fun withFastSingingAWordHeldLongForItsLineBlooms() {
        // A rap line: quick words and one dragged out.
        val line = words(0.2, 0.25, 0.2, 0.7, 0.2, 0.3)
        assertArrayEquals(booleanArrayOf(false, false, false, true, false, false), heldWords(line, fast = true))
        // Without fast singing, only notes held a second or more.
        assertArrayEquals(BooleanArray(6), heldWords(line, fast = false))
        assertArrayEquals(booleanArrayOf(false, true), heldWords(words(0.3, 1.2), fast = false))
    }

    @Test
    fun aWordIsNotHeldWhenTheWholeLineIsSlowOrItIsTooShort() {
        // Long for nothing: every word about as long.
        assertArrayEquals(BooleanArray(3), heldWords(words(0.7, 0.8, 0.75), fast = true))
        // Long for its line, but under the floor.
        assertArrayEquals(BooleanArray(3), heldWords(words(0.1, 0.5, 0.1), fast = true))
        // A line of one word has nothing to be long against.
        assertArrayEquals(BooleanArray(1), heldWords(words(0.9), fast = true))
        assertArrayEquals(BooleanArray(0), heldWords(emptyList(), fast = true))
    }

    @Test
    fun aFastHeldWordBloomsAsStronglyAsANoteHeldLonger() {
        val quick = emphasisFor(0.7, 4, false, 1.0, 1.0, fast = true, held = true)!!
        val asIf = emphasisFor(FAST_EMPHASIS_STRENGTH_S, 4, false, 1.0, 1.0, fast = true)!!
        assertEquals(asIf.amount, quick.amount, 1e-9)
        assertEquals(asIf.glow, quick.glow, 1e-9)
        // Its letters still swell over the word's own length.
        assertEquals(0.7, quick.run, 1e-9)
        // Not held, nothing blooms, fast or not.
        assertNull(emphasisFor(0.7, 4, false, 1.0, 1.0, fast = true, held = false))
    }

    @Test
    fun withFastSingingHeldNotesGlowMoreAndOffNothingChanges() {
        val old = emphasisFor(1.5, 4, false, 1.0, 1.0)!!
        val fast = emphasisFor(1.5, 4, false, 1.0, 1.0, fast = true)!!
        assertEquals(0.5 * 0.125, old.glow, 1e-9)
        // Fast, it blooms at least as strongly as a note held FAST_EMPHASIS_STRENGTH_S.
        val g = FAST_EMPHASIS_STRENGTH_S / 3
        assertEquals(0.5 * g * sqrt(g), fast.glow, 1e-9)
        assertTrue(fast.glow > old.glow * 2)
        // Past three seconds the glow is the same either way.
        assertEquals(emphasisFor(4.0, 4, false, 1.0, 1.0)!!.glow, emphasisFor(4.0, 4, false, 1.0, 1.0, fast = true)!!.glow, 1e-9)
    }

    @Test
    fun withFastSingingWordsRiseALittleMore() {
        assertEquals(LIFT_EM, liftOf(background = false, fast = false), 0.0)
        assertEquals(FAST_LIFT_EM, liftOf(background = false, fast = true), 0.0)
        assertEquals(FAST_BACKGROUND_LIFT_EM, liftOf(background = true, fast = true), 0.0)
        assertEquals(-FAST_LIFT_EM, liftEm(5.0, 0.0, 1.0, background = false, lift = 1.0, fast = true), 1e-9)
    }

    @Test
    fun theLastWordBloomsHarderAndLongerWithinTheLimits() {
        val last = emphasisFor(3.0, 4, true, 1.0, 1.0)!!
        assertEquals(sqrt(1.5) * 0.6 * 1.6, last.amount, 1e-9)
        assertEquals(0.75, last.glow, 1e-9)
        assertEquals(3.6, last.run, 1e-9)
        // Held long enough, both reach their limits.
        val long = emphasisFor(4.0, 4, true, 1.0, 1.0)!!
        assertEquals(1.2, long.amount, 1e-9)
        assertEquals(0.8, long.glow, 1e-9)
        assertEquals(0.24, long.glowRadiusEm, 1e-9)
        // The settings apply after the limits.
        val doubled = emphasisFor(4.0, 4, true, 2.0, 2.0)!!
        assertEquals(2.4, doubled.amount, 1e-9)
        assertEquals(0.3, doubled.glowRadiusEm, 1e-9)
    }

    @Test
    fun lettersStartOneAfterAnother() {
        val two = emphasisFor(2.0, 4, false, 1.0, 1.0)!!
        val starts = (0 until 4).map { glyphStart(10.0, two, it) }
        assertEquals(listOf(10.0, 10.2, 10.4, 10.6).map { it }, starts.map { Math.round(it * 1000) / 1000.0 })
    }

    @Test
    fun aLetterPeaksMidwayThenSettlesBack() {
        val bloom = emphasisFor(2.0, 4, false, 1.0, 1.0)!!
        val start = glyphStart(10.0, bloom, 1)
        assertEquals(RestingGlyph, glyphPose(start - 0.01, 10.0, bloom, 1, 4))
        val peak = glyphPose(start + bloom.run / 2, 10.0, bloom, 1, 4)
        assertEquals(1 + 0.1 * bloom.amount, peak.scale, 1e-9)
        assertEquals(-0.03 * bloom.amount * (4 / 2.0 - 1), peak.dxEm, 1e-9)
        assertEquals(-0.025 * bloom.amount, peak.dyEm, 1e-9)
        assertEquals(bloom.glow, peak.glowAlpha, 1e-9)
        assertEquals(RestingGlyph, glyphPose(start + bloom.run, 10.0, bloom, 1, 4))
    }

    @Test
    fun theSwellCurveRisesThenFalls() {
        assertEquals(0.0, upAndBack(0.0), 0.0)
        assertEquals(1.0, upAndBack(0.5), 1e-9)
        assertEquals(0.0, upAndBack(1.0), 0.0)
        assertTrue(upAndBack(0.25) in 0.0..1.0)
        assertTrue(upAndBack(0.75) in 0.0..1.0)
        // A straight bezier is a straight line.
        assertEquals(0.3, CubicBezier(0.0, 0.0, 1.0, 1.0).at(0.3), 1e-6)
        // Ease-out is ahead of a straight line at the start.
        assertTrue(EaseOut.at(0.3) > 0.3)
    }

    @Test
    fun theBobStartsEarlyAndRunsLonger() {
        val bloom = emphasisFor(2.0, 4, false, 1.0, 1.0)!!
        // 0.4 s before the first letter, it has just begun.
        assertEquals(0.0, bobEm(9.6, 10.0, bloom, 0, 1.0, false), 1e-12)
        // At the middle of its 1.4 run lengths, it is at its highest.
        val middle = 9.6 + 1.4 * bloom.run / 2
        assertEquals(-0.05, bobEm(middle, 10.0, bloom, 0, 1.0, false), 1e-9)
        assertEquals(-0.10, bobEm(middle, 10.0, bloom, 0, 1.0, true), 1e-9)
    }

    // ---- Interlude dots, over a 10 s gap ----

    private fun breathe(p: Double, f: Double): Double {
        val period = f / ceil(f / 1.5)
        return sin(1.5 * PI - 2 * p / period) / 20 + 1
    }

    @Test
    fun dotsGrowInUnseenThenFadeIn() {
        val early = dotsPose(0.25, 10.0, grown = false)
        assertEquals(0.0, early.opacity, 0.0)
        assertEquals(breathe(0.25, 10.0) * easeOutExpo(0.125) * 0.7, early.scale, 1e-9)
        val fading = dotsPose(0.75, 10.0, grown = false)
        assertEquals(0.5, fading.opacity, 1e-9)
        assertEquals(breathe(0.75, 10.0) * easeOutExpo(0.375) * 0.7, fading.scale, 1e-9)
    }

    @Test
    fun dotsBreatheInTheMiddle() {
        val middle = dotsPose(5.0, 10.0, grown = false)
        assertEquals(1.0, middle.opacity, 0.0)
        assertEquals(breathe(5.0, 10.0) * 0.7, middle.scale, 1e-9)
        assertTrue(middle.scale in 0.7 * 0.95..0.7 * 1.05)
    }

    @Test
    fun dotsInhaleThenPopAwayBeforeTheNextLine() {
        val closing = dotsPose(9.5, 10.0, grown = false)
        assertEquals(1.0, closing.opacity, 0.0)
        assertEquals(breathe(9.5, 10.0) * (1 - easeInOutBack(0.25 / 0.75 / 2)) * 0.7, closing.scale, 1e-9)
        // The little inhale: a touch bigger just as the exit starts.
        assertTrue(closing.scale > breathe(9.5, 10.0) * 0.7)
        val going = dotsPose(9.8, 10.0, grown = false)
        assertEquals(0.2 / 0.375, going.opacity, 1e-9)
        assertEquals(0.0, dotsPose(10.0, 10.0, grown = false).opacity, 0.0)
    }

    @Test
    fun dotsLightOneTwoThree() {
        val u = 10.0 - 0.75
        fun lights(p: Double) = dotsPose(p, 10.0, grown = false).lights
        // At the start all three are at their floor.
        assertArrayEquals(doubleArrayOf(0.25, 0.25, 0.25), lights(0.5), 0.0)
        // A third of the way: the first well lit, the second just starting.
        val third = lights(u / 3 + 0.5)
        assertTrue(third[0] > third[1])
        assertTrue(third[1] >= third[2])
        assertEquals(1.0, lights(u)[0], 0.0)
        assertEquals(1.0, lights(u)[1], 0.0)
        assertEquals(0.75, lights(u)[2], 1e-9)
        // Each is its own formula.
        val p = 6.0
        (0..2).forEach { k -> assertEquals(((p - k * u / 3) * 3 / u * 0.75).coerceIn(0.25, 1.0), lights(p)[k], 1e-12) }
    }

    @Test
    fun aSeekIntoTheGapShowsTheDotsAlreadyGrown() {
        val grown = dotsPose(0.25, 10.0, grown = true)
        assertEquals(1.0, grown.opacity, 0.0)
        assertEquals(breathe(0.25, 10.0) * 0.7, grown.scale, 1e-9)
        assertEquals(1.0, interludeOpen(0.1, 10.0, grown = true), 0.0)
    }

    @Test
    fun theGapOpensAndClosesItsSpace() {
        assertEquals(easeOutExpo(0.4 / 0.8), interludeOpen(0.4, 10.0, grown = false), 1e-12)
        assertEquals(1.0, interludeOpen(5.0, 10.0, grown = false), 1e-3)
        assertEquals(easeOutExpo(0.3 / 0.6), interludeOpen(9.7, 10.0, grown = false), 1e-12)
        assertEquals(0.0, interludeOpen(10.0, 10.0, grown = false), 0.0)
    }

    @Test
    fun reducedMotionDotsHoldStill() {
        assertEquals(0.7, StillDots.scale, 0.0)
        assertArrayEquals(doubleArrayOf(0.85, 0.85, 0.85), StillDots.lights, 0.0)
    }

    // ---- Curved lyrics ----

    @Test
    fun theFocusSitsForwardAndFlat() {
        val pose = arcPose(centre = FOCUS_AT * 1000, viewHeight = 1000.0, side = 1)
        assertEquals(0.0, pose.translationX, 1e-12)
        assertEquals(40.0, pose.z, 1e-12)
        assertEquals(0.0, pose.rotationY, 1e-12)
        assertEquals(1400.0 / 1360.0, pose.scale, 1e-12)
    }

    @Test
    fun linesAwayFromTheFocusCurveInward() {
        val radius = 0.55 * 1000
        val half = arcPose(centre = FOCUS_AT * 1000 + radius / 2, viewHeight = 1000.0, side = 1)
        // r = 0.5, a = 0.75.
        assertEquals(60 * 0.25, half.translationX, 1e-9)
        assertEquals(40 * 0.75, half.z, 1e-9)
        assertEquals(0.09 * 0.5 * 0.75, half.rotationY, 1e-12)
        assertEquals(1400.0 / (1400 - 30), half.scale, 1e-12)
        // Right-aligned lines curve the other way.
        val right = arcPose(centre = FOCUS_AT * 1000 + radius / 2, viewHeight = 1000.0, side = -1)
        assertEquals(-half.translationX, right.translationX, 1e-12)
        assertEquals(-half.rotationY, right.rotationY, 1e-12)
        // Far off, flat against the drum's edge.
        val far = arcPose(centre = FOCUS_AT * 1000 + 3 * radius, viewHeight = 1000.0, side = 1)
        assertEquals(60.0, far.translationX, 1e-9)
        assertEquals(0.0, far.z, 1e-12)
        assertEquals(1.0, far.scale, 1e-12)
    }
}
