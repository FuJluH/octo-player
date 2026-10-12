import Foundation
import Testing
@testable import OctoKit

@Suite struct PlaysTest {
    private func track(_ id: String) -> LibraryTrack {
        LibraryTrack(id: id, sourceId: "device", nativeId: id, title: id, searchKey: id, sortKey: id, artist: "", artistId: "",
                     album: "", albumId: "", durationMs: 0, addedAt: 0)
    }

    private func album(_ id: String) -> LibraryAlbum {
        LibraryAlbum(id: id, sourceId: "device", nativeId: id, title: id, searchKey: id, sortKey: id, artist: "", artistId: "",
                     songCount: 1, durationMs: 0, addedAt: 0)
    }

    private func played(_ id: String, _ plays: Int, _ at: Int64) -> PlayedTrack { PlayedTrack(track: track(id), plays: plays, lastPlayedAt: at) }

    @Test func albumsComeNewestPlayFirst() {
        let albums = [PlayedAlbum(album: album("a"), lastPlayedAt: 100), PlayedAlbum(album: album("b"), lastPlayedAt: 300),
                      PlayedAlbum(album: album("c"), lastPlayedAt: 200)]
        #expect(byLatestPlay(albums, limit: 20).map(\.id) == ["b", "c", "a"])
    }

    @Test func albumsStopAtTheLimit() {
        let albums = (1...30).map { PlayedAlbum(album: album("a\($0)"), lastPlayedAt: Int64($0)) }
        let shown = byLatestPlay(albums, limit: 20)
        #expect(shown.count == 20)
        #expect(shown.first?.id == "a30")
    }

    @Test func songsPlayedMoreComeFirst() {
        let songs = [played("a", 2, 900), played("b", 5, 100), played("c", 3, 500)]
        #expect(byPlayCount(songs, limit: 20).map(\.id) == ["b", "c", "a"])
    }

    @Test func aTieGoesToTheMoreRecentPlay() {
        let songs = [played("a", 4, 100), played("b", 4, 300), played("c", 4, 200)]
        #expect(byPlayCount(songs, limit: 20).map(\.id) == ["b", "c", "a"])
    }

    @Test func aFullTieKeepsASteadyOrder() {
        let songs = [played("b", 1, 100), played("a", 1, 100)]
        #expect(byPlayCount(songs, limit: 20).map(\.id) == ["a", "b"])
        #expect(byPlayCount(songs.reversed(), limit: 20).map(\.id) == ["a", "b"])
    }

    @Test func songsStopAtTheLimit() {
        let songs = (1...30).map { played("s\($0)", $0, 0) }
        #expect(byPlayCount(songs, limit: 2).map(\.id) == ["s30", "s29"])
    }

    @Test func nothingPlayedShowsNothing() {
        #expect(byLatestPlay([], limit: 20).isEmpty)
        #expect(byPlayCount([], limit: 20).isEmpty)
    }
}
