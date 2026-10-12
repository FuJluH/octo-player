import Foundation

// MARK: Biography

private let moreLink = try! NSRegularExpression(pattern: #"<a\b[^>]*>\s*read more\b[^<]*</a>\s*\.?\s*$"#, options: [.caseInsensitive])
private let breaks = try! NSRegularExpression(pattern: #"<br\s*/?>|</p\s*>"#, options: [.caseInsensitive])
private let tags = try! NSRegularExpression(pattern: #"<[^>]*>"#)
private let spaces = try! NSRegularExpression(pattern: "[ \t\u{00A0}]+")
private let gaps = try! NSRegularExpression(pattern: #"\s*\n\s*(\n\s*)*"#)
private let numbered = try! NSRegularExpression(pattern: "&#(x[0-9a-fA-F]+|[0-9]+);")
private let named: [(String, String)] = [("&quot;", "\""), ("&apos;", "'"), ("&lt;", "<"), ("&gt;", ">"), ("&nbsp;", "\u{00A0}")]

private func replacing(_ pattern: NSRegularExpression, in text: String, with template: String) -> String {
    pattern.stringByReplacingMatches(in: text, range: NSRange(text.startIndex..., in: text), withTemplate: template)
}

/// Replaces each match with what `with` makes of it.
private func replacing(_ pattern: NSRegularExpression, in text: String, with: (String, [String]) -> String) -> String {
    let source = text as NSString
    var out = ""
    var last = 0
    for match in pattern.matches(in: text, range: NSRange(location: 0, length: source.length)) {
        out += source.substring(with: NSRange(location: last, length: match.range.location - last))
        var groups: [String] = []
        for index in 0..<match.numberOfRanges {
            let range = match.range(at: index)
            groups.append(range.location == NSNotFound ? "" : source.substring(with: range))
        }
        out += with(groups[0], groups)
        last = match.range.location + match.range.length
    }
    out += source.substring(from: last)
    return out
}

/// A biography as plain text: the "Read more" link servers add at the end is dropped, then every
/// tag, and the rest is written out as characters with tidy spacing. Nothing when no words are
/// left.
public func cleanBiography(_ html: String) -> String? {
    var text = replacing(moreLink, in: html.trimmingCharacters(in: .whitespacesAndNewlines), with: "")
    text = replacing(breaks, in: text, with: "\n")
    text = replacing(tags, in: text, with: "")
    text = replacing(numbered, in: text) { whole, groups in
        let code = groups[1]
        let value = code.hasPrefix("x") ? UInt32(code.dropFirst(), radix: 16) : UInt32(code)
        guard let value, let scalar = Unicode.Scalar(value) else { return whole }
        return String(Character(scalar))
    }
    for (name, character) in named { text = text.replacingOccurrences(of: name, with: character, options: .caseInsensitive) }
    text = text.replacingOccurrences(of: "&amp;", with: "&", options: .caseInsensitive)
    // Paragraphs keep one empty line between them; other runs of space become one.
    text = replacing(spaces, in: text, with: " ")
    text = replacing(gaps, in: text) { whole, _ in whole.filter { $0 == "\n" }.count > 1 ? "\n\n" : "\n" }
    let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
    return trimmed.isEmpty ? nil : trimmed
}

// MARK: A library album whole

/// A library album's songs as the server sent them (`sent`), resolved to library songs and finds in
/// the same order (`resolved`). Only songs the server marks as outside the library stay finds, each
/// numbered as the album numbers it: a song with no mark that the library lacks was added to the
/// server since the last copy, and the next copy brings it in.
public func outsideAlbumSongs(_ sent: [Song], _ resolved: [LibraryTrack]) -> [LibraryTrack] {
    var marked: [String: Song] = [:]
    for song in sent where song.isExternal { marked[findId(song.id)] = song }
    return resolved.compactMap { track in
        if !isFind(track.id) { return track }
        guard let song = marked[track.id] else { return nil }
        var numbered = track
        numbered.trackNo = song.track.flatMap { $0 > 0 ? $0 : nil }
        numbered.discNo = song.discNumber.flatMap { $0 > 0 ? $0 : nil }
        return numbered
    }
}

/// A library album whole: the server's songs in the server's order, each library one as the library
/// has it and each find the library has since taken in (`adoptions`, find to library song) as that
/// library song. Library songs the server did not list, such as a copy only on the phone, follow in
/// their own order. With no finds from the server, the album is the library's as it is.
public func wholeAlbum(_ library: [LibraryTrack], server: [LibraryTrack], adoptions: [String: String] = [:]) -> [LibraryTrack] {
    if !server.contains(where: { isFind($0.id) }) { return library }
    var ours: [String: LibraryTrack] = [:]
    for track in library where ours[track.id] == nil { ours[track.id] = track }
    var placed: [LibraryTrack] = []
    var seen = Set<String>()
    for track in server {
        let adopted = isFind(track.id) ? adoptions[track.id].flatMap { ours[$0] } : nil
        let shown = adopted ?? ours[track.id] ?? track
        if seen.insert(shown.id).inserted { placed.append(shown) }
    }
    for track in library where seen.insert(track.id).inserted { placed.append(track) }
    return placed
}

// MARK: A library artist's page extras

/// How many of an artist's top songs their page shows.
public let artistPageTopSongs = 10

/// The server's own id for a library artist id of the form "<server source>:<id>". Nothing for
/// other sources, or for an artist the library named itself because the server gave no id.
public func serverArtistIdOf(_ artistId: String, sourceId: String) -> String? {
    guard artistId.hasPrefix(sourceId + ":") else { return nil }
    let native = String(artistId.dropFirst(sourceId.count + 1))
    return native.isEmpty || native.hasPrefix("artist:") ? nil : native
}

/// Top songs that are the artist's own, for a server asked by name, which can also send songs by
/// someone else of a similar name.
public func ownSongs(_ songs: [Song], artist: String) -> [Song] {
    songs.filter { sameArtist($0.artist ?? "", artist) }
}

// MARK: What the server knows of an artist

/// An artist's biography and the artists like them, as getArtistInfo2 answers.
public struct ServerArtistInfo: Decodable, Sendable {
    public var biography: String?
    public var similarArtist: [Artist]

    enum CodingKeys: String, CodingKey { case biography, similarArtist }

    public init(biography: String? = nil, similarArtist: [Artist] = []) {
        self.biography = biography
        self.similarArtist = similarArtist
    }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        biography = c.string(.biography)
        similarArtist = (try? c.decodeIfPresent([Artist].self, forKey: .similarArtist)) ?? []
    }
}

/// The server extension that lets top songs be asked for by artist id.
public let topSongsByArtistId = "topSongsByArtistId"

extension SubsonicClient {
    /// An artist's biography and up to `similar` artists like them.
    public func artistInfo2(id: String, similar: Int = 20) async throws -> ServerArtistInfo {
        try await get("getArtistInfo2", [("id", id), ("count", "\(similar)")], key: "artistInfo2")
    }

    /// An artist's most played songs, by name, or by id too on a server that lists
    /// topSongsByArtistId.
    public func topSongs(artist name: String, count: Int, id: String?) async throws -> [Song] {
        var params = [("artist", name), ("count", "\(count)")]
        if let id { params.append(("id", id)) }
        let body: SongsBody = try await get("getTopSongs", params, key: "topSongs")
        return body.song
    }
}
