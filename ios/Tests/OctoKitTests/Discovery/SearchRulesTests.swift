import Foundation
import Testing
@testable import OctoKit

private func topEntry(_ rank: Int, plays: Int? = nil) -> TopSong {
    var json = "{\"rank\":\(rank)"
    if let plays { json += ",\"plays\":\(plays)" }
    json += "}"
    return try! JSONDecoder().decode(TopSong.self, from: Data(json.utf8))
}

private func album(_ name: String, songs: Int, owned: Int?, external: Bool = true) -> Album {
    var album = Album(id: name, name: name, artist: "Drake")
    album.songCount = songs
    album.isExternal = external
    album.ownedCount = owned
    return album
}

private func artist(_ id: String, _ name: String) -> Artist {
    try! JSONDecoder().decode(Artist.self, from: Data("{\"id\":\"\(id)\",\"name\":\"\(name)\"}".utf8))
}

@Suite struct RecentSearchesTests {
    @Test func theNewestSearchComesFirst() {
        #expect(withRecent(withRecent([], "drake"), "sza") == ["sza", "drake"])
    }

    @Test func searchingAgainMovesItToTheTopOnce() {
        // Kept as typed the last time.
        #expect(withRecent(["sza", "drake", "adele"], "Drake") == ["Drake", "sza", "adele"])
    }

    @Test func onlyTheNewestTenAreKept() {
        let recent = (1...12).reduce([String]()) { withRecent($0, "q\($1)") }
        #expect(recent.count == recentSearchesKept)
        #expect(recent.first == "q12")
        #expect(recent.last == "q3")
    }

    @Test func spacesAreTidiedAndBlankSearchesIgnored() {
        #expect(withRecent([], "  frank   ocean ") == ["frank ocean"])
        #expect(withRecent(["a b"], "   ") == ["a b"])
        #expect(withRecent(["frank ocean"], "frank  ocean") == ["frank ocean"])
    }

    @Test func oneCanBeForgotten() {
        #expect(withoutRecent(["sza", "drake", "adele"], "DRAKE") == ["sza", "adele"])
    }

    @Test func theyReadBackInTheSameOrder() {
        let recent = ["sza", "drake", "a  b"]
        #expect(decodeRecent(encodeRecent(recent)) == recent)
        #expect(decodeRecent(nil) == [])
        #expect(decodeRecent("") == [])
    }
}

@Suite struct TopSongRulesTests {
    private let artists = ["Daft Punk Tribute Band", "Daft Punk", "The Weeknd", "Bob Marley & The Wailers"]

    @Test func theArtistSearchedForIsTheOneNamedWhole() {
        #expect(searchedArtist("daft punk", artists) { $0 } == "Daft Punk")
        #expect(searchedArtist("  DAFT PUNK ", artists) { $0 } == "Daft Punk")
        #expect(searchedArtist("weeknd", artists) { $0 } == "The Weeknd")
        #expect(searchedArtist("the weeknd", artists) { $0 } == "The Weeknd")
    }

    @Test func aPartOfANameOrASongIsNoArtist() {
        #expect(searchedArtist("daft", artists) { $0 } == nil)
        #expect(searchedArtist("bob marley", artists) { $0 } == nil)
        #expect(searchedArtist("get lucky", artists) { $0 } == nil)
        #expect(searchedArtist("", artists) { $0 } == nil)
    }

    @Test func playsAreShort() {
        #expect(playsText(1) == "1 play")
        #expect(playsText(940) == "940 plays")
        #expect(playsText(1_000) == "1K plays")
        #expect(playsText(1_460) == "1.5K plays")
        #expect(playsText(12_345) == "12K plays")
        #expect(playsText(12_960) == "13K plays")
        #expect(playsText(2_536_925) == "2.5M plays")
        #expect(playsText(999_960) == "1M plays")
        #expect(playsText(119_800_000) == "120M plays")
        #expect(playsText(1_234_000_000) == "1.2B plays")
    }

    @Test func theRankingIsNamed() {
        #expect(rankedBy(topSongsLastFm) == "Most played on Last.fm")
        #expect(rankedBy(topSongsDeezer) == "Most popular on Deezer")
        #expect(rankedBy("") == nil)
    }

