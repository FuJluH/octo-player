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

@Suite struct GlassPopupTests {
    private let window = PopupSize(1080, 2400)
    private let menu = PopupSize(600, 500)

    private func place(_ anchor: PopupRect?, _ size: PopupSize? = nil, top: Double = 0, bottom: Double = 0) -> PopupSpot {
        placePopup(anchor: anchor, size: size ?? menu, window: window, margin: 36, gap: 18, top: top, bottom: bottom)
    }

    private func rect(_ l: Double, _ t: Double, _ r: Double, _ b: Double) -> PopupRect {
        PopupRect(left: l, top: t, right: r, bottom: b)
    }

    @Test func aControlOnTheLeftGetsTheListUnderItFromItsStartEdge() {
        let spot = place(rect(40, 300, 240, 400))
        #expect(spot == PopupSpot(x: 40, y: 418, above: false, fromEnd: false))
        #expect(spot.origin == (0, 0))
    }

    @Test func aControlOnTheRightGetsTheListLinedUpWithItsEndEdge() {
        let spot = place(rect(800, 300, 1040, 400))
        #expect(spot == PopupSpot(x: 440, y: 418, above: false, fromEnd: true))
        #expect(spot.origin == (1, 0))
    }

    @Test func nearTheBottomItFlipsAboveTheControl() {
        let spot = place(rect(800, 2000, 1040, 2100), PopupSize(600, 800))
        #expect(spot.above)
        #expect(spot.y == 2000 - 18 - 800)
        #expect(spot.origin == (1, 1))
    }

    @Test func theSystemBarsCountAsEdges() {
        let anchor = rect(40, 1700, 240, 1800)
        #expect(!place(anchor, PopupSize(600, 500)).above)
        #expect(place(anchor, PopupSize(600, 500), bottom: 200).above)
        let high = place(rect(40, 0, 240, 60), PopupSize(600, 500), top: 120)
        #expect(high.y >= 120 + 36)
    }

    @Test func tooTallForEitherSideItTakesTheRoomierOneAndStaysOnScreen() {
        let tall = PopupSize(600, 1500)
        let spot = place(rect(40, 1100, 240, 1200), tall)
        #expect(!spot.above)
        #expect(spot.y == 2400 - 36 - 1500)
        let higher = place(rect(40, 1300, 240, 1400), tall)
        #expect(higher.above)
        #expect(higher.y == 36)
    }

    @Test func itKeepsTheMarginFromBothSides() {
        #expect(place(rect(0, 300, 100, 400)).x == 36)
        #expect(place(rect(980, 300, 1080, 400)).x == 1080 - 36 - 600)
        #expect(place(rect(900, 300, 1000, 400), PopupSize(1200, 500)).x == 36)
    }

    @Test func withNoControlItSitsInTheMiddle() {
        let spot = place(nil)
        #expect(spot.centered)
        #expect(spot.x == 240)
        #expect(spot.y == 36 + (2400 - 72 - 500) / 2)
        #expect(spot.origin == (0.5, 0.5))
    }

    @Test func itKeepsTheSideItOpenedOnWhileItFits() {
        let anchor = rect(40, 1000, 240, 1100)
        let opened = placePopup(anchor: anchor, size: PopupSize(600, 400), window: window, margin: 36, gap: 18, keepAbove: true)
        #expect(opened.above)
        let fresh = placePopup(anchor: anchor, size: PopupSize(600, 400), window: window, margin: 36, gap: 18)
        #expect(!fresh.above)
    }
}

@Suite struct PopupPlacementAtTests {
    private let window = PopupSize(1000, 700)
    private let size = PopupSize(200, 300)

    @Test func aPointMenuOpensDownAndRightOfThePointer() {
        let at = placePopupAt(point: (100, 100), anchor: nil, size: size, window: window, margin: 10)
        #expect(at.x == 100 && at.y == 100)
    }

    @Test func nearTheCornerItFlipsUpAndLeft() {
        let at = placePopupAt(point: (950, 650), anchor: nil, size: size, window: window, margin: 10)
        #expect(at.x == 750 && at.y == 350)
    }

    @Test func underAControlOnTheFarSideItLinesUpWithTheEnd() {
        let at = placePopupAt(point: nil, anchor: PopupRect(left: 800, top: 40, right: 900, bottom: 80), size: size, window: window, margin: 10, gap: 6)
        #expect(at.x == 700 && at.y == 86)
    }

