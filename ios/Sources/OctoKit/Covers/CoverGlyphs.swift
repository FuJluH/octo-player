import Foundation

/// The glyph a marked list's cover carries in place of words: a heart for Liked Songs, a magnifier
/// for Review, two overlapping squares for Duplicates.
public enum CoverGlyph: String, Sendable {
    case heart = "Heart"
    case magnifier = "Magnifier"
    case copies = "Copies"
}

public let octoNoticeReview = "review"
public let octoNoticeDuplicates = "duplicates"
public let octoListLiked = "liked"

/// The glyph a playlist row's cover carries: Review and Duplicates by the server's notice mark,
/// Liked Songs by its list kind. A notice kind this app does not know draws the usual cover.
public func playlistGlyph(octoNotice: String?, octoList: String? = nil) -> CoverGlyph? {
    if octoNotice == octoNoticeReview { return .magnifier }
    if octoNotice == octoNoticeDuplicates { return .copies }
    if octoList == octoListLiked || octoNotice == octoListLiked { return .heart }
    return nil
}

public struct GlyphNumbers: Decodable, Sendable {
    public var box: Float
    public var veilGrow: Float
    public var shadow: GlyphShadow
    public var heart: HeartNumbers
    public var magnifier: MagnifierNumbers
    public var copies: CopiesNumbers
}

public struct GlyphShadow: Decodable, Sendable {
    public var alpha: Float
    public var offsets: [Float]
}

public struct HeartNumbers: Decodable, Sendable {
    public var from: [Float]
    public var lobe: [[Float]]
}

public struct MagnifierNumbers: Decodable, Sendable {
    public var center: [Float]
    public var radius: Float
    public var stroke: Float
    public var handle: [[Float]]
    public var handleWidth: Float
}

public struct CopiesNumbers: Decodable, Sendable {
    public var side: Float
    public var radius: Float
    public var back: [Float]
    public var front: [Float]
    public var stroke: Float
    public var gap: Float
}

/// One filled shape of a glyph, in the cover's pixels.
public enum GlyphShape: Equatable, Sendable {
    case circle(x: Float, y: Float, radius: Float)
    case roundSquare(left: Float, top: Float, side: Float, radius: Float)
    /// A line `width` wide with round ends.
    case capsule(x0: Float, y0: Float, x1: Float, y1: Float, width: Float)
    /// A closed outline from (x, y) through cubics, each six numbers: two control points and the end.
    case curves(x: Float, y: Float, cubics: [[Float]])

    /// Bounds as left, top, right, bottom.
    public var bounds: [Float] {
        switch self {
        case .circle(let x, let y, let r): [x - r, y - r, x + r, y + r]
        case .roundSquare(let left, let top, let side, _): [left, top, left + side, top + side]
        case .capsule(let x0, let y0, let x1, let y1, let width):
            [min(x0, x1) - width / 2, min(y0, y1) - width / 2, max(x0, x1) + width / 2, max(y0, y1) + width / 2]
        case .curves(let x, let y, let cubics):
            curveBounds(x, y, cubics)
        }
    }
}

private func curveBounds(_ x: Float, _ y: Float, _ cubics: [[Float]]) -> [Float] {
    let xs = [x] + cubics.flatMap { [$0[0], $0[2], $0[4]] }
    let ys = [y] + cubics.flatMap { [$0[1], $0[3], $0[5]] }
    return [xs.min() ?? x, ys.min() ?? y, xs.max() ?? x, ys.max() ?? y]
}

/// A glyph as shapes laid one after another: each `add` joins the outline, each cut takes its area
/// away from what is there so far.
public struct GlyphStep: Equatable, Sendable {
    public var shape: GlyphShape
    public var add: Bool
}

/// A glyph ready to paint: its steps, the box it sits in (left, top, side), and its shadow's
/// offsets in pixels and opacity.
public struct GlyphDrawing: Equatable, Sendable {
    public var glyph: CoverGlyph
    public var steps: [GlyphStep]
    public var box: [Float]
    public var shadowOffsets: [Float]
    public var shadowAlpha: Float
}

/// Where a glyph's shapes go on a cover `side` pixels square.
public func glyphDrawing(_ glyph: CoverGlyph, side: Int, numbers: GlyphNumbers) -> GlyphDrawing {
    let s = Float(side)
    let size = s * numbers.box
    let left = (s - size) / 2
    let top = (s - size) / 2
    func x(_ v: Float) -> Float { left + v * size }
    func y(_ v: Float) -> Float { top + v * size }
    func d(_ v: Float) -> Float { v * size }
    let steps: [GlyphStep]
    switch glyph {
    case .heart:
        let h = numbers.heart
        let c1 = h.lobe[0], c2 = h.lobe[1], end = h.lobe[2]
        // The left lobe, then the same mirrored back to the point.
        let leftLobe = [x(c1[0]), y(c1[1]), x(c2[0]), y(c2[1]), x(end[0]), y(end[1])]
        let rightLobe = [x(1 - c2[0]), y(c2[1]), x(1 - c1[0]), y(c1[1]), x(1 - h.from[0]), y(h.from[1])]
        steps = [GlyphStep(shape: .curves(x: x(h.from[0]), y: y(h.from[1]), cubics: [leftLobe, rightLobe]), add: true)]
    case .magnifier:
        let m = numbers.magnifier
        let cx = x(m.center[0]), cy = y(m.center[1])
        steps = [
            GlyphStep(shape: .circle(x: cx, y: cy, radius: d(m.radius + m.stroke / 2)), add: true),
            GlyphStep(shape: .circle(x: cx, y: cy, radius: d(m.radius - m.stroke / 2)), add: false),
            GlyphStep(shape: .capsule(x0: x(m.handle[0][0]), y0: y(m.handle[0][1]), x1: x(m.handle[1][0]), y1: y(m.handle[1][1]),
                                      width: d(m.handleWidth)), add: true),
        ]
    case .copies:
        let c = numbers.copies
        let half = c.stroke / 2
        func square(_ at: [Float], _ grow: Float) -> GlyphShape {
            .roundSquare(left: x(at[0] - grow), top: y(at[1] - grow), side: d(c.side + 2 * grow), radius: d(max(c.radius + grow, 0)))
        }
        steps = [
            GlyphStep(shape: square(c.back, half), add: true),
            GlyphStep(shape: square(c.back, -half), add: false),
            GlyphStep(shape: square(c.front, c.gap), add: false),
            GlyphStep(shape: square(c.front, 0), add: true),
        ]
    }
    return GlyphDrawing(glyph: glyph, steps: steps, box: [left, top, size], shadowOffsets: numbers.shadow.offsets.map { $0 * s },
                        shadowAlpha: numbers.shadow.alpha)
}

/// The veil's region under a glyph: its box grown about its centre, darkened as under a title.
public func glyphVeilRegion(_ drawing: GlyphDrawing, numbers: GlyphNumbers, book: CoverBook = .standard) -> VeilRegion {
    let left = drawing.box[0], top = drawing.box[1], size = drawing.box[2]
    let grow = size * numbers.veilGrow / 2
    let v = book.veil.title
    let aim = veilLimit(v.aimContrast) * (1 - book.veil.margin)
    let least = veilLimit(v.minContrast) * (1 - book.veil.margin)
    return VeilRegion(box: [left - grow, top - grow, left + size + grow, top + size + grow], falloffX: v.falloff[0],
                      falloffY: v.falloff[1], aim: aim, least: least, maxDrop: v.maxDrop)
}
