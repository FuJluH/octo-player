import Foundation

// The text rules the lyrics and song matching code is written against. Positions, lengths and
// slices count UTF-16 units, white space and letter tests look at one unit at a time, case
// mapping is the simple one-to-one mapping, and regular expressions keep the classic engine's
// meaning of `.`, `$`, `\s`, `\d` and ignore-case. Writing them down once keeps every reading of
// a title, a credit or a lyric line the same as on the other apps and the server.

// MARK: - Units

extension String {
    /// The text as UTF-16 units.
    var units: [UInt16] { Array(utf16) }

    /// Text made from UTF-16 units. A unit left without its pair becomes U+FFFD.
    init(units: some Collection<UInt16>) {
        self = String(decoding: units, as: UTF16.self)
    }

    /// The units from `from` up to, not including, `to`.
    func utf16Slice(_ from: Int, _ to: Int) -> String {
        let all = units
        return String(units: all[from..<to])
    }

    /// The units from `from` to the end.
    func utf16Slice(from: Int) -> String {
        let all = units
        return String(units: all[from...])
    }

    /// The same units in the same order: no reading of accents as equal.
    func utf16Equals(_ other: String) -> Bool {
        utf16.elementsEqual(other.utf16)
    }

    /// The first place `other` starts, in units, or -1.
    func utf16Index(of other: String) -> Int {
        let hay = units
        let needle = other.units
        if needle.isEmpty { return 0 }
        if needle.count > hay.count { return -1 }
        var i = 0
        while i <= hay.count - needle.count {
            if hay[i] == needle[0] && Array(hay[i..<(i + needle.count)]) == needle { return i }
            i += 1
        }
        return -1
    }

    func utf16Contains(_ other: String) -> Bool { utf16Index(of: other) >= 0 }

    /// Every `target` replaced by `replacement`, left to right, never overlapping.
    func replacingAll(_ target: String, _ replacement: String) -> String {
        let hay = units
        let needle = target.units
        if needle.isEmpty || needle.count > hay.count { return self }
        let put = replacement.units
        var out: [UInt16] = []
        out.reserveCapacity(hay.count)
        var i = 0
        while i < hay.count {
            if i <= hay.count - needle.count && hay[i] == needle[0] && Array(hay[i..<(i + needle.count)]) == needle {
                out += put
                i += needle.count
            } else {
                out.append(hay[i])
                i += 1
            }
        }
        return String(units: out)
    }

    /// Every unit `from` replaced by `to`.
    func replacingUnit(_ from: UInt16, with to: UInt16) -> String {
        String(units: utf16.map { $0 == from ? to : $0 })
    }

    /// The units that pass `keep`.
    func filterUnits(_ keep: (UInt16) -> Bool) -> String {
        String(units: utf16.filter(keep))
    }

    /// Units that pass `strip` taken off both ends.
    func trimUnits(_ strip: (UInt16) -> Bool) -> String {
        let all = units
        var start = 0
        var end = all.count
        while start < end && strip(all[start]) { start += 1 }
        while end > start && strip(all[end - 1]) { end -= 1 }
        return String(units: all[start..<end])
    }

    /// Units that pass `strip` taken off the start.
    func trimStartUnits(_ strip: (UInt16) -> Bool) -> String {
        let all = units
        var start = 0
        while start < all.count && strip(all[start]) { start += 1 }
        return String(units: all[start...])
    }

    /// Units that pass `strip` taken off the end.
    func trimEndUnits(_ strip: (UInt16) -> Bool) -> String {
        let all = units
        var end = all.count
        while end > 0 && strip(all[end - 1]) { end -= 1 }
        return String(units: all[..<end])
    }

    /// White space taken off both ends.
    func trimWhitespace() -> String { trimUnits(isWhitespaceUnit) }

    /// White space taken off the start.
    func trimStartWhitespace() -> String { trimStartUnits(isWhitespaceUnit) }

    /// Nothing but white space, or empty.
    var isBlankText: Bool { utf16.allSatisfy(isWhitespaceUnit) }

    /// The text with its white space left out.
    func removingWhitespace() -> String { filterUnits { !isWhitespaceUnit($0) } }

    /// The lines of the text, split at "\r\n", "\n" and "\r". A line break at the end leaves an
    /// empty last line.
    func splitLines() -> [String] {
        let all = units
        var lines: [String] = []
        var start = 0
        var i = 0
        while i < all.count {
            let unit = all[i]
            if unit == 0x0A || unit == 0x0D {
                lines.append(String(units: all[start..<i]))
                if unit == 0x0D && i + 1 < all.count && all[i + 1] == 0x0A { i += 1 }
                start = i + 1
            }
            i += 1
        }
        lines.append(String(units: all[start...]))
        return lines
    }

    /// The text with `prefix` taken off its start, when it starts with it.
    func removingPrefix(_ prefix: String) -> String {
        let all = units
        let head = prefix.units
        if all.count >= head.count && Array(all[..<head.count]) == head { return String(units: all[head.count...]) }
        return self
    }