    @Test func aControlNearTheBottomOpensItAbove() {
        let at = placePopupAt(point: nil, anchor: PopupRect(left: 100, top: 600, right: 150, bottom: 640), size: size, window: window, margin: 10, gap: 6)
        #expect(at.x == 100 && at.y == 294)
    }

    @Test func withNothingToOpenFromItIsCentered() {
        let at = placePopupAt(point: nil, anchor: nil, size: size, window: window, margin: 10)
        #expect(at.x == 400 && at.y == 200)
    }
}

@Suite struct PopupPagesTests {
    private let start = PageTrail.of("actions")

    @Test func itStartsOnItsFirstPageWithNoWayBack() {
        #expect(start.current == "actions")
        #expect(!start.canGoBack)
    }

    @Test func openingAPageGoesDeeperWithAWayBack() {
        let info = start.open("info")
        #expect(info.current == "info")
        #expect(info.canGoBack)
        #expect(info.deeper)
        #expect(info.pages == ["actions", "info"])
    }

    @Test func backReturnsToThePageBeforeAndSlidesTheOtherWay() {
        let back = start.open("playlists").open("new").back()
        #expect(back.current == "playlists")
        #expect(!back.deeper)
        #expect(back.canGoBack)
        #expect(back.back().current == "actions")
    }

    @Test func backOnTheFirstPageChangesNothing() {
        #expect(start.back() == start)
    }

    @Test func replacingKeepsTheDepth() {
        let asked = start.open("question").replace("answer")
        #expect(asked.pages == ["actions", "answer"])
        #expect(asked.back().current == "actions")
    }

    @Test func startingOverIsANewOpeningEvenOnTheSamePage() {
        let again = start.open("info").restart("actions")
        #expect(again.pages == ["actions"])
        #expect(!again.canGoBack)
        #expect(start != again)
        #expect(again.opening == start.opening + 1)
        #expect(again.open("rate").back().opening == again.opening)
    }

    @Test func aTrailAlwaysHasAPage() {
        #expect(PageTrail<String>([]) == nil)
    }

    @Test func aSmallControlIsItsOwnAnchor() {
        let button = PopupRect(left: 900, top: 200, right: 1000, bottom: 300)
        #expect(menuAnchor(bounds: button, fingerX: 950, fingerY: 250, windowWidth: 1080) == button)
    }

    @Test func aWideRowIsNarrowedToTheFingerKeepingItsTopAndBottom() {
        let row = PopupRect(left: 0, top: 600, right: 1080, bottom: 760)
        #expect(menuAnchor(bounds: row, fingerX: 300, fingerY: 700, windowWidth: 1080) == PopupRect(left: 300, top: 600, right: 300, bottom: 760))
    }

    @Test func aPressCountsForTwoSeconds() {
        var memory = PressMemory()
        let spot = PopupRect(left: 1, top: 2, right: 3, bottom: 4)
        #expect(memory.recent(at: 0) == nil)
        memory.pressed(spot, at: 10)
        #expect(memory.recent(at: 11.9) == spot)
        #expect(memory.recent(at: 12) == nil)
    }
}

@Suite struct GlassMenuTests {
    private func looks(_ count: Int, _ selected: Int) -> [String] {
        menuRowLooks(count: count, selected: selected).map { ($0.selected ? "pill" : "plain") + ($0.lineAbove ? " line" : "") }
    }

    @Test func theChosenOptionHasThePillAndNoLinesTouchIt() {
        #expect(looks(4, 1) == ["plain", "pill", "plain", "plain line"])
    }

    @Test func withNothingChosenEveryOptionAfterTheFirstHasALine() {
        #expect(looks(3, -1) == ["plain", "plain line", "plain line"])
    }

    @Test func theFirstAndLastOptionsCanBeChosen() {
        #expect(looks(3, 0) == ["pill", "plain", "plain line"])
        #expect(looks(3, 2) == ["plain", "plain line", "pill"])
    }

    @Test func onlyOneOptionIsEverChosen() {
        #expect(menuRowLooks(count: 6, selected: 3).filter(\.selected).count == 1)
        #expect(menuRowLooks(count: 6, selected: 9).filter(\.selected).isEmpty)
        #expect(menuRowLooks(count: 0, selected: 0).isEmpty)
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
