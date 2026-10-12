import Foundation
import Testing
@testable import OctoKit

@Suite struct CatalogMergerTest {
    func track(_ id: String, _ source: String, _ title: String, _ album: String, artist: String? = nil, ms: Int64 = 200_000,
               no: Int? = nil, order: Int = 0, year: Int? = nil, genre: String = "") -> SourceTrack {
        SourceTrack(id: id, sourceId: source, nativeId: id, title: title, searchKey: title.lowercased(), sortKey: title.lowercased(),
                    artist: "Drake", artistId: artist ?? "\(source):artist", album: "Views", albumId: album, trackNo: no, discNo: nil,
                    year: year, durationMs: ms, addedAt: 0, albumOrder: order, relinkKey: "", genre: genre)
    }

    func album(_ id: String, _ source: String, title: String = "Views", artist: String? = nil, songs: Int = 0,
               art: String? = nil) -> SourceAlbum {
        SourceAlbum(id: id, sourceId: source, nativeId: id, title: title, searchKey: title.lowercased(), sortKey: title.lowercased(),
                    artist: "Drake", artistId: artist ?? "\(source):artist", year: nil, songCount: songs, durationMs: 0, addedAt: 0,
                    artwork: art)
    }

    func artist(_ id: String, _ source: String, name: String = "Drake") -> SourceArtist {
        SourceArtist(id: id, sourceId: source, name: name, searchKey: name.lowercased(), sortKey: name.lowercased(), albumCount: 1,
                     songCount: 1)
    }

    func phone(_ tracks: [SourceTrack], _ albums: [SourceAlbum], _ artists: [SourceArtist]) -> SourceCatalog {
        SourceCatalog(sourceId: "device", onPhone: true, tracks: tracks, albums: albums, artists: artists)
    }

    func server(_ tracks: [SourceTrack], _ albums: [SourceAlbum], _ artists: [SourceArtist]) -> SourceCatalog {
        SourceCatalog(sourceId: "server", onPhone: false, tracks: tracks, albums: albums, artists: artists)
    }

    var phoneOnly: SourceCatalog {
        phone([track("p1", "device", "Hotline Bling", "device:album", order: 1), track("p2", "device", "One Dance", "device:album", order: 0)],
              [album("device:album", "device", songs: 2)], [artist("device:artist", "device")])
    }

    func with(_ track: SourceTrack, _ change: (inout SourceTrack) -> Void) -> SourceTrack {
        var copy = track
        change(&copy)
        return copy
    }

    func byId(_ merged: MergedCatalog) -> [String: LibraryTrack] {
        Dictionary(uniqueKeysWithValues: merged.tracks.map { ($0.id, $0) })
    }

    @Test func oneSourcePassesThroughUnchanged() throws {
        let merged = mergeCatalogs([phoneOnly])
        let before = Dictionary(uniqueKeysWithValues: phoneOnly.tracks.map { ($0.id, $0) })
        #expect(merged.tracks.count == 2)
        for t in merged.tracks {
            let s = try #require(before[t.id])
            #expect(s.albumId == t.albumId)
            #expect(s.artistId == t.artistId)
            #expect(s.albumOrder == t.albumOrder)
            #expect(t.onPhone)
        }
        #expect(merged.albums.map(\.id) == ["device:album"])
        #expect(merged.albums.first?.songCount == 2)
        #expect(merged.mergedIds == ["p1": "p1", "p2": "p2"])
    }

    @Test func aServerRatingReachesTheLibrarySong() {
        let serverSide = server(
            [with(track("s1", "server", "Hotline Bling", "server:album")) { $0.rating = 4 },
             with(track("s2", "server", "One Dance", "server:album")) { $0.rating = 0 }],
            [album("server:album", "server", songs: 2)], [artist("server:artist", "server")])
        let merged = byId(mergeCatalogs([phoneOnly, serverSide]))
        #expect(merged["p1"]?.rating == 4)
        #expect(merged["p2"]?.rating == 0)
    }

    @Test func theFirstCopyThatSaysGivesTheExplicitMark() {
        let serverSide = server(
            [with(track("s1", "server", "Hotline Bling", "server:album")) { $0.explicit = true },
             with(track("s2", "server", "One Dance", "server:album")) { $0.explicit = false }],
            [album("server:album", "server", songs: 2)], [artist("server:artist", "server")])
        let merged = byId(mergeCatalogs([phoneOnly, serverSide]))
        #expect(merged["p1"]?.explicit == true)
        #expect(merged["p2"]?.explicit == false)
        var tagged = phoneOnly
        tagged.tracks = tagged.tracks.map { $0.id == "p1" ? with($0) { $0.explicit = false } : $0 }
        #expect(byId(mergeCatalogs([tagged, serverSide]))["p1"]?.explicit == false)
        #expect(mergeCatalogs([phoneOnly]).tracks.first?.explicit == nil)
    }

