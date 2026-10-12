import Foundation

// Playlist files (M3U and M3U8): reading, writing, and finding the songs a file names in a
// library.

/// The mark some editors put at the start of a text file to say it is UTF-8.
private let byteOrderMark = "\u{FEFF}"

/// One song in a playlist file: where the file said it is, and what its #EXTINF line said about
/// it, if it had one. `line` is the line number of the location, from 1.
public struct M3uEntry: Equatable, Sendable {
    public var location: String
    public var seconds: Int?
    public var artist: String?
    public var title: String?
    public var line: Int

    public init(location: String, seconds: Int? = nil, artist: String? = nil, title: String? = nil, line: Int = 0) {
        self.location = location
        self.seconds = seconds
        self.artist = artist
        self.title = title
        self.line = line
    }

    /// How a missed entry is listed: its #EXTINF artist and title, or its location.
    public var shown: String {
        if let title, let artist, !artist.trimmingCharacters(in: .whitespaces).isEmpty { return "\(artist) - \(title)" }
        if let title { return title }
        return location
    }
}

private extension String {
    var oneLine: String {
        replacingOccurrences(of: "\r", with: " ").replacingOccurrences(of: "\n", with: " ").trimmingCharacters(in: .whitespaces)
    }
}

/// Reads an M3U or M3U8 playlist: a location per line, each optionally led by an #EXTINF line
/// with its length and "Artist - Title". Other # lines are skipped. Takes Windows and Unix line
/// endings and a leading byte order mark.
public func parseM3u(_ text: String) -> [M3uEntry] {
    var entries: [M3uEntry] = []
    var info: (Int?, String?, String?)?
    let lines = text.removingPrefix(byteOrderMark).replacingOccurrences(of: "\r\n", with: "\n").split(separator: "\n", omittingEmptySubsequences: false)
    for (index, raw) in lines.enumerated() {
        let line = String(raw).trimmingCharacters(in: .whitespacesAndNewlines).removingPrefix(byteOrderMark)
        if line.isEmpty { continue }
        if line.lowercased().hasPrefix("#extinf:") {
            info = extInf(String(line.dropFirst("#EXTINF:".count)))
        } else if line.hasPrefix("#") {
            continue
        } else {
            let (seconds, artist, title) = info ?? (nil, nil, nil)
            entries.append(M3uEntry(location: line, seconds: seconds, artist: artist, title: title, line: index + 1))
            info = nil
        }
    }
    return entries
}

/// "215,Kavinsky - Nightcall", or with attributes before the comma. A length of -1 or 0 means
/// unknown.
private func extInf(_ body: String) -> (Int?, String?, String?) {
    let comma = firstCommaOutsideQuotes(body)
    let head = comma.map { String(body[..<$0]) } ?? body
    let display = comma.map { String(body[body.index(after: $0)...]).trimmingCharacters(in: .whitespaces) } ?? ""
    let first = head.trimmingCharacters(in: .whitespaces).split(separator: " ", maxSplits: 1, omittingEmptySubsequences: false).first.map(String.init) ?? ""
    let seconds = Double(first).map { Int($0) }.flatMap { $0 > 0 ? $0 : nil }
    if display.isEmpty { return (seconds, nil, nil) }
    if let split = display.range(of: " - "), split.lowerBound > display.startIndex {
        return (seconds, String(display[..<split.lowerBound]).trimmingCharacters(in: .whitespaces),
                String(display[split.upperBound...]).trimmingCharacters(in: .whitespaces))
    }
    return (seconds, nil, display)
}

private func firstCommaOutsideQuotes(_ text: String) -> String.Index? {
    var quoted = false
    var index = text.startIndex
    while index < text.endIndex {
        let c = text[index]
        if c == "\"" { quoted.toggle() }
        if c == ",", !quoted { return index }
        index = text.index(after: index)
    }
    return nil
}

/// A playlist line to write: the song's length, who and what, and where.
public struct M3uLine: Equatable, Sendable {
    public var seconds: Int
    public var artist: String
    public var title: String
    public var location: String

    public init(seconds: Int, artist: String, title: String, location: String) {
        self.seconds = seconds
        self.artist = artist
        self.title = title
        self.location = location
    }
}

/// Writes an M3U8 playlist: the header, then an #EXTINF line and a location for each song.
public func writeM3u(_ lines: [M3uLine]) -> String {
    var out = "#EXTM3U\n"
    for song in lines {
        let who = song.artist.oneLine
        let what = song.title.oneLine
        out += "#EXTINF:\(song.seconds > 0 ? song.seconds : -1),"
        out += who.isEmpty ? what : "\(who) - \(what)"
        out += "\n" + song.location.oneLine + "\n"
    }
    return out
}

