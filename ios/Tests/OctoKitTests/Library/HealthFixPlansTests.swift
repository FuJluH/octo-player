import Foundation
import Testing
@testable import OctoKit

/// Library health's fixes planned from the phone's report: what shows for which server, and the
/// steps each fix sends, by the server's own ids.
@Suite struct HealthFixPlansTests {
    typealias R = HealthRows
    let server = HealthRows.server
    let all = ["remove", "restore", "retag", "undo", "joinAlbum", "lookup", "cover", "upgrade"]

    private func actions(_ names: [String], admin: Bool = true, dryRun: Bool = false) -> FileActions {
        FileActions(enabled: true, allowed: true, dryRun: dryRun, actions: names, admin: admin)
    }

    /// Holocene twice on the server: a FLAC on Bon Iver with no genre, and an MP3 on a single of
    /// its own.
    private func twice(source: String = HealthRows.server) -> PhoneHealth {
        let tracks = [R.track("t1", "Holocene", album: "Bon Iver"), R.track("t2", "Holocene", album: "Holocene")]
        let copies = [
            R.copy("flac", "Holocene", merged: "t1", source: source, album: "Bon Iver", genre: ""),
            R.copy("mp3", "Holocene", merged: "t2", source: source, mime: "audio/mpeg", bitrate: 320, depth: nil, album: "Holocene",
                   genre: "Folk"),
        ]
        return phoneHealth(tracks, albums: [], copies: copies)
    }