    @Test func albumsOfTheSameNameInOneSourceStayApart() {
        let twin = phone([track("a", "device", "Intro", "device:a"), track("b", "device", "Intro", "device:b")],
                         [album("device:a", "device"), album("device:b", "device")],
                         [artist("device:artist", "device"), artist("device:other", "device", name: "DRAKE")])
        let merged = mergeCatalogs([twin])
        #expect(merged.albums.count == 2)
        #expect(merged.tracks.count == 2)
        #expect(merged.artists.count == 2)
    }

    @Test func theSameAlbumOnPhoneAndServerShowsOnce() throws {
        let serverSide = server(
            [track("s1", "server", "One Dance (feat. Wizkid)", "server:album", ms: 201_500, no: 2, year: 2016, genre: "Hip-Hop/Rap"),
             track("s2", "server", "Hotline Bling", "server:album", no: 20),
             track("s3", "server", "Views", "server:album", no: 1)],
            [album("server:album", "server", songs: 3, art: "server:art")], [artist("server:artist", "server")])
        let merged = mergeCatalogs([phoneOnly, serverSide])

        let album = try #require(merged.albums.first)
        #expect(merged.albums.count == 1)
        #expect(album.id == "device:album")
        #expect(album.artwork == "server:art")
        #expect(album.songCount == 3)

        let byTitle = Dictionary(uniqueKeysWithValues: merged.tracks.map { ($0.title, $0) })
        #expect(byTitle["One Dance"]?.id == "p2")
        #expect(byTitle["One Dance"]?.onPhone == true)
        #expect(byTitle["Views"]?.onPhone == false)
        #expect(byTitle["Views"]?.albumId == "device:album")
        #expect(byTitle["Views"]?.artistId == "device:artist")

        #expect(byTitle["One Dance"]?.trackNo == 2)
        #expect(byTitle["One Dance"]?.year == 2016)
        #expect(byTitle["One Dance"]?.genre == "Hip-Hop/Rap")
        #expect(merged.tracks.sorted { $0.albumOrder < $1.albumOrder }.map(\.title) == ["Views", "One Dance", "Hotline Bling"])

        #expect(merged.mergedIds["s1"] == "p2")
        #expect(merged.mergedIds["s2"] == "p1")
        #expect(merged.mergedIds["s3"] == "s3")

        let drake = try #require(merged.artists.first)
        #expect(merged.artists.count == 1)
        #expect(drake.id == "device:artist")
        #expect(drake.songCount == 3)
        #expect(drake.albumCount == 1)
    }

    @Test func theServersReleaseTypesFillWhatThePhoneLacks() {
        var typed = album("server:album", "server", songs: 2)
        typed.releaseTypes = joinLines(["Album", "Compilation"])
        let serverSide = server([track("s1", "server", "One Dance", "server:album"), track("s2", "server", "Hotline Bling", "server:album")],
                                [typed], [artist("server:artist", "server")])
        let merged = mergeCatalogs([phoneOnly, serverSide])
        #expect(merged.albums.first?.id == "device:album")
        #expect(merged.albums.first?.releaseTypes == joinLines(["Album", "Compilation"]))
    }

    @Test func songsOfDifferentLengthsAreDifferentSongs() {
        let serverSide = server([track("s1", "server", "One Dance", "server:album", ms: 260_000)], [album("server:album", "server")],
                                [artist("server:artist", "server")])
        let merged = mergeCatalogs([phoneOnly, serverSide])
        #expect(merged.tracks.count == 3)
        #expect(merged.tracks.filter { $0.title == "One Dance" }.count == 2)
    }

    @Test func anAlbumOnlyOnTheServerStreams() {
        let serverSide = server([track("s9", "server", "Gods Plan", "server:scorpion")],
                                [album("server:scorpion", "server", title: "Scorpion", songs: 1)], [artist("server:artist", "server")])
        let merged = mergeCatalogs([phoneOnly, serverSide])
        let scorpion = merged.albums.first { $0.title == "Scorpion" }
        #expect(scorpion?.id == "server:scorpion")
        #expect(scorpion?.artistId == "device:artist")
        #expect(merged.tracks.first { $0.id == "s9" }?.onPhone == false)
    }

