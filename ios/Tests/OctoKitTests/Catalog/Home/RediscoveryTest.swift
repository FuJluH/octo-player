import Foundation
import Testing
@testable import OctoKit

@Suite struct RediscoveryTest {
    private let now: Int64 = epochMs("2026-09-28T12:00:00Z") ?? 0
    private let day: Int64 = 24 * 60 * 60 * 1000

    private func album(_ id: String, songs: Int = 10, played: Int = 0, plays: Int64? = nil, daysAgo: Int64? = nil,
                       addedDaysAgo: Int64? = nil) -> AlbumListening {
        AlbumListening(id: id, songs: songs, playedSongs: played, plays: plays ?? Int64(played), lastPlayed: daysAgo.map { now - $0 * day },
                       added: addedDaysAgo.map { now - $0 * day })
    }

    private func ids(_ list: [AlbumListening]) -> [String] { list.map(\.id) }

    // Not played in 6 months

    @Test func onlyAlbumsPlayedBeforeButNotInSixMonthsAreQuiet() {
        let albums = [
            album("recent", played: 10, daysAgo: 3),
            album("old", played: 10, plays: 4, daysAgo: 200),
            album("never"),
            album("justInside", played: 10, daysAgo: 179),
            album("loved", played: 10, plays: 40, daysAgo: 400),
        ]
        #expect(ids(notPlayedLately(albums, of: { $0 }, now: now)) == ["loved", "old"])
    }

    @Test func quietAlbumsPlayedAsOftenGoLongestAgoFirst() {
        let albums = [album("b", played: 5, daysAgo: 300), album("a", played: 5, daysAgo: 500), album("c", played: 5, daysAgo: 300)]
        #expect(ids(notPlayedLately(albums, of: { $0 }, now: now)) == ["a", "b", "c"])
    }

    // Albums you never finished

    @Test func anAlbumIsUnfinishedWhenSomeButNotAllOfItsSongsWerePlayed() {
        let albums = [
            album("done", songs: 8, played: 8, daysAgo: 1),
            album("half", songs: 8, played: 4, daysAgo: 10),
            album("one", songs: 8, played: 1, daysAgo: 2),
            album("none", songs: 8),
            album("single", songs: 1, played: 1, daysAgo: 1),
        ]
        #expect(ids(neverFinished(albums, of: { $0 })) == ["one", "half"], "most recently played first")
    }

    // Unplayed albums

    @Test func unplayedAlbumsComeNewestAddedFirst() {
        let albums = [
            album("old", addedDaysAgo: 300),
            album("played", played: 2, daysAgo: 1, addedDaysAgo: 1),
            album("new", addedDaysAgo: 2),
            album("undated"),
            album("countedOnly", plays: 3),
        ]
        #expect(ids(neverPlayed(albums, of: { $0 })) == ["new", "old", "undated"])
    }

    // Most played

    @Test func mostPlayedLeavesOutTheUnplayedAndBreaksTiesByTheLatestPlay() {
        let albums = [album("a", played: 3, plays: 9, daysAgo: 20), album("b", plays: 0), album("c", played: 3, plays: 9, daysAgo: 2),
                      album("d", played: 1, plays: 30, daysAgo: 90)]
        #expect(ids(mostPlayedAlbums(albums, of: { $0 })) == ["d", "c", "a"])
    }

    // The shelves together

    @Test func anAlbumShowsOnOneShelfOnlyAndEachShelfKeepsToItsLimit() {
        let albums = [
            album("oldHalf", songs: 10, played: 5, daysAgo: 300),
            album("newHalf", songs: 10, played: 5, daysAgo: 5),
            album("oldFull", songs: 10, played: 10, daysAgo: 250),
            album("u1", addedDaysAgo: 1),
            album("u2", addedDaysAgo: 2),
            album("u3", addedDaysAgo: 3),
        ]
        let shelves = rediscovery(albums, of: { $0 }, now: now, limit: 2)
        #expect(ids(shelves.notPlayedLately) == ["oldFull", "oldHalf"], "the most played first")
        #expect(ids(shelves.neverFinished) == ["newHalf"], "the old unfinished album is already on the shelf above")
        #expect(ids(shelves.neverPlayed) == ["u1", "u2"])
    }

    @Test func anEmptyLibraryHasNoShelves() {
        #expect(rediscovery([AlbumListening](), of: { $0 }, now: now, limit: 20).isEmpty)
    }

    @Test func theSameLibraryAlwaysGivesTheSameShelves() {
        let albums = (1...40).map { i in
            album("a\(i)", songs: 10, played: i % 11, plays: Int64(i % 7), daysAgo: i % 11 == 0 ? nil : Int64(i) * 13,
                  addedDaysAgo: (Int64(i) * 3) % 17)
        }
        let first = rediscovery(albums, of: { $0 }, now: now, limit: 12)
        for _ in 0..<3 { #expect(rediscovery(albums.shuffled(), of: { $0 }, now: now, limit: 12) == first) }
    }

    // From a Subsonic library

    @Test func listeningIsReadFromTheSongs() throws {
        let albums = [
            ServerAlbum(id: "a1", songCount: 99, created: "2026-01-02T00:00:00Z"),
            ServerAlbum(id: "a2", songCount: 5, played: "2026-03-01T00:00:00Z", playCount: 7),
        ]
        let songs = [
            ServerSong(id: "s1", albumId: "a1", played: "2026-09-01T10:00:00Z", playCount: 3),
            ServerSong(id: "s2", albumId: "a1", playCount: 0),
            ServerSong(id: "s3", albumId: "a1", played: "2026-09-20T10:00:00Z"),
            ServerSong(id: "s4", albumId: nil, playCount: 50),
        ]
        let listening = albumListening(albums, songs)
        let a1 = try #require(listening["a1"])
        #expect(a1.songs == 3, "the songs listed, not the album's own count")
        #expect(a1.playedSongs == 2)
        #expect(a1.plays == 3)
        #expect(a1.lastPlayed == epochMs("2026-09-20T10:00:00Z"))
        #expect(a1.added == epochMs("2026-01-02T00:00:00Z"))
        let a2 = try #require(listening["a2"])
        #expect(a2.songs == 5, "no songs listed: the album's own counts")
        #expect(a2.plays == 7)
        #expect(a2.lastPlayed == epochMs("2026-03-01T00:00:00Z"))
        #expect(a2.played)
    }
}
