import Foundation
#if canImport(CoreGraphics)
import CoreGraphics
#endif

/// When the cover's flight into the player starts. The player takes a moment to build, and
/// nothing drawn on the main thread moves while it does, so the cover leaves first whenever it
/// can: with the small player showing and the card's place known from the last time the player
/// was open, it takes off at once and the player is built a frame later, under it. Without a
/// place known it waits for the card to be laid out; without the small player there is nothing
/// to fly from.
public enum CoverFlightStart: Equatable, Sendable {
    case now(to: CGRect)
    case afterCard
    case none
}

public func coverFlightStart(bar: CGRect?, lastCard: CGRect?) -> CoverFlightStart {
    guard let bar, bar.width > 1, bar.height > 1 else { return .none }
    guard let lastCard, lastCard.width > 1, lastCard.height > 1 else { return .afterCard }
    return .now(to: lastCard)
}

/// How long the player waits to be built after the cover took off: one frame at 60 Hz and a
/// little more, so the flight is handed to the screen before the player's building holds the
/// main thread.
public let playerBuildDelayMs = 20

/// A flight under way goes to where the card was laid out once that differs from where it was
/// headed by more than half a point.
public func flightNeedsRetarget(headed: CGRect, placed: CGRect) -> Bool {
    abs(headed.minX - placed.minX) > 0.5 || abs(headed.minY - placed.minY) > 0.5
        || abs(headed.width - placed.width) > 0.5 || abs(headed.height - placed.height) > 0.5
}

/// A spring given by damping ratio and stiffness, as Core Animation takes it: mass 1, this
/// stiffness and this damping.
public func springDamping(ratio: Double, stiffness: Double) -> Double {
    2 * ratio * stiffness.squareRoot()
}

/// How long a critically damped spring of this stiffness takes to come within `residual` (a
/// share of its whole way) of where it is going: the flight lands then, rather than after the
/// last invisible fraction of a point.
public func criticalSpringSeconds(stiffness: Double, residual: Double = 0.001) -> Double {
    let omega = stiffness.squareRoot()
    var t = 0.0
    while (1 + omega * t) * exp(-omega * t) > residual { t += 0.001 }
    return t
}
