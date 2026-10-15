import Foundation

/// Word animation is prepared for lines this close to the focus, and let go only once they are
/// further than the second pair, so lines near the edge do not flip back and forth.
public let PREPARE_BEHIND = 4
public let PREPARE_AHEAD = 10
public let RELEASE_BEHIND = 8
public let RELEASE_AHEAD = 14

/// Preparing word animation may take this long in one frame.
public let PREPARE_BUDGET_NANOS = 3_000_000

/// After a scroll by hand, the lyrics follow the song again this long after the finger lifts.
public let FOLLOW_AGAIN_NANOS = 2_000_000_000

/// A scroll stops with the first line no lower than this much of the view, and the last no higher
/// than this.
public let SCROLL_TOP_LIMIT = 0.3
public let SCROLL_BOTTOM_LIMIT = 0.7

/// A run of line numbers, first to last; empty when `first` is past `last`.
public struct LineRange: Equatable, Sendable {
    public var first: Int
    public var last: Int

    public init(first: Int, last: Int) {
        self.first = first
        self.last = last
    }

    public static let empty = LineRange(first: 1, last: 0)

    public var isEmpty: Bool { first > last }

    public func contains(_ index: Int) -> Bool { index >= first && index <= last }
}

/// The whole flowing view's motion, run once a frame from one loop: the clock, which lines are
/// being sung, where every line is headed, the ripple, the fades, the scroll by hand, and which
/// lines get their word animation ready. Drawing only reads what this leaves behind, through each
/// line's version counters, so a frame never rebuilds the view.
public final class LyricEngine {
    public let lines: [SyncLine]
    public let states: [LineState]
    public let clock = LyricClock()

    // Lines the focus can rest on: every line except backing vocals sung under the lead line just
    // above them.
    private let anchorable: [Bool]

    public var look = LyricsLook()
    public var reduceMotion = false

    // The lines' measured heights, and an interlude's closed and open height.
    private var baseHeights: [Double] = []
    private var idleHeight = 0.0
    private var fullHeight = 0.0
    public private(set) var viewHeight = 0.0

    public var ready: Bool { baseHeights.count == lines.count && viewHeight > 0 && !lines.isEmpty }

    /// Where the song is on the lyrics' clock, and the line in focus.
    public private(set) var lyricTime = 0.0
    public private(set) var focus = 0
    private var lastFocus = -1
    private var lastLyricTime = Double.nan
    private var needsJump = true
    private var appliedSpeed = 1.0
    private var lastNanos = 0

    // Scrolling by hand: an offset on its own spring, the focus held where it was when the finger
    // went down.
    private let scroll = scrollOffsetSpring()
    public var scrollOffset: Double { scroll.value() }
    public private(set) var scrolling = false
    private var dragging = false
    private var scrollFocus = 0
    private var followAt = 0

    // Worked out again each frame, kept to save making new ones.
    private var heights: [Double]
    private var above: [Double]
    private var targets: [Double]

    /// Nothing moved last frame and nothing is playing, so the loop may rest.
    public private(set) var settled = false

    /// Counts frames, for anything drawn from the engine as a whole.
    public private(set) var frames = 0

    /// The lines worth drawing: on screen or about to be, and the focus.
    public private(set) var shown = LineRange.empty

    public init(_ lines: [SyncLine]) {
        self.lines = lines
        states = lines.map(LineState.init)
        anchorable = lines.indices.map { i in
            let line = lines[i]
            let above: SyncLine? = i > 0 ? lines[i - 1] : nil
            guard let above else { return true }
            return !(line.isBackground && !above.isBackground && !above.isInterlude && line.start < above.end)
        }
        heights = [Double](repeating: 0.0, count: lines.count)
        above = [Double](repeating: 0.0, count: lines.count + 1)
        targets = [Double](repeating: 0.0, count: lines.count)
    }

    /// New sizes: after the first, lines jump to their new places.
    public func setGeometry(_ lineHeights: [Double], interludeIdle: Double, interludeFull: Double, height: Double) {
        baseHeights = lineHeights
        idleHeight = interludeIdle
        fullHeight = interludeFull
        viewHeight = height
        for state in states { state.live = false }
        needsJump = true
    }

    /// The view is showing again: start the clock fresh and put everything straight in place.
    public func restart() {
        clock.reset()
        needsJump = true
    }

    /// The line in focus at `t`: the last one begun, not counting backing vocals under a lead
    /// line. Before any has begun, the first.
    public func focusAt(_ t: Double) -> Int {
        var found = -1
        var first = -1
        for i in lines.indices {
            if !anchorable[i] { continue }
            if first < 0 { first = i }
            if lines[i].start <= t { found = i }
        }
        return found >= 0 ? found : max(first, 0)
    }

