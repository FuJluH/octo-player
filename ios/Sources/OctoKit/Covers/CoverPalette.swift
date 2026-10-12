import Foundation

/// The colour of a list's music that picks its cover's background: the hue, chroma and lightness
/// (OKLCH) of the strongest colour of its first covers, or one from its id when it has none.
public struct CoverPalette: Hashable, Sendable, CustomStringConvertible {
    public let hue: Int
    public let chroma: Double
    public let lightness: Double
    /// Whether the colour came from the music's covers.
    public let fromMusic: Bool

    private init(hue: Int, chroma: Double, lightness: Double, fromMusic: Bool) {
        self.hue = hue
        self.chroma = chroma
        self.lightness = lightness
        self.fromMusic = fromMusic
    }

    /// The colour as short text, the same for the same colour, for cache keys.
    public var key: String { "\(hue).\(Int((chroma * 1000).rounded())).\(Int((lightness * 1000).rounded()))" }

    public var description: String { "CoverPalette(\(key), fromMusic=\(fromMusic))" }

    public static func == (a: CoverPalette, b: CoverPalette) -> Bool { a.key == b.key && a.fromMusic == b.fromMusic }

    public func hash(into hasher: inout Hasher) { hasher.combine(key) }

    public static func of(hue: Double, chroma: Double, lightness: Double, fromMusic: Bool) -> CoverPalette {
        CoverPalette(hue: wrap(hue), chroma: round3(min(max(chroma, 0), 0.4)), lightness: round3(min(max(lightness, 0), 1)),
                     fromMusic: fromMusic)
    }

    /// Back from `key`, for a colour kept on disk; nil for anything else.
    public static func fromKey(_ key: String, fromMusic: Bool = true) -> CoverPalette? {
        let parts = key.split(separator: ".", omittingEmptySubsequences: false).map { Int($0) }
        guard parts.count == 3, let h = parts[0], let c = parts[1], let l = parts[2] else { return nil }
        return of(hue: Double(h), chroma: Double(c) / 1000, lightness: Double(l) / 1000, fromMusic: fromMusic)
    }

    private static func wrap(_ h: Double) -> Int { ((Int(h.rounded()) % 360) + 360) % 360 }
    private static func round3(_ v: Double) -> Double { (v * 1000).rounded() / 1000 }
}

/// Colours under this chroma read as grey, and give no hue to work from.
private let colourless = 0.035

/// A list's colour from its music: the main colours of the covers of its first few songs (a list
/// of swatches for each), weighed by how much of its cover each colour fills and how vivid it is;
/// the strongest wins. With no covers, or only grey ones, a colour of its own from the id.
public func coverPalette(_ covers: [[CoverSwatch]], seed: String) -> CoverPalette {
    let withColour = covers.filter { !$0.isEmpty }
    if withColour.isEmpty { return seededPalette(seed) }
    let seen = withColour.flatMap { swatches in
        swatches.prefix(4).map { (lch: toLch($0.argb), weight: Double($0.share) / Double(withColour.count)) }
    }
    let colourful = seen.filter { $0.lch.c >= colourless && $0.lch.l >= 0.15 && $0.lch.l <= 0.97 }
    guard let first = colourful.max(by: { sqrt($0.weight) * (0.3 + $0.lch.c * 5) < sqrt($1.weight) * (0.3 + $1.lch.c * 5) }) else {
        return seededPalette(seed)
    }
    return .of(hue: first.lch.h, chroma: first.lch.c, lightness: first.lch.l, fromMusic: true)
}

/// A colour from the id alone, for a list with no covers.
public func seededPalette(_ seed: String) -> CoverPalette {
    .of(hue: Double(coverHash(seed) % 360), chroma: 0.12, lightness: 0.5, fromMusic: false)
}

private func fnv(_ text: String) -> UInt64 {
    var hash: UInt64 = 0xCBF2_9CE4_8422_2325
    for byte in text.utf8 {
        hash ^= UInt64(byte)
        hash = hash &* 0x0000_0100_0000_01B3
    }
    return hash
}

/// A number from some text, always the same for the same text on every device (FNV-1a over its
/// UTF-8), never negative.
public func coverHash(_ text: String) -> Int64 { Int64(fnv(text) >> 1) }

/// The hash well mixed, for picking a background and its turn: FNV-1a then MurmurHash3's
/// finaliser (fmix64), then shifted right by one.
public func coverPick(_ text: String) -> Int64 {
    var k = fnv(text)
    k ^= k >> 33
    k = k &* 0xFF51_AFD7_ED55_8CCD
    k ^= k >> 33
    k = k &* 0xC4CE_B9FE_1A85_EC53
    k ^= k >> 33
    return Int64(k >> 1)
}
