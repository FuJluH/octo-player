import Foundation
import Testing
@testable import OctoKit

@Suite struct TransitionShaperTest {
    let rate = 48_000

    func plan(start: Int = 1_000, entry: Int = 0, overlap: Int = 1_000, k: Double = 0.4, strength: Double = 0, headroomDb: Double = 0,
              beatMs: Double? = nil, beatAnchorMs: Double? = nil, rate: Double? = nil) -> TransitionPlan {
        TransitionPlan(startMs: start, entryMs: entry, overlapMs: overlap, kind: .blend, k: k, filterStrength: strength,
                       beatMatchRate: rate, beatMs: beatMs, beatAnchorMs: beatAnchorMs, late: false, headroomDb: headroomDb, reason: "test")
    }

    /// `frames` mono frames at a fixed level, as 16-bit sound read into floats.
    func level(_ frames: Int, _ value: Int16 = 16_384) -> [Float] { [Float](repeating: Float(value) / 32_768, count: frames) }

    func tone(_ frames: Int, _ hz: Double, from: Int = 0) -> [Float] {
        (0..<frames).map { Float(Int16(Int(16_000 * sin(2 * Double.pi * hz * Double(from + $0) / Double(rate))))) / 32_768 }
    }

    /// A step with nothing to shape, kept running for crossfade, its stream starting at `fromMs`
    /// in its song.
    func processor(fromMs: Int = 0, speed: Float = 1, entry: String? = nil) -> DeckProcessor {
        let processor = DeckProcessor(keepActive: { true }, tap: nil, stage: nil)
        processor.configure(sampleRate: rate, channels: 1)
        processor.setSpeed(speed)
        processor.flush(streamStartMs: Double(fromMs), entryId: entry)
        return processor
    }

    func feed(_ processor: DeckProcessor, _ samples: [Float], into out: inout [Float]) {
        var block = samples
        block.withUnsafeMutableBufferPointer { buffer in
            processor.process([buffer.baseAddress!], frames: buffer.count)
        }
        out += block
    }

    /// Plays `ms` of `source` through the step in 10 ms buffers.
    func run(_ processor: DeckProcessor, _ ms: Int, _ source: ((Int, Int) -> [Float])? = nil) -> [Float] {
        var out: [Float] = []
        let step = rate / 100
        var at = 0
        while at < ms * rate / 1_000 {
            feed(processor, source?(step, at) ?? level(step), into: &out)
            at += step
        }
        return out
    }

    func msToFrame(_ ms: Double) -> Int { Int(ms * Double(rate) / 1_000) }

    func rms(_ samples: [Float], _ from: Int, _ to: Int) -> Double {
        (samples[from..<to].reduce(0.0) { $0 + Double($1) * Double($1) } / Double(to - from)).squareRoot()
    }

    var vectors: [String: Any] { try! JSONSerialization.jsonObject(with: Data(automixVectorsJSON.utf8)) as! [String: Any] }

    @Test func theSweepFiltersMatchTheSharedFilters() {
        var failures: [String] = []
        for o in vectors["biquads"] as! [[String: Any]] {
            let kind: FilterKind = (o["type"] as! String) == "lowPass" ? .lowPass : .highPass
            let sampleRate = (o["rate"] as! NSNumber).intValue
            let hz = (o["hz"] as! NSNumber).doubleValue
            let expected = (o["coefficients"] as! [NSNumber]).map(\.doubleValue)
            let got = sweepCoefficients(kind, sampleRate: sampleRate, hz: hz)
            for (i, e) in expected.enumerated() where abs(got[i] - e) > 1e-12 {
                failures.append("\(kind) \(sampleRate) \(hz): coefficient \(i) \(e), got \(got[i])")
            }
            let filter = SweptFilter(kind, sampleRate: sampleRate, channels: 1)
            filter.setCutoff(hz)
            for (n, e) in (o["impulse"] as! [NSNumber]).map(\.doubleValue).enumerated() {
                let y = filter.process(n == 0 ? 1 : 0, channel: 0)
                if abs(y - e) > 1e-9 { failures.append("\(kind) \(sampleRate) \(hz): impulse \(n) \(e), got \(y)") }
            }
        }
        #expect(failures.isEmpty, "\(failures.prefix(10).joined(separator: "\n"))")
    }

