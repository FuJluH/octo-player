import Foundation
import Testing
@testable import OctoKit

@Suite struct CoverFlightPlanTests {
    let bar = CGRect(x: 96, y: 721, width: 36, height: 36)
    let card = CGRect(x: 56, y: 128, width: 263, height: 263)

    @Test func theCoverLeavesBeforeThePlayerIsBuiltWhenItsPlaceIsKnown() {
        #expect(coverFlightStart(bar: bar, lastCard: card) == .now(to: card))
    }

    @Test func aFirstOpeningWaitsForTheCard() {
        #expect(coverFlightStart(bar: bar, lastCard: nil) == .afterCard)
        #expect(coverFlightStart(bar: bar, lastCard: .zero) == .afterCard)
    }

    @Test func withoutTheSmallPlayerNothingFlies() {
        #expect(coverFlightStart(bar: nil, lastCard: card) == CoverFlightStart.none)
        #expect(coverFlightStart(bar: .zero, lastCard: card) == CoverFlightStart.none)
    }

    @Test func thePlayerIsBuiltAFrameAfterTakeOff() {
        #expect(playerBuildDelayMs > 16 && playerBuildDelayMs < 50)
    }

    @Test func aFlightTurnsOnlyForAPlaceThatReallyMoved() {
        #expect(!flightNeedsRetarget(headed: card, placed: card))
        #expect(!flightNeedsRetarget(headed: card, placed: card.offsetBy(dx: 0.3, dy: -0.3)))
        #expect(flightNeedsRetarget(headed: card, placed: card.offsetBy(dx: 0, dy: 40)))
        #expect(flightNeedsRetarget(headed: card, placed: card.insetBy(dx: 20, dy: 20)))
    }

    @Test func springsKeepTheirFeel() {
        // Critically damped at stiffness 400 is damping 40, as SwiftUI's own spring of response
        // 2 pi / 20 with damping fraction 1.
        #expect(abs(springDamping(ratio: 1, stiffness: 400) - 40) < 1e-9)
        #expect(abs(springDamping(ratio: 1, stiffness: 1500) - 2 * 1500.0.squareRoot()) < 1e-9)
        #expect(abs(springDamping(ratio: 0.5, stiffness: 400) - 20) < 1e-9)
    }
}

@Suite struct CoverFlightSpringTests {
    @Test func theFlightLandsOnceItIsWithinAHairOfTheCard() {
        let t = criticalSpringSeconds(stiffness: 400)
        #expect(t > 0.4 && t < 0.5)
        // Within a thousandth of the way: under a point on the longest flight on a phone.
        #expect((1 + 20 * t) * exp(-20 * t) <= 0.001)
        #expect(criticalSpringSeconds(stiffness: 1500) < t)
    }
}
