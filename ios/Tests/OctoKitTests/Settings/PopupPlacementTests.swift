import Foundation
import Testing
@testable import OctoKit

@Suite struct PopupPlacementTests {
    // A phone of 1080 by 2400, with a 36 margin and an 18 gap.
    private func place(_ anchor: PopupRect?, _ size: (Double, Double) = (600, 500), top: Double = 0, bottom: Double = 0) -> PopupSpot {
        PopupPlacement.place(anchor: anchor, width: size.0, height: size.1, screenWidth: 1080, screenHeight: 2400, margin: 36, gap: 18,
                             top: top, bottom: bottom)
    }

    private func rect(_ l: Double, _ t: Double, _ r: Double, _ b: Double) -> PopupRect { PopupRect(left: l, top: t, right: r, bottom: b) }

    @Test func aControlOnTheLeftGetsTheListUnderItFromItsStartEdge() {
        let spot = place(rect(40, 300, 240, 400))
        #expect(spot == PopupSpot(x: 40, y: 418))
        #expect(spot.origin == (0, 0))
    }

    @Test func aControlOnTheRightGetsTheListLinedUpWithItsEndEdge() {
        let spot = place(rect(800, 300, 1040, 400))
        #expect(spot == PopupSpot(x: 440, y: 418, fromEnd: true))
        #expect(spot.origin == (1, 0))
    }

    @Test func nearTheBottomItFlipsAboveTheControl() {
        let spot = place(rect(800, 2000, 1040, 2100), (600, 800))
        #expect(spot.above)
        #expect(spot.y == 2000 - 18 - 800)
        #expect(spot.origin == (1, 1))
    }

    @Test func theSystemBarsCountAsEdges() {
        let anchor = rect(40, 1700, 240, 1800)
        #expect(!place(anchor).above)
        #expect(place(anchor, bottom: 200).above)
        #expect(place(rect(40, 0, 240, 60), top: 120).y >= 120 + 36)
    }

    @Test func tooTallForEitherSideItTakesTheRoomierOneAndStaysOnScreen() {
        let spot = place(rect(40, 1100, 240, 1200), (600, 1500))
        #expect(!spot.above)
        #expect(spot.y == 2400 - 36 - 1500)
        let higher = place(rect(40, 1300, 240, 1400), (600, 1500))
        #expect(higher.above)
        #expect(higher.y == 36)
    }

    @Test func itKeepsTheMarginFromBothSides() {
        #expect(place(rect(0, 300, 100, 400)).x == 36)
        #expect(place(rect(980, 300, 1080, 400)).x == 1080 - 36 - 600)
        #expect(place(rect(900, 300, 1000, 400), (1200, 500)).x == 36)
    }

    @Test func withNoControlItSitsInTheMiddle() {
        let spot = place(nil)
        #expect(spot.centered)
        #expect(spot.x == 240)
        #expect(spot.y == 36 + ((2400 - 72 - 500) / 2).rounded(.down))
        #expect(spot.origin == (0.5, 0.5))
    }

    @Test func onceOpenItKeepsItsSideWhileItFits() {
        let anchor = rect(40, 1000, 240, 1100)
        let kept = PopupPlacement.place(anchor: anchor, width: 600, height: 500, screenWidth: 1080, screenHeight: 2400, margin: 36, gap: 18,
                                        keepAbove: true)
        #expect(kept.above)
    }
}
