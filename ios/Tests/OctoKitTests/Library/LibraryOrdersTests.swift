import Foundation
import Testing
@testable import OctoKit

/// A library song with only what an order looks at.
func track(_ id: String, _ title: String, artist: String = "A", album: String = "Al", albumId: String = "al",
           disc: Int = 1, number: Int = 0, year: Int? = nil, seconds: Int = 0, added: Int64 = 0, rating: Int = 0,
           likedAt: Int64? = nil, plays: Int = 0, lastPlayedAt: Int64 = 0, genre: String? = nil) -> ShownSong {
    var song = Song(id: id, title: title, artist: artist, album: album, albumId: albumId, duration: seconds)
    song.track = number
    song.discNumber = disc
    song.year = year
    song.genre = genre
    return ShownSong(song: song, addedAt: added, rating: rating, plays: plays, lastPlayedAt: lastPlayedAt, likedAt: likedAt)
}

@Suite struct LibraryOrdersTests {
    @Test func titlesRunAToZWithTheArticleDropped() {
        let tracks = [track("1", "The Zoo"), track("2", "Apple"), track("3", "Mango")]
        let sorted = sortSongs(tracks, ListOrder(.song(.title), descending: false))
        #expect(sorted.items.map(\.id) == ["2", "3", "1"])
        #expect(sorted.headings == ["apple", "mango", "zoo"])
        #expect(sortSongs(tracks, ListOrder(.song(.title), descending: true)).items.map(\.id) == ["1", "3", "2"])
    }

    @Test func onlyTheFirstKeyFollowsTheDirection() {
        // Two albums added at different times; each album's songs stay in album order.
        let tracks = [
            track("a2", "Second", albumId: "old", number: 2, added: 100), track("a1", "First", albumId: "old", number: 1, added: 100),
            track("b2", "Two", albumId: "new", number: 2, added: 200), track("b1", "One", albumId: "new", number: 1, added: 200),
        ]
        let newest = sortSongs(tracks, ListOrder(.song(.recentlyAdded), descending: true))
        #expect(newest.items.map(\.id) == ["b1", "b2", "a1", "a2"])
        #expect(newest.headings == nil)
        let oldest = sortSongs(tracks, ListOrder(.song(.recentlyAdded), descending: false))
        #expect(oldest.items.map(\.id) == ["a1", "a2", "b1", "b2"])
    }

    @Test func missingYearsAndRatingsGoLastEitherWay() {
        let tracks = [track("1", "a", year: nil), track("2", "b", year: 1990), track("3", "c", year: 2000)]
        #expect(sortSongs(tracks, ListOrder(.song(.year), descending: true)).items.map(\.id) == ["3", "2", "1"])
        #expect(sortSongs(tracks, ListOrder(.song(.year), descending: false)).items.map(\.id) == ["2", "3", "1"])
        let rated = [track("1", "a", rating: 0), track("2", "b", rating: 3), track("3", "c", rating: 5)]
        #expect(sortSongs(rated, ListOrder(.song(.rating), descending: false)).items.map(\.id) == ["2", "3", "1"])
    }

    @Test func aRatingTieLikedSongsFirst() {
        let tracks = [track("1", "a", rating: 4), track("2", "b", rating: 4, likedAt: 5)]
        #expect(sortSongs(tracks, ListOrder(.song(.rating), descending: true)).items.map(\.id) == ["2", "1"])
        #expect(sortSongs(tracks, ListOrder(.song(.rating), descending: false)).items.map(\.id) == ["2", "1"])
    }

    @Test func neverLikedGoesLastByDateLiked() {
        let tracks = [track("1", "a"), track("2", "b", likedAt: 10), track("3", "c", likedAt: 20)]
        #expect(sortSongs(tracks, ListOrder(.song(.dateLiked), descending: true)).items.map(\.id) == ["3", "2", "1"])
        #expect(likedSongs(tracks, ListOrder(.song(.dateLiked), descending: false)).items.map(\.id) == ["2", "3"])
    }

