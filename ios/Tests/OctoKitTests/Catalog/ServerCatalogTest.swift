import Foundation
import Testing
@testable import OctoKit

@Suite struct ServerCatalogTest {
    let source = "server:10.0.0.5:4533"

    let album = ServerAlbum(id: "al1", name: "Nightcall", artist: "Kavinsky", artistId: "ar1", coverArt: "al-al1_6aafffab",
                            songCount: 1, duration: 179, year: 2024, created: "2026-09-20T15:51:15.203420216Z")

    let song = ServerSong(
        id: "s1", title: "Nightcall", album: "Nightcall", albumId: "al1", artist: "Kavinsky", artistId: "ar1",
        displayArtist: "Kavinsky feat. Angèle", track: 1, discNumber: 1, year: 2024, duration: 179, coverArt: "mf-s1_6aafffab",
        suffix: "flac", contentType: "audio/x-flac", bitRate: 1032, samplingRate: 44_100, bitDepth: 16, size: 24_740_366,
        starred: "2026-09-23T08:00:00Z", displayAlbumArtist: "Kavinsky", genre: "Electro",
        created: "2026-09-20T15:51:15.236955739Z", played: "2026-09-22T13:36:41.43536229Z", playCount: 4)

    func song(_ id: String, _ disc: Int?, _ track: Int?) -> ServerSong {
        ServerSong(id: id, title: "Song \(id)", albumId: "al1", track: track, discNumber: disc, duration: 200)
    }

    func build(_ songs: [ServerSong], _ albums: [ServerAlbum], _ artists: [ServerArtist] = []) -> ServerCatalog {
        buildServerCatalog(source, ServerLibrary(songs, albums, artists))
    }

    @Test func aSongOutsideTheLibraryIsNotKept() {
        var online = song
        online.id = "s2"
        online.title = "Found online"
        online.isExternal = true
        online.size = nil
        online.created = nil
        #expect(build([song, online], [album]).tracks.map(\.nativeId) == ["s1"])
    }

    @Test func aSongMapsToItsRow() {
        let expected = SourceTrack(
            id: "\(source):s1", sourceId: source, nativeId: "s1", title: "Nightcall", searchKey: "nightcall", sortKey: "nightcall",
            artist: "Kavinsky feat. Angèle", artistId: "\(source):ar1", album: "Nightcall", albumId: "\(source):al1", trackNo: 1,
            discNo: 1, year: 2024, durationMs: 179_000, addedAt: 1_789_919_475, mimeType: "audio/flac", sizeBytes: 24_740_366,
            // The album's cover, then the album's first song's own, for the server's stand-in picture.
            artwork: "server:\(source)|al-al1_6aafffab|mf-s1_6aafffab", uri: nil, albumOrder: 0,
            relinkKey: relinkKey(albumArtist: "Kavinsky", album: "Nightcall", disc: 1, track: 1, title: "Nightcall", durationMs: 179_000),
            genre: "Electro", bitrate: 1_032_000, sampleRate: 44_100, bitDepth: 16, playCount: 4, lastPlayedAt: 1_790_084_201_435,
            starredAt: 1_790_150_400_000,
            // A server that sends one genre still gives the list of genres.
            genres: "Electro")
        #expect(build([song], [album]).tracks == [expected])
    }

    var rich: ServerSong {
        var rich = song
        rich.genre = "Disco"
        rich.genres = ["Disco", "Funk"]
        rich.artists = [ArtistRef(id: "ar1", name: "Kavinsky"), ArtistRef(id: "ar2", name: "Angèle")]
        rich.musicBrainzId = "B1A9C0E9-D987-4042-AE91-78D6A3267D69"
        rich.bpm = 116
        rich.comment = " Single edit "
        rich.displayComposer = "Vincent Belorgey"
        rich.explicitStatus = "clean"
        rich.discNumber = 2
        rich.year = 2013
        return rich
    }

    var richAlbum: ServerAlbum {
        var album = album
        album.year = 2013
        album.musicBrainzId = "3f0a4f44-1f1b-4b3c-9c62-7a7d7e2c1a10"
        album.originalReleaseDate = ItemDate(year: 1979, month: 5, day: 1)
        album.discTitles = [DiscTitle(disc: 1, title: "Night One"), DiscTitle(disc: 2, title: "Night Two")]
        return album
    }

    let artists = [
        ServerArtist(id: "ar1", name: "Kavinsky", musicBrainzId: "056e4f3e-d505-4dad-8ec1-d04f521cbb56"),
        ServerArtist(id: "ar2", name: "Angèle", musicBrainzId: ""),
    ]

