import Foundation
import Testing
@testable import OctoKit

@Suite struct DownloadPlanTest {
    let manual = DownloadReasons.manual
    let liked = DownloadReasons.liked
    let gym = DownloadReasons.playlist("gym")
    let road = DownloadReasons.playlist("road")

    @Test func theRulesWantLikedSongsOnlyWhileLikedSongsAreKept() {
        let members = [PlaylistMember(playlistId: "gym", trackId: "a"), PlaylistMember(playlistId: "gym", trackId: "b"),
                       PlaylistMember(playlistId: "road", trackId: "b")]
        #expect(wantedByRules(keepLiked: true, liked: ["a", "c"], playlistSongs: members)
            == ["a": [liked, gym], "b": [gym, road], "c": [liked]])
        #expect(wantedByRules(keepLiked: false, liked: ["a", "c"], playlistSongs: members)
            == ["a": [gym], "b": [gym, road]])
    }

    @Test func newSongsDownloadOnlyWhenTheyCanBe() {
        let plan = planDownloads(held: [:], wanted: ["a": [liked], "b": [liked], "find:x": [gym]], downloadable: ["a"])
        #expect(plan.add == ["a": [liked]])
        #expect(plan.change.isEmpty && plan.remove.isEmpty)
    }

    @Test func aDownloadAskedForByHandStaysWhenNoRuleWantsIt() {
        let plan = planDownloads(held: ["a": [manual]], wanted: [:], downloadable: ["a"])
        #expect(plan.isEmpty)
    }

    @Test func switchingARuleOffLetsGoOfWhatOnlyItHeld() {
        let held: [String: Set<String>] = ["a": [liked], "b": [liked, manual], "c": [liked, gym]]
        let plan = planDownloads(held: held, wanted: ["c": [gym]], downloadable: [])
        #expect(plan.remove == ["a"])
        #expect(plan.change == ["b": [manual], "c": [gym]])
        #expect(plan.add.isEmpty)
    }

    @Test func aSongTakenOutOfAPlaylistGoesUnlessSomethingElseHoldsIt() {
        let held: [String: Set<String>] = ["a": [gym], "b": [gym, road]]
        let plan = planDownloads(held: held, wanted: ["b": [road]], downloadable: ["a", "b"])
        #expect(plan.remove == ["a"])
        #expect(plan.change == ["b": [road]])
    }

    @Test func aSongMissingFromTheLibraryForAMomentIsNotDeleted() {
        // During a sync the song is briefly not downloadable, but the playlist still has it.
        let plan = planDownloads(held: ["a": [gym]], wanted: ["a": [gym]], downloadable: [])
        #expect(plan.isEmpty)
    }

    @Test func aHeldSongGainsANewRuleWithoutDownloadingAgain() {
        let plan = planDownloads(held: ["a": [manual]], wanted: ["a": [liked]], downloadable: ["a"])
        #expect(plan.change == ["a": [manual, liked]])
        #expect(plan.add.isEmpty && plan.remove.isEmpty)
    }

    @Test func reasonsSurviveTheirColumn() {
        let reasons: Set<String> = [manual, liked, gym]
        #expect(DownloadReasons.parse(DownloadReasons.join(reasons)) == reasons)
        #expect(DownloadReasons.parse("") == [])
        #expect(DownloadReasons.playlistOf(gym) == "gym")
        #expect(DownloadReasons.playlistOf(liked) == nil)
    }

    @Test func reasonsAreStoredSorted() {
        #expect(DownloadReasons.join([manual, liked, gym]) == "liked,manual,playlist:gym")
        #expect(DownloadReasons.parse("liked,,manual, ") == [liked, manual])
    }
}
