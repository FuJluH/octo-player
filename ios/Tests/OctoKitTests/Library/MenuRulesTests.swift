import Foundation
import Testing
@testable import OctoKit

@Suite struct SongActionsTests {
    @Test func aLibrarySongOffersFindInFlacWhenTheServerCan() {
        #expect(songActions(find: false, radio: true, upgrade: true)
            == [.playNext, .addToQueue, .startRadio, .addToPlaylist, .findFlac, .like, .rate, .goToAlbum, .goToArtist, .info])
        #expect(songMenuGroups(songActions(find: false, radio: true, offline: true, upgrade: true))[1]
            == [.addToPlaylist, .like, .rate, .keepOffline, .findFlac])
    }

    @Test func findSongsComesAfterTheInfoForFoundAndLibrarySongsAlike() {
        #expect(songActions(find: true, radio: false, findSongs: true) == [.playNext, .addToQueue, .download, .info, .findSongs])
        #expect(songMenuGroups(songActions(find: false, radio: false, findSongs: true))[3] == [.info, .findSongs])
        #expect(!songActions(find: false, radio: true).contains(.findSongs))
    }

    @Test func aSongFoundOnlineNeverOffersFindInFlac() {
        #expect(songActions(find: true, radio: false, upgrade: true) == [.playNext, .addToQueue, .download, .info])
    }

    @Test func aLibrarySongOffersEverything() {
        #expect(songActions(find: false, radio: true)
            == [.playNext, .addToQueue, .startRadio, .addToPlaylist, .like, .rate, .goToAlbum, .goToArtist, .info])
    }

    @Test func theLastPlaylistComesFirstAmongTheWaysToKeepASong() {
        let actions = songActions(find: false, radio: true, lastPlaylist: true)
        #expect(actions == [.playNext, .addToQueue, .startRadio, .addToLastPlaylist, .addToPlaylist, .like, .rate, .goToAlbum, .goToArtist, .info])
        #expect(songMenuGroups(actions)[1] == [.addToLastPlaylist, .addToPlaylist, .like, .rate])
        #expect(songActions(find: true, radio: false, lastPlaylist: true) == [.playNext, .addToQueue, .download, .info])
    }

    @Test func radioNeedsAServer() {
        #expect(songActions(find: false, radio: false) == [.playNext, .addToQueue, .addToPlaylist, .like, .rate, .goToAlbum, .goToArtist, .info])
    }

    @Test func shareFollowsAPlaylistWhenTheSongIsOnAServerThatShares() {
        #expect(songActions(find: false, radio: true, share: true)
            == [.playNext, .addToQueue, .startRadio, .addToPlaylist, .share, .like, .rate, .goToAlbum, .goToArtist, .info])
        #expect(songActions(find: true, radio: true, share: true) == [.playNext, .addToQueue, .startRadio, .download, .info])
    }

    @Test func aSongWithAPhoneFileCanShareRingOrDeleteIt() {
        #expect(songActions(find: false, radio: true, phone: true)
            == [.playNext, .addToQueue, .startRadio, .addToPlaylist, .shareFile, .like, .rate, .goToAlbum, .goToArtist, .setAsSound,
                .deleteFromPhone, .info])
        #expect(songActions(find: false, radio: false, share: true, phone: true)
            == [.playNext, .addToQueue, .addToPlaylist, .shareFile, .share, .like, .rate, .goToAlbum, .goToArtist, .setAsSound,
                .deleteFromPhone, .info])
    }

    @Test func aSongOnlyOnAServerHasNoFileToShareRingOrDelete() {
        #expect(songActions(find: false, radio: false, share: true, offline: true, phone: false)
            == [.playNext, .addToQueue, .addToPlaylist, .keepOffline, .share, .like, .rate, .goToAlbum, .goToArtist, .info])
    }

    @Test func aFindOffersADownloadInsteadOfLibraryChoices() {
        #expect(songActions(find: true, radio: true) == [.playNext, .addToQueue, .startRadio, .download, .info])
        #expect(songActions(find: true, radio: false, phone: true) == [.playNext, .addToQueue, .download, .info])
        #expect(songActions(find: true, radio: false, offline: true) == [.playNext, .addToQueue, .download, .info])
    }

    @Test func tappingAStarSetsTheRatingAndTappingItAgainClearsIt() {
        #expect(nextRating(current: 0, tapped: 4) == 4)
        #expect(nextRating(current: 4, tapped: 2) == 2)
        #expect(nextRating(current: 4, tapped: 4) == 0)
        #expect(starsLabel(0) == nil)
        #expect(starsLabel(1) == "1 star")
        #expect(starsLabel(4) == "4 stars")
    }

    @Test func theKeepRowSaysWhereTheSongIs() {
        #expect(keepOfflineLabel(nil, byHand: false) == "Download")
        #expect(keepOfflineLabel(.queued, byHand: true) == "Waiting to download")
        #expect(keepOfflineLabel(.downloading, byHand: true) == "Downloading")
        #expect(keepOfflineLabel(.done, byHand: true) == "Remove download")
        #expect(keepOfflineLabel(.done, byHand: false) == "Kept downloaded")
        #expect(keepOfflineLabel(.failed, byHand: false) == "Download failed, try again")
        #expect(keepOfflineEnabled(nil, byHand: false))
        #expect(!keepOfflineEnabled(.done, byHand: false))
        #expect(keepOfflineEnabled(.done, byHand: true))
        #expect(!keepOfflineEnabled(.downloading, byHand: true))
        #expect(keepOfflineEnabled(.failed, byHand: false))
    }

    @Test func theAddRowSaysWhereTheSongIs() {
        #expect(downloadLabel(.none) == "Add to your library")
        #expect(downloadLabel(.requested) == "Adding to your library")
        #expect(downloadLabel(.done) == "In your library")
    }

    @Test func deleteFromDiskIsLastAndOnlyForALibrarySongTheServerLetsGo() {
        let actions = songActions(find: false, radio: false, phone: true, disk: true)
        #expect(Array(actions.suffix(4)) == [.setAsSound, .deleteFromPhone, .deleteFromDisk, .info])
        #expect(songMenuGroups(actions).last == [.deleteFromPhone, .deleteFromDisk])
        #expect(!songActions(find: true, radio: false, disk: true).contains(.deleteFromDisk))
        #expect(!songActions(find: false, radio: false).contains(.deleteFromDisk))
    }

    @Test func aFamilyMemberWhoAsksGetsRequestACopyBesideTheAdd() {
        #expect(songActions(find: true, radio: false, requestCopy: true) == [.playNext, .addToQueue, .download, .requestCopy, .info])
        #expect(songMenuGroups(songActions(find: true, radio: false, requestCopy: true))[1] == [.download, .requestCopy])
        #expect(!songActions(find: false, radio: false, requestCopy: true).contains(.requestCopy))
    }

    @Test func aManagedMemberCanTakeALibrarySongOutOfTheirOwnLibrary() {
        #expect(songMenuGroups(songActions(find: false, radio: false, disk: true, removeFromMine: true)).last
            == [.removeFromMyLibrary, .deleteFromDisk])
        #expect(!songActions(find: true, radio: false, removeFromMine: true).contains(.removeFromMyLibrary))
    }
}

