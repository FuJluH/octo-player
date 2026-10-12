import Foundation

/// The kinds of writing a cover sets differently: Latin, Greek, Cyrillic and the like (words between
/// spaces, tracked tight); Chinese, Japanese and Korean (wide, breaking between characters);
/// scripts with marks above and below the letters (Arabic, Hebrew, Thai, Devanagari and more),
/// which need room between lines; and emoji.
public enum CoverScript: Sendable {
    case latin, wide, tall, emoji
}

private func within(_ v: UInt32, _ ranges: [ClosedRange<UInt32>]) -> Bool { ranges.contains { $0.contains(v) } }

/// Han, Hiragana, Katakana, Hangul and Bopomofo.
func isWideScript(_ scalar: Unicode.Scalar) -> Bool {
    within(scalar.value, [0x1100...0x11FF, 0x2E80...0x2FDF, 0x3005...0x3007, 0x3021...0x3029, 0x3038...0x303B, 0x3040...0x30FF,
                          0x3100...0x312F, 0x3130...0x318F, 0x31A0...0x31BF, 0x31F0...0x31FF, 0x3400...0x4DBF, 0x4E00...0x9FFF,
                          0xA960...0xA97F, 0xAC00...0xD7FF, 0xF900...0xFAFF, 0xFF66...0xFFDC, 0x1B000...0x1B16F,
                          0x20000...0x323AF])
}

/// Arabic, Hebrew, Syriac, Thaana and N'Ko.
private func isRightToLeftScript(_ scalar: Unicode.Scalar) -> Bool {
    within(scalar.value, [0x0590...0x05FF, 0x0600...0x06FF, 0x0700...0x074F, 0x0750...0x077F, 0x0780...0x07BF, 0x07C0...0x07FF,
                          0x0860...0x086F, 0x0870...0x08FF, 0xFB1D...0xFB4F, 0xFB50...0xFDFF, 0xFE70...0xFEFF])
}

/// Latin, Greek, Cyrillic, Armenian and Georgian.
private func isSpacedScript(_ scalar: Unicode.Scalar) -> Bool {
    within(scalar.value, [0x0041...0x024F, 0x0250...0x02AF, 0x0370...0x03FF, 0x0400...0x052F, 0x0531...0x058F, 0x10A0...0x10FF,
                          0x1C80...0x1C8F, 0x1C90...0x1CBF, 0x1D00...0x1DBF, 0x1E00...0x1EFF, 0x1F00...0x1FFF, 0x2C60...0x2C7F,
                          0x2D00...0x2D2F, 0x2DE0...0x2DFF, 0xA640...0xA69F, 0xA720...0xA7FF, 0xAB30...0xAB6F, 0xFB00...0xFB17,
                          0xFF21...0xFF3A, 0xFF41...0xFF5A])
}

func isEmojiScalar(_ v: UInt32) -> Bool {
    (0x1F000...0x1FAFF).contains(v) || (0x2600...0x27BF).contains(v) || (0x2B00...0x2BFF).contains(v) || (0x1F900...0x1F9FF).contains(v)
}

private func isLetter(_ scalar: Unicode.Scalar) -> Bool {
    switch scalar.properties.generalCategory {
    case .uppercaseLetter, .lowercaseLetter, .titlecaseLetter, .modifierLetter, .otherLetter: true
    default: false
    }
}

/// The writing most of the text is in; digits, spaces and marks do not count.
public func coverScript(_ text: String) -> CoverScript {
    var latin = 0, wide = 0, tall = 0, emoji = 0
    for scalar in text.unicodeScalars {
        if isEmojiScalar(scalar.value) {
            emoji += 1
        } else if !isLetter(scalar) {
            continue
        } else if isWideScript(scalar) {
            wide += 1
        } else if isSpacedScript(scalar) {
            latin += 1
        } else {
            tall += 1
        }
    }
    let most = max(latin, wide, tall, emoji)
    if most == 0 || most == latin { return .latin }
    if most == wide { return .wide }
    if most == tall { return .tall }
    return .emoji
}

/// Whether the text reads right to left: its first letter decides.
public func isRightToLeft(_ text: String) -> Bool {
    for scalar in text.unicodeScalars where isLetter(scalar) { return isRightToLeftScript(scalar) }
    return false
}

/// The pieces of the text that cannot be broken across lines: words between spaces, while wide
/// characters (Chinese, Japanese, Korean) each stand alone.
public func unbreakableRuns(_ text: String) -> [String] {
    var runs: [String] = []
    var word = String.UnicodeScalarView()
    func end() {
        if !word.isEmpty { runs.append(String(word)) }
        word = String.UnicodeScalarView()
    }
    for scalar in text.unicodeScalars {
        if scalar.properties.isWhitespace {
            end()
        } else if isWideScript(scalar) {
            end()
            runs.append(String(scalar))
        } else {
            word.append(scalar)
        }
    }
    end()
    return runs
}

