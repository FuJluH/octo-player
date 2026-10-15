import Foundation
import Testing
@testable import OctoKit

@Suite struct PlayerMotionTests {
    @Test func atRestNothingMoves() {
        let clock = PlayerMotionClock()
        #expect(!clock.moving(at: 0))
        #expect(!clock.moving(at: 1_000))
        #expect(clock.restsIn(at: 5) == 0)
    }

    @Test func openingMovesUntilItHasLanded() {
        var clock = PlayerMotionClock()
        clock.moved(at: 100, for: PlayerMotionClock.openSeconds)
        #expect(clock.moving(at: 100))
        #expect(clock.moving(at: 100 + PlayerMotionClock.openSeconds - 0.01))
        #expect(!clock.moving(at: 100 + PlayerMotionClock.openSeconds))
    }

    @Test func aShorterTransitionNeverCutsALongerOneShort() {
        var clock = PlayerMotionClock()
        clock.moved(at: 0, for: PlayerMotionClock.closeSeconds)
        clock.moved(at: 0.1, for: 0.2)
        #expect(clock.moving(at: PlayerMotionClock.closeSeconds - 0.01))
    }

    @Test func aFingerHoldsItMovingForAsLongAsItPulls() {
        var clock = PlayerMotionClock()
        clock.hold(true, at: 0)
        #expect(clock.moving(at: 600))
        #expect(clock.restsIn(at: 600) == nil)
        clock.hold(false, at: 600)
        // Springing back or away after letting go still moves.
        #expect(clock.moving(at: 600 + PlayerMotionClock.releaseSeconds / 2))
        #expect(!clock.moving(at: 600 + PlayerMotionClock.releaseSeconds))
    }

    @Test func aPullThatClosesMovesThroughTheWholeClose() {
        var clock = PlayerMotionClock()
        clock.hold(true, at: 0)
        clock.moved(at: 2, for: PlayerMotionClock.closeSeconds)
        clock.hold(false, at: 2)
        #expect(clock.moving(at: 2 + PlayerMotionClock.closeSeconds - 0.01))
        #expect(!clock.moving(at: 2 + PlayerMotionClock.closeSeconds))
    }

    @Test func theTransitionsOutlastTheirAnimations() {
        // The cover's flight is ended by force after 1.2 s; closing takes the player down after 0.7 s.
        #expect(PlayerMotionClock.closeSeconds >= 1.2)
        #expect(PlayerMotionClock.openSeconds >= 0.6)
    }

    @Test func slowerPacesHoldOnlyAtRest() {
        #expect(pacedInterval(0.11, moving: false) == 0.11)
        #expect(pacedInterval(0.11, moving: true) == nil)
        #expect(pacedInterval(nil, moving: false) == nil)
        #expect(abs(meshFrameStep(1, moving: false) - 1.0 / 30) < 1e-12)
        #expect(abs(meshFrameStep(0, moving: false) - 1.0 / 10) < 1e-12)
        #expect(meshFrameStep(0, moving: true) == 0)
        #expect(meshFrameStep(1, moving: true) == 0)
    }

    @Test func onceASecondStepsFromARecentWholeSecond() {
        let now = Date(timeIntervalSinceReferenceDate: 813_456_789.75)
        let start = wholeSecondAtOrBefore(now)
        #expect(start.timeIntervalSinceReferenceDate == 813_456_789)
        #expect(now.timeIntervalSince(start) < 1)
        #expect(wholeSecondAtOrBefore(start) == start)
    }
}
