import Foundation

/// Where a set of lyrics to choose from was found, in the order the list shows them: the song's
/// own sources (the server's answer, then the copies the server's sources hold, when it offers
/// them), the online library's own match for the song, then the other copies its search holds.
public enum CandidateOrigin: Int, CaseIterable, Sendable {
    case server, serverCopy, songFile, lyricsFile, onlineMatch, onlineSearch
}

/// The origin lyrics from a source have when nothing else is known.
public func originOf(_ source: LyricsSource) -> CandidateOrigin {
    switch source {
    case .server: .server
    case .songFile: .songFile
    case .lyricsFile: .lyricsFile
    case .online: .onlineMatch
    }
}

/// How a set of lyrics is timed, best first.
public enum LyricsKind: Sendable, CaseIterable {
    case words, lines, plain, instrumental

    public var label: String {
        switch self {
        case .words: "Word by word"
        case .lines: "Timed"
        case .plain: "Not timed"
        case .instrumental: ""
        }
    }
}

public func kindOf(_ lyrics: Lyrics) -> LyricsKind {
    if lyrics.instrumental { return .instrumental }
    if !lyrics.synced { return .plain }
    if lyrics.lines.contains(where: { !$0.words.isEmpty }) { return .words }
    return .lines
}

/// One set of lyrics the listener can pick for a song. An online copy, or one the server holds,
/// carries what its source calls it; the song's own sources leave that blank. A copy the server
/// holds has no lyrics here, only its first lines and how it is timed: the server fetches the
/// rest once it is picked.
public struct LyricsCandidate: Equatable, Sendable {
    public var pick: LyricsPick
    public var origin: CandidateOrigin
    public var lyrics: Lyrics?
    public var title: String
    public var artist: String
    public var album: String
    public var durationMs: Int
    /// Where the server found it ("kugou", "lrclib"), for a server copy.
    public var source: String
    /// A server copy's timing and first lines, as the server said.
    public var serverKind: LyricsKind
    public var serverPreview: [String]

    public init(
        _ pick: LyricsPick,
        _ origin: CandidateOrigin,
        _ lyrics: Lyrics?,
        title: String = "",
        artist: String = "",
        album: String = "",
        durationMs: Int = 0,
        source: String = "",
        serverKind: LyricsKind = .plain,
        serverPreview: [String] = []
    ) {
        self.pick = pick
        self.origin = origin
        self.lyrics = lyrics
        self.title = title
        self.artist = artist
        self.album = album
        self.durationMs = durationMs
        self.source = source
        self.serverKind = serverKind
        self.serverPreview = serverPreview
    }

    public var kind: LyricsKind { lyrics.map(kindOf) ?? serverKind }

    /// The first two lines with words, to tell candidates apart at a glance.
    public var preview: [String] {
        if let lyrics {
            return Array(lyrics.lines.lazy.map { $0.text.trimWhitespace() }.filter { !$0.isEmpty }.prefix(2))
        }
        return Array(serverPreview.map { $0.trimWhitespace() }.filter { !$0.isEmpty }.prefix(2))
    }
}

extension OnlineCopy {
    public func asCandidate(_ origin: CandidateOrigin) -> LyricsCandidate {
        LyricsCandidate(.online(id), origin, lyrics, title: title, artist: artist, album: album, durationMs: durationMs)
    }
}

/// The list to choose from, and which entry (0 or none, -1) is showing now.
public struct CandidateChoices: Equatable, Sendable {
    public var items: [LyricsCandidate]
    public var showing: Int
}

/// Builds the list: the lyrics showing now first (the listener's pick, or else the ones the usual
/// order found), then the server's, the copies the server holds, the song file's, the .lrc
/// file's, the online library's match, then its search results, each kept in the order it came.
/// `current` is the pick in use, when known; without it, the showing lyrics are told apart by
/// their words. Each pick shows once, and lyrics with the same words and timing as one above are
/// left out, so a copy found twice is offered once (the server's copies are only known by their
/// first lines, so they are never merged this way). The showing lyrics are added when no source
/// offered them this time, so they can still be seen.
public func candidateList(_ found: [LyricsCandidate], current: LyricsPick?, showing: Lyrics?) -> CandidateChoices {
    let showingWords = showing.map(wordsOf)
    func isShowing(_ candidate: LyricsCandidate) -> Bool {
        if let current { return candidate.pick == current }
        if let showingWords { return candidate.lyrics.map(wordsOf) == showingWords }
        return false
    }
    let showingPick = current ?? showing.flatMap(pickOf)
    var all = found
    if let showing, let showingPick, !found.contains(where: { $0.pick == showingPick }) {
        all.append(LyricsCandidate(showingPick, originOf(showing.source), showing))
    }
    let ordered = all.enumerated().sorted { a, b in
        let aShowing = isShowing(a.element), bShowing = isShowing(b.element)
        if aShowing != bShowing { return aShowing }
        if a.element.origin != b.element.origin { return a.element.origin.rawValue < b.element.origin.rawValue }
        return a.offset < b.offset
    }.map(\.element)
    var picks = Set<LyricsPick>()
    var words = Set<String>()
    var items: [LyricsCandidate] = []
    for candidate in ordered {
        let lyrics = candidate.lyrics
        if let lyrics, lyrics.isEmpty { continue }
        if !picks.insert(candidate.pick).inserted { continue }
        if let lyrics, !words.insert(wordsOf(lyrics)).inserted { continue }
        items.append(candidate)
    }
    return CandidateChoices(items: items, showing: items.first.map(isShowing) == true ? 0 : -1)
}

/// The words and timing of a set of lyrics, to tell copies apart.
func wordsOf(_ lyrics: Lyrics) -> String {
    var out = lyrics.instrumental ? "instrumental" : (lyrics.synced ? "timed" : "plain")
    for line in lyrics.lines {
        out += "\n"
        if lyrics.synced { out += "\(line.startMs) " }
        out += line.text.trimWhitespace()
    }
    return out
}
