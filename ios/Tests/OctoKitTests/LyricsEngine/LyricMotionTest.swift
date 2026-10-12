import Foundation
import Testing
@testable import OctoKit

@Suite struct LyricMotionTest {
    // MARK: - Layout

    @Test func theFocusLineIsCentredAtItsAnchor() {
        let heights = [50.0, 60.0, 70.0, 80.0]
        let above = heightsAbove(heights)
        let view = 1000.0
        let focus = 2
        let y = (0..<4).map { targetY($0, a: focus, above: above, heights: heights, viewHeight: view) }
        #expect(near(FOCUS_AT * 1000, y[focus] + heights[focus] / 2, 1e-9))
        // The others stack right against it.
        #expect(near(y[2] - 60.0, y[1], 1e-9))
        #expect(near(y[1] - 50.0, y[0], 1e-9))
        #expect(near(y[2] + 70.0, y[3], 1e-9))
    }

    // MARK: - The ripple

    @Test func theRippleMatchesTheWorkedExample() {
        // Six lines on screen, focus on line 2.
        let targets = [100.0, 200.0, 300.0, 400.0, 500.0, 600.0]
        let delays = cascadeDelays(targets, focus: 2, viewHeight: 1000.0, stepScale: 1.0)
        let expected = [0.0, 0.05, 0.10, 0.150, 0.198, 0.243]
        for i in expected.indices { #expect(near(expected[i], delays[i], 0.001), "line \(i)") }
        // Three lines below the focus starts about 0.14 s after it.
        #expect(near(0.14, delays[5] - delays[2], 0.005))
    }

    @Test func linesOffScreenDoNotWaitOrPushTheOthersBack() {
        let targets = [-300.0, -100.0, 100.0, 200.0, 1200.0]
        let delays = cascadeDelays(targets, focus: 2, viewHeight: 1000.0, stepScale: 1.0)
        #expect(near([0.0, 0.0, 0.0, 0.05, 0.0], delays, 1e-12))
    }

    @Test func theRippleSettingScalesTheStep() {
        let targets = [100.0, 200.0, 300.0]
        #expect(near(0.2, cascadeDelays(targets, focus: 0, viewHeight: 1000.0, stepScale: 2.0)[1] * 2, 1e-9))
        #expect(near([0.0, 0.0, 0.0], cascadeDelays(targets, focus: 0, viewHeight: 1000.0, stepScale: 0.0), 0.0))
    }

    // MARK: - Fades

    @Test func opacityAndBlurFollowTheLinesState() {
        #expect(near(1.0, opacityTarget(.active, showPassed: false), 0.0))
        #expect(near(0.55, opacityTarget(.upcoming, showPassed: false), 0.0))
        #expect(near(0.0, opacityTarget(.passed, showPassed: false), 0.0))
        #expect(near(PASSED_SHOWN_OPACITY, opacityTarget(.passed, showPassed: true), 0.0))
        #expect(near(0.0, blurTarget(.active, distance: 3), 0.0))
        #expect(near(1.0, blurTarget(.upcoming, distance: 1), 1e-12))
        #expect(near(MAX_BLUR, blurTarget(.passed, distance: 9), 0.0))
    }

    @Test func fadesSettleTheSameAtAnyFrameRateAndSnapWhenClose() {
        var sixty = 0.0
        var oneTwenty = 0.0
        for _ in 0..<6 { sixty = settle(sixty, target: 1.0, dt: 1.0 / 60, snap: 0.0) }
        for _ in 0..<12 { oneTwenty = settle(oneTwenty, target: 1.0, dt: 1.0 / 120, snap: 0.0) }
        #expect(near(sixty, oneTwenty, 1e-12))
        #expect(near(1.0, settle(0.999, target: 1.0, dt: 1.0 / 60, snap: OPACITY_SNAP), 0.0))
    }

    @Test func blurIsDrawnInQuarterStepsAndNotAtAllWhenTiny() {
        #expect(near(1.25, shownBlur(1.2), 0.0))
        #expect(near(0.0, shownBlur(0.09), 0.0))
        #expect(near(5.0, shownBlur(4.95), 0.0))
    }

    // MARK: - The word fill

    @Test func theMaskIsTwoWordsWideWithHalfALineOfSoftEdge() {
        let shape = maskShape(wordWidth: 100.0, lineHeight: 40.0, softness: 1.0)
        let f = 0.5 * 40 / 100
        #expect(near(f, shape.edge, 1e-12))
        #expect(near(2 + f, shape.size, 1e-12))
        let v = f / (2 + f)
        #expect(near((1 - v) / 2, shape.brightStop, 1e-12))
        #expect(near((1 - v) / 2 + v, shape.darkStop, 1e-12))
        // The soft edge is half a line high wide, whatever the word's width.
        #expect(near(20.0, (shape.darkStop - shape.brightStop) * shape.size * 100.0, 1e-9))
        let wide = maskShape(wordWidth: 400.0, lineHeight: 40.0, softness: 1.0)
        #expect(near(20.0, (wide.darkStop - wide.brightStop) * wide.size * 400.0, 1e-9))
    }

    @Test func theMaskSlidesFromAllDarkToAllBright() {
        let shape = maskShape(wordWidth: 100.0, lineHeight: 40.0, softness: 1.0)
        let width = shape.size * 100.0
        // Nothing sung: the dark part starts where the word does.
        let none = maskLeft(0.0, wordLeft: 50.0, wordWidth: 100.0, shape: shape, rtl: false)
        #expect(near(50.0, none + shape.darkStop * width, 1e-9))
        // All sung: the bright part runs to the word's end.
        let all = maskLeft(1.0, wordLeft: 50.0, wordWidth: 100.0, shape: shape, rtl: false)
        #expect(near(150.0, all + shape.brightStop * width, 1e-9))
        // Half: the soft edge straddles the middle.
        let half = maskLeft(0.5, wordLeft: 50.0, wordWidth: 100.0, shape: shape, rtl: false)
        #expect(near(100.0, half + (shape.brightStop + shape.darkStop) / 2 * width, 1e-9))
    }

    @Test func rightToLeftWordsFillFromTheRight() {
        let shape = maskShape(wordWidth: 100.0, lineHeight: 40.0, softness: 1.0)
        let width = shape.size * 100.0
        // Mirrored mask: dark on the left, bright on the right.
        let none = maskLeft(0.0, wordLeft: 50.0, wordWidth: 100.0, shape: shape, rtl: true)
        #expect(near(150.0, none + shape.brightStop * width, 1e-9))
        let all = maskLeft(1.0, wordLeft: 50.0, wordWidth: 100.0, shape: shape, rtl: true)
        #expect(near(50.0, all + shape.darkStop * width, 1e-9))
    }

    @Test func noSoftnessGivesAHardEdge() {
        let shape = maskShape(wordWidth: 100.0, lineHeight: 40.0, softness: 0.0)
        #expect(near(2.0, shape.size, 0.0))
        #expect(near(0.5, shape.brightStop, 0.0))
        #expect(near(0.5, shape.darkStop, 0.0))
    }

    @Test func aWordIsSungEvenlyFromStartToEnd() {
        #expect(near(0.0, wordProgress(0.9, start: 1.0, end: 2.0), 0.0))
        #expect(near(0.25, wordProgress(1.25, start: 1.0, end: 2.0), 1e-12))
        #expect(near(1.0, wordProgress(2.5, start: 1.0, end: 2.0), 0.0))
    }

    // MARK: - Brightness

    @Test func brightnessFollowsTheLinesSize() {
        #expect(brightness(1.0) == Brightness(1.0, 0.4))
        #expect(brightness(0.0) == Brightness(0.3, 0.3))
        #expect(brightness(0.51) == Brightness(0.66, 0.36))
        // Past either end of the spring's swing, it holds.
        #expect(brightness(1.03) == Brightness(1.0, 0.4))
        #expect(TouchedBrightness == Brightness(1.0, 0.85))
    }

    @Test func brightnessMovesInSteps() {
        // Tiny changes round to the same pair, so nothing redraws.
        #expect(brightness(0.520) == brightness(0.525))
    }

    // MARK: - Lift and emphasis

    @Test func wordsRiseOverAtLeastASecondAndStayUp() {
        #expect(near(0.0, liftEm(0.5, start: 1.0, end: 1.2, background: false, lift: 1.0), 0.0))
        #expect(near(-0.05, liftEm(2.0, start: 1.0, end: 1.2, background: false, lift: 1.0), 1e-12))
        #expect(near(-0.10, liftEm(9.0, start: 1.0, end: 1.2, background: true, lift: 1.0), 1e-12))
        #expect(near(-0.10, liftEm(9.0, start: 1.0, end: 1.2, background: false, lift: 2.0), 1e-12))
        // Halfway through its second of rising, eased out: past halfway up.
        #expect(liftEm(1.5, start: 1.0, end: 1.2, background: false, lift: 1.0) < -0.025)
    }

    @Test func heldWordsBloomByHowLongTheyAreHeld() {
        #expect(emphasisFor(0.99, glyphs: 4, last: false, emphasis: 1.0, glow: 1.0) == nil)
        let two = emphasisFor(2.0, glyphs: 4, last: false, emphasis: 1.0, glow: 1.0)!
        #expect(near(0.6, two.amount, 1e-9))
        let third = 2.0 / 3
        #expect(near(0.5 * (third * third * third), two.glow, 1e-9))
        #expect(near(two.glow * 0.3, two.glowRadiusEm, 1e-9))
        #expect(near(2.0, two.run, 0.0))
        let three = emphasisFor(3.0, glyphs: 4, last: false, emphasis: 1.0, glow: 1.0)!
        #expect(near((1.5).squareRoot() * 0.6, three.amount, 1e-9))
        #expect(near(0.5, three.glow, 1e-9))
    }

    @Test func theLastWordBloomsHarderAndLongerWithinTheLimits() {
        let last = emphasisFor(3.0, glyphs: 4, last: true, emphasis: 1.0, glow: 1.0)!
        #expect(near((1.5).squareRoot() * 0.6 * 1.6, last.amount, 1e-9))
        #expect(near(0.75, last.glow, 1e-9))
        #expect(near(3.6, last.run, 1e-9))
        // Held long enough, both reach their limits.
        let long = emphasisFor(4.0, glyphs: 4, last: true, emphasis: 1.0, glow: 1.0)!
        #expect(near(1.2, long.amount, 1e-9))
        #expect(near(0.8, long.glow, 1e-9))
        #expect(near(0.24, long.glowRadiusEm, 1e-9))
        // The settings apply after the limits.
        let doubled = emphasisFor(4.0, glyphs: 4, last: true, emphasis: 2.0, glow: 2.0)!
        #expect(near(2.4, doubled.amount, 1e-9))
        #expect(near(0.3, doubled.glowRadiusEm, 1e-9))
    }

    @Test func lettersStartOneAfterAnother() {
        let two = emphasisFor(2.0, glyphs: 4, last: false, emphasis: 1.0, glow: 1.0)!
        let starts = (0..<4).map { glyphStart(10.0, emphasis: two, i: $0) }
        #expect([10.0, 10.2, 10.4, 10.6] == starts.map { Double(roundToLong($0 * 1000)) / 1000.0 })
    }

    @Test func aLetterPeaksMidwayThenSettlesBack() {
        let bloom = emphasisFor(2.0, glyphs: 4, last: false, emphasis: 1.0, glow: 1.0)!
        let start = glyphStart(10.0, emphasis: bloom, i: 1)
        #expect(glyphPose(start - 0.01, wordStart: 10.0, emphasis: bloom, i: 1, glyphs: 4) == RestingGlyph)
        let peak = glyphPose(start + bloom.run / 2, wordStart: 10.0, emphasis: bloom, i: 1, glyphs: 4)
        #expect(near(1 + 0.1 * bloom.amount, peak.scale, 1e-9))
        #expect(near(-0.03 * bloom.amount * (4 / 2.0 - 1), peak.dxEm, 1e-9))
        #expect(near(-0.025 * bloom.amount, peak.dyEm, 1e-9))
        #expect(near(bloom.glow, peak.glowAlpha, 1e-9))
        #expect(glyphPose(start + bloom.run, wordStart: 10.0, emphasis: bloom, i: 1, glyphs: 4) == RestingGlyph)
    }

    @Test func theSwellCurveRisesThenFalls() {
        #expect(near(0.0, upAndBack(0.0), 0.0))
        #expect(near(1.0, upAndBack(0.5), 1e-9))
        #expect(near(0.0, upAndBack(1.0), 0.0))
        #expect((0.0...1.0).contains(upAndBack(0.25)))
        #expect((0.0...1.0).contains(upAndBack(0.75)))
        // A straight bezier is a straight line.
        #expect(near(0.3, CubicBezier(0.0, 0.0, 1.0, 1.0).at(0.3), 1e-6))
        // Ease-out is ahead of a straight line at the start.
        #expect(EaseOut.at(0.3) > 0.3)
    }

    @Test func theBobStartsEarlyAndRunsLonger() {
        let bloom = emphasisFor(2.0, glyphs: 4, last: false, emphasis: 1.0, glow: 1.0)!
        // 0.4 s before the first letter, it has just begun.
        #expect(near(0.0, bobEm(9.6, wordStart: 10.0, emphasis: bloom, i: 0, lift: 1.0, background: false), 1e-12))
        // At the middle of its 1.4 run lengths, it is at its highest.
        let middle = 9.6 + 1.4 * bloom.run / 2
        #expect(near(-0.05, bobEm(middle, wordStart: 10.0, emphasis: bloom, i: 0, lift: 1.0, background: false), 1e-9))
        #expect(near(-0.10, bobEm(middle, wordStart: 10.0, emphasis: bloom, i: 0, lift: 1.0, background: true), 1e-9))
    }

    // MARK: - Interlude dots, over a 10 s gap

    private func breathe(_ p: Double, _ f: Double) -> Double {
        let period = f / ceil(f / 1.5)
        return sin(1.5 * Double.pi - 2 * p / period) / 20 + 1
    }

    @Test func dotsGrowInUnseenThenFadeIn() {
        let early = dotsPose(0.25, f: 10.0, grown: false)
        #expect(near(0.0, early.opacity, 0.0))
        #expect(near(breathe(0.25, 10.0) * easeOutExpo(0.125) * 0.7, early.scale, 1e-9))
        let fading = dotsPose(0.75, f: 10.0, grown: false)
        #expect(near(0.5, fading.opacity, 1e-9))
        #expect(near(breathe(0.75, 10.0) * easeOutExpo(0.375) * 0.7, fading.scale, 1e-9))
    }

    @Test func dotsBreatheInTheMiddle() {
        let middle = dotsPose(5.0, f: 10.0, grown: false)
        #expect(near(1.0, middle.opacity, 0.0))
        #expect(near(breathe(5.0, 10.0) * 0.7, middle.scale, 1e-9))
        #expect((0.7 * 0.95...0.7 * 1.05).contains(middle.scale))
    }

    @Test func dotsInhaleThenPopAwayBeforeTheNextLine() {
        let closing = dotsPose(9.5, f: 10.0, grown: false)
        #expect(near(1.0, closing.opacity, 0.0))
        #expect(near(breathe(9.5, 10.0) * (1 - easeInOutBack(0.25 / 0.75 / 2)) * 0.7, closing.scale, 1e-9))
        // The little inhale: a touch bigger just as the exit starts.
        #expect(closing.scale > breathe(9.5, 10.0) * 0.7)
        let going = dotsPose(9.8, f: 10.0, grown: false)
        #expect(near(0.2 / 0.375, going.opacity, 1e-9))
        #expect(near(0.0, dotsPose(10.0, f: 10.0, grown: false).opacity, 0.0))
    }

    @Test func dotsLightOneTwoThree() {
        let u = 10.0 - 0.75
        func lights(_ p: Double) -> [Double] { dotsPose(p, f: 10.0, grown: false).lights }
        // At the start all three are at their floor.
        #expect(near([0.25, 0.25, 0.25], lights(0.5), 0.0))
        // A third of the way: the first well lit, the second just starting.
        let third = lights(u / 3 + 0.5)
        #expect(third[0] > third[1])
        #expect(third[1] >= third[2])
        #expect(near(1.0, lights(u)[0], 0.0))
        #expect(near(1.0, lights(u)[1], 0.0))
        #expect(near(0.75, lights(u)[2], 1e-9))
        // Each is its own formula.
        let p = 6.0
        for k in 0...2 {
            #expect(near(((p - Double(k) * u / 3) * 3 / u * 0.75).clamped(0.25, 1.0), lights(p)[k], 1e-12))
        }
    }

    @Test func aSeekIntoTheGapShowsTheDotsAlreadyGrown() {
        let grown = dotsPose(0.25, f: 10.0, grown: true)
        #expect(near(1.0, grown.opacity, 0.0))
        #expect(near(breathe(0.25, 10.0) * 0.7, grown.scale, 1e-9))
        #expect(near(1.0, interludeOpen(0.1, f: 10.0, grown: true), 0.0))
    }

    @Test func theGapOpensAndClosesItsSpace() {
        #expect(near(easeOutExpo(0.4 / 0.8), interludeOpen(0.4, f: 10.0, grown: false), 1e-12))
        #expect(near(1.0, interludeOpen(5.0, f: 10.0, grown: false), 1e-3))
        #expect(near(easeOutExpo(0.3 / 0.6), interludeOpen(9.7, f: 10.0, grown: false), 1e-12))
        #expect(near(0.0, interludeOpen(10.0, f: 10.0, grown: false), 0.0))
    }

    @Test func reducedMotionDotsHoldStill() {
        #expect(near(0.7, StillDots.scale, 0.0))
        #expect(near([0.85, 0.85, 0.85], StillDots.lights, 0.0))
    }

    // MARK: - Curved lyrics

    @Test func theFocusSitsForwardAndFlat() {
        let pose = arcPose(centre: FOCUS_AT * 1000, viewHeight: 1000.0, side: 1)
        #expect(near(0.0, pose.translationX, 1e-12))
        #expect(near(40.0, pose.z, 1e-12))
        #expect(near(0.0, pose.rotationY, 1e-12))
        #expect(near(1400.0 / 1360.0, pose.scale, 1e-12))
    }

    @Test func linesAwayFromTheFocusCurveInward() {
        let radius = 0.55 * 1000
        let half = arcPose(centre: FOCUS_AT * 1000 + radius / 2, viewHeight: 1000.0, side: 1)
        // r = 0.5, a = 0.75.
        #expect(near(60 * 0.25, half.translationX, 1e-9))
        #expect(near(40 * 0.75, half.z, 1e-9))
        #expect(near(0.09 * 0.5 * 0.75, half.rotationY, 1e-12))
        #expect(near(1400.0 / (1400 - 30), half.scale, 1e-12))
        // Right-aligned lines curve the other way.
        let right = arcPose(centre: FOCUS_AT * 1000 + radius / 2, viewHeight: 1000.0, side: -1)
        #expect(near(-half.translationX, right.translationX, 1e-12))
        #expect(near(-half.rotationY, right.rotationY, 1e-12))
        // Far off, flat against the drum's edge.
        let far = arcPose(centre: FOCUS_AT * 1000 + 3 * radius, viewHeight: 1000.0, side: 1)
        #expect(near(60.0, far.translationX, 1e-9))
        #expect(near(0.0, far.z, 1e-12))
        #expect(near(1.0, far.scale, 1e-12))
    }
}
