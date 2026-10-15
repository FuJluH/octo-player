package app.winters.octo.lyrics.engine

import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.mutableStateOf
import app.winters.octo.lyrics.LookDial
import app.winters.octo.lyrics.LyricsLook
import kotlin.math.abs
import kotlin.math.max
import kotlin.math.min
import kotlin.math.sign

// Word animation is prepared for lines this close to the focus, and let go
// only once they are further than the second pair, so lines near the edge
// do not flip back and forth.
const val PREPARE_BEHIND = 4
const val PREPARE_AHEAD = 10
const val RELEASE_BEHIND = 8
const val RELEASE_AHEAD = 14

// Preparing word animation may take this long in one frame.
const val PREPARE_BUDGET_NANOS = 3_000_000L

// After a scroll by hand, the lyrics follow the song again this long after
// the finger lifts.
const val FOLLOW_AGAIN_NANOS = 2_000_000_000L

// A scroll stops with the first line no lower than this much of the view,
// and the last no higher than this.
const val SCROLL_TOP_LIMIT = 0.3
const val SCROLL_BOTTOM_LIMIT = 0.7

// The whole flowing view's motion, run once a frame from one loop: the
// clock, which lines are being sung, where every line is headed, the
// ripple, the fades, the scroll by hand, and which lines get their word
// animation ready. Drawing only reads what this leaves behind, through
// each line's version counters, so a frame never composes anything.
class LyricEngine(val lines: List<SyncLine>) {
    val states: List<LineState> = lines.map(::LineState)
    val clock = LyricClock()

    // Lines the focus can rest on: every line except backing vocals sung
    // under the lead line just above them.
    private val anchorable = BooleanArray(lines.size) { i ->
        val line = lines[i]
        val above = lines.getOrNull(i - 1)
        !(line.isBackground && above != null && !above.isBackground && !above.isInterlude && line.start < above.end)
    }

    var look: LyricsLook = LyricsLook()
    var reduceMotion: Boolean = false

    // The lines' measured heights, and an interlude's closed and open height.
    private var baseHeights = DoubleArray(0)
    private var idleHeight = 0.0
    private var fullHeight = 0.0
    var viewHeight = 0.0
        private set

    val ready: Boolean get() = baseHeights.size == lines.size && viewHeight > 0 && lines.isNotEmpty()

    // Where the song is on the lyrics' clock, and the line in focus.
    var lyricTime = 0.0
        private set
    var focus = 0
        private set
    private var lastFocus = -1
    private var lastLyricTime = Double.NaN
    private var needsJump = true
    private var appliedSpeed = 1.0
    private var lastNanos = 0L

    // Scrolling by hand: an offset on its own spring, the focus held where
    // it was when the finger went down.
    private val scroll = scrollOffsetSpring()
    val scrollOffset: Double get() = scroll.value()
    var scrolling = false
        private set
    private var dragging = false
    private var scrollFocus = 0
    private var followAt = 0L

    // Worked out again each frame, kept to save making new ones.
    private val heights = DoubleArray(lines.size)
    private val above = DoubleArray(lines.size + 1)
    private val targets = DoubleArray(lines.size)

    // Nothing moved last frame and nothing is playing, so the loop may rest.
    var settled = false
        private set

    // Counts frames, for anything drawn from the engine as a whole.
    val frames = mutableIntStateOf(0)

    // The lines worth composing: on screen or about to be, and the focus.
    val shown = mutableStateOf(IntRange.EMPTY)

    // New sizes: after the first, lines jump to their new places.
    fun setGeometry(lineHeights: DoubleArray, interludeIdle: Double, interludeFull: Double, height: Double) {
        baseHeights = lineHeights
        idleHeight = interludeIdle
        fullHeight = interludeFull
        viewHeight = height
        states.forEach { it.live = false }
        needsJump = true
    }

    // The view is showing again: start the clock fresh and put everything
    // straight in place.
    fun restart() {
        clock.reset()
        needsJump = true
    }

    // The line in focus at `t`: the last one begun, not counting backing
    // vocals under a lead line. Before any has begun, the first.
    fun focusAt(t: Double): Int {
        var found = -1
        var first = -1
        for (i in lines.indices) {
            if (!anchorable[i]) continue
            if (first < 0) first = i
            if (lines[i].start <= t) found = i
        }
        return if (found >= 0) found else max(first, 0)
    }

