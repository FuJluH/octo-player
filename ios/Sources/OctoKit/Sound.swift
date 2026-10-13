import Foundation

// How the sound is shaped: the equalizer, the level, loudness between songs, crossfeed, the
// limiter and balance. The same model and rules as the other apps.

/// A bump or dip around one frequency, or a lift or cut of everything below or above one.
public enum FilterType: String, Codable, Sendable, CaseIterable {
    case peak = "Peak", lowShelf = "LowShelf", highShelf = "HighShelf"
}

/// One filter on the curve. Stored with the same field names as the other apps, and without
/// the fields that hold their usual value.
public struct EqFilter: Codable, Sendable, Equatable, Identifiable {
    public var id = UUID()
    public var type: FilterType
    public var frequency: Double
    public var gainDb: Double
    public var q: Double
    public var enabled: Bool

    public init(type: FilterType = .peak, frequency: Double, gainDb: Double, q: Double = graphicQ, enabled: Bool = true) {
        self.type = type
        self.frequency = frequency
        self.gainDb = gainDb
        self.q = q
        self.enabled = enabled
    }

    enum CodingKeys: String, CodingKey { case type, frequency, gainDb, q, enabled }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        // In a backup, a shape this app does not know reads as a peak.
        type = try c.choice(FilterType.self, forKey: .type, decoder) ?? .peak
        frequency = try c.decode(Double.self, forKey: .frequency)
        gainDb = try c.decode(Double.self, forKey: .gainDb)
        q = try c.decodeIfPresent(Double.self, forKey: .q) ?? graphicQ
        enabled = try c.decodeIfPresent(Bool.self, forKey: .enabled) ?? true
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        if type != .peak { try c.encode(type, forKey: .type) }
        try c.encode(frequency, forKey: .frequency)
        try c.encode(gainDb, forKey: .gainDb)
        if q != graphicQ { try c.encode(q, forKey: .q) }
        if !enabled { try c.encode(enabled, forKey: .enabled) }
    }

    public static func == (a: EqFilter, b: EqFilter) -> Bool {
        a.type == b.type && a.frequency == b.frequency && a.gainDb == b.gainDb && a.q == b.q && a.enabled == b.enabled
    }
}

/// Set in a decoder's user info, a stored choice this app does not know reads as missing, so it
/// takes its default, as a backup reads them. Without it such a choice fails to read.
public let unknownChoicesTakeDefaults = CodingUserInfoKey(rawValue: "octo.unknownChoicesTakeDefaults")!

extension KeyedDecodingContainer {
    /// A stored choice by its name.
    func choice<T: Decodable & RawRepresentable>(_ type: T.Type, forKey key: Key, _ decoder: Decoder) throws -> T?
        where T.RawValue == String {
        if decoder.userInfo[unknownChoicesTakeDefaults] as? Bool == true {
            return try decodeIfPresent(String.self, forKey: key).flatMap(T.init(rawValue:))
        }
        return try decodeIfPresent(T.self, forKey: key)
    }
}

/// Ten sliders at fixed frequencies, or filters moved freely on the curve.
public enum EqMode: String, Codable, Sendable { case graphic = "Graphic", parametric = "Parametric" }

/// Evening out loudness between songs: off, per song, per album, or per album only while an
/// album plays in order.
public enum ReplayGainMode: String, Codable, Sendable, CaseIterable {
    case off = "Off", track = "Track", album = "Album", smart = "Smart"
}

/// The ten standard octave bands, in hertz.
public let graphicBands: [Double] = [31, 62, 125, 250, 500, 1_000, 2_000, 4_000, 8_000, 16_000]

/// The width of one octave band.
public let graphicQ = 1.41

/// How far a slider goes either way, in decibels.
public let gainRangeDb = 12.0

/// A correction for one model of headphones, made from its measurements.
public struct HeadphoneCorrection: Codable, Sendable, Equatable {
    public var name: String
    /// Who measured them, for the credit line.
    public var source: String
    public var preampDb: Double
    public var filters: [EqFilter]

    public init(name: String, source: String, preampDb: Double, filters: [EqFilter]) {
        self.name = name
        self.source = source
        self.preampDb = preampDb
        self.filters = filters
    }
}

