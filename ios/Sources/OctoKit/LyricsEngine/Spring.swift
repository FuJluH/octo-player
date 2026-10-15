import Foundation

/// Near enough to its target, and slow enough, to count as stopped.
public let SPRING_REST_DISTANCE = 0.01
public let SPRING_REST_SPEED = 0.01

// The window the speed is sampled over when a spring changes course.
private let VELOCITY_WINDOW_S = 1.0 / 240.0

/// A spring worked out in closed form instead of stepped: each time its target changes, the curve
/// from where it is, how fast it is going and where it is headed is solved once, and every frame
/// just reads that curve at the time gone by. So it lands the same at 60 or 120 frames a second.
/// A target can wait a moment before it takes over, for the ripple between lines. `speed` makes
/// it faster or slower without making it bouncier.
public final class Spring {
    private let mass: Double
    private let stiffness: Double
    private let damping: Double

    /// Where it is headed. The curve toward it: how far off it started (`x0`), how fast it was
    /// moving then (`v0`), and the time since.
    public private(set) var target: Double
    private var x0 = 0.0
    private var v0 = 0.0
    private var time = 0.0

    // The strength and friction in use, scaled by the speed.
    private var k: Double
    private var c: Double

    // A target still waiting its turn, and how long it has left.
    private var queued: Double?
    private var wait = 0.0

    public private(set) var atRest = true

    private var speedValue = 1.0

    public init(_ mass: Double, _ stiffness: Double, _ damping: Double, initial: Double = 0.0) {
        self.mass = mass
        self.stiffness = stiffness
        self.damping = damping
        target = initial
        k = stiffness
        c = damping
    }

    public var speed: Double {
        get { speedValue }
        set {
            if newValue == speedValue || newValue <= 0.0 { return }
            let now = value()
            let moving = velocity()
            speedValue = newValue
            k = stiffness * newValue * newValue
            c = damping * newValue
            restart(now, moving, target)
        }
    }

    /// How strongly it is damped: at 1 or more it never overshoots.
    public var dampingRatio: Double { c / (2.0 * (k * mass).squareRoot()) }

    public func value() -> Double { atRest ? target : target + offsetAt(time) }

    /// How fast it is moving now, from a tiny window either side.
    public func velocity() -> Double {
        if atRest { return 0.0 }
        let half = VELOCITY_WINDOW_S / 2
        return (offsetAt(time + half) - offsetAt(time - half)) / VELOCITY_WINDOW_S
    }

    /// Heads for a new target, now or once `delay` seconds have passed. A new target replaces one
    /// still waiting.
    public func setTarget(_ to: Double, delay: Double = 0.0) {
        if delay > 0.0 {
            queued = to
            wait = delay
            return
        }
        queued = nil
        retarget(to)
    }

    /// Moves the target without restarting a wait: a target still waiting just changes, one
    /// already in use changes course now.
    public func moveTarget(_ to: Double) {
        if queued != nil {
            queued = to
        } else if to != target {
            retarget(to)
        }
    }

    /// Puts it straight at a place, still.
    public func jump(_ to: Double) {
        queued = nil
        target = to
        x0 = 0.0
        v0 = 0.0
        time = 0.0
        atRest = true
    }

    /// Lets `dt` seconds go by. A waiting target takes over at the exact moment its wait runs
    /// out, even inside a frame.
    public func update(_ dt: Double) {
        if let waiting = queued {
            if wait <= dt {
                let before = wait
                advance(before)
                queued = nil
                retarget(waiting)
                advance(dt - before)
                return
            }
            wait -= dt
        }
        advance(dt)
    }

    /// Whether a target is still waiting its turn.
    public var hasQueued: Bool { queued != nil }

    private func retarget(_ to: Double) {
        restart(value(), velocity(), to)
    }

    private func restart(_ from: Double, _ moving: Double, _ to: Double) {
        target = to
        x0 = from - to
        v0 = moving
        time = 0.0
        atRest = abs(x0) < SPRING_REST_DISTANCE && abs(v0) < SPRING_REST_SPEED
        if atRest { x0 = 0.0 }
    }

    private func advance(_ dt: Double) {
        if atRest || dt <= 0.0 { return }
        time += dt
        if abs(offsetAt(time)) < SPRING_REST_DISTANCE && abs(velocity()) < SPRING_REST_SPEED {
            atRest = true
            x0 = 0.0
            v0 = 0.0
            time = 0.0
        }
    }

    // How far from the target it is `t` seconds into the current curve.
    private func offsetAt(_ t: Double) -> Double { springOffset(x0, v0: v0, t: t, mass: mass, stiffness: k, damping: c) }
}

/// The closed-form spring: how far from its target a spring is `t` seconds after starting `x0`
/// away at speed `v0`. Damped enough (a ratio of 1 or more) it creeps in; less, it swings in and
/// settles.
public func springOffset(_ x0: Double, v0: Double, t: Double, mass: Double, stiffness: Double, damping: Double) -> Double {
    let w0 = (stiffness / mass).squareRoot()
    let zeta = damping / (2.0 * (stiffness * mass).squareRoot())
    if zeta < 1.0 {
        let wd = w0 * (1.0 - zeta * zeta).squareRoot()
        return exp(-zeta * w0 * t) * (x0 * cos(wd * t) + (v0 + zeta * w0 * x0) / wd * sin(wd * t))
    } else if zeta == 1.0 {
        return exp(-w0 * t) * (x0 + (v0 + w0 * x0) * t)
    } else {
        let root = (zeta * zeta - 1.0).squareRoot()
        let r1 = -w0 * (zeta - root)
        let r2 = -w0 * (zeta + root)
        let a = (v0 - r2 * x0) / (r1 - r2)
        let b = x0 - a
        return a * exp(r1 * t) + b * exp(r2 * t)
    }
}

/// The springs the lyrics use (mass, stiffness, damping).
public func linePositionSpring(initial: Double = 0.0) -> Spring { Spring(1.0, 200.0, 28.0, initial: initial) }
public func lineScaleSpring(initial: Double = 0.0) -> Spring { Spring(1.0, 260.0, 32.0, initial: initial) }
public func scrollOffsetSpring(initial: Double = 0.0) -> Spring { Spring(1.0, 240.0, 28.0, initial: initial) }