@Suite struct MenuGroupsTests {
    @Test func aLibrarySongGroupsPlayingKeepingGoingAndLooking() {
        #expect(songMenuGroups(songActions(find: false, radio: true))
            == [[.playNext, .addToQueue, .startRadio], [.addToPlaylist, .like, .rate], [.goToAlbum, .goToArtist], [.info]])
    }

    @Test func whatTakesASongAwayComesLast() {
        let actions = songActions(find: false, radio: false, share: true, offline: true,
                                  place: MenuPlace(inPlaylist: true, selectable: true), phone: true)
        #expect(songMenuGroups(actions) == [
            [.playNext, .addToQueue], [.addToPlaylist, .like, .rate, .keepOffline], [.goToAlbum, .goToArtist],
            [.share, .shareFile, .setAsSound, .info, .select], [.removeFromPlaylist, .deleteFromPhone],
        ])
    }

    @Test func aFoundSongHasNoEmptyGroups() {
        #expect(songMenuGroups(songActions(find: true, radio: true)) == [[.playNext, .addToQueue, .startRadio], [.download], [.info]])
    }

    @Test func everySongActionHasAGroupAndOnlyOne() {
        let grouped = songMenuGroups(SongAction.allCases).flatMap { $0 }
        #expect(grouped.count == SongAction.allCases.count)
        #expect(Set(grouped.map { "\($0)" }) == Set(SongAction.allCases.map { "\($0)" }))
    }

    @Test func groupingKeepsOnlyWhatIsOffered() {
        #expect(songMenuGroups([.info]) == [[.info]])
        #expect(songMenuGroups([]).isEmpty)
    }

    @Test func aCollectionGroupsPlayingKeepingHomeAndGoing() {
        #expect(collectionMenuGroups(albumActions(canDownload: true))
            == [[.play, .shuffle, .playNext, .addToQueue], [.addToPlaylist, .addToFavorites, .download], [.pinToHome], [.goToArtist]])
        #expect(collectionMenuGroups(albumActions(canDownload: true, lossy: 4))[1] == [.addToPlaylist, .addToFavorites, .download, .findFlac])
    }

    @Test func aPlaylistPutsRenameAndDeleteLast() {
        #expect(collectionMenuGroups(playlistActions(empty: true, pin: .first)) == [[.unpin], [.rename, .duplicate, .delete]])
    }

    @Test func everyCollectionActionHasAGroupAndOnlyOne() {
        let grouped = collectionMenuGroups(CollectionAction.allCases).flatMap { $0 }
        #expect(grouped.count == CollectionAction.allCases.count)
    }
}

