import Foundation
import Testing
@testable import OctoKit

@Suite struct PlacesTest {
    private func track(_ id: String) -> LibraryTrack {
        LibraryTrack(id: id, sourceId: "device", nativeId: id, title: id, searchKey: id, sortKey: id, artist: "", artistId: "",
                     album: "", albumId: "", durationMs: 0, addedAt: 0)
    }

    @Test func wholeGroupsPlayInTheOrderShown() {
        let places = [
            TrackPlace(id: "1", albumId: "x", artistId: "p"),
            TrackPlace(id: "2", albumId: "x", artistId: "p"),
            TrackPlace(id: "3", albumId: "y", artistId: "q"),
            TrackPlace(id: "4", albumId: "z", artistId: "p"),
        ]
        #expect(songsInGroupOrder(places, groupOf: { $0.albumId }, groups: ["y", "x", "z"]) == ["3", "1", "2", "4"])
        #expect(songsInGroupOrder(places, groupOf: { $0.artistId }, groups: ["q", "p"]) == ["3", "1", "2", "4"])
        // A group not shown is left out.
        #expect(songsInGroupOrder(places, groupOf: { $0.albumId }, groups: ["y"]) == ["3"])
    }

    @Test func anArtistsSongsStayInAlbumOrderUntilPlayed() {
        let songs = [track("a"), track("b"), track("c")]
        #expect(artistSongOrder(songs, played: []).map(\.id) == ["a", "b", "c"])
    }

    @Test func theMostPlayedComeFirstThenTheRestInAlbumOrder() {
        let songs = [track("a"), track("b"), track("c"), track("d")]
        let played = [PlayedTrack(track: track("c"), plays: 5, lastPlayedAt: 10), PlayedTrack(track: track("b"), plays: 2, lastPlayedAt: 50),
                      PlayedTrack(track: track("d"), plays: 5, lastPlayedAt: 90)]
        #expect(artistSongOrder(songs, played: played).map(\.id) == ["d", "c", "b", "a"])
    }

    @Test func aSongListedTwiceCountsByItsLastRow() {
        let songs = [track("a"), track("b")]
        let played = [PlayedTrack(track: track("a"), plays: 1, lastPlayedAt: 10), PlayedTrack(track: track("b"), plays: 3, lastPlayedAt: 20),
                      PlayedTrack(track: track("a"), plays: 7, lastPlayedAt: 30)]
        #expect(artistSongOrder(songs, played: played).map(\.id) == ["a", "b"])
    }

    @Test func playsOfOtherArtistsDoNotCount() {
        let songs = [track("a"), track("b")]
        let played = [PlayedTrack(track: track("z"), plays: 9, lastPlayedAt: 10)]
        #expect(artistSongOrder(songs, played: played).map(\.id) == ["a", "b"])
    }
}