    @Test func matchKeysIgnoreCasePunctuationAndBracketedExtras() {
        #expect(matchKey("One Dance") == matchKey("one dance (feat. Wizkid & Kyla)"))
        #expect(matchKey("Jay-Z") == matchKey("JAY Z"))
        #expect(matchKey("Views") == matchKey("Views [Deluxe]"))
    }

    @Test func anAlbumFiledUnderAnotherArtistStillShowsOnce() {
        var deluxe = album("server:deluxe", "server", title: "Views (Deluxe)", artist: "server:ovo", songs: 2)
        deluxe.artist = "OVO Sound"
        let serverSide = server([track("s1", "server", "Hotline Bling", "server:deluxe", no: 1),
                                 track("s2", "server", "One Dance", "server:deluxe", no: 2)],
                                [deluxe], [artist("server:ovo", "server", name: "OVO Sound")])
        let merged = mergeCatalogs([phoneOnly, serverSide])
        #expect(merged.albums.map(\.id) == ["device:album"])
        #expect(merged.tracks.count == 2)
        #expect(merged.mergedIds["s1"] == "p1")
        #expect(merged.mergedIds["s2"] == "p2")
        #expect(merged.artists.map(\.id) == ["device:artist"])
    }

    @Test func aDeluxeEditionKeepsOnlyItsExtraSongs() {
        var deluxe = album("server:deluxe", "server", title: "Views (Deluxe)", artist: "server:ovo", songs: 2)
        deluxe.artist = "OVO Sound"
        let serverSide = server([track("s1", "server", "Hotline Bling", "server:deluxe"),
                                 track("s2", "server", "Bonus Track", "server:deluxe", ms: 180_000)],
                                [deluxe], [artist("server:ovo", "server", name: "OVO Sound")])
        let merged = mergeCatalogs([phoneOnly, serverSide])
        #expect(merged.albums.first { $0.id == "server:deluxe" }?.songCount == 1)
        #expect(merged.tracks.filter { $0.albumId == "server:deluxe" }.map(\.title) == ["Bonus Track"])
        #expect(merged.mergedIds["s1"] == "p1")
    }

    @Test func theSameTitleByAnotherArtistIsNotTheSameSong() {
        let cover = with(track("s1", "server", "One Dance", "server:covers")) { $0.artist = "Someone Else" }
        let serverSide = server([cover], [album("server:covers", "server", title: "Covers", artist: "server:someone")],
                                [artist("server:someone", "server", name: "Someone Else")])
        let merged = mergeCatalogs([phoneOnly, serverSide])
        #expect(merged.mergedIds["s1"] == "s1")
        #expect(merged.tracks.count == 3)
    }

    @Test func songsMatchByTheirTitleAsTheServerReadsIt() {
        let serverSide = server([track("s1", "server", "Hotline Bling - Remastered 2011", "server:album"),
                                 track("s2", "server", "One Dance (Live)", "server:album")],
                                [album("server:album", "server", songs: 2)], [artist("server:artist", "server")])
        let merged = mergeCatalogs([phoneOnly, serverSide])
        #expect(merged.mergedIds["s1"] == "p1")
        #expect(merged.mergedIds["s2"] == "s2")
        #expect(merged.tracks.count == 3)
    }

    @Test func aDrumlessEditionIsItsOwnSongWhileAnAnniversaryCopyMerges() {
        let serverSide = server([track("s1", "server", "Hotline Bling (10th Anniversary Edition)", "server:album"),
                                 track("s2", "server", "One Dance (Drumless Edition)", "server:album")],
                                [album("server:album", "server", songs: 2)], [artist("server:artist", "server")])
        let merged = mergeCatalogs([phoneOnly, serverSide])
        #expect(merged.mergedIds["s1"] == "p1")
        #expect(merged.mergedIds["s2"] == "s2")
        #expect(merged.tracks.count == 3)
    }

    @Test func stylizedAndCurlyTitlesStillMerge() {
        let phoneSide = phone([track("p1", "device", "Huntin’ Wabbitz", "device:album"), track("p2", "device", "$UICIDE", "device:album")],
                              [album("device:album", "device")], [artist("device:artist", "device")])
        let serverSide = server([track("s1", "server", "Huntin' Wabbitz", "server:album"), track("s2", "server", "＄UICIDE", "server:album")],
                                [album("server:album", "server")], [artist("server:artist", "server")])
        let merged = mergeCatalogs([phoneSide, serverSide])
        #expect(merged.mergedIds["s1"] == "p1")
        #expect(merged.mergedIds["s2"] == "p2")
    }

