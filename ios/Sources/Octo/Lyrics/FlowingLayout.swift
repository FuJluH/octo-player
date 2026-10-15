import CoreText
import OctoKit
import UIKit

// Everything in a flowing line is sized from the main line's size (em).
private let MIN_LINE_PT: CGFloat = 22
private let MAX_LINE_PT: CGFloat = 36
private let ROW_HEIGHT_EM: CGFloat = 1.2
private let LINE_PADDING_EM: CGFloat = 0.25
private let WORD_GAP_EM: CGFloat = 0.25
private let EXTRA_SIZE_EM: CGFloat = 0.5
private let EXTRA_LINE_HEIGHT: CGFloat = 1.3
private let EXTRA_GAP_EM: CGFloat = 0.1
private let BACKGROUND_SIZE_EM: CGFloat = 0.75
private let BACKGROUND_MIN_PT: CGFloat = 12
private let CREDIT_SIZE_EM: CGFloat = 0.4
private let CREDIT_MIN_PT: CGFloat = 13

/// An interlude closed, in points.
private let INTERLUDE_IDLE_PT: CGFloat = 10

/// Text drawn in whatever fill color the drawing has set, so one layout serves every color.
private let fromContext = NSAttributedString.Key(kCTForegroundColorFromContextAttributeName as String)

/// One piece of text as Core Text laid it out on one line, to measure and to draw.
final class TextRun: @unchecked Sendable {
    let line: CTLine
    let width: CGFloat
    let ascent: CGFloat
    let descent: CGFloat
    let leading: CGFloat

    init(_ text: String, font: UIFont) {
        let attributed = NSAttributedString(string: text, attributes: [.font: font, fromContext: true])
        line = CTLineCreateWithAttributedString(attributed)
        var ascent: CGFloat = 0, descent: CGFloat = 0, leading: CGFloat = 0
        width = CGFloat(CTLineGetTypographicBounds(line, &ascent, &descent, &leading))
        self.ascent = ascent
        self.descent = descent
        self.leading = leading
    }

    /// The height a line of this text takes.
    var height: CGFloat { ascent + descent + leading }

    /// Where a character starts, from the run's left edge.
    func offset(ofUnit index: Int) -> CGFloat { CTLineGetOffsetForStringIndex(line, index, nil) }
}

/// A block of text drawn whole and wrapped to a width: a line timed by line, the credit, or a
/// translation or romanization under a line. `rtl` nil lets the text's own first strong letter
/// set its direction.
final class TextBlock: @unchecked Sendable {
    let text: NSAttributedString
    let frame: CTFrame
    let size: CGSize

    init(_ string: String, font: UIFont, width: CGFloat, lineHeight: CGFloat, alignRight: Bool, rtl: Bool?) {
        let paragraph = NSMutableParagraphStyle()
        paragraph.minimumLineHeight = lineHeight
        paragraph.maximumLineHeight = lineHeight
        paragraph.alignment = alignRight ? .right : .left
        paragraph.baseWritingDirection = rtl.map { $0 ? .rightToLeft : .leftToRight } ?? .natural
        paragraph.lineBreakMode = .byWordWrapping
        text = NSAttributedString(string: string, attributes: [.font: font, .paragraphStyle: paragraph, fromContext: true])
        let setter = CTFramesetterCreateWithAttributedString(text)
        let fit = CTFramesetterSuggestFrameSizeWithConstraints(setter, CFRange(location: 0, length: 0), nil,
                                                              CGSize(width: width, height: .greatestFiniteMagnitude), nil)
        size = CGSize(width: width, height: ceil(fit.height))
        frame = CTFramesetterCreateFrame(setter, CFRange(location: 0, length: 0),
                                         CGPath(rect: CGRect(x: 0, y: 0, width: width, height: size.height + 1), transform: nil), nil)
    }
}

/// A word as laid out: its text, where it is drawn, and the row it sits in.
struct WordBox: @unchecked Sendable {
    let run: TextRun
    let x: CGFloat
    let top: CGFloat
    let width: CGFloat
    let rowTop: CGFloat
    let rowHeight: CGFloat
}

