import Foundation

// A playlist's cover: one of the painted backgrounds (chosen by the list's music), the
// colour-keeping veil where the words sit, and white words at the top left (its name large, a light
// line under it saying what it is) with a small line at the foot.

/// What a cover is made from: whose it is (its id), the name, the light line under it ("Playlist",
/// "Live list"), the small line at the foot ("12 songs", "By sam"), and its music's colour.
/// `coverTitle` is shorter words the server gives a list's cover in place of its name; `glyph`,
/// when set, is drawn in place of every word.
public struct CoverSpec: Equatable, Sendable {
    public var id: String
    public var name: String
    public var line: String?
    public var footer: String?
    public var palette: CoverPalette
    public var coverTitle: String?
    public var glyph: CoverGlyph?

    public init(id: String, name: String, line: String?, footer: String?, palette: CoverPalette, coverTitle: String? = nil,
                glyph: CoverGlyph? = nil) {
        self.id = id
        self.name = name
        self.line = line
        self.footer = footer
        self.palette = palette
        self.coverTitle = coverTitle
        self.glyph = glyph
    }
}

public enum CoverAlign: Sendable { case left, right }

/// Which words: the name, the line under it, or the foot line.
public enum CoverRole: Sendable { case title, line, footer }

/// Words on a cover: which, what, how they are set, the box they are set in, how they sit in it,
/// their colour (white, perhaps partly see-through), and what they measured.
public struct CoverWords: Equatable, Sendable {
    public var role: CoverRole
    public var text: String
    public var type: CoverType
    public var left: Float
    public var top: Float
    public var width: Float
    public var align: CoverAlign
    public var ink: UInt32
    public var measured: Measured

    public var height: Float { measured.height }

    /// Where the letters themselves are, as left, top, right, bottom.
    public var inked: [Float] {
        let w = min(measured.width, width)
        let x = align == .left ? left : left + width - w
        return [x, top, x + w, top + measured.height]
    }
}

/// A cover ready to paint: its side in pixels, its background and which way it is turned, its words
/// or its glyph, and the veil's regions under them.
public struct CoverPlan: Equatable, Sendable {
    public var side: Int
    public var background: CoverBackground
    public var orientation: Int
    public var words: [CoverWords]
    public var veil: [VeilRegion]
    public var glyph: GlyphDrawing?
}

private let white: UInt32 = 0xFFFF_FFFF

/// Everything about a cover `side` pixels square but its pixels: the words measured by the app's
/// own text engine.
public func planCover(_ spec: CoverSpec, side: Int, setter: CoverTypesetter, book: CoverBook = .standard,
                      library: CoverBackgrounds = .standard) -> CoverPlan {
    let background = chooseBackground(spec.id, spec.palette, library: library, rule: book.background)
    let orientation = coverOrientation(spec.id, rule: book.background)
    if let glyph = spec.glyph, let numbers = book.glyphs {
        let drawing = glyphDrawing(glyph, side: side, numbers: numbers)
        return CoverPlan(side: side, background: background, orientation: orientation, words: [],
                         veil: [glyphVeilRegion(drawing, numbers: numbers, book: book)], glyph: drawing)
    }
    let words = coverWords(spec, side: side, setter: setter, book: book)
    return CoverPlan(side: side, background: background, orientation: orientation, words: words,
                     veil: veilRegions(words, side: side, book: book))
}