    @Test func aServerWithEveryActionOffersEveryFix() {
        let offers = healthOffers(actions(all))
        #expect(offers == HealthOffers(fixDuplicates: true, edit: true, join: true, lookUp: true, covers: true, upgrade: true,
                                       restore: true, remove: true))
        for check in HealthCheck.allCases { #expect(offers.fixesAll(check), "\(check)") }
        #expect(offers.looksUp(.noYear))
        #expect(offers.looksUp(.noTrackNumber))
        #expect(!offers.looksUp(.noCover))
        #expect(!offers.looksUp(.duplicates))
    }

    @Test func noServerANonAdminOrARehearsalOffersNothingToChange() {
        #expect(healthOffers(nil) == HealthOffers())
        #expect(healthOffers(actions(all, admin: false)) == HealthOffers(upgrade: true))
        #expect(healthOffers(actions(all, dryRun: true)) == HealthOffers())
    }

    @Test func anOlderServerThatOnlyRemovesOffersDuplicatesWithoutTheirFills() {
        let offers = healthOffers(actions(["remove"]))
        #expect(offers.fixDuplicates)
        #expect(offers.remove)
        #expect(!offers.edit)
        #expect(!offers.restore)
        #expect(!offers.fixesAll(.noYear))
        #expect(!offers.fixesAll(.splitAlbums))
        // A look-up is only offered when what it finds can be written.
        #expect(!healthOffers(actions(["lookup"])).lookUp)
    }

    @Test func aSetOfCopiesKeepsTheBestFillsItAndRemovesTheOtherOnTheServer() throws {
        let health = twice()
        let plan = try #require(health.duplicatePlan(0, source: server))
        #expect(plan.keep.nativeId == "flac")
        #expect(plan.remove.map(\.nativeId) == ["mp3"])
        #expect(plan.fills == [TagChange("genre", now: nil, value: "Folk", from: "mp3")])
        #expect(plan.serverSteps(plan.fills, edit: true)
            == [.retag(id: "flac", title: "Holocene", tags: ["genre": "Folk"]), .remove(id: "mp3", title: "Holocene", copy: true)])
        // A server that cannot write tags only removes.
        #expect(plan.serverSteps(plan.fills, edit: false) == [.remove(id: "mp3", title: "Holocene", copy: true)])
        let everything = health.fixAllDuplicates(source: server, edit: true)
        #expect(everything.count == 1)
        #expect(everything.first?.1 == plan.serverSteps(plan.fills, edit: true))
    }

    @Test func keepingAnotherCopyRemovesTheBestAndAPickedValueIsWritten() throws {
        let health = twice()
        let mp3 = try #require(health.copyIn(0, trackId: "t2"))
        let plan = try #require(health.duplicatePlan(0, source: server, keep: mp3))
        #expect(plan.keep.nativeId == "mp3")
        #expect(plan.remove.map(\.nativeId) == ["flac"])
        // The albums disagree; picking the FLAC's album writes it.
        let album = try #require(plan.differs.first { $0.tag == "album" })
        #expect(album.value(of: "mp3") == "Holocene")
        #expect(album.value(of: "flac") == "Bon Iver")
        #expect(plan.picked(["album": "flac"]) == [TagChange("album", now: "Holocene", value: "Bon Iver", from: "flac")])
        // Picking the kept copy's own value changes nothing.
        #expect(plan.picked(["album": "mp3"]).isEmpty)
    }

    @Test func copiesOnAnotherSourceGetNoFix() {
        let health = twice(source: "server:other")
        #expect(health.report.duplicates.count == 1)
        #expect(health.duplicatePlan(0, source: server) == nil)
        #expect(health.duplicatePlan(0, source: nil) == nil)
        #expect(health.fixAllDuplicates(source: server, edit: true).isEmpty)
    }

    @Test func aSplitAlbumJoinsOntoItsLargestPartLedBySongTheServerHas() throws {
        let tracks = [
            R.track("a", "One", album: "It Was Fun", albumId: "x"),
            R.track("b", "Two", album: "It Was Fun", albumId: "x"),
            R.track("c", "Three", album: "It Was Fun", albumId: "y"),
        ]
        let health = phoneHealth(tracks, albums: [], copies: [])
        let ids = ["a": "na", "b": "nb", "c": "nc"]
        let (join, steps) = try #require(health.joinPlan(0, serverIds: ids))
        #expect(join.words == "Moves 1 song onto It Was Fun, the part with 2 songs.")
        #expect(steps == [.joinAlbum(id: "nc", title: "Three", like: "na")])
        // A lead the server does not have gives way to the next song.
        var withoutA = ids
        withoutA["a"] = nil
        #expect(health.joinPlan(0, serverIds: withoutA)?.1 == [.joinAlbum(id: "nc", title: "Three", like: "nb")])
        // Nothing to move on the server: no join.
        var withoutC = ids
        withoutC["c"] = nil
        #expect(health.joinPlan(0, serverIds: withoutC) == nil)
        #expect(health.joinAll(serverIds: ids) == steps)
        #expect(health.fixAllPreview(.splitAlbums, offers: healthOffers(actions(["joinAlbum"])), source: server, serverIds: ids).count == 1)
    }

    @Test func anAlbumFiledUnderEachOfItsArtistsJoinsOntoTheLargerPart() throws {
        let title = "$ome $exy $ongs 4 U"
        let tracks = [
            R.track("p1", "CELIBACY", artist: "PARTYNEXTDOOR", album: title, albumId: "pnd"),
            R.track("p2", "CN TOWER", artist: "PARTYNEXTDOOR", album: title, albumId: "pnd"),
            R.track("p3", "NOKIA", artist: "Drake", album: title, albumId: "pnd"),
            R.track("d1", "GIMME A HUG", artist: "Drake", album: title, albumId: "drake", year: nil),
        ]
        let health = phoneHealth(tracks, albums: [], copies: [])
        let ids = ["p1": "np1", "p2": "np2", "p3": "np3", "d1": "nd1"]
        let (join, steps) = try #require(health.joinPlan(0, serverIds: ids))
        #expect(health.report.splitAlbums.first?.reasons.first?.words
            == "One album filed under two artists: the part by PARTYNEXTDOOR has NOKIA by Drake.")
        #expect(steps == [.joinAlbum(id: "nd1", title: "GIMME A HUG", like: "np1")])
        #expect(join.words == "Moves 1 song onto \(title), the part with 3 songs. Their album artist becomes PARTYNEXTDOOR.")
    }

    @Test func aSourcesReleaseGroupTiesPartsByDifferentArtists() {
        let tracks = [
            R.track("z1", "Time", artist: "Hans Zimmer", album: "Inception", albumId: "zimmer"),
            R.track("b1", "Old Souls", artist: "Lorne Balfe", album: "Inception", albumId: "balfe"),
        ]
        let group = "5b5f2a1e-1111-4111-8111-111111111111"
        let copies = [R.copy("z", "Time", merged: "z1", album: "Inception", releaseGroup: group),
                      R.copy("b", "Old Souls", merged: "b1", album: "Inception", releaseGroup: group)]
        #expect(phoneHealth(tracks, albums: [], copies: []).report.splitAlbums.isEmpty)
        #expect(phoneHealth(tracks, albums: [], copies: copies).report.splitAlbums.first?.reasons.first?.basis == .sameReleaseGroup)
    }

    @Test func aMissingYearIsFilledFromItsAlbumAndACoverLookedFor() {
        let tracks = [
            R.track("a", "One", albumId: "x"),
            R.track("b", "Two", albumId: "x", year: nil, artwork: nil),
            R.track("c", "Three", albumId: "x"),
            // Alone on its album, with nothing to take a year from.
            R.track("d", "Four", album: "Single", albumId: "s", year: nil),
        ]
        let health = phoneHealth(tracks, albums: [], copies: [])
        let ids = ["a": "na", "b": "nb", "c": "nc", "d": "nd"]
        #expect(health.fillSteps(.noYear, serverIds: ids) == [.retag(id: "nb", title: "Two", tags: ["year": "2020"])])
        // A song the server does not have is left alone.
        var withoutB = ids
        withoutB["b"] = nil
        #expect(health.fillSteps(.noYear, serverIds: withoutB).isEmpty)
        #expect(health.coverSteps(serverIds: ids) == [.addCover(id: "nb", title: "Two")])
        let preview = health.fixAllPreview(.noYear, offers: healthOffers(actions(["retag", "undo"])), source: server, serverIds: ids)
        #expect(preview.count == 1)
        #expect(preview.lines.map { "\($0.0)|\($0.1 ?? "")" } == ["Two|Year: 2020"])
        // Not offered at all: nothing planned.
        #expect(health.fixAllPreview(.noYear, offers: healthOffers(actions(["remove"])), source: server, serverIds: ids).count == 0)
    }

    @Test func fixAllForDuplicatesPreviewsEachSet() {
        let preview = twice().fixAllPreview(.duplicates, offers: healthOffers(actions(["remove", "retag", "undo"])), source: server,
                                            serverIds: [:])
        #expect(preview.count == 1)
        #expect(preview.lines.map { "\($0.0)|\($0.1 ?? "")" }
            == ["Keeps Holocene (FLAC, 16-bit, 44.1 kHz)|Removes Holocene (MP3, 320 kbps). Fills in Genre: Folk."])
        #expect(preview.steps == [.retag(id: "flac", title: "Holocene", tags: ["genre": "Folk"]), .remove(id: "mp3", title: "Holocene", copy: true)])
    }

    @Test func aBulkLookUpTakesAtMostABatchOfSongsTheServerHas() {
        let songs = (1...30).map { R.track("t\($0)", "Song \($0)") }
        var ids: [String: String] = [:]
        for song in songs.dropFirst() { ids[song.id] = "n\(song.id)" }
        let batch = lookupBatch(songs, serverIds: ids)
        #expect(batch.count == lookupBatchSize)
        #expect(batch.first.map { "\($0.0.id)|\($0.1)" } == "t2|nt2")
        #expect(retagStep("n1", title: "One", changes: []) == nil)
        #expect(retagStep("n1", title: "One", changes: [TagChange("track", now: nil, value: "3"), TagChange("year", now: "1997", value: "1998")])
            == .retag(id: "n1", title: "One", tags: ["track": "3", "year": "1998"]))
    }

    @Test func theServerIdsAndDeleteStepsAreTheCopiesThere() {
        let copies = [R.copy("b", "Song", merged: "t1"), R.copy("a", "Song", merged: "t1"), R.copy("c", "Other", merged: "t2", source: "device")]
        #expect(serverSongIds(copies, sourceId: server) == ["t1": "a"])
        #expect(serverSongIds(copies, sourceId: nil).isEmpty)
        #expect(deleteSteps(["t1", "t1", "t2"], copies: copies, sourceId: server)
            == [.remove(id: "a", title: "Song"), .remove(id: "b", title: "Song")])
        #expect(listsLibraryActions(["octoLibraryActions:2"]))
        #expect(!listsLibraryActions(["octoTopSongs"]))
        #expect(canRunAll(actions(["remove", "restore"]), [.restore(id: "a", title: "A")]))
        #expect(!canRunAll(actions(["remove"]), [.restore(id: "a", title: "A")]))
        #expect(!canRunAll(nil, [.remove(id: "a", title: "A")]))
    }
}
