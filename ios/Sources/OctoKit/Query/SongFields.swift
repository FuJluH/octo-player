import Foundation

/// What a filter, and a query's order, can read from a song. Each kind of song is read through
/// its own fields. A value the song does not carry is nil (or 0, or empty), and a filter on it
/// matches nothing.
public protocol SongFields<Item> {
    associatedtype Item

    func id(_ song: Item) -> String
    func title(_ song: Item) -> String
    func artist(_ song: Item) -> String?
    func album(_ song: Item) -> String?
    func albumId(_ song: Item) -> String?
    func albumArtist(_ song: Item) -> String?
    /// Every genre the song is filed under.
    func genres(_ song: Item) -> [String]
    func composer(_ song: Item) -> String?
    func year(_ song: Item) -> Int?
    func disc(_ song: Item) -> Int?
    func track(_ song: Item) -> Int?
    /// Milliseconds since 1970.
    func addedAt(_ song: Item) -> Int64?
    /// Milliseconds since 1970.
    func lastPlayedAt(_ song: Item) -> Int64?
    func plays(_ song: Item) -> Int64
    /// 1 to 5 stars, 0 for none.
    func rating(_ song: Item) -> Int
    func favorite(_ song: Item) -> Bool
    func likedAt(_ song: Item) -> Int64?
    func seconds(_ song: Item) -> Int
    /// The file's kind in lower case, like "flac" or "mp3".
    func format(_ song: Item) -> String?
    func lossless(_ song: Item) -> Bool
    /// Kilobits per second.
    func bitRate(_ song: Item) -> Int?
    func bpm(_ song: Item) -> Int?
}

/// Formats that keep every bit of the recording.
private let losslessFormats: Set<String> = ["flac", "alac", "wav", "wave", "aiff", "aif", "aifc", "pcm", "ape", "wv", "dsf", "dff",
                                            "tta"]

/// Whether a file of this kind is lossless. An m4a or mp4 is Apple Lossless when the server gives
/// it a bit depth, and AAC otherwise.
public func isLosslessFormat(_ format: String?, bitDepth: Int? = nil) -> Bool {
    guard let kind = format?.lowercased() else { return false }
    if kind == "m4a" || kind == "mp4" { return (bitDepth ?? 0) > 0 }
    return losslessFormats.contains(kind)
}

/// Whether a FLAC could be looked for to take this song's place: a library file (not one the
/// server only found online) of a kind that loses detail. A song whose kind the server never said
/// is left alone, since it may well be lossless already.
public func isUpgradable(_ song: Song) -> Bool {
    guard !song.isExternal, let suffix = song.suffix, !LibraryQuery.isBlank(suffix) else { return false }
    return !isLosslessFormat(suffix, bitDepth: song.bitDepth)
}

/// A server's songs as `Song` carries them. It has no date added or played, play count, rating,
/// album artist, composer or BPM, so a filter on those reads them as missing.
public struct SubsonicSongFields: SongFields, Sendable {
    public init() {}

    public func id(_ song: Song) -> String { song.id }
    public func title(_ song: Song) -> String { song.title }
    public func artist(_ song: Song) -> String? { song.artist ?? song.displayArtist }
    public func album(_ song: Song) -> String? { song.album }
    public func albumId(_ song: Song) -> String? { song.albumId }
    public func albumArtist(_ song: Song) -> String? { nil }

    public func genres(_ song: Song) -> [String] {
        guard let genre = song.genre, !LibraryQuery.isBlank(genre) else { return [] }
        return [genre]
    }

    public func composer(_ song: Song) -> String? { nil }
    public func year(_ song: Song) -> Int? { song.year }
    public func disc(_ song: Song) -> Int? { song.discNumber }
    public func track(_ song: Song) -> Int? { song.track }
    public func addedAt(_ song: Song) -> Int64? { nil }
    public func lastPlayedAt(_ song: Song) -> Int64? { nil }
    public func plays(_ song: Song) -> Int64 { 0 }
    public func rating(_ song: Song) -> Int { 0 }
    public func favorite(_ song: Song) -> Bool { song.starred != nil }
    public func likedAt(_ song: Song) -> Int64? { quickTime(song.starred) }
    public func seconds(_ song: Song) -> Int { song.duration }

    public func format(_ song: Song) -> String? {
        guard let suffix = song.suffix?.lowercased(), !LibraryQuery.isBlank(suffix) else { return nil }
        return suffix
    }

    public func lossless(_ song: Song) -> Bool { isLosslessFormat(song.suffix, bitDepth: song.bitDepth) }
    public func bitRate(_ song: Song) -> Int? { song.bitRate }
    public func bpm(_ song: Song) -> Int? { nil }
}

extension LibraryQuery {
    /// The server's songs this query picks, in its order, at most its limit. `now` is the time in
    /// milliseconds, for rules like "in the last 30 days".
    public func apply(_ songs: [Song], now: Int64) -> [Song] { select(songs, now: now, fields: SubsonicSongFields()) }
}

