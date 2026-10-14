import Testing
@testable import OctoKit

@Suite struct ArtPlacementTests {
    @Test func aTallPhoneGetsFullWidthArtworkNearTheTop() {
        // About an iPhone 14 Pro Max's room once the top line and the controls are placed.
        let place = ArtPlacement.upright(width: 382, height: 492)
        #expect(place.side == 382)
        let spare = 492 - 382 - ArtPlacement.topMargin - ArtPlacement.bottomMargin
        #expect(place.top == ArtPlacement.topMargin + spare / 3)
        // Less room above than below: the artwork does not float in the middle.
        #expect(place.top < 492 - place.top - place.side)
    }

    @Test func aSmallPhoneShrinksTheArtworkAndCutsNothing() {
        // About an iPhone SE's room.
        let place = ArtPlacement.upright(width: 327, height: 300)
        #expect(place.side == 300 - ArtPlacement.topMargin - ArtPlacement.bottomMargin)
        #expect(place.top == ArtPlacement.topMargin)
        #expect(place.top + place.side + ArtPlacement.bottomMargin <= 300)
    }

    @Test func noRoomIsNoArtworkNeverANegativeSize() {
        #expect(ArtPlacement.upright(width: 300, height: 10).side == 0)
        #expect(ArtPlacement.upright(width: 300, height: 10).top <= 10)
        #expect(ArtPlacement.upright(width: -5, height: -5) == ArtPlacement(side: 0, top: 0))
    }

    @Test func theSameRoomPlacesTheArtworkTheSameWay() {
        #expect(ArtPlacement.upright(width: 345, height: 420) == ArtPlacement.upright(width: 345, height: 420))
    }
}
