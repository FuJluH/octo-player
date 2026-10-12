import Foundation
import Testing
@testable import OctoKit

@Suite struct SpringTest {
    // Runs a spring for `seconds` in steps of `hz` a second.
    private func run(_ spring: Spring, _ seconds: Double, _ hz: Int) {
        let steps = roundToLong(seconds * Double(hz))
        for _ in 0..<steps { spring.update(1.0 / Double(hz)) }
    }

    @Test func underDampedSwingsPastItsTargetAndMatchesTheClosedForm() {
        let spring = Spring(1.0, 100.0, 10.0)
        spring.setTarget(1.0)
        #expect(near(0.5, spring.dampingRatio, 1e-12))
        spring.update(0.2)
        // From 1 away at rest: x = e^(-zeta w t) (cos(wd t) + zeta w / wd sin(wd t)).
        let w = 10.0
        let zeta = 0.5
        let wd = w * (1 - zeta * zeta).squareRoot()
        let expected = 1 - exp(-zeta * w * 0.2) * (cos(wd * 0.2) + zeta * w / wd * sin(wd * 0.2))
        #expect(near(expected, spring.value(), 1e-9))
        // It goes past the target at some point.
        var most = 0.0
        for _ in 0..<120 {
            spring.update(1.0 / 120)
            most = max(most, spring.value())
        }
        #expect(most > 1.0)
    }

    @Test func criticallyDampedCreepsInWithoutPassingTheTarget() {
        let spring = Spring(1.0, 100.0, 20.0)
        #expect(near(1.0, spring.dampingRatio, 1e-12))
        spring.setTarget(1.0)
        spring.update(0.1)
        #expect(near(1 - exp(-1.0) * (1 + 1.0), spring.value(), 1e-9))
        for _ in 0..<240 {
            spring.update(1.0 / 120)
            #expect(spring.value() <= 1.0 + 1e-12)
        }
    }

    @Test func overDampedNeverPassesTheTarget() {
        let spring = Spring(1.0, 100.0, 40.0)
        #expect(spring.dampingRatio > 1)
        spring.setTarget(1.0)
        var last = 0.0
        for _ in 0..<600 {
            spring.update(1.0 / 120)
            #expect(spring.value() >= last - 1e-12)
            #expect(spring.value() <= 1.0 + 1e-12)
            last = spring.value()
        }
    }

    @Test func comesToRestExactlyOnItsTarget() {
        let spring = linePositionSpring()
        spring.setTarget(300.0)
        #expect(!spring.atRest)
        run(spring, 3.0, 60)
        #expect(spring.atRest)
        #expect(near(300.0, spring.value(), 0.0))
        #expect(near(0.0, spring.velocity(), 0.0))
    }

    @Test func aRestingSpringCountsAsStillWhenCloseAndSlow() {
        let spring = Spring(1.0, 200.0, 28.0, initial: 100.0)
        // Already within 0.01 and still: at rest straight away.
        spring.setTarget(100.005)
        #expect(spring.atRest)
        // Further than 0.01: moving.
        spring.setTarget(100.5)
        #expect(!spring.atRest)
    }

    @Test func landsTheSameAt60And120FramesASecond() {
        let sixty = linePositionSpring()
        let oneTwenty = linePositionSpring()
        for (spring, hz) in [(sixty, 60), (oneTwenty, 120)] {
            spring.setTarget(500.0)
            run(spring, 0.25, hz)
            // A change of course halfway, while it is moving fast.
            spring.setTarget(-200.0)
            run(spring, 0.25, hz)
        }
        #expect(near(sixty.value(), oneTwenty.value(), 1e-6))
        #expect(near(sixty.velocity(), oneTwenty.velocity(), 1e-4))
    }

    @Test func aWaitingTargetTakesOverAtTheSameMomentAtAnyFrameRate() {
        let sixty = linePositionSpring()
        let oneTwenty = linePositionSpring()
        for (spring, hz) in [(sixty, 60), (oneTwenty, 120)] {
            // A wait that falls between frames at 60 a second.
            spring.setTarget(100.0, delay: 0.123)
            run(spring, 0.1, hz)
            #expect(near(0.0, spring.value(), 0.0))
            #expect(spring.hasQueued)
            run(spring, 0.4, hz)
        }
        #expect(!sixty.hasQueued)
        #expect(near(sixty.value(), oneTwenty.value(), 1e-6))
    }

    @Test func movingAWaitingTargetKeepsItsWait() {
        let spring = linePositionSpring()
        spring.setTarget(100.0, delay: 0.1)
        spring.update(0.05)
        spring.moveTarget(150.0)
        spring.update(0.04)
        #expect(near(0.0, spring.value(), 0.0))
        spring.update(0.02)
        #expect(near(150.0, spring.target, 0.0))
    }

    @Test func speedKeepsTheDampingRatioSoFasterIsNotBouncier() {
        let normal = linePositionSpring()
        let fast = linePositionSpring()
        fast.speed = 2.0
        let slow = linePositionSpring()
        slow.speed = 0.5
        #expect(near(normal.dampingRatio, fast.dampingRatio, 1e-12))
        #expect(near(normal.dampingRatio, slow.dampingRatio, 1e-12))
        // Twice the speed covers in t what normal covers in 2t.
        normal.setTarget(100.0)
        fast.setTarget(100.0)
        normal.update(0.2)
        fast.update(0.1)
        #expect(near(normal.value(), fast.value(), 1e-9))
    }

    @Test func theLyricsSpringsAreJustUnderCriticalDamping() {
        #expect(near(28 / (2 * (200.0).squareRoot()), linePositionSpring().dampingRatio, 1e-12))
        #expect(near(32 / (2 * (260.0).squareRoot()), lineScaleSpring().dampingRatio, 1e-12))
        #expect(near(28 / (2 * (240.0).squareRoot()), scrollOffsetSpring().dampingRatio, 1e-12))
    }

    @Test func aJumpPutsItStraightThere() {
        let spring = linePositionSpring()
        spring.setTarget(100.0, delay: 1.0)
        spring.jump(40.0)
        #expect(spring.atRest)
        #expect(!spring.hasQueued)
        #expect(near(40.0, spring.value(), 0.0))
    }
}