    /// One frame. `offsetMs` is the song's lyrics timing and `outputOffsetMs` the output's, which
    /// the clock takes as its latency. `prepare` readies a line's word animation and `release`
    /// lets it go; both come from the view, which holds the text.
    public func frame(
        _ nanos: Int,
        _ reportedMs: Int,
        playing: Bool,
        rate: Double,
        offsetMs: Int,
        outputOffsetMs: Int = 0,
        prepare: (Int) -> Void = { _ in },
        release: (Int) -> Void = { _ in }
    ) {
        if !ready { return }
        lastNanos = nanos
        clock.setLatency(Double(outputOffsetMs) / 1000.0)
        let playerTime = clock.frame(nanos, Double(reportedMs) / 1000.0, rate: rate, playing: playing)
        let dt = clock.step
        let t = playerTime - Double(offsetMs) / 1000.0
        lyricTime = t
        let seeked = clock.seeked
        // Places are set outright on the first frame, after a seek or a resize; with reduced
        // motion, always.
        let snap = needsJump || seeked
        let jump = snap || reduceMotion
        needsJump = false
        if seeked && scrolling { endScroll(immediately: true) }

        let speed = look.fraction(.speed)
        if speed != appliedSpeed {
            appliedSpeed = speed
            for state in states {
                state.y.speed = speed
                state.grown.speed = speed
            }
            scroll.speed = speed
        }
        if scrolling && !dragging && nanos >= followAt { endScroll(immediately: false) }

        // Who is singing, and how tall each line is now.
        for i in lines.indices {
            let st = states[i]
            let line = lines[i]
            if t < line.start {
                st.status = .upcoming
            } else if t < line.end {
                st.status = .active
            } else {
                st.status = .passed
            }
            if line.isInterlude {
                if st.status != .active {
                    st.grownIn = false
                } else if snap {
                    st.grownIn = true
                }
                let open: Double
                if st.status != .active {
                    open = 0.0
                } else if reduceMotion {
                    open = 1.0
                } else {
                    open = interludeOpen(t - line.start, f: line.end - line.start, grown: st.grownIn)
                }
                st.height = idleHeight + (fullHeight - idleHeight) * open
            } else {
                st.height = baseHeights[i]
            }
            heights[i] = st.height
        }

        let a = scrolling ? scrollFocus : focusAt(t)
        focus = a
        for i in lines.indices { above[i + 1] = above[i] + heights[i] }
        for i in lines.indices { targets[i] = targetY(i, a: a, above: above, heights: heights, viewHeight: viewHeight) }
        let ripple = a != lastFocus && lastFocus >= 0 && !jump && !scrolling && look.cascade > 0
        let delays = ripple ? cascadeDelays(targets, focus: a, viewHeight: viewHeight, stepScale: look.fraction(.cascade)) : nil
        lastFocus = a

        let scrollBefore = scroll.value()
        scroll.update(dt)
        let offset = scroll.value()
        let scrollMoved = offset != scrollBefore

        let showPassed = look.keepCompleted || scrolling
        let timeMoved = t != lastLyricTime
        lastLyricTime = t
        var anythingMoved = scrollMoved

        for i in lines.indices {
            let st = states[i]
            let line = lines[i]
            let yBefore = st.y.value()
            let grownBefore = st.grown.value()
            let opacityBefore = st.opacity
            let blurBefore = shownBlur(st.blur)
            let pressBefore = st.press

            let grownTarget = st.status == .active ? 1.0 : 0.0
            if jump {
                st.grown.jump(grownTarget)
            } else if st.grown.target != grownTarget {
                st.grown.setTarget(grownTarget)
            }

            let target = targets[i]
            if jump {
                st.y.jump(target)
            } else {
                let at = st.y.value()
                if !onScreen(at + offset, height: st.height, viewHeight: viewHeight)
                    && !onScreen(target + offset, height: st.height, viewHeight: viewHeight) {
                    st.y.jump(target)
                } else {
                    let limit = MAX_TRAVEL_VIEWS * viewHeight
                    let far = abs(at - target) > limit
                    if far { st.y.jump(target + signum(at - target) * limit) }
                    if let delays {
                        st.y.setTarget(target, delay: delays[i])
                    } else if far {
                        st.y.setTarget(target)
                    } else {
                        st.y.moveTarget(target)
                    }
                }
            }
            st.y.update(dt)
            st.grown.update(dt)

            let opacityGoal = opacityTarget(st.status, showPassed: showPassed)
            let blurGoal = blurTarget(st.status, distance: abs(i - a))
            if snap {
                st.opacity = opacityGoal
                st.blur = blurGoal
            } else {
                st.opacity = settle(st.opacity, target: opacityGoal, dt: dt, snap: OPACITY_SNAP)
                st.blur = settle(st.blur, target: blurGoal, dt: dt, snap: BLUR_SNAP)
            }

            let pressTarget = st.pressed || nanos < st.pressHeldUntil ? 1.0 : 0.0
            st.press = pressTarget > st.press ? min(pressTarget, st.press + dt / PRESS_S) : max(pressTarget, st.press - dt / PRESS_S)

            // Nothing is written for a line whose springs, fades and press all stood still.
            let layerChanged = snap || scrollMoved
                || st.y.value() != yBefore || st.grown.value() != grownBefore
                || st.opacity != opacityBefore || shownBlur(st.blur) != blurBefore || st.press != pressBefore
            if layerChanged {
                st.layerVersion += 1
                anythingMoved = true
            }

            // The brightness pair can only change when the size or the press did.
            let pairMayChange = snap || st.drawnBrightness == nil || st.grown.value() != grownBefore
                || st.press != pressBefore || st.pressed != (st.drawnBrightness == TouchedBrightness)
            let bright = pairMayChange ? st.brightness() : st.drawnBrightness
            let wordsMoving = timeMoved && t >= st.motionFrom && t <= st.motionUntil
            let dotsMoving = line.isInterlude && (st.status == .active || st.height != baseHeights[i]) && timeMoved
            if snap || bright != st.drawnBrightness || wordsMoving || dotsMoving || (layerChanged && line.isInterlude) {
                st.drawnBrightness = bright
                st.drawVersion += 1
                anythingMoved = true
            }
        }

        prepareNear(a, prepare, release)
        publishShown(a, offset)
        settled = !anythingMoved && !playing && !scrolling
        frames += 1
    }

