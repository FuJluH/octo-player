import Foundation
import Testing
@testable import OctoKit

@Suite struct AlbumShareTest {
    private func outside(_ name: String, _ songs: Int, _ owned: Int?) -> Album {
        var album = Album(id: name, name: name, artist: "Drake")
        album.songCount = songs
        album.isExternal = true
        album.ownedCount = owned
        return album
    }

    @Test func anAlbumHeldInPartSaysHowMuch() {
        let album = outside("What A Time To Be Alive", 11, 2)
        #expect(albumShare(album) == .part)
        #expect(albumShareLine(album) == "2 of 11 in your library")
    }

    @Test func thePhonesOwnAlbumsSayItFromTheCounts() {
        #expect(albumShareLine(owned: 20, songs: 21) == "20 of 21 in your library")
        #expect(albumShareLine(owned: 0, songs: 14) == nil)
        #expect(albumShareLine(owned: 11, songs: 11) == nil)
        #expect(albumShareLine(owned: nil, songs: 11) == nil)
    }

    @Test func noneAndWholeHaveNoLine() {
        #expect(albumShare(outside("MAID OF HONOUR", 14, 0)) == AlbumShare.none)
        #expect(albumShareLine(outside("MAID OF HONOUR", 14, 0)) == nil)
        #expect(albumShare(outside("HABIBTI", 11, 11)) == .whole)
        #expect(albumShareLine(outside("HABIBTI", 11, 11)) == nil)
    }

    @Test func uncountedAndLibraryAlbumsHaveNoShare() {
        #expect(albumShare(outside("$ome $exy $ongs 4 U", 21, nil)) == nil)
        var library = Album(id: "al-1", name: "HABIBTI (FOMO)", artist: "")
        library.songCount = 15
        library.ownedCount = 15
        #expect(albumShare(library) == nil)
    }

    @Test func theServersFieldsAreReadAndAnOlderServerLeavesThemOut() throws {
        let counted = try JSONDecoder().decode(Album.self, from: Data(
            #"{"id":"x","name":"What A Time To Be Alive","songCount":11,"isExternal":true,"ownedCount":2}"#.utf8))
        #expect(albumShareLine(counted) == "2 of 11 in your library")
        let older = try JSONDecoder().decode(Album.self, from: Data(#"{"id":"x","name":"What A Time To Be Alive","songCount":11,"isExternal":true}"#.utf8))
        #expect(albumShare(older) == nil)
    }
}
