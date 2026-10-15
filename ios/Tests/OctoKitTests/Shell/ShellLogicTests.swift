import Foundation
import Testing
@testable import OctoKit

@Suite struct SwipesTests {
    private let slop = 8.0

    @Test func nothingIsDecidedInsideTheSlop() {
        #expect(dragAxis(5, 5, slop: slop) == .undecided)
        #expect(dragAxis(0, -7.9, slop: slop) == .undecided)
    }

    @Test func theLargerMovementDecides() {
        #expect(dragAxis(9, 3, slop: slop) == .horizontal)
        #expect(dragAxis(-9, 3, slop: slop) == .horizontal)
        #expect(dragAxis(3, 9, slop: slop) == .vertical)
        #expect(dragAxis(3, -9, slop: slop) == .vertical)
    }

    @Test func aDiagonalCrossesTheSlopBeforeEitherAxisDoes() {
        #expect(dragAxis(7, 4.5, slop: slop) == .horizontal)
        #expect(dragAxis(4.5, 7, slop: slop) == .vertical)
    }

    @Test func aTieGoesToThePullDown() {
        #expect(dragAxis(6, 6, slop: slop) == .vertical)
        #expect(dragAxis(-6, 6, slop: slop) == .vertical)
    }

    private let distance = 100.0
    private let fling = 1_000.0

    @Test func farEnoughSkipsLeftToNextRightToPrevious() {
        #expect(swipeSkip(offset: -120, velocity: 0, distance: distance, fling: fling) == .next)
        #expect(swipeSkip(offset: 120, velocity: 0, distance: distance, fling: fling) == .previous)
        #expect(swipeSkip(offset: -60, velocity: 0, distance: distance, fling: fling) == .stay)
    }

    @Test func aFlickSkipsOnlyTheWayItWasGoing() {
        #expect(swipeSkip(offset: -30, velocity: -1_500, distance: distance, fling: fling) == .next)
        #expect(swipeSkip(offset: 30, velocity: 1_500, distance: distance, fling: fling) == .previous)
        #expect(swipeSkip(offset: -30, velocity: 1_500, distance: distance, fling: fling) == .stay)
        #expect(swipeSkip(offset: 0, velocity: -1_500, distance: distance, fling: fling) == .stay)
    }

    @Test func farEnoughStillSkipsWhenLetGoMovingBack() {
        #expect(swipeSkip(offset: -150, velocity: 300, distance: distance, fling: fling) == .next)
    }

    @Test func onlyAPullUpOpens() {
        #expect(swipeUp(offset: -40, velocity: 0, distance: 30, fling: fling))
        #expect(swipeUp(offset: -10, velocity: -1_200, distance: 30, fling: fling))
        #expect(!swipeUp(offset: -10, velocity: 0, distance: 30, fling: fling))
        #expect(!swipeUp(offset: 40, velocity: 0, distance: 30, fling: fling))
        #expect(!swipeUp(offset: 10, velocity: -1_200, distance: 30, fling: fling))
    }

    @Test func progressIsAClampedFractionAndZeroWithoutALength() {
        #expect(fractionAt(positionMs: 30_000, durationMs: 120_000) == 0.25)
        #expect(fractionAt(positionMs: 130_000, durationMs: 120_000) == 1)
        #expect(fractionAt(positionMs: -5, durationMs: 120_000) == 0)
        #expect(fractionAt(positionMs: 5_000, durationMs: 0) == 0)
    }
}

@Suite struct SelectionTests {
    private func song(_ id: String) -> Song {
        Song(id: id, title: id)
    }

    @Test func nothingPickedIsNotPicking() {
        #expect(!Picks().active)
    }

    @Test func startingPicksJustThatSong() {
        let picks = Picks(["a", "b"]).start("c")
        #expect(picks.keys == ["c"])
        #expect(picks.active)
    }

    @Test func aTapTogglesAndTakingTheLastOffEndsPicking() {
        var picks = Picks().start("a")
        picks = picks.toggle("b")
        #expect(picks.keys == ["a", "b"])
        picks = picks.toggle("a")
        #expect(picks.keys == ["b"])
        picks = picks.toggle("b")
        #expect(!picks.active)
    }

    @Test func songsThatLeaveTheListLeaveThePicks() {
        let picks = Picks(["a", "b", "c"])
        #expect(picks.keepOnly(["a", "c", "d"]).keys == ["a", "c"])
        #expect(picks.keepOnly(["a", "b", "c", "d"]) == picks)
        #expect(!picks.keepOnly([]).active)
    }

    @Test func pickedSongsComeInTheListsOrderNotThePickingOrder() {
        let list = ["a", "b", "c", "d"].map { Pickable(key: $0, song: song($0)) }
        let picks = Picks().start("d").toggle("a").toggle("c")
        #expect(picks.inOrder(list).map(\.key) == ["a", "c", "d"])
    }

    @Test func aSongTwiceOnAPlaylistIsPickedByItsRow() {
        let same = song("t")
        let list = [Pickable(key: "1", song: same), Pickable(key: "2", song: same)]
        #expect(Picks().start("2").inOrder(list).map(\.key) == ["2"])
    }

    @Test func theCountIsSaidInWords() {
        #expect(selectedWords(1) == "1 selected")
        #expect(selectedWords(3) == "3 selected")
    }
}

@Suite struct PageWordsTests {
    @Test func lengthsReadAsAClock() {
        #expect(asClock(187) == "3:07")
        #expect(asClock(3765) == "1:02:45")
        #expect(asClock(0) == "0:00")
    }

    @Test func longLengthsReadInWordsToTheNearestMinute() {
        #expect(asLength(48 * 60) == "48 min")
        #expect(asLength(72 * 60 + 29) == "1 hr 12 min")
        #expect(asLength(72 * 60 + 30) == "1 hr 13 min")
    }

    @Test func countsSayOneOrMany() {
        #expect(songsCount(1) == "1 song")
        #expect(songsCount(12) == "12 songs")
        #expect(albumsCount(1) == "1 album")
        #expect(albumsCount(0) == "0 albums")
    }

    @Test func failuresAreSaidInPlainWords() {
        #expect(userMessage(for: URLError(.cannotConnectToHost)) == "Couldn't reach the server. Check the address, and that you're on the right network.")
        #expect(userMessage(for: URLError(.cancelled)) == nil)
        #expect(userMessage(for: CancellationError()) == nil)
        #expect(userMessage(for: OctoError.http(503)) == "The server isn't answering right now. It may be restarting, so try again in a moment.")
        #expect(userMessage(for: OctoError.http(404)) == "That address answered, but not like a music server. Check the port.")
        #expect(userMessage(for: OctoError.notSubsonic) == "That address answered, but not like a music server. Check the port.")
        #expect(userMessage(for: OctoError.wrongCredentials("x")) == "Wrong username or password.")
        #expect(userMessage(for: OctoError.authUnsupported(code: 41, message: "")) == "This account can't sign in with a token. Turn on Legacy sign-in under Advanced.")
        #expect(userMessage(for: OctoError.authUnsupported(code: 42, message: "")) == "The server doesn't take this way of signing in.")
        #expect(userMessage(for: OctoError.notFound("")) == "That isn't on the server any more.")
        #expect(userMessage(for: OctoError.server(code: 0, message: "Disk full")) == "The server said: Disk full")
        struct Other: Error {}
        #expect(userMessage(for: Other()) == "Something went wrong.")
    }
}
