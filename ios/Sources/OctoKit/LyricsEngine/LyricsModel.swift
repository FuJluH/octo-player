import Foundation

/// Where a song's lyrics came from, in the words the lyrics menu uses.
public enum LyricsSource: String, Codable, Sendable, CaseIterable {
    case server = "Server"
    case songFile = "SongFile"
    case lyricsFile = "LyricsFile"
    case online = "Online"

    public var label: String {
        switch self {
        case .server: "From your server"
        case .songFile: "From the song file"
        case .lyricsFile: "From a .lrc file beside the song"
        case .online: "From LRCLIB"
        }
    }
}

/// A song's lyrics, however they were found. Synced lyrics have a start time on every line;
/// plain ones are only text, in order.
public struct Lyrics: Equatable, Sendable, Codable {
    public var synced: Bool
    public var lines: [LyricLine]
    public var source: LyricsSource
    /// Known to have no words at all.
    public var instrumental: Bool
    /// The online library's number for this copy, so a pick of it can be fetched again. Nil for
    /// other sources, and for answers saved before it was kept.
    public var onlineId: Int?
    /// The copy the server has pinned for the song ("kugou:123"), when this phone knows it, so
    /// the menu can say where they are from. Nil for the server's own automatic answer and for
    /// other sources.
    public var serverPick: String?

    public init(
        synced: Bool,
        lines: [LyricLine],
        source: LyricsSource,
        instrumental: Bool = false,
        onlineId: Int? = nil,
        serverPick: String? = nil
    ) {
        self.synced = synced
        self.lines = lines
        self.source = source
        self.instrumental = instrumental
        self.onlineId = onlineId
        self.serverPick = serverPick
    }

    public var isEmpty: Bool { !instrumental && !lines.contains { !$0.text.isBlankText } }

    enum CodingKeys: String, CodingKey { case synced, lines, source, instrumental, onlineId, serverPick }

    // A saved answer may leave out any field that has a default.
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        synced = try c.decode(Bool.self, forKey: .synced)
        lines = try c.decode([LyricLine].self, forKey: .lines)
        source = try c.decode(LyricsSource.self, forKey: .source)
        instrumental = try c.decodeIfPresent(Bool.self, forKey: .instrumental) ?? false
        onlineId = try c.decodeIfPresent(Int.self, forKey: .onlineId)
        serverPick = try c.decodeIfPresent(String.self, forKey: .serverPick)
    }
}

public struct LyricLine: Equatable, Sendable, Codable {
    public var startMs: Int
    /// When the line is known to end, or nil to run until the next one.
    public var endMs: Int?
    /// Empty for a gap where nobody sings.
    public var text: String
    /// Timed words or syllables within the text, when the source has them.
    public var words: [LyricWord]
    /// Backing vocals sung over this line, with their own timings.
    public var backingText: String
    public var backing: [LyricWord]
    /// Who sings it, when the source says.
    public var agent: String?
    /// Sung only by the backing voices.
    public var background: Bool
    /// Sung by a second lead voice, as in a duet.
    public var duet: Bool
    /// The line in the phone's language, when the source has it.
    public var translation: String?
    /// How the line sounds, written in Latin letters, when the source has it.
    public var romanization: String?

    public init(
        startMs: Int = 0,
        endMs: Int? = nil,
        text: String,
        words: [LyricWord] = [],
        backingText: String = "",
        backing: [LyricWord] = [],
        agent: String? = nil,
        background: Bool = false,
        duet: Bool = false,
        translation: String? = nil,
        romanization: String? = nil
    ) {
        self.startMs = startMs
        self.endMs = endMs
        self.text = text
        self.words = words
        self.backingText = backingText
        self.backing = backing
        self.agent = agent
        self.background = background
        self.duet = duet
        self.translation = translation
        self.romanization = romanization
    }

    public var isGap: Bool { text.isBlankText && backingText.isBlankText }

    enum CodingKeys: String, CodingKey {
        case startMs, endMs, text, words, backingText, backing, agent, background, duet, translation, romanization
    }

    // A saved line may leave out any field that has a default.
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        startMs = try c.decodeIfPresent(Int.self, forKey: .startMs) ?? 0
        endMs = try c.decodeIfPresent(Int.self, forKey: .endMs)
        text = try c.decode(String.self, forKey: .text)
        words = try c.decodeIfPresent([LyricWord].self, forKey: .words) ?? []
        backingText = try c.decodeIfPresent(String.self, forKey: .backingText) ?? ""
        backing = try c.decodeIfPresent([LyricWord].self, forKey: .backing) ?? []
        agent = try c.decodeIfPresent(String.self, forKey: .agent)
        background = try c.decodeIfPresent(Bool.self, forKey: .background) ?? false
        duet = try c.decodeIfPresent(Bool.self, forKey: .duet) ?? false
        translation = try c.decodeIfPresent(String.self, forKey: .translation)
        romanization = try c.decodeIfPresent(String.self, forKey: .romanization)
    }
}

/// A timed piece of a line: `from` and `to` are where it sits in the line's text, in UTF-16
/// units, `to` not included.
public struct LyricWord: Equatable, Sendable, Codable {
    public var startMs: Int
    public var endMs: Int?
    public var text: String
    public var from: Int
    public var to: Int

    public init(startMs: Int, endMs: Int? = nil, text: String, from: Int, to: Int) {
        self.startMs = startMs
        self.endMs = endMs
        self.text = text
        self.from = from
        self.to = to
    }
}

extension Array where Element == LyricLine {
    /// Which line is being sung at this point in the song: the last one that has started, or -1
    /// before the first.
    public func lineAt(_ positionMs: Int) -> Int {
        var low = 0
        var high = count - 1
        var found = -1
        while low <= high {
            let mid = (low + high) >> 1
            if self[mid].startMs <= positionMs {
                found = mid
                low = mid + 1
            } else {
                high = mid - 1
            }
        }
        return found
    }

    /// When a line ends: its own end, or when the next one starts.
    public func endOf(_ index: Int) -> Int? {
        self[index].endMs ?? (index + 1 < count ? self[index + 1].startMs : nil)
    }
}

// A gap longer than this, before the first line or after a line that is known to end, gets its
// own quiet line so the dots can show there.
private let LONG_GAP_MS = 5_000

extension Lyrics {
    /// The lines as they are shown: a long wait before the first line, or after a line that is
    /// known to end, becomes an empty line where the dots show.
    public func shownLines() -> [LyricLine] {
        if !synced || lines.isEmpty { return lines }
        var shown: [LyricLine] = []
        shown.reserveCapacity(lines.count + 4)
        if lines[0].startMs >= LONG_GAP_MS && !lines[0].isGap { shown.append(LyricLine(startMs: 0, text: "")) }
        for (index, line) in lines.enumerated() {
            shown.append(line)
            guard let end = line.endMs else { continue }
            guard index + 1 < lines.count else { continue }
            let next = lines[index + 1].startMs
            if !line.isGap && next - end >= LONG_GAP_MS && !lines[index + 1].isGap {
                shown.append(LyricLine(startMs: end, text: ""))
            }
        }
        return shown
    }
}
