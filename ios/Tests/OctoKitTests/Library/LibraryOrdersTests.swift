import Foundation
import Testing
@testable import OctoKit

/// A library song with only what an order looks at.
func pageTrack(_ id: String, _ title: String, artist: String = "A", album: String = "Al", albumId: String = "al",
               albumOrder: Int = 0, year: Int? = nil, seconds: Int64 = 0, added: Int64 = 0) -> LibraryTrack {
    LibraryTrack(id: id, sourceId: "server:x", nativeId: id, title: title, searchKey: searchKey(title), sortKey: sortKey(title),
                 artist: artist, artistId: "artist:\(artist)", album: album, albumId: albumId, year: year,
                 durationMs: seconds * 1_000, addedAt: added, albumOrder: albumOrder)
}

@Suite struct LibraryOrdersTests {
    @Test func folderOrderIsAsListedOrReversed() {
        let tracks = [pageTrack("1", "c"), pageTrack("2", "a"), pageTrack("3", "b")]
        #expect(sortFolderSongs(tracks, ListOrder(.song(.folderOrder), descending: false)).map(\.id) == ["1", "2", "3"])
        #expect(sortFolderSongs(tracks, ListOrder(.song(.folderOrder), descending: true)).map(\.id) == ["3", "2", "1"])
        #expect(sortFolderSongs(tracks, ListOrder(.song(.title), descending: false)).map(\.id) == ["2", "3", "1"])
    }

    @Test func aFoldersSongsByArtistKeepEachAlbumInOrder() {
        let tracks = [pageTrack("1", "x", artist: "B", albumId: "b", albumOrder: 2), pageTrack("2", "y", artist: "A"),
                      pageTrack("3", "z", artist: "B", albumId: "b", albumOrder: 1)]
        #expect(sortFolderSongs(tracks, ListOrder(.song(.artist), descending: false)).map(\.id) == ["2", "3", "1"])
        #expect(sortFolderSongs(tracks, ListOrder(.song(.artist), descending: true)).map(\.id) == ["3", "1", "2"])
    }

    @Test func missingYearsGoLastEitherWay() {
        let tracks = [pageTrack("1", "a"), pageTrack("2", "b", year: 1990), pageTrack("3", "c", year: 2000)]
        #expect(sortFolderSongs(tracks, ListOrder(.song(.year), descending: true)).map(\.id) == ["3", "2", "1"])
        #expect(sortFolderSongs(tracks, ListOrder(.song(.year), descending: false)).map(\.id) == ["2", "3", "1"])
    }

    @Test func playlistsByChangeThenName() {
        let lists = [PlaylistSummary(id: "1", name: "b", songCount: 1, durationMs: 0, covers: [], updatedAt: 5),
                     PlaylistSummary(id: "2", name: "a", songCount: 9, durationMs: 0, covers: [], updatedAt: 5),
                     PlaylistSummary(id: "3", name: "c", songCount: 3, durationMs: 0, covers: [], updatedAt: 9)]
        #expect(sortPlaylists(lists, SortList.playlists.defaultOrder).map(\.id) == ["3", "2", "1"])
        #expect(sortPlaylists(lists, ListOrder(.playlist(.name), descending: true)).map(\.id) == ["3", "1", "2"])
        #expect(sortPlaylists(lists, ListOrder(.playlist(.songCount), descending: true)).map(\.id) == ["2", "3", "1"])
    }

    @Test func downloadsOnTheirWayStayOnTop() {
        struct Row { let id: String; let title: String; let done: Bool; let size: Int64; let added: Int64 }
        let rows = [Row(id: "a", title: "Zed", done: true, size: 5, added: 1), Row(id: "b", title: "Mid", done: false, size: 0, added: 9),
                    Row(id: "c", title: "Abe", done: true, size: 9, added: 3)]
        func order(_ order: ListOrder) -> [String] {
            sortDownloads(rows, order, done: \.done, title: \.title, id: \.id, size: \.size, addedAt: \.added).map(\.id)
        }
        #expect(order(SortList.downloads.defaultOrder) == ["b", "c", "a"])
        #expect(order(ListOrder(.download(.title), descending: false)) == ["b", "c", "a"])
        #expect(order(ListOrder(.download(.size), descending: false)) == ["b", "a", "c"])
    }

    @Test func listeningAddsUpByAlbumAndArtist() {
        let x1 = pageTrack("1", "a", artist: "Q", albumId: "x")
        let x2 = pageTrack("2", "b", artist: "Q", albumId: "x")
        let played = [PlayedTrack(track: x1, plays: 2, lastPlayedAt: 10), PlayedTrack(track: x2, plays: 3, lastPlayedAt: 5)]
        let albums = albumListening(played, [PlayedAlbum(album: LibraryAlbum(id: "y", sourceId: "s", nativeId: "y", title: "Y",
                                                                             searchKey: "y", sortKey: "y", artist: "", artistId: "",
                                                                             songCount: 1, durationMs: 0, addedAt: 0), lastPlayedAt: 7)])
        #expect(albums["x"] == Listening(plays: 5, lastPlayedAt: 10))
        #expect(albums["y"] == Listening(plays: 0, lastPlayedAt: 7))
        #expect(artistListening(played)["artist:Q"] == Listening(plays: 5, lastPlayedAt: 10))
        #expect(songListening(played)["2"] == Listening(plays: 3, lastPlayedAt: 5))
    }
}

/// What songs, albums and artists add up to from the plays here and on the server.
@Suite struct PlayedListeningTest {
    private func album(_ id: String) -> LibraryAlbum {
        LibraryAlbum(id: id, sourceId: "s", nativeId: id, title: id, searchKey: id, sortKey: id, artist: "", artistId: "",
                     songCount: 1, durationMs: 0, addedAt: 0)
    }

    @Test func albumsAddUpTheirSongsAndTakeTheLatestPlay() {
        let played = [
            PlayedTrack(track: pageTrack("1", "a", albumId: "x"), plays: 2, lastPlayedAt: 10),
            PlayedTrack(track: pageTrack("2", "b", albumId: "x"), plays: 5, lastPlayedAt: 40),
            PlayedTrack(track: pageTrack("3", "c", albumId: "y"), plays: 1, lastPlayedAt: 20),
        ]
        let server = [PlayedAlbum(album: album("y"), lastPlayedAt: 90), PlayedAlbum(album: album("z"), lastPlayedAt: 30)]
        #expect(albumListening(played, server) == [
            "x": Listening(plays: 7, lastPlayedAt: 40),
            "y": Listening(plays: 1, lastPlayedAt: 90),
            "z": Listening(plays: 0, lastPlayedAt: 30),
        ])
    }

    @Test func artistsAddUpTheSongsOnTheirAlbums() {
        let played = [
            PlayedTrack(track: pageTrack("1", "a", artist: "p"), plays: 2, lastPlayedAt: 10),
            PlayedTrack(track: pageTrack("2", "b", artist: "p"), plays: 4, lastPlayedAt: 5),
            PlayedTrack(track: pageTrack("3", "c", artist: "q"), plays: 1, lastPlayedAt: 20),
        ]
        #expect(artistListening(played) == ["artist:p": Listening(plays: 6, lastPlayedAt: 10), "artist:q": Listening(plays: 1, lastPlayedAt: 20)])
    }

    @Test func songsKeepTheirCombinedCounts() {
        let played = [PlayedTrack(track: pageTrack("1", "a"), plays: 9, lastPlayedAt: 77)]
        #expect(songListening(played) == ["1": Listening(plays: 9, lastPlayedAt: 77)])
    }
}
