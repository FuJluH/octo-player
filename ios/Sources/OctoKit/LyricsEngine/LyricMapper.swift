import Foundation

/// A wait between sung lines at least this long shows the interlude dots. The dots' own steps take
/// 1.75 s (half a second unseen, half a second to fade in, three quarters of a second to go), and
/// one slow breath on top needs about 1.5 s more, so anything much under 4 s would only flicker.
public let INTERLUDE_GAP_S = 4.0

/// An empty line in the source marks a gap on purpose, so it gets dots with less room: just
/// enough for them to appear and go.
public let MARKED_INTERLUDE_MIN_S = 2.0

/// How long a last line with no known end is held.
public let LAST_LINE_HOLD_S = 5.0

// Lines some sources put in for who wrote the song, which the view skips. Case is ignored in
// every script.
private let SourceCredit = TextPattern(
    #"^[ \t\n\u000B\f\r]*(written by|lyrics by|words by|music by|composed by|composer|lyricist|作词|作詞|作曲|编曲|編曲|词|詞|曲)[ \t\n\u000B\f\r]*[:：]"#,
    case: .unicode
)

/// Turns a song's lyrics, as any source gave them, into the flat list of lines the flowing view
/// draws. Plain lyrics give nothing: the view is for synced ones.
public enum LyricMapper {
    public static func map(_ lyrics: Lyrics, writers: [String] = []) -> [SyncLine] {
        if !lyrics.synced || lyrics.instrumental { return [] }
        let source = lyrics.lines
            .stableSorted { $0.startMs < $1.startMs }
            .filter { !(SourceCredit.containsMatch(in: $0.text) && $0.words.isEmpty) }
        var out: [SyncLine] = []
        // The last lead or background line, whose end a short wait stretches to meet the next.
        var lastSung = -1
        // Whether an interlude was just added, so no second one goes after it.
        var afterInterlude = false

        for (index, line) in source.enumerated() {
            let nextStart = index + 1 < source.count ? source[index + 1].startMs : nil
            if line.isGap {
                guard let next = source[(index + 1)...].first(where: { !$0.isGap }) else { continue }
                let start = seconds(line.startMs)
                let end = seconds(next.startMs)
                if end - start >= MARKED_INTERLUDE_MIN_S {
                    if lastSung >= 0 { out[lastSung] = stretched(out[lastSung], start) }
                    out.append(interlude(start, end, next))
                    afterInterlude = true
                }
                continue
            }

            // A line only backing voices sing, whichever way the source put it.
            let backingOnly = line.background || line.text.isBlankText
            let main: SyncLine
            if line.background {
                main = backing(line.text, line.words, line, nextStart)
            } else if line.text.isBlankText {
                main = backing(line.backingText, line.backing, line, nextStart)
            } else {
                main = lead(line, nextStart)
            }
            if !afterInterlude {
                let waitFrom = lastSung >= 0 ? out[lastSung].end : 0.0
                let wait = main.start - waitFrom
                if wait >= INTERLUDE_GAP_S {
                    out.append(interlude(waitFrom, main.start, line))
                } else if lastSung >= 0 {
                    out[lastSung] = stretched(out[lastSung], main.start)
                }
            }
            afterInterlude = false
            out.append(main)
            lastSung = out.count - 1
            if !backingOnly && !line.backingText.isBlankText {
                var back = backing(line.backingText, line.backing, line, nextStart)
                // Backing vocals take the side of the voice they back.
                back.isDuet = main.isDuet
                back.start = max(back.start, main.start)
                out.append(back)
            }
        }

        if !writers.isEmpty && !out.isEmpty {
            let last = out.map(\.end).max()!
            out.append(SyncLine(
                index: 0,
                text: "Written by \(names(writers))",
                words: [],
                start: last,
                end: Double.infinity,
                isCredit: true
            ))
        }
        return out.enumerated().map { index, line in
            var line = line
            line.index = index
            return line
        }
    }

    private static func lead(_ line: LyricLine, _ nextStartMs: Int?) -> SyncLine {
        let text = line.text.trimWhitespace()
        let end = seconds(lineEndMs(line, nextStartMs))
        let words = timedWords(text, words: line.words, lineEnd: end)
        let start = seconds(line.startMs)
        let translation = line.translation?.trimWhitespace()
        let romanization = line.romanization?.trimWhitespace()
        return SyncLine(
            index: 0,
            text: text,
            words: words ?? [SyncWord(text: text, start: start, end: end, trailingSpace: true)],
            start: start,
            end: end,
            rtl: isRtl(text),
            translation: translation.flatMap { $0.isEmpty || sameText($0, text) ? nil : $0 },
            romanization: romanization.flatMap { spelled in
                let repeated = spelled.isEmpty || sameText(spelled, text) || (line.translation.map { sameText(spelled, $0) } ?? false)
                return repeated ? nil : spelled
            },
            isDuet: line.duet,
            isLineTimed: words == nil
        )
    }

