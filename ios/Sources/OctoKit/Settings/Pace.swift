import Foundation

/// What the player is told: the speed, and the pitch as a multiple of the original. With "keep
/// pitch" on the voice stays where it was; with it off the pitch rises and falls with the speed,
/// like a record. Semitones move it further either way.
public struct Pace: Sendable, Equatable {
    public var speed: Float
    public var pitch: Float

    public init(speed: Float, pitch: Float) {
        self.speed = speed
        self.pitch = pitch
    }

    /// How fast music can play, from half speed to double.
    public static let slowestSpeed: Float = 0.5
    public static let fastestSpeed: Float = 2.0

    /// Speeds the slider settles on when the finger lands near them.
    public static let speedDetents: [Float] = [0.75, 1, 1.25, 1.5]

    /// How near a detent the finger has to be for the slider to settle on it.
    static let detentPull: Float = 0.04

    /// Between detents the speed moves in steps this size.
    static let speedStep: Float = 0.05

    /// How far the pitch can be moved either way, in semitones.
    public static let pitchRangeSemitones = 6

    /// A whole number the way the other apps round: halves go up.
    static func roundHalfUp(_ value: Float) -> Int { Int((value + 0.5).rounded(.down)) }

    /// A speed the player can use: inside the range, on a 0.05 step, and pulled onto a detent
    /// when close to one, so 1.0 is easy to find again.
    public static func snapSpeed(_ raw: Float) -> Float {
        let inRange = min(max(raw, slowestSpeed), fastestSpeed)
        if let detent = speedDetents.first(where: { abs($0 - inRange) <= detentPull }) { return detent }
        let stepped = Float(roundHalfUp(inRange / speedStep)) * speedStep
        // Rounded to two places, so 1.1500001 is saved and shown as 1.15.
        return min(max(Float(roundHalfUp(stepped * 100)) / 100, slowestSpeed), fastestSpeed)
    }

    /// Where a speed sits along the slider, 0 at the slowest and 1 at the fastest.
    public static func speedFraction(_ speed: Float) -> Float {
        min(max((speed - slowestSpeed) / (fastestSpeed - slowestSpeed), 0), 1)
    }

    /// The speed at a point along the slider.
    public static func speedAt(_ fraction: Float) -> Float {
        snapSpeed(slowestSpeed + min(max(fraction, 0), 1) * (fastestSpeed - slowestSpeed))
    }

    /// The pitch shift at a point along its slider, in whole semitones.
    public static func semitonesAt(_ fraction: Float) -> Int {
        roundHalfUp(min(max(fraction, 0), 1) * Float(2 * pitchRangeSemitones)) - pitchRangeSemitones
    }

    public static func semitonesFraction(_ semitones: Int) -> Float {
        Float(min(max(semitones, -pitchRangeSemitones), pitchRangeSemitones) + pitchRangeSemitones) / Float(2 * pitchRangeSemitones)
    }

    public static func of(speed: Float, keepPitch: Bool, semitones: Int) -> Pace {
        let clean = snapSpeed(speed)
        let shift = Float(pow(2.0, Double(min(max(semitones, -pitchRangeSemitones), pitchRangeSemitones)) / 12.0))
        return Pace(speed: clean, pitch: (keepPitch ? 1 : clean) * shift)
    }

    /// A speed as the player shows it, like "1.25x" or "2x".
    public static func speedLabel(_ speed: Float) -> String {
        let hundredths = roundHalfUp(speed * 100)
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
        return text + "x"
    }

    /// A pitch shift as its slider shows it, like "+2 st" or "0 st".
    public static func semitonesLabel(_ semitones: Int) -> String {
        semitones > 0 ? "+\(semitones) st" : "\(semitones) st"
    }
}
