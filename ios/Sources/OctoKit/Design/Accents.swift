import Foundation

/// The accent the app draws selected states, sliders, switches and filled buttons in. Every fixed
/// one is a light shade at about the OKLCH lightness of Octo's own (0.76), so each reads at WCAG
/// AA or better as words on the page and as the fill under the page's dark ink. The raw value is
/// the name kept in settings and backups, the same on every Octo app; `argb` is nil for the one
/// taken from the playing song's cover.
public enum AccentChoice: String, StoredChoice, Codable {
    case octo = "Octo"
    case sky = "Sky"
    case iris = "Iris"
    case lilac = "Lilac"
    case rose = "Rose"
    case coral = "Coral"
    case amber = "Amber"
    case lime = "Lime"
    case mint = "Mint"
    case fromArt = "FromArt"

    public var label: String {
        switch self {
        case .octo: "Octo"
        case .sky: "Sky"
        case .iris: "Iris"
        case .lilac: "Lilac"
        case .rose: "Rose"
        case .coral: "Coral"
        case .amber: "Amber"
        case .lime: "Lime"
        case .mint: "Mint"
        case .fromArt: "From the album art"
        }
    }

    /// `0xFFRRGGBB`, or nil for the one that follows the cover.
    public var argb: UInt32? {
        switch self {
        case .octo: 0xFF97_B1B9
        case .sky: 0xFF73_BAEA
        case .iris: 0xFFA3_A9F6
        case .lilac: 0xFFC7_9DE6
        case .rose: 0xFFE4_96B4
        case .coral: 0xFFEF_9687
        case .amber: 0xFFDA_A75D
        case .lime: 0xFFA0_BE66
        case .mint: 0xFF6F_C5A1
        case .fromArt: nil
        }
    }

    /// One line under the picker saying what the choice does.
    public var help: String {
        switch self {
        case .fromArt: "Follows the playing song's cover. Octo's own color while nothing plays or the cover is gray."
        case .octo: "Octo's own blue gray for selections, sliders, switches and buttons."
        default: "Selections, sliders, switches and buttons in \(label.lowercased())."
        }
    }

    /// The fixed accents, in the order the picker shows them.
    public static let fixed: [AccentChoice] = allCases.filter { $0.argb != nil }
}

/// Octo's own accent, the default.
public let octoAccentArgb: UInt32 = 0xFF97_B1B9

/// The page color and the raised surface the accent sits on.
public let accentPageArgb: UInt32 = 0xFF0C_0C0D
public let accentSurfaceArgb: UInt32 = 0xFF1A_1A1B

/// The contrast every accent keeps against the page and the raised surface: WCAG AA for small
/// text.
public let accentContrast = 4.5

/// Below this chroma a cover is gray enough to keep Octo's own accent.
private let minArtChroma = 0.04

/// Whether an accent reads on the page and on the raised surface, each at AA.
public func accentReads(_ argb: UInt32) -> Bool {
    contrastRatio(argb, accentPageArgb) >= accentContrast && contrastRatio(argb, accentSurfaceArgb) >= accentContrast
}

/// A cover's color made into an accent: the same hue, at the fixed accents' lightness and a
/// chroma held between theirs, lightened further while the page would still not read it at AA.
/// Nil for a cover with hardly any color, which keeps Octo's own.
public func accentFromArt(_ argb: UInt32) -> UInt32? {
    let lch = toLch(argb)
    if lch.c < minArtChroma { return nil }
    let chroma = min(max(lch.c, 0.07), 0.12)
    var lightness = 0.76
    var accent = lchToArgb(lightness, chroma, lch.h)
    while !accentReads(accent) && lightness < 0.95 {
        lightness += 0.02
        accent = lchToArgb(lightness, chroma, lch.h)
    }
    return accent
}

/// The accent to draw now: a fixed one as it is, the cover's for From the album art (`art` is
/// the playing cover's color, nil with none), or Octo's own when the cover gives none.
public func accentArgb(_ choice: AccentChoice, art: UInt32?) -> UInt32 {
    choice.argb ?? art.flatMap(accentFromArt) ?? octoAccentArgb
}

/// What Color the glass says: what it does, or, while the accent is Octo's own, why it has
/// nothing to change.
public enum GlassTintWords {
    public static let help = "The bar, glass buttons and toasts take the accent too. Off, the glass stays Apple's own, untinted."
    public static let same = "Octo's own accent is already the glass's color. Pick another accent to tint the glass with it."

    /// The line under the switch for the accent chosen.
    public static func helper(_ choice: AccentChoice) -> String { choice == .octo ? same : help }
}

/// The film laid into Octo's glass. Plain, it is the faintest dim; with Color the glass on, the
/// same dim carries the accent, as Android and the desktop light their glass with it.
public func glassFilm(accent: RGBA, tinted: Bool) -> RGBA {
    guard tinted else { return OctoPalette.glazeFilm }
    return mix(.black, accent, 0.55).opacity(0.34)
}
