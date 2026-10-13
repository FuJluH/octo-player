import Foundation

// Crossfeed for headphones: each ear also hears a little of the other channel, softened by a
// low-pass, as it would from a pair of speakers in a room. One low-pass runs on the difference
// between the two channels, so a sound that is the same on both sides passes through exactly.

/// A named crossfeed strength, or one set by hand.
public enum CrossfeedPreset: String, Codable, Sendable, CaseIterable {
    case natural = "Natural", chuMoy = "ChuMoy", janMeier = "JanMeier", custom = "Custom"

    /// The cut frequency and feed level a named preset stands for; nil for Custom.
    public var values: (cutHz: Int, feedDb: Double)? {
        switch self {
        case .natural: (700, 4.5)
        case .chuMoy: (700, 6)
        case .janMeier: (650, 9.5)
        case .custom: nil
        }
    }

    public var label: String {
        switch self {
        case .natural: "Natural"
        case .chuMoy: "Chu Moy"
        case .janMeier: "Jan Meier"
        case .custom: "Custom"
        }
    }

    public var detail: String {
        switch self {
        case .natural: "The most blend of the three, close to speakers in a room."
        case .chuMoy: "A middle blend: a higher feed level, so a lighter effect."
        case .janMeier: "The lightest blend: the highest feed level changes the music least."
        case .custom: "Set the blend yourself."
        }
    }
}

/// The crossfeed settings of one output. Off by default. `cutHz` and `feedDb` are Custom's own
/// values; a named preset plays its own. Stored with the same field names as the other apps, and
/// without the fields that hold their usual value.
public struct Crossfeed: Codable, Sendable, Equatable {
    public static let cutRange = 300...2_000
    public static let feedRange = 1.0...15.0

    public var on = false
    public var preset: CrossfeedPreset = .natural
    public var cutHz = 700
    public var feedDb = 4.5

    public init(on: Bool = false, preset: CrossfeedPreset = .natural, cutHz: Int = 700, feedDb: Double = 4.5) {
        self.on = on
        self.preset = preset
        self.cutHz = cutHz
        self.feedDb = feedDb
    }

    /// The cut frequency that plays, held to the range.
    public var effectiveCutHz: Int { min(max(preset.values?.cutHz ?? cutHz, Self.cutRange.lowerBound), Self.cutRange.upperBound) }

    /// The feed level that plays, held to the range.
    public var effectiveFeedDb: Double {
        let db = preset.values?.feedDb ?? feedDb
        return db.isFinite ? min(max(db, Self.feedRange.lowerBound), Self.feedRange.upperBound) : 4.5
    }

    enum CodingKeys: String, CodingKey { case on, preset, cutHz, feedDb }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let d = Crossfeed()
        on = try c.decodeIfPresent(Bool.self, forKey: .on) ?? d.on
        // In a backup, a preset this app does not know takes the default.
        preset = try c.choice(CrossfeedPreset.self, forKey: .preset, decoder) ?? d.preset
        cutHz = try c.decodeIfPresent(Int.self, forKey: .cutHz) ?? d.cutHz
        feedDb = try c.decodeIfPresent(Double.self, forKey: .feedDb) ?? d.feedDb
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        let d = Crossfeed()
        if on != d.on { try c.encode(on, forKey: .on) }
        if preset != d.preset { try c.encode(preset, forKey: .preset) }
        if cutHz != d.cutHz { try c.encode(cutHz, forKey: .cutHz) }
        if feedDb != d.feedDb { try c.encode(feedDb, forKey: .feedDb) }
    }
}

/// How the crossfeed reads on the Sound page, and its sliders.
public enum CrossfeedWords {
    /// What crossfeed does, in a line.
    public static let about = "Blends a little of each side into the other, like speakers in a room. Eases listening fatigue on headphones."
    /// Why the card stays off on an output with no headphones.
    public static let headphonesOnly = "Crossfeed is for headphones."
    /// Why it rests while mono is on.
    public static let monoOn = "Off while Mono is on: both ears already hear the same sound."
    /// What the two sliders of Custom do.
    public static let customHelp = "Cut: below it, sound blends across. Feed level: how far under the near side the far side plays; higher is lighter."