/// Everything that shapes the sound on one output. Stored with the same field names as the other
/// apps; a field left out reads as its default, and a field at its default is left out. So a
/// stored set with no "preset" is "Flat", while `"preset": null` is a curve made by hand.
public struct SoundSettings: Codable, Sendable, Equatable {
    public var eqEnabled = false
    public var mode: EqMode = .graphic
    public var graphicGains: [Double] = Array(repeating: 0, count: graphicBands.count)
    public var filters: [EqFilter] = []
    /// The preset the curve came from, until it is changed by hand.
    public var preset: String? = "Flat"
    public var preampDb = 0.0
    /// Lowers the level by the curve's highest boost, so boosting never clips.
    public var autoPreamp = true
    public var correction: HeadphoneCorrection?
    public var replayGain: ReplayGainMode = .off
    public var replayGainPreampDb = 0.0
    /// For songs with no loudness tags.
    public var replayGainFallbackDb = 0.0
    public var preventClipping = true
    /// Catches any peak that would still clip, just below full scale.
    public var limiter = true
    /// From -1 (all left) to 1 (all right).
    public var balance = 0.0
    public var mono = false
    /// Blends a little of each side into the other, for headphones.
    public var crossfeed = Crossfeed()

    public init() {}

    enum CodingKeys: String, CodingKey {
        case eqEnabled, mode, graphicGains, filters, preset, preampDb, autoPreamp, correction, replayGain
        case replayGainPreampDb, replayGainFallbackDb, preventClipping, limiter, balance, mono, crossfeed
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        let d = SoundSettings()
        eqEnabled = try c.decodeIfPresent(Bool.self, forKey: .eqEnabled) ?? d.eqEnabled
        // In a backup, a mode or loudness choice this app does not know takes its default.
        mode = try c.choice(EqMode.self, forKey: .mode, decoder) ?? d.mode
        graphicGains = try c.decodeIfPresent([Double].self, forKey: .graphicGains) ?? d.graphicGains
        filters = try c.decodeIfPresent([EqFilter].self, forKey: .filters) ?? d.filters
        preset = c.contains(.preset) ? try c.decodeIfPresent(String.self, forKey: .preset) : d.preset
        preampDb = try c.decodeIfPresent(Double.self, forKey: .preampDb) ?? d.preampDb
        autoPreamp = try c.decodeIfPresent(Bool.self, forKey: .autoPreamp) ?? d.autoPreamp
        correction = try c.decodeIfPresent(HeadphoneCorrection.self, forKey: .correction)
        replayGain = try c.choice(ReplayGainMode.self, forKey: .replayGain, decoder) ?? d.replayGain
        replayGainPreampDb = try c.decodeIfPresent(Double.self, forKey: .replayGainPreampDb) ?? d.replayGainPreampDb
        replayGainFallbackDb = try c.decodeIfPresent(Double.self, forKey: .replayGainFallbackDb) ?? d.replayGainFallbackDb
        preventClipping = try c.decodeIfPresent(Bool.self, forKey: .preventClipping) ?? d.preventClipping
        limiter = try c.decodeIfPresent(Bool.self, forKey: .limiter) ?? d.limiter
        balance = try c.decodeIfPresent(Double.self, forKey: .balance) ?? d.balance
        mono = try c.decodeIfPresent(Bool.self, forKey: .mono) ?? d.mono
        crossfeed = try c.decodeIfPresent(Crossfeed.self, forKey: .crossfeed) ?? d.crossfeed
    }

    public func encode(to encoder: Encoder) throws {
        var c = encoder.container(keyedBy: CodingKeys.self)
        let d = SoundSettings()
        if eqEnabled != d.eqEnabled { try c.encode(eqEnabled, forKey: .eqEnabled) }
        if mode != d.mode { try c.encode(mode, forKey: .mode) }
        if graphicGains != d.graphicGains { try c.encode(graphicGains, forKey: .graphicGains) }
        if filters != d.filters { try c.encode(filters, forKey: .filters) }
        if preset != d.preset {
            if let preset { try c.encode(preset, forKey: .preset) } else { try c.encodeNil(forKey: .preset) }
        }
        if preampDb != d.preampDb { try c.encode(preampDb, forKey: .preampDb) }
        if autoPreamp != d.autoPreamp { try c.encode(autoPreamp, forKey: .autoPreamp) }
        if let correction { try c.encode(correction, forKey: .correction) }
        if replayGain != d.replayGain { try c.encode(replayGain, forKey: .replayGain) }
        if replayGainPreampDb != d.replayGainPreampDb { try c.encode(replayGainPreampDb, forKey: .replayGainPreampDb) }
        if replayGainFallbackDb != d.replayGainFallbackDb { try c.encode(replayGainFallbackDb, forKey: .replayGainFallbackDb) }
        if preventClipping != d.preventClipping { try c.encode(preventClipping, forKey: .preventClipping) }
        if limiter != d.limiter { try c.encode(limiter, forKey: .limiter) }
        if balance != d.balance { try c.encode(balance, forKey: .balance) }
        if mono != d.mono { try c.encode(mono, forKey: .mono) }
        if crossfeed != d.crossfeed { try c.encode(crossfeed, forKey: .crossfeed) }
    }