/// A server's time, read fast when it is the usual UTC form ("2026-09-28T10:00:00Z", with or
/// without a fraction of a second), else as `epochMs` reads it.
public func quickTime(_ text: String?) -> Int64? {
    guard let text else { return nil }
    if text.utf8.count < 20 { return epochMs(text) }
    var copy = text
    let quick: Int64? = copy.withUTF8 { bytes in
        func digits(_ from: Int, _ count: Int) -> Int64 {
            var n: Int64 = 0
            for i in from..<(from + count) {
                let d = Int64(bytes[i]) - 48
                if d < 0 || d > 9 { return -1 }
                n = n * 10 + d
            }
            return n
        }
        guard bytes[4] == UInt8(ascii: "-"), bytes[7] == UInt8(ascii: "-"), bytes[10] == UInt8(ascii: "T"),
              bytes[13] == UInt8(ascii: ":"), bytes[16] == UInt8(ascii: ":") else { return nil }
        let year = digits(0, 4)
        let month = digits(5, 2)
        let day = digits(8, 2)
        let hour = digits(11, 2)
        let minute = digits(14, 2)
        let second = digits(17, 2)
        guard year >= 0, (1...12).contains(month), day >= 1, day <= quickDaysIn(month, year), (0...23).contains(hour),
              (0...59).contains(minute), (0...59).contains(second) else { return nil }
        var at = 19
        var millis: Int64 = 0
        if bytes[at] == UInt8(ascii: ".") {
            at += 1
            var scale: Int64 = 100
            while at < bytes.count, bytes[at] >= 48, bytes[at] <= 57 {
                millis += (Int64(bytes[at]) - 48) * scale
                scale /= 10
                at += 1
            }
        }
        guard at == bytes.count - 1, bytes[at] == UInt8(ascii: "Z") else { return nil }
        let days = daysFromCivil(year, month, day)
        return days * 86_400_000 + hour * 3_600_000 + minute * 60_000 + second * 1_000 + millis
    }
    return quick ?? epochMs(text)
}

private func quickDaysIn(_ month: Int64, _ year: Int64) -> Int64 {
    switch month {
    case 2: (year % 4 == 0 && year % 100 != 0) || year % 400 == 0 ? 29 : 28
    case 4, 6, 9, 11: 30
    default: 31
    }
}

/// The songs of `items` read by their places in it, so a query can pick places rather than
/// songs: a playlist filtered on screen still knows which of its entries each row is.
public struct PlacedSongFields<Base: SongFields>: SongFields {
    public let items: [Base.Item]
    public let base: Base

    public init(items: [Base.Item], base: Base) {
        self.items = items
        self.base = base
    }

    public func id(_ song: Int) -> String { base.id(items[song]) }
    public func title(_ song: Int) -> String { base.title(items[song]) }
    public func artist(_ song: Int) -> String? { base.artist(items[song]) }
    public func album(_ song: Int) -> String? { base.album(items[song]) }
    public func albumId(_ song: Int) -> String? { base.albumId(items[song]) }
    public func albumArtist(_ song: Int) -> String? { base.albumArtist(items[song]) }
    public func genres(_ song: Int) -> [String] { base.genres(items[song]) }
    public func composer(_ song: Int) -> String? { base.composer(items[song]) }
    public func year(_ song: Int) -> Int? { base.year(items[song]) }
    public func disc(_ song: Int) -> Int? { base.disc(items[song]) }
    public func track(_ song: Int) -> Int? { base.track(items[song]) }
    public func addedAt(_ song: Int) -> Int64? { base.addedAt(items[song]) }
    public func lastPlayedAt(_ song: Int) -> Int64? { base.lastPlayedAt(items[song]) }
    public func plays(_ song: Int) -> Int64 { base.plays(items[song]) }
    public func rating(_ song: Int) -> Int { base.rating(items[song]) }
    public func favorite(_ song: Int) -> Bool { base.favorite(items[song]) }
    public func likedAt(_ song: Int) -> Int64? { base.likedAt(items[song]) }
    public func seconds(_ song: Int) -> Int { base.seconds(items[song]) }
    public func format(_ song: Int) -> String? { base.format(items[song]) }
    public func lossless(_ song: Int) -> Bool { base.lossless(items[song]) }
    public func bitRate(_ song: Int) -> Int? { base.bitRate(items[song]) }
    public func bpm(_ song: Int) -> Int? { base.bpm(items[song]) }
}

extension PlacedSongFields: Sendable where Base: Sendable, Base.Item: Sendable {}

extension SongFields {
    /// These fields read through the places in `items`.
    public func at(_ items: [Item]) -> PlacedSongFields<Self> { PlacedSongFields(items: items, base: self) }
}

extension LibraryQuery {
    /// The places in `items` this query picks, in its order. The ids a sort breaks ties by are the
    /// items' own, so a song twice in a list sorts beside itself.
    public func places<F: SongFields>(_ items: [F.Item], now: Int64, fields: F) -> [Int] {
        select(Array(items.indices), now: now, fields: fields.at(items))
    }
}
