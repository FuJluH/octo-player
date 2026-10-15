import Foundation
import Testing
@testable import OctoKit

@Suite struct LyricEngineTest {
    private let frame = 1_000_000_000 / 60
    private let view = 1000.0
    private let lineHeight = 80.0

    // Ten lines, one every two seconds, each sung for the whole two.
    private func engine() -> LyricEngine {
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
        engine.setGeometry([Double](repeating: lineHeight, count: 10), interludeIdle: 10.0, interludeFull: 60.0, height: view)
        return engine
    }

    private func centre(_ engine: LyricEngine, _ i: Int) -> Double { engine.states[i].y.value() + engine.states[i].height / 2 }

    @Test func theFirstFramePutsTheFocusAtItsAnchorInOneJump() {
        let engine = engine()
        engine.frame(0, 4_500, playing: true, rate: 1.0, offsetMs: 0)
        #expect(engine.focus == 2)
        #expect(near(FOCUS_AT * view, centre(engine, 2), 1e-9))
        #expect(engine.states.allSatisfy { $0.y.atRest })
        #expect(engine.states[2].status == .active)
        #expect(engine.states[1].status == .passed)
        #expect(engine.states[3].status == .upcoming)
        #expect(near(1.0, engine.states[2].opacity, 0.0))
        // Sung lines stay visible by default.
        #expect(near(PASSED_SHOWN_OPACITY, engine.states[1].opacity, 0.0))
        #expect(near(0.55, engine.states[3].opacity, 0.0))
    }

    @Test func aNewLineRipplesTheLinesBelowItInTurn() {
        let engine = engine()
        var now = 0
        var position = 3_900
        engine.frame(now, position, playing: true, rate: 1.0, offsetMs: 0)
        // Play on into line 2.
        for _ in 0..<12 {
            now += frame
            position += 1000 / 60
            engine.frame(now, position, playing: true, rate: 1.0, offsetMs: 0)
        }
        #expect(engine.focus == 2)
        // The top line on screen has started; three lines below the focus still waits.
        #expect(!engine.states[0].y.hasQueued)
        #expect(engine.states[5].y.hasQueued)
        // Half a second on, everything is under way.
        for _ in 0..<30 {
            now += frame
            position += 1000 / 60
            engine.frame(now, position, playing: true, rate: 1.0, offsetMs: 0)
        }
        #expect(!engine.states.contains { $0.y.hasQueued })
    }

    @Test func aSeekLandsInOneJumpWithNoRipple() {
        let engine = engine()
        engine.frame(0, 1_000, playing: true, rate: 1.0, offsetMs: 0)
        engine.frame(frame, 13_000, playing: true, rate: 1.0, offsetMs: 0)
        #expect(engine.focus == 6)
        #expect(near(FOCUS_AT * view, centre(engine, 6), 1e-9))
        #expect(engine.states.allSatisfy { $0.y.atRest && !$0.y.hasQueued })
    }

    @Test func theTimingOffsetMovesTheLyricsClock() {
        let engine = engine()
        // Heard half a second later than written: at 4.2 s the lyrics are at 3.7 s.
        engine.frame(0, 4_200, playing: true, rate: 1.0, offsetMs: 500)
        #expect(near(3.7, engine.lyricTime, 1e-9))
        #expect(engine.focus == 1)
    }

    @Test func reducedMotionJumpsEveryLine() {
        let engine = engine()
        engine.reduceMotion = true
        engine.frame(0, 3_900, playing: true, rate: 1.0, offsetMs: 0)
        engine.frame(frame * 10, 4_100, playing: true, rate: 1.0, offsetMs: 0)
        #expect(engine.states.allSatisfy { $0.y.atRest && !$0.y.hasQueued })
        #expect(near(FOCUS_AT * view, centre(engine, 2), 1e-9))
    }

    @Test func keptLinesStayFaintlyVisible() {
        let engine = engine()
        engine.look = LyricsLook(keepCompleted: true)
        engine.frame(0, 4_500, playing: true, rate: 1.0, offsetMs: 0)
        #expect(near(PASSED_SHOWN_OPACITY, engine.states[1].opacity, 0.0))
    }

    @Test func wordAnimationIsPreparedNearTheFocusOnly() {
        let engine = engine()
        var prepared: [Int] = []
        engine.frame(0, 8_500, playing: true, rate: 1.0, offsetMs: 0, prepare: { prepared.append($0) })
        // Focus 4: itself, then ahead, then behind.
        #expect(prepared == [4, 5, 6, 7, 8, 9, 3, 2, 1, 0])
    }

    @Test func aScrollHoldsTheFocusThenFollowsAgain() {
        let engine = engine()
        // The player's position `nanos` into the test, from 4.5 s.
        func at(_ nanos: Int) -> Int { 4_500 + nanos / 1_000_000 }
        engine.frame(0, at(0), playing: true, rate: 1.0, offsetMs: 0)
        engine.dragStart()
        engine.dragBy(-150.0)
        engine.dragEnd()
        #expect(engine.scrolling)
        // Every frame from `from` to `to`, playing on.
        func play(_ from: Int, _ to: Int) {
            for n in from...to { engine.frame(frame * n, at(frame * n), playing: true, rate: 1.0, offsetMs: 0) }
        }
        // The song moves on into line 3, but the lines hold where the finger left them.
        play(1, 96)
        #expect(engine.focus == 2)
        #expect(engine.states[3].status == .active)
        // Passed lines show while scrolling.
        #expect(engine.states[1].opacity > 0.0)
        // Two seconds after the finger lifted, the lyrics follow the song again.
        play(97, 126)
        #expect(!engine.scrolling)
        #expect(engine.focus == 3)
    }

    @Test func aScrollStopsBeforeTheFirstLinePassesThirtyPercent() {
        let engine = engine()
        engine.frame(0, 500, playing: true, rate: 1.0, offsetMs: 0)
        engine.dragStart()
        engine.dragBy(10_000.0)
        for it in 0..<120 { engine.frame(frame * (it + 1), 500 + it * 16, playing: true, rate: 1.0, offsetMs: 0) }
        #expect(near(0.3 * view, engine.states[0].y.value() + engine.scrollOffset, 1.0))
    }
}
