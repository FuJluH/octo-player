import Foundation
import Testing
@testable import OctoKit

// Ported from the Android app's shared tests (shared/core/src/commonTest/.../sound/).

@Suite struct SoundModelTests {
    @Test func aPeakFilterBoostsItsFrequencyByItsGain() {
        let bump = [EqFilter(type: .peak, frequency: 1_000, gainDb: 6, q: 1.41)]
        #expect(abs(ResponseCurve.gainDb(bump, at: 1_000) - 6) < 0.05)
        #expect(abs(ResponseCurve.gainDb(bump, at: 20)) < 0.1)
        #expect(abs(ResponseCurve.gainDb(bump, at: 18_000)) < 0.2)
    }

    @Test func shelvesLiftEverythingPastTheirCorner() {
        let low = [EqFilter(type: .lowShelf, frequency: 200, gainDb: 6, q: 0.707)]
        #expect(abs(ResponseCurve.gainDb(low, at: 20) - 6) < 0.2)
        #expect(abs(ResponseCurve.gainDb(low, at: 10_000)) < 0.1)
        let high = [EqFilter(type: .highShelf, frequency: 4_000, gainDb: -6, q: 0.707)]
        #expect(abs(ResponseCurve.gainDb(high, at: 18_000) + 6) < 0.3)
        #expect(abs(ResponseCurve.gainDb(high, at: 100)) < 0.1)
    }

    @Test func theAutomaticPreampTakesBackTheHighestBoost() {
        var settings = SoundSettings()
        settings.eqEnabled = true
        settings.graphicGains = eqPresets.first { $0.name == "Bass Boost" }!.gains
        let preamp = settings.effectivePreampDb()
        #expect(preamp < -5)
        #expect(abs(-ResponseCurve.peakDb(settings.activeFilters()) - preamp) < 0.001)
    }

    @Test func anEqualizerThatIsOffChangesNothing() {
        var settings = SoundSettings()
        settings.graphicGains = Array(repeating: 6, count: 10)
        #expect(settings.activeFilters().isEmpty)
        #expect(settings.effectivePreampDb() == 0)
    }

    @Test func aCorrectionRunsBeforeTheOwnCurve() {
        var settings = SoundSettings()
        settings.eqEnabled = true
        settings.correction = HeadphoneCorrection(name: "HD 650", source: "oratory1990", preampDb: -6,
                                                  filters: [EqFilter(type: .lowShelf, frequency: 105, gainDb: 6.4, q: 0.7)])
        settings.graphicGains = (0..<10).map { $0 == 5 ? 3 : 0 }
        let filters = settings.activeFilters()
        #expect(filters.first?.type == .lowShelf)
        #expect(filters.count == 2)
    }

    @Test func everyPresetHasTenBands() {
        for preset in eqPresets { #expect(preset.gains.count == graphicBands.count, "\(preset.name)") }
    }
}

@Suite struct ReplayGainTests {
    func db(_ factor: Double) -> Double { 20 * log10(factor) }

    @Test func standardTagsWinOverR128() {
        let info = ReplayGainTags.fromTags([("R128_TRACK_GAIN", "0"), ("REPLAYGAIN_TRACK_GAIN", "-3 dB")])!
        #expect(abs(info.trackGain! + 3) < 1e-4)
    }

    @Test func readsTheShapesGainsComeIn() {
        #expect(abs(ReplayGainTags.parseGain("-6.54 dB")! + 6.54) < 1e-4)
        #expect(abs(ReplayGainTags.parseGain("-6,54 dB")! + 6.54) < 1e-4)
        #expect(abs(ReplayGainTags.parseGain("+2.1dB")! - 2.1) < 1e-4)
        #expect(abs(ReplayGainTags.parseGain("  0.5 DB ")! - 0.5) < 1e-4)
        #expect(abs(ReplayGainTags.parseGain("-4")! + 4) < 1e-4)
        #expect(ReplayGainTags.parseGain("loud") == nil)
        #expect(ReplayGainTags.parseGain("-300 dB") == nil)
        #expect(ReplayGainTags.parsePeak("0") == nil)
    }

    let tagged = ReplayGainInfo(trackGain: -6, trackPeak: 0.9, albumGain: -8, albumPeak: 0.95)

