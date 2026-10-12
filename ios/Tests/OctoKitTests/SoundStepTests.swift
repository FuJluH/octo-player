import Foundation
import Testing
@testable import OctoKit

/// Runs buffers of one channel through a step, the way a player hands them over.
private struct Mono {
    let step: ShapingStep

    func run(_ input: [Float]) -> [Float] {
        var samples = input
        var output = [Float](repeating: 0, count: input.count)
        let written = samples.withUnsafeMutableBufferPointer { inBuffer in
            output.withUnsafeMutableBufferPointer { outBuffer in
                step.process([inBuffer.baseAddress!], frames: input.count, output: [outBuffer.baseAddress!])
            }
        }
        return Array(output.prefix(written))
    }

    func drain() -> [Float] {
        var tail = [Float](repeating: 0, count: 1_024)
        let count = tail.withUnsafeMutableBufferPointer { step.endOfStream(into: [$0.baseAddress!]) }
        return Array(tail.prefix(count))
    }
}

@Suite struct ShapingStepTests {
    func gain(_ db: Double) -> SongLoudness { SongLoudness(ReplayGainInfo(trackGain: db), followsSameAlbum: false) }

    func half(_ frames: Int) -> [Float] { [Float](repeating: Float(16_384) / 32_768, count: frames) }

    @Test func aSongsGainStartsAtItsFirstSample() {
        var settings = SoundSettings()
        settings.replayGain = .track
        settings.limiter = false
        settings.preventClipping = false
        let step = ShapingStep(settings: SoundSettingsBox(settings))
        let mono = Mono(step: step)
        step.setNextSong(gain(-6.0206))
        #expect(step.configure(sampleRate: 48_000, channels: 1))
        step.flush()

        var first = mono.run(half(1_000))
        // The next song is set up while this one still plays...
        step.setNextSong(gain(0))
        step.configure(sampleRate: 48_000, channels: 1)
        first += mono.run(half(1_000))
        // ...and this one plays out at its own level.
        first += mono.drain()
        #expect(first.count == 2_000)
        #expect(first.allSatisfy { abs($0 - 0.25) < 1e-4 })

        // After the hand-over the new level holds from the very first sample.
        step.flush()
        let second = mono.run(half(1_000)) + mono.drain()
        #expect(second.count == 1_000)
        #expect(second.allSatisfy { $0 == 0.5 })
    }

    @Test func turningEverythingOffLeavesTheSoundAlone() {
        var off = SoundSettings()
        off.limiter = false
        let step = ShapingStep(settings: SoundSettingsBox(off))
        #expect(!step.configure(sampleRate: 48_000, channels: 1))
        var samples: [Float] = [0.1, -0.2, 0.3]
        samples.withUnsafeMutableBufferPointer { step.process([$0.baseAddress!], frames: 3) }
        #expect(samples == [0.1, -0.2, 0.3])
    }

    @Test func keptActiveItRunsWithNothingToShape() {
        var off = SoundSettings()
        off.limiter = false
        let step = ShapingStep(settings: SoundSettingsBox(off), keepActive: { true })
        #expect(step.configure(sampleRate: 48_000, channels: 1))
        step.flush()
        let input = (0..<2_000).map { Float(sin(Double($0) / 7)) * 0.9 }
        let mono = Mono(step: step)
        let out = mono.run(input) + mono.drain()
        #expect(out == input)
    }

    @Test func settingsChangedMidStreamGlideIn() {
        var settings = SoundSettings()
        settings.limiter = false
        let box = SoundSettingsBox(settings)
        let step = ShapingStep(settings: box, keepActive: { true })
        step.configure(sampleRate: 48_000, channels: 1)
        step.flush()
        let mono = Mono(step: step)
        _ = mono.run([Float](repeating: 1, count: 4_800))
        settings.eqEnabled = true
        settings.autoPreamp = false
        settings.preampDb = -6.0206
        box.set(settings)
        let out = mono.run([Float](repeating: 1, count: 4_800))
        // The delay still holds the last 72 frames at the old level, then the glide runs.
        let late = 72
        #expect(out[late - 1] == 1)
        #expect(out[late] < 1 && out[late] > 0.99)
        #expect(abs(out[late + 720] - 0.75) < 0.01)
        #expect(abs(out[late + 1_440 + 10] - 0.5) < 1e-4)
    }