    // One frame. `offsetMs` is the song's lyrics timing and `outputOffsetMs`
    // the output's, which the clock takes as its latency. `prepare` readies
    // a line's word animation and `release` lets it go; both come from the
    // view, which holds the text.
    fun frame(
        nanos: Long,
        reportedMs: Long,
        playing: Boolean,
        rate: Double,
        offsetMs: Long,
        outputOffsetMs: Long = 0,
        prepare: (Int) -> Unit = {},
        release: (Int) -> Unit = {},
    ) {
        if (!ready) return
        lastNanos = nanos
        clock.setLatency(outputOffsetMs / 1000.0)
        val playerTime = clock.frame(nanos, reportedMs / 1000.0, rate, playing)
        val dt = clock.step
        val t = playerTime - offsetMs / 1000.0
        lyricTime = t
        val seeked = clock.seeked
        // Places are set outright on the first frame, after a seek or a
        // resize; with reduced motion, always.
        val snap = needsJump || seeked
        val jump = snap || reduceMotion
        needsJump = false
        if (seeked && scrolling) endScroll(immediately = true)

        val speed = look.fraction(LookDial.Speed)
        if (speed != appliedSpeed) {
            appliedSpeed = speed
            states.forEach {
                it.y.speed = speed
                it.grown.speed = speed
            }
            scroll.speed = speed
        }
        if (scrolling && !dragging && nanos >= followAt) endScroll(immediately = false)

        // Who is singing, and how tall each line is now.
        for (i in lines.indices) {
            val st = states[i]
            val line = lines[i]
            st.status = when {
                t < line.start -> LineStatus.Upcoming
                t < line.end -> LineStatus.Active
                else -> LineStatus.Passed
            }
            st.height = if (line.isInterlude) {
                if (st.status != LineStatus.Active) {
                    st.grownIn = false
                } else if (snap) {
                    st.grownIn = true
                }
                val open = when {
                    st.status != LineStatus.Active -> 0.0
                    reduceMotion -> 1.0
                    else -> interludeOpen(t - line.start, line.end - line.start, st.grownIn)
                }
                idleHeight + (fullHeight - idleHeight) * open
            } else {
                baseHeights[i]
            }
            heights[i] = st.height
        }

        val a = if (scrolling) scrollFocus else focusAt(t)
        focus = a
        for (i in lines.indices) above[i + 1] = above[i] + heights[i]
        for (i in lines.indices) targets[i] = targetY(i, a, above, heights, viewHeight)
        val ripple = a != lastFocus && lastFocus >= 0 && !jump && !scrolling && look.cascade > 0
        val delays = if (ripple) cascadeDelays(targets, a, viewHeight, look.fraction(LookDial.Cascade)) else null
        lastFocus = a

        val scrollBefore = scroll.value()
        scroll.update(dt)
        val offset = scroll.value()
        val scrollMoved = offset != scrollBefore

        val showPassed = look.keepCompleted || scrolling
        val timeMoved = t != lastLyricTime
        lastLyricTime = t
        var anythingMoved = scrollMoved

        for (i in lines.indices) {
            val st = states[i]
            val line = lines[i]
            val grownTarget = if (st.status == LineStatus.Active) 1.0 else 0.0
            val opacityTarget = opacityTarget(st.status, showPassed)
            val blurTarget = blurTarget(st.status, abs(i - a))
            val pressTarget = if (st.pressed || nanos < st.pressHeldUntil) 1.0 else 0.0
            // A line already resting where everything sends it, with no words
            // or dots moving, would come out of the steps below unchanged:
            // it is left as it is.
            val resting = !snap && !scrollMoved && !delaysPending(delays) &&
                st.y.atRest && !st.y.hasQueued && st.y.target == targets[i] &&
                st.grown.atRest && !st.grown.hasQueued && st.grown.target == grownTarget &&
                st.opacity == opacityTarget && st.blur == blurTarget &&
                st.press == 0.0 && pressTarget == 0.0 && st.drawnBrightness != null &&
                !(timeMoved && t >= st.motionFrom && t <= st.motionUntil) &&
                !(line.isInterlude && (st.status == LineStatus.Active || st.height != baseHeights[i]))
            if (resting) continue

            val yBefore = st.y.value()
            val grownBefore = st.grown.value()
            val opacityBefore = st.opacity
            val blurBefore = shownBlur(st.blur)
            val pressBefore = st.press

            if (jump) st.grown.jump(grownTarget) else if (st.grown.target != grownTarget) st.grown.setTarget(grownTarget)

            val target = targets[i]
            if (jump) {
                st.y.jump(target)
            } else {
                val at = st.y.value()
                if (!onScreen(at + offset, st.height, viewHeight) && !onScreen(target + offset, st.height, viewHeight)) {
                    st.y.jump(target)
                } else {
                    val limit = MAX_TRAVEL_VIEWS * viewHeight
                    val far = abs(at - target) > limit
                    if (far) st.y.jump(target + sign(at - target) * limit)
                    when {
                        delays != null -> st.y.setTarget(target, delays[i])
                        far -> st.y.setTarget(target)
                        else -> st.y.moveTarget(target)
                    }
                }
            }
            st.y.update(dt)
            st.grown.update(dt)

            if (snap) {
                st.opacity = opacityTarget
                st.blur = blurTarget
            } else {
                if (st.opacity != opacityTarget) st.opacity = settle(st.opacity, opacityTarget, dt, OPACITY_SNAP)
                if (st.blur != blurTarget) st.blur = settle(st.blur, blurTarget, dt, BLUR_SNAP)
            }

            st.press = if (pressTarget > st.press) min(pressTarget, st.press + dt / PRESS_S) else max(pressTarget, st.press - dt / PRESS_S)

            // Nothing is written for a line whose springs, fades and press
            // all stood still.
            val layerChanged = snap || scrollMoved ||
                st.y.value() != yBefore || st.grown.value() != grownBefore ||
                st.opacity != opacityBefore || shownBlur(st.blur) != blurBefore || st.press != pressBefore
            if (layerChanged) {
                st.layerVersion.intValue++
                anythingMoved = true
            }

            // The brightness pair can only change when the size or the press did.
            val pairMayChange = snap || st.drawnBrightness == null || st.grown.value() != grownBefore ||
                st.press != pressBefore || st.pressed != (st.drawnBrightness == TouchedBrightness)
            val bright = if (pairMayChange) st.brightness() else st.drawnBrightness
            val wordsMoving = timeMoved && t >= st.motionFrom && t <= st.motionUntil
            val dotsMoving = line.isInterlude && (st.status == LineStatus.Active || st.height != baseHeights[i]) && timeMoved
            if (snap || bright != st.drawnBrightness || wordsMoving || dotsMoving || layerChanged && line.isInterlude) {
                st.drawnBrightness = bright
                st.drawVersion.intValue++
                anythingMoved = true
            }
        }

        prepareNear(a, prepare, release)
        publishShown(a, offset)
        settled = !anythingMoved && !playing && !scrolling
        frames.intValue++
    }

