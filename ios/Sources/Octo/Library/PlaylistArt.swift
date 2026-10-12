import CoreGraphics
import CoreText
import Foundation
import OctoKit
import SwiftUI
import UIKit

// Designed playlist covers on the phone: a painted background with the colour-keeping veil, and
// words set in Inter Display (bundled with the app), measured and painted by Core Text at the exact
// size the picture is made at. Writing Inter does not cover (Chinese, Arabic, emoji) falls back to
// the system's fonts. Pixels throughout.

/// Inter Display in the three weights covers use, registered for this app once.
enum CoverFonts {
    private static let names: [Int: String] = {
        var out: [Int: String] = [:]
        for (weight, file) in [(300, "InterDisplay-light"), (500, "InterDisplay-medium"), (600, "InterDisplay-semibold")] {
            guard let url = Bundle.module.url(forResource: file, withExtension: "ttf", subdirectory: "CoverArt") else { continue }
            CTFontManagerRegisterFontsForURL(url as CFURL, .process, nil)
            let descriptors = CTFontManagerCreateFontDescriptorsFromURL(url as CFURL) as? [CTFontDescriptor] ?? []
            if let name = descriptors.first.flatMap({ CTFontDescriptorCopyAttribute($0, kCTFontNameAttribute) as? String }) {
                out[weight] = name
            }
        }
        return out
    }()

    /// The face for a weight: Inter Display where it is bundled, else the system's.
    static func font(weight: Int, size: CGFloat) -> CTFont {
        if let name = names[weight] { return CTFontCreateWithName(name as CFString, size, nil) }
        let system: UIFont.Weight = weight >= 600 ? .semibold : weight >= 500 ? .medium : weight <= 300 ? .light : .regular
        return UIFont.systemFont(ofSize: size, weight: system) as CTFont
    }
}

/// Core Text, as the design measures words.
struct CoreTextCoverTypesetter: CoverTypesetter {
    static func attributed(_ text: String, _ type: CoverType, color: CGColor? = nil, alignment: CTTextAlignment = .left) -> NSAttributedString {
        let font = CoverFonts.font(weight: type.weight, size: CGFloat(type.sizePx))
        var align = alignment
        let style = withUnsafePointer(to: &align) { pointer in
            var settings = [CTParagraphStyleSetting(spec: .alignment, valueSize: MemoryLayout<CTTextAlignment>.size, value: pointer)]
            return CTParagraphStyleCreate(&settings, settings.count)
        }
        var attributes: [NSAttributedString.Key: Any] = [
            NSAttributedString.Key(kCTFontAttributeName as String): font,
            NSAttributedString.Key(kCTKernAttributeName as String): CGFloat(type.tracking * type.sizePx),
            NSAttributedString.Key(kCTParagraphStyleAttributeName as String): style,
        ]
        if let color { attributes[NSAttributedString.Key(kCTForegroundColorAttributeName as String)] = color }
        return NSAttributedString(string: text, attributes: attributes)
    }

    /// The text broken into lines `width` wide.
    static func lines(_ text: String, _ type: CoverType, width: Float, color: CGColor? = nil, alignment: CTTextAlignment = .left) -> [CTLine] {
        let setter = CTFramesetterCreateWithAttributedString(attributed(text, type, color: color, alignment: alignment))
        let path = CGPath(rect: CGRect(x: 0, y: 0, width: CGFloat(max(width, 1)), height: 100_000), transform: nil)
        let frame = CTFramesetterCreateFrame(setter, CFRange(location: 0, length: 0), path, nil)
        return CTFrameGetLines(frame) as? [CTLine] ?? []
    }

    static func width(_ line: CTLine) -> Float {
        Float(CTLineGetTypographicBounds(line, nil, nil, nil) - CTLineGetTrailingWhitespaceWidth(line))
    }

    func measure(_ text: String, _ type: CoverType, width: Float) -> Measured {
        let all = Self.lines(text, type, width: width)
        let shown = min(all.count, type.maxLines)
        let widest = all.prefix(shown).map(Self.width).max() ?? 0
        // Lines sit a whole line height apart, as the design counts them.
        return Measured(lines: shown, width: widest, height: Float(shown) * type.sizePx * type.lineHeight, cut: all.count > type.maxLines)
    }

    func widthOf(_ text: String, _ type: CoverType) -> Float {
        Self.width(CTLineCreateWithAttributedString(Self.attributed(text, type)))
    }
}

