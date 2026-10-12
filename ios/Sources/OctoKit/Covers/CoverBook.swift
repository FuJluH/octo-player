import Foundation

// The covers' design as numbers: the layout, the fonts and the veil, read from cover-design.json.
// The phone, the desktop and the server all draw from that one file, so their covers match.

public struct CoverBook: Decodable, Sendable {
    public var version: Int
    public var fonts: CoverFonts
    public var layout: CoverLayoutNumbers
    public var background: BackgroundRule
    public var veil: VeilNumbers
    /// The glyphs marked lists carry in place of words.
    public var glyphs: GlyphNumbers?

    public static func parse(_ text: String) throws -> CoverBook { try JSONDecoder().decode(CoverBook.self, from: Data(text.utf8)) }

    /// The book the apps draw from.
    public static let standard: CoverBook = {
        do { return try parse(coverDesignJSON) } catch { fatalError("cover-design.json does not read: \(error)") }
    }()
}

public struct CoverFonts: Decodable, Sendable {
    public var family: String
    public var title: String
    public var line: String
    public var footer: String
}

public struct CoverLayoutNumbers: Decodable, Sendable {
    public var margin: Float
    public var contrast: Double
    public var tinyBelowPx: Int
    public var title: TitleNumbers
    public var line: LineNumbers
    public var footer: FooterNumbers
}

public struct TitleNumbers: Decodable, Sendable {
    public var top: Float
    public var weight: Int
    public var size: Float
    public var oneLineDownTo: Float
    /// One line never smaller than this; a small cover wraps instead.
    public var oneLineMinPx: Float
    public var wrapSize: Float
    /// Wrapped lines start at least this big (never over `size`).
    public var wrapMinPx: Float
    public var minSize: Float
    public var minPx: Float
    public var maxLines: Int
    public var lineHeight: Float
    public var tracking: Float

    enum CodingKeys: String, CodingKey {
        case top, weight, size, oneLineDownTo, oneLineMinPx, wrapSize, wrapMinPx, minSize, minPx, maxLines, lineHeight, tracking
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        top = try c.decode(Float.self, forKey: .top)
        weight = try c.decode(Int.self, forKey: .weight)
        size = try c.decode(Float.self, forKey: .size)
        oneLineDownTo = try c.decode(Float.self, forKey: .oneLineDownTo)
        oneLineMinPx = try c.decodeIfPresent(Float.self, forKey: .oneLineMinPx) ?? 0
        wrapSize = try c.decode(Float.self, forKey: .wrapSize)
        wrapMinPx = try c.decodeIfPresent(Float.self, forKey: .wrapMinPx) ?? 0
        minSize = try c.decode(Float.self, forKey: .minSize)
        minPx = try c.decode(Float.self, forKey: .minPx)
        maxLines = try c.decode(Int.self, forKey: .maxLines)
        lineHeight = try c.decode(Float.self, forKey: .lineHeight)
        tracking = try c.decode(Float.self, forKey: .tracking)
    }
}

public struct LineNumbers: Decodable, Sendable {
    public var weight: Int
    public var shareOfTitle: Float
    public var minPx: Float
    public var lineHeight: Float
    public var tracking: Float
    public var showFromPx: Int
}

public struct FooterNumbers: Decodable, Sendable {
    public var weight: Int
    public var size: Float
    public var minPx: Float
    public var bottom: Float
    public var opacity: Float
    public var lineHeight: Float
    public var tracking: Float
    public var showFromPx: Int
}

/// How music picks a background (see "background" in cover-design.json).
public struct BackgroundRule: Decodable, Sendable {
    public var nearest: Int
    /// Music duller than this picks like a list with no covers.
    public var lowChromaAsGrey: Double
    public var hueStep: Double
    public var greyBelow: Double
    public var greyPenalty: Double
    public var chromaWeight: Double
    public var lightnessWeight: Double
    public var orientation: OrientationRule
}

/// How a list turns its background, so lists sharing one do not look like copies.
public struct OrientationRule: Decodable, Sendable {
    public var shift: Int
    public var count: Int
}

/// The veil's numbers (see "veil" in cover-design.json for what each means).
public struct VeilNumbers: Decodable, Sendable {
    public var margin: Double
    public var refine: Int
    public var title: TitleVeil
    public var footer: FooterVeil
    public var yellow: YellowTurn
}

public struct TitleVeil: Decodable, Sendable {
    public var pad: Float
    public var falloff: [Double]
    public var aimContrast: Double
    public var minContrast: Double
    public var maxDrop: Double
}

public struct FooterVeil: Decodable, Sendable {
    public var pad: Float
    public var falloff: [Double]
    public var contrast: Double
}

public struct YellowTurn: Decodable, Sendable {
    public var hues: [Double]
    public var split: Double
    public var towards: [Double]
    public var turnPerDrop: Double
    public var chromaFrom: Double
    public var chromaLift: Double
}

/// The library of painted backgrounds: each file's strongest hues (OKLCH, strongest first) and
/// mean lightness.
public struct CoverBackgrounds: Decodable, Sendable {
    public var version: Int
    public var size: Int
    public var backgrounds: [CoverBackground]

    public static func parse(_ text: String) throws -> CoverBackgrounds {
        try JSONDecoder().decode(CoverBackgrounds.self, from: Data(text.utf8))
    }

    public static let standard: CoverBackgrounds = {
        do { return try parse(coverBackgroundsJSON) } catch { fatalError("backgrounds.json does not read: \(error)") }
    }()
}

public struct CoverBackground: Decodable, Sendable, Hashable {
    public var file: String
    public var name: String
    public var family: String
    public var hues: [BackgroundHue]
    public var meanLightness: Double

    enum CodingKeys: String, CodingKey { case file, name, family, hues, meanLightness }

    public init(file: String, name: String, family: String = "", hues: [BackgroundHue], meanLightness: Double) {
        self.file = file
        self.name = name
        self.family = family
        self.hues = hues
        self.meanLightness = meanLightness
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        file = try c.decode(String.self, forKey: .file)
        name = try c.decode(String.self, forKey: .name)
        family = try c.decodeIfPresent(String.self, forKey: .family) ?? ""
        hues = try c.decode([BackgroundHue].self, forKey: .hues)
        meanLightness = try c.decode(Double.self, forKey: .meanLightness)
    }
}

public struct BackgroundHue: Decodable, Sendable, Hashable {
    public var l: Double
    public var c: Double
    public var h: Double

    public init(l: Double, c: Double, h: Double) {
        self.l = l
        self.c = c
        self.h = h
    }
}