    @Test func theVolumesAndCutoffsFollowTheSharedCurves() {
        let all = vectors
        for o in all["gains"] as! [[String: Any]] {
            let t = (o["t"] as! NSNumber).doubleValue, k = (o["k"] as! NSNumber).doubleValue
            let out = DeckTransition(entryId: nil, plan: plan(k: k), incoming: false)
            let into = DeckTransition(entryId: nil, plan: plan(k: k), incoming: true)
            let expectOut = t >= 1 ? 0 : (o["out"] as! NSNumber).doubleValue
            let expectIn = t < 0 ? 0 : (o["in"] as! NSNumber).doubleValue
            #expect(abs(out.gainAt(t) - expectOut) <= 1e-9, "out at \(t), k \(k)")
            #expect(abs(into.gainAt(t) - expectIn) <= 1e-9, "in at \(t), k \(k)")
        }
        for o in all["filters"] as! [[String: Any]] {
            let t = (o["t"] as! NSNumber).doubleValue, strength = (o["strength"] as! NSNumber).doubleValue
            let out = DeckTransition(entryId: nil, plan: plan(strength: strength), incoming: false)
            let into = DeckTransition(entryId: nil, plan: plan(strength: strength), incoming: true)
            #expect(abs(out.lowPassAt(t) - (o["outgoingLowPassHz"] as! NSNumber).doubleValue) <= 1e-6)
            #expect(abs(out.highPassAt(t) - (o["outgoingHighPassHz"] as! NSNumber).doubleValue) <= 1e-6)
            #expect(abs(into.highPassAt(t) - (o["incomingHighPassHz"] as! NSNumber).doubleValue) <= 1e-6)
        }
    }

    @Test func theOutgoingSongFollowsItsCurveOnItsOwnSongTime() {
        let processor = processor(fromMs: 500)
        processor.arm(DeckTransition(entryId: nil, plan: plan(k: 0.4), incoming: false))
        let out = run(processor, 2_000)
        #expect(out[0..<msToFrame(490)].allSatisfy { $0 == 0.5 })
        for t in [0.1, 0.25, 0.5, 0.75, 0.9] {
            let frame = msToFrame(500 + t * 1_000)
            #expect(abs(Double(out[frame]) - 0.5 * automixOutGain(t, 0.4)) <= 2e-3, "at \(t)")
        }
        #expect(out[msToFrame(1_540)...].allSatisfy { abs($0) < 1e-6 })
    }

    @Test func theIncomingSongIsSilentUntilItsEntryThenFadesInAndIsLeftAlone() {
        let processor = processor()
        processor.arm(DeckTransition(entryId: nil, plan: plan(entry: 600, overlap: 1_000, k: 0.55), incoming: true))
        let out = run(processor, 2_500)
        #expect(out[0..<msToFrame(600)].allSatisfy { $0 == 0 })
        for t in [0.1, 0.5, 0.9] {
            #expect(abs(Double(out[msToFrame(600 + t * 1_000)]) - 0.5 * automixInGain(t, 0.55)) <= 2e-3, "at \(t)")
        }
        #expect(out[msToFrame(1_700)...].allSatisfy { $0 == 0.5 })
    }

    @Test func bothSongsDropByTheHeadroomInTheMiddleOfTheBlend() {
        let processor = processor()
        processor.arm(DeckTransition(entryId: nil, plan: plan(start: 0, headroomDb: 1), incoming: false))
        let out = run(processor, 800)
        let expected = 0.5 * automixOutGain(0.5, 0.4) * pow(10, -1.0 / 20)
        #expect(abs(Double(out[msToFrame(500)]) - expected) <= 2e-3)
    }

    @Test func theSweepsCutTheOutgoingSongsTopAndBass() {
        let strong = plan(start: 0, overlap: 2_000, strength: filterStrength)
        func loudness(_ hz: Double, _ transition: DeckTransition?) -> (Double, Double) {
            let processor = processor()
            processor.arm(transition)
            let out = run(processor, 1_900) { n, from in tone(n, hz, from: from) }
            let early = rms(out, msToFrame(100), msToFrame(200)) / (transition?.gainAt(0.075) ?? 1)
            let late = rms(out, msToFrame(1_700), msToFrame(1_800)) / (transition?.gainAt(0.875) ?? 1)
            return (early, late)
        }
        let (highEarly, highLate) = loudness(6_000, DeckTransition(entryId: nil, plan: strong, incoming: false))
        let (_, highDry) = loudness(6_000, nil)
        #expect(highEarly > highDry * 0.9, "\(highEarly) vs \(highDry)")
        #expect(highLate < highDry * 0.1, "\(highLate) vs \(highDry)")
        let (_, bassLate) = loudness(60, DeckTransition(entryId: nil, plan: strong, incoming: false))
        let (_, bassDry) = loudness(60, nil)
        #expect(bassLate < bassDry * 0.2, "\(bassLate) vs \(bassDry)")
    }