    /// The filters the equalizer applies now: the headphone correction first, then the
    /// listener's own curve.
    public func activeFilters() -> [EqFilter] {
        guard eqEnabled else { return [] }
        let own: [EqFilter] = switch mode {
        case .graphic: zip(graphicBands, graphicGains).map { EqFilter(type: .peak, frequency: $0, gainDb: $1) }
        case .parametric: filters
        }
        return ((correction?.filters ?? []) + own).filter { $0.enabled && $0.gainDb != 0 }
    }

    /// The level change before the filters, in decibels: set by hand (with a correction's own
    /// preamp), or just enough to take back the curve's highest boost.
    public func effectivePreampDb(sampleRate: Double = 48_000) -> Double {
        guard eqEnabled else { return 0 }
        if autoPreamp { return -max(0, ResponseCurve.peakDb(activeFilters(), sampleRate: sampleRate)) }
        return (correction?.preampDb ?? 0) + preampDb
    }
}

/// A named curve for the ten bands.
public struct EqPreset: Codable, Sendable, Equatable {
    public var name: String
    public var gains: [Double]

    public init(name: String, gains: [Double]) {
        self.name = name
        self.gains = gains
    }
}

/// The built-in curves.
public let eqPresets: [EqPreset] = [
    EqPreset(name: "Flat", gains: [0, 0, 0, 0, 0, 0, 0, 0, 0, 0]),
    EqPreset(name: "Bass Boost", gains: [6, 5.5, 4.5, 2.5, 0.5, 0, 0, 0, 0, 0]),
    EqPreset(name: "Bass Reducer", gains: [-6, -5, -4, -2.5, -1, 0, 0, 0, 0, 0]),
    EqPreset(name: "Treble Boost", gains: [0, 0, 0, 0, 0, 0.5, 1.5, 3.5, 5, 6]),
    EqPreset(name: "Treble Reducer", gains: [0, 0, 0, 0, 0, -0.5, -1.5, -3.5, -5, -6]),
    EqPreset(name: "Vocal", gains: [-2, -2, -1, 0.5, 2, 3.5, 3.5, 2.5, 1, 0]),
    EqPreset(name: "Rock", gains: [5, 5, 4, 3, 0.5, -0.5, 1.5, 3, 4, 5]),
    EqPreset(name: "Pop", gains: [-1, -1, 0.5, 2, 3.5, 4.5, 2.5, 1, -1, -2]),
    EqPreset(name: "Jazz", gains: [4, 4, 3, 2, -0.5, -1.5, 0.5, 2, 4, 5]),
    EqPreset(name: "Classical", gains: [5, 5, 4, 2.5, 0, -1.5, 1.5, 4, 4, 4]),
    EqPreset(name: "Electronic", gains: [6, 6, 2.5, 0, 1, 2, 3, 4, 2, 1]),
    EqPreset(name: "Hip-Hop", gains: [5, 5, 4, 3, 1.5, 0, 0.5, 1, 2, 3]),
    EqPreset(name: "Metal", gains: [4, 4, 2.5, 1.5, 5.5, 8.5, 5.5, 3, 1, 0]),
    EqPreset(name: "Folk", gains: [3, 3, 1.5, 0, 0, 0, 1, 2, 0, -1]),
    EqPreset(name: "Acoustic", gains: [3, 3, 2.5, 1, 1, 0.5, 1.5, 2.5, 2.5, 1.5]),
    EqPreset(name: "Loudness", gains: [6, 5, 3, 1, 0, 0, 0, 1, 3, 4]),
    EqPreset(name: "Late Night", gains: [-4, -3, -1.5, 0, 0.5, 1, 2, 1.5, 0, -1]),
    EqPreset(name: "Spoken Word", gains: [-6, -5, -3, -1, 1, 2.5, 3.5, 2.5, 0, -2]),
    EqPreset(name: "Small Speakers", gains: [-6, -3, 2, 3, 1.5, 0, 0, 1.5, 2.5, 1]),
]

/// One filter's coefficients, normalised so a0 is 1.
public struct Coefficients: Sendable, Equatable {
    public var b0, b1, b2, a1, a2: Double
}

