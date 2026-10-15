import Foundation
import Testing
@testable import OctoKit

private func db(_ x: Double) -> Double { 20 * log10(x) }

/// The shared crossfeed vectors, as the file has them.
private struct CrossfeedVectors: Decodable {
    struct Tolerances: Decodable {
        let coefficient: Double
        let db: Double
        let floatSample: Double
    }

    struct Impulse: Decodable {
        let own: [Double]
        let other: [Double]
    }

    struct Point: Decodable {
        let hz: Double
        let ownDb: Double
        let otherDb: Double
    }

    struct Case: Decodable {
        let preset: CrossfeedPreset
        let cutHz: Int
        let feedDb: Double
        let rate: Double
        let gain: Double
        let pole: Double
        let impulse: Impulse
        let response: [Point]
    }

    let tolerances: Tolerances
    let cases: [Case]

    var coefficient: Double { tolerances.coefficient }
    var dbTolerance: Double { tolerances.db }
    var floatSample: Double { tolerances.floatSample }

    static let shared = try! JSONDecoder().decode(CrossfeedVectors.self, from: Data(crossfeedVectorsJSON.utf8))
}

@Suite struct CrossfeedFilterTests {
    private let vectors = CrossfeedVectors.shared

    @Test func theSharedVectorsCoverEveryPresetAtBothRates() {
        #expect(Set(vectors.cases.map(\.preset)) == Set(CrossfeedPreset.allCases))
        #expect(Set(vectors.cases.map(\.rate)) == [44_100, 48_000])
    }

    @Test func presetsCarryTheirValues() {
        for c in vectors.cases where c.preset != .custom {
            #expect(c.preset.values?.cutHz == c.cutHz)
            #expect(c.preset.values?.feedDb == c.feedDb)
        }
        #expect(CrossfeedPreset.custom.values == nil)
        var custom = Crossfeed(on: true, preset: .custom, cutHz: 5_000, feedDb: 40)
        #expect(custom.effectiveCutHz == 2_000)
        #expect(custom.effectiveFeedDb == 15)
        custom.preset = .janMeier
        #expect(custom.effectiveCutHz == 650)
        #expect(custom.effectiveFeedDb == 9.5)
    }

    @Test func coefficientsMatchTheSharedVectors() {
        for c in vectors.cases {
            let k = CrossfeedCoefficients(Crossfeed(on: true, preset: c.preset, cutHz: c.cutHz, feedDb: c.feedDb), sampleRate: c.rate)
            #expect(abs(k.gain - c.gain) <= vectors.coefficient, "\(c.preset) gain at \(c.rate)")
            #expect(abs(k.pole - c.pole) <= vectors.coefficient, "\(c.preset) pole at \(c.rate)")
        }
    }

    /// One frame of sound on the left only, as 32-bit samples through the buffer path.
    @Test func anImpulseMatchesTheSharedVectors() {
        for c in vectors.cases {
            let k = CrossfeedCoefficients(cutHz: Double(c.cutHz), feedDb: c.feedDb, sampleRate: c.rate)
            var left = [Float](repeating: 0, count: c.impulse.own.count)
            var right = [Float](repeating: 0, count: c.impulse.own.count)
            left[0] = 1
            var filter = CrossfeedFilter()
            left.withUnsafeMutableBufferPointer { l in
                right.withUnsafeMutableBufferPointer { r in filter.process(l.baseAddress!, r.baseAddress!, frames: l.count, k) }
            }
            for n in c.impulse.own.indices {
                #expect(abs(Double(left[n]) - c.impulse.own[n]) <= vectors.floatSample, "\(c.preset) own[\(n)]")
                #expect(abs(Double(right[n]) - c.impulse.other[n]) <= vectors.floatSample, "\(c.preset) other[\(n)]")
            }
        }
    }

    @Test func theResponseMatchesTheSharedVectors() {
        for c in vectors.cases {
            let k = CrossfeedCoefficients(cutHz: Double(c.cutHz), feedDb: c.feedDb, sampleRate: c.rate)
            for point in c.response {
                let r = k.response(at: point.hz, sampleRate: c.rate)
                #expect(abs(db(r.direct) - point.ownDb) <= vectors.dbTolerance, "\(c.preset) own at \(point.hz) Hz")
                #expect(abs(db(r.cross) - point.otherDb) <= vectors.dbTolerance, "\(c.preset) other at \(point.hz) Hz")
            }
        }
    }

    @Test func atLowFrequenciesTheOtherSideIsTheFeedLevelBelow() {
        for c in vectors.cases {
            let k = CrossfeedCoefficients(cutHz: Double(c.cutHz), feedDb: c.feedDb, sampleRate: c.rate)
            let low = k.response(at: 0.001, sampleRate: c.rate)
            #expect(abs(db(low.cross / low.direct) + c.feedDb) < 1e-6)
            // The feed is 3 dB down from there at the cut, give or take the one-pole's bend.
            let drop = db(k.response(at: Double(c.cutHz), sampleRate: c.rate).cross / low.cross)
            #expect(abs(drop + 3) < 0.05, "\(drop) dB at \(c.cutHz) Hz")
        }
    }