    @Test func theOpenSubsonicDetailsAreKept() throws {
        let row = try #require(build([rich], [richAlbum], artists).tracks.first)
        #expect(row.genre == "Disco")
        #expect(row.genres == "Disco\nFunk")
        #expect(row.artists == "Kavinsky\nAngèle")
        #expect(row.mbRecordingId == "b1a9c0e9-d987-4042-ae91-78d6a3267d69")
        #expect(row.mbAlbumId == "3f0a4f44-1f1b-4b3c-9c62-7a7d7e2c1a10")
        // Only the artist the server has an id for.
        #expect(row.mbArtistIds == "056e4f3e-d505-4dad-8ec1-d04f521cbb56")
        #expect(row.bpm == 116)
        #expect(row.comment == "Single edit")
        #expect(row.composer == "Vincent Belorgey")
        #expect(row.explicit == false)
        #expect(row.discTitle == "Night Two")
        #expect(row.year == 2013)
        #expect(row.originalYear == 1979)
    }

    @Test func anAlbumShowsItsFirstEditionYear() throws {
        #expect(build([rich], [richAlbum], artists).albums.first?.year == 1979)
        // A first edition said to come after this one is a mistake.
        var wrong = richAlbum
        wrong.originalReleaseDate = ItemDate(year: 2020)
        let catalog = build([rich], [wrong], artists)
        #expect(catalog.albums.first?.year == 2013)
        #expect(catalog.tracks.first?.originalYear == nil)
    }

    @Test func aSongInTheMembersOwnLibraryIsKeptAsTheirs() {
        var mine = song
        mine.octoPersonal = true
        var other = song
        other.id = "s2"
        let catalog = build([mine, other], [album])
        #expect(catalog.tracks.filter(\.personal).count == 1)
        #expect(catalog.tracks.filter { !$0.personal }.count == 1)
    }

    @Test func blankDetailsAreNotKept() throws {
        var blank = song
        blank.musicBrainzId = ""
        blank.comment = ""
        blank.displayComposer = " "
        blank.explicitStatus = ""
        blank.bpm = 0
        let row = try #require(build([blank], [album]).tracks.first)
        #expect(row.mbRecordingId == nil)
        #expect(row.comment == nil)
        #expect(row.composer == nil)
        #expect(row.explicit == nil)
        #expect(row.bpm == nil)
        #expect(row.originalYear == nil)
        #expect(row.mbArtistIds == "")
    }

    @Test func onlyTheSongsOwnMarkCountsNotItsAlbums() {
        var explicitAlbum = album
        explicitAlbum.explicitStatus = "explicit"
        var plainSong = song
        plainSong.explicitStatus = ""
        #expect(build([plainSong], [explicitAlbum]).tracks.first?.explicit == nil)
        var marked = song
        marked.explicitStatus = "explicit"
        #expect(build([marked], [album]).tracks.first?.explicit == true)
    }

    @Test func anAlbumsSongsShareOneCoverWithOneFallback() {
        var b = song("b", 1, 2)
        b.coverArt = "mf-b_1"
        var a = song("a", 1, 1)
        a.coverArt = "mf-a_1"
        let catalog = build([b, a], [album])
        // The first song in album order gives the fallback, for every song.
        #expect(Set(catalog.tracks.map(\.artwork)) == ["server:\(source)|al-al1_6aafffab|mf-a_1"])
        #expect(catalog.albums.first?.artwork == "server:\(source)|al-al1_6aafffab|mf-a_1")
    }

    @Test func aSongWithNoAlbumCoverIsDrawnWithItsOwn() {
        var bare = album
        bare.coverArt = nil
        #expect(build([song], [bare]).tracks.first?.artwork == "server:\(source)|mf-s1_6aafffab")
    }

    @Test func aGenreTextJoiningSeveralGivesEachOne() {
        var joined = song
        joined.genre = "Rock; Pop"
        let row = build([joined], [album]).tracks.first
        #expect(row?.genre == "Rock")
        #expect(row?.genres == "Rock\nPop")
    }

    @Test func anAlbumMapsToItsRow() {
        let expected = SourceAlbum(
            id: "\(source):al1", sourceId: source, nativeId: "al1", title: "Nightcall", searchKey: "nightcall kavinsky",
            sortKey: "nightcall", artist: "Kavinsky", artistId: "\(source):ar1", year: 2024, songCount: 1, durationMs: 179_000,
            addedAt: 1_789_919_475, artwork: "server:\(source)|al-al1_6aafffab|mf-s1_6aafffab")
        #expect(build([song], [album]).albums == [expected])
    }

    @Test func anAlbumKeepsItsReleaseTypesForTheArtistsShelves() {
        var live = album
        live.releaseTypes = ["Album", " Live ", ""]
        #expect(build([song], [live]).albums.first?.releaseTypes == joinLines(["Album", "Live"]))
        // Not tagged, nothing kept.
        #expect(build([song], [album]).albums.first?.releaseTypes == "")
    }