    func settings(_ mode: ReplayGainMode, preamp: Double = 0, fallback: Double = 0, clipping: Bool = true) -> SoundSettings {
        var s = SoundSettings()
        s.replayGain = mode
        s.replayGainPreampDb = preamp
        s.replayGainFallbackDb = fallback
        s.preventClipping = clipping
        return s
    }

    @Test func theModeChoosesTrackOrAlbum() {
        let song = SongLoudness(tagged, followsSameAlbum: false)
        #expect(replayGainFactor(settings(.off), song) == 1)
        #expect(abs(db(replayGainFactor(settings(.track), song)) + 6) < 1e-4)
        #expect(abs(db(replayGainFactor(settings(.album), song)) + 8) < 1e-4)
    }

    @Test func eachFallsBackToTheOther() {
        let trackOnly = SongLoudness(ReplayGainInfo(trackGain: -4), followsSameAlbum: false)
        let albumOnly = SongLoudness(ReplayGainInfo(albumGain: -5), followsSameAlbum: false)
        #expect(abs(db(replayGainFactor(settings(.album), trackOnly)) + 4) < 1e-4)
        #expect(abs(db(replayGainFactor(settings(.track), albumOnly)) + 5) < 1e-4)
    }

    @Test func thePreampAddsAndTheFallbackCoversUntaggedSongs() {
        let s = settings(.track, preamp: 2, fallback: -7, clipping: false)
        #expect(abs(db(replayGainFactor(s, SongLoudness(tagged, followsSameAlbum: false))) + 4) < 1e-4)
        #expect(abs(db(replayGainFactor(s, SongLoudness(nil, followsSameAlbum: false))) + 7) < 1e-4)
        #expect(abs(db(replayGainFactor(s, nil)) + 7) < 1e-4)
    }

    @Test func preventingClippingStopsAtThePeak() {
        let loud = SongLoudness(ReplayGainInfo(trackGain: 6, trackPeak: 0.8), followsSameAlbum: false)
        #expect(abs(replayGainFactor(settings(.track), loud) - 1 / 0.8) < 1e-5)
        #expect(abs(replayGainFactor(settings(.track, clipping: false), loud) - pow(10, 6.0 / 20)) < 1e-5)
        let quiet = SongLoudness(ReplayGainInfo(trackGain: -6, trackPeak: 0.8), followsSameAlbum: false)
        #expect(abs(db(replayGainFactor(settings(.track), quiet)) + 6) < 1e-4)
    }

    @Test func smartUsesTheAlbumOnlyWhileAnAlbumPlays() {
        #expect(abs(db(replayGainFactor(settings(.smart), SongLoudness(tagged, followsSameAlbum: false))) + 6) < 1e-4)
        #expect(abs(db(replayGainFactor(settings(.smart), SongLoudness(tagged, followsSameAlbum: true))) + 8) < 1e-4)
    }

    @Test func theAlbumRunFollowsConsecutiveSongs() {
        let run = AlbumRun()
        #expect(!run.follows("a1", "A"))
        #expect(run.follows("a2", "A"))
        #expect(run.follows("a3", "A"))
        #expect(run.follows("a3", "A"))
        #expect(!run.follows("b1", "B"))
        #expect(!run.follows("x", nil))
        #expect(!run.follows("y", nil))
    }
}

@Suite struct ParametricEqFileTests {
    let sample = """
    Preamp: -6.1 dB
    Filter 1: ON LSC Fc 105 Hz Gain 6.4 dB Q 0.70
    Filter 2: ON PK Fc 180 Hz Gain -3.2 dB Q 0.55
    Filter 3: ON PK Fc 1450.5 Hz Gain 2.0 dB Q 1.93
    Filter 4: OFF PK Fc 3000 Hz Gain 4.0 dB Q 2.00
    Filter 5: ON HSC Fc 10000 Hz Gain -2.5 dB Q 0.70
    """