/// What a playlist file points at when a song has no path known: the artist and title.
public func fallbackLocation(artist: String, title: String) -> String {
    artist.trimmingCharacters(in: .whitespaces).isEmpty ? title.oneLine : "\(artist.oneLine) - \(title.oneLine)"
}

/// The folders and file name a location names, whatever its slashes. "." and ".." and a drive
/// letter are dropped.
public func pathParts(_ location: String) -> [String] {
    var path = location
    if let scheme = location.range(of: "://") {
        let encoded = location.replacingOccurrences(of: " ", with: "%20")
        if let url = URLComponents(string: encoded) {
            let raw = url.percentEncodedPath
            path = raw.replacingOccurrences(of: "+", with: "%2B").removingPercentEncoding ?? raw
        } else {
            path = String(location[scheme.upperBound...])
        }
    }
    return path.split(whereSeparator: { $0 == "/" || $0 == "\\" }).map(String.init).filter { part in
        !part.isEmpty && part != "." && part != ".." && !(part.count == 2 && part.last == ":")
    }
}

/// A file's name without its folder or its ending, like "01 Nightcall".
public func baseName(_ location: String) -> String {
    let last = pathParts(location).last ?? ""
    let stem = last.lastIndex(of: ".").map { String(last[..<$0]) } ?? last
    return stem.trimmingCharacters(in: .whitespaces)
}

/// The songs a playlist file named that the library has, in order, and the entries it could not
/// find.
public struct M3uMatch: Equatable, Sendable {
    public var trackIds: [String]
    public var missed: [M3uEntry]
}

/// A library song as the matching sees it: its id, title, artist and length.
public struct M3uSong: Equatable, Sendable {
    public var id: String
    public var title: String
    public var artist: String
    public var durationMs: Int64

    public init(_ id: String, _ title: String, _ artist: String, _ durationMs: Int64) {
        self.id = id
        self.title = title
        self.artist = artist
        self.durationMs = durationMs
    }
}

/// Lengths further apart than this are different recordings.
private let sameLengthMs: Int64 = 10_000

