import Foundation

/// The tempo everything is paced against: at this many beats a minute the background moves at
/// its base speed.
public let BaseBpm: Float = 120

private let TwoPi = Float.pi * 2

// Every slow wobble in the composite repeats after this long in `t`, so time can wrap here
// without a jump.
private let TimeWrap = Float.pi * 40

/// The tempo to pace by: the song's own when it has one and that is wanted, otherwise the base.
/// Odd tag values are held to a sensible range.
public func paceBpm(_ bpm: Int?, useBpm: Bool) -> Float {
    if useBpm, let bpm, bpm > 0 { return Float(bpm).clamped(40, 240) }
    return BaseBpm
}

/// How far one drawn frame moves things: k = (BPM / 120) x (60 / frame limit), so a slow song
/// drifts slower and the speed does not depend on the frame rate.
public func frameFactor(_ bpm: Float, _ fpsLimit: Float) -> Float { (bpm / BaseBpm) * (60 / fpsLimit) }

/// The moving values behind the background, advanced one drawn frame at a time.
public final class WashMotion {
    public private(set) var time: Float = 0
    /// The phase the warp's dividers swing on.
    public private(set) var warpPhase: Float = 0
    /// The slow global rotation, and which way it is turning.
    public private(set) var rotation: Float = 0
    public private(set) var direction: Float = 1
    /// The final pass's own slowly growing turn, in radians.
    public private(set) var turn: Float = 0
    /// The breathing swell's phase.
    public private(set) var breathPhase: Float = 0
    /// Extra spin from beats, which fades by 1 a second.
    public private(set) var pulse: Float = 0

    public init() {}

    /// The breathing scale, 0.9 to 1.1.
    public var breathing: Float { 1 + 0.1 * sin(breathPhase) }

    /// How much the pulse speeds up the rotation, up to 10 times.
    public var pulseBoost: Float { min(1 + pulse, 10) }

    /// One drawn frame: k from `frameFactor`, the tempo, and the seconds since the last frame.
    public func step(_ k: Float, _ bpm: Float, _ seconds: Float) {
        time = (time + 0.016 * k).truncatingRemainder(dividingBy: TimeWrap)
        warpPhase = (warpPhase + 0.016 * k * (bpm / BaseBpm).clamped(1, 2)).truncatingRemainder(dividingBy: TwoPi)
        rotation += 0.001 * k * breathing * direction * pulseBoost
        // Past a full turn either way, it turns back.
        if rotation > TwoPi { direction = -1 } else if rotation < -TwoPi { direction = 1 }
        turn = (turn + 0.002 * k).truncatingRemainder(dividingBy: TwoPi)
        breathPhase = (breathPhase + 0.016 * k * k / BaseBpm).truncatingRemainder(dividingBy: TwoPi)
        pulse = max(pulse - seconds, 0)
    }

    public func beat() {
        pulse += 2
    }
}

/// What the background can be doing, for its frame rate.
public enum WashVisibility: Sendable {
    case focused, unfocused, hidden
}

/// The frame rate the background aims for: the set limit while in view and focused (at most 30
/// with low power mode on), 10 behind another window, and none while hidden.
public func targetFps(_ visibility: WashVisibility, _ limit: Int, powerSave: Bool) -> Float {
    switch visibility {
    case .focused: Float(powerSave ? min(limit, 30) : limit)
    case .unfocused: 10
    case .hidden: 0
    }
}

/// The frame limit in use. A change eases in by 8% of the gap each frame rather than snapping.
public final class FrameRate {
    public private(set) var limit: Float

    public init(_ initial: Float) {
        limit = initial
    }

    @discardableResult
    public func ease(_ target: Float) -> Float {
        if target <= 0 { return limit }
        limit += (target - limit) * 0.08
        if abs(target - limit) < 0.01 { limit = target }
        return limit
    }
}

/// Whether enough time has passed since the last drawn frame to draw another under this limit.
public func frameDue(_ elapsedNanos: Int, _ limit: Float) -> Bool {
    limit > 0 && elapsedNanos >= Int(1_000_000_000.0 / Double(limit) * 0.8)
}

/// How many frames' worth of time a gap is, at this limit; held to 3 so a pause never makes
/// things leap.
public func framesElapsed(_ elapsedNanos: Int, _ limit: Float) -> Float {
    Float(Double(elapsedNanos) / 1_000_000_000.0 * Double(limit)).clamped(0.5, 3)
}

/// The classic mesh at full speed (while music plays): the color under any one pixel changes by
/// about a level of brightness in a 30th of a second, which no eye picks out as a step.
public let meshFullFps = 30

/// The classic mesh moving at `pace` (1 while music plays) needs this many frames a second: 30
/// at full speed, fewer as it slows, never under 10.
public func meshFps(_ pace: Float) -> Double {
    min(max(Double(meshFullFps) * Double(pace), 10), Double(meshFullFps))
}
