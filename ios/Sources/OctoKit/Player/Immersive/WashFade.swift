import Foundation

/// How long one cover takes to become the next, and the quicker fade used when covers change
/// within a moment of each other (skipping through).
public let CoverFadeMs = 500
public let QuickCoverFadeMs = 300
public let QuickChangeWindowMs = 1_500

/// The fade for a cover arriving now: none for the very first, quick when the last change was
/// under 1.5 s ago, otherwise the full one.
public func coverFadeMs(_ lastChangeMs: Int?, _ nowMs: Int) -> Int {
    guard let lastChangeMs else { return 0 }
    return nowMs - lastChangeMs < QuickChangeWindowMs ? QuickCoverFadeMs : CoverFadeMs
}

/// Slow at both ends, quick through the middle.
public func easeInOutCubic(_ x: Float) -> Float {
    let t = x.clamped(0, 1)
    if t < 0.5 { return 4 * t * t * t }
    let u = -2 * t + 2
    return 1 - u * u * u / 2
}

/// The fade between the old cover and the new one, run by the frame clock.
public final class CoverFade {
    private var durationMs = 0
    private var elapsedMs: Float = 0
    private var lastChangeMs: Int?

    public init() {}

    /// How far the new cover has come in, 0 to 1, before easing.
    public var progress: Float { durationMs <= 0 ? 1 : (elapsedMs / Float(durationMs)).clamped(0, 1) }

    /// The mix of old and new the drawing uses.
    public var mix: Float { easeInOutCubic(progress) }

    public var running: Bool { progress < 1 }

    /// A new cover has arrived at this moment; returns the fade's length.
    @discardableResult
    public func start(_ nowMs: Int) -> Int {
        durationMs = coverFadeMs(lastChangeMs, nowMs)
        elapsedMs = 0
        lastChangeMs = nowMs
        return durationMs
    }

    public func advance(_ ms: Float) {
        elapsedMs += ms
    }
}