/// Paints a cover: the veiled background, then its words or its glyph.
enum CoverPainter {
    static func image(_ pixels: [UInt32], side: Int, plan: CoverPlan) -> CGImage? {
        var buffer = pixels
        let space = CGColorSpaceCreateDeviceRGB()
        let info = CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue
        return buffer.withUnsafeMutableBytes { raw -> CGImage? in
            guard let context = CGContext(data: raw.baseAddress, width: side, height: side, bitsPerComponent: 8, bytesPerRow: side * 4,
                                          space: space, bitmapInfo: info) else { return nil }
            // Top left at the origin, y down, as the plan measures.
            context.translateBy(x: 0, y: CGFloat(side))
            context.scaleBy(x: 1, y: -1)
            for words in plan.words { draw(words, in: context) }
            if let glyph = plan.glyph { draw(glyph, in: context) }
            return context.makeImage()
        }
    }

    private static func draw(_ words: CoverWords, in context: CGContext) {
        let ink = UIColor(red: CGFloat(words.ink >> 16 & 0xFF) / 255, green: CGFloat(words.ink >> 8 & 0xFF) / 255,
                          blue: CGFloat(words.ink & 0xFF) / 255, alpha: CGFloat(words.ink >> 24 & 0xFF) / 255).cgColor
        var lines = CoreTextCoverTypesetter.lines(words.text, words.type, width: words.width, color: ink)
        if lines.count > words.type.maxLines {
            lines = Array(lines.prefix(words.type.maxLines))
            if let last = lines.last {
                let range = CTLineGetStringRange(last)
                let rest = (words.text as NSString).substring(from: min(range.location, (words.text as NSString).length))
                let tail = CTLineCreateWithAttributedString(CoreTextCoverTypesetter.attributed(rest, words.type, color: ink))
                let ellipsis = CTLineCreateWithAttributedString(CoreTextCoverTypesetter.attributed("\u{2026}", words.type, color: ink))
                lines[lines.count - 1] = CTLineCreateTruncatedLine(tail, Double(words.width), .end, ellipsis) ?? last
            }
        }
        let size = CGFloat(words.type.sizePx)
        let box = size * CGFloat(words.type.lineHeight)
        for (index, line) in lines.enumerated() {
            var ascent: CGFloat = 0, descent: CGFloat = 0, leading: CGFloat = 0
            let width = CGFloat(CTLineGetTypographicBounds(line, &ascent, &descent, &leading) - CTLineGetTrailingWhitespaceWidth(line))
            // Each line centred in its line height.
            let baseline = CGFloat(words.top) + CGFloat(index) * box + (box - (ascent + descent)) / 2 + ascent
            let x = words.align == .left ? CGFloat(words.left) : CGFloat(words.left + words.width) - width
            context.saveGState()
            context.translateBy(x: x, y: baseline)
            context.scaleBy(x: 1, y: -1)
            context.textPosition = .zero
            CTLineDraw(line, context)
            context.restoreGState()
        }
    }

    /// One shape of a glyph as a path.
    private static func path(_ shape: GlyphShape) -> CGPath {
        let path = CGMutablePath()
        switch shape {
        case .circle(let x, let y, let r):
            path.addEllipse(in: CGRect(x: CGFloat(x - r), y: CGFloat(y - r), width: CGFloat(2 * r), height: CGFloat(2 * r)))
        case .roundSquare(let left, let top, let side, let radius):
            let rect = CGRect(x: CGFloat(left), y: CGFloat(top), width: CGFloat(side), height: CGFloat(side))
            let corner = min(CGFloat(radius), rect.width / 2)
            path.addRoundedRect(in: rect, cornerWidth: corner, cornerHeight: corner)
        case .capsule(let x0, let y0, let x1, let y1, let width):
            let r = CGFloat(width / 2)
            let dx = CGFloat(x1 - x0), dy = CGFloat(y1 - y0)
            let length = max(hypot(dx, dy), 1e-6)
            let nx = -dy / length * r, ny = dx / length * r
            path.move(to: CGPoint(x: CGFloat(x0) + nx, y: CGFloat(y0) + ny))
            path.addLine(to: CGPoint(x: CGFloat(x1) + nx, y: CGFloat(y1) + ny))
            path.addLine(to: CGPoint(x: CGFloat(x1) - nx, y: CGFloat(y1) - ny))
            path.addLine(to: CGPoint(x: CGFloat(x0) - nx, y: CGFloat(y0) - ny))
            path.closeSubpath()
            let ends = CGMutablePath()
            ends.addEllipse(in: CGRect(x: CGFloat(x0) - r, y: CGFloat(y0) - r, width: 2 * r, height: 2 * r))
            ends.addEllipse(in: CGRect(x: CGFloat(x1) - r, y: CGFloat(y1) - r, width: 2 * r, height: 2 * r))
            return path.union(ends)
        case .curves(let x, let y, let cubics):
            path.move(to: CGPoint(x: CGFloat(x), y: CGFloat(y)))
            for c in cubics where c.count == 6 {
                path.addCurve(to: CGPoint(x: CGFloat(c[4]), y: CGFloat(c[5])), control1: CGPoint(x: CGFloat(c[0]), y: CGFloat(c[1])),
                              control2: CGPoint(x: CGFloat(c[2]), y: CGFloat(c[3])))
            }
            path.closeSubpath()
        }
        return path
    }

