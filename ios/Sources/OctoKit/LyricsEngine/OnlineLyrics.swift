import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

// The free, open lyrics library used when nothing else has a song's lyrics. It needs no key; the
// app names itself in every request.
@usableFromInline let LIBRARY_ADDRESS = "https://lrclib.net"

// What the lyrics library answers for one song. A field of the wrong type fails the whole answer;
// one that is missing takes its default.
struct LibrarySong: Decodable, Sendable {
    // The library's number for this copy.
    var id: Int?
    var instrumental: Bool
    var plainLyrics: String?
    var syncedLyrics: String?
    // Seconds; only search answers carry it.
    var duration: Double?
    var albumName: String?
    var trackName: String?
    var artistName: String?

    enum CodingKeys: String, CodingKey { case id, instrumental, plainLyrics, syncedLyrics, duration, albumName, trackName, artistName }

    init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        id = try c.decodeIfPresent(Int.self, forKey: .id)
        instrumental = c.contains(.instrumental) ? try c.decode(Bool.self, forKey: .instrumental) : false
        plainLyrics = try c.decodeIfPresent(String.self, forKey: .plainLyrics)
        syncedLyrics = try c.decodeIfPresent(String.self, forKey: .syncedLyrics)
        duration = try c.decodeIfPresent(Double.self, forKey: .duration)
        albumName = try c.decodeIfPresent(String.self, forKey: .albumName)
        trackName = try c.decodeIfPresent(String.self, forKey: .trackName)
        artistName = try c.decodeIfPresent(String.self, forKey: .artistName)
    }
}

// How far apart two lengths may be and still be the same recording.
private let SAME_LENGTH_S = 3.0

/// The library answered with a failure: the lookup could not be made, which is not the same as
/// the library having no lyrics for the song.
public struct OnlineLyricsError: Error, Equatable, Sendable, CustomStringConvertible {
    public let status: Int
    public var description: String { "Lyrics lookup failed: HTTP \(status)" }
}

/// Looks a song up in the online lyrics library by its title, artist, album and length, which is
/// all that is sent.
public final class OnlineLyrics: @unchecked Sendable {
    private let session: URLSession
    private let base: URL
    private let userAgent: String?

    /// `userAgent` names the app in every request.
    public init(session: URLSession = .shared, base: URL = URL(string: LIBRARY_ADDRESS)!, userAgent: String? = nil) {
        self.session = session
        self.base = base
        self.userAgent = userAgent
    }

    /// The song's lyrics, or nil when the library does not have them. Throws when the library
    /// cannot be reached.
    /// The exact lookup comes first. When it finds nothing timed, the library's search is asked
    /// too: it often holds a timed copy of the same recording under a slightly different album or
    /// title. The search is asked with each of the song's search queries in turn, until one
    /// answer holds a timed copy. A search that cannot be reached still leaves plain lyrics found;
    /// with none, it is a failure, never "the library has none".
    public func find(_ title: String, artist: String, album: String, durationMs: Int) async throws -> Lyrics? {
        let exact = try await fetch(lookupUrl(base, title: title, artist: artist, album: album, durationMs: durationMs))
            .flatMap(libraryLyrics)
        if let exact, exact.synced || exact.instrumental { return exact }
        for query in lyricsSearches(title, artist: artist) {
            let found: String?
            do {
                found = try await fetch(searchUrl(base, title: query.title, artist: query.artist))
            } catch let error where isLookupFailure(error) {
                if exact == nil { throw error }
                break
            }
            guard let found else { continue }
            if let match = bestSearchMatch(found, title: title, artist: artist, album: album, durationMs: durationMs) { return match }
        }
        return exact
    }

    /// The library's own match for the song, or nil when it has none. Throws when the library
    /// cannot be reached.
    public func exact(_ title: String, artist: String, album: String, durationMs: Int) async throws -> OnlineCopy? {
        try await fetch(lookupUrl(base, title: title, artist: artist, album: album, durationMs: durationMs))
            .flatMap(librarySong)?.toCopy()
    }

