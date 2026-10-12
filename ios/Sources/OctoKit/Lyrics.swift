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

/// lrclib.net, the open lyrics library the other apps ask last.
public enum LrcLib {
    struct Record: Decodable {
        let id: Int
        let trackName: String?
        let artistName: String?
        let albumName: String?
        let duration: Double?
        let instrumental: Bool?
        let plainLyrics: String?
        let syncedLyrics: String?
    }

    /// The best match for a song, by title, artist and length.
    public static func find(title: String, artist: String, album: String?, duration: Int?, userAgent: String,
                            session: URLSession = .shared) async throws -> StructuredLyrics? {
        var parts = URLComponents(string: "https://lrclib.net/api/get")!
        parts.queryItems = [URLQueryItem(name: "track_name", value: title), URLQueryItem(name: "artist_name", value: artist)]
            + (album.map { [URLQueryItem(name: "album_name", value: $0)] } ?? [])
            + (duration.map { [URLQueryItem(name: "duration", value: String($0))] } ?? [])
        var request = URLRequest(url: parts.url!, timeoutInterval: 10)
        request.setValue(userAgent, forHTTPHeaderField: "User-Agent")
        let (data, response) = try await session.data(for: request)
        if (response as? HTTPURLResponse)?.statusCode == 404 { return nil }
        return lyrics(of: try JSONDecoder().decode(Record.self, from: data))
    }

    /// Every copy lrclib holds for a title and artist, for the chooser.
    public static func search(title: String, artist: String, userAgent: String, session: URLSession = .shared) async throws -> [LyricsCandidate] {
        var parts = URLComponents(string: "https://lrclib.net/api/search")!
        parts.queryItems = [URLQueryItem(name: "track_name", value: title), URLQueryItem(name: "artist_name", value: artist)]
        var request = URLRequest(url: parts.url!, timeoutInterval: 10)
        request.setValue(userAgent, forHTTPHeaderField: "User-Agent")
        let (data, _) = try await session.data(for: request)
        let records = try JSONDecoder().decode([Record].self, from: data)
        return records.prefix(20).compactMap { record in
            guard let found = lyrics(of: record) else { return nil }
            return LyricsCandidate(
                id: "lrclib:\(record.id)", source: "lrclib", title: record.trackName ?? title, artist: record.artistName ?? artist,
                album: record.albumName, duration: record.duration.map { Int($0) },
                kind: record.instrumental == true ? "instrumental" : (found.synced ? "line" : "plain"),
                sameSong: false, chosen: false,
                preview: Array(found.line.map(\.value).filter { !$0.isEmpty }.prefix(3)), lyrics: found)
        }
    }

    /// One copy by its lrclib id ("lrclib:123" or "123").
    public static func copy(_ id: String, userAgent: String, session: URLSession = .shared) async throws -> StructuredLyrics? {
        guard let number = id.split(separator: ":").last else { return nil }
        var request = URLRequest(url: URL(string: "https://lrclib.net/api/get/\(number)")!, timeoutInterval: 10)
        request.setValue(userAgent, forHTTPHeaderField: "User-Agent")
        let (data, _) = try await session.data(for: request)
        return lyrics(of: try JSONDecoder().decode(Record.self, from: data))
    }

    static func lyrics(of record: Record) -> StructuredLyrics? {
        if let synced = record.syncedLyrics, !synced.isEmpty { return Lrc.parse(synced) }
        if let plain = record.plainLyrics, !plain.isEmpty {
            return StructuredLyrics(synced: false, lines: plain.components(separatedBy: "\n").map { LyricsLine(start: nil, value: $0) })
        }
        return nil
    }
}

/// Reads LRC text: "[01:02.34]words" lines, several stamps on one line allowed.
public enum Lrc {
    public static func parse(_ text: String) -> StructuredLyrics {
        var lines: [LyricsLine] = []
        var offset = 0
        for raw in text.components(separatedBy: .newlines) {
            var rest = Substring(raw)
            var stamps: [Int] = []
            while rest.hasPrefix("["), let close = rest.firstIndex(of: "]") {
                let tag = rest[rest.index(after: rest.startIndex)..<close]
                if tag.hasPrefix("offset:"), let value = Int(tag.dropFirst(7).trimmingCharacters(in: .whitespaces)) {
                    offset = value
                } else if let ms = milliseconds(tag) {
                    stamps.append(ms)
                }
                rest = rest[rest.index(after: close)...]
            }
            for stamp in stamps { lines.append(LyricsLine(start: stamp, value: rest.trimmingCharacters(in: .whitespaces))) }
        }
        lines.sort { ($0.start ?? 0) < ($1.start ?? 0) }
        // In LRC and in OpenSubsonic alike, a positive offset shows the words sooner.
        return StructuredLyrics(synced: true, lines: lines, offset: offset)
    }

    static func milliseconds(_ tag: Substring) -> Int? {
        let parts = tag.split(separator: ":")
        guard parts.count == 2, let minutes = Int(parts[0]), let seconds = Double(parts[1]) else { return nil }
        return minutes * 60_000 + Int((seconds * 1000).rounded())
    }
}

extension StructuredLyrics {
    public init(synced: Bool, lines: [LyricsLine], offset: Int = 0) {
        self.lang = nil
        self.synced = synced
        self.offset = offset
        self.line = lines
    }
}
