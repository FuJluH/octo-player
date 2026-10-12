import Foundation

/// Which way a drag is meant to go. It is decided once, from the first clear movement, and
/// holds for the rest of the drag.
public enum DragAxis: Sendable, Equatable {
    case undecided, horizontal, vertical
}

/// The finger has moved (`dx`, `dy`) since it went down. Until it has gone `slop` in any
/// direction nothing is decided; then the larger of the two wins. A tie counts as upright.
public func dragAxis(_ dx: Double, _ dy: Double, slop: Double) -> DragAxis {
    if dx * dx + dy * dy < slop * slop { return .undecided }
    return abs(dx) > abs(dy) ? .horizontal : .vertical
}

public enum SwipeSkip: Sendable, Equatable {
    case next, previous, stay
}

/// Where a sideways swipe over a song ends up once the finger lifts. Far enough, or flicked
/// fast enough the way it was already going, it skips: left to the next song, right to the one
/// before. Otherwise it stays.
public func swipeSkip(offset: Double, velocity: Double, distance: Double, fling: Double) -> SwipeSkip {
    if offset <= -distance || (offset < 0 && velocity <= -fling) { return .next }
    if offset >= distance || (offset > 0 && velocity >= fling) { return .previous }
    return .stay
}

/// Whether an upright swipe ends by opening what is above it: pulled up far enough, or flicked
/// up fast enough while already going up.
public func swipeUp(offset: Double, velocity: Double, distance: Double, fling: Double) -> Bool {
    offset <= -distance || (offset < 0 && velocity <= -fling)
}

/// The bar's swipe distances, in points.
public enum BarSwipe {
    /// Sideways this far skips.
    public static let skipAt = 56.0
    /// Up this far opens the player.
    public static let openAt = 28.0
    /// A flick at least this fast, in points per second, acts at any distance.
    public static let fling = 700.0
    /// How much of the finger's travel the contents lean with.
    public static let lean = 0.3
    /// How far a finger moves before a drag is taken as one.
    public static let slop = 8.0
}

/// How far into the song playback is, from 0 to 1; 0 when the length is not known.
public func fractionAt(positionMs: Int64, durationMs: Int64) -> Double {
    durationMs > 0 ? min(1, max(0, Double(positionMs) / Double(durationMs))) : 0
}