/// The standard formulas for these filters (the Audio EQ Cookbook).
public func coefficients(_ filter: EqFilter, sampleRate: Double) -> Coefficients {
    let a = pow(10, filter.gainDb / 40)
    let w0 = 2 * Double.pi * filter.frequency / sampleRate
    let c = cos(w0)
    let alpha = sin(w0) / (2 * filter.q)
    func normalise(_ b0: Double, _ b1: Double, _ b2: Double, _ a0: Double, _ a1: Double, _ a2: Double) -> Coefficients {
        Coefficients(b0: b0 / a0, b1: b1 / a0, b2: b2 / a0, a1: a1 / a0, a2: a2 / a0)
    }
    switch filter.type {
    case .peak:
        return normalise(1 + alpha * a, -2 * c, 1 - alpha * a, 1 + alpha / a, -2 * c, 1 - alpha / a)
    case .lowShelf:
        let s = 2 * sqrt(a) * alpha
        return normalise(a * ((a + 1) - (a - 1) * c + s), 2 * a * ((a - 1) - (a + 1) * c), a * ((a + 1) - (a - 1) * c - s),
                         (a + 1) + (a - 1) * c + s, -2 * ((a - 1) + (a + 1) * c), (a + 1) + (a - 1) * c - s)
    case .highShelf:
        let s = 2 * sqrt(a) * alpha
        return normalise(a * ((a + 1) + (a - 1) * c + s), -2 * a * ((a - 1) + (a + 1) * c), a * ((a + 1) + (a - 1) * c - s),
                         (a + 1) - (a - 1) * c + s, 2 * ((a - 1) - (a + 1) * c), (a + 1) - (a - 1) * c - s)
    }
}

/// Filters at or above this share of the sample rate are left out: the formulas bend out of
/// shape that close to the top of the range.
public let highestBandShare = 0.45

/// How filters change the level at each frequency, for drawing the curve and for keeping
/// boosts from clipping.
public enum ResponseCurve {
    /// Log-spaced frequencies from 20 Hz to 20 kHz.
    public static func frequencies(points: Int = 256) -> [Double] {
        (0..<points).map { 20 * pow(1_000, Double($0) / Double(points - 1)) }
    }

    /// The change in decibels at one frequency.
    public static func gainDb(_ filters: [EqFilter], at frequency: Double, sampleRate: Double = 48_000) -> Double {
        filters.filter { $0.frequency < sampleRate * highestBandShare }
            .reduce(0) { $0 + magnitudeDb(coefficients($1, sampleRate: sampleRate), frequency, sampleRate) }
    }

    public static func curve(_ filters: [EqFilter], points: Int = 256, sampleRate: Double = 48_000) -> [Double] {
        frequencies(points: points).map { gainDb(filters, at: $0, sampleRate: sampleRate) }
    }

    /// The highest boost anywhere on the curve.
    public static func peakDb(_ filters: [EqFilter], sampleRate: Double = 48_000) -> Double {
        filters.isEmpty ? 0 : (curve(filters, points: 512, sampleRate: sampleRate).max() ?? 0)
    }

    static func magnitudeDb(_ k: Coefficients, _ frequency: Double, _ sampleRate: Double) -> Double {
        let phi = pow(sin(Double.pi * frequency / sampleRate), 2)
        func part(_ x0: Double, _ x1: Double, _ x2: Double) -> Double {
            pow(x0 + x1 + x2, 2) - 4 * (x0 * x1 + 4 * x0 * x2 + x1 * x2) * phi + 16 * x0 * x2 * phi * phi
        }
        return 10 * log10(part(k.b0, k.b1, k.b2) / part(1, k.a1, k.a2))
    }
}

/// A chain of filters run one after another over one channel's samples, in place. The filters
/// use the transposed direct form II, with their memory in doubles so deep bass and quiet
/// passages stay clean.
public final class FilterBank: @unchecked Sendable {
    public let channels: Int
    private let b0, b1, b2, a1, a2: [Double]
    private var z1: [Double]
    private var z2: [Double]
    public var isEmpty: Bool { b0.isEmpty }
    /// How many filters run.
    public var count: Int { b0.count }

    public init(channels: Int, coefficients: [Coefficients]) {
        self.channels = channels
        b0 = coefficients.map(\.b0)
        b1 = coefficients.map(\.b1)
        b2 = coefficients.map(\.b2)
        a1 = coefficients.map(\.a1)
        a2 = coefficients.map(\.a2)
        z1 = Array(repeating: 0, count: coefficients.count * channels)
        z2 = Array(repeating: 0, count: coefficients.count * channels)
    }

    public convenience init(filters: [EqFilter], sampleRate: Double, channels: Int) {
        self.init(channels: channels, coefficients: filters.filter { $0.frequency < sampleRate * highestBandShare }
            .map { coefficients($0, sampleRate: sampleRate) })
    }

