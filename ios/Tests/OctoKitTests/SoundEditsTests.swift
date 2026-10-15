import Foundation
import Testing
@testable import OctoKit

@Suite struct SoundEditsTests {
    let rock = eqPresets.first { $0.name == "Rock" }!

    @Test func aPresetSetsTheBandsAndSwitchesToGraphic() {
        var before = SoundSettings()
        before.mode = .parametric
        before.preset = nil
        let after = SoundEdits.withPreset(before, rock)
        #expect(after.graphicGains == rock.gains)
        #expect(after.mode == .graphic)
        #expect(after.preset == "Rock")
        #expect(after.eqEnabled)
        #expect(SoundEdits.presetLabel(after) == "Rock")
    }

    @Test func movingABandByHandMakesTheCurveCustom() {
        let after = SoundEdits.withBandGain(SoundEdits.withPreset(SoundSettings(), rock), band: 3, gainDb: 20)
        #expect(after.graphicGains[3] == 12)
        #expect(after.preset == nil)
        #expect(SoundEdits.presetLabel(after) == SoundEdits.custom)
    }

    @Test func gainsSnapToZeroAndToTenths() {
        #expect(SoundEdits.cleanGain(0.2) == 0)
        #expect(SoundEdits.cleanGain(-0.24) == 0)
        #expect(SoundEdits.cleanGain(3.46) == 3.5)
        #expect(SoundEdits.cleanGain(-30) == -12)
    }

    @Test func parametricStartsFromTheTenBands() {
        let graphic = SoundEdits.withPreset(SoundSettings(), rock)
        let after = SoundEdits.withMode(graphic, .parametric)
        #expect(after.mode == .parametric)
        #expect(after.filters.count == graphicBands.count)
        for (i, filter) in after.filters.enumerated() {
            #expect(filter == EqFilter(type: .peak, frequency: graphicBands[i], gainDb: rock.gains[i], q: graphicQ))
        }
        let heard = ResponseCurve.curve(graphic.activeFilters())
        let same = ResponseCurve.curve(after.activeFilters())
        for (a, b) in zip(heard, same) { #expect(abs(a - b) < 0.0001) }
    }

    @Test func flatBandsLeaveEarlierFiltersAlone() {
        let own = [EqFilter(type: .peak, frequency: 3_000, gainDb: -4, q: 2)]
        var settings = SoundSettings()
        settings.filters = own
        #expect(SoundEdits.withMode(settings, .parametric).filters == own)
    }

    @Test func goingBackToGraphicKeepsTheBands() {
        let parametric = SoundEdits.withMode(SoundEdits.withPreset(SoundSettings(), rock), .parametric)
        let back = SoundEdits.withMode(parametric, .graphic)
        #expect(back.graphicGains == rock.gains)
        #expect(SoundEdits.presetLabel(back) == "Rock")
    }

    @Test func newFiltersGoInTheWidestGapAndStopAtSixteen() {
        var start = SoundSettings()
        start.mode = .parametric
        let none = SoundEdits.withNewFilter(start)
        #expect(none.filters.count == 1)
        #expect(none.filters[0].frequency == 630)
        #expect(none.filters[0].gainDb == 0)
        var full = start
        for _ in 0..<20 { full = SoundEdits.withNewFilter(full) }
        #expect(full.filters.count == SoundEdits.maxFilters)
        #expect(SoundEdits.withNewFilter(full) == full)
    }

    @Test func filterEditsStayInRange() {
        var settings = SoundSettings()
        settings.mode = .parametric
        settings.filters = [EqFilter(type: .peak, frequency: 1_000, gainDb: 0, q: 1)]
        let after = SoundEdits.withFilter(settings, index: 0, EqFilter(type: .highShelf, frequency: 50_000, gainDb: 40, q: 0))
        #expect(after.filters[0] == EqFilter(type: .highShelf, frequency: SoundEdits.maxHz, gainDb: 12, q: SoundEdits.minQ))
        #expect(SoundEdits.withoutFilter(after, index: 0).filters.isEmpty)
    }

    @Test func readingsAreShortAndPlain() {
        #expect(SoundEdits.readDb(3.5) == "+3.5 dB")
        #expect(SoundEdits.readDb(-2) == "-2 dB")
        #expect(SoundEdits.readDb(-0.01) == "0 dB")
        #expect(SoundEdits.describeNode(hz: 62, db: 3) == "62 Hz, +3 dB")
        #expect(SoundEdits.shortHz(1_000) == "1k")
        #expect(SoundEdits.shortHz(16_000) == "16k")
        #expect(SoundEdits.readHz(1_200) == "1.2 kHz")
        #expect(SoundEdits.readBalance(0.004) == "Center")
        #expect(SoundEdits.readBalance(-0.3) == "30% left")
    }
}
