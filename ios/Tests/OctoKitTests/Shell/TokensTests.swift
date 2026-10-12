import Foundation
import Testing
@testable import OctoKit

/// Colors keep each channel to 1/255.
private let byte = 1.0 / 255.0 + 1e-4

@Suite struct TokensTests {
    @Test func theDurationsAreTheSpecsSet() {
        for d in [80, 140, 160, 180, 200, 300] { #expect(OctoDuration.all.contains(d)) }
    }

    @Test func reducedMotionScalesEveryDuration() {
        #expect(OctoDuration.all.count >= 6)
        for base in OctoDuration.all {
            #expect(MotionScale.full.ms(base) == base)
            #expect(MotionScale.reduced.ms(base) == Int((Double(base) * 0.5).rounded(.toNearestOrAwayFromZero)))
            #expect(MotionScale.reduced.ms(base) < base)
        }
    }

    @Test func aDurationMultiplierScalesEveryDurationByItself() {
        let slow = MotionScale(duration: 2)
        for base in OctoDuration.all { #expect(slow.ms(base) == base * 2) }
    }

    @Test func reducedMotionStopsEveryTravelAndGrowth() {
        let reduced = MotionScale.reduced
        #expect(reduced.still)
        #expect(reduced.travel(OctoPress.liftMedium) == 0)
        #expect(reduced.scale(OctoPress.pop) == 1)
        #expect(reduced.scale(OctoPress.scale) == 1)
        #expect(abs(MotionScale.full.scale(OctoPress.pop) - OctoPress.pop) < 1e-9)
        #expect(MotionScale.full.travel(OctoPress.liftSmall) == 1)
    }

    @Test func theSystemAnimatorScaleOnlyCountsWhenOff() {
        #expect(MotionScale.of(systemAnimatorScale: 1, reduce: false) == .full)
        #expect(MotionScale.of(systemAnimatorScale: 1.5, reduce: false) == .full)
        #expect(MotionScale.of(systemAnimatorScale: 0, reduce: false) == .reduced)
        #expect(MotionScale.of(systemAnimatorScale: 1, reduce: true) == .reduced)
        #expect(MotionScale.of(systemReduced: true, reduce: false) == .reduced)
        #expect(MotionScale.of(systemReduced: false, reduce: false) == .full)
    }

    @Test func theCurvesStartAtZeroAndEndAtOne() {
        for curve in OctoEasing.all {
            #expect(abs(curve.at(0)) < 1e-3)
            #expect(abs(curve.at(1) - 1) < 1e-3)
        }
        #expect((1...99).contains { OctoEasing.overshoot.at(Double($0) / 100) > 1 })
    }

    @Test func wordsAreBlackOnALightFillAndWhiteOnADarkOne() {
        #expect(contentColorFor(.white) == .black)
        #expect(contentColorFor(.black) == .white)
        #expect(contentColorFor(OctoPalette.accent) == .black)
        #expect(contentColorFor(OctoPalette.accentFill) == .white)
        #expect(contentColorFor(OctoPalette.accentTonal) == .white)
    }

    @Test func theSwitchFromWhiteToBlackWordsIsAtAbout58Percent() {
        let grays = (0...255).map { RGBA($0, $0, $0) }
        let below = grays.last { perceivedLightness($0) <= lightFillThreshold }!
        let above = grays.first { perceivedLightness($0) > lightFillThreshold }!
        #expect(contentColorFor(below) == .white)
        #expect(contentColorFor(above) == .black)
        #expect(abs(perceivedLightness(above) - 0.58) < 0.01)
        #expect(abs(perceivedLightness(RGBA(128, 128, 128)) - 0.536) < 0.005)
    }

    @Test func theAccentFamilyIsDerivedFromTheAccent() {
        let accent = OctoPalette.accent
        #expect(abs(accent.red * 0.4 - OctoPalette.accentSelected.red) < byte)
        #expect(abs(accent.green * 0.4 - OctoPalette.accentSelected.green) < byte)
        #expect(abs(accent.blue * 0.4 - OctoPalette.accentSelected.blue) < byte)
        let gray = 30.0 / 255.0
        #expect(abs(gray + (accent.red - gray) * 0.1 - OctoPalette.accentTonal.red) < byte)
        #expect(abs(gray + (accent.blue - gray) * 0.1 - OctoPalette.accentTonal.blue) < byte)
        #expect(OctoPalette.focusRing == accent.opacity(0.7))
        #expect(OctoPalette.menuPress == OctoPalette.accentSelected.opacity(0.55))
        #expect(OctoPalette.destructive == OctoPalette.signalRed.opacity(0.85))
    }

    @Test func theDerivedColorsAreTheNamedOnes() {
        #expect(OctoPalette.surfaceRaised.hex == 0x222324)
        #expect(OctoPalette.accentTonal.hex == 0x2A2D2E)
        #expect(OctoPalette.accentSelected.hex == 0x3C474A)
        #expect(OctoPalette.accentFill.hex == 0x536166)
        #expect(OctoPalette.sheetFill.hex == 0x131416)
        #expect(abs(OctoPalette.sheetFill.alpha - 0.97) < 1e-9)
    }

    @Test func theTextHierarchyIsWhiteAtFallingOpacities() {
        let levels = [OctoInk.primary, OctoInk.secondary, OctoInk.tertiary, OctoInk.quaternary, OctoInk.quinary]
        for (want, color) in zip([0.85, 0.55, 0.25, 0.10, 0.05], levels) { #expect(abs(color.alpha - want) < 0.003) }
        #expect(levels.allSatisfy { $0.red == 1 && $0.green == 1 && $0.blue == 1 })
    }

    @Test func theRadiiAreTheSpecs() {
        #expect([OctoRadii.chrome, OctoRadii.chromeSmall, OctoRadii.row] == [10, 6, 12])
        #expect([OctoRadii.artXs, OctoRadii.artS, OctoRadii.artM, OctoRadii.artL] == [3, 6, 8, 12])
        #expect(OctoRadii.dialog == 12)
    }

    @Test func anIconGesturePeaksAt45PercentAndRestsAtEitherEnd() {
        #expect(accentStrength(0) == 0)
        #expect(accentStrength(1) == 0)
        #expect(abs(accentStrength(accentPeak) - 1) < 1e-3)
        #expect(accentStrength(0.2) < 1 && accentStrength(0.8) < 1)
        #expect(abs(accentPose(.pulse, accentPeak).scale - 1.2) < 1e-3)
        #expect(abs(accentPose(.slideForward, accentPeak).dx - 4) < 1e-3)
        #expect(abs(accentPose(.slideBack, accentPeak).dx + 4) < 1e-3)
        for accent in IconAccent.allCases { #expect(accentPose(accent, accentPeak, distance: 0) == .rest) }
    }

    @Test func theTabsThePillPassesFlashAndTheOneItLandsOnDoesNot() {
        #expect(abs(gearShiftTint(1, pill: 1, selected: 3) - gearShiftTintMax) < 1e-9)
        #expect(abs(gearShiftTint(2, pill: 1.5, selected: 3) - gearShiftTintMax / 2) < 1e-9)
        #expect(gearShiftTint(3, pill: 3, selected: 3) == 0)
        #expect(gearShiftTint(0, pill: 2, selected: 3) == 0)
    }

    @Test func aSliderSnapsToItsSteps() {
        #expect(abs(snapToSteps(0.3, 4) - 0.25) < 1e-9)
        #expect(abs(snapToSteps(0.4, 4) - 0.5) < 1e-9)
        #expect(abs(snapToSteps(0.3, 0) - 0.3) < 1e-9)
        #expect(snapToSteps(1.4, 0) == 1)
        #expect(!(snapToSteps(-1, 3) < 0))
    }

    private func thumb(_ position: Double, _ stretch: Double) -> SwitchThumb {
        switchThumb(track: 36, thumb: 18, padding: 2, position: position, stretch: stretch)
    }

    @Test func theSwitchThumbSitsAtEitherEndAtRest() {
        #expect(thumb(0, 0) == SwitchThumb(2, 18))
        #expect(thumb(1, 0) == SwitchThumb(16, 18))
    }

    @Test func aHeldThumbStretches18PercentFromTheSideItIsLeaving() {
        let off = thumb(0, 1)
        #expect(abs(off.width - 18 * switchSquish) < 1e-4)
        #expect(abs(off.x - 2) < 1e-4)
        let on = thumb(1, 1)
        #expect(abs(on.width - 18 * switchSquish) < 1e-4)
        #expect(abs(on.x + on.width - 34) < 1e-4)
    }

    @Test func theSwitchSizesAreTheSpecs() {
        #expect([SwitchSize.small.width, SwitchSize.small.height, SwitchSize.small.thumb] == [30, 18, 14])
        #expect([SwitchSize.standard.width, SwitchSize.standard.height, SwitchSize.standard.thumb] == [36, 22, 18])
        #expect([SwitchSize.large.width, SwitchSize.large.height, SwitchSize.large.thumb] == [44, 26, 22])
    }

    @Test func theButtonSizesAreTheSpecs() {
        let sizes: [ButtonSize] = [.extraSmall, .small, .medium, .large]
        #expect(sizes.map(\.height) == [24, 30, 36, 50])
        #expect(sizes.map(\.dense) == [20, 24, 28, 40])
    }

    @Test func aSpringsResponseComesFromItsStiffness() {
        #expect(abs(SpringSpec(0.75, 200).response - 0.4443) < 1e-3)
        #expect(OctoSprings.calm == SpringSpec(0.9, 500))
    }
}