    @Test func aSeekForgetsTheHeldSoundAndKeepsTheLevel() {
        var settings = SoundSettings()
        settings.replayGain = .track
        settings.preventClipping = false
        let step = ShapingStep(settings: SoundSettingsBox(settings))
        step.setNextSong(gain(-6.0206))
        step.configure(sampleRate: 48_000, channels: 1)
        step.flush()
        let mono = Mono(step: step)
        _ = mono.run(half(500))
        step.flush()
        let after = mono.run(half(500)) + mono.drain()
        #expect(after.count == 500)
        #expect(after.allSatisfy { abs($0 - 0.25) < 1e-4 })
    }

    @Test func inPlaceTheEndOfTheSongBeforePlaysWhileTheDelayFills() {
        let box = SoundSettingsBox(SoundSettings())
        let handOff = SoundHandOff()
        let before = ShapingStep(settings: box)
        before.configure(sampleRate: 48_000, channels: 1)
        before.flush()
        var song = (0..<1_000).map { Float($0) / 1_000 }
        song.withUnsafeMutableBufferPointer { before.process([$0.baseAddress!], frames: 1_000) }
        var tail = [Float](repeating: 0, count: 256)
        let count = tail.withUnsafeMutableBufferPointer { buffer -> Int in
            let n = before.endOfStream(into: [buffer.baseAddress!])
            handOff.put([buffer.baseAddress!], count: n, sampleRate: 48_000, now: 10)
            return n
        }
        #expect(count == 72)
        #expect(Array(tail.prefix(count)) == (928..<1_000).map { Float($0) / 1_000 })

        let next = ShapingStep(settings: box)
        next.configure(sampleRate: 48_000, channels: 1)
        next.flush(lead: handOff.take(sampleRate: 48_000, channels: 1, now: 10.02))
        // A first buffer shorter than the delay, then the rest.
        var a = [Float](repeating: 0.5, count: 40)
        var b = [Float](repeating: 0.5, count: 200)
        a.withUnsafeMutableBufferPointer { next.process([$0.baseAddress!], frames: 40) }
        b.withUnsafeMutableBufferPointer { next.process([$0.baseAddress!], frames: 200) }
        let heard = a + b
        #expect(Array(heard.prefix(72)) == (928..<1_000).map { Float($0) / 1_000 })
        #expect(heard.dropFirst(72).allSatisfy { $0 == 0.5 })
    }

    @Test func aHandOffWaitsOnlyALittleAndOnlyForItsFormat() {
        let handOff = SoundHandOff(window: 0.5)
        var tail: [Float] = [0.1, 0.2]
        tail.withUnsafeMutableBufferPointer { handOff.put([$0.baseAddress!], count: 2, sampleRate: 44_100, now: 1) }
        #expect(handOff.take(sampleRate: 48_000, channels: 1, now: 1.1) == nil)
        tail.withUnsafeMutableBufferPointer { handOff.put([$0.baseAddress!], count: 2, sampleRate: 44_100, now: 1) }
        #expect(handOff.take(sampleRate: 44_100, channels: 1, now: 2) == nil)
        tail.withUnsafeMutableBufferPointer { handOff.put([$0.baseAddress!], count: 2, sampleRate: 44_100, now: 1) }
        #expect(handOff.take(sampleRate: 44_100, channels: 1, now: 1.2) == [[0.1, 0.2]])
        #expect(handOff.take(sampleRate: 44_100, channels: 1, now: 1.2) == nil)
    }
}

@Suite struct LimiterDrainTests {
    let rate = 48_000.0