    // Gets word animation ready near the focus, the focus line first, then the lines ahead, then
    // those behind, within the frame's budget; lets it go for lines that have moved well away.
    private func prepareNear(_ a: Int, _ prepare: (Int) -> Void, _ release: (Int) -> Void) {
        for i in lines.indices {
            let st = states[i]
            if st.live && (i < a - RELEASE_BEHIND || i > a + RELEASE_AHEAD) {
                release(i)
                st.live = false
                st.drawVersion += 1
            }
        }
        let started = monotonicNanos()
        for step in 0...(PREPARE_AHEAD + PREPARE_BEHIND) {
            let i = step <= PREPARE_AHEAD ? a + step : a - (step - PREPARE_AHEAD)
            if !lines.indices.contains(i) || states[i].live { continue }
            if monotonicNanos() - started > PREPARE_BUDGET_NANOS { break }
            prepare(i)
            states[i].live = true
            states[i].drawVersion += 1
        }
    }

    private func publishShown(_ a: Int, _ offset: Double) {
        var first = a
        var last = a
        for i in lines.indices {
            let st = states[i]
            if onScreen(st.y.value() + offset, height: st.height, viewHeight: viewHeight) {
                first = min(first, i)
                last = max(last, i)
            }
        }
        if shown.first != first || shown.last != last { shown = LineRange(first: first, last: last) }
    }

    // MARK: - Touch

    /// A finger went down to scroll: the lyrics stop following the song.
    public func dragStart() {
        if !scrolling {
            scrollFocus = focus
            scrolling = true
        }
        dragging = true
    }

    /// The finger moved; the lyrics follow it, but only so far.
    public func dragBy(_ dy: Double) {
        if !ready { return }
        let last = lines.count - 1
        let lowest = SCROLL_BOTTOM_LIMIT * viewHeight - (targets[last] + heights[last])
        let highest = SCROLL_TOP_LIMIT * viewHeight - targets[0]
        let wanted = scroll.target + dy
        scroll.setTarget(lowest <= highest ? wanted.clamped(lowest, highest) : (lowest + highest) / 2)
    }

    /// The finger lifted: follow the song again in a moment.
    public func dragEnd() {
        dragging = false
        followAt = lastNanos + FOLLOW_AGAIN_NANOS
    }

    private func endScroll(immediately: Bool) {
        scrolling = false
        dragging = false
        if immediately { scroll.jump(0.0) } else { scroll.setTarget(0.0) }
    }

    public func press(_ index: Int, down: Bool) {
        guard states.indices.contains(index) else { return }
        states[index].pressed = down
    }

    /// A tap on a line: it presses in briefly, the lyrics follow the song again, and the target
    /// time shows until the player gets there.
    public func tapped(_ index: Int, playerTarget: Double) {
        if states.indices.contains(index) { states[index].pressHeldUntil = lastNanos + Int(PRESS_S * 1e9) }
        if scrolling { endScroll(immediately: false) }
        clock.holdSeek(playerTarget, nowNanos: lastNanos)
    }
}