    /// A glyph's outline: its shapes joined and cut in order.
    static func outline(_ drawing: GlyphDrawing) -> CGPath {
        var outline: CGPath = CGMutablePath()
        for step in drawing.steps {
            let part = path(step.shape)
            outline = step.add ? outline.union(part) : outline.subtracting(part)
        }
        return outline
    }

    /// Its soft shadow, then the glyph in white.
    private static func draw(_ drawing: GlyphDrawing, in context: CGContext) {
        let outline = outline(drawing)
        for offset in drawing.shadowOffsets {
            context.saveGState()
            context.translateBy(x: 0, y: CGFloat(offset))
            context.addPath(outline)
            context.setFillColor(UIColor.black.withAlphaComponent(CGFloat(drawing.shadowAlpha)).cgColor)
            context.fillPath()
            context.restoreGState()
        }
        context.addPath(outline)
        context.setFillColor(UIColor.white.cgColor)
        context.fillPath()
    }
}

/// Designed covers: their colours, from the covers of a list's first albums, and the pictures,
/// drawn at the size shown. Both are kept in memory, and the pictures in the app's caches too.
actor PlaylistArt {
    static let shared = PlaylistArt()

    private var palettes: [String: CoverPalette] = [:]
    private let pictures = NSCache<NSString, UIImage>()
    private var drawing: [String: Task<UIImage?, Never>] = [:]
    /// The last two backgrounds read, by file: a list of playlists often shares one.
    private var backgrounds: [(file: String, pixels: [UInt32], side: Int)] = []
    private let folder: URL

    init() {
        folder = FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0].appendingPathComponent("playlist-art")
        try? FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        pictures.totalCostLimit = 24 * 1024 * 1024
    }

    func knownPalette(_ key: String) -> CoverPalette? { palettes[key] }

    /// A list's colours, from its covers (artwork references); the list's own when it has none, or
    /// none could be read.
    func palette(id: String, covers: [String], key: String, client: SubsonicClient?, source: String?) async -> CoverPalette {
        if let known = palettes[key] { return known }
        guard !covers.isEmpty else {
            let own = coverPalette([], seed: id)
            palettes[key] = own
            return own
        }
        var swatches: [[CoverSwatch]] = []
        for cover in covers {
            guard let image = await ArtworkCache.shared.image(cover, px: 64, client: client, signedInSource: source),
                  let pixels = Self.pixels(of: image, side: 64) else { return coverPalette([], seed: id) }
            swatches.append(coverSwatches(pixels))
        }
        let found = coverPalette(swatches, seed: id)
        palettes[key] = found
        return found
    }

    func known(_ key: String) -> UIImage? { pictures.object(forKey: key as NSString) }

    /// The cover drawn `side` pixels square: kept, or drawn now away from the main thread.
    func art(_ spec: CoverSpec, side: Int) async -> UIImage? {
        let key = coverArtKey(spec, side: side)
        if let hit = pictures.object(forKey: key as NSString) { return hit }
        if let running = drawing[key] { return await running.value }
        let file = folder.appendingPathComponent(coverFileName(key, "png"))
        let task = Task<UIImage?, Never> {
            if let data = try? Data(contentsOf: file), let stored = UIImage(data: data) { return stored }
            guard let made = await self.draw(spec, side: side) else { return nil }
            if let png = made.pngData() { try? png.write(to: file, options: .atomic) }
            return made
        }
        drawing[key] = task
        let image = await task.value
        drawing[key] = nil
        if let image { pictures.setObject(image, forKey: key as NSString, cost: side * side * 4) }
        return image
    }

    private func draw(_ spec: CoverSpec, side: Int) async -> UIImage? {
        let plan = planCover(spec, side: side, setter: CoreTextCoverTypesetter())
        guard let full = background(plan.background) else { return nil }
        let image = await Task.detached(priority: .utility) { () -> CGImage? in
            // Turned before the veil, so the veil still keeps the words readable.
            let turned = orientBackground(sampleBackground(full.pixels, from: full.side, side: side), side: side, v: plan.orientation)
            let veiled = applyVeil(turned, side: side, regions: plan.veil)
            return CoverPainter.image(veiled, side: side, plan: plan)
        }.value
        return image.map { UIImage(cgImage: $0) }
    }

    private func background(_ background: CoverBackground) -> (pixels: [UInt32], side: Int)? {
        if let held = backgrounds.first(where: { $0.file == background.file }) { return (held.pixels, held.side) }
        let name = (background.file as NSString).deletingPathExtension
        guard let url = Bundle.module.url(forResource: name, withExtension: "webp", subdirectory: "CoverArt"),
              let image = UIImage(contentsOfFile: url.path), let cg = image.cgImage,
              let pixels = Self.pixels(of: UIImage(cgImage: cg), side: cg.width) else { return nil }
        backgrounds.append((background.file, pixels, cg.width))
        if backgrounds.count > 2 { backgrounds.removeFirst() }
        return (pixels, cg.width)
    }

    /// A picture's pixels, ARGB, `side` square.
    nonisolated static func pixels(of image: UIImage, side: Int) -> [UInt32]? {
        guard let cg = image.cgImage, side > 0 else { return nil }
        var out = [UInt32](repeating: 0, count: side * side)
        let info = CGImageAlphaInfo.premultipliedFirst.rawValue | CGBitmapInfo.byteOrder32Little.rawValue
        let drawn = out.withUnsafeMutableBytes { raw -> Bool in
            guard let context = CGContext(data: raw.baseAddress, width: side, height: side, bitsPerComponent: 8, bytesPerRow: side * 4,
                                          space: CGColorSpaceCreateDeviceRGB(), bitmapInfo: info) else { return false }
            context.interpolationQuality = .high
            context.draw(cg, in: CGRect(x: 0, y: 0, width: side, height: side))
            return true
        }
        return drawn ? out : nil
    }
}