/// How words on a cover are set: size in pixels, weight (600 semibold and so on), the space between
/// letters (a share of the size) and between lines (times the size), and how many lines at most.
public struct CoverType: Equatable, Sendable {
    public var sizePx: Float
    public var weight: Int
    public var tracking: Float
    public var lineHeight: Float
    public var maxLines: Int

    public init(sizePx: Float, weight: Int, tracking: Float, lineHeight: Float, maxLines: Int) {
        self.sizePx = sizePx
        self.weight = weight
        self.tracking = tracking
        self.lineHeight = lineHeight
        self.maxLines = maxLines
    }

    func with(size: Float, maxLines lines: Int? = nil) -> CoverType {
        var copy = self
        copy.sizePx = size
        if let lines { copy.maxLines = lines }
        return copy
    }
}

/// What the app's text engine found for some words set in a width: how many lines, the widest
/// line, the height, and whether some words did not fit.
public struct Measured: Equatable, Sendable {
    public var lines: Int
    public var width: Float
    public var height: Float
    public var cut: Bool

    public init(lines: Int, width: Float, height: Float, cut: Bool) {
        self.lines = lines
        self.width = width
        self.height = height
        self.cut = cut
    }
}

/// The app's text engine, as the cover's design needs it.
public protocol CoverTypesetter {
    /// The text wrapped in `width`, at most `type.maxLines` lines.
    func measure(_ text: String, _ type: CoverType, width: Float) -> Measured
    /// The text on one line.
    func widthOf(_ text: String, _ type: CoverType) -> Float
}

/// The space between lines for this writing: at least `wanted`, with room for the marks above and
/// below the letters in the scripts that have them.
public func coverLineHeight(_ script: CoverScript, _ wanted: Float) -> Float {
    switch script {
    case .latin: wanted
    case .wide, .emoji: max(wanted, 1.15)
    case .tall: max(wanted, 1.4)
    }
}

/// Words set to fit: the type chosen and what it measured.
public struct FittedText: Equatable, Sendable {
    public var text: String
    public var type: CoverType
    public var measured: Measured
}

/// The largest size from `minPx` to `maxPx` (whole pixels) at which the text fits a box `width` by
/// `height` in at most `maxLines` lines with no word broken, or nil when even the smallest does not.
public func fitOrNull(_ text: String, width: Float, height: Float, maxLines: Int, minPx: Float, maxPx: Float, look: CoverType,
                      setter: CoverTypesetter) -> FittedText? {
    let runs = unbreakableRuns(text)
    func typeAt(_ size: Float) -> CoverType { look.with(size: size, maxLines: maxLines) }
    func fits(_ size: Float) -> Measured? {
        let type = typeAt(size)
        if runs.contains(where: { setter.widthOf($0, type) > width }) { return nil }
        let measured = setter.measure(text, type, width: width)
        return !measured.cut && measured.lines <= maxLines && measured.height <= height ? measured : nil
    }
    var low = max(floor(minPx), 1)
    var high = max(floor(maxPx), low)
    if let top = fits(high) { return FittedText(text: text, type: typeAt(high), measured: top) }
    guard var best = fits(low) else { return nil }
    while high - low > 1 {
        let mid = floor((low + high) / 2)
        if let measured = fits(mid) {
            low = mid
            best = measured
        } else {
            high = mid
        }
    }
    return FittedText(text: text, type: typeAt(low), measured: best)
}

/// As fitOrNull, but when nothing fits: the smallest size, with as many lines as the box holds and
/// the rest cut.
public func fitCoverText(_ text: String, width: Float, height: Float, maxLines: Int, minPx: Float, maxPx: Float, look: CoverType,
                         setter: CoverTypesetter) -> FittedText {
    if let fitted = fitOrNull(text, width: width, height: height, maxLines: maxLines, minPx: minPx, maxPx: maxPx, look: look,
                              setter: setter) {
        return fitted
    }
    let size = max(floor(minPx), 1)
    // A word too long for the width even at the smallest is cut on one line rather than broken
    // across two.
    let tooLong = unbreakableRuns(text).contains { setter.widthOf($0, look.with(size: size)) > width }
    let lines = tooLong ? 1 : min(max(Int(height / (size * look.lineHeight)), 1), maxLines)
    let type = look.with(size: size, maxLines: lines)
    return FittedText(text: text, type: type, measured: setter.measure(text, type, width: width))
}
