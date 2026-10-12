import Foundation

/// Octo lists a song it found online as exactly three minutes long when it does not know the real
/// length yet.
private let guessedSeconds = 180

/// Lengths further apart than this are different recordings. Looser than the lyrics match, since a
/// library copy and a server's copy of one recording can be cut a little differently.
private let sameLengthS = 10

private let withinTenSeconds = SongMatchOptions(lengthToleranceSeconds: sameLengthS)

private let extras = try! NSRegularExpression(pattern: #"\s*[(\[][^)\]]*[)\]]"#)

/// The length the server gave, or zero when it only guessed.
public func knownLengthMs(_ song: Song) -> Int64 {
    song.duration <= 0 || song.duration == guessedSeconds ? 0 : Int64(song.duration) * 1_000
}

/// The keys a title is looked up by in the library's search keys: as written, without bracketed
/// extras like "(feat. X)" or "[Remastered]", and as the title a person would say ("Song" for
/// "01 - Song - Remastered"). Only a first pass: whatever they find is still compared song by song.
public func titleKeys(_ title: String) -> [String] {
    let range = NSRange(title.startIndex..., in: title)
    let bare = extras.stringByReplacingMatches(in: title, range: range, withTemplate: "").trimmingCharacters(in: .whitespacesAndNewlines)
    var keys: [String] = []
    for key in [searchKey(title), searchKey(bare), searchKey(SongIdentity.parseTitle(title).core)] where !key.isEmpty && !keys.contains(key) {
        keys.append(key)
    }
    return keys
}

/// The two credits share an artist and do not disagree about the guests: "Drake feat. Rihanna" is
/// "Drake", and "Ye (侃爷)" is "Kanye West", but "A feat. B" is not "A feat. C".
public func sameArtist(_ a: String, _ b: String) -> Bool { SongIdentity.artistsAgree(a, b) }

/// Which kind of recording a title names: its version markers that make another recording
/// ("live", "remix"), not the ones that never do ("remaster", "explicit").
public func versionOf(_ title: String) -> Set<String> { SongIdentity.distinctVersions(SongIdentity.parseTitle(title)) }

/// The same song by the same artist, and the same kind of recording. Lengths only count when both
/// are known. ISRCs, when both sides have them and share one, make it the same recording whatever
/// the titles say.
public func sameSong(_ title: String, _ artist: String, _ lengthMs: Int64, _ otherTitle: String, _ otherArtist: String,
                     _ otherLengthMs: Int64, isrcs: [String] = [], otherIsrcs: [String] = []) -> Bool {
    SongIdentity.same(
        SongRef(title: title, artist: artist, seconds: secondsOf(lengthMs), isrcs: isrcs),
        SongRef(title: otherTitle, artist: otherArtist, seconds: secondsOf(otherLengthMs), isrcs: otherIsrcs),
        options: withinTenSeconds
    ).isSame
}

/// The same recording by the same artist, lengths not compared.
public func sameRecording(_ titleA: String, _ artistA: String, _ titleB: String, _ artistB: String,
                          isrcsA: [String] = [], isrcsB: [String] = []) -> Bool {
    SongIdentity.same(SongRef(title: titleA, artist: artistA, isrcs: isrcsA), SongRef(title: titleB, artist: artistB, isrcs: isrcsB),
                      options: .AnyLength).isSame
}

/// The same song by the same artist in any version: a live take or a remix counts too.
public func sameSongAnyVersion(_ titleA: String, _ artistA: String, _ titleB: String, _ artistB: String,
                               isrcsA: [String] = [], isrcsB: [String] = []) -> Bool {
    let match = SongIdentity.same(SongRef(title: titleA, artist: artistA, isrcs: isrcsA), SongRef(title: titleB, artist: artistB, isrcs: isrcsB),
                                  options: .AnyLength)
    return match.verdict != .different
}

private func secondsOf(_ ms: Int64) -> Double? { ms > 0 ? Double(ms) / 1_000 : nil }

/// Songs by every key their titles can agree on, so a song is only compared with the few whose
/// titles might be its own. What it finds keeps the list's order.
public final class TitleIndex<T> {
    private let items: [T]
    private var byKey: [String: [Int]] = [:]

    public init(_ items: [T], title: (T) -> String, artist: (T) -> String) {
        self.items = items
        for (index, item) in items.enumerated() {
            for key in SongIdentity.titleLookupKeys(title(item), artist(item)) { byKey[key, default: []].append(index) }
        }
    }

    public func candidates(_ title: String, _ artist: String) -> [T] {
        var seen = Set<Int>()
        let found = SongIdentity.titleLookupKeys(title, artist).flatMap { byKey[$0] ?? [] }.filter { seen.insert($0).inserted }
        return found.sorted().map { items[$0] }
    }
}

/// Songs by every valid ISRC they carry, for the songs a title lookup cannot find: the same
/// recording under a title in another script or language. What it finds keeps the list's order.
public final class IsrcIndex<T> {
    private let items: [T]
    private var byIsrc: [String: [Int]] = [:]

    public init(_ items: [T], isrcs: (T) -> [String]) {
        self.items = items
        for (index, item) in items.enumerated() {
            for isrc in SongIdentity.isrcs(isrcs(item)) { byIsrc[isrc, default: []].append(index) }
        }
    }

    public func candidates(_ isrcs: [String]) -> [T] {
        guard !byIsrc.isEmpty else { return [] }
        var seen = Set<Int>()
        let found = SongIdentity.isrcs(isrcs).flatMap { byIsrc[$0] ?? [] }.filter { seen.insert($0).inserted }
        return found.sorted().map { items[$0] }
    }
}

/// What the player receives for a server song, from its type or its file ending.
public func mimeTypeOf(contentType: String?, suffix: String?) -> String? {
    if let contentType, !contentType.trimmingCharacters(in: .whitespaces).isEmpty { return contentType }
    switch suffix?.lowercased() {
    case "m4a", "mp4", "aac": return "audio/mp4"
    case "mp3": return "audio/mpeg"
    case "flac": return "audio/flac"
    case "ogg", "oga", "opus": return "audio/ogg"
    case "wav": return "audio/wav"
    default: return nil
    }
}