@Suite struct MenuPlaceTests {
    private func place(_ context: SongMenuContext) -> MenuPlace { menuPlace(context, albumId: "album:1", artistId: "artist:1") }

    @Test func anywhereElseLeadsToTheAlbumAndTheArtist() {
        #expect(place(SongMenuContext()) == MenuPlace())
    }

    @Test func onItsOwnAlbumPageThereIsNoGoingToTheAlbum() {
        let here = place(SongMenuContext(albumId: "album:1"))
        #expect(here.onAlbumPage)
        #expect(songActions(find: false, radio: false, place: here) == [.playNext, .addToQueue, .addToPlaylist, .like, .rate, .goToArtist, .info])
    }

    @Test func onItsOwnArtistPageThereIsNoGoingToTheArtist() {
        let here = place(SongMenuContext(artistId: "artist:1"))
        #expect(songActions(find: false, radio: false, place: here) == [.playNext, .addToQueue, .addToPlaylist, .like, .rate, .goToAlbum, .info])
    }

    @Test func anotherAlbumsOrArtistsPageStillLeadsThere() {
        let elsewhere = place(SongMenuContext(albumId: "album:2", artistId: "artist:2"))
        #expect(!elsewhere.onAlbumPage)
        #expect(!elsewhere.onArtistPage)
    }

    @Test func onAPlaylistPageTheRowCanBeTakenOut() {
        let here = place(SongMenuContext(playlistId: "p", playlistItemId: 7))
        #expect(songActions(find: false, radio: false, place: here)
            == [.playNext, .addToQueue, .addToPlaylist, .removeFromPlaylist, .like, .rate, .goToAlbum, .goToArtist, .info])
        #expect(songActions(find: true, radio: false, place: here) == [.playNext, .addToQueue, .download, .removeFromPlaylist, .info])
        #expect(!place(SongMenuContext(playlistId: "p")).inPlaylist)
    }

    @Test func selectIsOfferedInAListThatCanPickAndIsNotPickingYet() {
        let picking = place(SongMenuContext(selecting: false, selectKey: "t"))
        #expect(picking.selectable)
        #expect(songActions(find: false, radio: false, place: picking)
            == [.playNext, .addToQueue, .addToPlaylist, .select, .like, .rate, .goToAlbum, .goToArtist, .info])
        #expect(!place(SongMenuContext(selecting: true, selectKey: "t")).selectable)
        #expect(!place(SongMenuContext(selectKey: "t")).selectable)
    }
}