    @Test func playsPutPlayedSongsFirstWithoutHeadings() {
        let tracks = [track("1", "a"), track("2", "b", plays: 2, lastPlayedAt: 5), track("3", "c", plays: 9, lastPlayedAt: 1)]
        let most = sortSongs(tracks, ListOrder(.song(.mostPlayed), descending: true))
        #expect(most.items.map(\.id) == ["3", "2", "1"])
        #expect(most.headings == nil)
        #expect(sortSongs(tracks, ListOrder(.song(.recentlyPlayed), descending: true)).items.map(\.id) == ["2", "3", "1"])
    }

    @Test func aGenreMatchesWhateverTheCase() {
        let tracks = [track("1", "a", genre: "Rock"), track("2", "b", genre: "rock"), track("3", "c", genre: "Pop")]
        #expect(genreSongs(tracks, genre: "ROCK", SortList.genreSongs.defaultOrder).items.map(\.id) == ["1", "2"])
    }

    @Test func folderOrderIsAsListedOrReversed() {
        let tracks = [track("1", "c"), track("2", "a"), track("3", "b")]
        #expect(sortFolderSongs(tracks, ListOrder(.song(.folderOrder), descending: false)).map(\.id) == ["1", "2", "3"])
        #expect(sortFolderSongs(tracks, ListOrder(.song(.folderOrder), descending: true)).map(\.id) == ["3", "2", "1"])
        #expect(sortFolderSongs(tracks, ListOrder(.song(.title), descending: false)).map(\.id) == ["2", "3", "1"])
    }

    @Test func albumsByYearPutTheUndatedLast() {
        func album(_ id: String, _ name: String, year: Int?) -> ShownAlbum {
            var a = Album(id: id, name: name, artist: "X")
            a.year = year
            return ShownAlbum(album: a)
        }
        let albums = [album("1", "a", year: nil), album("2", "b", year: 1999), album("3", "c", year: 2010)]
        let sorted = sortAlbums(albums, ListOrder(.album(.year), descending: true))
        #expect(sorted.items.map(\.id) == ["3", "2", "1"])
        #expect(sorted.headings == nil)
        #expect(sortAlbums(albums, ListOrder(.album(.title), descending: false)).headings == ["a", "b", "c"])
    }

    @Test func artistsByNameHaveHeadings() {
        let artists = [ShownArtist(id: "1", name: "The Who", songCount: 3), ShownArtist(id: "2", name: "ABBA", songCount: 9)]
        let byName = sortArtists(artists, ListOrder(.artist(.name), descending: false))
        #expect(byName.items.map(\.id) == ["2", "1"])
        #expect(byName.headings == ["abba", "who"])
        #expect(sortArtists(artists, ListOrder(.artist(.songCount), descending: true)).items.map(\.id) == ["2", "1"])
    }

    @Test func playlistsByChangeThenName() {
        let lists = [ShownPlaylist(id: "1", name: "b", updatedAt: 5), ShownPlaylist(id: "2", name: "a", updatedAt: 5),
                     ShownPlaylist(id: "3", name: "c", updatedAt: 9)]
        #expect(sortPlaylists(lists, SortList.playlists.defaultOrder).map(\.id) == ["3", "2", "1"])
        #expect(sortPlaylists(lists, ListOrder(.playlist(.name), descending: true)).map(\.id) == ["3", "1", "2"])
    }

    @Test func albumListeningAddsSongsAndTheServersAlbumHistory() {
        let tracks = [track("1", "a", albumId: "x", plays: 2, lastPlayedAt: 10), track("2", "b", albumId: "x", plays: 3, lastPlayedAt: 5)]
        let listening = albumListening(tracks, albumsPlayed: ["x": 50, "y": 7])
        #expect(listening["x"] == Listening(plays: 5, lastPlayedAt: 50))
        #expect(listening["y"] == Listening(plays: 0, lastPlayedAt: 7))
    }
}
