import Foundation
@testable import OctoKit

/// A server song with every field a filter reads, dates as the server writes them.
struct QueryTestSong: Sendable, Hashable {
    var id: String
    var title: String
    var album: String?
    var albumId: String?
    var artist: String?
    var displayArtist: String?
    var year: Int?
    var duration = 0
    var suffix: String?
    var bitRate: Int?
    var bitDepth: Int?
    var genre: String?
    var genres: [String] = []
    var created: String?
    var played: String?
    var playCount: Int64?
    var userRating: Int?
    var starred: String?
    var bpm: Int?
    var track: Int?
    var discNumber: Int?
    var displayComposer: String?
    var displayAlbumArtist: String?
    var albumArtists: [String] = []

    init(_ id: String, _ title: String, album: String? = nil, albumId: String? = nil, artist: String? = nil, year: Int? = nil,
         duration: Int = 0, suffix: String? = nil, bitRate: Int? = nil, bitDepth: Int? = nil, genre: String? = nil,
         genres: [String] = [], created: String? = nil, played: String? = nil, playCount: Int64? = nil, userRating: Int? = nil,
         starred: String? = nil, bpm: Int? = nil, track: Int? = nil, displayComposer: String? = nil, albumArtists: [String] = []) {
        self.id = id
        self.title = title
        self.album = album
        self.albumId = albumId
        self.artist = artist
        self.year = year
        self.duration = duration
        self.suffix = suffix
        self.bitRate = bitRate
        self.bitDepth = bitDepth
        self.genre = genre
        self.genres = genres
        self.created = created
        self.played = played
        self.playCount = playCount
        self.userRating = userRating
        self.starred = starred
        self.bpm = bpm
        self.track = track
        self.displayComposer = displayComposer
        self.albumArtists = albumArtists
    }
}

/// Reads a `QueryTestSong` the way a server's songs are read.
struct QueryTestFields: SongFields, Sendable {
    func id(_ song: QueryTestSong) -> String { song.id }
    func title(_ song: QueryTestSong) -> String { song.title }
    func artist(_ song: QueryTestSong) -> String? { song.artist ?? song.displayArtist }
    func album(_ song: QueryTestSong) -> String? { song.album }
    func albumId(_ song: QueryTestSong) -> String? { song.albumId }
    func albumArtist(_ song: QueryTestSong) -> String? { song.displayAlbumArtist ?? song.albumArtists.first }

    func genres(_ song: QueryTestSong) -> [String] {
        let one = song.genre.flatMap { $0.allSatisfy(\.isWhitespace) ? nil : $0 }
        if song.genres.isEmpty { return one.map { [$0] } ?? [] }
        guard let one, !song.genres.contains(one) else { return song.genres }
        return song.genres + [one]
    }

    func composer(_ song: QueryTestSong) -> String? { song.displayComposer }
    func year(_ song: QueryTestSong) -> Int? { song.year }
    func disc(_ song: QueryTestSong) -> Int? { song.discNumber }
    func track(_ song: QueryTestSong) -> Int? { song.track }
    func addedAt(_ song: QueryTestSong) -> Int64? { quickTime(song.created) }
    func lastPlayedAt(_ song: QueryTestSong) -> Int64? { quickTime(song.played) }
    func plays(_ song: QueryTestSong) -> Int64 { song.playCount ?? 0 }
    func rating(_ song: QueryTestSong) -> Int { song.userRating ?? 0 }
    func favorite(_ song: QueryTestSong) -> Bool { song.starred != nil }
    func likedAt(_ song: QueryTestSong) -> Int64? { quickTime(song.starred) }
    func seconds(_ song: QueryTestSong) -> Int { song.duration }

    func format(_ song: QueryTestSong) -> String? {
        guard let suffix = song.suffix?.lowercased(), !suffix.allSatisfy(\.isWhitespace) else { return nil }
        return suffix
    }

    func lossless(_ song: QueryTestSong) -> Bool { isLosslessFormat(song.suffix, bitDepth: song.bitDepth) }
    func bitRate(_ song: QueryTestSong) -> Int? { song.bitRate }
    func bpm(_ song: QueryTestSong) -> Int? { song.bpm }
}

/// The moment the query tests run at: 2026-09-28T12:00:00Z.
let queryTestNow: Int64 = epochMs("2026-09-28T12:00:00Z") ?? 0

/// A moment as a server writes it: "2026-09-25T12:00:00Z", with milliseconds when it has some.
func queryTestTime(_ ms: Int64) -> String {
    let seconds = floorDiv(ms, 1_000)
    let millis = ms - seconds * 1_000
    let days = floorDiv(seconds, 86_400)
    let inDay = seconds - days * 86_400
    let z = days + 719_468
    let era = (z >= 0 ? z : z - 146_096) / 146_097
    let doe = z - era * 146_097
    let yoe = (doe - doe / 1_460 + doe / 36_524 - doe / 146_096) / 365
    let doy = doe - (365 * yoe + yoe / 4 - yoe / 100)
    let mp = (5 * doy + 2) / 153
    let day = doy - (153 * mp + 2) / 5 + 1
    let month = mp < 10 ? mp + 3 : mp - 9
    let year = yoe + era * 400 + (month <= 2 ? 1 : 0)
    func pad(_ n: Int64, _ width: Int) -> String {
        let text = String(n)
        return String(repeating: "0", count: max(0, width - text.count)) + text
    }
    let time = "\(pad(inDay / 3_600, 2)):\(pad(inDay % 3_600 / 60, 2)):\(pad(inDay % 60, 2))"
    return "\(pad(year, 4))-\(pad(month, 2))-\(pad(day, 2))T\(time)" + (millis == 0 ? "" : ".\(pad(millis, 3))") + "Z"
}

/// The moment `days` days before the tests' now, as a server writes it.
func queryTestDaysAgo(_ days: Int64) -> String { queryTestTime(queryTestNow - days * 86_400_000) }