@Suite struct CollectionActionsTests {
    @Test func anAlbumOffersFindFlacOnlyWithSongsAFlacCouldReplace() {
        #expect(albumActions(canDownload: true, lossy: 3)
            == [.play, .shuffle, .playNext, .addToQueue, .addToPlaylist, .download, .findFlac, .addToFavorites, .pinToHome, .goToArtist])
        #expect(albumActions(canDownload: false) == albumActions(canDownload: false, lossy: 0))
        #expect(albumActions(canDownload: false, lossy: 1)
            == [.play, .shuffle, .playNext, .addToQueue, .addToPlaylist, .findFlac, .addToFavorites, .pinToHome, .goToArtist])
    }

    @Test func anAlbumRadioFollowsWhatPlays() {
        #expect(albumActions(canDownload: false, radio: true)
            == [.play, .shuffle, .playNext, .addToQueue, .startRadio, .addToPlaylist, .addToFavorites, .pinToHome, .goToArtist])
    }

    @Test func anArtistRadio() {
        #expect(artistActions(radio: true) == [.play, .shuffle, .playNext, .addToQueue, .startRadio, .addToFavorites, .pinToHome])
        #expect(artistActions(radio: false) == [.play, .shuffle, .playNext, .addToQueue, .addToFavorites, .pinToHome])
    }

    @Test func anEmptyPlaylistCanOnlyBePinnedRenamedCopiedOrDeleted() {
        #expect(playlistActions(empty: false) == [.play, .shuffle, .playNext, .addToQueue, .pinToHome, .rename, .duplicate, .delete])
        #expect(playlistActions(empty: true) == [.pinToHome, .rename, .duplicate, .delete])
    }

    @Test func aFavoriteOffersToBeRemoved() {
        #expect(albumActions(canDownload: false, favorite: true)[5] == .removeFromFavorites)
        #expect(artistActions(radio: false, favorite: true)[4] == .removeFromFavorites)
    }

    @Test func aPinOffersUnpinAndMoveToFrontUnlessItIsFirst() {
        #expect(artistActions(radio: false, pin: .pinned) == [.play, .shuffle, .playNext, .addToQueue, .addToFavorites, .unpin, .moveToFront])
        #expect(playlistActions(empty: true, pin: .first) == [.unpin, .rename, .duplicate, .delete])
        #expect(playlistActions(empty: true, pin: .pinned) == [.unpin, .moveToFront, .rename, .duplicate, .delete])
    }

    @Test func aPinsSpotComesFromTheRowHomeShows() {
        let shown = ["album:a", "artist:b"]
        #expect(pinSpot(shown, "album:a") == .first)
        #expect(pinSpot(shown, "artist:b") == .pinned)
        #expect(pinSpot(shown, "playlist:a") == PinSpot.none)
    }
}

@Suite struct PlaylistAddsTests {
    @Test func songsNotOnThePlaylistGoStraightIn() {
        let plan = planAdd(["a", "b"], onPlaylist: ["x"])
        #expect(plan.fresh == ["a", "b"])
        #expect(!plan.asks)
    }

    @Test func eachSongGoesInOnceInTheOrderGiven() {
        #expect(planAdd(["b", "a", "b"], onPlaylist: []).songs == ["b", "a"])
    }

    @Test func oneSongOnThePlaylistAlreadyAsksToAddItAgain() {
        let plan = planAdd(["a"], onPlaylist: ["a"])
        #expect(plan.asks)
        #expect(!plan.offersNewOnly)
        #expect(addAgainQuestion("Road trip", plan) == "Already in Road trip. Add again?")
    }