    func sine(_ frequency: Double, _ frames: Int, amplitude: Float = 0.25) -> [Float] {
        (0..<frames).map { amplitude * Float(sin(2 * Double.pi * frequency * Double($0) / rate)) }
    }

    @Test func theLimiterNeverGoesOverItsCeilingAndLosesNoFrames() {
        let limiter = Limiter(channels: 2, sampleRate: rate)
        let frames = Int(rate) / 2
        func burst(_ frame: Int) -> Float {
            let level: Float = (10_000..<12_000).contains(frame) ? 4 : 0.3
            return level * Float(sin(2 * Double.pi * 440 * Double(frame) / rate))
        }
        var left = (0..<frames).map(burst)
        var right = left
        var outLeft = [Float](repeating: 0, count: frames)
        var outRight = [Float](repeating: 0, count: frames)
        let written = withPointers(&left, &right) { input in
            withPointers(&outLeft, &outRight) { output in limiter.process(input, frames: frames, output: output) }
        }
        var tailLeft = [Float](repeating: 0, count: limiter.latency)
        var tailRight = [Float](repeating: 0, count: limiter.latency)
        let drained = withPointers(&tailLeft, &tailRight) { limiter.drain($0) }
        #expect(written + drained == frames)
        let all = Array(outLeft.prefix(written)) + Array(tailLeft.prefix(drained)) + Array(outRight.prefix(written))
        #expect(all.allSatisfy { abs($0) <= limiter.ceilingLevel })
        // The burst is held right at the ceiling, not crushed far below it.
        #expect(all.map(abs).max()! > limiter.ceilingLevel * 0.99)
    }

    @Test func everythingComesOutInOrderUnchanged() {
        let limiter = Limiter(channels: 1, sampleRate: rate)
        var input = sine(440, 4_800)
        let original = input
        var output = [Float](repeating: 0, count: input.count)
        let out = input.withUnsafeMutableBufferPointer { i in
            output.withUnsafeMutableBufferPointer { o in limiter.process([i.baseAddress!], frames: 4_800, output: [o.baseAddress!]) }
        }
        #expect(out == 4_800 - limiter.latency)
        var tail = [Float](repeating: 0, count: limiter.latency)
        #expect(tail.withUnsafeMutableBufferPointer { limiter.drain([$0.baseAddress!]) } == limiter.latency)
        #expect(Array(output.prefix(out)) + tail == original)
    }

    @Test func untouchedSoundPassesThroughExactlyWithNothingLost() {
        let shaper = SoundShaper(sampleRate: rate, channels: 2)
        shaper.apply(SoundSettings(), song: nil, instant: true)
        let input = sine(1_000, 2_000, amplitude: 0.99)
        var left = input
        var right = input
        var outLeft = [Float](repeating: 0, count: 2_000)
        var outRight = [Float](repeating: 0, count: 2_000)
        let n = withPointers(&left, &right) { i in withPointers(&outLeft, &outRight) { o in shaper.process(i, frames: 2_000, output: o) } }
        var tailLeft = [Float](repeating: 0, count: shaper.latency)
        var tailRight = [Float](repeating: 0, count: shaper.latency)
        let m = withPointers(&tailLeft, &tailRight) { shaper.drain($0) }
        #expect(n + m == 2_000)
        #expect(Array(outLeft.prefix(n)) + Array(tailLeft.prefix(m)) == input)
        #expect(Array(outRight.prefix(n)) + Array(tailRight.prefix(m)) == input)
    }

    @Test func theDelayIsAMomentLong() {
        #expect(Limiter(channels: 1, sampleRate: 48_000).latency == 72)
        #expect(Limiter(channels: 1, sampleRate: 44_100).latency == 66)
    }

    private func withPointers<R>(_ a: inout [Float], _ b: inout [Float], _ body: ([UnsafeMutablePointer<Float>]) -> R) -> R {
        a.withUnsafeMutableBufferPointer { x in b.withUnsafeMutableBufferPointer { y in body([x.baseAddress!, y.baseAddress!]) } }
    }
}
