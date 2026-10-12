import Foundation

/// How fast music can play, from half speed to double.
public let slowestSpeed: Float = 0.5
public let fastestSpeed: Float = 2.0

/// Speeds the slider settles on when the finger lands near them.
public let speedDetents: [Float] = [0.75, 1, 1.25, 1.5]

/// How near a detent the finger has to be for the slider to settle on it.
private let detentPull: Float = 0.04

/// Between detents the speed moves in steps this size.
private let speedStep: Float = 0.05

/// How far the pitch can be moved either way, in semitones.
public let pitchRangeSemitones = 6

/// Rounds halves up, as the other apps do.
@inline(__always) func roundHalfUpToInt(_ x: Float) -> Int { Int((x + 0.5).rounded(.down)) }

/// A speed the player can use: inside the range, on a 0.05 step, and pulled onto a detent when
/// close to one, so 1.0 is easy to find again.
public func snapSpeed(_ raw: Float) -> Float {
    let inRange = min(max(raw, slowestSpeed), fastestSpeed)
    if let detent = speedDetents.first(where: { abs($0 - inRange) <= detentPull }) { return detent }
    let stepped = Float(roundHalfUpToInt(inRange / speedStep)) * speedStep
    // Rounded to two places, so 1.1500001 is saved and shown as 1.15.
    return min(max(Float(roundHalfUpToInt(stepped * 100)) / 100, slowestSpeed), fastestSpeed)
}

/// Where a speed sits along the slider, 0 at the slowest and 1 at the fastest.
public func speedFraction(_ speed: Float) -> Float {
    min(max((speed - slowestSpeed) / (fastestSpeed - slowestSpeed), 0), 1)
}

/// The speed at a point along the slider.
public func speedAt(_ fraction: Float) -> Float {
    snapSpeed(slowestSpeed + min(max(fraction, 0), 1) * (fastestSpeed - slowestSpeed))
}

/// The pitch shift at a point along its slider, in whole semitones.
public func semitonesAt(_ fraction: Float) -> Int {
    roundHalfUpToInt(min(max(fraction, 0), 1) * 2 * Float(pitchRangeSemitones)) - pitchRangeSemitones
}

public func semitonesFraction(_ semitones: Int) -> Float {
    Float(min(max(semitones, -pitchRangeSemitones), pitchRangeSemitones) + pitchRangeSemitones) / (2 * Float(pitchRangeSemitones))
}

/// What the player is told: the speed, and the pitch as a multiple of the original. With "keep
/// pitch" on the voice stays where it was; with it off the pitch rises and falls with the
/// speed, like a record. Semitones move it further either way.
public struct Pace: Sendable, Equatable {
    public var speed: Float
    public var pitch: Float

    public init(speed: Float, pitch: Float) {
        self.speed = speed
        self.pitch = pitch
    }
}

public func paceOf(speed: Float, keepPitch: Bool, semitones: Int) -> Pace {
    let clean = snapSpeed(speed)
    let shift = powf(2, Float(min(max(semitones, -pitchRangeSemitones), pitchRangeSemitones)) / 12)
    return Pace(speed: clean, pitch: (keepPitch ? 1 : clean) * shift)
}

/// A speed as the player shows it, like "1.25x" or "2x".
public func speedLabel(_ speed: Float) -> String {
    let hundredths = roundHalfUpToInt(speed * 100)
    let whole = hundredths / 100
    let part = hundredths % 100
    let text: String
    if part == 0 {
        text = "\(whole)"
    } else if part % 10 == 0 {
        text = "\(whole).\(part / 10)"
    } else {
        text = "\(whole)." + (part < 10 ? "0\(part)" : "\(part)")
    }
    return "\(text)x"
}

/// A pitch shift as its slider shows it, like "+2 st" or "0 st".
public func semitonesLabel(_ semitones: Int) -> String { semitones > 0 ? "+\(semitones) st" : "\(semitones) st" }
