import Foundation
import Testing
@testable import OctoKit

/// What a search, a radio and a library album take from the server, beyond the library.
@Suite struct DiscoveryRulesTest {
    private let source = "server:music.test"

    private func track(_ id: String, _ title: String, _ artist: String) -> LibraryTrack {
        LibraryTrack(id: id, sourceId: "device", nativeId: id, title: title, searchKey: searchKey(title), sortKey: sortKey(title),
                     artist: artist, artistId: "", album: "", albumId: "", durationMs: 200_000, addedAt: 0)
    }

    private func album(_ id: String, _ name: String, _ artist: String, songs: Int = 10, external: Bool = false, owned: Int? = nil) -> Album {
        var album = Album(id: id, name: name, artist: artist, coverArt: "c-\(id)")
        album.songCount = songs
        album.isExternal = external
        album.ownedCount = owned
        return album
    }

    private func libraryAlbum(_ title: String, _ artist: String) -> LibraryAlbum {
        LibraryAlbum(id: "device:\(title)", sourceId: "device", nativeId: title, title: title, searchKey: searchKey("\(title) \(artist)"),
                     sortKey: sortKey(title), artist: artist, artistId: "", songCount: 1, durationMs: 0, addedAt: 0)
    }

    private func artist(_ id: String, _ name: String, albums: Int = 1) throws -> Artist {
        let json: [String: Any] = ["id": id, "name": name, "albumCount": albums, "coverArt": "ar-\(id)"]
        return try JSONDecoder().decode(Artist.self, from: JSONSerialization.data(withJSONObject: json))
    }

    private func libraryArtist(_ name: String) -> LibraryArtist {
        LibraryArtist(id: "device:\(name)", sourceId: "device", name: name, searchKey: searchKey(name), sortKey: sortKey(name), albumCount: 1,
                      songCount: 1)
    }

    private func copy(_ trackId: String, source: String, native: String, album: String) -> SourceTrack {
        SourceTrack(id: "\(source):\(native)", sourceId: source, nativeId: native, title: "", searchKey: "", sortKey: "", artist: "",
                    artistId: "", album: "", albumId: album, durationMs: 0, addedAt: 0, mergedId: trackId)
    }

    // Search

    @Test func aSearchAsksForMoreSongsThanOctoHoldsBack() {
        #expect(discoverySearchArtists == 10)
        #expect(discoverySearchAlbums == 20)
        #expect(discoverySearchSongs == 40)
        #expect(discoverySearchSongs > 12)
    }

    @Test func onlyFindsAreListedAmongTheSongs() {
        let songs = [track("device:1", "Hold On", "Drake"), track("find:s2", "Hold On", "Chord Overstreet"), track("find:s3", "Hold Up", "Beyonce")]
        let found = discovered(songs: songs, albums: [], artists: [], sourceId: source)
        #expect(found.songs.map(\.id) == ["find:s2", "find:s3"])
        #expect(!found.notInLibraryEmpty)
    }

    @Test func albumsHeldWholeAreDroppedAndAlbumsHeldInPartGoApart() {
        let albums = [
            album("a1", "Views", "Drake", songs: 20, external: true, owned: 20),
            album("a2", "Scorpion", "Drake", songs: 25, external: true, owned: 3),
            album("a3", "Honestly, Nevermind", "Drake", songs: 14, external: true, owned: 0),
            album("a4", "Dark Lane Demo Tapes", "Drake", songs: 14, external: true),
        ]
        let found = discovered(songs: [], albums: albums, artists: [], sourceId: source)
        #expect(found.albums.map(\.id) == ["a3", "a4"])
        #expect(found.partAlbums.map(\.id) == ["a2"])
        #expect(found.partAlbums.first?.ownedCount == 3)
        #expect(found.albums.first?.artwork == onlineArtwork(source, "c-a3"))
        #expect(found.notInLibraryEmpty == false)
    }

    @Test func onlyAPartlyHeldAlbumLeavesNothingNotInTheLibrary() {
        let found = discovered(songs: [], albums: [album("a2", "Scorpion", "Drake", songs: 25, external: true, owned: 3)], artists: [],
                               sourceId: source)
        #expect(found.notInLibraryEmpty)
        #expect(!found.isEmpty)
        #expect(discovered(songs: [], albums: [], artists: [], sourceId: source).isEmpty)
    }

