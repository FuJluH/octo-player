import Foundation
import Testing
@testable import OctoKit

// Ten lines, one every two seconds, each sung for the whole two.
private func timedEngine() -> LyricEngine {
    let lines = (0..<10).map { i in
        SyncLine(
            index: i,
            text: "line \(i)",
            words: [SyncWord(text: "line", start: Double(i) * 2.0, end: Double(i) * 2.0 + 2, trailingSpace: true)],
            start: Double(i) * 2.0,
            end: Double(i) * 2.0 + 2
        )
    }
    let engine = LyricEngine(lines)
    engine.setGeometry([Double](repeating: 80.0, count: 10), interludeIdle: 10.0, interludeFull: 60.0, height: 1000.0)
    return engine
}

private let frame = 1_000_000_000 / 60

/// The timing control moves the flowing lyrics while they play: each frame reads the offset
/// afresh, so a step lands on the next frame, with no restart, and a tap still plays from where
/// the line is heard.
@Suite struct LyricTimingLiveTest {
    @Test func aStepLandsOnTheNextFrameWithoutARestart() {
        let engine = timedEngine()
        var now = 0
        var position = 6_100
        engine.frame(now, position, playing: true, rate: 1.0, offsetMs: 0)
        #expect(engine.focus == 3)

        // Fifteen steps earlier while it plays: the words run 0.75 s sooner.
        let earlier = (1...15).reduce(0) { offset, _ in stepTiming(offset, -1) }
        #expect(earlier == -750)
        now += frame
        position += 1000 / 60
        engine.frame(now, position, playing: true, rate: 1.0, offsetMs: earlier)
        #expect(near(Double(6_116 + 750) / 1000.0, engine.lyricTime, 0.02))
        #expect(engine.focus == 3)

        // Moved 1.5 s the other way, the line before it is sung again.
        engine.frame(now + frame, position + 1000 / 60, playing: true, rate: 1.0, offsetMs: earlier + 1_500)
        #expect(engine.focus == 2)
    }

    @Test func resettingPutsTheWordsBackWhereTheyAreWritten() {
        let engine = timedEngine()
        engine.frame(0, 9_000, playing: true, rate: 1.0, offsetMs: 1_250)
        #expect(near(7.75, engine.lyricTime, 1e-9))
        engine.frame(frame, 9_000 + 1000 / 60, playing: true, rate: 1.0, offsetMs: 0)
        #expect(engine.focus == 4)
        #expect(near(9.0, engine.lyricTime, 0.02))
    }

    @Test func aTapPlaysFromWhereTheLineIsHeardAndLandsOnIt() {
        for offset in [0, 750, -1_000] {
            let engine = timedEngine()
            engine.frame(0, 1_000, playing: true, rate: 1.0, offsetMs: offset)
            // Tapping line 6, as the view does: it seeks to where it is heard.
            let target = heardAt(Int((engine.lines[6].start * 1000).rounded()), offset)
            #expect(target == 12_000 + offset)
            engine.tapped(6, playerTarget: Double(target) / 1000.0)
            engine.frame(frame, target, playing: true, rate: 1.0, offsetMs: offset)
            #expect(engine.focus == 6, "offset \(offset)")
        }
    }
}

/// The output's lyrics timing (the phone's speaker, a pair of earbuds) runs in the clock as its
/// latency, on top of the song's own timing: the words follow the song less both, a tap plays
/// from the line plus both, and a new output moves the words without a jump.
@Suite struct OutputTimingTest {
    /// One tap on the output's Earlier button.
    private func earlier(_ outputMs: Int) -> Int { stepTiming(outputMs, -1, limitMs: LyricsOutputTiming.limitMs) }

    @Test func earlierShowsTheWordsSoonerByExactlyOneStep() {
        // The words are behind the voice, so Earlier is tapped once.
        let before = timedEngine()
        let after = timedEngine()
        before.frame(0, 6_100, playing: true, rate: 1.0, offsetMs: 0, outputOffsetMs: 0)
        after.frame(0, 6_100, playing: true, rate: 1.0, offsetMs: 0, outputOffsetMs: earlier(0))
        #expect(earlier(0) == -50)
        // At the same point in the song the lyrics are a step further on, so every word lights
        // up a step sooner.
        #expect(near(0.05, after.lyricTime - before.lyricTime, 1e-9))

        // A word written at 8.0 s lights at 7.95 s of the song, not 8.0 s.
        let word = 8.0
        let lit = timedEngine()
        lit.frame(0, 7_950, playing: true, rate: 1.0, offsetMs: 0, outputOffsetMs: earlier(0))
        #expect(near(word, lit.lyricTime, 1e-9))
        #expect(lit.focus == 4)
    }

