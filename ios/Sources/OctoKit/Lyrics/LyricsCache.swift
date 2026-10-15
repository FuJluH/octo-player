import Foundation

/// How long "no lyrics" is believed before the sources are asked again.
public let NONE_FOUND_FOR_MS = 24 * 60 * 60 * 1000

/// How long a "none" that may be wrong is believed: one from a server that looks lyrics up
/// itself and answers "none" when its time runs out, or one found while nobody was looking at
/// the lyrics.
public let SHORT_NONE_FOR_MS = 10 * 60 * 1000

/// Raised when the online lookup learns a new way to find synced lyrics, so songs that only got
/// plain ones are asked again once.
public let ONLINE_LOOKUP_VERSION = 4

// The first answers saved once the server ranked a song's own lyrics among its sources: lyrics
// it sent without word timing before that are asked again once, as it may have word-timed ones
// now.
private let SERVER_RANKS_OWN_VERSION = 4

/// How long lyrics from the server without word timing are believed before it is asked again:
/// it may have found word-timed ones since, or had its sources reordered.
public let SERVER_RECHECK_MS = 60 * 60 * 1000

// The online lookup that could take another song's lyrics: it matched a search result by length
// alone. What it found is asked again once.
private let LOOSE_SEARCH_VERSION = 2

/// One song's saved answer: its lyrics, or none, when that was found, and whether the online
/// library was asked.
public struct CachedLyrics: Equatable, Sendable, Codable {
    public var savedAt: Int
    public var lyrics: Lyrics?
    public var askedOnline: Bool
    /// Which online lookup gave this answer; older ones are asked again when they found no
    /// synced lyrics.
    public var lookupVersion: Int
    /// The listener's pick these lyrics came from, or nil when the usual order found them.
    public var pick: String?
    /// A "none" from a server whose lookup may have run out of time.
    public var unsure: Bool
    /// Saved while the lyrics were not on screen, so a "none" is asked again once they are.
    public var away: Bool

    public init(
        savedAt: Int,
        lyrics: Lyrics? = nil,
        askedOnline: Bool = false,
        lookupVersion: Int = 0,
        pick: String? = nil,
        unsure: Bool = false,
        away: Bool = false
    ) {
        self.savedAt = savedAt
        self.lyrics = lyrics
        self.askedOnline = askedOnline
        self.lookupVersion = lookupVersion
        self.pick = pick
        self.unsure = unsure
        self.away = away
    }

    enum CodingKeys: String, CodingKey { case savedAt, lyrics, askedOnline, lookupVersion, pick, unsure, away }

    // A saved answer may leave out any field that has a default; unknown fields are ignored.
    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        savedAt = try c.decode(Int.self, forKey: .savedAt)
        lyrics = try c.decodeIfPresent(Lyrics.self, forKey: .lyrics)
        askedOnline = try c.decodeIfPresent(Bool.self, forKey: .askedOnline) ?? false
        lookupVersion = try c.decodeIfPresent(Int.self, forKey: .lookupVersion) ?? 0
        pick = try c.decodeIfPresent(String.self, forKey: .pick)
        unsure = try c.decodeIfPresent(Bool.self, forKey: .unsure) ?? false
        away = try c.decodeIfPresent(Bool.self, forKey: .away) ?? false
    }

    /// Whether this answer stands for a song whose pick is `current`: picked lyrics stand while
    /// they are the ones picked; the usual answer stands only while nothing is picked, and as
    /// long as `stillGood` says.
    public func standsFor(_ current: String?, now: Int, onlineAllowed: Bool) -> Bool {
        if let current { return pick == current && lyrics != nil }
        return pick == nil && stillGood(now: now, onlineAllowed: onlineAllowed)
    }

    /// Whether a "none" should be asked again now that the lyrics are back on screen: it was
    /// found while they were not.
    public func recheckOnReturn() -> Bool { lyrics == nil && away }

    /// Whether the answer still stands. "None" lasts a day, or a few minutes when it may be
    /// wrong. An answer found without asking online is asked again once online lookups are
    /// allowed, in case synced ones are there. The server's lyrics without word timing last an
    /// hour.
    public func stillGood(now: Int, onlineAllowed: Bool) -> Bool {
        if let lyrics, lyrics.source == .server, !lyrics.instrumental, !lyrics.lines.contains(where: { !$0.words.isEmpty }) {
            if lookupVersion < SERVER_RANKS_OWN_VERSION || now - savedAt >= SERVER_RECHECK_MS { return false }
        }
        if onlineAllowed && !askedOnline && lyrics?.synced != true { return false }
        if onlineAllowed, let lyrics, !lyrics.synced, lookupVersion < ONLINE_LOOKUP_VERSION { return false }
        if onlineAllowed, lyrics?.source == .online, lookupVersion == LOOSE_SEARCH_VERSION { return false }
        return lyrics != nil || now - savedAt < ((unsure || away) ? SHORT_NONE_FOR_MS : NONE_FOUND_FOR_MS)
    }
}