/// Leading track numbers on a file name, like "01 ", "01 - " or "1. ".
private let trackNumber = try! NSRegularExpression(pattern: #"^\d{1,3}\s*[-.)_]?\s+"#)

/// Finds each playlist entry in the library, trying in turn: the file (a song whose path ends
/// the same way, from `paths`), the #EXTINF artist and title (with the length when both are
/// known), then the file's own name as a title or as "Artist - Title".
public func matchM3u(_ entries: [M3uEntry], library: [M3uSong], paths: [String: String]) -> M3uMatch {
    var byId: [String: M3uSong] = [:]
    for song in library { byId[song.id] = song }
    var byFileName: [String: [(String, [String])]] = [:]
    for (id, path) in paths.sorted(by: { $0.key < $1.key }) where byId[id] != nil {
        let parts = pathParts(path).map { $0.lowercased() }
        guard let name = parts.last else { continue }
        byFileName[name, default: []].append((id, parts))
    }
    // Paths keep the order the library gave them, so a tie goes to the first.
    for (name, list) in byFileName {
        byFileName[name] = list.sorted { a, b in
            (library.firstIndex { $0.id == a.0 } ?? 0) < (library.firstIndex { $0.id == b.0 } ?? 0)
        }
    }
    var byTitle: [String: [M3uSong]] = [:]
    for track in library {
        for key in titleKeys(track.title) { byTitle[key, default: []].append(track) }
    }
    var ids: [String] = []
    var missed: [M3uEntry] = []
    for entry in entries {
        let found = byPath(entry, byFileName)
            ?? entry.title.flatMap { byTitleAndArtist($0, entry.artist, Int64(entry.seconds ?? 0) * 1_000, byTitle) }
            ?? byFileNameAsTitle(entry, byTitle)
        if let found { ids.append(found) } else { missed.append(entry) }
    }
    return M3uMatch(trackIds: ids, missed: missed)
}

private func byPath(_ entry: M3uEntry, _ byFileName: [String: [(String, [String])]]) -> String? {
    let parts = pathParts(entry.location).map { $0.lowercased() }
    guard let last = parts.last, let candidates = byFileName[last], !candidates.isEmpty else { return nil }
    var best = candidates[0]
    var bestShared = sharedEnding(parts, best.1)
    for candidate in candidates.dropFirst() {
        let shared = sharedEnding(parts, candidate.1)
        if shared > bestShared {
            best = candidate
            bestShared = shared
        }
    }
    return best.0
}

private func sharedEnding(_ a: [String], _ b: [String]) -> Int {
    var n = 0
    while n < a.count, n < b.count, a[a.count - 1 - n] == b[b.count - 1 - n] { n += 1 }
    return n
}

/// A library song with this title, by this artist when one is given, and of about this length
/// when it is known. Without an artist, a title only counts when it points at one song.
private func byTitleAndArtist(_ title: String, _ artist: String?, _ lengthMs: Int64, _ byTitle: [String: [M3uSong]]) -> String? {
    let versions = versionOf(title)
    var seen = Set<String>()
    let candidates = titleKeys(title).flatMap { byTitle[$0] ?? [] }
        .filter { seen.insert($0.id).inserted }
        .filter { versionOf($0.title) == versions }
        .filter { lengthMs <= 0 || $0.durationMs <= 0 || abs(lengthMs - $0.durationMs) <= sameLengthMs }
    if let artist, !artist.trimmingCharacters(in: .whitespaces).isEmpty {
        return candidates.first { sameArtist(artist, $0.artist) && SongIdentity.sameTitle(title, $0.title).isSame }?.id
            ?? candidates.first { sameArtist(artist, $0.artist) }?.id
    }
    return candidates.count == 1 ? candidates[0].id : nil
}

private func byFileNameAsTitle(_ entry: M3uEntry, _ byTitle: [String: [M3uSong]]) -> String? {
    var name = baseName(entry.location).replacingOccurrences(of: "_", with: " ")
    name = trackNumber.stringByReplacingMatches(in: name, range: NSRange(name.startIndex..., in: name), withTemplate: "")
        .trimmingCharacters(in: .whitespaces)
    if name.isEmpty { return nil }
    let lengthMs = Int64(entry.seconds ?? 0) * 1_000
    if let split = name.range(of: " - "), split.lowerBound > name.startIndex {
        let artist = String(name[..<split.lowerBound]).trimmingCharacters(in: .whitespaces)
        let title = String(name[split.upperBound...]).trimmingCharacters(in: .whitespaces)
        if let found = byTitleAndArtist(title, artist, lengthMs, byTitle) { return found }
    }
    return byTitleAndArtist(name, entry.artist, lengthMs, byTitle)
}

/// How an import went: the playlist made, how many of the file's songs were found, and the
/// lines that were not.
public struct ImportReport: Equatable, Sendable {
    public var name: String
    public var matched: Int
    public var total: Int
    public var missed: [String]

    public init(_ name: String, _ matched: Int, _ total: Int, _ missed: [String]) {
        self.name = name
        self.matched = matched
        self.total = total
        self.missed = missed
    }
}

private let refused = try! NSRegularExpression(pattern: #"[\\/:*?"<>|\x00-\x1F]"#)

/// A file name for a playlist, without characters file systems refuse.
public func playlistFileName(_ name: String) -> String {
    let cleaned = refused.stringByReplacingMatches(in: name, range: NSRange(name.startIndex..., in: name), withTemplate: " ")
        .trimmingCharacters(in: .whitespaces)
    return (cleaned.isEmpty ? "Playlist" : cleaned) + ".m3u"
}

/// A playlist named after the file it came from, like "Road trip" for "Road trip.m3u8".
public func playlistNameOf(_ fileName: String) -> String {
    var name = fileName
    if let slash = name.lastIndex(of: "/") { name = String(name[name.index(after: slash)...]) }
    if let slash = name.lastIndex(of: "\\") { name = String(name[name.index(after: slash)...]) }
    if let dot = name.lastIndex(of: ".") { name = String(name[..<dot]) }
    name = name.trimmingCharacters(in: .whitespaces)
    return name.isEmpty ? "Imported playlist" : name
}

/// The largest playlist file read.
public let playlistFileLimit = 8 * 1024 * 1024

/// A playlist file's text: UTF-8 when it reads as UTF-8, otherwise Windows' Western encoding.
public func playlistText(_ bytes: Data) -> String {
    if let text = String(data: bytes, encoding: .utf8) { return text }
    return String(data: bytes, encoding: .windowsCP1252) ?? String(decoding: bytes, as: UTF8.self)
}