    @Test func theIncomingSongComesInThinAndOpensUp() {
        let into = DeckTransition(entryId: nil, plan: plan(entry: 0, overlap: 2_000, strength: filterStrength), incoming: true)
        let processor = processor()
        processor.arm(into)
        let out = run(processor, 3_000) { n, from in tone(n, 100, from: from) }
        let early = rms(out, msToFrame(150), msToFrame(250)) / into.gainAt(0.1)
        let dry = 16_000 / 32_768.0 / 2.0.squareRoot()
        #expect(early < dry * 0.3, "\(early) vs \(dry)")
        let after = rms(out, msToFrame(2_600), msToFrame(2_900))
        #expect(abs(after - dry) <= dry * 0.01)
    }

    @Test func anOutgoingSongThatFallsSilentFadesOutEarly() {
        let processor = processor()
        processor.arm(DeckTransition(entryId: nil, plan: plan(start: 0, overlap: 4_000, k: 0.2), incoming: false, gateDb: -50))
        let out = run(processor, 2_000) { n, from in
            from >= msToFrame(500) && from < msToFrame(900) ? level(n, 0) : level(n)
        }
        #expect(out[msToFrame(400)] > 0.3)
        #expect(out[msToFrame(900)...].allSatisfy { abs($0) < 1e-6 })
    }

    @Test func aQuietPassageShorterThanTheWaitDoesNotEndTheSong() {
        let processor = processor()
        processor.arm(DeckTransition(entryId: nil, plan: plan(start: 0, overlap: 4_000, k: 0.2), incoming: false, gateDb: -50))
        let out = run(processor, 2_000) { n, from in
            from >= msToFrame(500) && from < msToFrame(700) ? level(n, 0) : level(n)
        }
        #expect(out[msToFrame(1_500)] > 0.2)
    }

    @Test func aTransitionForAnotherSongLeavesThisOneAlone() {
        let processor = processor(entry: "q:1")
        processor.arm(DeckTransition(entryId: "q:9", plan: plan(start: 0), incoming: false))
        #expect(run(processor, 1_500).allSatisfy { $0 == 0.5 })
        let own = self.processor(entry: "q:9")
        own.arm(DeckTransition(entryId: "q:9", plan: plan(start: 0), incoming: false))
        #expect(run(own, 1_500).last == 0)
    }

    @Test func withNothingToShapeTheSoundPassesThroughUnchanged() {
        let processor = processor()
        let out = run(processor, 300) { n, from in tone(n, 440, from: from) }
        let expected = tone(msToFrame(300), 440)
        #expect(out == expected)
    }

    @Test func songTimeRunsWithTheSpeed() {
        let processor = processor(speed: 2)
        processor.arm(DeckTransition(entryId: nil, plan: plan(k: 0.4), incoming: false))
        let out = run(processor, 1_200)
        #expect(abs(Double(out[msToFrame(750)]) - 0.5 * automixOutGain(0.5, 0.4)) <= 2e-3)
        #expect(out[msToFrame(1_020)...].allSatisfy { abs($0) < 1e-6 })
    }

    @Test func droppingATransitionMidwayGlidesBackWithoutAJump() {
        let processor = processor()
        processor.arm(DeckTransition(entryId: nil, plan: plan(start: 0, overlap: 1_000, k: 0.75), incoming: false))
        var out: [Float] = []
        let step = rate / 100
        for _ in 0..<70 { feed(processor, level(step), into: &out) }
        processor.arm(nil)
        for _ in 0..<20 { feed(processor, level(step), into: &out) }
        let biggestStep = (1..<out.count).map { abs(out[$0] - out[$0 - 1]) }.max()!
        #expect(biggestStep <= 0.5 / Float(Double(rate) * transitionSlewMs / 1_000) * 1.01, "\(biggestStep)")
        #expect(out.last == 0.5)
    }

    @Test func theIncomingSongsFilterHandsOverToItsDrySoundOverTenMs() {
        let into = DeckTransition(entryId: nil, plan: plan(entry: 0, overlap: 1_000, strength: filterStrength), incoming: true)
        let processor = processor()
        processor.arm(into)
        let out = run(processor, 1_200) { n, from in tone(n, 45, from: from) }
        let dry = tone(msToFrame(1_200), 45)
        let end = msToFrame(1_000)
        let lastWet = (end..<out.count).last { out[$0] != dry[$0] }!
        let releaseMs = Double(lastWet - end) * 1_000 / Double(rate)
        #expect(releaseMs >= filterEngageMs * 0.9 && releaseMs <= filterEngageMs + 2, "released over \(releaseMs) ms")
        let slope = 16_000 / 32_768.0 * 2 * Double.pi * 45 / Double(rate)
        let biggest = ((end - msToFrame(20))..<(lastWet + 10)).map { abs(Double(out[$0] - out[$0 - 1])) }.max()!
        #expect(biggest <= slope * 1.6, "\(biggest) vs \(slope)")
    }