    /// Filters `frames` samples of one channel in place.
    public func process(_ samples: UnsafeMutablePointer<Float>, frames: Int, channel: Int) {
        let count = b0.count
        guard count > 0 else { return }
        let base = channel * count
        for i in 0..<frames {
            var x = Double(samples[i])
            for k in 0..<count {
                let slot = base + k
                let y = b0[k] * x + z1[slot]
                z1[slot] = b1[k] * x - a1[k] * y + z2[slot]
                z2[slot] = b2[k] * x - a2[k] * y
                x = y
            }
            samples[i] = Float(x)
        }
        for slot in base..<(base + count) {
            if abs(z1[slot]) < 1e-25 { z1[slot] = 0 }
            if abs(z2[slot]) < 1e-25 { z2[slot] = 0 }
        }
    }

    /// Carries on from another bank's memory when the filters line up, so a small change to the
    /// curve does not restart them from silence.
    public func continueFrom(_ other: FilterBank) {
        guard other.b0.count == b0.count, other.channels == channels else { return }
        z1 = other.z1
        z2 = other.z2
    }

    /// Forgets the filters' memory.
    public func clear() {
        for i in z1.indices { z1[i] = 0 }
        for i in z2.indices { z2[i] = 0 }
    }
}

/// The coefficients of the filters that run at this sample rate.
public func bandCoefficients(_ filters: [EqFilter], sampleRate: Double) -> [Coefficients] {
    filters.filter { $0.frequency < sampleRate * highestBandShare }.map { coefficients($0, sampleRate: sampleRate) }
}

/// A song's loudness tags: how far to turn it up or down to reach the common level, in
/// decibels, and its highest sample, where 1 is full scale. Any of them can be missing.
public struct ReplayGainInfo: Sendable, Equatable {
    public var trackGain: Double?
    public var trackPeak: Double?
    public var albumGain: Double?
    public var albumPeak: Double?

    public init(trackGain: Double? = nil, trackPeak: Double? = nil, albumGain: Double? = nil, albumPeak: Double? = nil) {
        self.trackGain = trackGain
        self.trackPeak = trackPeak
        self.albumGain = albumGain
        self.albumPeak = albumPeak
    }

    public var hasGain: Bool { trackGain != nil || albumGain != nil }
}

/// What the audio path knows about the song about to play: its tags, and whether it follows a
/// song from the same album.
public struct SongLoudness: Sendable, Equatable {
    public var replayGain: ReplayGainInfo?
    public var followsSameAlbum: Bool

    public init(_ replayGain: ReplayGainInfo?, followsSameAlbum: Bool) {
        self.replayGain = replayGain
        self.followsSameAlbum = followsSameAlbum
    }
}

public enum ReplayGainTags {
    /// The newer loudness tags aim 5 dB quieter than the older ones.
    static let r128ToReplayGainDb = 5.0
    /// Gains past this are a broken tag, not a real song.
    static let largestGainDb = 64.0

    /// Reads the tags from name and value pairs, names in any case. The standard tags win over
    /// the newer R128 ones when a song has both.
    public static func fromTags(_ tags: [(String, String)]) -> ReplayGainInfo? {
        var trackGain: Double?, trackPeak: Double?, albumGain: Double?, albumPeak: Double?
        var r128Track: Double?, r128Album: Double?
        for (name, value) in tags {
            switch name.trimmingCharacters(in: .whitespaces).uppercased() {
            case "REPLAYGAIN_TRACK_GAIN": trackGain = trackGain ?? parseGain(value)
            case "REPLAYGAIN_TRACK_PEAK": trackPeak = trackPeak ?? parsePeak(value)
            case "REPLAYGAIN_ALBUM_GAIN": albumGain = albumGain ?? parseGain(value)
            case "REPLAYGAIN_ALBUM_PEAK": albumPeak = albumPeak ?? parsePeak(value)
            case "R128_TRACK_GAIN": r128Track = r128Track ?? parseR128(value)
            case "R128_ALBUM_GAIN": r128Album = r128Album ?? parseR128(value)
            default: break
            }
        }
        let info = ReplayGainInfo(trackGain: trackGain ?? r128Track, trackPeak: trackPeak, albumGain: albumGain ?? r128Album, albumPeak: albumPeak)
        return info == ReplayGainInfo() ? nil : info
    }

    /// A gain like "-6.54 dB", "+2.1dB" or "-6,54 dB".
    public static func parseGain(_ value: String) -> Double? {
        let text = value.trimmingCharacters(in: .whitespaces)
        let bare = text.lowercased().hasSuffix("db") ? String(text.dropLast(2)) : text
        guard let gain = number(bare.trimmingCharacters(in: .whitespaces)), abs(gain) <= largestGainDb else { return nil }
        return gain
    }