/// One letter of a held word, drawn on its own so it can swell. `x` is from the word's left edge.
struct GlyphBox: @unchecked Sendable {
    let run: TextRun
    let x: CGFloat
    let width: CGFloat
}

/// A block drawn whole, and where.
struct TextPiece: @unchecked Sendable {
    let block: TextBlock
    let x: CGFloat
    let y: CGFloat
}

/// One line as laid out, in points from its own top left.
final class LineBox: @unchecked Sendable {
    let height: CGFloat
    /// Its main text's size.
    let em: CGFloat
    let font: UIFont
    /// Word by word, in the line's order; empty for a line drawn whole.
    let words: [WordBox]
    let block: TextPiece?
    let extras: [TextPiece]
    /// Where it grows from: the edge its text starts at.
    let pivotX: CGFloat
    /// Each held word's letters, while the line is near the focus.
    var glyphs: [[GlyphBox]?]?

    init(height: CGFloat, em: CGFloat, font: UIFont, words: [WordBox], block: TextPiece?, extras: [TextPiece], pivotX: CGFloat) {
        self.height = height
        self.em = em
        self.font = font
        self.words = words
        self.block = block
        self.extras = extras
        self.pivotX = pivotX
    }
}

/// The sizes every line shares, worked out from the view's width.
struct LyricsSpec: Sendable {
    let width: CGFloat
    let em: CGFloat
    let left: CGFloat
    let right: CGFloat
    let available: CGFloat
    let backgroundSize: CGFloat
    let creditSize: CGFloat
    let interludeIdle: CGFloat
    let interludeFull: CGFloat

    init(width: CGFloat, textScale: CGFloat) {
        self.width = width
        // Large enough to read at arm's length: about 30 points on a typical phone.
        let size = min(max(width / 13, MIN_LINE_PT), MAX_LINE_PT)
        em = size * textScale
        left = min(max(width * 0.06, 24), 48)
        right = min(max(width * 0.04, 16), 56)
        available = max(1, width - left - right)
        backgroundSize = max(BACKGROUND_SIZE_EM * em, BACKGROUND_MIN_PT)
        creditSize = max(CREDIT_SIZE_EM * em, CREDIT_MIN_PT)
        interludeIdle = INTERLUDE_IDLE_PT
        interludeFull = ROW_HEIGHT_EM * em + 2 * LINE_PADDING_EM * em
    }

    func font(_ size: CGFloat, credit: Bool = false) -> UIFont {
        UIFont.systemFont(ofSize: size, weight: credit ? .semibold : .heavy)
    }
}

/// All the lines as laid out for one width.
final class LyricsLayout: @unchecked Sendable {
    let spec: LyricsSpec
    let lines: [LineBox]

    init(spec: LyricsSpec, lines: [LineBox]) {
        self.spec = spec
        self.lines = lines
    }

    var width: CGFloat { spec.width }

    /// Heights for the engine; an interlude counts closed.
    func baseHeights() -> [Double] { lines.map { Double($0.height) } }

    /// Splits a line's held words (see `heldWords`; with `fast`, fast singing's held notes too)
    /// into letters, so they can swell one by one.
    func prepare(_ index: Int, _ line: SyncLine, fast: Bool) {
        let box = lines[index]
        if box.words.isEmpty { return }
        let held = heldWords(line.words, fast: fast)
        box.glyphs = line.words.indices.map { j in
            held[j] ? letters(box.words[j], line.words[j].text, box.font, rtl: line.rtl) : nil
        }
    }

    func release(_ index: Int) {
        lines[index].glyphs = nil
    }
}

