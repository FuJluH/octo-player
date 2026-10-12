import Testing
@testable import OctoKit

@Suite struct SoundPopupTests {
    // A window of 1080 by 2400, with a 36 margin and an 18 gap.
    let windowWidth = 1_080
    let windowHeight = 2_400

    func place(_ anchor: SoundPopup.Box?, width: Int = 600, height: Int = 500, top: Int = 0, bottom: Int = 0) -> SoundPopup.Spot {
        SoundPopup.place(anchor: anchor, width: width, height: height, windowWidth: windowWidth, windowHeight: windowHeight,
                         margin: 36, gap: 18, top: top, bottom: bottom)
    }

    @Test func aControlOnTheLeftGetsTheCardUnderItFromItsStartEdge() {
        let spot = place(SoundPopup.Box(40, 300, 240, 400))
        #expect(spot == SoundPopup.Spot(x: 40, y: 418, above: false, fromEnd: false))
        #expect(spot.origin == (0, 0))
    }

    @Test func aControlOnTheRightGetsTheCardLinedUpWithItsEndEdge() {
        let spot = place(SoundPopup.Box(800, 300, 1_040, 400))
        #expect(spot == SoundPopup.Spot(x: 440, y: 418, above: false, fromEnd: true))
        #expect(spot.origin == (1, 0))
    }

    @Test func nearTheBottomItFlipsAboveTheControl() {
        let spot = place(SoundPopup.Box(800, 2_000, 1_040, 2_100), height: 800)
        #expect(spot.above)
        #expect(spot.y == 2_000 - 18 - 800)
        #expect(spot.origin == (1, 1))
    }

    @Test func theSystemBarsCountAsEdges() {
        let anchor = SoundPopup.Box(40, 1_700, 240, 1_800)
        #expect(!place(anchor).above)
        #expect(place(anchor, bottom: 200).above)
        let high = place(SoundPopup.Box(40, 0, 240, 60), top: 120)
        #expect(high.y >= 120 + 36)
    }

    @Test func tooTallForEitherSideItTakesTheRoomierOneAndStaysOnScreen() {
        let spot = place(SoundPopup.Box(40, 1_100, 240, 1_200), height: 1_500)
        #expect(!spot.above)
        #expect(spot.y == 2_400 - 36 - 1_500)
        let higher = place(SoundPopup.Box(40, 1_300, 240, 1_400), height: 1_500)
        #expect(higher.above)
        #expect(higher.y == 36)
    }

    @Test func itKeepsTheMarginFromBothSides() {
        #expect(place(SoundPopup.Box(0, 300, 100, 400)).x == 36)
        #expect(place(SoundPopup.Box(980, 300, 1_080, 400)).x == 1_080 - 36 - 600)
        #expect(place(SoundPopup.Box(900, 300, 1_000, 400), width: 1_200).x == 36)
    }

    @Test func withNoControlItSitsInTheMiddle() {
        let spot = place(nil)
        #expect(spot.centered)
        #expect(spot.x == 240)
        #expect(spot.y == 36 + (2_400 - 72 - 500) / 2)
        #expect(spot.origin == (0.5, 0.5))
    }

    @Test func aWideRowIsNarrowedToTheFinger() {
        #expect(SoundPopup.anchor(bounds: SoundPopup.Box(0, 10, 1_000, 60), fingerX: 300, windowWidth: 1_080) == SoundPopup.Box(300, 10, 300, 60))
        #expect(SoundPopup.anchor(bounds: SoundPopup.Box(0, 10, 200, 60), fingerX: 30, windowWidth: 1_080) == SoundPopup.Box(0, 10, 200, 60))
    }
}
