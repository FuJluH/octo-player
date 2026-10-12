import Foundation

/// A spring as a damping ratio and a stiffness, on a unit mass.
public struct SpringSpec: Sendable, Equatable {
    public let damping: Double
    public let stiffness: Double

    public init(_ damping: Double, _ stiffness: Double) {
        self.damping = damping
        self.stiffness = stiffness
    }

    /// The time one undamped swing takes, which is how SwiftUI names a spring's speed.
    public var response: Double { 2 * Double.pi / stiffness.squareRoot() }
}

/// The shared springs, so every surface moves the same way.
public enum OctoSprings {
    public static let soft = SpringSpec(0.75, 400)
    public static let snappy = SpringSpec(0.65, 600)
    public static let bouncy = SpringSpec(0.5, 400)
    public static let jelly = SpringSpec(0.55, 300)
    public static let smooth = SpringSpec(0.75, 1500)
    /// Settles without a bounce: a card changing size, like a menu turning to its next page.
    public static let calm = SpringSpec(0.9, 500)
    /// A color or a corner changing state: no bounce, quick.
    public static let state = SpringSpec(1, 1500)
    /// Something entering, leaving or flying to a new place: no bounce, medium.
    public static let move = SpringSpec(1, 400)
}

/// How long each kind of change takes, in milliseconds, before the motion scale.
public enum OctoDuration {
    /// A press going down.
    public static let press = 80
    /// The pointer arriving or leaving.
    public static let hover = 140
    /// One icon or pop-up swapping for another.
    public static let swap = 160
    /// A fill changing color.
    public static let fill = 180
    /// A card or row changing, or a ripple of light.
    public static let card = 200
    /// Anything without a more particular speed, and a focus ring.
    public static let neutral = 300
    /// A row squeezed by a long press, down and back.
    public static let squeeze = 340
    /// The scrubber growing, and its played part sweeping away at the end.
    public static let scrub = 400

    public static let all = [press, hover, swap, fill, card, neutral, squeeze, scrub]
}

/// A cubic bezier from (0, 0) to (1, 1), named by its two control points.
public struct EasingCurve: Sendable, Equatable {
    public let x1: Double
    public let y1: Double
    public let x2: Double
    public let y2: Double

    public init(_ x1: Double, _ y1: Double, _ x2: Double, _ y2: Double) {
        self.x1 = x1
        self.y1 = y1
        self.x2 = x2
        self.y2 = y2
    }

    public static func == (a: EasingCurve, b: EasingCurve) -> Bool {
        a.x1 == b.x1 && a.y1 == b.y1 && a.x2 == b.x2 && a.y2 == b.y2
    }

    /// The curve's height where it is `x` of the way along.
    public func at(_ x: Double) -> Double { CubicBezier(x1, y1, x2, y2).at(x) }
}

/// The curves every tween uses.
public enum OctoEasing {
    /// The default: quick off the mark, a long soft landing.
    public static let spring = EasingCurve(0.2, 0.8, 0.2, 1)
    /// Goes a little past and comes back, for something growing.
    public static let overshoot = EasingCurve(0.34, 1.56, 0.64, 1)
    /// Dips back a touch before it starts and passes a touch at the end.
    public static let bounce = EasingCurve(0.45, -0.05, 0.15, 1.05)
    /// Even in and out, for a pill sliding between places.
    public static let smooth = EasingCurve(0.65, 0.05, 0.36, 1)
    /// All at once, then settling.
    public static let snappy = EasingCurve(0, 0, 0, 1)
    /// Gathers speed as it goes, for something leaving.
    public static let easeIn = EasingCurve(0.4, 0, 1, 1)
    /// The scrubber's played part sweeping off the end.
    public static let sweep = EasingCurve(0.5, 0, 0.75, 0)
    /// The plain tween's curve: speeds up quickly and settles slowly.
    public static let standard = EasingCurve(0.4, 0, 0.2, 1)
    /// Starts at full speed and settles slowly.
    public static let decelerate = EasingCurve(0, 0, 0.2, 1)
    /// Starts slowly and leaves at full speed.
    public static let accelerate = EasingCurve(0.4, 0, 1, 1)

    public static let all = [spring, overshoot, bounce, smooth, snappy, easeIn, sweep]
}

/// How far a press, a pop and a lift go.
public enum OctoPress {
    /// A control pressed down.
    public static let scale = 0.96
    /// A large surface pressed, like a row or a card.
    public static let largeScale = 0.985
    /// A chrome button popping out as it is pressed.
    public static let pop = 1.05
    /// A small control rising under the pointer, in points.
    public static let liftSmall = 1.0
    /// A medium one.
    public static let liftMedium = 2.0
}

/// One number for how long motion takes and one for how far it goes, so reduced motion calms
/// everything at once. Every token duration is multiplied by `duration` and every travel, lift
/// or growth by `distance`.
public struct MotionScale: Sendable, Equatable {
    public let duration: Double
    public let distance: Double

    public init(duration: Double = 1, distance: Double = 1) {
        self.duration = duration
        self.distance = distance
    }

    /// A token duration after the scale, in whole milliseconds.
    public func ms(_ base: Int) -> Int { Int((Double(base) * duration).rounded(.toNearestOrAwayFromZero)) }

    /// A token duration after the scale, in seconds.
    public func seconds(_ base: Int) -> Double { Double(ms(base)) / 1_000 }

    /// A travel after the scale.
    public func travel(_ base: Double) -> Double { base * distance }

    /// A scale factor after the scale: 1.05 becomes 1.0 when nothing moves.
    public func scale(_ base: Double) -> Double { 1 + (base - 1) * distance }

    /// True when nothing moves at all.
    public var still: Bool { distance == 0 }

    public static let full = MotionScale()

    /// Reduced motion: nothing travels, grows or shrinks, and what still changes (a fade, a
    /// color) does so in half the time.
    public static let reduced = MotionScale(duration: 0.5, distance: 0)

    /// The scale from the phone's animation speed and Octo's own Reduce motion. Only the
    /// phone's "off" counts, as reduced: a slower or faster speed is applied by the system
    /// itself, so passing it on would count it twice.
    public static func of(systemAnimatorScale: Double, reduce: Bool) -> MotionScale {
        reduce || systemAnimatorScale == 0 ? reduced : full
    }

    /// The scale from the phone's Reduce Motion and Octo's own setting.
    public static func of(systemReduced: Bool, reduce: Bool) -> MotionScale {
        reduce || systemReduced ? reduced : full
    }
}