    /// Every copy in the library's search with the song's title and artist, for the listener to
    /// choose from. Looser than `find`: live takes and remixes stay in the list, named, since the
    /// listener picks. The search queries are asked in turn until one finds copies; only the
    /// first request's failure is thrown.
    public func copiesOf(_ title: String, artist: String, album: String, durationMs: Int) async throws -> [OnlineCopy] {
        for (index, query) in lyricsSearches(title, artist: artist).enumerated() {
            let url = searchUrl(base, title: query.title, artist: query.artist)
            let body: String?
            if index == 0 {
                body = try await fetch(url)
            } else {
                do { body = try await fetch(url) } catch { break }
            }
            guard let body else { continue }
            let copies = songCopies(body).filter { sameTitleAndArtist($0, title: title, artist: artist) }
            if !copies.isEmpty { return rankCopies(copies, album: album, durationMs: durationMs) }
        }
        return []
    }

    /// Whatever the library finds for words the listener typed, as it answers them: for a song
    /// whose tags are wrong, nothing is filtered.
    public func search(_ query: String) async throws -> [OnlineCopy] {
        try await fetch(freeSearchUrl(base, query: query)).map(songCopies) ?? []
    }

    /// One copy by its number, for lyrics the listener picked before; nil when the library no
    /// longer has it.
    public func byId(_ id: Int) async throws -> Lyrics? {
        try await fetch(recordUrl(base, id: id)).flatMap(libraryLyrics)
    }

    // The answer's body, or nil when the library has nothing for it. A lookup no longer wanted
    // (the song was skipped) stops its request.
    private func fetch(_ url: URL) async throws -> String? {
        try Task.checkCancellation()
        var request = URLRequest(url: url, timeoutInterval: 10)
        if let userAgent { request.setValue(userAgent, forHTTPHeaderField: "User-Agent") }
        let (data, response) = try await session.data(for: request)
        return try read(data, response)
    }

    private func read(_ data: Data, _ response: URLResponse) throws -> String? {
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        if status == 404 { return nil }
        if !(200..<300).contains(status) { throw OnlineLyricsError(status: status) }
        return String(decoding: data, as: UTF8.self)
    }

    // A failure to reach the library or a failed answer, as opposed to the lookup being stopped.
    private func isLookupFailure(_ error: Error) -> Bool {
        if error is OnlineLyricsError { return true }
        if let error = error as? URLError { return error.code != .cancelled }
        return false
    }
}

/// A search by title and artist, which returns every copy the library holds.
func searchUrl(_ base: URL, title: String, artist: String) -> URL {
    libraryUrl(base, path: ["api", "search"], query: [("track_name", title), ("artist_name", artist)])
}

// How many searches a song may cost when the first finds nothing.
private let MAX_SEARCHES = 3

// Lyrics compare lengths on their own, since not every copy knows one. A clean edit counts as the
// song here: its lyrics are the same words at the same times, with a few bleeped. Downloads and
// the library stay strict.
private let LyricsTitles = SongMatchOptions(lengthToleranceSeconds: nil, alsoNeutral: ["clean"])

/// Whether a copy is the song asked for, as lyrics read it: the same title whole (case, accents,
/// punctuation, stylized characters, guests and upload noise ignored), the same kind of
/// recording, and the same artist.
func sameLyricsSong(_ wantTitle: String, wantArtist: String, gotTitle: String?, gotArtist: String?) -> Bool {
    guard let gotTitle, !gotTitle.isBlankText, !wantArtist.isBlankText else { return false }
    return SongIdentity.same(wantTitle, wantArtist, gotTitle, gotArtist, options: LyricsTitles).isSame
}

/// The searches to ask for a song, from SongIdentity's query variants: as tagged, cleaned, with
/// stylized characters read as letters, and by the primary artist alone. Each keeps an artist,
/// since a search by title alone returns every song of that name, and there are at most three.
/// Whatever they find is still held to the song as asked.
func lyricsSearches(_ title: String, artist: String) -> [SongQuery] {
    let queries = Array(SongIdentity.queryVariants(title, artist).filter { !$0.artist.isEmpty }.prefix(MAX_SEARCHES))
    return queries.isEmpty ? [SongQuery(title: title, artist: artist)] : queries
}