    /// A peak like "0.988251", where 1 is full scale.
    public static func parsePeak(_ value: String) -> Double? {
        guard let peak = number(value.trimmingCharacters(in: .whitespaces)), peak > 0 else { return nil }
        return peak
    }

    /// An R128 gain: whole 256ths of a decibel, measured against a level 5 dB quieter than the
    /// standard tags use.
    public static func parseR128(_ value: String) -> Double? {
        guard let whole = Int(value.trimmingCharacters(in: .whitespaces)) else { return nil }
        let gain = Double(whole) / 256 + r128ToReplayGainDb
        return abs(gain) <= largestGainDb ? gain : nil
    }

    static func number(_ text: String) -> Double? {
        var t = text
        if t.hasPrefix("+") { t.removeFirst() }
        guard let value = Double(t.replacingOccurrences(of: ",", with: ".")), value.isFinite else { return nil }
        return value
    }

    /// Loudness values a source kept, checked the way tags are: a gain past the limit or a peak
    /// that is not above zero is left out. Nothing without a gain.
    public static func stored(trackGain: Double?, trackPeak: Double?, albumGain: Double?, albumPeak: Double?) -> ReplayGainInfo? {
        func gain(_ v: Double?) -> Double? { v.flatMap { $0.isFinite && abs($0) <= largestGainDb ? $0 : nil } }
        func peak(_ v: Double?) -> Double? { v.flatMap { $0.isFinite && $0 > 0 ? $0 : nil } }
        let info = ReplayGainInfo(trackGain: gain(trackGain), trackPeak: peak(trackPeak), albumGain: gain(albumGain), albumPeak: peak(albumPeak))
        return info.hasGain ? info : nil
    }

    /// The loudness a song plays at: its own tags when the sound carries them, otherwise the
    /// values its source keeps. Peaks alone say nothing about how loud to play, so stored gains
    /// win over a stream with only those.
    public static func choose(stream: ReplayGainInfo?, stored: ReplayGainInfo?) -> ReplayGainInfo? {
        if stream?.hasGain == true { return stream }
        if stored?.hasGain == true { return stored }
        return stream
    }
}

/// How much to scale a song, as a multiplier. The gain is the chosen tag plus the ReplayGain
/// preamp, or the fallback for a song with no tags. Album and track each fall back to the
/// other when missing. Smart uses the album gain only while songs from one album follow each
/// other, so an album keeps its own loud and quiet songs, and a mix levels every song. With
/// clipping prevented, the song is never raised past its own peak.
public func replayGainFactor(_ settings: SoundSettings, _ song: SongLoudness?) -> Double {
    let useAlbum: Bool
    switch settings.replayGain {
    case .off: return 1
    case .track: useAlbum = false
    case .album: useAlbum = true
    case .smart: useAlbum = song?.followsSameAlbum == true
    }
    var gain: Double?
    var peak: Double?
    if let info = song?.replayGain, info.hasGain {
        if useAlbum, let album = info.albumGain {
            gain = album; peak = info.albumPeak ?? info.trackPeak
        } else if useAlbum {
            gain = info.trackGain; peak = info.trackPeak ?? info.albumPeak
        } else if let track = info.trackGain {
            gain = track; peak = info.trackPeak ?? info.albumPeak
        } else {
            gain = info.albumGain; peak = info.albumPeak ?? info.trackPeak
        }
    }
    let db = gain.map { $0 + settings.replayGainPreampDb } ?? settings.replayGainFallbackDb
    let factor = pow(10, db / 20)
    if settings.preventClipping, let peak, peak > 0 { return min(factor, 1 / peak) }
    return factor
}

/// Remembers the album of the last song that started, for Smart ReplayGain: a song uses its
/// album gain when the song before it came from the same album. A song set up again (the same
/// song twice in a row, as the player reopens it) keeps the answer it had.
public final class AlbumRun: @unchecked Sendable {
    private let lock = NSLock()
    private var lastSong: String?
    private var lastAlbum: String?
    private var lastAnswer = false

    public init() {}

    public func follows(_ song: String?, _ album: String?) -> Bool {
        lock.lock()
        defer { lock.unlock() }
        if let song, song == lastSong { return lastAnswer }
        lastAnswer = album != nil && album == lastAlbum
        lastSong = song
        lastAlbum = album
        return lastAnswer
    }
}