    @Test func appleListsSayWhichKindTheyAre() {
        #expect(rankedBy("apple") == "Most played on Apple Music")
        #expect(rankedBy("apple", chart: "18") == "Most played on Apple Music")
        #expect(rankedBy("apple", chart: "new") == "Picked by Apple Music")
        #expect(rankedBy("apple", chart: "trending") == "Trending on Apple Music")
        #expect(rankedBy("deezer", chart: "34") == "Most popular on Deezer")
    }

    @Test func roomsHoldAHundredChartsFifty() {
        #expect(chartSongs("new") == 100)
        #expect(chartSongs("trending") == 100)
        #expect(chartSongs("34") == 50)
        #expect(chartSongs("18") == 50)
    }

    @Test func theChartsPageNeedsTheSecondVersion() {
        #expect(!chartsOffered(["octoTopSongs:1"]))
        #expect(chartsOffered(["octoTopSongs:1", "octoTopSongs:2"]))
        #expect(!chartsOffered([]))
    }

    @Test func theLibrarysArtistComesFirstThenTheServersFind() {
        let library = [artist("ar1", "Daft Punk Tribute"), artist("ar2", "Daft Punk")]
        let online = [artist("ext7", "Daft Punk"), artist("ext8", "Justice")]
        #expect(namedArtist("daft punk", library: library, online: online) == NamedArtist(name: "Daft Punk", libraryId: "ar2"))
        #expect(namedArtist("justice", library: library, online: online) == NamedArtist(name: "Justice", serverId: "ext8"))
        #expect(namedArtist("daft", library: library, online: online) == nil)
    }

    @Test func aRankStaysWithItsSong() {
        let entries = [topEntry(1, plays: 9_000_000), topEntry(2), topEntry(3, plays: 6_000_000), topEntry(4), topEntry(0)]
        let tracks: [String?] = ["lib1", nil, "find3", "lib1", "lib5"]
        let ranked = rankTracks(entries, tracks) { $0 }
        // A library song gone is left out; a find that became a song listed above it stands
        // once, at the better place; no rank takes its place.
        #expect(ranked.map(\.track) == ["lib1", "find3", "lib5"])
        #expect(ranked.map(\.rank) == [1, 3, 5])
        #expect(ranked.map(\.plays) == [9_000_000, 6_000_000, nil])
    }

    @Test func libraryOnlyKeepsEachSongAtItsOwnRank() {
        let list = RankedSongs(artist: nil, source: "lastfm", songs: [
            RankedSong(rank: 1, track: "find:a", plays: nil), RankedSong(rank: 2, track: "b", plays: nil),
        ])
        let kept = list.inLibraryOnly { $0.hasPrefix("find:") }
        #expect(kept?.songs.map(\.rank) == [2])
        #expect(RankedSongs(artist: nil, source: "", songs: [RankedSong(rank: 1, track: "find:a", plays: nil)])
            .inLibraryOnly { $0.hasPrefix("find:") } == nil)
    }
}

@Suite struct AlbumShareTests {
    @Test func anAlbumHeldInPartSaysHowMuch() {
        let wattba = album("What A Time To Be Alive", songs: 11, owned: 2)
        #expect(albumShare(wattba) == .part)
        #expect(albumShareLine(wattba) == "2 of 11 in your library")
    }

    @Test func thePhonesOwnAlbumsSayItFromTheCounts() {
        #expect(albumShareLine(owned: 20, songs: 21) == "20 of 21 in your library")
        #expect(albumShareLine(owned: 0, songs: 14) == nil)
        #expect(albumShareLine(owned: 11, songs: 11) == nil)
        #expect(albumShareLine(owned: nil, songs: 11) == nil)
    }

    @Test func noneAndWholeHaveNoLine() {
        #expect(albumShare(album("MAID OF HONOUR", songs: 14, owned: 0)) == AlbumShare.none)
        #expect(albumShareLine(album("MAID OF HONOUR", songs: 14, owned: 0)) == nil)
        #expect(albumShare(album("HABIBTI", songs: 11, owned: 11)) == .whole)
        #expect(albumShareLine(album("HABIBTI", songs: 11, owned: 11)) == nil)
    }

    @Test func uncountedAndLibraryAlbumsHaveNoShare() {
        #expect(albumShare(album("$ome $exy $ongs 4 U", songs: 21, owned: nil)) == nil)
        #expect(albumShare(album("HABIBTI (FOMO)", songs: 15, owned: 15, external: false)) == nil)
    }