    @Test func someAlreadyOnItOfferAllOrOnlyTheNewOnes() {
        let plan = planAdd(["a", "b", "c"], onPlaylist: ["b", "c"])
        #expect(plan.fresh == ["a"])
        #expect(plan.repeats == ["b", "c"])
        #expect(plan.offersNewOnly)
        #expect(addAgainQuestion("Road trip", plan) == "2 of these songs are already in Road trip.")
        #expect(addAgainQuestion("Road trip", planAdd(["a", "b"], onPlaylist: ["b"])) == "1 of these songs is already in Road trip.")
    }

    @Test func allAlreadyOnItAsksToAddThemAgain() {
        let plan = planAdd(["a", "b"], onPlaylist: ["a", "b"])
        #expect(!plan.offersNewOnly)
        #expect(addAgainQuestion("Road trip", plan) == "These songs are already in Road trip. Add them again?")
    }

    @Test func theMessageCountsTheSongs() {
        #expect(addedMessage("Road trip", 1) == "Added to Road trip")
        #expect(addedMessage("Road trip", 3) == "Added 3 songs to Road trip")
    }

    @Test func theAddButtonSaysWhatItAdds() {
        #expect(addAgainChoice(planAdd(["a"], onPlaylist: ["a"])) == "Add")
        #expect(addAgainChoice(planAdd(["a", "b"], onPlaylist: ["a", "b"])) == "Add again")
        #expect(addAgainChoice(planAdd(["a", "b"], onPlaylist: ["a"])) == "Add all")
    }

    @Test func theLastPlaylistsAddedToAreKeptNewestFirst() {
        #expect(recentPlaylists([], adding: "p1") == ["p1"])
        #expect(recentPlaylists(["p1"], adding: "p2") == ["p2", "p1"])
        #expect(recentPlaylists(["p2", "p1"], adding: "p1") == ["p1", "p2"])
        #expect(recentPlaylists(["p3", "p2", "p1"], adding: "p4") == ["p4", "p3", "p2"])
    }

    @Test func theLastPlaylistsUsedComeFirst() {
        let all = ["a", "b", "c", "d"]
        #expect(recentFirst(all, recent: ["c", "a"], id: { $0 }) == ["c", "a", "b", "d"])
        #expect(recentFirst(all, recent: ["gone", "b"], id: { $0 }) == ["b", "a", "c", "d"])
    }

    @Test func aCopyIsNamedAfterItsPlaylist() {
        #expect(playlistCopyName(" Late night ") == "Late night (copy)")
        #expect(copiedMessage("Late night (copy)") == "Made a copy: Late night (copy)")
    }

    @Test func anImportSaysHowManySongsWereFound() {
        #expect(importSummary(ImportReport("Road trip", 18, 20, ["a", "b"])) == "Imported 18 of 20 songs into \"Road trip\"")
        #expect(importSummary(ImportReport("Road trip", 1, 1, [])) == "Imported 1 of 1 song into \"Road trip\"")
        #expect(importSummary(ImportReport("Road trip", 0, 4, [])) == "None of the 4 songs in \"Road trip\" are in your library.")
        #expect(importSummary(ImportReport("Road trip", 0, 0, [])) == "\"Road trip\" has no songs in it.")
    }
}

@Suite struct M3uTextTests {
    private let library = [
        M3uSong("s1", "Nightcall", "Kavinsky", 258_000),
        M3uSong("s2", "Digital Love", "Daft Punk", 301_000),
        M3uSong("s3", "Genesis", "Justice", 234_000),
    ]

    @Test func whatIsWrittenFindsTheSameSongsAgain() {
        let text = writeM3u([
            M3uLine(seconds: 258, artist: "Kavinsky", title: "Nightcall", location: "Kavinsky/OutRun/01 - Nightcall.flac"),
            M3uLine(seconds: 301, artist: "Daft Punk", title: "Digital Love", location: fallbackLocation(artist: "Daft Punk", title: "Digital Love")),
        ])
        let match = matchM3u(parseM3u(text), library: library, paths: [:])
        #expect(match.trackIds == ["s1", "s2"])
        #expect(match.missed.isEmpty)
    }