    @Test func readsThePreampAndEveryFilterThatIsOn() {
        let read = ParametricEqFile.parse(sample)
        #expect(abs(read.preampDb + 6.1) < 0.0001)
        #expect(read.filters.count == 4)
        #expect(read.filters[0] == EqFilter(type: .lowShelf, frequency: 105, gainDb: 6.4, q: 0.7))
        #expect(read.filters[1] == EqFilter(type: .peak, frequency: 180, gainDb: -3.2, q: 0.55))
        #expect(abs(read.filters[2].frequency - 1450.5) < 0.0001)
        #expect(read.filters[3].type == .highShelf)
    }

    @Test func skipsLinesItDoesNotUnderstand() {
        let read = ParametricEqFile.parse("# a comment\nFilter 1: ON LP Fc 20000 Hz\nFilter 2: ON PK Fc 60 Hz Gain 1.5 dB Q 1.00\n")
        #expect(read.preampDb == 0)
        #expect(read.filters == [EqFilter(type: .peak, frequency: 60, gainDb: 1.5, q: 1)])
    }

    @Test func aCorrectionIsNamedAfterItsFile() {
        let fix = ParametricEqFile.correction(fileName: "Sennheiser HD 650 ParametricEQ.txt", text: sample)!
        #expect(fix.name == "Sennheiser HD 650")
        #expect(fix.source == ParametricEqFile.imported)
        #expect(abs(fix.preampDb + 6.1) < 0.0001)
        #expect(fix.filters.count == 4)
        #expect(ParametricEqFile.name(from: "My curve.txt") == "My curve")
        #expect(ParametricEqFile.name(from: "ParametricEQ.txt") == "ParametricEQ")
    }

    @Test func aFileWithNoFiltersIsNoCorrection() {
        #expect(ParametricEqFile.correction(fileName: "empty.txt", text: "Preamp: -3 dB\n") == nil)
    }

    @Test func whatIsWrittenReadsBackTheSame() {
        let filters = [
            EqFilter(type: .lowShelf, frequency: 105, gainDb: 6.4, q: 0.7),
            EqFilter(type: .peak, frequency: 1_000, gainDb: -3.5, q: 1.41),
            EqFilter(type: .peak, frequency: 62.5, gainDb: 2, q: 0.9),
            EqFilter(type: .highShelf, frequency: 12_000, gainDb: -1, q: 0.71),
        ]
        let text = ParametricEqFile.write(preampDb: -4.25, filters: filters)
        #expect(text.hasPrefix("Preamp: -4.3 dB\n"))
        #expect(text.contains("Filter 2: ON PK Fc 1000 Hz Gain -3.5 dB Q 1.41"))
        let read = ParametricEqFile.parse(text)
        #expect(abs(read.preampDb + 4.3) < 0.0001)
        #expect(read.filters.count == filters.count)
        for (wrote, back) in zip(filters, read.filters) {
            #expect(wrote.type == back.type)
            #expect(abs(wrote.frequency - back.frequency) < 0.05)
            #expect(abs(wrote.gainDb - back.gainDb) < 0.05)
            #expect(abs(wrote.q - back.q) < 0.005)
        }
    }

    @Test func zeroIsWrittenWithoutASign() {
        #expect(ParametricEqFile.write(preampDb: -0.01, filters: []).hasPrefix("Preamp: 0.0 dB"))
    }
}

@Suite struct FilterBankTests {
    @Test func aFlatBankLeavesTheSoundAlone() {
        let bank = FilterBank(filters: [], sampleRate: 48_000, channels: 1)
        var samples: [Float] = [0.1, -0.2, 0.3]
        samples.withUnsafeMutableBufferPointer { bank.process($0.baseAddress!, frames: 3, channel: 0) }
        #expect(samples == [0.1, -0.2, 0.3])
    }

    @Test func aBoostRaisesAToneAtItsFrequency() {
        let bank = FilterBank(filters: [EqFilter(type: .peak, frequency: 1_000, gainDb: 6, q: 1.41)], sampleRate: 48_000, channels: 1)
        let count = 48_000
        var samples = (0..<count).map { Float(sin(2 * Double.pi * 1_000 * Double($0) / 48_000)) * 0.25 }
        samples.withUnsafeMutableBufferPointer { bank.process($0.baseAddress!, frames: count, channel: 0) }
        let tail = samples.suffix(4_800).map { abs($0) }.max()!
        #expect(abs(20 * log10(Double(tail) / 0.25) - 6) < 0.2)
    }
}