    /// Whether the text starts with `prefix`, letters compared one unit at a time ignoring case.
    func startsWith(_ prefix: String, ignoreCase: Bool) -> Bool {
        let all = units
        let head = prefix.units
        if head.count > all.count { return false }
        for i in head.indices where !unitsMatch(all[i], head[i], ignoreCase: ignoreCase) { return false }
        return true
    }

    /// The same length, and each unit the same ignoring case.
    func equalsIgnoreCase(_ other: String) -> Bool {
        let a = units
        let b = other.units
        if a.count != b.count { return false }
        for i in a.indices where !unitsMatch(a[i], b[i], ignoreCase: true) { return false }
        return true
    }

    /// Lowercase in the root language: each letter by its own mapping, and a capital sigma at
    /// the end of a word as a final sigma.
    func lowercaseRoot() -> String {
        let all = units
        // A capital I with a dot, or anything outside the basic plane, takes the full reading
        // of the final sigma; everything else looks only at the letters either side.
        let full = all.contains(0x130) || all.contains { $0 >= 0xD800 && $0 <= 0xDBFF }
        if full { return lowercaseFull() }
        var out: [UInt16] = []
        out.reserveCapacity(all.count)
        for i in all.indices {
            let ch = all[i]
            if ch == 0x3A3 && isFinalSigma(all, i) {
                out.append(0x3C2)
            } else {
                out.append(simpleLower(ch))
            }
        }
        return String(units: out)
    }

    private func lowercaseFull() -> String {
        let scalars = Array(unicodeScalars)
        var out = String.UnicodeScalarView()
        for i in scalars.indices {
            let scalar = scalars[i]
            if scalar.value == 0x3A3 {
                var before = false
                var j = i - 1
                while j >= 0 {
                    let p = scalars[j].properties
                    if p.isCaseIgnorable { j -= 1; continue }
                    before = p.isCased
                    break
                }
                var after = false
                j = i + 1
                while j < scalars.count {
                    let p = scalars[j].properties
                    if p.isCaseIgnorable { j += 1; continue }
                    after = p.isCased
                    break
                }
                out.append(Unicode.Scalar(before && !after ? 0x3C2 : 0x3C3)!)
            } else {
                out.append(contentsOf: scalar.properties.lowercaseMapping.unicodeScalars)
            }
        }
        return String(out)
    }

    /// Uppercase in the root language, each letter by its full mapping ("ß" as "SS").
    func uppercaseRoot() -> String { uppercased() }
}

// A capital sigma is final when the unit before it is a cased letter and the one after it is not.
private func isFinalSigma(_ text: [UInt16], _ index: Int) -> Bool {
    if index <= 0 { return false }
    if !isCasedUnit(text[index - 1]) { return false }
    if index + 1 >= text.count { return true }
    return !isCasedUnit(text[index + 1])
}

private func isCasedUnit(_ unit: UInt16) -> Bool {
    switch generalCategory(unit) {
    case .lowercaseLetter, .uppercaseLetter, .titlecaseLetter: return true
    default: return false
    }
}

private func unitsMatch(_ a: UInt16, _ b: UInt16, ignoreCase: Bool) -> Bool {
    if a == b { return true }
    if !ignoreCase { return false }
    let upperA = simpleUpper(a)
    let upperB = simpleUpper(b)
    if upperA == upperB { return true }
    return simpleLower(upperA) == simpleLower(upperB)
}

/// The unit's one-to-one lowercase, or the unit itself when it has none.
func simpleLower(_ unit: UInt16) -> UInt16 {
    if unit < 0x80 { return unit >= 0x41 && unit <= 0x5A ? unit + 0x20 : unit }
    if unit == 0x130 { return 0x69 }
    guard let scalar = Unicode.Scalar(unit) else { return unit }
    return single(scalar.properties.lowercaseMapping) ?? unit
}

/// The unit's one-to-one uppercase, or the unit itself when it has none.
func simpleUpper(_ unit: UInt16) -> UInt16 {
    if unit < 0x80 { return unit >= 0x61 && unit <= 0x7A ? unit - 0x20 : unit }
    guard let scalar = Unicode.Scalar(unit) else { return unit }
    if let upper = single(scalar.properties.uppercaseMapping) { return upper }
    // A letter whose full uppercase is two letters still has a one-letter title case when it
    // has a one-to-one uppercase at all.
    if let title = single(scalar.properties.titlecaseMapping), title != unit { return title }
    return unit
}

/// The scalar value of a code point's one-to-one lowercase, or the point itself.
func simpleLower(point: UInt32) -> UInt32 {
    if point == 0x130 { return 0x69 }
    guard let scalar = Unicode.Scalar(point) else { return point }
    let mapped = scalar.properties.lowercaseMapping.unicodeScalars
    return mapped.count == 1 ? mapped.first!.value : point
}

private func single(_ mapping: String) -> UInt16? {
    let mapped = Array(mapping.utf16)
    return mapped.count == 1 ? mapped[0] : nil
}

// MARK: - Character classes

