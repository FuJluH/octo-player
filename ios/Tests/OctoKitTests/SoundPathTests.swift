import Foundation
import Testing
@testable import OctoKit

// The audio path's tests from the other apps, on buffers of one channel each.

@Suite struct AudioOutputTests {
    func bt(_ name: String, _ address: String) -> OutputDevice { OutputDevice(kind: .bluetooth, name: name, address: address) }

    @Test func earbudsListedTwiceAreOneOutputInEitherOrder() {
        let left = bt("Enco X3", "AA:01")
        let right = bt("Enco X3", "AA:02")
        let speaker = OutputDevice(kind: .other, name: "Phone", address: "")
        let one = SoundOutputs.outputFor([speaker, left, right])
        let other = SoundOutputs.outputFor([right, speaker, left])
        #expect(one.key == "bluetooth:Enco X3")
        #expect(one == other)
        #expect(one.label == "Enco X3")
        #expect(one.formerKeys == ["bluetooth:AA:01", "bluetooth:AA:02"])
    }

    @Test func aNamelessDeviceIsKnownByItsAddress() {
        let out = SoundOutputs.outputFor([bt("", "BB:02"), bt("", "BB:01")])
        #expect(out.key == "bluetooth:BB:01")
        #expect(out.label == "Bluetooth")
        #expect(out.formerKeys == ["bluetooth:BB:02"])
    }

    @Test func bluetoothComesBeforeUsbAndACable() {
        let devices = [OutputDevice(kind: .wired, name: "", address: ""), OutputDevice(kind: .usb, name: "DAC", address: ""), bt("Car", "CC:01")]
        #expect(SoundOutputs.outputFor(devices).key == "bluetooth:Car")
        #expect(SoundOutputs.outputFor(Array(devices.dropLast())) == AudioOutput(key: "usb:DAC", label: "DAC"))
        #expect(SoundOutputs.outputFor(Array(devices.prefix(1))) == AudioOutput(key: "wired", label: "Headphones"))
    }

    @Test func withNothingConnectedItIsTheSpeaker() {
        #expect(SoundOutputs.outputFor([]) == .phoneSpeaker)
        #expect(SoundOutputs.outputFor([OutputDevice(kind: .other, name: "Earpiece", address: "")]) == .phoneSpeaker)
    }

    @Test func settingsSavedUnderAnOldAddressAreFound() {
        let out = SoundOutputs.outputFor([bt("Enco X3", "AA:01"), bt("Enco X3", "AA:02")])
        #expect(SoundOutputs.savedFor(["bluetooth:AA:02": 7], out) == 7)
        #expect(SoundOutputs.savedFor(["bluetooth:AA:02": 7, "bluetooth:Enco X3": 9], out) == 9)
        #expect(SoundOutputs.savedFor(["bluetooth:ZZ:99": 7], out) == nil)
    }

    @Test func eachOutputKeepsItsOwnOnlyWhenAsked() {
        let out = SoundOutputs.outputFor([bt("Enco X3", "AA:01")])
        var mine = SoundSettings()
        mine.mono = true
        var saved = SoundOutputs.saving({ $0 }, to: [:], perOutput: false, output: out)
        #expect(saved.keys.sorted() == ["all"])
        saved = SoundOutputs.saving({ var s = $0; s.mono = true; return s }, to: ["bluetooth:AA:01": SoundSettings()], perOutput: true, output: out)
        #expect(saved["bluetooth:Enco X3"] == mine)
        #expect(saved["bluetooth:AA:01"] == nil)
    }
}

@Suite struct SoundPathTests {
    let rate = 48_000.0

    func sine(_ frequency: Double, _ frames: Int, amplitude: Float = 0.25) -> [Float] {
        (0..<frames).map { amplitude * Float(sin(2 * Double.pi * frequency * Double($0) / rate)) }
    }

    func rms(_ samples: [Float], _ from: Int, _ to: Int) -> Double {
        sqrt(samples[from..<to].reduce(0) { $0 + Double($1) * Double($1) } / Double(to - from))
    }

    @Test func aPeakFilterGivesItsGainAtItsFrequency() {
        let bank = FilterBank(filters: [EqFilter(type: .peak, frequency: 1_000, gainDb: 6, q: 1.41)], sampleRate: rate, channels: 1)
        let input = sine(1_000, Int(rate))
        var output = input
        output.withUnsafeMutableBufferPointer { bank.process($0.baseAddress!, frames: Int(rate), channel: 0) }
        let gainDb = 20 * log10(rms(output, Int(rate) / 2, Int(rate)) / rms(input, Int(rate) / 2, Int(rate)))
        #expect(abs(gainDb - 6) < 0.05)
    }

    @Test func eachChannelIsFilteredOnItsOwn() {
        let bank = FilterBank(filters: [EqFilter(type: .peak, frequency: 1_000, gainDb: -12, q: 1.41)], sampleRate: rate, channels: 2)
        var left = sine(1_000, Int(rate), amplitude: 0.5)
        var right = [Float](repeating: 0, count: Int(rate))
        left.withUnsafeMutableBufferPointer { bank.process($0.baseAddress!, frames: Int(rate), channel: 0) }
        right.withUnsafeMutableBufferPointer { bank.process($0.baseAddress!, frames: Int(rate), channel: 1) }
        #expect(right.allSatisfy { $0 == 0 })
        let gainDb = 20 * log10(rms(left, Int(rate) / 2, Int(rate)) / (0.5 / sqrt(2.0)))
        #expect(abs(gainDb + 12) < 0.1)
    }