/// The timed copy in a search answer that is the same song (see sameLyricsSong: a remix never
/// stands in for the original), with a length within a few seconds when the song's is known, the
/// same album preferred. The search is loose and returns other songs by the artist too; a length
/// alone once let one of those stand in. Nil when no timed copy of this song is there.
func bestSearchMatch(_ body: String, title: String, artist: String, album: String, durationMs: Int) -> Lyrics? {
    guard let songs = try? JSONDecoder().decode([LibrarySong].self, from: Data(body.utf8)) else { return nil }
    let seconds = Double(durationMs) / 1000.0
    func otherAlbum(_ song: LibrarySong) -> Bool { !(song.albumName?.equalsIgnoreCase(album) ?? false) }
    func apart(_ song: LibrarySong) -> Double {
        if durationMs > 0, let duration = song.duration { return abs(duration - seconds) }
        return 0.0
    }
    let ranked = songs
        .filter { !($0.syncedLyrics?.isBlankText ?? true) }
        .filter { sameLyricsSong(title, wantArtist: artist, gotTitle: $0.trackName, gotArtist: $0.artistName) }
        .filter { song in durationMs <= 0 || (song.duration.map { abs($0 - seconds) <= SAME_LENGTH_S } ?? false) }
        .stableSorted { a, b in
            if otherAlbum(a) != otherAlbum(b) { return !otherAlbum(a) }
            return apart(a) < apart(b)
        }
    for song in ranked {
        guard let synced = song.syncedLyrics, var lyrics = parseLyricsText(synced, source: .online), lyrics.synced else { continue }
        lyrics.onlineId = song.id
        return lyrics
    }
    return nil
}

/// A search for words the listener typed, matched against any field.
func freeSearchUrl(_ base: URL, query: String) -> URL {
    libraryUrl(base, path: ["api", "search"], query: [("q", query.trimWhitespace())])
}

/// One copy by the library's number for it.
func recordUrl(_ base: URL, id: Int) -> URL {
    libraryUrl(base, path: ["api", "get", String(id)], query: [])
}

/// One copy of a song's lyrics in the online library: its number, what the library calls it, and
/// its lyrics.
public struct OnlineCopy: Equatable, Sendable {
    public var id: Int
    public var title: String
    public var artist: String
    public var album: String
    public var durationMs: Int
    public var lyrics: Lyrics

    public init(id: Int, title: String, artist: String, album: String, durationMs: Int, lyrics: Lyrics) {
        self.id = id
        self.title = title
        self.artist = artist
        self.album = album
        self.durationMs = durationMs
        self.lyrics = lyrics
    }
}

/// The same song as the one playing, in any version: the same title and the same artist, as
/// lyrics read them. A live take or a remix stays, since the listener picks.
func sameTitleAndArtist(_ copy: OnlineCopy, title: String, artist: String) -> Bool {
    !copy.title.isBlankText && !artist.isBlankText
        && SongIdentity.same(title, artist, copy.title, copy.artist, options: LyricsTitles).verdict != .different
}

/// Copies in the order they are offered: timed ones first, then the same album, then the nearest
/// length.
func rankCopies(_ copies: [OnlineCopy], album: String, durationMs: Int) -> [OnlineCopy] {
    func otherAlbum(_ copy: OnlineCopy) -> Bool { !(!album.isBlankText && copy.album.equalsIgnoreCase(album)) }
    func apart(_ copy: OnlineCopy) -> Int {
        durationMs > 0 && copy.durationMs > 0 ? abs(copy.durationMs - durationMs) : Int.max
    }
    return copies.stableSorted { a, b in
        if a.lyrics.synced != b.lyrics.synced { return a.lyrics.synced }
        if otherAlbum(a) != otherAlbum(b) { return !otherAlbum(a) }
        return apart(a) < apart(b)
    }
}