/// Where the words go.
public func coverWords(_ spec: CoverSpec, side: Int, setter: CoverTypesetter, book: CoverBook = .standard) -> [CoverWords] {
    let layout = book.layout
    let s = Float(side)
    let shown = coverTitle(spec.name, line: spec.line, coverTitle: spec.coverTitle)
    let align: CoverAlign = isRightToLeft(shown.title) ? .right : .left
    let name = shown.title
    // A small cover is its artwork alone: at a list's row size the name is beside it anyway.
    if side < layout.tinyBelowPx { return [] }
    let margin = (s * layout.margin).rounded()
    let width = s - 2 * margin
    var out: [CoverWords] = []
    var foot: CoverWords?

    // The foot line first, so the name knows how far down it may go.
    var floor = s - margin
    if let footerText = spec.footer?.trimmingCharacters(in: .whitespacesAndNewlines), !footerText.isEmpty,
       side >= layout.footer.showFromPx {
        let f = layout.footer
        let look = CoverType(sizePx: 0, weight: f.weight, tracking: f.tracking, lineHeight: coverLineHeight(coverScript(footerText), f.lineHeight),
                             maxLines: 1)
        let size = max(f.minPx, s * f.size)
        let fit = fitCoverText(footerText, width: width, height: s * 0.2, maxLines: 1, minPx: f.minPx, maxPx: size, look: look, setter: setter)
        let top = s - s * f.bottom - fit.measured.height
        foot = CoverWords(role: .footer, text: footerText, type: fit.type, left: margin, top: top, width: width, align: align,
                          ink: withAlpha(white, f.opacity), measured: fit.measured)
        floor = top - s * 0.04
    }
    if name.isEmpty { return foot.map { [$0] } ?? [] }

    let t = layout.title
    let top = s * t.top
    let lineText = side >= layout.line.showFromPx ? shown.line : nil
    let lineRoom: Float = lineText == nil ? 0 : max(s * t.wrapSize, t.wrapMinPx) * layout.line.shareOfTitle * layout.line.lineHeight
    let room = floor - top - lineRoom
    let look = CoverType(sizePx: 0, weight: t.weight, tracking: t.tracking, lineHeight: coverLineHeight(coverScript(name), t.lineHeight),
                         maxLines: 1)
    let minPx = max(t.minPx, s * t.minSize)
    let oneLineLeast = max(minPx, max(s * t.oneLineDownTo, t.oneLineMinPx))
    let wrapMost = max(minPx, max(s * t.wrapSize, min(t.wrapMinPx, s * t.size)))
    let oneLine = oneLineLeast <= s * t.size
        ? fitOrNull(name, width: width, height: room, maxLines: 1, minPx: oneLineLeast, maxPx: s * t.size, look: look, setter: setter)
        : nil
    let title = oneLine ?? fitCoverText(name, width: width, height: room, maxLines: t.maxLines, minPx: minPx, maxPx: wrapMost, look: look,
                                        setter: setter)
    out.append(CoverWords(role: .title, text: name, type: title.type, left: margin, top: top, width: width, align: align, ink: white,
                          measured: title.measured))

    if let lineText {
        let l = layout.line
        let lineTop = top + title.measured.height
        let most = max(l.minPx, title.type.sizePx * l.shareOfTitle)
        let lineLook = CoverType(sizePx: 0, weight: l.weight, tracking: l.tracking,
                                 lineHeight: coverLineHeight(coverScript(lineText), l.lineHeight), maxLines: 1)
        let fit = fitCoverText(lineText, width: width, height: s, maxLines: 1, minPx: min(l.minPx, most), maxPx: most, look: lineLook,
                               setter: setter)
        if lineTop + fit.measured.height <= floor {
            out.append(CoverWords(role: .line, text: lineText, type: fit.type, left: margin, top: lineTop, width: width, align: align,
                                  ink: white, measured: fit.measured))
        }
    }
    return out + (foot.map { [$0] } ?? [])
}

/// The words a cover sets large and the light line under them.
public struct CoverTitle: Equatable, Sendable {
    public var title: String
    public var line: String?
}

/// A name ending in a word that says what the list is (Mix, Radio, Chart) is set as two lines,
/// "Discovery" over "Mix", "Bad Bunny" over "Station", whatever kind of list it is; "Your Mix"
/// and the like stay whole. A `coverTitle` from the server is set as it is. Otherwise the name is
/// set whole over `line`, unless the name already says what it is.
public func coverTitle(_ name: String, line: String?, coverTitle: String? = nil) -> CoverTitle {
    let shown = name.trimmingCharacters(in: .whitespacesAndNewlines)
    var title = coverTitle?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty ?? shown
    var said = line?.trimmingCharacters(in: .whitespacesAndNewlines).nilIfEmpty
    if title == shown {
        for (suffix, word) in kindSuffixes {
            guard shown.lowercased().hasSuffix(suffix.lowercased()) else { continue }
            let head = String(shown.dropLast(suffix.count)).trimmingCharacters(in: .whitespacesAndNewlines)
            if head.count > 1, !possessives.contains(where: { $0.caseInsensitiveCompare(head) == .orderedSame }) {
                title = head
                said = word
                break
            }
        }
    }
    return CoverTitle(title: title, line: !title.isEmpty && !nameSaysWhatItIs(title) ? said : nil)
}

/// Name endings that say what a list is, and the word the light line uses for each.
private let kindSuffixes = [(" Radio", stationCoverLine), (" Chart", chartCoverLine), (" Mix", mixCoverLine)]

/// Names that keep their kind word: "Your Mix" stays "Your Mix".
private let possessives = ["Your", "My", "Our"]

/// Whether a name already ends with the word the second line would add ("Road Trip Playlist",
/// "Your Mix"). Only a whole last word counts: "Mixtape" does not.
public func nameSaysWhatItIs(_ name: String) -> Bool {
    var words: [String] = []
    var word = ""
    for scalar in name.unicodeScalars {
        let category = scalar.properties.generalCategory
        let letterOrDigit = scalar.properties.isAlphabetic || category == .decimalNumber || category == .letterNumber
            || category == .otherNumber
        if letterOrDigit {
            word.unicodeScalars.append(scalar)
        } else if !word.isEmpty {
            words.append(word)
            word = ""
        }
    }
    if !word.isEmpty { words.append(word) }
    guard let last = words.last else { return false }
    return kindWords.contains(last.lowercased())
}

