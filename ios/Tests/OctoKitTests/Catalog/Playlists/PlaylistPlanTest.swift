import Foundation
import Testing
@testable import OctoKit

@Suite struct PlaylistPlanTest {
    func server(_ id: String, name: String? = nil, stamp: String = "t1|3") -> ServerPlaylist { ServerPlaylist(id, name ?? id, stamp) }

    func linked(_ serverId: String, name: String? = nil, edited: Bool = false, syncedName: String? = nil,
                syncedStamp: String = "t1|3") -> LinkedPlaylist {
        LinkedPlaylist("local-\(serverId)", serverId, name ?? serverId, edited, syncedName ?? name ?? serverId, syncedStamp)
    }

    func plan(_ server: [ServerPlaylist] = [], _ linked: [LinkedPlaylist] = [], others: Set<String> = [], waiting: [String] = [],
              deleted: Set<String> = []) -> [PlaylistStep] {
        planPlaylists(server: server, others: others, linked: linked, waiting: waiting, deleted: deleted)
    }

    @Test func agreeingSidesNeedNothing() {
        #expect(plan([server("a")], [linked("a")]) == [])
    }

    @Test func aNewServerPlaylistIsImported() {
        #expect(plan([server("a")]) == [.importing(serverId: "a", stamp: "t1|3")])
    }

