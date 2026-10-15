import Foundation
import Testing
@testable import OctoKit

@Suite struct FavoritesTest {
    // Relinking favorites and pins after a rebuild

    @Test func aFavoriteWhoseIdVanishedFollowsItsKey() {
        // The album was only on the server; now the phone has it too, and the phone's id wins
        // the merge.
        let held = [Held(id: "server:x:al1", relinkKey: "ok computer radiohead")]
        let byKey = ["ok computer radiohead": ["device:album:7"]]
        #expect(relinks(held, present: ["device:album:7"], byKey: byKey) == [Relink(from: "server:x:al1", to: "device:album:7")])
    }

    @Test func aFavoriteStillInTheLibraryStaysPut() {
        let held = [Held(id: "device:album:7", relinkKey: "ok computer radiohead")]
        let byKey = ["ok computer radiohead": ["device:album:7", "server:x:al1"]]
        #expect(relinks(held, present: ["device:album:7", "server:x:al1"], byKey: byKey).isEmpty)
    }

    @Test func nothingWithTheKeyMeansItWaitsAsItIs() {
        // Signed out, say: the server's album is gone for now, and the favorite waits for it to
        // come back.
        let held = [Held(id: "server:x:al1", relinkKey: "ok computer radiohead"), Held(id: "server:x:al2", relinkKey: "")]
        #expect(relinks(held, present: [], byKey: ["": ["device:album:1"]]).isEmpty)
    }

    @Test func itNeverMovesOntoSomethingAlreadyHeld() {
        let held = [Held(id: "gone", relinkKey: "k"), Held(id: "device:album:1", relinkKey: "k")]
        #expect(relinks(held, present: ["device:album:1"], byKey: ["k": ["device:album:1"]]).isEmpty)
    }

