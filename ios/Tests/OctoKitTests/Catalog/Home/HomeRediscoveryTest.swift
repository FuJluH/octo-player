import Foundation
import Testing
@testable import OctoKit

/// Home's rediscovery shelves read from the phone's albums and plays.
@Suite struct HomeRediscoveryTest {
    private let day: Int64 = 24 * 60 * 60 * 1000
    private var now: Int64 { 1_000 * day }

    private func track(_ id: String, _ albumId: String) -> LibraryTrack {
        LibraryTrack(id: id, sourceId: "device", nativeId: id, title: id, searchKey: id, sortKey: id, artist: "", artistId: "",
                     album: "", albumId: albumId, durationMs: 0, addedAt: 0)
    }

    private func album(_ id: String, _ songs: Int, addedDaysAgo: Int64 = 0) -> LibraryAlbum {
        LibraryAlbum(id: id, sourceId: "device", nativeId: id, title: id, searchKey: id, sortKey: id, artist: "", artistId: "",
                     songCount: songs, durationMs: 0, addedAt: now - addedDaysAgo * day)
    }

    private func played(_ id: String, _ albumId: String, _ plays: Int, _ daysAgo: Int64) -> PlayedTrack {
        PlayedTrack(track: track(id, albumId), plays: plays, lastPlayedAt: now - daysAgo * day)
    }

    @Test func theSharedShelvesReadThePhonesAlbumsAndPlays() {
        let albums = [album("full", 2), album("half", 3), album("old", 1), album("new", 5, addedDaysAgo: 1), album("older", 5, addedDaysAgo: 50)]
        let plays = [
            played("f1", "full", 3, 2), played("f2", "full", 1, 3),
            played("h1", "half", 2, 10),
            played("o1", "old", 9, 400),
        ]
        let shelves = homeRediscovery(albums, played: plays, now: now)
        #expect(shelves.notPlayedLately.map(\.id) == ["old"])
        #expect(shelves.neverFinished.map(\.id) == ["half"])
        #expect(shelves.neverPlayed.map(\.id) == ["new", "older"])
    }

    @Test func aSongListedTwiceCountsOnce() {
        let albums = [album("a", 2)]
        let plays = [played("s1", "a", 1, 1), played("s1", "a", 1, 1)]
        #expect(albumListening(albums, played: plays)(albums[0]).playedSongs == 1)
    }
}
