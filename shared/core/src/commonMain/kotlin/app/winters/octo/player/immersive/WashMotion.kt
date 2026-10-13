package app.winters.octo.player.immersive

import kotlin.math.PI
import kotlin.math.abs
import kotlin.math.max
import kotlin.math.min
import kotlin.math.sin

// The tempo everything is paced against: at this many beats a minute the
// background moves at its base speed.
const val BaseBpm = 120f

private const val TwoPi = (2 * PI).toFloat()

// Every slow wobble in the composite repeats after this long in `t` (the
// slowest is 0.25t and all the others are whole multiples of 0.05t), so
// time can wrap here without a jump.
private val TimeWrap = (40 * PI).toFloat()

// The tempo to pace by: the song's own when it has one and that is wanted,
// otherwise the base. Odd tag values are held to a sensible range.
fun paceBpm(bpm: Int?, useBpm: Boolean): Float =
    if (useBpm && bpm != null && bpm > 0) bpm.toFloat().coerceIn(40f, 240f) else BaseBpm

// How far one drawn frame moves things: k = (BPM / 120) x (60 / frame
// limit), so a slow song drifts slower and the speed does not depend on
// the frame rate.
fun frameFactor(bpm: Float, fpsLimit: Float): Float = (bpm / BaseBpm) * (60f / fpsLimit)

// The moving values behind the background, advanced one drawn frame at a
// time. Only the drawing reads them.
class WashMotion {
    // Animation time.
    var time = 0f
        private set

    // The phase the warp's dividers swing on.
    var warpPhase = 0f
        private set

    // The slow global rotation, and which way it is turning.
    var rotation = 0f
        private set
    var direction = 1f
        private set

    // The final pass's own slowly growing turn, in radians.
    var turn = 0f
        private set

    // The breathing swell's phase.
    var breathPhase = 0f
        private set

    // Extra spin from beats, which fades by 1 a second. Nothing drives it
    // yet; a beat hook can call `beat`.
    var pulse = 0f
        private set

    // The breathing scale, 0.9 to 1.1.
    val breathing: Float get() = 1f + 0.1f * sin(breathPhase)

    // How much the pulse speeds up the rotation, up to 10 times.
    val pulseBoost: Float get() = min(1f + pulse, 10f)

    // One drawn frame: k from `frameFactor`, the tempo, and the seconds
    // since the last frame (for the pulse's fade).
    fun step(k: Float, bpm: Float, seconds: Float) {
        time = (time + 0.016f * k) % TimeWrap
        warpPhase = (warpPhase + 0.016f * k * (bpm / BaseBpm).coerceIn(1f, 2f)) % TwoPi
        rotation += 0.001f * k * breathing * direction * pulseBoost
        // Past a full turn either way, it turns back.
        if (rotation > TwoPi) direction = -1f else if (rotation < -TwoPi) direction = 1f
        turn = (turn + 0.002f * k) % TwoPi
        breathPhase = (breathPhase + 0.016f * k * k / BaseBpm) % TwoPi
        pulse = (pulse - seconds).coerceAtLeast(0f)
    }

    fun beat() {
        pulse += 2f
    }
}

// What the background can be doing, for its frame rate.
enum class WashVisibility { Focused, Unfocused, Hidden }

// The frame rate the background aims for: the set limit while in view and
// focused (at most 30 with battery saver on), 10 behind another window,
// and none while hidden.
fun targetFps(visibility: WashVisibility, limit: Int, powerSave: Boolean): Float = when (visibility) {
    WashVisibility.Focused -> (if (powerSave) min(limit, 30) else limit).toFloat()
    WashVisibility.Unfocused -> 10f
    WashVisibility.Hidden -> 0f
}

// The frame limit in use. A change eases in by 8% of the gap each frame
// rather than snapping.
class FrameRate(initial: Float) {
    var limit = initial
        private set

    fun ease(target: Float): Float {
        if (target <= 0f) return limit
        limit += (target - limit) * 0.08f
        if (abs(target - limit) < 0.01f) limit = target
        return limit
    }
}

// Whether enough time has passed since the last drawn frame to draw
// another under this limit. A fifth of a frame's slack keeps a 60 limit on
// a 60 Hz screen from skipping frames that arrive a hair early.
fun frameDue(elapsedNanos: Long, limit: Float): Boolean =
    limit > 0f && elapsedNanos >= (1_000_000_000.0 / limit * 0.8).toLong()

// The time slot, on this limit's even spacing, that a frame drawn at
// `nowNanos` fills, given the slot of the frame before. When the screen's
// rate is not a whole multiple of the limit (60 on a 90 Hz screen), frames
// land up to part of a screen frame off their slots; counting from the
// slot rather than from when each was drawn keeps the average at the
// limit. A frame drawn under a twentieth of a frame before its slot takes
// the drawn time instead, so a screen a hair faster than the limit never
// skips one. The slot never trails the drawn time by more than half a
// frame, so a screen a hair slower never skips one either, and a stall
// brings no run of quick frames.
fun nextSlot(slotNanos: Long, nowNanos: Long, limit: Float): Long {
    if (limit <= 0f) return nowNanos
    val period = (1_000_000_000.0 / limit).toLong()
    val next = slotNanos + period
    return if (next >= nowNanos && next - nowNanos < period / 20) nowNanos else max(next, nowNanos - period / 2)
}

// How many frames' worth of time a gap is, at this limit. Usually 1; more
// when the screen could not keep up, so the speed holds; held to 3 so a
// pause never makes things leap.
fun framesElapsed(elapsedNanos: Long, limit: Float): Float =
    (elapsedNanos / 1_000_000_000.0 * limit).toFloat().coerceIn(0.5f, 3f)