    @Test func aGuestInTheCreditStillFindsTheSongElsewhere() {
        let single = with(track("s1", "server", "One Dance (feat. Wizkid & Kyla)", "server:single")) { $0.artist = "Drake feat. Wizkid" }
        let serverSide = server([single], [album("server:single", "server", title: "One Dance - Single", songs: 1)],
                                [artist("server:artist", "server")])
        #expect(mergeCatalogs([phoneOnly, serverSide]).mergedIds["s1"] == "p2")
    }

    @Test func namesMatchWithoutAccentsOrAnAmpersand() {
        #expect(matchKey("Beyoncé") == matchKey("BEYONCE"))
        #expect(matchKey("Simon & Garfunkel") == matchKey("Simon and Garfunkel"))
        #expect(matchKey("ＬＯＶＥ") == matchKey("Love"))
        #expect(matchKey("!!!") == "!!!")
        #expect(matchKey("÷") != matchKey("×"))
    }
}

/// Which copy each field of a merged song or album comes from.
@Suite struct MergeRulesTest {
    func copy(_ id: String, _ source: String, added: Int64 = 0, year: Int? = nil, originalYear: Int? = nil, artist: String = "Daft Punk",
              artists: [String] = [], genre: String = "", genres: [String] = [], composer: String? = nil,
              recording: String? = nil) -> SourceTrack {
        SourceTrack(id: id, sourceId: source, nativeId: id, title: "Get Lucky", searchKey: "get lucky", sortKey: "get lucky",
                    artist: artist, artistId: "\(source):artist", album: "RAM", albumId: "\(source):album", year: year,
                    durationMs: 369_000, addedAt: added, albumOrder: 0, relinkKey: "", genre: genre, originalYear: originalYear,
                    genres: joinLines(genres), artists: joinLines(artists), composer: composer, mbRecordingId: recording)
    }

    func album(_ source: String, _ added: Int64) -> SourceAlbum {
        SourceAlbum(id: "\(source):album", sourceId: source, nativeId: "a", title: "RAM", searchKey: "ram", sortKey: "ram",
                    artist: "Daft Punk", artistId: "\(source):artist", year: nil, songCount: 1, durationMs: 369_000, addedAt: added)
    }

    func artist(_ source: String) -> SourceArtist {
        SourceArtist(id: "\(source):artist", sourceId: source, name: "Daft Punk", searchKey: "daft punk", sortKey: "daft punk",
                     albumCount: 1, songCount: 1)
    }

    func merge(_ phone: SourceTrack, _ server: SourceTrack, _ phoneAlbumAdded: Int64 = 0, _ serverAlbumAdded: Int64 = 0) -> MergedCatalog {
        mergeCatalogs([
            SourceCatalog(sourceId: "device", onPhone: true, tracks: [phone], albums: [album("device", phoneAlbumAdded)], artists: [artist("device")]),
            SourceCatalog(sourceId: "server:x", onPhone: false, tracks: [server], albums: [album("server:x", serverAlbumAdded)],
                          artists: [artist("server:x")]),
        ])
    }

    @Test func theEarliestRealAddedTimeWins() {
        #expect(merge(copy("p", "device", added: 1_583_485_817), copy("s", "server:x", added: 1_786_000_000)).tracks.first?.addedAt == 1_583_485_817)
        #expect(merge(copy("p", "device", added: 0), copy("s", "server:x", added: 1_786_000_000)).tracks.first?.addedAt == 1_786_000_000)
    }

    @Test func albumsTakeTheEarliestAddedTimeToo() {
        #expect(merge(copy("p", "device"), copy("s", "server:x"), 1_786_000_000, 1_500_000_000).albums.first?.addedAt == 1_500_000_000)
        #expect(merge(copy("p", "device"), copy("s", "server:x"), 0, 1_500_000_000).albums.first?.addedAt == 1_500_000_000)
    }

    @Test func theOriginalYearFromAnyCopyIsShown() {
        #expect(merge(copy("p", "device", year: 2013), copy("s", "server:x", year: 2013, originalYear: 1979)).tracks.first?.year == 1979)
    }

    @Test func aYearFromAnyCopyFillsAGap() {
        #expect(merge(copy("p", "device"), copy("s", "server:x", year: 2013)).tracks.first?.year == 2013)
        #expect(merge(copy("p", "device"), copy("s", "server:x")).tracks.first?.year == nil)
    }

