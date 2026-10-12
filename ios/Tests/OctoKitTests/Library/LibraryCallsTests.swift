import Foundation
import Testing
@testable import OctoKit

@Suite struct LibraryCallsTests {
    @Test func aSongListingKeepsWhatIsSaidBesideTheSong() throws {
        let json = """
        {"subsonic-response":{"status":"ok","searchResult3":{"song":[{"id":"7","title":"Halo","artist":"Beyoncé",
        "created":"2023-11-14T22:13:20Z","played":"2025-06-15T00:00:00.000Z","playCount":12,"userRating":4,
        "genres":[{"name":"Pop"},{"name":"R&B"}],"displayAlbumArtist":"Beyoncé","bpm":"80","isrc":"USSM10804556",
        "size":8000000,"path":"B/Halo.mp3","octoPersonal":true,"starred":"2024-01-01T00:00:00Z"}]}}}
        """
        struct Body: Decodable {
            let song: [ListedSong]
            init(from decoder: Decoder) throws {
                let c = try decoder.container(keyedBy: AnyKey.self)
                song = try c.decode([ListedSong].self, forKey: AnyKey("song"))
            }
        }
        let body: Body = try SubsonicClient.decode(Data(json.utf8), key: "searchResult3")
        let listed = try #require(body.song.first)
        #expect(listed.song.title == "Halo")
        #expect(listed.song.isStarred)
        #expect(listed.extras.playCount == 12)
        #expect(listed.extras.userRating == 4)
        #expect(listed.extras.genres == ["Pop", "R&B"])
        #expect(listed.extras.bpm == 80)
        #expect(listed.extras.isrc == ["USSM10804556"])
        #expect(listed.extras.size == 8_000_000)
        #expect(listed.extras.personal)
        #expect(serverDateMs(listed.extras.created) == 1_700_000_000_000)
        #expect(serverDateMs(listed.extras.played) == 1_749_945_600_000)
    }

    @Test func anAlbumListingKeepsItsReleaseTypesAndDiscTitles() throws {
        let json = """
        {"subsonic-response":{"status":"ok","album":{"id":"a","name":"RAM","artist":"Daft Punk","songCount":2,
        "releaseTypes":["Album","Compilation"],"discTitles":[{"disc":2,"title":"Night Two"}],"created":"2013-05-17T00:00:00Z",
        "song":[{"id":"1","title":"Give Life Back to Music"},{"id":"2","title":"The Game of Love"}]}}}
        """
        let album: ListedAlbum = try SubsonicClient.decode(Data(json.utf8), key: "album")
        #expect(album.album.name == "RAM")
        #expect(album.extras.releaseTypes == ["Album", "Compilation"])
        #expect(album.extras.discTitles == [2: "Night Two"])
        #expect(album.songs.map(\.song.id) == ["1", "2"])
    }

    @Test func fileActionsSayWhatCanBeDone() throws {
        let json = """
        {"subsonic-response":{"status":"ok","libraryActions":{"enabled":true,"allowed":true,"dryRun":false,
        "actions":["remove","upgrade","restore"],"keepDays":30,"upgradeSource":"Soulseek"}}}
        """
        let actions: FileActions = try SubsonicClient.decode(Data(json.utf8), key: "libraryActions")
        #expect(actions.canRemove)
        #expect(actions.canUpgrade)
        #expect(actions.canRestore)
        #expect(!actions.canEdit)
        #expect(actions.keepDays == 30)
        #expect(!FileActions(enabled: true, allowed: true, dryRun: true, actions: ["remove"]).canRemove)
    }
}