    // Whether a ripple has just set lines waiting: then every line takes its
    // new target this frame.
    private fun delaysPending(delays: DoubleArray?): Boolean = delays != null

    // Gets word animation ready near the focus, the focus line first, then
    // the lines ahead, then those behind, within the frame's budget; lets it
    // go for lines that have moved well away.
    private fun prepareNear(a: Int, prepare: (Int) -> Unit, release: (Int) -> Unit) {
        for (i in lines.indices) {
            val st = states[i]
            if (st.live && (i < a - RELEASE_BEHIND || i > a + RELEASE_AHEAD)) {
                release(i)
                st.live = false
                st.drawVersion.intValue++
            }
        }
        val started = System.nanoTime()
        for (step in 0..PREPARE_AHEAD + PREPARE_BEHIND) {
            val i = when {
                step <= PREPARE_AHEAD -> a + step
                else -> a - (step - PREPARE_AHEAD)
            }
            if (i !in lines.indices || states[i].live) continue
            if (System.nanoTime() - started > PREPARE_BUDGET_NANOS) break
            prepare(i)
            states[i].live = true
            states[i].drawVersion.intValue++
        }
    }

    private fun publishShown(a: Int, offset: Double) {
        var first = a
        var last = a
        for (i in lines.indices) {
            val st = states[i]
            if (onScreen(st.y.value() + offset, st.height, viewHeight)) {
                first = min(first, i)
                last = max(last, i)
            }
        }
        val now = shown.value
        if (now.first != first || now.last != last) shown.value = first..last
    }

    // ---- Touch ----

    // A finger went down to scroll: the lyrics stop following the song.
    fun dragStart() {
        if (!scrolling) {
            scrollFocus = focus
            scrolling = true
        }
        dragging = true
    }

    // The finger moved; the lyrics follow it, but only so far.
    fun dragBy(dy: Double) {
        if (!ready) return
        val last = lines.lastIndex
        val lowest = SCROLL_BOTTOM_LIMIT * viewHeight - (targets[last] + heights[last])
        val highest = SCROLL_TOP_LIMIT * viewHeight - targets[0]
        val wanted = scroll.target + dy
        scroll.setTarget(if (lowest <= highest) wanted.coerceIn(lowest, highest) else (lowest + highest) / 2)
    }

    // The finger lifted: follow the song again in a moment.
    fun dragEnd() {
        dragging = false
        followAt = lastNanos + FOLLOW_AGAIN_NANOS
    }

    private fun endScroll(immediately: Boolean) {
        scrolling = false
        dragging = false
        if (immediately) scroll.jump(0.0) else scroll.setTarget(0.0)
    }

    fun press(index: Int, down: Boolean) {
        states.getOrNull(index)?.pressed = down
    }

    // A tap on a line: it presses in briefly, the lyrics follow the song
    // again, and the target time shows until the player gets there.
    fun tapped(index: Int, playerTarget: Double) {
        states.getOrNull(index)?.pressHeldUntil = lastNanos + (PRESS_S * 1e9).toLong()
        if (scrolling) endScroll(immediately = false)
        clock.holdSeek(playerTarget, lastNanos)
    }
}
