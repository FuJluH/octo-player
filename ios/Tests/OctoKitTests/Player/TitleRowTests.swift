import Foundation
import Testing
@testable import OctoKit

@Suite struct TitleRowTests {
    @Test func theButtonsSitOnTheMiddleOfTheCapitals() {
        #expect(capMiddle(baseline: 23, capHeight: 17) == 14.5)
        #expect(PlayerTitleRow.iconAlpha == 0.7)
        #expect(PlayerTitleRow.heightOverCap >= 1.1 && PlayerTitleRow.heightOverCap <= 1.2)
        #expect(PlayerTitleRow.buttonSize >= 44)
    }

    @Test func theGapsBetweenTheIconsAndToTheEdgeAreEven() {
        // A 44 point target, a heart 10 across each way and dots 9: a 25 point gap between them,
        // so the dots end 25 in from the screen's edge.
        let reach = titleButtonsReach(sideMargin: 24, buttonSize: 44, heartHalf: 10, dotsHalf: 9)
        // The dots' right edge: 22 + 9 = 31 points in from the buttons' right edge.
        let dotsFromScreenEdge = 24 - (reach - (22 - 9))
        #expect(abs(dotsFromScreenEdge - (44 - 10 - 9)) < 1e-9)
        #expect(titleButtonsReach(sideMargin: 0, heartHalf: 10, dotsHalf: 9) == 0)
    }

    @Test func theQuietIconsKeepFourAndAHalfToOne() {
        // On a dark background 70% white reads.
        #expect(quietAlpha(0xFF10_1010, ink: 0xFFFF_FFFF, soft: 0.7) == 0.7)
        // On a mid gray it needs more.
        let raised = quietAlpha(0xFF70_7070, ink: 0xFFFF_FFFF, soft: 0.7)
        #expect(raised > 0.7)
        #expect(contrastRatio(overlay(0xFFFF_FFFF, raised, 0xFF70_7070), 0xFF70_7070) >= 4.5 - 1e-6)
        // Where even full white cannot read, it stays full.
        #expect(quietAlpha(0xFFF0_F0F0, ink: 0xFFFF_FFFF, soft: 0.7) == 1)
    }

    @Test func theIconsSitOnTheBackgroundsHardestPart() {
        let range = WashRange(0xFF20_2020, 0xFFE0_E0E0)
        #expect(quietIconsUnder(nil, base: 0xFF0C_0C0D, dark: false, show: 1) == 0xFF0C_0C0D)
        #expect(quietIconsUnder(range, base: 0xFF00_0000, dark: true, show: 1) == 0xFF20_2020)
        #expect(quietIconsUnder(range, base: 0xFF00_0000, dark: false, show: 0.5) == overlay(0xFFE0_E0E0, 0.5, 0xFF00_0000))
    }

    @Test func aLongLineRestsThenScrollsThreeTimesThenRestsForGood() {
        let distance = 300.0
        #expect(Marquee.at(0.5, distance: distance) == (0, 0))
        let moving = Marquee.at(Marquee.rest + 1, distance: distance)
        #expect(abs(moving.offset - Marquee.speed) < 1e-9)
        #expect(moving.leftFade == 1)
        // Just started: the left fade is coming in.
        #expect(Marquee.at(Marquee.rest + 0.1, distance: distance).leftFade < 1)
        // Past the last pass: at rest, the first letter crisp.
        #expect(Marquee.at(Marquee.duration(distance: distance) + 1, distance: distance) == (0, 0))
        #expect(Marquee.fade >= 24 && Marquee.fade <= 32)
    }

    @Test func theFadeEasesFromShownToGone() {
        let stops = Marquee.easedOut
        #expect(stops.first!.alpha == 1)
        #expect(stops.last!.alpha == 0)
        #expect(zip(stops, stops.dropFirst()).allSatisfy { $0.alpha >= $1.alpha })
    }
}
