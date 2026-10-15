import Foundation
import Testing
@testable import OctoKit

@Suite struct FullScreenLookTests {
    @Test func theNumbersAreTheTuningPagesOwn() {
        #expect(FullScreenLook.zoom == 1.10)
        #expect(FullScreenLook.top == -0.005)
        #expect(FullScreenLook.meltStart == 0.505)
        #expect(FullScreenLook.meltEnd == 0.68)
        #expect(FullScreenLook.sideFeather == 0)
        #expect(FullScreenLook.darkening == 0)
        #expect(abs(FullScreenLook.backgroundGain - 1.290) < 0.001)
    }

    @Test func theMeltIsASmoothstep() {
        #expect(FullScreenLook.melt(0) == 0)
        #expect(FullScreenLook.melt(1) == 1)
        #expect(FullScreenLook.melt(0.5) == 0.5)
        #expect(abs(FullScreenLook.melt(0.25) - 0.15625) < 1e-9)
        #expect(FullScreenLook.melt(-1) == 0)
        #expect(FullScreenLook.melt(2) == 1)
    }

    @Test func onAFourteenProMaxTheMeltEndsAtTheLoopsBottom() {
        // A 2048 x 2732 loop on a 430 x 932 pt screen.
        let place = FullScreenLook.place(width: 430, height: 932, shape: 2732.0 / 2048.0)
        #expect(abs(place.width - 473) < 0.01)
        #expect(abs(place.height - 631.0) < 0.1)
        #expect(abs(place.top - -4.66) < 0.01)
        #expect(abs(place.meltFrom - 470.66) < 0.01)
        // 68% of the screen would be 633.8 pt, past the loop's own bottom at 626.3 pt.
        #expect(abs(place.meltTo - (place.top + place.height)) < 0.001)
        #expect(abs(place.meltTo - 626.3) < 0.1)
    }

    @Test func onAShorterLoopTheMeltStillEndsByItsBottom() {
        let place = FullScreenLook.place(width: 430, height: 932, shape: 1)
        #expect(place.meltTo <= place.top + place.height)
        #expect(place.meltFrom < place.meltTo)
    }
}