    @Test func theFullestCreditWins() {
        let merged = merge(copy("p", "device", artist: "Daft Punk", artists: ["Daft Punk"]),
                           copy("s", "server:x", artist: "Daft Punk feat. Pharrell Williams", artists: ["Daft Punk", "Pharrell Williams"]))
        #expect(merged.tracks.first?.artist == "Daft Punk feat. Pharrell Williams")
        let equal = merge(copy("p", "device", artist: "Daft Punk", artists: ["Daft Punk"]),
                          copy("s", "server:x", artist: "DAFT PUNK", artists: ["DAFT PUNK"]))
        #expect(equal.tracks.first?.artist == "Daft Punk")
    }

    @Test func theFirstCopysGenreIsTheMainOneAndAnotherFillsAGap() {
        #expect(merge(copy("p", "device", genre: "Disco"), copy("s", "server:x", genre: "Funk")).tracks.first?.genre == "Disco")
        #expect(merge(copy("p", "device"), copy("s", "server:x", genre: "Funk")).tracks.first?.genre == "Funk")
    }

    @Test func detailsComeFromEveryCopyPhoneFirst() {
        let details = songDetails([
            copy("s", "server:x", year: 2013, originalYear: 1979, genre: "Funk", genres: ["Funk", "Disco", "Hip-Hop"], composer: "Server",
                 recording: "rec-s"),
            copy("p", "device", year: 2014, genre: "Disco", genres: ["Disco", "Hip Hop", "Pop"], recording: "rec-p"),
        ])
        #expect(details.year == 2014)
        #expect(details.originalYear == 1979)
        #expect(details.genres == ["Disco", "Hip Hop", "Pop", "Funk"])
        #expect(details.composer == "Server")
        #expect(details.mbRecordingId == "rec-p")
    }

    @Test func aCopyWithOnlyAMainGenreStillCounts() {
        #expect(songDetails([copy("p", "device", genre: "Disco")]).genres == ["Disco"])
    }

    @Test func linesListsRoundTrip() {
        #expect(splitLines(joinLines(["a", "b"])) == ["a", "b"])
        #expect(splitLines(joinLines(nil)) == [])
        #expect(splitLines("") == [])
    }
}

/// Several servers are kept, one in use: only the phone's music and the server in use make the
/// library, so two servers' copies of a song never become one row.
@Suite struct LibrarySourcesTest {
    func source(_ id: String) -> SourceCatalog {
        SourceCatalog(
            sourceId: id, onPhone: id == "device",
            tracks: [SourceTrack(id: "\(id):1", sourceId: id, nativeId: "1", title: "Hotline Bling", searchKey: "hotline bling",
                                 sortKey: "hotline bling", artist: "Drake", artistId: "\(id):artist", album: "Views", albumId: "\(id):album",
                                 trackNo: 1, durationMs: 200_000, addedAt: 0)],
            albums: [SourceAlbum(id: "\(id):album", sourceId: id, nativeId: "album", title: "Views", searchKey: "views", sortKey: "views",
                                 artist: "Drake", artistId: "\(id):artist", songCount: 1, durationMs: 0, addedAt: 0)],
            artists: [SourceArtist(id: "\(id):artist", sourceId: id, name: "Drake", searchKey: "drake", sortKey: "drake", albumCount: 1, songCount: 1)])
    }

    @Test func onlyTheServerInUseJoinsThePhonesMusic() {
        #expect(inLibrary("device", serverInUse: "server:home.test"))
        #expect(inLibrary("server:home.test", serverInUse: "server:home.test"))
        #expect(!inLibrary("server:work.test", serverInUse: "server:home.test"))
        #expect(inLibrary("device", serverInUse: nil))
        #expect(!inLibrary("server:home.test", serverInUse: nil))
    }

    @Test func twoServersCopiesOfASongAreNeverOneRow() throws {
        let all = ["device", "server:home.test", "server:work.test"].map(source)
        let merged = mergeCatalogs(all.filter { inLibrary($0.sourceId, serverInUse: "server:work.test") })
        let song = try #require(merged.tracks.first)
        #expect(merged.tracks.count == 1)
        #expect(song.id == "device:1")
        #expect(merged.mergedIds["server:work.test:1"] == "device:1")
        #expect(merged.mergedIds["server:home.test:1"] == nil)
    }

    @Test func withNoServerInUseTheLibraryIsThePhonesOwn() {
        let all = ["server:home.test", "server:work.test"].map(source)
        #expect(mergeCatalogs(all.filter { inLibrary($0.sourceId, serverInUse: nil) }).tracks.isEmpty)
    }
}
