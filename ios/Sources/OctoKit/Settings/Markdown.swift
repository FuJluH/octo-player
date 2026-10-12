import Foundation

/// A small reader for the little markdown Octo writes itself, like its release notes: headings
/// one to three deep, paragraphs, bullet lists one level nested, bold, italic, inline code,
/// links and horizontal rules. Anything else is kept as plain text, so a song title such as
/// "$UICIDE" or "F*ck It" reads exactly as written.
public enum Markdown {
    /// A run of text and how it looks. `link` is where a tap on it goes.
    public struct Span: Equatable, Sendable {
        public var text: String
        public var bold = false
        public var italic = false
        public var code = false
        public var link: String?

        public init(_ text: String, bold: Bool = false, italic: Bool = false, code: Bool = false, link: String? = nil) {
            self.text = text
            self.bold = bold
            self.italic = italic
            self.code = code
            self.link = link
        }

        func sameLook(_ other: Span) -> Bool { bold == other.bold && italic == other.italic && code == other.code && link == other.link }
    }

    /// One bullet, and the bullets under it.
    public struct Bullet: Equatable, Sendable {
        public var text: [Span]
        public var children: [Bullet]

        public init(_ text: [Span], children: [Bullet] = []) {
            self.text = text
            self.children = children
        }
    }

    /// A piece of the page, top to bottom.
    public enum Block: Equatable, Sendable {
        /// Level 1 to 3.
        case heading(Int, [Span])
        case paragraph([Span])
        case bullets([Bullet])
        case rule
    }

    /// How far in a bullet must sit to be under the one above it.
    static let nestSpaces = 2

    /// Reads the page into blocks.
    public static func parse(_ source: String) -> [Block] {
        var blocks: [Block] = []
        var paragraph: [String] = []
        // The list being read: top-level bullets, each with its children so far.
        var bullets: [(top: String, children: [String])] = []
        // Where the last line went, so an indented line after a bullet carries it on.
        var lastBullet: (index: Int, child: Int?)?

        func endParagraph() {
            if !paragraph.isEmpty {
                blocks.append(.paragraph(parseInline(paragraph.joined(separator: " "))))
                paragraph.removeAll()
            }
        }
        func endList() {
            if !bullets.isEmpty {
                blocks.append(.bullets(bullets.map { Bullet(parseInline($0.top), children: $0.children.map { Bullet(parseInline($0)) }) }))
                bullets.removeAll()
            }
            lastBullet = nil
        }

        for raw in source.replacingOccurrences(of: "\r\n", with: "\n").split(separator: "\n", omittingEmptySubsequences: false).map(String.init) {
            let line = trimEnd(raw)
            if line.trimmingCharacters(in: .whitespaces).isEmpty {
                endParagraph()
                endList()
                continue
            }
            if isRule(line) {
                endParagraph()
                endList()
                blocks.append(.rule)
                continue
            }
            if let (level, text) = heading(line) {
                endParagraph()
                endList()
                blocks.append(.heading(min(level, 3), parseInline(text)))
                continue
            }
            if let (indent, text) = bullet(line) {
                endParagraph()
                if indent >= nestSpaces, !bullets.isEmpty {
                    // Deeper than one level still sits one level in.
                    bullets[bullets.count - 1].children.append(text)
                    lastBullet = (bullets.count - 1, bullets[bullets.count - 1].children.count - 1)
                } else {
                    bullets.append((text, []))
                    lastBullet = (bullets.count - 1, nil)
                }
                continue
            }
            if let carried = lastBullet, raw.hasPrefix(" ") {
                // An indented line after a bullet continues it.
                let more = " " + line.trimmingCharacters(in: .whitespaces)
                if let child = carried.child { bullets[carried.index].children[child] += more } else { bullets[carried.index].top += more }
                continue
            }
            endList()
            paragraph.append(line.trimmingCharacters(in: .whitespaces))
        }
        endParagraph()
        endList()
        return blocks
    }

    static func trimEnd(_ text: String) -> String {
        var out = Substring(text)
        while let last = out.last, last.isWhitespace { out = out.dropLast() }
        return String(out)
    }

    /// Three or more of the same "-", "*" or "_", spaces allowed between.
    static func isRule(_ line: String) -> Bool {
        let marks = line.filter { !$0.isWhitespace }
        guard let first = marks.first, "-*_".contains(first), marks.count >= 3 else { return false }
        return marks.allSatisfy { $0 == first } && line.allSatisfy { $0.isWhitespace || $0 == first }
    }

    /// One to six "#" then whitespace; trailing " #..." marks are removed.
    static func heading(_ line: String) -> (Int, String)? {
        let hashes = line.prefix { $0 == "#" }.count
        guard (1...6).contains(hashes) else { return nil }
        let rest = line.dropFirst(hashes)
        guard let first = rest.first, first.isWhitespace else { return nil }
        var text = rest.trimmingCharacters(in: .whitespaces)
        // A closing run of "#" after a space is not part of the words.
        if let space = text.lastIndex(where: { $0.isWhitespace }) {
            let tail = text[text.index(after: space)...]
            if !tail.isEmpty, tail.allSatisfy({ $0 == "#" }) { text = String(text[..<space]).trimmingCharacters(in: .whitespaces) }
        }
        return (hashes, text)
    }