/// A unit's general category; nil for half of a surrogate pair.
func generalCategory(_ unit: UInt16) -> Unicode.GeneralCategory? {
    Unicode.Scalar(unit)?.properties.generalCategory
}

/// A code point's general category; surrogates and values past the last plane read as such.
func generalCategory(point: UInt32) -> Unicode.GeneralCategory {
    if point >= 0xD800 && point <= 0xDFFF { return .surrogate }
    return Unicode.Scalar(point)?.properties.generalCategory ?? .unassigned
}

/// White space: the Unicode separators, tab to carriage return, and the four information
/// separators.
func isWhitespaceUnit(_ unit: UInt16) -> Bool {
    switch unit {
    case 0x09...0x0D, 0x1C...0x1F: return true
    default:
        switch generalCategory(unit) {
        case .spaceSeparator, .lineSeparator, .paragraphSeparator: return true
        default: return false
        }
    }
}

func isLetterCategory(_ category: Unicode.GeneralCategory?) -> Bool {
    switch category {
    case .uppercaseLetter, .lowercaseLetter, .titlecaseLetter, .modifierLetter, .otherLetter: return true
    default: return false
    }
}

/// A letter of any script, read one unit at a time.
func isLetterUnit(_ unit: UInt16) -> Bool { isLetterCategory(generalCategory(unit)) }

// MARK: - Numbers

extension Comparable {
    /// The value held within `low` and `high`.
    func clamped(_ low: Self, _ high: Self) -> Self {
        precondition(low <= high, "Cannot clamp to an empty range")
        return self < low ? low : (self > high ? high : self)
    }
}

/// The nearest whole number, halves rounded up toward positive infinity.
func roundToLong(_ value: Double) -> Int {
    precondition(!value.isNaN, "Cannot round NaN value.")
    if value >= 9.223372036854775807e18 { return Int.max }
    if value <= -9.223372036854775808e18 { return Int.min }
    let floor = value.rounded(.down)
    return Int(value - floor >= 0.5 ? floor + 1 : floor)
}

/// The nearest whole number within 32 bits, halves rounded up toward positive infinity.
func roundToInt(_ value: Double) -> Int {
    precondition(!value.isNaN, "Cannot round NaN value.")
    if value >= 2147483647.0 { return Int(Int32.max) }
    if value <= -2147483648.0 { return Int(Int32.min) }
    return roundToLong(value)
}

/// -1, 0 or 1 by the value's sign, and NaN for NaN.
func signum(_ value: Double) -> Double {
    if value.isNaN { return value }
    if value > 0 { return 1.0 }
    if value < 0 { return -1.0 }
    return value
}

/// A whole number written in decimal digits of any script in the basic plane, with an optional
/// sign; nil when it is anything else or does not fit.
func wholeNumber(_ text: String) -> Int? {
    let scalars = Array(text.unicodeScalars)
    if scalars.isEmpty { return nil }
    var index = 0
    var negative = false
    if scalars[0] == "-" || scalars[0] == "+" {
        if scalars.count == 1 { return nil }
        negative = scalars[0] == "-"
        index = 1
    }
    var value = 0
    while index < scalars.count {
        let properties = scalars[index].properties
        guard scalars[index].value <= 0xFFFF, properties.generalCategory == .decimalNumber,
              let digit = properties.numericValue else { return nil }
        let (shifted, overflowA) = value.multipliedReportingOverflow(by: 10)
        let (next, overflowB) = negative
            ? shifted.subtractingReportingOverflow(Int(digit))
            : shifted.addingReportingOverflow(Int(digit))
        if overflowA || overflowB { return nil }
        value = next
        index += 1
    }
    return value
}

/// A steady clock in nanoseconds, for measuring time spent within a frame.
func monotonicNanos() -> Int {
    Int(clamping: DispatchTime.now().uptimeNanoseconds)
}

extension Array {
    /// Sorted by `inOrder`, elements that compare equal kept in the order they had.
    func stableSorted(by inOrder: (Element, Element) -> Bool) -> [Element] {
        enumerated().sorted { a, b in
            if inOrder(a.element, b.element) { return true }
            if inOrder(b.element, a.element) { return false }
            return a.offset < b.offset
        }.map(\.element)
    }
}

// MARK: - Regular expressions

/// A compiled regular expression whose matches are given in UTF-16 positions.
final class TextPattern: @unchecked Sendable {
    enum Case {
        /// Letters must match exactly.
        case exact
        /// ASCII letters match either case; no other letter does.
        case ascii
        /// Letters of every script match either case.
        case unicode
    }

    private let regex: NSRegularExpression