    /// A feed level as a reading: 4.5 dB, 6 dB.
    public static func readFeed(_ db: Double) -> String {
        let tenths = SoundEdits.roundHalfUp(abs(db) * 10)
        return tenths % 10 == 0 ? "\(tenths / 10) dB" : "\(tenths / 10).\(tenths % 10) dB"
    }

    /// The values a preset plays at, like "700 Hz, 4.5 dB".
    public static func values(_ crossfeed: Crossfeed) -> String {
        "\(SoundEdits.readHz(Double(crossfeed.effectiveCutHz))), \(readFeed(crossfeed.effectiveFeedDb))"
    }

    /// The cut frequency on a log scale across its range.
    public static func cutFraction(_ hz: Double) -> Double {
        let low = Double(Crossfeed.cutRange.lowerBound), high = Double(Crossfeed.cutRange.upperBound)
        return log(min(max(hz, low), high) / low) / log(high / low)
    }

    public static func cutValue(_ fraction: Double) -> Double {
        let low = Double(Crossfeed.cutRange.lowerBound), high = Double(Crossfeed.cutRange.upperBound)
        return low * pow(high / low, min(max(fraction, 0), 1))
    }
}

/// The crossfeed's coefficients at one sample rate. A one-pole low-pass at the cut frequency
/// runs on the difference between the channels; at low frequencies it moves each side
/// `feedDb` under its own level across to the other ear, and above the cut ever less.
public struct CrossfeedCoefficients: Sendable, Equatable {
    /// How much of the new difference joins the low-pass each frame.
    public var gain: Double
    /// How much of the low-pass's last value it keeps.
    public var pole: Double

    public init(gain: Double, pole: Double) {
        self.gain = gain
        self.pole = pole
    }

    /// Passes both channels through untouched.
    public static let none = CrossfeedCoefficients(gain: 0, pole: 0)

    public init(cutHz: Double, feedDb: Double, sampleRate: Double) {
        pole = exp(-2 * Double.pi * cutHz / sampleRate)
        let feed = pow(10, -feedDb / 20)
        gain = feed / (1 + feed) * (1 - pole)
    }

    public init(_ crossfeed: Crossfeed, sampleRate: Double) {
        self.init(cutHz: Double(crossfeed.effectiveCutHz), feedDb: crossfeed.effectiveFeedDb, sampleRate: sampleRate)
    }

    /// How one side's sound reaches its own ear (`direct`) and the other ear (`cross`) at `hz`,
    /// as magnitudes where 1 is unchanged.
    public func response(at hz: Double, sampleRate: Double) -> (direct: Double, cross: Double) {
        let w = 2 * Double.pi * hz / sampleRate
        // The low-pass, gain / (1 - pole e^-jw), as real and imaginary parts.
        let denRe = 1 - pole * cos(w), denIm = pole * sin(w)
        let den = denRe * denRe + denIm * denIm
        let re = gain * denRe / den, im = -gain * denIm / den
        let direct = ((1 - re) * (1 - re) + im * im).squareRoot()
        return (direct, (re * re + im * im).squareRoot())
    }
}

/// The crossfeed's memory for one stereo stream: the low-passed difference between the
/// channels. A plain value, so running it makes nothing new.
public struct CrossfeedFilter: Sendable {
    private var difference = 0.0

    public init() {}

    /// One frame in, one frame out.
    @inline(__always)
    public mutating func process(_ left: Double, _ right: Double, _ k: CrossfeedCoefficients) -> (left: Double, right: Double) {
        difference = k.gain * (right - left) + k.pole * difference
        return (left + difference, right - difference)
    }

    /// Runs `frames` frames of two channels in place.
    public mutating func process(_ left: UnsafeMutablePointer<Float>, _ right: UnsafeMutablePointer<Float>, frames: Int,
                                 _ k: CrossfeedCoefficients) {
        for i in 0..<frames {
            let out = process(Double(left[i]), Double(right[i]), k)
            left[i] = Float(out.left)
            right[i] = Float(out.right)
        }
        flushDenormals()
    }

    /// Settles a value too small to hear to zero, so quiet passages do not slow the filter down,
    /// and a sound the same on both sides passes through exactly once the difference has died away.
    public mutating func flushDenormals() {
        if abs(difference) < 1e-25 { difference = 0 }
    }

    /// Forgets the filter's memory.
    public mutating func clear() { difference = 0 }
}
