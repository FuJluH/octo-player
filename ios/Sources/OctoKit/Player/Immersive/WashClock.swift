import Foundation

/// The wash's one clock. Each frame the screen offers is handed to `tick`, which says whether to
/// draw one under the frame limit, and moves the motion and the cover fade on by the time that
/// passed.
public final class WashClock {
    public let motion = WashMotion()
    public let fade = CoverFade()
    public let rate: FrameRate
    private var last = 0

    public init(_ initialLimit: Float) {
        rate = FrameRate(initialLimit)
    }

    /// Whether there is anything to move: the motion, or a cover fading in.
    public func busy(_ moving: Bool) -> Bool { moving || fade.running }

    /// The clock starts, or starts again after a rest, at this frame.
    public func start(_ nowNanos: Int) {
        last = nowNanos
    }

    /// One frame the screen offers. True when a frame is due, and so was stepped and should be
    /// drawn.
    public func tick(_ nowNanos: Int, target: Float, bpm: Float, speed: Float, moving: Bool) -> Bool {
        let elapsed = nowNanos - last
        if !frameDue(elapsed, rate.limit) { return false }
        last = nowNanos
        let limit = rate.ease(target)
        if moving { motion.step(frameFactor(bpm, limit) * framesElapsed(elapsed, limit) * speed, bpm, Float(elapsed) / 1e9) }
        fade.advance(Float(elapsed) / 1e6)
        return true
    }

    /// How long the clock can rest after the frame at `nowNanos` before asking for the next, a
    /// little short of when that is due.
    public func restNanos(_ nowNanos: Int) -> Int {
        let limit = rate.limit
        if limit <= 0 { return 0 }
        let due = last + Int(1_000_000_000.0 / Double(limit) * 0.8)
        return max(due - nowNanos - RestMarginNanos, 0)
    }
}

/// How much sooner than due the clock wakes, for a timer that runs late.
public let RestMarginNanos = 6_000_000

/// The two covers the wash fades between.
public final class CoverSwap<T: AnyObject> {
    public private(set) var old: T?
    public private(set) var new: T?

    public init() {}

    /// A new cover arrives now and its fade starts. Mid-fade, the new fade starts from the two as
    /// they show at that moment (`blend` mixes them, as the wash does), so nothing jumps. Returns
    /// the covers to fade from and to.
    public func arrive(_ next: T, _ fade: CoverFade, _ nowMs: Int, blend: (T, T, Float) -> T) -> (from: T, to: T) {
        let from: T
        if let current = new {
            if fade.running, let previous = old, previous !== current {
                from = blend(previous, current, fade.mix)
            } else {
                from = current
            }
        } else {
            from = next
        }
        old = from
        new = next
        fade.start(nowMs)
        return (from, next)
    }
}

/// How far out the background starts on the way in, and ends on the way out, as a share of its
/// full size.
public let DollyStart: Float = 0.9

/// The dolly as a scale: `dolly` runs from 0 (out) to 1 (in).
public func dollyScale(_ dolly: Float) -> Float { DollyStart + (1 - DollyStart) * dolly }