/// Every copy in a search answer that has lyrics.
func songCopies(_ body: String) -> [OnlineCopy] {
    ((try? JSONDecoder().decode([LibrarySong].self, from: Data(body.utf8))) ?? []).compactMap { $0.toCopy() }
}

private func librarySong(_ body: String) -> LibrarySong? {
    try? JSONDecoder().decode(LibrarySong.self, from: Data(body.utf8))
}

extension LibrarySong {
    /// A copy with its lyrics, or nil when it has no number or no words.
    func toCopy() -> OnlineCopy? {
        guard let number = id, let words = asLyrics() else { return nil }
        let length = duration.map { roundToLong($0 * 1000) } ?? 0
        return OnlineCopy(id: number, title: trackName ?? "", artist: artistName ?? "", album: albumName ?? "", durationMs: length, lyrics: words)
    }

    // Synced lyrics when the copy has them, plain if not, and an instrumental marked as one.
    fileprivate func asLyrics() -> Lyrics? {
        if instrumental { return Lyrics(synced: false, lines: [], source: .online, instrumental: true, onlineId: id) }
        let timed = syncedLyrics.flatMap { parseLyricsText($0, source: .online) }.flatMap { $0.synced ? $0 : nil }
        guard var words = timed ?? plainLyrics.flatMap({ parseLyricsText($0, source: .online) }) else { return nil }
        words.onlineId = id
        return words
    }
}

/// The lookup for one song. The library matches the length to within a couple of seconds, so it
/// is sent in whole seconds; an unknown album or length is left out.
func lookupUrl(_ base: URL, title: String, artist: String, album: String, durationMs: Int) -> URL {
    var query = [("track_name", title), ("artist_name", artist)]
    if !album.isBlankText { query.append(("album_name", album)) }
    if durationMs > 0 { query.append(("duration", String(roundToLong(Double(durationMs) / 1000.0)))) }
    return libraryUrl(base, path: ["api", "get"], query: query)
}

/// The library's answer as lyrics: synced when it has them, plain if not, and an instrumental
/// marked as one.
func libraryLyrics(_ body: String) -> Lyrics? { librarySong(body)?.asLyrics() }

// The base address with path segments added after its own (a trailing empty segment is replaced)
// and query parameters appended, every value escaped so that "+", "&", "=" and the other
// separators arrive as written.
private func libraryUrl(_ base: URL, path: [String], query: [(String, String)]) -> URL {
    var parts = URLComponents(url: base, resolvingAgainstBaseURL: false)!
    var basePath = parts.percentEncodedPath
    if !basePath.hasSuffix("/") { basePath += "/" }
    parts.percentEncodedPath = basePath + path.map(escapeSegment).joined(separator: "/")
    if !query.isEmpty {
        let added = query.map { escapeQuery($0.0) + "=" + escapeQuery($0.1) }.joined(separator: "&")
        parts.percentEncodedQuery = parts.percentEncodedQuery.map { $0 + "&" + added } ?? added
    }
    return parts.url!
}

// Bytes a query name or value always escapes: controls, anything outside ASCII, and these.
private let queryEscaped = Set(" !\"#$&'(),/:;<=>?@[]\\^`{|}~+%".utf8)

private func escapeQuery(_ text: String) -> String {
    escape(text) { $0 < 0x20 || $0 >= 0x7F || queryEscaped.contains($0) }
}

private let segmentEscaped = Set(" \"<>^`{}|/\\?#%".utf8)

private func escapeSegment(_ text: String) -> String {
    escape(text) { $0 < 0x20 || $0 >= 0x7F || segmentEscaped.contains($0) }
}

private func escape(_ text: String, _ escaped: (UInt8) -> Bool) -> String {
    var out = ""
    for byte in text.utf8 {
        if escaped(byte) {
            out += String(format: "%%%02X", Int(byte))
        } else {
            out.unicodeScalars.append(Unicode.Scalar(byte))
        }
    }
    return out
}