    @Test func theOutgoingSongsFiltersComeInWithoutAClick() {
        let processor = processor()
        processor.arm(DeckTransition(entryId: nil, plan: plan(start: 500, overlap: 1_000, strength: filterStrength), incoming: false))
        let out = run(processor, 800)
        let start = msToFrame(500)
        let biggest = ((start - 10)..<(start + msToFrame(40))).map { abs(out[$0] - out[$0 - 1]) }.max()!
        #expect(biggest < 0.002, "a step of \(biggest) where the filters came in")
    }

    @Test func anOutgoingSongArmedPartWayIntoItsBlendGlidesToTheCurve() {
        let processor = processor(fromMs: 600)
        processor.arm(DeckTransition(entryId: nil, plan: plan(start: 0, overlap: 1_000, k: 0.75), incoming: false))
        let out = run(processor, 200)
        #expect(abs(out.first! - 0.5) <= 0.5 * 0.02)
        let biggestStep = (1..<out.count).map { abs(out[$0] - out[$0 - 1]) }.max()!
        #expect(biggestStep <= 0.5 / Float(Double(rate) * transitionSlewMs / 1_000) * 1.01, "\(biggestStep)")
    }
}

@Suite struct LiveTapFeedTest {
    let rate = 44_100

    /// `seconds` of stereo sine at half scale: an RMS of -9 dBFS.
    func sine(_ seconds: Double) -> [Float] {
        let frames = Int(seconds * Double(rate))
        return (0..<(frames * 2)).map { Float(0.5 * sin(2 * Double.pi * 440 * Double($0 / 2) / Double(rate))) }
    }

    /// A kick every half second (120 BPM) with a bass note under it.
    func beat(_ seconds: Double) -> [Float] {
        let frames = Int(seconds * Double(rate))
        return (0..<(frames * 2)).map { i -> Float in
            let n = i / 2
            let sinceKick = Double(n % (rate / 2)) / Double(rate)
            return Float(0.6 * exp(-sinceKick * 30) * sin(2 * Double.pi * 60 * Double(n) / Double(rate))
                + 0.05 * sin(2 * Double.pi * 880 * Double(n) / Double(rate)))
        }
    }

    /// In 10 ms blocks, as the audio thread hands them over.
    func pushAll(_ feed: LiveTapFeed, _ samples: [Float]) {
        let block = rate / 100 * 2
        var at = 0
        while at < samples.count {
            let n = min(block, samples.count - at)
            feed.push(Array(samples[at..<(at + n)]), count: n)
            at += n
            if at % (block * 50) == 0 { feed.drain() }
        }
    }

    @Test func theTapHearsTheSongsLevel() {
        let feed = LiveTapFeed()
        defer { feed.close() }
        feed.begin("q:1", sampleRate: rate, channels: 2)
        pushAll(feed, sine(5))
        let reading = feed.reading("q:1")!
        #expect(reading.heardMs == 5_000)
        #expect(abs(reading.bodyLevelDb! + 9.03) <= 0.2)
    }

    @Test func aNewSongStartsANewTapWhereItsSoundStarts() {
        let feed = LiveTapFeed()
        defer { feed.close() }
        feed.begin("q:1", sampleRate: rate, channels: 2)
        feed.push(sine(1), count: rate * 2)
        feed.begin("q:2", sampleRate: rate, channels: 2)
        feed.push(sine(1), count: rate * 2)
        #expect(feed.reading("q:1") == nil)
        #expect(feed.reading("q:2")!.heardMs == 1_000)
    }

    @Test func aSteadyBeatGivesATempo() {
        let feed = LiveTapFeed()
        defer { feed.close() }
        feed.begin("q:1", sampleRate: rate, channels: 2)
        pushAll(feed, beat(20))
        let tempo = feed.reading("q:1")!.tempoPrior
        #expect(tempo != nil)
        #expect(abs(tempo! - 120) <= 1)
    }

    @Test func soundThatDoesNotFitIsDroppedNotWrappedOver() {
        let feed = LiveTapFeed()
        defer { feed.close() }
        feed.begin("q:1", sampleRate: rate, channels: 1)
        let tooMuch = [Float](repeating: 0.5, count: tapRingSamples + 10)
        feed.push(tooMuch, count: tooMuch.count)
        #expect(feed.reading("q:1")!.heardMs == 0)
    }

    @Test func theSongsTagTempoPicksTheOctaveHeard() {
        let feed = LiveTapFeed()
        defer { feed.close() }
        feed.begin("q:1", sampleRate: rate, channels: 2)
        pushAll(feed, beat(20))
        #expect(abs(feed.reading("q:1", tagBpm: 61)!.tempoPrior! - 60) <= 1)
        #expect(abs(feed.reading("q:1")!.tempoPrior! - 120) <= 1)
    }
}