    @Test func soundTheSameOnBothSidesPassesThroughExactly() {
        let k = CrossfeedCoefficients(Crossfeed(on: true, preset: .natural), sampleRate: 48_000)
        var left: [Float] = (0..<4_096).map { Float(sin(Double($0) * 0.037)) * 0.9 }
        var right = left
        let before = left
        var filter = CrossfeedFilter()
        left.withUnsafeMutableBufferPointer { l in
            right.withUnsafeMutableBufferPointer { r in filter.process(l.baseAddress!, r.baseAddress!, frames: l.count, k) }
        }
        #expect(left == before)
        #expect(right == before)
    }

    @Test func offPassesBothChannelsThroughUnchanged() {
        var filter = CrossfeedFilter()
        for (l, r) in [(0.5, -0.25), (1.0, 0.0), (-0.75, 0.125)] {
            let out = filter.process(l, r, .none)
            #expect(out.left == l && out.right == r)
        }
    }

    /// A full-scale sine on one side, or opposite on the two sides, never comes out over full scale
    /// once it is under way. Its first cycles can overshoot by under 1 %, which the limiter catches.
    @Test func fullScaleMakesNoOvers() {
        for c in vectors.cases {
            let k = CrossfeedCoefficients(cutHz: Double(c.cutHz), feedDb: c.feedDb, sampleRate: c.rate)
            for hz in [20.0, 200, 650, 700, 1_500, 5_000, 15_000] {
                var oneSide = CrossfeedFilter()
                var opposite = CrossfeedFilter()
                var peak = 0.0
                for i in 0..<Int(c.rate / 4) {
                    let x = sin(2 * Double.pi * hz * Double(i) / c.rate)
                    let a = oneSide.process(x, 0, k)
                    let b = opposite.process(x, -x, k)
                    if i >= Int(c.rate / 20) { peak = max(peak, abs(a.left), abs(a.right), abs(b.left), abs(b.right)) }
                }
                #expect(peak <= 1 + 1e-9, "\(peak) at \(hz) Hz")
            }
        }
    }
}

@Suite struct CrossfeedSettingsTests {
    func json(_ settings: SoundSettings) -> String {
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.sortedKeys]
        return String(decoding: try! encoder.encode(settings), as: UTF8.self)
    }

    func read(_ text: String) throws -> SoundSettings {
        try JSONDecoder().decode(SoundSettings.self, from: Data(text.utf8))
    }

    @Test func offByDefaultAndLeftOutOfTheStoredSettings() throws {
        #expect(SoundSettings().crossfeed == Crossfeed())
        #expect(!SoundSettings().crossfeed.on)
        #expect(json(SoundSettings()) == "{}")
        var s = SoundSettings()
        s.crossfeed = Crossfeed(on: true, preset: .chuMoy)
        #expect(json(s) == #"{"crossfeed":{"on":true,"preset":"ChuMoy"}}"#)
        #expect(try read(json(s)) == s)
        s.crossfeed = Crossfeed(on: true, preset: .custom, cutHz: 900, feedDb: 7.5)
        #expect(json(s) == #"{"crossfeed":{"cutHz":900,"feedDb":7.5,"on":true,"preset":"Custom"}}"#)
        #expect(try read(json(s)) == s)
    }

    @Test func onTheSpeakerACarOrAirPlayItStaysOff() {
        var s = SoundSettings()
        s.crossfeed.on = true
        for output in [AudioOutput.phoneSpeaker, AudioOutput(key: "car:CarPlay", label: "CarPlay"),
                       AudioOutput(key: "airplay:Kitchen", label: "Kitchen")] {
            #expect(!output.takesCrossfeed)
            #expect(!SoundOutputs.playing(s, on: output).crossfeed.on)
        }
        for output in [AudioOutput(key: "wired", label: "Headphones"), AudioOutput(key: "usb:DAC", label: "DAC"),
                       AudioOutput(key: "bluetooth:Enco X3", label: "Enco X3")] {
            #expect(output.takesCrossfeed)
            #expect(SoundOutputs.playing(s, on: output) == s)
        }
    }

    @Test func crossfeedAloneShapesTheSound() {
        var s = SoundSettings()
        s.limiter = false
        #expect(!s.shapesSound)
        s.crossfeed.on = true
        #expect(s.shapesSound)
    }

    @Test func goesThroughABackupAndBack() {
        var settings = SoundSettings()
        settings.crossfeed = Crossfeed(on: true, preset: .custom, cutHz: 1_200, feedDb: 8)
        var backup = Backup()
        backup.sound = SoundBackup(perOutput: true, profiles: ["wired": settings])
        let text = BackupFile.encode(backup)
        #expect(text.contains("\"crossfeed\""))
        #expect(text.contains("\"preset\": \"Custom\""))
        guard case .read(let read) = BackupFile.decode(text) else { Issue.record("not read"); return }
        #expect(read.sound?.profiles["wired"]?.crossfeed == settings.crossfeed)
    }

    @Test func anUnknownPresetInABackupIsNatural() {
        let text = #"{"sound": {"perOutput": true, "profiles": {"wired": {"crossfeed": {"on": true, "preset": "Wide", "cutHz": 800}}}}}"#
        guard case .read(let backup) = BackupFile.decode(text), let crossfeed = backup.sound?.profiles["wired"]?.crossfeed
        else { Issue.record("not read"); return }
        #expect(crossfeed.on)
        #expect(crossfeed.preset == .natural)
        #expect(crossfeed.cutHz == 800)
    }

    @Test func readingsOnThePage() {
        #expect(CrossfeedWords.readFeed(4.5) == "4.5 dB")
        #expect(CrossfeedWords.readFeed(6) == "6 dB")
        #expect(CrossfeedWords.values(Crossfeed(preset: .janMeier)) == "650 Hz, 9.5 dB")
        #expect(abs(CrossfeedWords.cutValue(CrossfeedWords.cutFraction(700)) - 700) < 1e-9)
        #expect(CrossfeedWords.cutFraction(300) == 0)
        #expect(abs(CrossfeedWords.cutFraction(2_000) - 1) < 1e-12)
    }
}