    @Test func bandsTooCloseToTheTopAreLeftOut() {
        let filters = [EqFilter(type: .peak, frequency: 1_000, gainDb: 3), EqFilter(type: .peak, frequency: 21_000, gainDb: 6)]
        #expect(FilterBank(filters: filters, sampleRate: 44_100, channels: 1).count == 1)
        #expect(FilterBank(filters: filters, sampleRate: 96_000, channels: 1).count == 2)
    }

    @Test func theLimiterNeverGoesOverItsCeiling() {
        let limiter = Limiter(channels: 2, sampleRate: rate)
        let frames = Int(rate) / 2
        func burst(_ frame: Int) -> Float {
            let level: Float = (10_000..<12_000).contains(frame) ? 4 : 0.3
            return level * Float(sin(2 * Double.pi * 440 * Double(frame) / rate))
        }
        var left = (0..<frames).map(burst)
        var right = left
        left.withUnsafeMutableBufferPointer { l in
            right.withUnsafeMutableBufferPointer { r in limiter.process([l.baseAddress!, r.baseAddress!], frames: frames) }
        }
        #expect((left + right).allSatisfy { abs($0) <= limiter.ceilingLevel })
        #expect((left + right).map(abs).max()! > limiter.ceilingLevel * 0.99)
    }

    @Test func theLimiterLosesNoFramesAndLeavesQuietSoundAlone() {
        let limiter = Limiter(channels: 1, sampleRate: rate)
        let input = sine(440, 4_800)
        var output = input + [Float](repeating: 0, count: limiter.latency)
        output.withUnsafeMutableBufferPointer { limiter.process([$0.baseAddress!], frames: $0.count) }
        #expect(output.prefix(limiter.latency).allSatisfy { $0 == 0 })
        for i in input.indices { #expect(output[i + limiter.latency] == input[i]) }
    }

    @Test func untouchedSoundPassesThroughExactly() {
        let shaper = SoundShaper(sampleRate: rate, channels: 2)
        shaper.apply(SoundSettings(), song: nil, instant: true)
        let input = sine(1_000, 2_000, amplitude: 0.99)
        var left = input + [Float](repeating: 0, count: shaper.latency)
        var right = left
        left.withUnsafeMutableBufferPointer { l in
            right.withUnsafeMutableBufferPointer { r in shaper.process([l.baseAddress!, r.baseAddress!], frames: l.count) }
        }
        for i in input.indices {
            #expect(left[i + shaper.latency] == input[i])
            #expect(right[i + shaper.latency] == input[i])
        }
    }

    @Test func monoAndBalanceMixTheChannels() {
        let shaper = SoundShaper(sampleRate: rate, channels: 2)
        var settings = SoundSettings()
        settings.mono = true
        settings.balance = 0.5
        settings.limiter = false
        shaper.apply(settings, song: nil, instant: true)
        let frames = 1_000
        var left = [Float](repeating: 0.4, count: frames)
        var right = [Float](repeating: 0, count: frames)
        left.withUnsafeMutableBufferPointer { l in
            right.withUnsafeMutableBufferPointer { r in shaper.process([l.baseAddress!, r.baseAddress!], frames: frames) }
        }
        #expect(abs(left[frames - 1] - 0.1) < 1e-6)
        #expect(abs(right[frames - 1] - 0.2) < 1e-6)
    }

    @Test func aSongsGainStartsAtItsFirstSample() {
        let shaper = SoundShaper(sampleRate: rate, channels: 1)
        var settings = SoundSettings()
        settings.replayGain = .track
        settings.limiter = false
        shaper.apply(settings, song: SongLoudness(ReplayGainInfo(trackGain: -6.0206), followsSameAlbum: false), instant: true)
        var samples = [Float](repeating: 0.5, count: 100 + shaper.latency)
        samples.withUnsafeMutableBufferPointer { shaper.process([$0.baseAddress!], frames: $0.count) }
        // The sound always runs the limiter's latency late, limiting or not.
        #expect(samples.prefix(shaper.latency).allSatisfy { $0 == 0 })
        #expect(samples.dropFirst(shaper.latency).allSatisfy { abs($0 - 0.25) < 1e-4 })
    }

    @Test func aChangeGlidesInOverThirtyMilliseconds() {
        let shaper = SoundShaper(sampleRate: rate, channels: 1)
        var settings = SoundSettings()
        settings.limiter = false
        shaper.apply(settings, song: nil, instant: true)
        settings.eqEnabled = true
        settings.autoPreamp = false
        settings.preampDb = -6.0206
        shaper.apply(settings, song: nil, instant: false)
        let frames = 1_440
        let late = shaper.latency
        var samples = [Float](repeating: 1, count: frames + late + 10)
        samples.withUnsafeMutableBufferPointer { shaper.process([$0.baseAddress!], frames: $0.count) }
        #expect(samples[late] < 1 && samples[late] > 0.99)
        #expect(abs(samples[late + frames / 2] - 0.75) < 0.01)
        #expect(abs(samples[late + frames + 5] - 0.5) < 1e-4)
    }
}