/// Saved lyrics answers, one small JSON file per song in the app's cache folder, keyed by the
/// song's id. The phone may clear the folder when it needs space; the lyrics are then just
/// looked up again.
public final class LyricsCache: @unchecked Sendable {
    private let folder: URL

    public init(_ folder: URL) {
        self.folder = folder
    }

    public func read(_ songId: String) -> CachedLyrics? {
        guard let data = try? Data(contentsOf: fileFor(songId)) else { return nil }
        return try? JSONDecoder().decode(CachedLyrics.self, from: data)
    }

    public func write(_ songId: String, _ entry: CachedLyrics) {
        let files = FileManager.default
        try? files.createDirectory(at: folder, withIntermediateDirectories: true)
        let file = fileFor(songId)
        // Written beside it first, so a reader never sees half a file.
        let next = folder.appendingPathComponent(file.lastPathComponent + ".tmp")
        guard let data = try? JSONEncoder().encode(entry), (try? data.write(to: next)) != nil else { return }
        if (try? files.replaceItemAt(file, withItemAt: next)) == nil {
            try? files.removeItem(at: file)
            try? files.moveItem(at: next, to: file)
        }
    }

    /// Forgets a song's answer, so its lyrics are looked up again.
    public func drop(_ songId: String) {
        try? FileManager.default.removeItem(at: fileFor(songId))
    }

    private func fileFor(_ songId: String) -> URL {
        folder.appendingPathComponent("\(SHA1.hex(songId)).json")
    }
}

/// SHA-1, for naming the saved answers by the song they answer. Written out here so OctoKit
/// has no dependencies and builds the same on iOS and Linux.
enum SHA1 {
    static func hex(_ string: String) -> String {
        digest(Array(string.utf8)).map { String(format: "%02x", $0) }.joined()
    }

    static func digest(_ message: [UInt8]) -> [UInt8] {
        var h: [UInt32] = [0x6745_2301, 0xEFCD_AB89, 0x98BA_DCFE, 0x1032_5476, 0xC3D2_E1F0]
        var bytes = message
        let bitLength = UInt64(message.count) &* 8
        bytes.append(0x80)
        while bytes.count % 64 != 56 { bytes.append(0) }
        for i in (0..<8).reversed() { bytes.append(UInt8(truncatingIfNeeded: bitLength >> (8 * UInt64(i)))) }
        var w = [UInt32](repeating: 0, count: 80)
        for chunk in stride(from: 0, to: bytes.count, by: 64) {
            for i in 0..<16 {
                let j = chunk + i * 4
                w[i] = UInt32(bytes[j]) << 24 | UInt32(bytes[j + 1]) << 16 | UInt32(bytes[j + 2]) << 8 | UInt32(bytes[j + 3])
            }
            for i in 16..<80 {
                let x = w[i - 3] ^ w[i - 8] ^ w[i - 14] ^ w[i - 16]
                w[i] = (x << 1) | (x >> 31)
            }
            var a = h[0], b = h[1], c = h[2], d = h[3], e = h[4]
            for i in 0..<80 {
                let f: UInt32
                let k: UInt32
                switch i {
                case 0..<20:
                    f = (b & c) | (~b & d)
                    k = 0x5A82_7999
                case 20..<40:
                    f = b ^ c ^ d
                    k = 0x6ED9_EBA1
                case 40..<60:
                    f = (b & c) | (b & d) | (c & d)
                    k = 0x8F1B_BCDC
                default:
                    f = b ^ c ^ d
                    k = 0xCA62_C1D6
                }
                let temp = ((a << 5) | (a >> 27)) &+ f &+ e &+ k &+ w[i]
                e = d
                d = c
                c = (b << 30) | (b >> 2)
                b = a
                a = temp
            }
            h[0] = h[0] &+ a
            h[1] = h[1] &+ b
            h[2] = h[2] &+ c
            h[3] = h[3] &+ d
            h[4] = h[4] &+ e
        }
        return h.flatMap { word in (0..<4).map { UInt8(truncatingIfNeeded: word >> (24 - 8 * UInt32($0))) } }
    }
}
