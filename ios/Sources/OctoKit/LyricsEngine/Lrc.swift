import Foundation

// A line's time stamp, like [01:23.45], [01:23:45] or [01:23].
private let lineStamp = TextPattern(#"^\[([0-9]{1,3}):([0-9]{1,2})(?:[.:]([0-9]{1,3}))?\]"#)

// A word's time stamp inside a line, like <01:23.45>.
private let wordStamp = TextPattern(#"<([0-9]{1,3}):([0-9]{1,2})(?:[.:]([0-9]{1,3}))?>"#)

// What some editors put before the text of a UTF-8 file.
private let ByteOrderMark = "\u{FEFF}"

// A tag line, like [ar:Someone] or [offset:+250]. The value is anything up to the closing
// bracket that does not end a line.
private let tagLine = TextPattern(#"^\[([A-Za-z#]+):([^\n\r\u0085  ]*)\]$"#, whole: true)

/// Lyrics from text, which may be LRC (timed) or plain. Tags like [ar:] and [ti:] are skipped,
/// [offset:] moves every time (above zero, sooner), an empty timed line is a gap where nobody
/// sings, and <mm:ss.xx> stamps time each word. A line with several stamps is sung at each of
/// them. Nil when there is nothing to show.
public func parseLyricsText(_ text: String, source: LyricsSource) -> Lyrics? {
    let rows = text.removingPrefix(ByteOrderMark).splitLines()
    var offset = 0
    var timed: [LyricLine] = []
    var plain: [String] = []
    // The lines the last timed row made, which a [bg:] row adds backing to.
    var lastMade: [Int] = []

    for row in rows {
        var rest = row.trimWhitespace()
        var stamps: [Int] = []
        while true {
            guard let stamp = lineStamp.find(rest) else { break }
            stamps.append(millisOf(stamp))
            rest = rest.utf16Slice(from: stamp.end)
        }
        if !stamps.isEmpty {
            lastMade = stamps.map { start in
                let (line, words) = timedText(start, rest)
                timed.append(LyricLine(startMs: start, endMs: words.last?.endMs, text: line, words: words))
                return timed.count - 1
            }
            continue
        }
        if let tag = tagLine.matchEntire(rest) {
            let value = tag.groupValue(2).trimWhitespace()
            switch tag.groupValue(1).lowercaseRoot() {
            case "offset":
                offset = wholeNumber(value.removingPrefix("+")) ?? offset
            case "bg":
                for index in lastMade {
                    let (line, words) = timedText(timed[index].startMs, value)
                    timed[index].backingText = line
                    timed[index].backing = words
                }
            default:
                break
            }
            continue
        }
        plain.append(rest)
    }

    if !timed.isEmpty {
        if !timed.contains(where: { !$0.isGap }) { return nil }
        let lines = timed
            .map { $0.shifted(-offset) }
            .stableSorted { $0.startMs < $1.startMs }
            .drop { $0.isGap }
        return Lyrics(synced: true, lines: Array(lines), source: source)
    }

    // Plain text: blank rows split verses, so runs of them fold into one.
    var lines: [String] = []
    for row in plain where !row.isEmpty || lines.last.map({ !$0.isEmpty }) == true {
        lines.append(row)
    }
    while let last = lines.last, last.isEmpty { lines.removeLast() }
    if lines.isEmpty { return nil }
    return Lyrics(synced: false, lines: lines.map { LyricLine(text: $0) }, source: source)
}

// A line's text, and its timed words when it has <mm:ss.xx> stamps. Text before the first stamp
// starts with the line. A stamp with nothing after it ends the word before it.
private func timedText(_ start: Int, _ body: String) -> (String, [LyricWord]) {
    let stamps = wordStamp.findAll(body)
    if stamps.isEmpty { return (body.trimWhitespace(), []) }

    let bodyUnits = body.units
    var pieces: [(at: Int, piece: String)] = []
    let lead = String(units: bodyUnits[0..<stamps[0].start])
    if !lead.isBlankText { pieces.append((start, lead)) }
    for (index, stamp) in stamps.enumerated() {
        let end = index + 1 < stamps.count ? stamps[index + 1].start : bodyUnits.count
        pieces.append((millisOf(stamp), String(units: bodyUnits[stamp.end..<end])))
    }

    var text: [UInt16] = []
    var words: [LyricWord] = []
    for (index, (at, piece)) in pieces.enumerated() {
        if piece.isEmpty { continue }
        let from = text.count
        text += piece.units
        if !piece.isBlankText {
            let next = index + 1 < pieces.count ? pieces[index + 1].at : nil
            words.append(LyricWord(startMs: at, endMs: next, text: piece, from: from, to: text.count))
        }
    }

    // Spaces around the line go, and the words move with the text.
    let whole = String(units: text)
    let cut = text.count - whole.trimStartWhitespace().utf16.count
    let trimmed = whole.trimWhitespace()
    let length = trimmed.utf16.count
    return (trimmed, words.compactMap { word in
        let from = (word.from - cut).clamped(0, length)
        let to = (word.to - cut).clamped(0, length)
        guard to > from else { return nil }
        var moved = word
        moved.from = from
        moved.to = to
        return moved
    })
}

// Milliseconds from a stamp's minutes, seconds and fraction. The fraction is read as a decimal,
// so .5, .50 and .500 are all half a second.
private func millisOf(_ stamp: TextMatch) -> Int {
    let minutes = stamp.groupValue(1)
    let seconds = stamp.groupValue(2)
    let fraction = stamp.groupValue(3)
    let millis: Int
    switch fraction.utf16.count {
    case 0: millis = 0
    case 1: millis = Int(fraction)! * 100
    case 2: millis = Int(fraction)! * 10
    default: millis = Int(fraction)!
    }
    return Int(minutes)! * 60_000 + Int(seconds)! * 1_000 + millis
}

extension LyricLine {
    /// The same line moved in time, never before the start of the song.
    func shifted(_ by: Int) -> LyricLine {
        if by == 0 { return self }
        func move(_ time: Int) -> Int { max(time + by, 0) }
        func moved(_ word: LyricWord) -> LyricWord {
            var word = word
            word.startMs = move(word.startMs)
            word.endMs = word.endMs.map(move)
            return word
        }
        var line = self
        line.startMs = move(startMs)
        line.endMs = endMs.map(move)
        line.words = words.map(moved)
        line.backing = backing.map(moved)
        return line
    }
}
