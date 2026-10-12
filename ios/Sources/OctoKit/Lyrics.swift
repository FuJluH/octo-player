import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// Every copy of a song's lyrics an Octo server's sources hold (the octoLyrics extension), and
/// what the song is set to: "auto", "none", or the id of the copy pinned. The choice holds for
/// the whole server, so every app and every listener sees it.
public struct LyricsCandidates: Decodable, Sendable {
    public var id: String
    public var choice: String
    public var candidate: [LyricsCandidate]

    enum CodingKeys: String, CodingKey { case id, choice, candidate }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = c.string(.id) ?? ""
        choice = c.string(.choice) ?? LyricsChoice.auto
        candidate = (try? c.decodeIfPresent([LyricsCandidate].self, forKey: .candidate)) ?? []
    }
}

public enum LyricsChoice {
    /// The server finds the lyrics itself.
    public static let auto = "auto"
    /// The song's lyrics are hidden.
    public static let none = "none"
}

/// One copy of a song's lyrics. The id names its source before the colon ("kugou:123").
public struct LyricsCandidate: Decodable, Sendable, Identifiable, Equatable {
    public var id: String
    public var source: String
    public var title: String
    public var artist: String
    public var album: String?
    /// Seconds, when the source says.
    public var duration: Int?
    /// "word", "line", "plain" or "instrumental".
    public var kind: String
    /// The server is sure it is this song, going by title, artist and length.
    public var sameSong: Bool
    public var chosen: Bool
    public var preview: [String]
    /// For copies found by the phone itself (lrclib), the lyrics themselves.
    public var lyrics: StructuredLyrics?

    enum CodingKeys: String, CodingKey { case id, source, title, artist, album, duration, kind, sameSong, chosen, preview }

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

    public init(id: String, source: String, title: String, artist: String, album: String?, duration: Int?, kind: String,
                sameSong: Bool, chosen: Bool, preview: [String], lyrics: StructuredLyrics?) {
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
        self.lyrics = lyrics
    }
}

extension SubsonicClient {
    /// The copies an Octo server finds; a title or artist typed by hand searches for those.
    public func lyricsCandidates(songId: String, title: String? = nil, artist: String? = nil) async throws -> LyricsCandidates {
        var params = [("id", songId)]
        if let title = title?.trimmingCharacters(in: .whitespaces), !title.isEmpty { params.append(("title", title)) }
        if let artist = artist?.trimmingCharacters(in: .whitespaces), !artist.isEmpty { params.append(("artist", artist)) }
        return try await get("getLyricsCandidates", params, key: "lyricsCandidates", timeout: 60)
    }

    /// Pins a copy, or sets the song back to "auto", or hides it with "none".
    public func setLyricsChoice(songId: String, candidate: String) async throws {
        try await call("setLyricsChoice", [("id", songId), ("candidate", candidate)])
    }
}

/// lrclib.net, the open lyrics library the other apps ask last. Every call goes through
/// OnlineLyrics, so lookups, matching and ranking are the same as on the other apps.
public enum LrcLib {
    /// The best match for a song, by title, artist, album and length (whole seconds).
    public static func find(title: String, artist: String, album: String?, duration: Int?, userAgent: String,
                            session: URLSession = .shared) async throws -> StructuredLyrics? {
        let library = OnlineLyrics(session: session, userAgent: userAgent)
        let found = try await library.find(title, artist: artist, album: album ?? "", durationMs: (duration ?? 0) * 1000)
        return found.map(StructuredLyrics.init(lyrics:))
    }

    /// Every copy lrclib holds of a title and artist, any version of it, for the chooser: timed
    /// copies first.
    public static func search(title: String, artist: String, userAgent: String, session: URLSession = .shared) async throws -> [LyricsCandidate] {
        let library = OnlineLyrics(session: session, userAgent: userAgent)
        return try await library.copiesOf(title, artist: artist, album: "", durationMs: 0).map { candidate($0, artist: artist) }
    }

    /// One copy by its lrclib id ("lrclib:123" or "123").
    public static func copy(_ id: String, userAgent: String, session: URLSession = .shared) async throws -> StructuredLyrics? {
        guard let number = id.split(separator: ":").last.flatMap({ Int($0) }) else { return nil }
        let library = OnlineLyrics(session: session, userAgent: userAgent)
        return try await library.byId(number).map(StructuredLyrics.init(lyrics:))
    }

    static func candidate(_ copy: OnlineCopy, artist: String) -> LyricsCandidate {
        let lyrics = StructuredLyrics(lyrics: copy.lyrics)
        let kind: String
        if copy.lyrics.instrumental {
            kind = "instrumental"
        } else if !copy.lyrics.synced {
            kind = "plain"
        } else {
            kind = copy.lyrics.lines.contains { !$0.words.isEmpty } ? "word" : "line"
        }
        return LyricsCandidate(
            id: "lrclib:\(copy.id)", source: "lrclib", title: copy.title, artist: copy.artist.isEmpty ? artist : copy.artist,
            album: copy.album.isEmpty ? nil : copy.album, duration: copy.durationMs > 0 ? copy.durationMs / 1000 : nil,
            kind: kind, sameSong: false, chosen: false,
            preview: Array(lyrics.line.map(\.value).filter { !$0.isEmpty }.prefix(3)), lyrics: lyrics)
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