@Suite struct CrossfeedShapingTests {
    func shaped(_ settings: SoundSettings, left: [Float], right: [Float]) -> ([Float], [Float]) {
        let shaper = SoundShaper(sampleRate: 48_000, channels: 2)
        shaper.apply(settings, song: nil, instant: true)
        var l = left, r = right
        l.withUnsafeMutableBufferPointer { lb in
            r.withUnsafeMutableBufferPointer { rb in shaper.process([lb.baseAddress!, rb.baseAddress!], frames: lb.count) }
        }
        let late = shaper.latency
        return (Array(l.dropFirst(late)), Array(r.dropFirst(late)))
    }

    @Test func aSoundOnTheLeftReachesTheRightEar() {
        var s = SoundSettings()
        s.limiter = false
        s.crossfeed.on = true
        let (l, r) = shaped(s, left: Array(repeating: 0.5, count: 4_800), right: Array(repeating: 0, count: 4_800))
        let k = CrossfeedCoefficients(s.crossfeed, sampleRate: 48_000)
        let low = k.response(at: 0.001, sampleRate: 48_000)
        #expect(abs(Double(r.last!) - 0.5 * low.cross) < 1e-4)
        #expect(abs(Double(l.last!) - 0.5 * low.direct) < 1e-4)
    }

    @Test func withMonoOnThereIsNothingToBlend() {
        var s = SoundSettings()
        s.limiter = false
        s.mono = true
        let left: [Float] = (0..<2_000).map { Float(sin(Double($0) * 0.07)) * 0.5 }
        let right: [Float] = (0..<2_000).map { Float(sin(Double($0) * 0.31)) * 0.25 }
        let plain = shaped(s, left: left, right: right)
        s.crossfeed.on = true
        let fed = shaped(s, left: left, right: right)
        #expect(plain.0 == fed.0)
        #expect(plain.1 == fed.1)
    }

    /// Turning crossfeed on, changing its preset and turning it off while a sine plays never
    /// jumps the waveform: no step is bigger than the sine's own steepest step, with a margin.
    @Test func changesGlideInWithoutAClick() {
        let rate = 48_000.0
        let shaper = SoundShaper(sampleRate: rate, channels: 2)
        var s = SoundSettings()
        s.limiter = false
        shaper.apply(s, song: nil, instant: true)
        let hz = 200.0
        let steepest = Float(2 * Double.pi * hz / rate) * 0.8
        var phase = 0
        var last: (Float, Float)?
        var biggest: Float = 0
        func run(_ frames: Int) {
            var l: [Float] = (0..<frames).map { Float(sin(2 * Double.pi * hz * Double(phase + $0) / rate)) * 0.8 }
            var r: [Float] = Array(repeating: 0, count: frames)
            phase += frames
            l.withUnsafeMutableBufferPointer { lb in
                r.withUnsafeMutableBufferPointer { rb in shaper.process([lb.baseAddress!, rb.baseAddress!], frames: frames) }
            }
            for (x, y) in zip(l, r) {
                if let last { biggest = max(biggest, abs(x - last.0), abs(y - last.1)) }
                last = (x, y)
            }
        }
        run(4_800)
        s.crossfeed.on = true
        shaper.apply(s, song: nil, instant: false)
        run(4_800)
        s.crossfeed.preset = .janMeier
        shaper.apply(s, song: nil, instant: false)
        run(4_800)
        s.crossfeed.preset = .custom
        s.crossfeed.cutHz = 2_000
        s.crossfeed.feedDb = 1
        shaper.apply(s, song: nil, instant: false)
        run(4_800)
        s.crossfeed.on = false
        shaper.apply(s, song: nil, instant: false)
        run(4_800)
        #expect(biggest < steepest * 1.05, "\(biggest) against \(steepest)")
    }
}