    /// `whole` makes a match cover the whole text or nothing. `unixLines` makes only "\n" end a
    /// line. The pattern spells out its own classes: `.` is written as the units it stands for.
    init(_ pattern: String, case caseRule: Case = .exact, unixLines: Bool = false, whole: Bool = false) {
        var source = caseRule == .ascii ? TextPattern.asciiCaseless(pattern) : pattern
        if whole { source = #"\A(?:"# + source + #")\z"# }
        var options: NSRegularExpression.Options = []
        if caseRule == .unicode { options.insert(.caseInsensitive) }
        if unixLines { options.insert(.useUnixLineSeparators) }
        do {
            regex = try NSRegularExpression(pattern: source, options: options)
        } catch {
            preconditionFailure("Bad pattern \(source): \(error)")
        }
    }

    /// The first match at or after `from`.
    func find(_ text: String, from: Int = 0) -> TextMatch? {
        let units = text.units
        guard from <= units.count else { return nil }
        let options: NSRegularExpression.MatchingOptions = from > 0 ? [.withTransparentBounds, .withoutAnchoringBounds] : []
        let range = NSRange(location: from, length: units.count - from)
        guard let result = regex.firstMatch(in: text, options: options, range: range) else { return nil }
        return TextMatch(units: units, result: result)
    }

    /// Every match, left to right, never overlapping.
    func findAll(_ text: String) -> [TextMatch] {
        let units = text.units
        return regex.matches(in: text, options: [], range: NSRange(location: 0, length: units.count))
            .map { TextMatch(units: units, result: $0) }
    }

    func containsMatch(in text: String) -> Bool { find(text) != nil }

    /// For a pattern made with `whole`: whether it matches the whole text.
    func matches(_ text: String) -> Bool { find(text) != nil }

    /// The match covering the whole text, for a pattern made with `whole`.
    func matchEntire(_ text: String) -> TextMatch? { find(text) }

    /// Every match replaced by what `transform` gives for it.
    func replace(_ text: String, _ transform: (TextMatch) -> String) -> String {
        let units = text.units
        var out: [UInt16] = []
        var last = 0
        for match in findAll(text) {
            out += units[last..<match.start]
            out += transform(match).units
            last = match.end
        }
        out += units[last...]
        return String(units: out)
    }

    /// Every match replaced by `replacement`, taken as plain text.
    func replace(_ text: String, _ replacement: String) -> String {
        replace(text) { _ in replacement }
    }

    // The pattern with every ASCII letter written as a set of both its cases, so that ignoring
    // case reaches ASCII letters only. Escapes are copied as they are: \p{..}, \uXXXX and the
    // character after a backslash.
    static func asciiCaseless(_ pattern: String) -> String {
        let chars = Array(pattern.unicodeScalars)
        var out = String.UnicodeScalarView()
        var i = 0
        var inSet = false
        func isLetter(_ c: Unicode.Scalar) -> Bool { (c >= "a" && c <= "z") || (c >= "A" && c <= "Z") }
        func other(_ c: Unicode.Scalar) -> Unicode.Scalar {
            c >= "a" && c <= "z" ? Unicode.Scalar(c.value - 0x20)! : Unicode.Scalar(c.value + 0x20)!
        }
        while i < chars.count {
            let c = chars[i]
            if c == "\\" {
                out.append(c)
                i += 1
                guard i < chars.count else { break }
                let next = chars[i]
                out.append(next)
                i += 1
                if (next == "p" || next == "P") && i < chars.count && chars[i] == "{" {
                    while i < chars.count {
                        let x = chars[i]
                        out.append(x)
                        i += 1
                        if x == "}" { break }
                    }
                } else if next == "u" {
                    var taken = 0
                    while taken < 4 && i < chars.count {
                        out.append(chars[i])
                        i += 1
                        taken += 1
                    }
                }
                continue
            }
            if inSet {
                if c == "]" {
                    inSet = false
                    out.append(c)
                } else if isLetter(c) {
                    if i + 2 < chars.count && chars[i + 1] == "-" && isLetter(chars[i + 2]) {
                        let end = chars[i + 2]
                        out.append(c)
                        out.append("-")
                        out.append(end)
                        out.append(other(c))
                        out.append("-")
                        out.append(other(end))
                        i += 3
                        continue
                    }
                    out.append(c)
                    out.append(other(c))
                } else {
                    out.append(c)
                }
                i += 1
                continue
            }
            if c == "[" {
                inSet = true
                out.append(c)
                i += 1
                if i < chars.count && chars[i] == "^" {
                    out.append(chars[i])
                    i += 1
                }
                continue
            }
            if isLetter(c) {
                out.append("[")
                out.append(c)
                out.append(other(c))
                out.append("]")
            } else {
                out.append(c)
            }
            i += 1
        }
        return String(out)
    }
}

/// One match: where it is in UTF-16 units, and its groups.
struct TextMatch {
    private let units: [UInt16]
    private let ranges: [NSRange]

    fileprivate init(units: [UInt16], result: NSTextCheckingResult) {
        self.units = units
        ranges = (0..<result.numberOfRanges).map { result.range(at: $0) }
    }

    /// Where the match starts.
    var start: Int { ranges[0].location }

    /// Where the match ends, not included.
    var end: Int { ranges[0].location + ranges[0].length }

    /// The matched text.
    var value: String { String(units: units[start..<end]) }

