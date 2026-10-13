package app.winters.octo.player.immersive

// The wash's one clock, the same on the phone and the desktop. Each frame
// the screen offers is handed to `tick`, which says whether to draw one
// under the frame limit, and moves the motion and the cover fade on by the
// time that passed.
class WashClock(initialLimit: Float) {
    val motion = WashMotion()
    val fade = CoverFade()
    val rate = FrameRate(initialLimit)
    private var last = 0L
    // The slot the last drawn frame filled (`nextSlot`).
    private var slot = 0L

    // Whether there is anything to move: the motion, or a cover fading in.
    fun busy(moving: Boolean): Boolean = moving || fade.running

    // The clock starts, or starts again after a rest, at this frame.
    fun start(nowNanos: Long) {
        last = nowNanos
        slot = nowNanos
    }

    // One frame the screen offers. `target` is the frame rate wanted now
    // (`targetFps`), `bpm` the tempo to pace by, `speed` the share of the
    // full pace. True when a frame is due, and so was stepped and should be
    // drawn.
    fun tick(nowNanos: Long, target: Float, bpm: Float, speed: Float, moving: Boolean): Boolean {
        val elapsed = nowNanos - last
        if (!frameDue(nowNanos - slot, rate.limit)) return false
        slot = nextSlot(slot, nowNanos, rate.limit)
        last = nowNanos
        val limit = rate.ease(target)
        if (moving) motion.step(frameFactor(bpm, limit) * framesElapsed(elapsed, limit) * speed, bpm, elapsed / 1e9f)
        fade.advance(elapsed / 1e6f)
        return true
    }

    // How long the clock can rest after the frame at `nowNanos` before
    // asking for the next, a little short of when that is due. A desktop
    // window redraws whole for every frame asked for, drawn or not, so
    // asking for each of a 60 Hz screen's frames under a 30 limit would
    // draw the window twice as often as the wash moves.
    fun restNanos(nowNanos: Long): Long {
        val limit = rate.limit
        if (limit <= 0f) return 0L
        val due = slot + (1_000_000_000.0 / limit * 0.8).toLong()
        return (due - nowNanos - RestMarginNanos).coerceAtLeast(0L)
    }
}

// How much sooner than due the clock wakes, for a timer that runs late.
const val RestMarginNanos = 6_000_000L

// The two covers the wash fades between.
class CoverSwap<T : Any> {
    var old: T? = null
        private set
    var new: T? = null
        private set

    // A new cover arrives now and its fade starts. Mid-fade, the new fade
    // starts from the two as they show at that moment (`blend` mixes them,
    // as the wash does), so nothing jumps. Picking whichever showed most
    // snapped the old cover back when a song's real cover came in just
    // after its stand-in, as an outside song's does on radio. Returns the
    // covers to fade from and to.
    fun arrive(next: T, fade: CoverFade, nowMs: Long, blend: (old: T, new: T, mix: Float) -> T): Pair<T, T> {
        val current = new
        val previous = old
        val from = when {
            current == null -> next
            fade.running && previous != null && previous !== current -> blend(previous, current, fade.mix)
            else -> current
        }
        old = from
        new = next
        fade.start(nowMs)
        return from to next
    }
}

// How far out the background starts on the way in, and ends on the way
// out, as a share of its full size.
const val DollyStart = 0.9f

// The dolly as a scale: `dolly` runs from 0 (out) to 1 (in).
fun dollyScale(dolly: Float): Float = DollyStart + (1f - DollyStart) * dolly
