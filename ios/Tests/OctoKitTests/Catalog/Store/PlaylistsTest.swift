import Foundation
import Testing
@testable import OctoKit

@Suite struct PlaylistsTest {
    private func item(_ id: Int64, _ position: Int) -> PlaylistItem {
        PlaylistItem(id: id, playlistId: "p", trackId: "device:\(id)", relinkKey: "key\(id)", position: position)
    }

    private func order(_ items: [PlaylistItem]) -> [Int64] { items.map(\.id) }

    private func track(_ id: String, _ relinkKey: String) -> LibraryTrack {
        LibraryTrack(id: id, sourceId: "device", nativeId: id, title: id, searchKey: id, sortKey: id, artist: "", artistId: "",
                     album: "", albumId: "", durationMs: 0, addedAt: 0, relinkKey: relinkKey)
    }

    private var items: [PlaylistItem] { [item(10, 0), item(11, 1), item(12, 2), item(13, 3)] }

    @Test func movingDownTakesTheTargetsPlace() {
        let moved = movedItem(items, itemId: 10, targetId: 12)
        #expect(order(moved) == [11, 12, 10, 13])
        #expect(moved.map(\.position) == [0, 1, 2, 3])
    }

    @Test func movingUpTakesTheTargetsPlace() {
        let moved = movedItem(items, itemId: 13, targetId: 11)
        #expect(order(moved) == [10, 13, 11, 12])
        #expect(moved.map(\.position) == [0, 1, 2, 3])
    }

    @Test func movingToTheEnds() {
        #expect(order(movedItem(items, itemId: 10, targetId: 13)) == [11, 12, 13, 10])
        #expect(order(movedItem(items, itemId: 13, targetId: 10)) == [13, 10, 11, 12])
    }

    @Test func unknownIdsChangeNothing() {
        #expect(movedItem(items, itemId: 99, targetId: 10) == items)
        #expect(movedItem(items, itemId: 10, targetId: 99) == items)
    }

    @Test func renumberingClosesGapsAndKeepsOrder() {
        let gappy = [item(10, 0), item(12, 2), item(13, 5)]
        let fixed = renumbered(gappy)
        #expect(order(fixed) == [10, 12, 13])
        #expect(fixed.map(\.position) == [0, 1, 2])
        // A row already in place is the same row, so it is not written again.
        #expect(fixed[0] == gappy[0])
    }

    @Test func appendedSongsNumberOnAndKeepTheirRelinkKeys() {
        let rows = appendedItems("p", start: 4, tracks: [track("device:1", "a"), track("device:2", "b")])
        #expect(rows.map(\.position) == [4, 5])
        #expect(rows.map(\.trackId) == ["device:1", "device:2"])
        #expect(rows.map(\.relinkKey) == ["a", "b"])
        #expect(rows.map(\.playlistId) == ["p", "p"])
    }

    @Test func mosaicTakesOneCoverPerAlbumUpToFour() {
        let art: [(album: String, art: String?)] = [
            ("a", "cover:a1"),
            ("a", "cover:a2"),
            ("b", nil),
            ("c", "cover:c"),
            ("b", "cover:b"),
            ("d", "cover:d"),
            ("e", "cover:e"),
            ("f", "cover:f"),
        ]
        #expect(mosaicCovers(art) == ["cover:a1", "cover:c", "cover:b", "cover:d"])
    }

    @Test func mosaicWithFewAlbums() {
        #expect(mosaicCovers([("a", "cover:a"), ("a", "cover:a")]) == ["cover:a"])
        #expect(mosaicCovers([("a", nil)]) == [])
    }

    @Test func anUndoPutsARowBackInItsPlace() {
        // 11 was taken out from place 1; the rest were renumbered around it.
        let rest = renumbered([item(10, 0), item(12, 2), item(13, 3)])
        let restored = restoredItems(rest, item(11, 1))
        #expect(order(restored) == [10, 11, 12, 13])
        #expect(restored.map(\.position) == [0, 1, 2, 3])
    }

    @Test func anUndoPutsTheFirstAndLastRowsBack() {
        #expect(order(restoredItems(renumbered(Array(items.dropFirst())), item(10, 0))) == [10, 11, 12, 13])
        #expect(order(restoredItems(renumbered(Array(items.dropLast())), item(13, 3))) == [10, 11, 12, 13])
    }

    @Test func anUndoAfterTheListShrankPutsTheRowLast() {
        let restored = restoredItems([item(10, 0)], item(13, 3))
        #expect(order(restored) == [10, 13])
        #expect(restored.map(\.position) == [0, 1])
    }

    @Test func anUndoForARowAlreadyBackChangesNothing() {
        #expect(restoredItems(items, item(12, 0)) == items)
    }

    @Test func summariesCountLengthAndCoversPerPlaylist() {
        let playlists = [
            PlaylistRow(id: "new", name: "Empty", createdAt: 2, updatedAt: 2),
            PlaylistRow(id: "p", name: "Road", createdAt: 1, updatedAt: 1),
        ]
        let entries = [
            PlaylistEntry(playlistId: "p", albumId: "a", durationMs: 1_000, artwork: "cover:a"),
            PlaylistEntry(playlistId: "p", albumId: "b", durationMs: 2_000, artwork: "cover:b"),
        ]
        #expect(summarize(playlists, entries) == [
            PlaylistSummary(id: "new", name: "Empty", songCount: 0, durationMs: 0, covers: [], createdAt: 2, updatedAt: 2),
            PlaylistSummary(id: "p", name: "Road", songCount: 2, durationMs: 3_000, covers: ["cover:a", "cover:b"], createdAt: 1, updatedAt: 1),
        ])
    }

    @Test func aSummaryCarriesTheServersNoticeMark() {
        let playlists = [PlaylistRow(id: "r", name: "Review", createdAt: 1, updatedAt: 1, serverId: "pl9", sourceId: "s", octoNotice: "review")]
        let summaries = summarize(playlists, [])
        #expect(summaries.count == 1)
        #expect(summaries.first?.octoNotice == "review")
    }
}