    @Test func twoVanishedFavoritesDoNotBothTakeOneId() {
        let held = [Held(id: "old:b", relinkKey: "k"), Held(id: "old:a", relinkKey: "k")]
        let byKey = ["k": ["new:2", "new:1"]]
        // The first by id takes the first by id, the other the next.
        #expect(relinks(held, present: ["new:1", "new:2"], byKey: byKey)
            == [Relink(from: "old:a", to: "new:1"), Relink(from: "old:b", to: "new:2")])
        #expect(relinks(held, present: ["new:1"], byKey: ["k": ["new:1"]]) == [Relink(from: "old:a", to: "new:1")])
    }

    // Following an album that merged into another

    @Test func aFavoriteFollowsTheAlbumItsSongsMergedIntoWhateverTheKeys() {
        // Made a favorite while only on the server as "Simon & Garfunkel"; the phone's copy is
        // tagged "Simon and Garfunkel", so the two merge but their search keys differ and the key
        // alone finds nothing.
        let held = [Held(id: "server:x:al1", relinkKey: "bookends simon & garfunkel")]
        let byKey = ["bookends simon and garfunkel": ["device:album:7"]]
        let merged = ["server:x:al1": "device:album:7"]
        #expect(relinks(held, present: ["device:album:7"], byKey: byKey, merged: merged)
            == [Relink(from: "server:x:al1", to: "device:album:7")])
    }

    @Test func theMergeIsFollowedBeforeTheKey() {
        // Two albums share the key; the one the songs went into is the right one.
        let held = [Held(id: "server:x:al1", relinkKey: "k")]
        let byKey = ["k": ["device:album:1", "device:album:2"]]
        let merged = ["server:x:al1": "device:album:2"]
        #expect(relinks(held, present: ["device:album:1", "device:album:2"], byKey: byKey, merged: merged)
            == [Relink(from: "server:x:al1", to: "device:album:2")])
    }

    @Test func aMergeOntoSomethingAlreadyHeldLeavesTheRowAsItWas() {
        let held = [Held(id: "server:x:al1", relinkKey: "k"), Held(id: "device:album:7", relinkKey: "k")]
        let merged = ["server:x:al1": "device:album:7"]
        #expect(relinks(held, present: ["device:album:7"], byKey: [:], merged: merged).isEmpty)
    }

    @Test func aVanishedAlbumWentWhereMostOfItsSongsWent() {
        // A deluxe edition: 12 songs joined the phone's album, 3 bonus songs an album of their
        // own. Ties go to the first id, the same every time.
        let counts = [
            CopyCount(serverRowId: "server:x:deluxe", libraryId: "device:album:1", songs: 12),
            CopyCount(serverRowId: "server:x:deluxe", libraryId: "server:x:bonus", songs: 3),
            CopyCount(serverRowId: "server:x:ep", libraryId: "device:album:9", songs: 2),
            CopyCount(serverRowId: "server:x:ep", libraryId: "device:album:4", songs: 2),
        ]
        #expect(mergedInto(counts) == ["server:x:deluxe": "device:album:1", "server:x:ep": "device:album:4"])
    }

    // Pins

    private func pin(_ id: String, _ position: Int, _ kind: PinKind = .album) -> PinnedItem {
        PinnedItem(kind: kind.rawValue, itemId: id, relinkKey: id, position: position)
    }

    private func ids(_ pins: [PinnedItem]) -> [String] { pins.map(\.itemId) }

    @Test func aNewPinGoesAtTheEnd() throws {
        let pins = [pin("b", 1), pin("a", 0)]
        let after = try #require(withPin(pins, add: pin("c", 99, .playlist), showing: 2))
        #expect(ids(after) == ["a", "b", "c"])
        #expect(after.map(\.position) == [0, 1, 2])
    }

    @Test func pinningTwiceChangesNothing() {
        let pins = [pin("a", 0), pin("b", 1)]
        #expect(withPin(pins, add: pin("a", 5), showing: 2) == pins)
    }

    @Test func theSameIdOfAnotherKindIsAnotherPin() throws {
        let pins = [pin("x", 0)]
        #expect(try #require(withPin(pins, add: pin("x", 0, .artist), showing: 1)).count == 2)
    }

    @Test func homeHoldsTwelve() {
        let pins = (0..<pinLimit).map { pin("p\($0)", $0) }
        #expect(withPin(pins, add: pin("one more", 0), showing: pinLimit) == nil)
        // Something already pinned is still fine to pin again.
        #expect(withPin(pins, add: pin("p3", 0), showing: pinLimit) == pins)
    }

    @Test func pinsHomeCannotShowDoNotCountAgainstTheLimit() throws {
        // Twelve rows, but two point at albums of a server that is signed out.
        let pins = (0..<pinLimit).map { pin("p\($0)", $0) }
        let after = try #require(withPin(pins, add: pin("new", 0), showing: pinLimit - 2))
        #expect(after.last?.itemId == "new")
    }

    @Test func unpinningClosesTheGap() {
        let pins = [pin("a", 0), pin("b", 1), pin("c", 2)]
        let after = withoutPin(pins, kind: PinKind.album.rawValue, itemId: "b")
        #expect(ids(after) == ["a", "c"])
        #expect(after.map(\.position) == [0, 1])
        // Something not pinned leaves the row as it was.
        #expect(withoutPin(pins, kind: PinKind.artist.rawValue, itemId: "a") == pins)
    }

    @Test func moveToFrontKeepsTheRestInOrder() {
        let pins = [pin("a", 0), pin("b", 1), pin("c", 2), pin("d", 3)]
        let after = movedToFront(pins, kind: PinKind.album.rawValue, itemId: "c")
        #expect(ids(after) == ["c", "a", "b", "d"])
        #expect(after.map(\.position) == [0, 1, 2, 3])
        #expect(movedToFront(pins, kind: PinKind.album.rawValue, itemId: "a") == pins)
        #expect(movedToFront(pins, kind: PinKind.album.rawValue, itemId: "missing") == pins)
    }

    @Test func pinKindsReadBackFromWhatIsSaved() {
        for kind in [PinKind.album, .artist, .playlist] { #expect(PinKind.of(kind.rawValue) == kind) }
        #expect(PinKind(rawValue: "song") == nil)
    }
}