    /// A group's text, or nil when the group took no part.
    func group(_ index: Int) -> String? {
        guard index < ranges.count, ranges[index].location != NSNotFound else { return nil }
        let range = ranges[index]
        return String(units: units[range.location..<(range.location + range.length)])
    }

    /// A group's text, empty when the group took no part.
    func groupValue(_ index: Int) -> String { group(index) ?? "" }
}

// MARK: - Direction

/// A code point's strong direction, by its bidirectional class: right to left (classes R and AL:
/// Hebrew, Arabic, Syriac, Thaana, N'Ko and the like), left to right (class L), or neither
/// (digits, punctuation, spaces, marks, and anything unassigned).
enum StrongDirection: Sendable {
    case rightToLeft
    case leftToRight
    case neither
}

func strongDirection(_ point: UInt32) -> StrongDirection {
    var low = 0
    var high = bidiTable.count - 1
    while low <= high {
        let mid = (low + high) >> 1
        let run = bidiTable[mid]
        if point < run.start {
            high = mid - 1
        } else if point > run.end {
            low = mid + 1
        } else {
            return run.rtl ? .rightToLeft : .leftToRight
        }
    }
    return .neither
}

private let bidiTable: [(start: UInt32, end: UInt32, rtl: Bool)] = bidiRuns.split(whereSeparator: { $0 == " " || $0 == "\n" }).map { token in
    let rtl = token.last == "R"
    let bounds = token.dropLast().split(separator: "-").map { UInt32($0, radix: 16)! }
    return (bounds[0], bounds.count > 1 ? bounds[1] : bounds[0], rtl)
}

// Runs of code points with a strong direction, in order: first-last (or one point) in hex, then
// R for right to left or L for left to right. Every point not in a run has neither.
// Unicode 16.0.0
private let bidiRuns = """
41-5AL 61-7AL AAL B5L BAL C0-D6L D8-F6L F8-2B8L 2BB-2C1L 2D0-2D1L 2E0-2E4L 2EEL 370-373L
376-377L 37A-37DL 37FL 386L 388-38AL 38CL 38E-3A1L 3A3-3F5L 3F7-482L 48A-52FL 531-556L 559-589L
5BER 5C0R 5C3R 5C6R 5D0-5EAR 5EF-5F4R 608R 60BR 60DR 61B-64AR 66D-66FR 671-6D5R 6E5-6E6R
6EE-6EFR 6FA-70DR 70F-710R 712-72FR 74D-7A5R 7B1R 7C0-7EAR 7F4-7F5R 7FAR 7FE-815R 81AR 824R
828R 830-83ER 840-858R 85ER 860-86AR 870-88ER 8A0-8C9R 903-939L 93BL 93D-940L 949-94CL 94E-950L
958-961L 964-980L 982-983L 985-98CL 98F-990L 993-9A8L 9AA-9B0L 9B2L 9B6-9B9L 9BD-9C0L 9C7-9C8L
9CB-9CCL 9CEL 9D7L 9DC-9DDL 9DF-9E1L 9E6-9F1L 9F4-9FAL 9FC-9FDL A03L A05-A0AL A0F-A10L A13-A28L
A2A-A30L A32-A33L A35-A36L A38-A39L A3E-A40L A59-A5CL A5EL A66-A6FL A72-A74L A76L A83L A85-A8DL
A8F-A91L A93-AA8L AAA-AB0L AB2-AB3L AB5-AB9L ABD-AC0L AC9L ACB-ACCL AD0L AE0-AE1L AE6-AF0L AF9L
B02-B03L B05-B0CL B0F-B10L B13-B28L B2A-B30L B32-B33L B35-B39L B3D-B3EL B40L B47-B48L B4B-B4CL
B57L B5C-B5DL B5F-B61L B66-B77L B83L B85-B8AL B8E-B90L B92-B95L B99-B9AL B9CL B9E-B9FL BA3-BA4L
BA8-BAAL BAE-BB9L BBE-BBFL BC1-BC2L BC6-BC8L BCA-BCCL BD0L BD7L BE6-BF2L C01-C03L C05-C0CL
C0E-C10L C12-C28L C2A-C39L C3DL C41-C44L C58-C5AL C5DL C60-C61L C66-C6FL C77L C7F-C80L C82-C8CL
C8E-C90L C92-CA8L CAA-CB3L CB5-CB9L CBD-CC4L CC6-CC8L CCA-CCBL CD5-CD6L CDD-CDEL CE0-CE1L
CE6-CEFL CF1-CF3L D02-D0CL D0E-D10L D12-D3AL D3D-D40L D46-D48L D4A-D4CL D4E-D4FL D54-D61L
D66-D7FL D82-D83L D85-D96L D9A-DB1L DB3-DBBL DBDL DC0-DC6L DCF-DD1L DD8-DDFL DE6-DEFL DF2-DF4L
E01-E30L E32-E33L E40-E46L E4F-E5BL E81-E82L E84L E86-E8AL E8C-EA3L EA5L EA7-EB0L EB2-EB3L EBDL
EC0-EC4L EC6L ED0-ED9L EDC-EDFL F00-F17L F1A-F34L F36L F38L F3E-F47L F49-F6CL F7FL F85L
F88-F8CL FBE-FC5L FC7-FCCL FCE-FDAL 1000-102CL 1031L 1038L 103B-103CL 103F-1057L 105A-105DL
1061-1070L 1075-1081L 1083-1084L 1087-108CL 108E-109CL 109E-10C5L 10C7L 10CDL 10D0-1248L
124A-124DL 1250-1256L 1258L 125A-125DL 1260-1288L 128A-128DL 1290-12B0L 12B2-12B5L 12B8-12BEL
12C0L 12C2-12C5L 12C8-12D6L 12D8-1310L 1312-1315L 1318-135AL 1360-137CL 1380-138FL 13A0-13F5L
13F8-13FDL 1401-167FL 1681-169AL 16A0-16F8L 1700-1711L 1715L 171F-1731L 1734-1736L 1740-1751L
1760-176CL 176E-1770L 1780-17B3L 17B6L 17BE-17C5L 17C7-17C8L 17D4-17DAL 17DCL 17E0-17E9L
1810-1819L 1820-1878L 1880-1884L 1887-18A8L 18AAL 18B0-18F5L 1900-191EL 1923-1926L 1929-192BL
1930-1931L 1933-1938L 1946-196DL 1970-1974L 1980-19ABL 19B0-19C9L 19D0-19DAL 1A00-1A16L
1A19-1A1AL 1A1E-1A55L 1A57L 1A61L 1A63-1A64L 1A6D-1A72L 1A80-1A89L 1A90-1A99L 1AA0-1AADL
1B04-1B33L 1B35L 1B3BL 1B3D-1B41L 1B43-1B4CL 1B4E-1B6AL 1B74-1B7FL 1B82-1BA1L 1BA6-1BA7L 1BAAL
1BAE-1BE5L 1BE7L 1BEA-1BECL 1BEEL 1BF2-1BF3L 1BFC-1C2BL 1C34-1C35L 1C3B-1C49L 1C4D-1C8AL
1C90-1CBAL 1CBD-1CC7L 1CD3L 1CE1L 1CE9-1CECL 1CEE-1CF3L 1CF5-1CF7L 1CFAL 1D00-1DBFL 1E00-1F15L
1F18-1F1DL 1F20-1F45L 1F48-1F4DL 1F50-1F57L 1F59L 1F5BL 1F5DL 1F5F-1F7DL 1F80-1FB4L 1FB6-1FBCL
1FBEL 1FC2-1FC4L 1FC6-1FCCL 1FD0-1FD3L 1FD6-1FDBL 1FE0-1FECL 1FF2-1FF4L 1FF6-1FFCL 200EL 200FR
2071L 207FL 2090-209CL 2102L 2107L 210A-2113L 2115L 2119-211DL 2124L 2126L 2128L 212A-212DL
212F-2139L 213C-213FL 2145-2149L 214E-214FL 2160-2188L 2336-237AL 2395L 249C-24E9L 26ACL
2800-28FFL 2C00-2CE4L 2CEB-2CEEL 2CF2-2CF3L 2D00-2D25L 2D27L 2D2DL 2D30-2D67L 2D6F-2D70L
2D80-2D96L 2DA0-2DA6L 2DA8-2DAEL 2DB0-2DB6L 2DB8-2DBEL 2DC0-2DC6L 2DC8-2DCEL 2DD0-2DD6L
2DD8-2DDEL 3005-3007L 3021-3029L 302E-302FL 3031-3035L 3038-303CL 3041-3096L 309D-309FL
30A1-30FAL 30FC-30FFL 3105-312FL 3131-318EL 3190-31BFL 31F0-321CL 3220-324FL 3260-327BL
327F-32B0L 32C0-32CBL 32D0-3376L 337B-33DDL 33E0-33FEL 3400-4DBFL 4E00-A48CL A4D0-A60CL
A610-A62BL A640-A66EL A680-A69DL A6A0-A6EFL A6F2-A6F7L A722-A787L A789-A7CDL A7D0-A7D1L A7D3L
A7D5-A7DCL A7F2-A801L A803-A805L A807-A80AL A80C-A824L A827L A830-A837L A840-A873L A880-A8C3L
A8CE-A8D9L A8F2-A8FEL A900-A925L A92E-A946L A952-A953L A95F-A97CL A983-A9B2L A9B4-A9B5L
A9BA-A9BBL A9BE-A9CDL A9CF-A9D9L A9DE-A9E4L A9E6-A9FEL AA00-AA28L AA2F-AA30L AA33-AA34L
AA40-AA42L AA44-AA4BL AA4DL AA50-AA59L AA5C-AA7BL AA7D-AAAFL AAB1L AAB5-AAB6L AAB9-AABDL AAC0L
AAC2L AADB-AAEBL AAEE-AAF5L AB01-AB06L AB09-AB0EL AB11-AB16L AB20-AB26L AB28-AB2EL AB30-AB69L
AB70-ABE4L ABE6-ABE7L ABE9-ABECL ABF0-ABF9L AC00-D7A3L D7B0-D7C6L D7CB-D7FBL E000-FA6DL
FA70-FAD9L FB00-FB06L FB13-FB17L FB1DR FB1F-FB28R FB2A-FB36R FB38-FB3CR FB3ER FB40-FB41R
FB43-FB44R FB46-FBC2R FBD3-FD3DR FD50-FD8FR FD92-FDC7R FDF0-FDFCR FE70-FE74R FE76-FEFCR
FF21-FF3AL FF41-FF5AL FF66-FFBEL FFC2-FFC7L FFCA-FFCFL FFD2-FFD7L FFDA-FFDCL 10000-1000BL
1000D-10026L 10028-1003AL 1003C-1003DL 1003F-1004DL 10050-1005DL 10080-100FAL 10100L 10102L
10107-10133L 10137-1013FL 1018D-1018EL 101D0-101FCL 10280-1029CL 102A0-102D0L 10300-10323L
1032D-1034AL 10350-10375L 10380-1039DL 1039F-103C3L 103C8-103D5L 10400-1049DL 104A0-104A9L
104B0-104D3L 104D8-104FBL 10500-10527L 10530-10563L 1056F-1057AL 1057C-1058AL 1058C-10592L
10594-10595L 10597-105A1L 105A3-105B1L 105B3-105B9L 105BB-105BCL 105C0-105F3L 10600-10736L
10740-10755L 10760-10767L 10780-10785L 10787-107B0L 107B2-107BAL 10800-10805R 10808R
1080A-10835R 10837-10838R 1083CR 1083F-10855R 10857-1089ER 108A7-108AFR 108E0-108F2R
108F4-108F5R 108FB-1091BR 10920-10939R 1093FR 10980-109B7R 109BC-109CFR 109D2-10A00R
10A10-10A13R 10A15-10A17R 10A19-10A35R 10A40-10A48R 10A50-10A58R 10A60-10A9FR 10AC0-10AE4R
10AEB-10AF6R 10B00-10B35R 10B40-10B55R 10B58-10B72R 10B78-10B91R 10B99-10B9CR 10BA9-10BAFR
10C00-10C48R 10C80-10CB2R 10CC0-10CF2R 10CFA-10D23R 10D4A-10D65R 10D6F-10D85R 10D8E-10D8FR
10E80-10EA9R 10EADR 10EB0-10EB1R 10EC2-10EC4R 10F00-10F27R 10F30-10F45R 10F51-10F59R
10F70-10F81R 10F86-10F89R 10FB0-10FCBR 10FE0-10FF6R 11000L 11002-11037L 11047-1104DL
11066-1106FL 11071-11072L 11075L 11082-110B2L 110B7-110B8L 110BB-110C1L 110CDL 110D0-110E8L
110F0-110F9L 11103-11126L 1112CL 11136-11147L 11150-11172L 11174-11176L 11182-111B5L
111BF-111C8L 111CD-111CEL 111D0-111DFL 111E1-111F4L 11200-11211L 11213-1122EL 11232-11233L
11235L 11238-1123DL 1123F-11240L 11280-11286L 11288L 1128A-1128DL 1128F-1129DL 1129F-112A9L
112B0-112DEL 112E0-112E2L 112F0-112F9L 11302-11303L 11305-1130CL 1130F-11310L 11313-11328L
1132A-11330L 11332-11333L 11335-11339L 1133D-1133FL 11341-11344L 11347-11348L 1134B-1134DL
11350L 11357L 1135D-11363L 11380-11389L 1138BL 1138EL 11390-113B5L 113B7-113BAL 113C2L 113C5L
113C7-113CAL 113CC-113CDL 113CFL 113D1L 113D3-113D5L 113D7-113D8L 11400-11437L 11440-11441L
11445L 11447-1145BL 1145DL 1145F-11461L 11480-114B2L 114B9L 114BB-114BEL 114C1L 114C4-114C7L
114D0-114D9L 11580-115B1L 115B8-115BBL 115BEL 115C1-115DBL 11600-11632L 1163B-1163CL 1163EL
11641-11644L 11650-11659L 11680-116AAL 116ACL 116AE-116AFL 116B6L 116B8-116B9L 116C0-116C9L
116D0-116E3L 11700-1171AL 1171EL 11720-11721L 11726L 11730-11746L 11800-1182EL 11838L 1183BL
118A0-118F2L 118FF-11906L 11909L 1190C-11913L 11915-11916L 11918-11935L 11937-11938L 1193DL
1193F-11942L 11944-11946L 11950-11959L 119A0-119A7L 119AA-119D3L 119DC-119DFL 119E1-119E4L
11A00L 11A07-11A08L 11A0B-11A32L 11A39-11A3AL 11A3F-11A46L 11A50L 11A57-11A58L 11A5C-11A89L
11A97L 11A9A-11AA2L 11AB0-11AF8L 11B00-11B09L 11BC0-11BE1L 11BF0-11BF9L 11C00-11C08L
11C0A-11C2FL 11C3E-11C45L 11C50-11C6CL 11C70-11C8FL 11CA9L 11CB1L 11CB4L 11D00-11D06L
11D08-11D09L 11D0B-11D30L 11D46L 11D50-11D59L 11D60-11D65L 11D67-11D68L 11D6A-11D8EL
11D93-11D94L 11D96L 11D98L 11DA0-11DA9L 11EE0-11EF2L 11EF5-11EF8L 11F02-11F10L 11F12-11F35L
11F3E-11F3FL 11F41L 11F43-11F59L 11FB0L 11FC0-11FD4L 11FFF-12399L 12400-1246EL 12470-12474L
12480-12543L 12F90-12FF2L 13000-1343FL 13441-13446L 13460-143FAL 14400-14646L 16100-1611DL
1612A-1612CL 16130-16139L 16800-16A38L 16A40-16A5EL 16A60-16A69L 16A6E-16ABEL 16AC0-16AC9L
16AD0-16AEDL 16AF5L 16B00-16B2FL 16B37-16B45L 16B50-16B59L 16B5B-16B61L 16B63-16B77L
16B7D-16B8FL 16D40-16D79L 16E40-16E9AL 16F00-16F4AL 16F50-16F87L 16F93-16F9FL 16FE0-16FE1L
16FE3L 16FF0-16FF1L 17000-187F7L 18800-18CD5L 18CFF-18D08L 1AFF0-1AFF3L 1AFF5-1AFFBL
1AFFD-1AFFEL 1B000-1B122L 1B132L 1B150-1B152L 1B155L 1B164-1B167L 1B170-1B2FBL 1BC00-1BC6AL
1BC70-1BC7CL 1BC80-1BC88L 1BC90-1BC99L 1BC9CL 1BC9FL 1CCD6-1CCEFL 1CF50-1CFC3L 1D000-1D0F5L
1D100-1D126L 1D129-1D166L 1D16A-1D172L 1D183-1D184L 1D18C-1D1A9L 1D1AE-1D1E8L 1D2C0-1D2D3L
1D2E0-1D2F3L 1D360-1D378L 1D400-1D454L 1D456-1D49CL 1D49E-1D49FL 1D4A2L 1D4A5-1D4A6L
1D4A9-1D4ACL 1D4AE-1D4B9L 1D4BBL 1D4BD-1D4C3L 1D4C5-1D505L 1D507-1D50AL 1D50D-1D514L
1D516-1D51CL 1D51E-1D539L 1D53B-1D53EL 1D540-1D544L 1D546L 1D54A-1D550L 1D552-1D6A5L
1D6A8-1D6C0L 1D6C2-1D6DAL 1D6DC-1D6FAL 1D6FC-1D714L 1D716-1D734L 1D736-1D74EL 1D750-1D76EL
1D770-1D788L 1D78A-1D7A8L 1D7AA-1D7C2L 1D7C4-1D7CBL 1D800-1D9FFL 1DA37-1DA3AL 1DA6D-1DA74L
1DA76-1DA83L 1DA85-1DA8BL 1DF00-1DF1EL 1DF25-1DF2AL 1E030-1E06DL 1E100-1E12CL 1E137-1E13DL
1E140-1E149L 1E14E-1E14FL 1E290-1E2ADL 1E2C0-1E2EBL 1E2F0-1E2F9L 1E4D0-1E4EBL 1E4F0-1E4F9L
1E5D0-1E5EDL 1E5F0-1E5FAL 1E5FFL 1E7E0-1E7E6L 1E7E8-1E7EBL 1E7ED-1E7EEL 1E7F0-1E7FEL
1E800-1E8C4R 1E8C7-1E8CFR 1E900-1E943R 1E94BR 1E950-1E959R 1E95E-1E95FR 1EC71-1ECB4R
1ED01-1ED3DR 1EE00-1EE03R 1EE05-1EE1FR 1EE21-1EE22R 1EE24R 1EE27R 1EE29-1EE32R 1EE34-1EE37R
1EE39R 1EE3BR 1EE42R 1EE47R 1EE49R 1EE4BR 1EE4D-1EE4FR 1EE51-1EE52R 1EE54R 1EE57R 1EE59R 1EE5BR
1EE5DR 1EE5FR 1EE61-1EE62R 1EE64R 1EE67-1EE6AR 1EE6C-1EE72R 1EE74-1EE77R 1EE79-1EE7CR 1EE7ER
1EE80-1EE89R 1EE8B-1EE9BR 1EEA1-1EEA3R 1EEA5-1EEA9R 1EEAB-1EEBBR 1F110-1F12EL 1F130-1F169L
1F170-1F1ACL 1F1E6-1F202L 1F210-1F23BL 1F240-1F248L 1F250-1F251L 20000-2A6DFL 2A700-2B739L
2B740-2B81DL 2B820-2CEA1L 2CEB0-2EBE0L 2EBF0-2EE5DL 2F800-2FA1DL 30000-3134AL 31350-323AFL
F0000-FFFFDL 100000-10FFFDL
"""