    @Test func artistsAreAlbumArtistsNamedByTheArtistList() {
        var newer = album
        newer.id = "al2"
        newer.name = "OutRun"
        newer.coverArt = "al-al2_1"
        newer.created = "2026-09-21T10:00:00Z"
        let catalog = build([song], [album, newer], [ServerArtist(id: "ar1", name: "KAVINSKY", coverArt: "ar-ar1_0")])
        let expected = SourceArtist(id: "\(source):ar1", sourceId: source, name: "KAVINSKY", searchKey: "kavinsky", sortKey: "kavinsky",
                                    albumCount: 2, songCount: 1, artwork: "server:\(source)|al-al2_1")
        #expect(catalog.artists == [expected])
    }

    @Test func albumOrderFollowsDiscThenTrack() {
        let catalog = build([song("c", 2, 1), song("b", 1, 2), song("a", 1, 1), song("d", 0, 0)], [album])
        let order = catalog.tracks.sorted { $0.albumOrder < $1.albumOrder }
        #expect(order.map(\.nativeId) == ["a", "b", "d", "c"])
        // A 0 from the server means it does not know.
        #expect(order[2].trackNo == nil)
        #expect(order[2].discNo == nil)
    }

    @Test func aSongWhoseAlbumWasNotListedStillGetsOne() throws {
        var late = song
        late.id = "s9"
        late.albumId = "al9"
        late.album = "Late Album"
        late.displayAlbumArtist = "Someone"
        let catalog = build([late], [])
        let made = try #require(catalog.albums.first)
        #expect(catalog.albums.count == 1)
        #expect(made.id == "\(source):al9")
        #expect(made.title == "Late Album")
        #expect(made.artist == "Someone")
        #expect(catalog.tracks.first?.albumId == made.id)
        #expect(catalog.artists.first?.id == made.artistId)
    }

    @Test func aRepeatedSongIsKeptOnce() {
        #expect(build([song, song], [album]).tracks.count == 1)
    }

    @Test func sourceIdNamesThePortOnlyWhenItIsNotTheUsualOne() {
        #expect(serverSourceId(URL(string: "http://10.0.0.5:4533/")!) == "server:10.0.0.5:4533")
        #expect(serverSourceId(URL(string: "https://music.example.com/navidrome/")!) == "server:music.example.com")
        #expect(serverSourceId(URL(string: "http://music.example.com:80/")!) == "server:music.example.com")
        #expect(serverSourceId(URL(string: "https://music.example.com:80/")!) == "server:music.example.com:80")
    }

    @Test func datesWithAndWithoutAZone() {
        #expect(epochMs("2026-09-23T08:00:00Z") == 1_790_150_400_000)
        #expect(epochMs("2026-09-23T10:00:00+02:00") == 1_790_150_400_000)
        #expect(epochMs("2026-09-23T08:00:00") == 1_790_150_400_000)
        #expect(epochMs("yesterday") == nil)
        #expect(epochMs(nil) == nil)
    }

    @Test func keepsTheServersLoudnessAndRating() throws {
        var rated = song
        rated.replayGain = SongReplayGain(trackGain: -8.4, albumGain: -7.9, trackPeak: 0.98, albumPeak: 0, baseGain: 0, fallbackGain: -6)
        rated.userRating = 4
        let row = try #require(build([rated], [album]).tracks.first)
        #expect(row.trackGain == -8.4)
        #expect(row.albumGain == -7.9)
        #expect(row.trackPeak == 0.98)
        // A peak of nothing is no peak.
        #expect(row.albumPeak == nil)
        #expect(row.baseGain == 0)
        #expect(row.fallbackGain == -6)
        #expect(row.rating == 4)

        let plain = try #require(build([song], [album]).tracks.first)
        #expect(plain.trackGain == nil)
        #expect(plain.rating == nil)
    }

    @Test func aFullSongDecodesItsExtras() throws {
        let json = """
        {"subsonic-response":{"status":"ok","version":"1.16.1","song":{"id":7,"title":"T","genres":[{"name":"Rock"},{"name":" "}],
        "artists":[{"id":"a1","name":"A"}],"bpm":"120.5","isrc":"USRC17607839","isExternal":"true","octoPersonal":true,
        "replayGain":{"trackGain":-6.5},"userRating":3,"size":12345}}}
        """
        let decoded: ServerSong = try SubsonicClient.decode(Data(json.utf8), key: "song")
        #expect(decoded.id == "7")
        #expect(decoded.genres == ["Rock"])
        #expect(decoded.artists == [ArtistRef(id: "a1", name: "A")])
        #expect(decoded.bpm == 121)
        #expect(decoded.isrc == ["USRC17607839"])
        #expect(decoded.isExternal)
        #expect(decoded.octoPersonal)
        #expect(decoded.replayGain?.trackGain == -6.5)
        #expect(decoded.userRating == 3)
        #expect(decoded.size == 12345)
    }
}
