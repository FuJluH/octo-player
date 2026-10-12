import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// Every copy of a song's lyrics an Octo server's sources hold (the octoLyrics extension), and
/// what the song is set to: "auto", "none", or the id of the copy pinned. The choice holds for
/// the whole server, so every app and every listener sees it.
public struct LyricsCandidates: Decodable, Sendable, Equatable {
    public var id: String
    public var choice: String
    public var candidate: [ServerLyricsCandidate]

    enum CodingKeys: String, CodingKey { case id, choice, candidate }

    public init(id: String = "", choice: String = LYRICS_AUTO, candidate: [ServerLyricsCandidate] = []) {
        self.id = id
        self.choice = choice
        self.candidate = candidate
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = c.string(.id) ?? ""
        choice = c.string(.choice) ?? LYRICS_AUTO
        candidate = (try? c.decodeIfPresent([ServerLyricsCandidate].self, forKey: .candidate)) ?? []
    }
}

/// One copy the server found. The id names its source before the colon ("kugou:123"), and is
/// what a pin sends back.
public struct ServerLyricsCandidate: Decodable, Sendable, Equatable {
    public var id: String
    /// Where it was found, as the server names it: "kugou", "lrclib" and so on.
    public var source: String
    public var title: String
    public var artist: String
    public var album: String?
    /// Seconds, when the source says.
    public var duration: Int?
    /// "word", "line", "plain" or "instrumental".
    public var kind: String
    /// Whether the server is sure it is this song, going by title, artist and length.
    public var sameSong: Bool
    /// Whether it is the copy pinned now.
    public var chosen: Bool
    /// Its first lines with words.
    public var preview: [String]

    enum CodingKeys: String, CodingKey { case id, source, title, artist, album, duration, kind, sameSong, chosen, preview }

    public init(id: String = "", source: String = "", title: String = "", artist: String = "", album: String? = nil,
                duration: Int? = nil, kind: String = "", sameSong: Bool = false, chosen: Bool = false, preview: [String] = []) {
        self.id = id
        self.source = source
        self.title = title
        self.artist = artist
        self.album = album
        self.duration = duration
        self.kind = kind
        self.sameSong = sameSong
        self.chosen = chosen
        self.preview = preview
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = c.string(.id) ?? ""
        source = c.string(.source) ?? ""
        title = c.string(.title) ?? ""
        artist = c.string(.artist) ?? ""
        album = c.string(.album)
        duration = c.int(.duration)
        kind = c.string(.kind) ?? ""
        sameSong = c.bool(.sameSong) ?? false
        chosen = c.bool(.chosen) ?? false
        preview = (try? c.decodeIfPresent([String].self, forKey: .preview)) ?? []
    }
}

/// What setLyricsChoice answers: the song and what it is set to now.
struct LyricsChoiceAnswer: Decodable {
    var choice: String?
}

/// The whole answer to setLyricsChoice, which may leave its part out.
struct LyricsChoiceBody: Decodable {
    var lyricsChoice: LyricsChoiceAnswer?
}

/// What the older lyrics call answers with.
struct PlainLyricsBody: Decodable {
    var value: String?
}

/// The whole answer to the older lyrics call, which may leave its part out.
struct PlainLyricsAnswer: Decodable {
    var lyrics: PlainLyricsBody?
}

/// What asking for a song's lyrics copies sends. A title or artist typed by hand searches for
/// those instead of the song's own tags.
public func lyricsCandidatesParams(_ id: String, _ title: String?, _ artist: String?) -> [(String, String)] {
    var params = [("id", id)]
    if let title = title?.trimWhitespace(), !title.isEmpty { params.append(("title", title)) }
    if let artist = artist?.trimWhitespace(), !artist.isEmpty { params.append(("artist", artist)) }
    return params
}

extension SubsonicClient {
    /// Every set of lyrics the server has for a song. Only for servers that list the songLyrics
    /// extension. Enhanced (version 2) adds word timings, who sings each line, and translations.
    public func lyricsBySongId(_ id: String, enhanced: Bool) async throws -> [StructuredLyrics] {
        let params = enhanced ? [("id", id), ("enhanced", "true")] : [("id", id)]
        let body: LyricsListBody = try await get("getLyricsBySongId", params, key: "lyricsList")
        return body.structuredLyrics
    }

    /// Every copy of a song's lyrics the server's sources hold, and what the song is set to. Only
    /// for servers that list the octoLyrics extension. A title or artist given searches for those
    /// instead of the song's tags.
    public func lyricsCandidates(_ id: String, title: String? = nil, artist: String? = nil) async throws -> LyricsCandidates {
        try await get("getLyricsCandidates", lyricsCandidatesParams(id, title, artist), key: "lyricsCandidates", timeout: 60)
    }

    /// Sets a song's lyrics on the server to one copy from lyricsCandidates, to "none" to hide
    /// them, or to "auto" to let the server find them again. It holds for every app and user on
    /// the server. Answers with what the song is set to now.
    @discardableResult
    public func setLyricsChoice(_ id: String, candidate: String) async throws -> String {
        let body: LyricsChoiceBody = try await get("setLyricsChoice", [("id", id), ("candidate", candidate)], key: nil)
        return body.lyricsChoice?.choice ?? candidate
    }

    /// The older lyrics call, found by artist and title: plain text, or nil when the server has
    /// none.
    public func lyrics(artist: String, title: String) async throws -> String? {
        let body: PlainLyricsAnswer = try await get("getLyrics", [("artist", artist), ("title", title)], key: nil)
        guard let value = body.lyrics?.value, !value.isBlankText else { return nil }
        return value
    }
}

/// Reads LRC text: "[01:02.34]words" lines, several stamps on one line allowed, through
/// parseLyricsText, with the offset already in every start. Text without stamps comes back plain.
public enum Lrc {
    public static func parse(_ text: String) -> StructuredLyrics {
        parseLyricsText(text, source: .lyricsFile).map(StructuredLyrics.init(lyrics:)) ?? StructuredLyrics(synced: true, lines: [])
    }
}

extension StructuredLyrics {
    public init(synced: Bool, lines: [LyricsLine], offset: Int = 0) {
        self.init(lang: nil, synced: synced, line: lines, offset: offset)
    }

    /// Lyrics as plain lines: each line's text, and its start when they are synced.
    public init(lyrics: Lyrics) {
        self.init(
            lang: nil,
            synced: lyrics.synced,
            line: lyrics.lines.map { LyricsLine(start: lyrics.synced ? $0.startMs : nil, value: $0.text) }
        )
    }
}