/// A playlist's or live list's picture, as the listener chose: designed from its name (`line`
/// says what it is, `footer` how big) on colours from its covers, or its covers in a square.
/// `glyph` marks one of Octo's own lists, drawn in place of the words.
struct DesignedCover: View {
    let id: String
    let name: String
    let covers: [String]
    let size: CGFloat
    var radius: CGFloat = OctoRadius.artS
    var line: String? = playlistCoverLine
    var footer: String?
    var glyph: CoverGlyph?
    @Environment(Session.self) private var session
    @Environment(\.displayScale) private var scale
    @State private var palette: CoverPalette?
    @State private var shown: UIImage?

    var body: some View {
        let side = coverSide(Int((size * scale).rounded(.up)))
        let spec = palette.map { CoverSpec(id: id, name: name, line: line, footer: footer, palette: $0, glyph: glyph) }
        let ground = spec.map { Color(argb: backgroundColour(chooseBackground($0.id, $0.palette))) } ?? OctoColor.backgroundTertiary
        let shape = RoundedRectangle(cornerRadius: radius, style: .continuous)
        ZStack {
            ground
            // The last picture stays up while a changed one is drawn.
            if let shown { Image(uiImage: shown).resizable().interpolation(.high) }
        }
        .frame(width: size, height: size)
        .clipShape(shape)
        .overlay { if size >= 96 { shape.strokeBorder(.white.opacity(0.1), lineWidth: 1) } }
        .accessibilityHidden(true)
        .task(id: coverPaletteKey(session.inUse?.sourceId ?? "phone", covers)) {
            let key = coverPaletteKey(session.inUse?.sourceId ?? "phone", covers)
            if let known = await PlaylistArt.shared.knownPalette(key) {
                palette = known
            } else {
                palette = await PlaylistArt.shared.palette(id: id, covers: covers, key: key, client: session.client,
                                                           source: session.inUse?.sourceId)
            }
        }
        .task(id: spec.map { coverArtKey($0, side: side) }) {
            guard let spec else { return }
            if let image = await PlaylistArt.shared.art(spec, side: side) { shown = image }
        }
    }
}