private let kindWords: Set<String> = ["mix", "mixes", "radio", "radios", "station", "stations", "playlist", "playlists"]

private extension String {
    var nilIfEmpty: String? { isEmpty ? nil : self }
}

// MARK: Backgrounds

/// A list's background from the library: with music, one of the few whose strongest hues and
/// lightness are nearest the music's colour; without, or with music too dull to say much, any,
/// from a hash of its id. Always the same one for the same list and music.
public func chooseBackground(_ id: String, _ palette: CoverPalette, library: CoverBackgrounds = .standard,
                             rule: BackgroundRule = CoverBook.standard.background) -> CoverBackground {
    let all = library.backgrounds
    let pick = coverPick(id) >> 7
    if !palette.fromMusic || palette.chroma < rule.lowChromaAsGrey { return all[Int(pick % Int64(all.count))] }
    let distances: [Double] = all.map { backgroundDistance($0, palette, rule: rule) }
    let order: [Int] = all.indices.sorted { a, b in
        distances[a] != distances[b] ? distances[a] < distances[b] : a < b
    }
    let near: [CoverBackground] = order.prefix(rule.nearest).map { all[$0] }
    return near[Int(pick % Int64(near.count))]
}

/// How far a background is from the music's colour.
func backgroundDistance(_ background: CoverBackground, _ palette: CoverPalette, rule: BackgroundRule) -> Double {
    let hue = background.hues.enumerated().map { i, h -> Double in
        let grey = h.c < rule.greyBelow ? rule.greyPenalty : 0
        return hueDistance(h.h, Double(palette.hue)) / 180 + Double(i) * rule.hueStep + grey + abs(h.c - palette.chroma) * rule.chromaWeight
    }.min() ?? 1
    return hue + abs(background.meanLightness - palette.lightness) * rule.lightnessWeight
}

/// Which way a list turns its background, 0 to count - 1.
public func coverOrientation(_ id: String, rule: BackgroundRule = CoverBook.standard.background) -> Int {
    Int((coverPick(id) >> Int64(rule.orientation.shift)) % Int64(rule.orientation.count))
}

/// ARGB pixels, `side` square, turned (v mod 4) quarter turns clockwise, then mirrored left to
/// right when v >= 4.
public func orientBackground(_ pixels: [UInt32], side: Int, v: Int) -> [UInt32] {
    let turns = v % 4
    let mirror = v >= 4
    if turns == 0 && !mirror { return pixels }
    return (0..<(side * side)).map { i in
        var x = i % side
        let y = i / side
        if mirror { x = side - 1 - x }
        let (sx, sy): (Int, Int) = switch turns {
        case 1: (y, side - 1 - x)
        case 2: (side - 1 - x, side - 1 - y)
        case 3: (side - 1 - y, x)
        default: (x, y)
        }
        return pixels[sy * side + sx]
    }
}

/// A background's pixels (ARGB, `from` square) at `side`: halved while that still leaves at least
/// `side`, then each output pixel the mean of the area it covers.
public func sampleBackground(_ pixels: [UInt32], from: Int, side: Int) -> [UInt32] {
    var current = pixels
    var size = from
    while side * 2 <= size && size % 2 == 0 {
        current = halve(current, size)
        size /= 2
    }
    return size == side ? current : areaAverage(current, from: size, side: side)
}

private func halve(_ pixels: [UInt32], _ size: Int) -> [UInt32] {
    let half = size / 2
    return (0..<(half * half)).map { i in
        let x = (i % half) * 2, y = (i / half) * 2
        let a = pixels[y * size + x], b = pixels[y * size + x + 1], c = pixels[(y + 1) * size + x], d = pixels[(y + 1) * size + x + 1]
        func ch(_ shift: UInt32) -> Int {
            (Int(a >> shift & 0xFF) + Int(b >> shift & 0xFF) + Int(c >> shift & 0xFF) + Int(d >> shift & 0xFF) + 2) / 4
        }
        return opaque(ch(16), ch(8), ch(0))
    }
}