/// Keeps peaks under a ceiling just below full scale. The sound runs a moment late, so the
/// limiter sees a peak coming and turns the level down in time instead of clipping it, then
/// lets the level back up slowly so the change is not heard. All channels move together, so
/// the stereo picture stays put. Samples are one buffer per channel.
///
/// The delay holds back the first moment of each stream and hands it out at the end, so nothing
/// is lost or added between songs.
public final class Limiter: @unchecked Sendable {
    public let channels: Int
    /// Frames of delay.
    public let latency: Int
    /// Off, the level returns to unity and the sound only passes through the delay.
    public var enabled = true
    private let ceiling: Float
    private let release: Float
    /// The delayed frames, oldest first from `head`, one frame after another.
    private var held: [Float]
    private var head = 0
    private var heldFrames = 0
    /// The level each frame needs, kept as a rising queue so the lowest one in the lookahead
    /// window is always at the front.
    private var need: [Float]
    private var needAt: [Int]
    private var needFront = 0
    private var needSize = 0
    /// Frames in and out, to know which needs are still in view.
    private var inCount = 0
    private var outCount = 0
    /// The level applied now.
    private var gain: Float = 1
    /// One incoming frame, read before anything is written over it.
    private var incoming: [Float]

    public init(channels: Int, sampleRate: Double, ceilingDb: Double = -1, lookaheadMs: Double = 1.5, releaseMs: Double = 100) {
        self.channels = channels
        latency = max(1, Int((sampleRate * lookaheadMs / 1_000).rounded()))
        ceiling = Float(pow(10, ceilingDb / 20))
        release = Float(1 - exp(-1 / (sampleRate * releaseMs / 1_000)))
        held = Array(repeating: 0, count: latency * channels)
        need = Array(repeating: 1, count: latency + 2)
        needAt = Array(repeating: 0, count: latency + 2)
        incoming = Array(repeating: 0, count: channels)
    }

    public var ceilingLevel: Float { ceiling }

    /// Takes `frames` frames from `input` and writes the frames that come out of the delay to
    /// `output`, which may be the same buffers. Returns how many frames came out: fewer than
    /// went in only while the delay is filling.
    public func process(_ input: [UnsafeMutablePointer<Float>], frames: Int, output: [UnsafeMutablePointer<Float>]) -> Int {
        guard input.count == channels, output.count == channels else { return 0 }
        var written = 0
        for i in 0..<frames {
            var peak: Float = 0
            for ch in 0..<channels {
                let sample = input[ch][i]
                incoming[ch] = sample
                peak = max(peak, abs(sample))
            }
            pushNeed(enabled && peak > ceiling ? ceiling / peak : 1)
            inCount += 1
            if heldFrames < latency {
                let slot = ((head + heldFrames) % latency) * channels
                for ch in 0..<channels { held[slot + ch] = incoming[ch] }
                heldFrames += 1
            } else {
                // The oldest frame leaves and the new one takes its place.
                emit(output, at: written)
                let slot = head * channels
                for ch in 0..<channels { held[slot + ch] = incoming[ch] }
                head = (head + 1) % latency
                written += 1
            }
        }
        return written
    }

    /// Runs `frames` frames through the delay in place, the same number out as in: while the
    /// delay fills, what it holds back comes out as silence at the start.
    public func process(_ buffers: [UnsafeMutablePointer<Float>], frames: Int) {
        guard buffers.count == channels else { return }
        let written = process(buffers, frames: frames, output: buffers)
        shiftToEnd(buffers, frames: frames, written: written)
    }

    /// Hands out every frame still in the delay, at the end of a stream. `output` needs room
    /// for `latency` frames.
    public func drain(_ output: [UnsafeMutablePointer<Float>]) -> Int {
        guard output.count == channels else { return 0 }
        let count = heldFrames
        for index in 0..<count {
            emit(output, at: index)
            head = (head + 1) % latency
            heldFrames -= 1
        }
        head = 0
        return count
    }

    /// Forgets the sound in the delay, after a jump to another place. The level is kept.
    public func clear() {
        head = 0
        heldFrames = 0
        needFront = 0
        needSize = 0
        inCount = 0
        outCount = 0
    }

    /// Writes the oldest held frame, turned down as far as any frame in view needs. Down is
    /// instant; back up is slow.
    private func emit(_ output: [UnsafeMutablePointer<Float>], at index: Int) {
        while needSize > 0 && needAt[needFront] < outCount { popFront() }
        let target = needSize > 0 ? need[needFront] : 1
        gain = target < gain ? target : gain + (target - gain) * release
        let from = head * channels
        for ch in 0..<channels {
            var y = held[from + ch] * gain
            if enabled { y = min(ceiling, max(-ceiling, y)) }
            output[ch][index] = y
        }
        outCount += 1
    }