    /// A line starting (after optional indent) with "-", "*" or "+" and whitespace; a tab counts
    /// as four spaces of indent.
    static func bullet(_ line: String) -> (Int, String)? {
        let indentText = line.prefix { $0 == " " || $0 == "\t" }
        let rest = line.dropFirst(indentText.count)
        guard let mark = rest.first, "-*+".contains(mark) else { return nil }
        let after = rest.dropFirst()
        guard let gap = after.first, gap.isWhitespace else { return nil }
        let indent = indentText.reduce(0) { $0 + ($1 == "\t" ? 4 : 1) }
        return (indent, after.trimmingCharacters(in: .whitespaces))
    }

    /// Reads one line's inline marks into runs of text.
    public static func parseInline(_ text: String) -> [Span] {
        var reader = InlineReader(Array(text))
        return merge(reader.read(Look()))
    }

    /// The words alone, with the marks gone.
    public static func plainText(_ spans: [Span]) -> String { spans.map(\.text).joined() }

    /// Joins neighboring runs that look the same, and drops empty ones.
    static func merge(_ spans: [Span]) -> [Span] {
        var out: [Span] = []
        for span in spans where !span.text.isEmpty {
            if let last = out.last, last.sameLook(span) {
                out[out.count - 1].text += span.text
            } else {
                out.append(span)
            }
        }
        return out
    }

    /// How the text being read looks so far, from the marks around it.
    struct Look {
        var bold = false
        var italic = false
        var link: String?
    }

    struct InlineReader {
        let text: [Character]
        var at = 0
        static let escapable: Set<Character> = Set("\\`*_[]()#+-.!$")

        init(_ text: [Character]) { self.text = text }

        func char(_ i: Int) -> Character? { i >= 0 && i < text.count ? text[i] : nil }

        func starts(_ mark: String, at i: Int) -> Bool {
            let chars = Array(mark)
            guard i >= 0, i + chars.count <= text.count else { return false }
            return Array(text[i..<(i + chars.count)]) == chars
        }

        func index(of mark: String, from: Int) -> Int? {
            var i = max(from, 0)
            while i < text.count {
                if starts(mark, at: i) { return i }
                i += 1
            }
            return nil
        }

        /// Reads until `until` (a closing mark) or the end.
        mutating func read(_ look: Look, until: String? = nil) -> [Span] {
            var out: [Span] = []
            var plain = ""
            func flush() {
                if !plain.isEmpty {
                    out.append(Span(plain, bold: look.bold, italic: look.italic, link: look.link))
                    plain = ""
                }
            }
            while at < text.count {
                if let until, closes(until) {
                    flush()
                    return out
                }
                let c = text[at]
                if c == "\\", let next = char(at + 1), Self.escapable.contains(next) {
                    plain.append(next)
                    at += 2
                } else if c == "`" {
                    if let end = index(of: "`", from: at + 1), end > at + 1 {
                        flush()
                        out.append(Span(String(text[(at + 1)..<end]), bold: look.bold, italic: look.italic, code: true, link: look.link))
                        at = end + 1
                    } else {
                        plain.append(c)
                        at += 1
                    }
                } else if (c == "*" || c == "_"), char(at + 1) == c, opens(2, c), hasClosing("\(c)\(c)", from: at + 2) {
                    flush()
                    at += 2
                    var inner = look
                    inner.bold = true
                    out += read(inner, until: "\(c)\(c)")
                    if starts("\(c)\(c)", at: at) { at += 2 }
                } else if (c == "*" || c == "_"), opens(1, c), hasClosing("\(c)", from: at + 1) {
                    flush()
                    at += 1
                    var inner = look
                    inner.italic = true
                    out += read(inner, until: "\(c)")
                    if starts("\(c)", at: at) { at += 1 }
                } else if c == "[", look.link == nil {
                    if let (label, url, end) = linkAt(at) {
                        flush()
                        var inner = look
                        inner.link = url
                        var reader = InlineReader(Array(label))
                        out += reader.read(inner)
                        at = end
                    } else {
                        plain.append(c)
                        at += 1
                    }
                } else {
                    plain.append(c)
                    at += 1
                }
            }
            flush()
            return out
        }

        /// A mark opens here when text follows it straight away, and it does not sit inside a word.
        func opens(_ width: Int, _ mark: Character) -> Bool {
            guard let next = char(at + width), !next.isWhitespace, next != mark else { return false }
            guard let before = char(at - 1) else { return true }
            return !(before.isLetter || before.isNumber)
        }

        /// Whether `mark` closes somewhere after `from`, right after text and not inside a word.
        func hasClosing(_ mark: String, from: Int) -> Bool {
            var i = index(of: mark, from: from)
            while let found = i {
                if closes(at: found, mark) { return true }
                i = index(of: mark, from: found + 1)
            }
            return false
        }

        func closes(_ mark: String) -> Bool { starts(mark, at: at) && closes(at: at, mark) }

        func closes(at i: Int, _ mark: String) -> Bool {
            guard let before = char(i - 1), !before.isWhitespace else { return false }
            // A single mark is not half of a double one.
            if mark.count == 1, let m = mark.first, char(i + 1) == m || before == m { return false }
            guard let after = char(i + mark.count) else { return true }
            return !(after.isLetter || after.isNumber)
        }

        /// A link here: its words, where it goes, and where it ends.
        func linkAt(_ start: Int) -> (String, String, Int)? {
            guard let close = index(of: "]", from: start + 1), char(close + 1) == "(",
                  let end = index(of: ")", from: close + 2)
            else { return nil }
            let label = String(text[(start + 1)..<close])
            let url = String(text[(close + 2)..<end]).trimmingCharacters(in: .whitespaces)
            if label.trimmingCharacters(in: .whitespaces).isEmpty || url.isEmpty || url.contains(where: \.isWhitespace) { return nil }
            return (label, url, end + 1)
        }
    }
}