    @Test func aServerPathFindsItsSongBeforeTheTitle() {
        let twins = library + [M3uSong("s9", "Nightcall", "Kavinsky", 258_000)]
        let paths = ["s9": "Kavinsky/Live/01 - Nightcall.flac", "s1": "Kavinsky/OutRun/01 - Nightcall.flac"]
        let match = matchM3u(parseM3u("#EXTINF:258,Kavinsky - Nightcall\nD:\\Music\\Kavinsky\\Live\\01 - Nightcall.flac"), library: twins, paths: paths)
        #expect(match.trackIds == ["s9"])
    }

    @Test func linesNotInTheLibraryAreMissed() {
        let match = matchM3u(parseM3u("#EXTINF:200,Nobody - Nothing\nx.mp3\nC:\\Justice - Genesis.mp3"), library: library, paths: [:])
        #expect(match.trackIds == ["s3"])
        #expect(match.missed.map(\.shown) == ["Nobody - Nothing"])
    }

    @Test func aFileIsReadAsUtf8OrElseAsWindowsWestern() {
        #expect(playlistText(Data("Beyoncé - Halo".utf8)) == "Beyoncé - Halo")
        #expect(playlistText("Beyoncé - Halo".data(using: .windowsCP1252)!) == "Beyoncé - Halo")
    }

    @Test func aPlaylistIsNamedAfterItsFile() {
        #expect(playlistNameOf("Road trip.m3u8") == "Road trip")
        #expect(playlistNameOf("C:\\Users\\me\\Road trip.m3u") == "Road trip")
        #expect(playlistNameOf(".m3u") == "Imported playlist")
        #expect(playlistFileName("AC/DC") == "AC DC.m3u")
    }

    @Test func extinfReadsLengthAndCredits() {
        let entries = parseM3u("\u{FEFF}#EXTM3U\r\n#EXTINF:-1 tvg-name=\"a,b\",Kavinsky - Nightcall\r\nfile.mp3\r\n")
        #expect(entries == [M3uEntry(location: "file.mp3", seconds: nil, artist: "Kavinsky", title: "Nightcall", line: 3)])
    }
}

@Suite struct ReleaseGroupsTests {
    private struct Release { let id: String; let types: [String]; var compilation = false; var artistId = "r1" }

    private func groups(_ items: [Release]) -> [(ReleaseGroup, [String])] {
        groupReleases(items, types: \.types, compilation: \.compilation, own: { $0.artistId == "r1" }).map { ($0.group, $0.items.map(\.id)) }
    }

    @Test func eachKindGoesOnItsShelfInThePagesOrder() {
        let albums = [
            Release(id: "appears", types: ["Album"], artistId: "other"), Release(id: "live", types: ["Album", "Live"]),
            Release(id: "single", types: ["Single"]), Release(id: "ep", types: ["ep"]), Release(id: "best", types: ["Album", "Compilation"]),
            Release(id: "ok", types: ["Album"]), Release(id: "soundtrack", types: ["Album", "Soundtrack"]),
        ]
        let shelves = groups(albums)
        #expect(shelves.map(\.0) == [.albums, .singlesAndEps, .compilations, .live, .appearsOn])
        #expect(shelves.map(\.1) == [["ok", "soundtrack"], ["single", "ep"], ["best"], ["live"], ["appears"]])
    }

    @Test func aCompilationFlagWinsOverAnyType() {
        #expect(releaseGroupOf(["Single"], compilation: true) == .compilations)
        #expect(releaseGroupOf(["single", "LIVE"]) == .live)
    }

    @Test func withNoTypesEverythingOwnIsAnAlbum() {
        let shelves = groups([Release(id: "a", types: []), Release(id: "b", types: [], compilation: true),
                              Release(id: "c", types: [], artistId: "other")])
        #expect(shelves.map(\.0) == [.albums, .appearsOn])
        #expect(shelves.map(\.1) == [["a", "b"], ["c"]])
    }

    @Test func nothingGivesNoShelves() {
        #expect(groups([]).isEmpty)
    }

    @Test func theShelvesHaveThePhonesWords() {
        #expect(ReleaseGroup.allCases.map(\.title) == ["Albums", "Singles and EPs", "Compilations", "Live", "Appears on"])
    }
}
