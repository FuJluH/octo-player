import Foundation
import Testing
@testable import OctoKit

@Suite struct LyricClockTest {
    private let frame = 1_000_000_000 / 60

    @Test func projectsSmoothlyBetweenCoarseReportsAtThePlaybackSpeed() {
        let clock = LyricClock()
        // The player reports only every third frame, at 1.5x.
        var reported = 10.0
        for n in 0...60 {
            let elapsed = Double(n) / 60.0
            if n % 3 == 0 { reported = 10.0 + 1.5 * elapsed }
            let time = clock.frame(n * frame, reported, rate: 1.5, playing: true)
            #expect(near(10.0 + 1.5 * elapsed, time, 1e-6))
            #expect(!clock.seeked)
        }
    }

    @Test func snapsToThePlayerOnlyWhenItDriftsMoreThanAFewFrames() {
        let clock = LyricClock()
        clock.frame(0, 10.0, rate: 1.0, playing: true)
        // 0.1 s off: the projection stands.
        let kept = clock.frame(frame, 10.0 + 1.0 / 60 + 0.1, rate: 1.0, playing: true)
        #expect(near(10.0 + 1.0 / 60, kept, 1e-9))
        // 0.2 s off: the player wins, and that is not a seek.
        let snapped = clock.frame(2 * frame, 10.0 + 2.0 / 60 + 0.2, rate: 1.0, playing: true)
        #expect(near(10.0 + 2.0 / 60 + 0.2, snapped, 1e-9))
        #expect(!clock.seeked)
    }

    @Test func aJumpOfMoreThanSixTenthsIsASeek() {
        let clock = LyricClock()
        clock.frame(0, 10.0, rate: 1.0, playing: true)
        clock.frame(frame, 10.5 + 1.0 / 60, rate: 1.0, playing: true)
        #expect(!clock.seeked)
        clock.frame(2 * frame, 11.2 + 2.0 / 60, rate: 1.0, playing: true)
        #expect(clock.seeked)
        clock.frame(3 * frame, 11.2 + 3.0 / 60, rate: 1.0, playing: true)
        #expect(!clock.seeked)
    }

    @Test func sixStillFramesMeanPausedWhateverThePlayerSays() {
        let clock = LyricClock()
        clock.frame(0, 20.0, rate: 1.0, playing: true)
        // Five frames standing still: still projecting.
        for n in 1...5 { #expect(clock.frame(n * frame, 20.0, rate: 1.0, playing: true) > 20.0) }
        // The sixth: paused, on the player's own position.
        #expect(near(20.0, clock.frame(6 * frame, 20.0, rate: 1.0, playing: true), 0.0))
    }

    @Test func pausedShowsThePlayersPositionLessTheLatency() {
        let clock = LyricClock(latency: 0.05)
        #expect(near(30.0 - 0.05, clock.frame(0, 30.0, rate: 1.0, playing: false), 1e-12))
        #expect(near(30.0 - 0.05, clock.frame(frame * 30, 30.0, rate: 1.0, playing: false), 1e-12))
    }

    @Test func aTapShowsItsTargetUntilThePlayerGetsThere() {
        let clock = LyricClock()
        clock.frame(0, 10.0, rate: 1.0, playing: true)
        clock.holdSeek(40.0, nowNanos: 0)
        // The player has not moved yet: the target shows, as a seek.
        #expect(near(40.0, clock.frame(frame, 10.0 + 1.0 / 60, rate: 1.0, playing: true), 0.0))
        #expect(clock.seeked)
        #expect(near(40.0, clock.frame(2 * frame, 10.0 + 2.0 / 60, rate: 1.0, playing: true), 0.0))
        // Within half a second of it: the player takes over.
        let close = clock.frame(3 * frame, 39.7, rate: 1.0, playing: true)
        #expect(near(39.7, close, 1e-9))
        #expect(!clock.seeked)
    }

    @Test func aTapsHoldGivesUpAfterTwoAndAHalfSeconds() {
        let clock = LyricClock()
        clock.frame(0, 10.0, rate: 1.0, playing: false)
        clock.holdSeek(40.0, nowNanos: 0)
        #expect(near(40.0, clock.frame(2_400_000_000, 10.0, rate: 1.0, playing: false), 0.0))
        #expect(near(10.0, clock.frame(2_600_000_000, 10.0, rate: 1.0, playing: false), 0.0))
    }

    @Test func theStepGivenToTheSpringsIsKeptSmall() {
        let clock = LyricClock()
        clock.frame(0, 10.0, rate: 1.0, playing: true)
        clock.frame(frame, 10.0, rate: 1.0, playing: true)
        #expect(near(1.0 / 60, clock.step, 1e-6))
        clock.frame(frame + 200_000_000, 10.2, rate: 1.0, playing: true)
        #expect(near(MAX_FRAME_STEP_S, clock.step, 0.0))
    }

    @Test func startingOverIsNotASeek() {
        let clock = LyricClock()
        clock.frame(0, 10.0, rate: 1.0, playing: true)
        clock.reset()
        clock.frame(frame, 90.0, rate: 1.0, playing: true)
        #expect(!clock.seeked)
        #expect(near(0.0, clock.step, 0.0))
    }
}