    @Test func theServersFieldsAreReadAndAnOlderServerLeavesThemOut() throws {
        let counted = try JSONDecoder().decode(Album.self, from: Data(
            #"{"id":"x","name":"What A Time To Be Alive","songCount":11,"isExternal":true,"ownedCount":2}"#.utf8))
        #expect(albumShareLine(counted) == "2 of 11 in your library")
        let older = try JSONDecoder().decode(Album.self, from: Data(
            #"{"id":"x","name":"What A Time To Be Alive","songCount":11,"isExternal":true}"#.utf8))
        #expect(albumShare(older) == nil)
    }

    @Test func onlyLibrarySongsStayInTheirOrder() {
        let songs = ["a", "find:b", "c", "find:d"]
        #expect(librarySongsOnly(songs, hide: true) { $0.hasPrefix("find:") } == ["a", "c"])
        #expect(librarySongsOnly(songs, hide: false) { $0.hasPrefix("find:") } == songs)
    }

    @Test func theWordsHaveNoDashes() {
        for words in [LibraryOnlyWords.setting, LibraryOnlyWords.help, LibraryOnlyWords.onlyMySongs] {
            #expect(!words.unicodeScalars.contains { $0.value == 0x2014 || $0.value == 0x2013 })
        }
    }
}

@Suite struct SearchSectionsTests {
    private func song(_ id: String, external: Bool = true) -> Song { Song(id: id, title: id, isExternal: external) }

    @Test func capsFollowTheFilter() {
        #expect(searchCaps(.all) == SearchCaps(artists: 10, albums: 20, songs: 50, playlists: 10))
        #expect(searchCaps(.songs).songs == 1_000)
        #expect(searchCaps(.albums).albums == 500)
        #expect(searchCaps(.artists).artists == 500)
        #expect(searchCaps(.playlists).playlists == 500)
        #expect(SearchFilter.allCases.map(\.label) == ["All", "Songs", "Albums", "Artists", "Playlists"])
    }

    @Test func aSongAddedWhileShownStaysAmongTheFindsUntilTheNextSearch() {
        let found = Discovered(songs: [song("e1"), song("e2")])
        // The library was searched before the song arrived: nothing listed yet.
        #expect(found.without(listedFinds([:], songIds: ["t-1"])).songs.map(\.id) == ["e1", "e2"])
    }

    @Test func aRebuildListsTheAddedSongOnceAsTheLibrarySong() {
        let adoptions = ["e1": "t-9"]
        let found = Discovered(songs: [song("e1"), song("e2")])
        let listed = listedFinds(adoptions, songIds: ["t-9"])
        #expect(listed == ["e1"])
        #expect(found.without(listed).songs.map(\.id) == ["e2"])
    }

    @Test func aFindWhoseLibrarySongIsNotListedStays() {
        let listed = listedFinds(["e1": "t-9"], songIds: ["t-1"])
        #expect(listed.isEmpty)
        #expect(Discovered(songs: [song("e1")]).without(listed).songs.map(\.id) == ["e1"])
    }

    @Test func albumsHeldInPartStayApartFromTheFinds() {
        let wattba = album("What A Time To Be Alive", songs: 11, owned: 2)
        let partOnly = Discovered(partAlbums: [wattba])
        #expect(partOnly.notInLibraryEmpty)
        #expect(!partOnly.isEmpty)
    }

    @Test func eachFilterShowsItsOwnFinds() {
        let found = Discovered(songs: [song("s")], albums: [album("a", songs: 3, owned: 0)], artists: [artist("ext-1", "x")],
                               partAlbums: [album("p", songs: 3, owned: 1)])
        #expect(found.only(.playlists) == nil)
        #expect(found.only(.songs)?.songs.count == 1 && found.only(.songs)?.albums.isEmpty == true)
        #expect(found.only(.albums)?.partAlbums.count == 1 && found.only(.albums)?.songs.isEmpty == true)
        #expect(found.only(.artists)?.artists.count == 1 && found.only(.artists)?.partAlbums.isEmpty == true)
        #expect(found.only(.all)?.songs.count == 1)
    }

    @Test func searchSortsTheServersAnswer() throws {
        let answer = try JSONDecoder().decode(SearchResult.self, from: Data("""
        {"artist":[{"id":"ar1","name":"Drake"},{"id":"ext-deezer-artist-9","name":"Drake & Future"},
                   {"id":"ext-deezer-artist-10","name":"DRAKE"}],
         "album":[{"id":"al1","name":"Views","artist":"Drake"},
                  {"id":"ext-a1","name":"Views (Deluxe)","artist":"Drake","isExternal":true,"songCount":20,"ownedCount":0},
                  {"id":"ext-a2","name":"What A Time To Be Alive","artist":"Drake","isExternal":true,"songCount":11,"ownedCount":2},
                  {"id":"ext-a3","name":"Take Care","artist":"Drake","isExternal":true,"songCount":18,"ownedCount":18},
                  {"id":"ext-a4","name":"Scorpion","artist":"Drake","isExternal":true,"songCount":25}],
         "song":[{"id":"s1","title":"Hotline Bling"},{"id":"ext-s2","title":"Jumbotron","isExternal":true}]}
        """.utf8))
        let library = SearchResult(artist: answer.artist.filter { !isOnlineId($0.id) }, album: answer.album.filter { !$0.isExternal })
        let found = discovered(from: answer, libraryAlbums: library.album, libraryArtists: library.artist) { $0.isExternal }
        #expect(found.songs.map(\.id) == ["ext-s2"])
        // "Views (Deluxe)" names the library's "Views" once its brackets are left out.
        #expect(found.albums.map(\.id) == ["ext-a4"])
        #expect(found.partAlbums.map(\.id) == ["ext-a2"])
        // The library's Drake is the same name as the server's DRAKE.
        #expect(found.artists.map(\.id) == ["ext-deezer-artist-9"])
    }

    @Test func theAddHintShowsTheFirstFiveTimes() {
        for shown in 0..<addHintShowings { #expect(showsAddHint(AddHintState(shown: shown), countedThisVisit: false)) }
        #expect(!showsAddHint(AddHintState(shown: 5), countedThisVisit: false))
        #expect(!showsAddHint(AddHintState(shown: 9), countedThisVisit: false))
        // The fifth showing stays for the rest of its visit.
        #expect(showsAddHint(AddHintState(shown: 5), countedThisVisit: true))
        // It stops once a song is added, even on the visit that counted it.
        #expect(!showsAddHint(AddHintState(shown: 0, added: true), countedThisVisit: false))
        #expect(!showsAddHint(AddHintState(shown: 1, added: true), countedThisVisit: true))
    }
}

@Suite struct NotInLibraryTests {
    private func song(_ id: String, external: Bool) -> Song { Song(id: id, title: id, isExternal: external) }

    @Test func onlyASongFoundOnlineAndNotYetInTheLibraryIsMarked() {
        #expect(isOutsideLibrary(song("e1", external: true), adopted: []))
        #expect(!isOutsideLibrary(song("t-42", external: false), adopted: []))
        // Downloaded into the library since: the mark goes.
        #expect(!isOutsideLibrary(song("e1", external: true), adopted: ["e1"]))
        #expect(isOutsideLibrary(song("e2", external: true), adopted: ["e1"]))
        #expect(!isOutsideLibrary(nil, adopted: []))
    }

    @Test func addingAnAlbumsMissingSongsSaysHowMany() {
        #expect(addMissingLabel(1) == "Add the missing song")
        #expect(addMissingLabel(9) == "Add the 9 missing songs")
        #expect(albumLibraryNote(songs: 11, outside: 9) == "2 of 11 in your library")
    }

    @Test func aRowThatOffersAddingShowsTheButtonAndNoMark() {
        #expect(rowAddSign(isFind: true, adopted: false, offersAdd: true) == .button)
        // Kept once added, so its check shows before the page swaps the row.
        #expect(rowAddSign(isFind: true, adopted: true, offersAdd: true) == .button)
        #expect(rowAddSign(isFind: false, adopted: false, offersAdd: true) == AddSign.none)
    }

    @Test func aRowElsewhereShowsTheMarkUntilTheSongIsAdded() {
        #expect(rowAddSign(isFind: true, adopted: false, offersAdd: false) == .mark)
        #expect(rowAddSign(isFind: true, adopted: true, offersAdd: false) == AddSign.none)
        #expect(rowAddSign(isFind: false, adopted: false, offersAdd: false) == AddSign.none)
    }

    @Test func rowsBesideAddButtonsKeepTheirSpace() {
        #expect(rowKeepsAddSpace(.none, librarySpace: true))
        #expect(!rowKeepsAddSpace(.button, librarySpace: true))
        #expect(!rowKeepsAddSpace(.none, librarySpace: false))
        #expect(!rowKeepsAddSpace(.mark, librarySpace: false))
    }

    private func end(find: Bool, adopted: Bool = false, offersAdd: Bool, librarySpace: Bool? = nil, hasTrailing: Bool = false) -> RowEnd {
        rowEnd(rowAddSign(isFind: find, adopted: adopted, offersAdd: offersAdd), librarySpace: librarySpace ?? offersAdd,
               hasTrailing: hasTrailing)
    }

    @Test func aFindThatBecameALibrarySongEndsLikeTheListsLibrarySongs() {
        #expect(end(find: false, offersAdd: false) == end(find: false, offersAdd: true, librarySpace: false))
        #expect(end(find: false, offersAdd: true, librarySpace: false) == .trailing)
        #expect(end(find: true, offersAdd: true, librarySpace: false) == .addButton)
        #expect(end(find: true, adopted: true, offersAdd: true, librarySpace: false) == .addButton)
        #expect(end(find: false, offersAdd: true) == .addSpace)
        #expect(end(find: false, offersAdd: false, hasTrailing: true) == .trailing)
        #expect(end(find: false, offersAdd: true, hasTrailing: true) == .trailing)
    }

    @Test func theMarkScalesWithTheArtworkWithinItsBounds() {
        #expect(abs(notInLibraryMarkSize(150) - 18.75) < 0.01)
        #expect(abs(notInLibraryMarkSize(120) - 15) < 0.01)
        #expect(notInLibraryMarkSize(44) == 12)
        #expect(notInLibraryMarkSize(36) == 12)
        #expect(notInLibraryMarkSize(240) == 20)
        #expect(notInLibraryMarkSize(400) == 20)
    }

    @Test func onASquareCoverTheMarkSitsJustInFromTheCorner() {
        #expect(abs(notInLibraryMarkInset(150, mark: 18.75, round: false) - 6) < 0.01)
        #expect(abs(notInLibraryMarkInset(44, mark: 12, round: false) - 3) < 0.01)
    }

    @Test func onARoundPictureTheWholeMarkStaysInsideTheCircle() {
        for art in [36.0, 48, 96, 160] {
            let mark = notInLibraryMarkSize(art)
            let inset = notInLibraryMarkInset(art, mark: mark, round: true)
            let radius = art / 2
            let center = art - inset - mark / 2
            let fromMiddle = 2.0.squareRoot() * (center - radius)
            #expect(fromMiddle + mark / 2 <= radius + 1e-9)
            #expect(center > radius)
            #expect(inset > 0)
        }
    }

    @Test func screenReadersHearWhatIsNotInTheLibrary() {
        #expect(artworkDescription(nil, outside: false) == nil)
        #expect(artworkDescription(nil, outside: true) == "Not in your library")
        #expect(artworkDescription("Cover", outside: true) == "Cover, not in your library")
        #expect(artworkDescription("Cover", outside: false) == "Cover")
    }

    @Test func anAlbumPageSaysHowMuchIsInTheLibrary() {
        #expect(albumLibraryNote(songs: 7, outside: 7) == nil)
        #expect(albumLibraryNote(songs: 7, outside: 4) == "3 of 7 in your library")
        #expect(albumLibraryNote(songs: 7, outside: 0) == nil)
    }

    @Test func aFindsOwnAlbumTitleIsLeftOffItsRow() {
        var single = Song(id: "e1", title: "Nightcall", artist: "Kavinsky", album: "nightcall ", isExternal: true)
        #expect(rowAlbum(single) == "")
        #expect(songSubtitle(single) == "Kavinsky")
        single.isExternal = false
        #expect(songSubtitle(single) == "Kavinsky • nightcall ")
    }
}

@Suite struct FindSwapTests {
    private func faces(_ adopted: Bool?..., offersAdd: Bool = true) -> [FindFace?] {
        var face: FindFace?
        return adopted.map { known in
            face = nextFindFace(face, adopted: known, offersAdd: offersAdd)
            return face
        }
    }

    @Test func aFindAddedInViewShowsTheCheckThenTheLibrarySong() {
        #expect(faces(false, false, true, true) == [.find, .find, .check, .check])
        #expect(afterCheck(.check) == .library)
        #expect(nextFindFace(.library, adopted: true, offersAdd: true) == .library)
        #expect(swapFadeMs(sawFind: true, calm: false) == swapFadeDurationMs)
        #expect(checkHoldMs + swapFadeDurationMs == 1_500)
    }

    @Test func aSongAlreadyInTheLibraryOpensAsTheLibrarySong() {
        #expect(faces(true, true) == [.library, .library])
        #expect(swapFadeMs(sawFind: false, calm: false) == 0)
    }

    @Test func nothingIsDecidedUntilTheLibraryIsKnown() {
        #expect(faces(nil, true) == [nil, .library])
        #expect(faces(nil, false) == [nil, .find])
        #expect(afterCheck(nil) == nil)
    }

    @Test func aRowWithoutTheAddButtonTurnsAtOnce() {
        #expect(faces(false, true, offersAdd: false) == [.find, .library])
    }

    @Test func reducedMotionKeepsTheCheckAndSwapsWithoutAFade() {
        #expect(faces(false, true) == [.find, .check])
        #expect(afterCheck(.check) == .library)
        #expect(swapFadeMs(sawFind: true, calm: true) == 0)
    }

    @Test func onlyTheCheckMovesOnWhenItsMomentEnds() {
        #expect(afterCheck(.find) == .find)
        #expect(afterCheck(.library) == .library)
    }
}

@Suite struct ChartsCaptionTests {
    private let english = Locale(identifier: "en_US")

    @Test func aChartSaysWhoRankedItAndForWhichCountry() {
        #expect(chartCaption(source: "apple", chart: "34", country: "us", locale: english) == "Most played on Apple Music in United States")
        #expect(chartCaption(source: "apple", chart: "new", country: "gb", locale: english) == "Picked by Apple Music in United Kingdom")
        #expect(chartCaption(source: "apple", chart: "trending", country: "jp", locale: english) == "Trending on Apple Music in Japan")
    }

    @Test func withoutACountryOnlyWhoRankedIt() {
        #expect(chartCaption(source: "deezer", chart: "34", country: nil, locale: english) == "Most popular on Deezer")
        #expect(chartCaption(source: "apple", chart: "18", country: "usa", locale: english) == "Most played on Apple Music")
    }

    @Test func aListNobodyRankedSaysNothing() {
        #expect(chartCaption(source: "", chart: "34", country: "us", locale: english) == nil)
    }
}

@Suite struct AlbumHighlightTests {
    private func track(_ id: String, _ title: String, _ artist: String = "Drake") -> (id: String, title: String, artist: String) {
        (id, title, artist)
    }

    private var album: [(id: String, title: String, artist: String)] {
        [track("t1", "Rusty Intro"), track("t2", "WNBA"), track("t3", "Gen 5"), track("t4", "Quebec")]
    }

    @Test func theAlbumSongFirstInTheArtistsTopSongsIsTheMainOne() {
        let ranked = [TopSongRef(id: "x1", title: "Hotline Bling", artist: "Drake"), TopSongRef(id: "t3", title: "Gen 5", artist: "Drake"),
                      TopSongRef(id: "t2", title: "WNBA", artist: "Drake")]
        #expect(albumHighlight(album, ranked) == "t3")
    }

    @Test func aSongTheRankingKnowsByAnotherIdIsMatchedByTitleAndArtist() {
        #expect(albumHighlight(album, [TopSongRef(id: "online-9", title: "Quebec (feat. Future)", artist: "Drake")]) == "t4")
    }

    @Test func aGuestCreditInsideAVersionTagStillFindsThatVersion() {
        let tracks = [track("t1", "Get Lucky"), track("t2", "Get Lucky (Radio Edit)")]
        #expect(albumHighlight(tracks, [TopSongRef(id: "online-1", title: "Get Lucky (Radio Edit - feat. Pharrell Williams)", artist: "Drake")]) == "t2")
        #expect(albumHighlight(tracks, [TopSongRef(id: "online-2", title: "Get Lucky feat. Pharrell Williams", artist: "Drake")]) == "t1")
    }

    @Test func theSameTitleByAnotherArtistIsNotTheAlbumsSong() {
        #expect(albumHighlight(album, [TopSongRef(id: "z9", title: "Quebec", artist: "Someone Else")]) == nil)
    }

    @Test func noAlbumSongAmongTheTopSongsMeansNoStar() {
        #expect(albumHighlight(album, [TopSongRef(id: "x1", title: "Hotline Bling", artist: "Drake")]) == nil)
        #expect(albumHighlight(album, []) == nil)
    }
}