/// Each output pixel the mean of the source area it covers, part pixels in proportion, across then
/// down.
private func areaAverage(_ pixels: [UInt32], from: Int, side: Int) -> [UInt32] {
    let scale = Double(from) / Double(side)
    let spans: [(start: Int, weights: [Double])] = (0..<side).map { o in
        let a = Double(o) * scale, b = Double(o + 1) * scale
        let start = min(max(Int(a.rounded(.down)), 0), from - 1)
        let end = max(min(from, Int(b.rounded(.up))), start + 1)
        return (start, (0..<(end - start)).map { k in
            let lo = max(a, Double(start + k)), hi = min(b, Double(start + k + 1))
            return max(0, hi - lo) / (b - a)
        })
    }
    var across = [[Double]](repeating: [Double](repeating: 0, count: side * from), count: 3)
    for y in 0..<from {
        for x in 0..<side {
            let span = spans[x]
            var r = 0.0, g = 0.0, bl = 0.0
            for k in span.weights.indices {
                let p = pixels[y * from + span.start + k]
                let w = span.weights[k]
                r += Double(red(p)) * w
                g += Double(green(p)) * w
                bl += Double(blue(p)) * w
            }
            across[0][y * side + x] = r
            across[1][y * side + x] = g
            across[2][y * side + x] = bl
        }
    }
    return (0..<(side * side)).map { i in
        let x = i % side
        let span = spans[i / side]
        func ch(_ c: Int) -> Int {
            var v = 0.0
            for k in span.weights.indices { v += across[c][(span.start + k) * side + x] * span.weights[k] }
            return min(max(Int(v.rounded()), 0), 255)
        }
        return opaque(ch(0), ch(1), ch(2))
    }
}

/// A colour standing for a background while its picture is made: its strongest hue.
public func backgroundColour(_ background: CoverBackground) -> UInt32 {
    background.hues.first.map { lchToArgb($0.l, $0.c, $0.h) } ?? 0xFF20_2020
}

// MARK: Playlist covers

/// The light line under a cover's name: what the list is.
public let playlistCoverLine = "Playlist"
public let liveListCoverLine = "Live list"
public let stationCoverLine = "Station"
public let chartCoverLine = "Chart"
public let mixCoverLine = "Mix"

/// The small line at a cover's foot: whose it is when it is someone else's, else how many songs it
/// has (nothing while it has none).
public func playlistCoverFooter(_ songCount: Int, owner: String? = nil, you: String? = nil) -> String? {
    if let owner, let you, !owner.trimmingCharacters(in: .whitespaces).isEmpty, !you.trimmingCharacters(in: .whitespaces).isEmpty,
       owner.caseInsensitiveCompare(you) != .orderedSame {
        return "By \(owner)"
    }
    if songCount == 1 { return "1 song" }
    return songCount > 1 ? "\(grouped(songCount)) songs" : nil
}

/// Bumped whenever the drawing changes, so covers kept on disk are made again.
public let coverDesignVersion = 4

/// Bumped whenever the colours are picked differently.
public let coverPaletteVersion = 2

/// The size a cover shown `px` wide is drawn at: the next step up, fine where a pixel shows (every
/// 4 up to 128), coarser above (16 up to 512, then 64).
public func coverSide(_ px: Int) -> Int {
    let p = min(max(px, 16), 2048)
    func up(_ step: Int) -> Int { (p + step - 1) / step * step }
    if p <= 128 { return up(4) }
    return p <= 512 ? up(16) : up(64)
}

/// What a drawn cover is kept under: the design's version, the book's and the library's, the
/// background, the playlist, the size, and its words.
public func coverArtKey(_ spec: CoverSpec, side: Int, book: CoverBook = .standard, library: CoverBackgrounds = .standard) -> String {
    let text = [spec.name, spec.line ?? "", spec.footer ?? "", spec.coverTitle ?? "", spec.glyph?.rawValue ?? ""].joined(separator: "\n")
    let words = String(coverHash(text), radix: 36)
    var background = chooseBackground(spec.id, spec.palette, library: library, rule: book.background).file
    if background.hasSuffix(".webp") { background = String(background.dropLast(5)) }
    let look = "\(book.version).\(library.version).\(background).\(coverOrientation(spec.id, rule: book.background))"
    return "playlist-art:v\(coverDesignVersion):\(look):\(spec.id):\(side):\(words)"
}

/// What a playlist's colours are kept under: the server, and the covers they come from (in order).
public func coverPaletteKey(_ server: String, _ sources: [String]) -> String {
    "playlist-palette:v\(coverPaletteVersion):\(server):\(sources.joined(separator: "|"))"
}

/// A name for a file holding something kept under `key`: short, and safe on every system.
public func coverFileName(_ key: String, _ ext: String) -> String {
    let a = UInt64(bitPattern: coverHash(key)), b = UInt64(bitPattern: coverPick(key))
    return String(format: "%016llx%016llx", a, b) + "." + ext
}

/// Up to four covers for a list's colours, one per album in the order its songs come.
public func coverSources(_ albumCovers: [(album: String?, cover: String?)], most: Int = 4) -> [String] {
    var seen = Set<String>()
    var out: [String] = []
    for (album, cover) in albumCovers {
        guard let cover, out.count < most, seen.insert(album ?? cover).inserted else { continue }
        out.append(cover)
    }
    return out
}