    // A backing vocal line, its brackets gone.
    private static func backing(_ rawText: String, _ rawWords: [LyricWord], _ line: LyricLine, _ nextStartMs: Int?) -> SyncLine {
        let lineEnd = seconds(lineEndMs(line, nextStartMs))
        let timed = timedWords(rawText.trimWhitespace(), words: rawWords, lineEnd: lineEnd)
        let text = withoutBrackets(rawText)
        let words = timed.map(wordsWithoutBrackets).flatMap { $0.isEmpty ? nil : $0 }
        let start = words?.first?.start ?? seconds(line.startMs)
        let end = words?.map(\.end).max() ?? lineEnd
        return SyncLine(
            index: 0,
            text: text,
            words: words ?? [SyncWord(text: text, start: start, end: end, trailingSpace: true)],
            start: start,
            end: end,
            rtl: isRtl(text),
            isBackground: true,
            isDuet: line.duet,
            isLineTimed: words == nil
        )
    }

    // An interlude, set on the side of the line that follows it.
    private static func interlude(_ start: Double, _ end: Double, _ next: LyricLine) -> SyncLine {
        let text = next.text.isBlankText ? next.backingText : next.text
        return SyncLine(
            index: 0,
            text: "",
            words: [],
            start: start,
            end: end,
            rtl: isRtl(text),
            isInterlude: true,
            isDuet: next.duet
        )
    }
}

/// A line's words, or nil when it has none or they do not cover its text (then the line is shown
/// timed by line). Syllables of one word stay together: only a piece followed by a space, or the
/// last, ends a group.
func timedWords(_ text: String, words: [LyricWord], lineEnd: Double) -> [SyncWord]? {
    if words.isEmpty { return nil }
    let letters = text.removingWhitespace()
    if !words.map(\.text).joined().removingWhitespace().utf16Equals(letters) { return nil }
    let kept = words.enumerated().filter { !$0.element.text.isBlankText }
    let units = text.units
    return kept.enumerated().map { position, entry in
        let (index, word) = entry
        let next = position + 1 < kept.count ? kept[position + 1].element : nil
        let start = seconds(word.startMs)
        let end = word.endMs.map(seconds) ?? (index + 1 < words.count ? seconds(words[index + 1].startMs) : lineEnd)
        var between: ArraySlice<UInt16> = []
        if let next {
            let from = word.to.clamped(0, units.count)
            between = units[from..<next.from.clamped(from, units.count)]
        }
        let spaced = next == nil
            || isWhitespaceUnit(word.text.utf16.last!)
            || isWhitespaceUnit(next!.text.utf16.first!)
            || between.contains(where: isWhitespaceUnit)
        return SyncWord(text: word.text.trimWhitespace(), start: start, end: max(start, end), trailingSpace: spaced)
    }
}

// When a line ends: its own end, its last word's, or the next line's start.
private func lineEndMs(_ line: LyricLine, _ nextStartMs: Int?) -> Int {
    line.endMs ?? line.words.last?.endMs ?? nextStartMs ?? (line.startMs + Int(LAST_LINE_HOLD_S * 1000))
}

// A line held on until `until`, so the focus never goes dark in a short wait. Lines that overlap
// the next are left as they are.
private func stretched(_ line: SyncLine, _ until: Double) -> SyncLine {
    guard line.end < until else { return line }
    var line = line
    line.end = until
    return line
}

/// Whether a line reads right to left, from its first letter with a direction: Arabic, Hebrew,
/// Syriac, Thaana, N'Ko and the like do.
public func isRtl(_ text: String) -> Bool {
    for scalar in text.unicodeScalars {
        switch strongDirection(scalar.value) {
        case .rightToLeft: return true
        case .leftToRight: return false
        case .neither: continue
        }
    }
    return false
}

/// The same words, ignoring spaces and case.
func sameText(_ a: String, _ b: String) -> Bool {
    a.removingWhitespace().lowercaseRoot().utf16Equals(b.removingWhitespace().lowercaseRoot())
}

private let Opening: Set<UInt16> = [0x28, 0xFF08]
private let Closing: Set<UInt16> = [0x29, 0xFF09]

/// "(ooh yeah)" as "ooh yeah".
func withoutBrackets(_ text: String) -> String {
    let trimmed = text.trimWhitespace()
    let units = trimmed.units
    if units.count >= 2 && Opening.contains(units[0]) && Closing.contains(units[units.count - 1]) {
        return String(units: units[1..<(units.count - 1)]).trimWhitespace()
    }
    return trimmed
}

// The words with an opening bracket off the first and a closing one off the last. A word left
// empty goes.
private func wordsWithoutBrackets(_ words: [SyncWord]) -> [SyncWord] {
    if words.isEmpty { return words }
    let opens = words[0].text.utf16.first.map { Opening.contains($0) } == true
    let closes = words[words.count - 1].text.utf16.last.map { Closing.contains($0) } == true
    if !opens || !closes { return words }
    let kept = words.enumerated().map { index, word in
        var units = word.text.units
        if index == 0 { units = Array(units.dropFirst()) }
        if index == words.count - 1 { units = Array(units.dropLast()) }
        var word = word
        word.text = String(units: units).trimWhitespace()
        return word
    }.filter { !$0.text.isEmpty }
    return kept.enumerated().map { index, word in
        guard index == kept.count - 1 else { return word }
        var word = word
        word.trailingSpace = true
        return word
    }
}

// "A", "A & B", "A, B & C".
private func names(_ writers: [String]) -> String {
    writers.count == 1 ? writers[0] : writers.dropLast().joined(separator: ", ") + " & " + writers[writers.count - 1]
}

private func seconds(_ ms: Int) -> Double { Double(ms) / 1000.0 }
