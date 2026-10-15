import Foundation

/// Whether the player is moving on screen: opening, held under a finger that pulls it down,
/// springing back, or closing with its cover flying home. While it moves, every frame loop that
/// shows (the progress line and ring, the LIVE dot, the background, the lyrics) runs at the
/// screen's own rate; their slower resting paces come back only once it has stopped.
public struct PlayerMotionClock: Sendable, Equatable {
    /// How long opening takes, the cover's flight and the content rising in included.
    public static let openSeconds = 1.0
    /// How long closing takes, until the cover is home and the player is taken down.
    public static let closeSeconds = 1.3
    /// How long the player takes to spring back or away once the finger lets go.
    public static let releaseSeconds = 0.8

    /// Until when, in the clock's seconds, a transition started runs.
    public private(set) var until: Double = 0
    /// A finger holds the player.
    public private(set) var held = false

    public init() {}

    /// A transition of `seconds` starts at `now`; one already running that ends later keeps its end.
    public mutating func moved(at now: Double, for seconds: Double) {
        until = max(until, now + seconds)
    }

    /// A finger took the player, or let it go; letting go leaves it moving while it springs.
    public mutating func hold(_ on: Bool, at now: Double) {
        guard on != held else { return }
        held = on
        if !on { moved(at: now, for: Self.releaseSeconds) }
    }

    public func moving(at now: Double) -> Bool { held || now < until }

    /// Seconds from `now` until it stops moving, or nil while a finger holds it.
    public func restsIn(at now: Double) -> Double? { held ? nil : max(0, until - now) }
}

/// A frame loop's interval: its own slower one at rest, none (every frame) while the player moves.
public func pacedInterval(_ resting: Double?, moving: Bool) -> Double? {
    moving ? nil : resting
}

/// The least time between two of the classic mesh's frames at `pace`: none while the player
/// moves, so the background never lags what moves over it.
public func meshFrameStep(_ pace: Float, moving: Bool) -> Double {
    moving ? 0 : 1 / meshFps(pace)
}

/// The start of the whole-second clock a once-a-second timeline steps on: a whole second at or
/// before `now`, so every ring on screen moves in the same frame, and never far behind, so the
/// timeline has no backlog of past seconds to step through.
public func wholeSecondAtOrBefore(_ now: Date) -> Date {
    Date(timeIntervalSinceReferenceDate: now.timeIntervalSinceReferenceDate.rounded(.down))
}