    @Test func aServerChangeIsTakenWithItsName() {
        #expect(plan([server("a", name: "Renamed", stamp: "t2|4")], [linked("a")])
            == [.pull(localId: "local-a", serverId: "a", stamp: "t2|4", keepName: false)])
    }

    @Test func aPhoneChangeIsSent() {
        #expect(plan([server("a")], [linked("a", edited: true)]) == [.push(localId: "local-a", serverId: "a")])
    }

    @Test func whenBothChangedTheServerWinsForSongs() {
        #expect(plan([server("a", name: "Server name", stamp: "t2|5")], [linked("a", edited: true)])
            == [.pull(localId: "local-a", serverId: "a", stamp: "t2|5", keepName: false)])
    }

    @Test func whenBothChangedANameChangedHereWins() {
        let here = linked("a", name: "Phone name", edited: true, syncedName: "a")
        #expect(plan([server("a", name: "Server name", stamp: "t2|5")], [here])
            == [.pull(localId: "local-a", serverId: "a", stamp: "t2|5", keepName: true)])
    }

    @Test func theSameNewNameOnBothSidesNeedsNoRename() {
        let here = linked("a", name: "Same", edited: true, syncedName: "a")
        #expect(plan([server("a", name: "Same", stamp: "t2|5")], [here])
            == [.pull(localId: "local-a", serverId: "a", stamp: "t2|5", keepName: false)])
    }

    @Test func aSongCountChangeAloneCountsAsAChange() {
        #expect(plan([server("a", stamp: "t1|4")], [linked("a")]) == [.pull(localId: "local-a", serverId: "a", stamp: "t1|4", keepName: false)])
    }

    @Test func deletedOnTheServerGoesFromThePhone() {
        #expect(plan([], [linked("a")]) == [.remove(localId: "local-a")])
    }

    @Test func deletedOnTheServerButEditedHereStaysOnThePhone() {
        #expect(plan([], [linked("a", edited: true)]) == [.unlink(localId: "local-a")])
    }

    @Test func aPlaylistNoLongerKeptInStepStaysOnThePhone() {
        #expect(plan([], [linked("a")], others: ["a"]) == [.unlink(localId: "local-a")])
    }

    @Test func deletedHereIsDeletedThereAndNotImportedBack() {
        let steps = plan([server("a"), server("b")], deleted: ["a", "gone"])
        #expect(Set(steps) == [.deleteOnServer(serverId: "a"), .forgetDeletion(serverId: "gone"), .importing(serverId: "b", stamp: "t1|3")])
    }

    @Test func playlistsWaitingForTheServerAreMade() {
        #expect(plan(waiting: ["p1"]) == [.create(localId: "p1")])
    }

    @Test func aPushThatFindsTheServerChangedSettlesLikeASync() {
        let here = linked("a", edited: true)
        #expect(planLinked(server("a"), here) == .push(localId: "local-a", serverId: "a"))
        #expect(planLinked(server("a", stamp: "t9|1"), here) == .pull(localId: "local-a", serverId: "a", stamp: "t9|1", keepName: false))
        #expect(planLinked(nil, here) == .unlink(localId: "local-a"))
        #expect(planLinked(server("a"), linked("a")) == nil)
    }

    func listed(_ id: String, owner: String? = "winters", readonly: Bool = false) -> ServerPlaylistInfo {
        ServerPlaylistInfo(id: id, name: id, owner: owner, readonly: readonly)
    }

    @Test func readOnlyStationsAndOtherPeoplesPlaylistsAreSkipped() {
        let all = [listed("mine"), listed("or7", readonly: true), listed("orStation"), listed("smart", readonly: true),
                   listed("theirs", owner: "someone"), listed("noOwner", owner: nil), listed("orchestra"),
                   ServerPlaylistInfo(id: "og1", name: "New Releases", owner: "winters", readonly: true, octoList: "newReleases")]
        #expect(importable(all, stationIds: ["orStation"], username: "Winters").map(\.id) == ["mine", "noOwner", "orchestra"])
    }

    @Test func onlyUnmarkedPlaylistsThatLookLikeStationsAreSuspects() {
        #expect(stationSuspects([listed("or1", readonly: true), listed("or2"), listed("abc")]).map(\.id) == ["or2"])
    }

    @Test func anUnknownUserOwnsEverything() {
        #expect(importable([listed("x", owner: "someone")], stationIds: [], username: "").count == 1)
    }

    @Test func theStampFollowsTimeAndCount() {
        #expect(stampOf("2026-09-26T10:00:00Z", 12) == "2026-09-26T10:00:00Z|12")
        #expect(stampOf(nil, 0) == "|0")
    }

    func track(_ id: String, _ title: String, _ artist: String) -> LibraryTrack {
        LibraryTrack(id: id, sourceId: "device", nativeId: id, title: title, searchKey: title.lowercased(), sortKey: title.lowercased(),
                     artist: artist, artistId: "a", album: "Album", albumId: "al", durationMs: 200_000, addedAt: 0)
    }

    func song(_ id: String, _ title: String, _ artist: String) -> Song { Song(id: id, title: title, artist: artist, duration: 200) }

    @Test func serverEntriesBecomeLibrarySongsOrFindsInOrderWithRepeats() {
        let songs = [song("s1", "One More Time", "Daft Punk"), song("e1", "Genesis", "Justice"), song("s1", "One More Time", "Daft Punk"),
                     song("s2", "Digital Love", "Daft Punk")]
        let phone = track("p2", "Digital Love", "Daft Punk")
        let ids = resolveSongs(songs, sourceId: "server:x", links: ["s1": "lib1"], library: [phone], now: 0).map(\.id)
        #expect(serverRows(songs.map(\.id), ids)
            == [PlaylistSyncRow("lib1", "s1"), PlaylistSyncRow("find:e1", "e1"), PlaylistSyncRow("lib1", "s1"), PlaylistSyncRow("p2", "s2")])
    }

    @Test func eachRowGoesBackAsTheRightServerSong() {
        #expect(serverSongFor(PlaylistSyncRow("lib", "s2"), ["s1", "s2"]) == "s2")
        #expect(serverSongFor(PlaylistSyncRow("lib"), ["s3", "s1"]) == "s1")
        #expect(serverSongFor(PlaylistSyncRow("lib", "gone"), ["s1"]) == "s1")
        #expect(serverSongFor(PlaylistSyncRow("find:e1"), []) == "e1")
        #expect(serverSongFor(PlaylistSyncRow("p9", "s9"), []) == "s9")
        #expect(serverSongFor(PlaylistSyncRow("p1"), []) == nil)
    }

    @Test func songsOnlyOnThePhoneKeepTheirPlaceAfterAPull() {
        let phoneOnly: Set<String> = ["p1", "p2", "p3"]
        let local = ["p1", "a", "p2", "b", "c", "p3"].map { PlaylistSyncRow($0) }
        let server = [PlaylistSyncRow("c", "sc"), PlaylistSyncRow("a", "sa"), PlaylistSyncRow("d", "sd")]
        #expect(withPhoneOnly(server, local) { phoneOnly.contains($0.trackId) }.map(\.trackId) == ["p1", "c", "p3", "a", "p2", "d"])
    }

    @Test func aPhoneSongAfterOneTheServerDroppedFollowsTheOneBefore() {
        let merged = withPhoneOnly([PlaylistSyncRow("a", "sa")], ["a", "b", "p1"].map { PlaylistSyncRow($0) }) { $0.trackId == "p1" }
        #expect(merged.map(\.trackId) == ["a", "p1"])
    }

    @Test func withNothingOnlyOnThePhoneTheServersListIsTakenAsIs() {
        let server = [PlaylistSyncRow("b", "sb"), PlaylistSyncRow("a", "sa"), PlaylistSyncRow("b", "sb")]
        #expect(withPhoneOnly(server, [PlaylistSyncRow("a"), PlaylistSyncRow("b")]) { _ in false } == server)
    }

    @Test func thePhoneOnlyLineCountsSongs() {
        #expect(phoneOnlyNote(1) == "1 song is only on this phone and is not in the server's copy")
        #expect(phoneOnlyNote(3) == "3 songs are only on this phone and are not in the server's copy")
    }

    @Test func theServersPlaylistsAreLookedAtAgainOnceAMinuteOld() {
        let now: Int64 = 10_000_000
        #expect(playlistsStale(now, 0))
        #expect(playlistsStale(now, now - playlistsFreshMs))
        #expect(!playlistsStale(now, now - playlistsFreshMs + 1))
        #expect(!playlistsStale(now, now))
    }

    @Test func longSongListsGoInBatchesUnlessAFormBodyTakesThem() {
        let ids = (1...320).map { "s\($0)" }
        #expect(songBatches(ids, formPost: false).map(\.count) == [150, 150, 20])
        #expect(songBatches(ids, formPost: true).map(\.count) == [320])
        #expect(songBatches([], formPost: false) == [[]])
        let calls = replaceSongsCalls("p", ids, formPost: false)
        #expect(calls.map(\.endpoint) == ["createPlaylist", "updatePlaylist", "updatePlaylist"])
        #expect(calls[0].params.first == PlaylistCall.Param("playlistId", "p"))
        #expect(calls[1].params.filter { $0.name == "songIdToAdd" }.count == 150)
        let update = updateCalls("p", name: "N", comment: nil, isPublic: nil, songIdsToAdd: ["x"], songIndexesToRemove: [2, 2], formPost: false)
        #expect(update[0].params == [.init("playlistId", "p"), .init("name", "N"), .init("songIndexToRemove", "2"),
                                     .init("songIndexToRemove", "2"), .init("songIdToAdd", "x")])
    }
}