    /// Anything asking for more level than this one can never be the lowest while this one is
    /// in view.
    private func pushNeed(_ level: Float) {
        while needSize > 0 && need[(needFront + needSize - 1) % need.count] >= level { needSize -= 1 }
        let slot = (needFront + needSize) % need.count
        need[slot] = level
        needAt[slot] = inCount
        needSize += 1
    }

    private func popFront() {
        needFront = (needFront + 1) % need.count
        needSize -= 1
    }
}

/// The plain text filter list other equalizers read and write, one filter a line, like
/// "Filter 1: ON PK Fc 105 Hz Gain 6.4 dB Q 0.70", after a "Preamp: -6.1 dB" line. Headphone
/// corrections are shared in this form.
public enum ParametricEqFile {
    public static let imported = "Imported"

    public static func parse(_ text: String) -> (preampDb: Double, filters: [EqFilter]) {
        var preamp = 0.0
        var filters: [EqFilter] = []
        let preampLine = try! NSRegularExpression(pattern: #"Preamp:\s*([+-]?[\d.]+)\s*dB"#, options: .caseInsensitive)
        let filterLine = try! NSRegularExpression(
            pattern: #"Filter\s+\d+:\s+ON\s+(PK|LSC|HSC)\s+Fc\s+([\d.]+)\s+Hz\s+Gain\s+([+-]?[\d.]+)\s+dB\s+Q\s+([\d.]+)"#,
            options: .caseInsensitive)
        for line in text.components(separatedBy: .newlines) {
            let range = NSRange(line.startIndex..., in: line)
            func group(_ match: NSTextCheckingResult, _ i: Int) -> String {
                Range(match.range(at: i), in: line).map { String(line[$0]) } ?? ""
            }
            if let match = preampLine.firstMatch(in: line, range: range), let value = Double(group(match, 1)) {
                preamp = value
            }
            if let match = filterLine.firstMatch(in: line, range: range),
               let frequency = Double(group(match, 2)), let gain = Double(group(match, 3)), let q = Double(group(match, 4)), q > 0 {
                let type: FilterType = switch group(match, 1).uppercased() {
                case "LSC": .lowShelf
                case "HSC": .highShelf
                default: .peak
                }
                filters.append(EqFilter(type: type, frequency: frequency, gainDb: gain, q: q))
            }
        }
        return (preamp, filters)
    }

    /// A headphone correction from a file, named after it, or nothing when it has no filters.
    public static func correction(fileName: String, text: String) -> HeadphoneCorrection? {
        let contents = parse(text)
        guard !contents.filters.isEmpty else { return nil }
        return HeadphoneCorrection(name: name(from: fileName), source: imported, preampDb: contents.preampDb, filters: contents.filters)
    }

    /// The file's name without its extension and the "ParametricEQ" such files end in.
    public static func name(from fileName: String) -> String {
        let base = fileName.lastIndex(of: ".").map { String(fileName[..<$0]) } ?? fileName
        let bare = base.trimmingCharacters(in: .whitespacesAndNewlines)
        var short = bare
        if short.hasSuffix("ParametricEQ") { short.removeLast("ParametricEQ".count) }
        short = short.trimmingCharacters(in: .whitespacesAndNewlines)
        while let last = short.last, last == "-" || last == "_" { short.removeLast() }
        short = short.trimmingCharacters(in: .whitespacesAndNewlines)
        return short.isEmpty ? (bare.isEmpty ? "Correction" : bare) : short
    }

    /// Writes filters as a file another equalizer can load.
    public static func write(preampDb: Double, filters: [EqFilter]) -> String {
        var text = "Preamp: \(decimal(preampDb, 1)) dB\n"
        for (index, filter) in filters.enumerated() {
            let code = switch filter.type {
            case .peak: "PK"
            case .lowShelf: "LSC"
            case .highShelf: "HSC"
            }
            let whole = filter.frequency.rounded()
            let fc = abs(filter.frequency - whole) < 0.05 ? String(Int(whole)) : decimal(filter.frequency, 1)
            text += "Filter \(index + 1): \(filter.enabled ? "ON" : "OFF") \(code) Fc \(fc) Hz Gain \(decimal(filter.gainDb, 1)) dB Q \(decimal(filter.q, 2))\n"
        }
        return text
    }

    /// Always with a dot, halves rounded away from zero, and no "-0.0".
    static func decimal(_ value: Double, _ places: Int) -> String {
        let scale = pow(10, Double(places))
        let rounded = (value * scale).rounded(.toNearestOrAwayFromZero) / scale
        let shown = String(format: "%.\(places)f", locale: Locale(identifier: "en_US_POSIX"), rounded)
        return shown.drop { $0 == "-" }.allSatisfy { $0 == "0" || $0 == "." } ? String(shown.drop { $0 == "-" }) : shown
    }
}