    @Test func theSongsAndTheOutputsTimingAddUp() {
        let engine = timedEngine()
        // The song's words run 0.25 s late and the earbuds' 0.1 s early.
        engine.frame(0, 10_000, playing: false, rate: 1.0, offsetMs: 250, outputOffsetMs: -100)
        #expect(near(10.0 - 0.25 + 0.1, engine.lyricTime, 1e-9))
    }

    @Test func earlierWhilePlayingMovesTheWordsOnTheNextFrameWithoutASeek() {
        let engine = timedEngine()
        engine.frame(0, 6_100, playing: true, rate: 1.0, offsetMs: 0, outputOffsetMs: 0)
        let before = engine.lyricTime
        engine.frame(frame, 6_100 + 1000 / 60, playing: true, rate: 1.0, offsetMs: 0, outputOffsetMs: earlier(0))
        #expect(near(before + 1.0 / 60 + 0.05, engine.lyricTime, 0.002))
        #expect(!engine.clock.seeked)
    }

    @Test func aTapPlaysFromWhereTheLineIsHeardOnThisOutputAndLandsOnIt() {
        for song in [0, 750, -1_000] {
            for output in [0, -150, 200] {
                let engine = timedEngine()
                engine.frame(0, 1_000, playing: true, rate: 1.0, offsetMs: song, outputOffsetMs: output)
                // Tapping line 6, as the view does: it seeks to where the line is heard with
                // both timings.
                let total = totalOffset(songMs: song, outputMs: output)
                let target = heardAt(Int((engine.lines[6].start * 1000).rounded()), total)
                #expect(target == 12_000 + song + output)
                engine.tapped(6, playerTarget: Double(target) / 1000.0)

                // The player has not got there yet: the line shows at its start.
                engine.frame(frame, 1_000 + 1000 / 60, playing: true, rate: 1.0, offsetMs: song, outputOffsetMs: output)
                #expect(near(12.0, engine.lyricTime, 1e-9), "song \(song) output \(output)")
                #expect(engine.focus == 6)

                // It gets there: still the line's start, with no step.
                engine.frame(2 * frame, target, playing: true, rate: 1.0, offsetMs: song, outputOffsetMs: output)
                #expect(near(12.0, engine.lyricTime, 1e-9), "song \(song) output \(output)")
                #expect(engine.focus == 6)
                #expect(!engine.clock.seeked)
            }
        }
    }

    @Test func aNewOutputTakesAFreshAnchorAndIsNotASeek() {
        let clock = LyricClock()
        for n in 0...10 {
            clock.frame(n * frame, 30.0 + Double(n) / 60.0, rate: 1.0, playing: true)
        }
        // Earbuds come in with their own timing, far enough to be a seek if it were one: the
        // time moves by it, from the player's own position.
        clock.setLatency(-0.8)
        let next = 30.0 + 11 / 60.0 + 0.004
        let time = clock.frame(11 * frame, next, rate: 1.0, playing: true)
        #expect(near(next + 0.8, time, 1e-9))
        #expect(!clock.seeked)
        // And it runs on from there.
        #expect(near(30.0 + 12 / 60.0 + 0.004 + 0.8, clock.frame(12 * frame, 30.0 + 12 / 60.0, rate: 1.0, playing: true), 1e-6))
        #expect(!clock.seeked)
        // The same timing again changes nothing.
        clock.setLatency(-0.8)
        #expect(near(30.0 + 13 / 60.0 + 0.004 + 0.8, clock.frame(13 * frame, 30.0 + 13 / 60.0, rate: 1.0, playing: true), 1e-6))
    }

    @Test func aNewOutputMovesTheLinesInsteadOfJumpingThem() {
        let engine = timedEngine()
        // Two seconds of playing from 7.5 s, into line 4.
        for n in 0..<120 {
            engine.frame(n * frame, 7_500 + n * 1000 / 60, playing: true, rate: 1.0, offsetMs: 0, outputOffsetMs: 0)
        }
        #expect(engine.focus == 4)
        #expect(engine.states.allSatisfy { $0.y.atRest && !$0.y.hasQueued })
        // Earbuds whose words run a second earlier: line 5 is the one sung now, and the lines
        // ripple over to it instead of jumping.
        engine.frame(120 * frame, 7_500 + 2_000, playing: true, rate: 1.0, offsetMs: 0, outputOffsetMs: -1_000)
        #expect(engine.focus == 5)
        #expect(!engine.clock.seeked)
        #expect(engine.states.contains { !$0.y.atRest || $0.y.hasQueued })
        // A seek, for comparison, is taken as one.
        let sought = timedEngine()
        sought.frame(0, 7_500, playing: true, rate: 1.0, offsetMs: 0, outputOffsetMs: 0)
        sought.frame(frame, 10_500, playing: true, rate: 1.0, offsetMs: 0, outputOffsetMs: 0)
        #expect(sought.clock.seeked)
    }
}