/// Lays out one line.
func measureLine(_ line: SyncLine, _ spec: LyricsSpec) -> LineBox {
    let pivot = line.alignRight ? spec.left + spec.available : spec.left
    if line.isInterlude {
        return LineBox(height: spec.interludeIdle, em: spec.em, font: spec.font(spec.em), words: [], block: nil, extras: [], pivotX: pivot)
    }
    let em = line.isBackground ? spec.backgroundSize : (line.isCredit ? spec.creditSize : spec.em)
    let font = spec.font(em, credit: line.isCredit)
    let padding = LINE_PADDING_EM * em
    var bottom: CGFloat
    var words: [WordBox] = []
    var block: TextPiece?
    if line.isLineTimed || line.isCredit || line.words.isEmpty {
        let text = TextBlock(line.text, font: font, width: spec.available, lineHeight: ROW_HEIGHT_EM * em,
                             alignRight: line.alignRight, rtl: line.rtl)
        block = TextPiece(block: text, x: spec.left, y: padding)
        bottom = padding + text.size.height
    } else {
        words = flowWords(line, font, em, padding, spec)
        bottom = words.map { $0.rowTop + $0.rowHeight }.max() ?? padding
    }
    var extras: [TextPiece] = []
    let extraFont = UIFont.systemFont(ofSize: EXTRA_SIZE_EM * em, weight: .semibold)
    for text in [line.romanization, line.translation].compactMap({ $0 }) {
        bottom += EXTRA_GAP_EM * em
        let piece = TextBlock(text, font: extraFont, width: spec.available, lineHeight: EXTRA_LINE_HEIGHT * EXTRA_SIZE_EM * em,
                              alignRight: line.alignRight, rtl: nil)
        extras.append(TextPiece(block: piece, x: spec.left, y: bottom))
        bottom += piece.size.height
    }
    return LineBox(height: bottom + padding, em: em, font: font, words: words, block: block, extras: extras, pivotX: pivot)
}

/// Word by word: syllables of one word sit flush, a quarter em follows each whole word, and
/// whole words wrap to the next row. A group is never broken, so one wider than the room sits
/// alone on its row and runs past the right margin. Right-to-left lines run from the right;
/// right-aligned lines sit against the right edge.
private func flowWords(_ line: SyncLine, _ font: UIFont, _ em: CGFloat, _ padding: CGFloat, _ spec: LyricsSpec) -> [WordBox] {
    let measured = line.words.map { TextRun($0.text, font: font) }
    let gap = WORD_GAP_EM * em
    let rowHeight = ROW_HEIGHT_EM * em

    // Words into groups (one sung word each), groups into rows.
    var groups: [ClosedRange<Int>] = []
    var from = 0
    for (index, word) in line.words.enumerated() where word.trailingSpace || index == line.words.count - 1 {
        groups.append(from...index)
        from = index + 1
    }
    var rows: [[ClosedRange<Int>]] = []
    var used: CGFloat = 0
    for group in groups {
        let width = group.reduce(CGFloat(0)) { $0 + measured[$1].width }
        if let last = rows.last, last.isEmpty || used + width <= spec.available {
            rows[rows.count - 1].append(group)
            used += width + gap
        } else {
            rows.append([group])
            used = width + gap
        }
    }

    var boxes = [WordBox?](repeating: nil, count: line.words.count)
    for (r, row) in rows.enumerated() {
        let rowTop = padding + CGFloat(r) * rowHeight
        let rowWidth = row.reduce(CGFloat(0)) { sum, group in sum + group.reduce(CGFloat(0)) { $0 + measured[$1].width } }
            + gap * CGFloat(row.count - 1)
        let start = line.alignRight ? spec.left + spec.available - rowWidth : spec.left
        var along: CGFloat = 0
        for group in row {
            for index in group {
                let run = measured[index]
                let x = line.rtl ? start + rowWidth - along - run.width : start + along
                boxes[index] = WordBox(run: run, x: x, top: rowTop + (rowHeight - run.height) / 2, width: run.width,
                                       rowTop: rowTop, rowHeight: rowHeight)
                along += run.width
            }
            along += gap
        }
    }
    return boxes.compactMap { $0 }
}

/// A held word's letters (a letter being what reads as one character, so accents stay on their
/// letters), spaces left out. Right-to-left words stay whole, since their letters join and would
/// break apart if drawn singly.
private func letters(_ word: WordBox, _ text: String, _ font: UIFont, rtl: Bool) -> [GlyphBox] {
    if rtl { return [GlyphBox(run: word.run, x: 0, width: word.width)] }
    var glyphs: [GlyphBox] = []
    var unit = 0
    for character in text {
        let piece = String(character)
        defer { unit += piece.utf16.count }
        if piece.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { continue }
        let run = TextRun(piece, font: font)
        glyphs.append(GlyphBox(run: run, x: word.run.offset(ofUnit: unit), width: run.width))
    }
    return glyphs
}
