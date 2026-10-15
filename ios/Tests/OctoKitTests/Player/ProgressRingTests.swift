import Foundation
import Testing
@testable import OctoKit

@Suite struct ProgressRingTests {
    @Test func aBreathIsSlowAndStaysBetweenFaintAndFull() {
        #expect(abs(pauseBreath(0) - 1) < 1e-9)
        #expect(abs(pauseBreath(RingLook.breathSeconds / 2)) < 1e-9)
        #expect(abs(pauseBreath(RingLook.breathSeconds) - 1) < 1e-9)
        for i in 0...200 { #expect((0...1).contains(pauseBreath(Double(i) * 0.05))) }
        #expect(RingLook.breathSeconds == 2.6)
    }

    @Test func thePauseRedrawsAtMostAboutTwelveTimesASecond() {
        #expect(RingLook.breathFrameSeconds >= 0.083)
        #expect(RingLook.stepSeconds == 1)
    }

    @Test func aBreathSettlesAfterAMinuteNearItsFaintest() {
        #expect(!breathSettles(10))
        #expect(!breathSettles(RingLook.breathLimitSeconds), "not mid-breath")
        var t = RingLook.breathLimitSeconds
        while !breathSettles(t) { t += RingLook.breathFrameSeconds }
        #expect(t < RingLook.breathLimitSeconds + RingLook.breathSeconds, "within one breath of the limit")
        #expect(pauseBreath(t) <= 0.2)
        // Known up front: within a frame of where looking every frame finds it.
        let known = breathSettleSeconds()
        #expect(breathSettles(known + 1e-9))
        #expect(known >= RingLook.breathLimitSeconds && known < RingLook.breathLimitSeconds + RingLook.breathSeconds)
        #expect(abs(known - t) <= RingLook.breathFrameSeconds + 1e-9)
        #expect(!breathSettles(known - 0.01))
    }

    @Test func theArcBreathesFromAThirdToFullAndTwoToThreePoints() {
        #expect(RingArc.of(paused: false, breath: 0.4) == RingArc(alpha: 1, width: 2))
        #expect(RingArc.of(paused: true, breath: 0) == RingArc(alpha: 0.35, width: 2))
        #expect(RingArc.of(paused: true, breath: 1) == RingArc(alpha: 1, width: 3))
        // Settled, or with motion reduced: still and dimmed.
        #expect(RingArc.of(paused: true, breath: nil) == RingArc(alpha: 0.45, width: 2))
        #expect(RingLook.pausedTrackAlpha > 0)
    }

    @Test func aStationIsTheWholeRing() {
        #expect(ringSweep(position: 10, length: 0, live: true) == 1)
        #expect(ringSweep(position: 50, length: 200, live: false) == 0.25)
        #expect(ringSweep(position: 500, length: 200, live: false) == 1)
        #expect(ringSweep(position: 5, length: 0, live: false) == 0)
    }

    @Test func aScreenReaderHearsHowMuchHasPlayed() {
        #expect(playedWords(playedSeconds: 65, lengthSeconds: 200, live: false) == "1:05 of 3:20 played")
        #expect(playedWords(playedSeconds: 900, lengthSeconds: 200, live: false) == "3:20 of 3:20 played")
        #expect(playedWords(playedSeconds: 65, lengthSeconds: 200, live: true) == "")
        #expect(playedWords(playedSeconds: 65, lengthSeconds: 0, live: false) == "")
    }

    @Test func theButtonSaysTheSongAndWhetherItPlays() {
        #expect(nowPlayingWords(title: "Nightcall", artist: "Kavinsky", loaded: true) == "Now playing: Nightcall, Kavinsky")
        #expect(nowPlayingWords(title: " ", artist: nil, loaded: true) == "Now playing")
        #expect(nowPlayingWords(title: nil, artist: nil, loaded: false) == "Shuffle your library")
        #expect(nowPlayingState(loaded: true, paused: false, live: false) == "Playing")
        #expect(nowPlayingState(loaded: true, paused: true, live: false) == "Paused")
        #expect(nowPlayingState(loaded: true, paused: true, live: true) == "Stopped")
        #expect(nowPlayingState(loaded: false, paused: true, live: false) == "")
    }

    @Test func theProgressLineStepsEachHalfPixelAtMostASecond() {
        // A 3:20 song on a 1,035 pixel line: about ten steps a second.
        #expect(abs(progressStepSeconds(200, lengthPixels: 1035) - 200.0 / 2070) < 1e-9)
        // A short song on a long line moves every frame.
        #expect(progressStepSeconds(10, lengthPixels: 1035) == 0)
        // A very long song steps at most once a second.
        #expect(progressStepSeconds(36_000, lengthPixels: 100) == 1)
        #expect(progressStepSeconds(0, lengthPixels: 100) == 0)
        #expect(progressStepSeconds(200, lengthPixels: 0) == 0)
    }
}

@Suite struct MeshPaceTests {
    @Test func theMeshTakesThirtyFramesAtFullSpeedAndNeverUnderTen() {
        #expect(meshFps(1) == 30)
        #expect(meshFps(0.5) == 15)
        #expect(meshFps(0.15) == 10)
        #expect(meshFps(0) == 10)
        #expect(meshFps(3) == 30)
    }
}