    @Test func aLibraryAlbumKeepsNoCount() {
        let online = OnlineAlbum(album("a1", "Views", "Drake", songs: 20, owned: 20), sourceId: source)
        #expect(online.ownedCount == nil)
        #expect(online.title == "Views")
        #expect(online.artwork == "online:\(source)|c-a1")
    }

    @Test func albumsTheLibraryHasFromTheServerOrByNameAreLeftOut() {
        let albums = [album("a1", "Views", "Drake"), album("a2", "Scorpion (Deluxe)", "Drake"), album("a3", "Take Care", "Drake")]
        let library = [libraryAlbum("Scorpion", "Drake")]
        #expect(albumLookupKeys(albums) == ["views drake", "scorpion (deluxe) drake", "take care drake"])
        #expect(albumsNotInLibrary(albums, known: ["a1"], library: library).map(\.id) == ["a3"])
        #expect(albumsNotInLibrary([], known: [], library: library).isEmpty)
    }

    @Test func artistsTheLibraryHasFromTheServerOrByNameAreLeftOut() throws {
        let artists = [try artist("ar1", "Drake"), try artist("ar2", "The Weeknd"), try artist("ar3", "SZA", albums: 3)]
        #expect(artistRowIds(artists, sourceId: source) == ["\(source):ar1", "\(source):ar2", "\(source):ar3"])
        #expect(artistLookupKeys(artists) == ["drake", "the weeknd", "sza"])
        let shown = artistsNotInLibrary(artists, sourceId: source, known: ["\(source):ar1"], library: [libraryArtist("The Weeknd")])
        #expect(shown == [OnlineArtist(id: "ar3", name: "SZA", albumCount: 3, artwork: onlineArtwork(source, "ar-ar3"))])
    }

    // Radio

    @Test func aFindSeedsRadioWithItsOwnId() async throws {
        let seed = track("find:s9", "Genesis", "Justice")
        #expect(knownSeedId(seed, copies: []) == "s9")
        let id = try await radioSeedId(seed, copies: []) { _ in
            Issue.record("a find needs no search")
            return []
        }
        #expect(id == "s9")
    }

    @Test func aLibrarySongSeedsRadioWithItsServerCopy() {
        let seed = track("device:7", "Genesis", "Justice")
        let copies = [copy("device:7", source: "device", native: "7", album: "device:al"),
                      copy("device:7", source: source, native: "tr-7", album: "\(source):al")]
        #expect(knownSeedId(seed, copies: copies) == "tr-7")
        #expect(knownSeedId(seed, copies: [copies[0]]) == nil)
    }

    @Test func aSongOnlyOnThePhoneIsSearchedForTheSameRecordingFirst() async throws {
        let seed = track("device:7", "Genesis", "Justice")
        #expect(seedSearch(seed) == "Justice Genesis")
        let found = [Song(id: "live", title: "Genesis (Live)", artist: "Justice"), Song(id: "studio", title: "Genesis", artist: "Justice")]
        var asked: [String] = []
        let id = try await radioSeedId(seed, copies: []) { query in
            asked.append(query)
            return found
        }
        #expect(asked == ["Justice Genesis"])
        #expect(id == "studio")
    }

    @Test func elseTheSameSongInAnyVersion() {
        let seed = track("device:7", "Genesis", "Justice")
        let found = [Song(id: "other", title: "Genesis", artist: "Phil Collins"), Song(id: "live", title: "Genesis (Live)", artist: "Justice")]
        #expect(seedIdAmong(found, for: seed) == "live")
        #expect(seedIdAmong([Song(id: "other", title: "Genesis", artist: "Phil Collins")], for: seed) == nil)
    }

    @Test func aServerThatCannotAnswerGivesNoSeedButAStopIsPassedOn() async throws {
        struct Down: Error {}
        let seed = track("device:7", "Genesis", "Justice")
        let none = try await radioSeedId(seed, copies: []) { _ in throw Down() }
        #expect(none == nil)
        await #expect(throws: CancellationError.self) {
            _ = try await radioSeedId(seed, copies: []) { _ in throw CancellationError() }
        }
    }

    @Test func aRadioStartsFromItsSeedAndPlaysEachSongOnce() {
        let seed = track("device:1", "Genesis", "Justice")
        let similar = [track("find:2", "D.A.N.C.E.", "Justice"), track("device:1", "Genesis", "Justice"), track("find:2", "D.A.N.C.E.", "Justice"),
                       track("find:3", "Phantom", "Justice")]
        #expect(radioSongs(seed: seed, similar: similar).map(\.id) == ["device:1", "find:2", "find:3"])
        #expect(discoveryRadioSongs == 50)
    }

    // Stations

    @Test func aStationWithoutACoverIsDrawnFromItsId() throws {
        let json = #"[{"id":"or3kZ9QpLmN2xY7wV1bC0a","name":"Chill"},{"id":"or2","name":"Gym","coverArt":"cv-2"}]"#
        let stations = try JSONDecoder().decode([RadioStation].self, from: Data(json.utf8)).map { Station($0, sourceId: source) }
        #expect(stations.map(\.artwork) == [ArtworkRef.server(sourceId: source, coverId: "or3kZ9QpLmN2xY7wV1bC0a").encode(),
                                            ArtworkRef.server(sourceId: source, coverId: "cv-2").encode()])
        #expect(stations.allSatisfy { $0.songCount == nil })
    }

    @Test func anAddedStationPlaysItsStreamAndOneWithoutIsLeftOff() throws {
        let json = #"[{"id":"or3kZ9QpLmN2xY7wV1bC0a","name":"Your Mix","streamUrl":"https://octo/radio/stream/abc","coverArt":"or3kZ9QpLmN2xY7wV1bC0a"},"# +
            #"{"id":"rs-1","name":"City Radio","streamUrl":"https://radio.example.com/live.mp3","coverArt":"ra-rs-1"},"# +
            #"{"id":"rs-2","name":"Town FM","streamUrl":"https://town.example.com/fm","homePageUrl":"https://town.example.com"},"# +
            #"{"id":"rs-3","name":"Empty","coverArt":"ra-rs-3"}]"#
        let stations = homeStations(try JSONDecoder().decode([RadioStation].self, from: Data(json.utf8)), sourceId: source)
        #expect(stations.map(\.id) == ["or3kZ9QpLmN2xY7wV1bC0a", "rs-1", "rs-2"])
        #expect(stations[0].streamUrl == nil)
        #expect(stations[1].streamUrl == "https://radio.example.com/live.mp3")
        #expect(stations[1].artwork == ArtworkRef.server(sourceId: source, coverId: "ra-rs-1").encode())
        #expect(stations[2].artwork == ArtworkRef.server(sourceId: source, coverId: "rs-2").encode())
        // The server's website for a station rides with it; one without has none.
        #expect(stations[2].homepage == "https://town.example.com")
        #expect(stations[1].homepage == nil)
    }

    // A library album on the server

    @Test func aLibraryAlbumIsTheServerAlbumMostOfItsSongsCameFrom() {
        let copies = [
            copy("t1", source: source, native: "1", album: "\(source):deluxe"),
            copy("t2", source: source, native: "2", album: "\(source):std"),
            copy("t3", source: source, native: "3", album: "\(source):std"),
            copy("t4", source: "device", native: "4", album: "device:x"),
            copy("t5", source: "device", native: "5", album: "device:x"),
            copy("t6", source: "device", native: "6", album: "device:x"),
        ]
        #expect(serverAlbumRow(copies, sourceId: source) == "\(source):std")
    }

    @Test func aTieGoesToTheAlbumSeenFirst() {
        let copies = [copy("t1", source: source, native: "1", album: "\(source):b"), copy("t2", source: source, native: "2", album: "\(source):a")]
        #expect(serverAlbumRow(copies, sourceId: source) == "\(source):b")
    }

    @Test func noSongFromTheServerMeansNoAlbum() {
        #expect(serverAlbumRow([copy("t1", source: "device", native: "1", album: "device:x")], sourceId: source) == nil)
        #expect(serverAlbumRow([], sourceId: source) == nil)
    }
}
