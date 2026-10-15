import Foundation
import Testing
@testable import OctoKit

@Suite struct AutomixTest {
    func sine(_ hz: Double, _ seconds: Double, _ rate: Int, amplitude: Double = 1) -> [Float] {
        (0..<Int(seconds * Double(rate))).map { Float(amplitude * sin(2 * Double.pi * hz * Double($0) / Double(rate))) }
    }

    func envelopeOf(_ samples: [Float], _ rate: Int, channels: Int = 1, block: Int? = nil) -> SectionEnvelope {
        let builder = EnvelopeBuilder(sampleRate: rate, channels: channels, startMs: 0)
        let step = block ?? samples.count
        var at = 0
        while at < samples.count {
            let length = min(step, samples.count - at)
            builder.push(samples, offset: at, length: length)
            at += length
        }
        return builder.build()
    }

    func near(_ a: Double, _ b: Double, _ tolerance: Double) -> Bool { abs(a - b) <= tolerance }

    func plan(_ name: String) -> TransitionPlan { AutomixCases.plan(AutomixCases.pair(name)) }

    func offBy(_ x: Double, _ period: Double) -> Double {
        let r = (x.truncatingRemainder(dividingBy: period) + period).truncatingRemainder(dividingBy: period)
        return r > period / 2 ? r - period : r
    }

    // Envelope

    @Test func aFullScaleSineReadsMinusThreeDecibels() {
        let envelope = envelopeOf(sine(1_000, 1, 48_000), 48_000)
        #expect(envelope.size == 100)
        #expect(near(Double(envelope.db[50]), -3.01, 0.02))
        #expect(envelope.lowDb[50] < -30, "1 kHz barely reaches the bass band")
    }

    @Test func aBassToneFillsTheBassBand() {
        let envelope = envelopeOf(sine(50, 1, 44_100, amplitude: 0.5), 44_100)
        #expect(near(Double(envelope.db[60]), Double(envelope.lowDb[60]), 0.5))
    }

    @Test func silenceIsTheFloorAndOnsetsMarkTheRise() {
        let samples = [Float](repeating: 0, count: 48_000) + sine(1_000, 1, 48_000)
        let envelope = envelopeOf(samples, 48_000)
        #expect(envelope.db[10] == silentDb)
        #expect(envelope.onset[10] == 0)
        #expect(envelope.onset[100] > 1)
        #expect(near(Double(envelope.onset[150]), 0, 0.05))
    }

    @Test func blocksOfAnySizeAndSplitFramesGiveTheSameEnvelope() {
        let mono = sine(220, 2, 22_050, amplitude: 0.3)
        let stereo = (0..<(mono.count * 2)).map { mono[$0 / 2] }
        let whole = envelopeOf(mono, 22_050)
        let pieces = envelopeOf(stereo, 22_050, channels: 2, block: 333)
        #expect(whole.size == 200)
        #expect(whole.db == pieces.db)
        #expect(whole.lowDb == pieces.lowDb)
        let shorts = mono.map { Int16(Int($0 * 32767)) }
        let builder = EnvelopeBuilder(sampleRate: 22_050, channels: 1, startMs: 0)
        builder.push(shorts)
        #expect(near(Double(whole.db[100]), Double(builder.build().db[100]), 0.01))
    }

    @Test func aMinuteOfStereoAt48kHzIsQuick() {
        let mono = AutomixCases.songs["beat-120"]!.renderMono(140_000, 200_000)
        let samples = (0..<(mono.count * 2)).map { mono[$0 / 2] }
        func run() -> Int {
            let began = Date()
            let builder = EnvelopeBuilder(sampleRate: 48_000, channels: 2, startMs: 140_000)
            var at = 0
            while at < samples.count {
                let length = min(8_192, samples.count - at)
                builder.push(samples, offset: at, length: length)
                at += length
            }
            _ = analyzeTail(builder.build())
            return Int(Date().timeIntervalSince(began) * 1000)
        }
        _ = run()
        let ms = (1...2).map { _ in run() }.min()!
        print("automix: envelope and features of 60 s of 48 kHz stereo in \(ms) ms")
        // An unoptimized test build runs many times slower than the app; the bound holds there.
        #if !DEBUG
        #expect(ms < 400, "took \(ms) ms")
        #endif
    }

    // Features

    @Test func trailingSilenceEndsTheSound() {
        let features = AutomixCases.tail("silence-tail").features
        #expect(near(Double(features.soundEndMs!), 192_000, 30))
        #expect(features.soundEndMs == features.outroStartMs)
        #expect(features.gateDb == -60)
        #expect(features.boundariesMs.contains { abs($0 - 192_000) <= 300 })
    }

    @Test func aFadeOutStartsTheOutroWhereItDropsSixDecibels() {
        let features = AutomixCases.tail("fade-out").features
        #expect(near(Double(features.outroStartMs!), 184_000, 500))
        #expect((205_000...215_000).contains(features.soundEndMs!))
        #expect(features.tempo == nil)
    }

    @Test func aQuietIntroPlaysUnderTheEndOfAHotSong() {
        let head = AutomixCases.head("quiet-intro").features
        #expect(near(Double(head.introEndMs!), 5_750, 20))
        #expect(AutomixCases.head("hot-end").features.introEndMs == 0)
        let plan = plan("quiet-intro")
        #expect(self.plan("hot-end").overlapMs == shortestBlendMs)
        #expect(plan.overlapMs >= head.introEndMs! - plan.entryMs, "\(plan.overlapMs)")
        #expect(plan.startMs + plan.overlapMs == 199_750)
        #expect(plan.reason.contains("(full from 5."), "\(plan.reason)")
        #expect(self.plan("quiet-intro-capped").overlapMs == 4_000)
    }

    @Test func aHotEndingHasNoOutro() {
        let features = AutomixCases.tail("hot-end").features
        #expect(features.soundEndMs == 200_000)
        #expect(features.soundEndMs == features.outroStartMs)
        #expect(features.tempo == nil, "a steady tone has no beat")
    }

    @Test func aThreeThreeTwoKickPatternKeepsItsBeat() {
        let length = 60_000.0
        func hit(_ hz: Double, _ db: Double, _ bpm: Double, _ firstMs: Double, _ decayMs: Double) -> SongLayer {
            SongLayer("pulse", 0, length, hz: hz, db: db, bpm: bpm, firstMs: firstMs, every: 1, decayMs: decayMs)
        }
        let song = SyntheticSong(rate: 44_100, channels: 1, lengthMs: 60_000, layers: [
            SongLayer("tone", 0, length, hz: 300, db: -30),
            hit(60, -6, 40, 0, 80),
            hit(60, -6, 40, 562.5, 80),
            hit(60, -6, 40, 1_125, 80),
            hit(2_000, -12, 20, 1_500, 30),
        ])
        let tempo = song.head().features.tempo!
        #expect(near(foldTempoRatio(tempo.bpm / 80), 1, 0.01), "\(tempo)")
        #expect(tempo.confident, "\(tempo)")
    }

    @Test func aClickTrackHasItsTempoBeatAndBar() throws {
        let tempo = try #require(AutomixCases.tail("beat-120").features.tempo)
        #expect(tempo.confident)
        #expect(tempo.consistency >= 0.9)
        #expect(near(tempo.bpm, 120, 1))
        #expect(near(offBy(tempo.downbeatMs - 500, 2_000), 0, 20))
        #expect(near(offBy(tempo.firstBeatMs - 500, 500), 0, 20))
        let head = AutomixCases.head("beat-120-b").features.tempo!
        #expect(near(head.downbeatMs, 1_000, 20))
    }

    @Test func otherTempos() {
        #expect(near(AutomixCases.tail("beat-100").features.tempo!.bpm, 100, 1))
        #expect(near(AutomixCases.head("beat-118").features.tempo!.bpm, 118, 0.1))
        #expect(near(AutomixCases.tail("beat-118").features.tempo!.bpm, 118, 0.1))
        #expect(AutomixCases.tail("beat-118").features.tempo!.confident)
    }

    @Test func aSilentSectionHasNoSound() {
        let analysis = analyzeHead(envelopeOf([Float](repeating: 0, count: 48_000 * 5), 48_000))
        #expect(analysis.features.soundStartMs == nil)
        #expect(analysis.features.soundEndMs == nil)
        #expect(analysis.features.tempo == nil)
    }

    @Test func scatteredHitsAreNotABeat() {
        var seed: UInt64 = 12345
        func next() -> Double {
            seed = seed &* 6364136223846793005 &+ 1442695040888963407
            return Double(seed >> 11) / Double(UInt64(1) << 53)
        }
        let rate = 22_050
        var samples = [Float](repeating: 0, count: rate * 30)
        var at = 0.0
        while true {
            at += 0.15 + next() * 0.6
            let start = Int(at * Double(rate))
            if start >= samples.count { break }
            for i in 0..<min(2_000, samples.count - start) {
                samples[start + i] += Float(0.5 * exp(-Double(i) / 300) * sin(2 * Double.pi * 80 * Double(i) / Double(rate)))
            }
        }
        let tempo = analyzeHead(envelopeOf(samples, rate)).features.tempo
        #expect(tempo == nil || !tempo!.confident, "found \(String(describing: tempo))")
    }

    @Test func aTagTempoPicksOnlyAmongTheFoundOctaves() {
        let envelope = AutomixCases.songs["beat-120"]!.envelope(0, 30_000)
        let found = analyzeHead(envelope).features.tempo!
        #expect(near(found.bpm, 120, 0.5))
        #expect(near(analyzeHead(envelope, tagBpm: 61).features.tempo!.bpm, 60, 0.5))
        #expect(near(analyzeHead(envelope, tagBpm: 238).features.tempo!.bpm, 240, 1))
        #expect(analyzeHead(envelope, tagBpm: 121).features.tempo == found)
        for tag in [125.0, 62, 0, -120, 90, Double.nan] {
            #expect(analyzeHead(envelope, tagBpm: tag).features.tempo == found, "tag \(tag)")
        }
        let fast = AutomixCases.songs["beat-128"]!.envelope(0, 30_000)
        let fastFound = analyzeHead(fast).features.tempo!
        #expect(near(fastFound.bpm, 128, 0.5))
        #expect(analyzeHead(fast, tagBpm: 70).features.tempo == fastFound)
    }

    @Test func theLiveTapHearsTheWholeSong() {
        let song = AutomixCases.songs["fade-out"]!
        let tap = LiveTap(sampleRate: song.rate, channels: 1)
        let samples = song.renderMono(0, 220_000)
        var at = 0
        while at < samples.count {
            let length = min(4_800, samples.count - at)
            tap.push(samples, offset: at, length: length)
            at += length
        }
        #expect(tap.heardMs() == 220_000)
        #expect(near(tap.bodyLevelDb()!, -15.25, 0.1))
        #expect(tap.tempoPrior() == nil, "a steady tone has no tempo")
        let beat = AutomixCases.songs["beat-100"]!
        let beatTap = LiveTap(sampleRate: beat.rate, channels: 1)
        beatTap.push(beat.renderMono(0, 60_000))
        #expect(near(beatTap.tempoPrior()!, 100, 0.1))
        #expect(LiveTap(sampleRate: 44_100, channels: 2).bodyLevelDb() == nil)
    }

    @Test func theFftMatchesAPlainDft() {
        let n = 64
        let input = (0..<n).map { sin(Double($0) * 0.37) + 0.5 * cos(Double($0) * 1.9) + ($0 == 5 ? 1.0 : 0.0) }
        var out = [Double](repeating: 0, count: n / 2 + 1)
        RealFft(size: n).magnitudes(input, &out)
        for k in 0...(n / 2) {
            var re = 0.0, im = 0.0
            for t in 0..<n {
                re += input[t] * cos(2 * Double.pi * Double(k * t) / Double(n))
                im -= input[t] * sin(2 * Double.pi * Double(k * t) / Double(n))
            }
            #expect(near((re * re + im * im).squareRoot(), out[k], 1e-9), "bin \(k)")
        }
    }

    @Test func theBiquadsPassAndCutWhereTheyShould() {
        func gainOf(_ filter: Biquad, _ hz: Double, _ rate: Int) -> Double {
            var peak = 0.0
            for i in 0..<rate {
                let y = filter.process(sin(2 * Double.pi * hz * Double(i) / Double(rate)))
                if i > rate / 2 { peak = max(peak, abs(y)) }
            }
            return peak
        }
        #expect(near(gainOf(Biquad.lowPass(sampleRate: 48_000, hz: 1_000), 100, 48_000), 1, 0.01))
        #expect(near(gainOf(Biquad.lowPass(sampleRate: 48_000, hz: 1_000), 1_000, 48_000), 0.7071, 0.01))
        #expect(gainOf(Biquad.lowPass(sampleRate: 48_000, hz: 1_000), 10_000, 48_000) < 0.02)
        #expect(near(gainOf(Biquad.highPass(sampleRate: 44_100, hz: 200), 5_000, 44_100), 1, 0.01))
        #expect(gainOf(Biquad.highPass(sampleRate: 44_100, hz: 200), 20, 44_100) < 0.02)
        #expect(gainOf(Biquad.lowPass(sampleRate: 22_050, hz: 18_000), 1_000, 22_050) < 1.01)
    }

    // Plans

    @Test func trailingSilenceIsSkipped() {
        let plan = plan("trailing-silence")
        let soundEnd = AutomixCases.tail("silence-tail").features.soundEndMs!
        #expect(plan.startMs + plan.overlapMs <= soundEnd)
        #expect(plan.startMs + plan.overlapMs >= soundEnd - 1_000)
        #expect(plan.overlapMs == 1_800)
        #expect(plan.kind == .cut)
        #expect(near(Double(plan.entryMs), 1_480, 30))
    }

    @Test func aLongFadeOutBlendsFromTheOutro() {
        let plan = plan("fade-out")
        let outro = AutomixCases.tail("fade-out").features.outroStartMs!
        #expect(((outro - 500)...(outro + 3_000)).contains(plan.startMs), "start \(plan.startMs) outro \(outro)")
        #expect(plan.overlapMs == 8_000)
        #expect(plan.kind == .lift, "the next song is louder than the fading one")
        #expect(plan.k == liftCurve)
        #expect(plan.reason.hasPrefix("lift at"))
    }

    @Test func aHotEndingCutsShortAtTheEnd() {
        let plan = plan("hot-end")
        #expect(plan.startMs + plan.overlapMs == 200_000 - endMarginMs)
        #expect(plan.kind == .cut)
        #expect(plan.k == cutCurve)
    }

    @Test func theSameTempoBlendsFourBarsFromABarLine() {
        let plan = plan("same-tempo")
        #expect(near(offBy(Double(plan.startMs) - 500, 2_000), 0, 20))
        #expect(near(Double(plan.overlapMs), 8_000, 10))
        #expect(plan.kind == .blend)
        #expect(near(Double(plan.entryMs), 1_000, 20))
        #expect(plan.barLocked)
        #expect(plan.headroomDb == overlapHeadroomDb)
        #expect(plan.filterStrength == filterStrength)
        #expect(plan.beatMatchRate == nil)
        #expect(plan.reason.contains("4 bars of 120.0 BPM"))
        #expect(self.plan("same-tempo-long").overlapMs == 8_000)
    }

    @Test func aShortSliderKeepsWholeBars() {
        #expect(near(Double(plan("same-tempo-short").overlapMs), 4_000, 10))
    }

    @Test func differentTemposBlendTwoBars() {
        let plan = plan("tempo-clash")
        #expect(near(Double(plan.overlapMs), 4_000, 10))
        #expect(near(offBy(Double(plan.startMs) - 500, 2_000), 0, 20))
    }

    @Test func beatMatchNudgesTheNextSongOntoTheBar() {
        let plan = plan("beat-match")
        #expect(near(plan.beatMatchRate!, 120.0 / 118.0, 0.005))
        let head = AutomixCases.head("beat-118").features.tempo!
        #expect(near(offBy(Double(plan.entryMs) - head.downbeatMs, head.barMs), 0, 1))
        #expect(near(Double(plan.overlapMs), 8_000, 10))
        #expect(self.plan("beat-match-off").beatMatchRate == nil, "beat match is off unless asked for")
    }

    @Test func smartOffIsThePlainCrossfade() {
        let plan = plan("smart-off")
        #expect(plan.kind == .crossfade)
        #expect(plan.startMs == 192_000)
        #expect(plan.overlapMs == 8_000)
        #expect(plan.entryMs == 0)
        #expect(plan.k == 0)
        #expect(plan.filterStrength == 0)
        #expect(plan.headroomDb == 0)
    }

    @Test func thePlainCrossfadeForAGenreKeepsItsCurve() {
        let plan = plan("classical")
        #expect(plan.kind == .crossfade)
        #expect(plan.k == crossfadeCurve)
        #expect(plan.filterStrength == 0)
    }

    @Test func withoutTheTailItBlendsLateAtTheEnd() {
        for name in ["no-analysis", "no-tail"] {
            let plan = plan(name)
            let length = AutomixCases.songs[AutomixCases.pair(name).a]!.lengthMs
            #expect(plan.late, "\(name)")
            #expect(plan.startMs == length - endMarginMs - 8_000, "\(name)")
            #expect(plan.overlapMs == 8_000, "\(name)")
            #expect(plan.filterStrength == filterStrength, "\(name)")
            #expect(!plan.barLocked, "\(name)")
        }
        #expect(plan("no-analysis").entryMs == 0)
        #expect(near(Double(plan("no-tail").entryMs), 1_480, 30), "the next song still skips its silence")
    }

    @Test func withoutTheHeadThereIsNoBarLock() {
        let plan = plan("no-head")
        #expect(!plan.barLocked)
        #expect(!plan.late)
        #expect(plan.entryMs == 0)
    }

    @Test func genresThatShouldNotBeMixedGetThePlainCrossfade() {
        #expect(plan("classical").kind == .crossfade)
        #expect(plan("podcast").kind == .crossfade)
        #expect(plan("podcast").reason.hasSuffix("genre Podcast"))
    }

    @Test func paceAndSkipSilenceTurnOffBarLockAndBeatMatch() {
        for name in ["pace", "skip-silence"] {
            let plan = plan(name)
            #expect(!plan.barLocked, "\(name)")
            #expect(plan.beatMatchRate == nil, "\(name)")
            #expect(plan.kind != .crossfade && plan.kind != .gapless, "\(name)")
        }
    }

    @Test func tooLateForTheChosenStartBlendsAtTheEnd() {
        let late = plan("late")
        #expect(late.late)
        #expect(late.startMs == 199_750 - 8_000)
        #expect(late.overlapMs == 8_000)
        #expect(!late.barLocked)
        let short = plan("late-short")
        #expect(short.startMs == 197_000)
        #expect(short.overlapMs == 2_750)
        #expect(plan("too-late").kind == .gapless)
    }

    @Test func theStartLeavesTimeToPreRoll() {
        let plan = plan("pre-roll")
        #expect(plan.startMs >= 183_000 + preRollMs)
        #expect(!plan.late)
    }

    @Test func theBlendWaitsUntilTheSongCountsAsPlayed() {
        let plan = plan("seeked-forward")
        #expect(plan.late)
        let soundEnd = AutomixCases.tail("fade-out").features.soundEndMs!
        #expect(plan.startMs + plan.overlapMs == soundEnd)
        for pair in AutomixCases.pairs {
            let p = AutomixCases.plan(pair)
            if p.kind == .gapless || p.kind == .crossfade { continue }
            #expect(p.startMs >= AutomixCases.songs[pair.a]!.lengthMs / 2, "\(pair.name)")
        }
    }

    @Test func theWholeSongsLevelMovesTheOutro() {
        let plan = plan("whole-song-level")
        let moved = AutomixCases.tail("fade-out").withBodyLevel(-24).features
        #expect(moved.bodyDb == -24)
        #expect(moved.outroStartMs! > AutomixCases.tail("fade-out").features.outroStartMs! + 4_000)
        #expect(((moved.outroStartMs! - 500)...(moved.outroStartMs! + 3_000)).contains(plan.startMs))
    }

    @Test func theWholeSongsTempoSetsTheOctaveOrDropsTheLock() {
        let half = plan("tempo-prior")
        #expect(near(half.beatMs!, 1_000, 1))
        #expect(half.reason.contains("of 120.0 BPM"), "\(half.reason)")
        #expect(!plan("tempo-prior-off").barLocked, "a tempo the whole song does not share is not trusted")
    }

    @Test func anAlbumInOrderStaysGapless() {
        let plan = plan("album-in-order")
        #expect(plan.kind == .gapless)
        #expect(plan.overlapMs == 0)
        #expect(plan.startMs == 200_000)
        #expect(plan.reason == "gapless: the album plays in order")
    }

    @Test func repeatOneTheSleepTimerAndCrossfadeOffNeverBlend() {
        #expect(plan("stop-at-end").kind == .gapless)
        #expect(plan("repeat-one").kind == .gapless)
        #expect(plan("repeat-one").reason == "gapless: repeat one")
        #expect(plan("crossfade-off").kind == .gapless)
    }

    @Test func sweepsOffLeavesTheFiltersOpen() {
        let plan = plan("no-sweeps")
        #expect(plan.filterStrength == 0)
        #expect(near(plan.outgoingLowPassAt(0.9), openLowPassHz, 1e-9))
        #expect(near(plan.outgoingHighPassAt(0.9), openHighPassHz, 1e-9))
        #expect(near(plan.incomingHighPassAt(0.1), incomingOpenHz, 1e-9))
    }

    @Test func aShortSongGetsThePlainCrossfade() {
        let plan = planTransition(current: FadeSong(albumId: "a", albumOrder: 1, durationMs: 30_000),
                                  next: FadeSong(albumId: "b", albumOrder: 1, durationMs: 180_000),
                                  tail: AutomixCases.tail("hot-end"), head: AutomixCases.head("plain-b"),
                                  settings: AutomixSettings(maxOverlapMs: 8_000))
        #expect(plan.kind == .crossfade)
        #expect(plan.startMs == 22_000)
    }

    // Curves

    @Test func theGainsKeepEqualPowerAndEndCleanly() {
        for k in [0.0, blendCurve, crossfadeCurve, liftCurve, cutCurve] {
            #expect(near(automixOutGain(0, k), 1, 1e-12))
            #expect(near(automixInGain(0, k), 0, 1e-6))
            #expect(near(automixOutGain(1, k), 0, 1e-12))
            #expect(near(automixInGain(1, k), 1, 1e-12))
            var last = 1.0
            for step in 0...100 {
                let t = Double(step) / 100
                let out = automixOutGain(t, k), into = automixInGain(t, k)
                #expect(near(out * out + into * into, 1, 1e-9))
                #expect(out <= last + 1e-12)
                last = out
            }
        }
        #expect(near(automixOutGain(0.3, 0), Double(fadeOutVolume(0.3)), 1e-6))
        #expect(near(sCurve(0.5), 0.5, 1e-12))
    }

    @Test func theFiltersSweepTheirRanges() {
        #expect(near(outgoingLowPassHz(0, filterStrength), 18_000, 1e-9))
        #expect(near(outgoingLowPassHz(1, filterStrength), 18_000 * pow(450.0 / 18_000, 0.7), 1e-6))
        #expect(near(outgoingHighPassHz(0, filterStrength), 10, 1e-9))
        #expect(near(outgoingHighPassHz(0.5, filterStrength), 210, 1e-9))
        #expect(near(outgoingHighPassHz(0.9, filterStrength), 210, 1e-9))
        #expect(near(incomingHighPassHz(0, filterStrength), 472.5, 1e-9))
        #expect(near(incomingHighPassHz(0.6, filterStrength), 20, 1e-9))
        #expect(near(incomingHighPassHz(1, filterStrength), 20, 1e-9))
        #expect(near(outgoingLowPassHz(1, 0), 18_000, 1e-9))
    }

    @Test func theSteppedLowPassHoldsEachBeatThenGlides() {
        let beats = [0.25, 0.5, 0.75]
        let glide = 0.05
        #expect(near(steppedOutgoingLowPassHz(0.1, filterStrength, beats, glide), 18_000, 1e-9))
        #expect(near(steppedOutgoingLowPassHz(0.3, filterStrength, beats, glide), outgoingLowPassHz(0.25, filterStrength), 1e-9))
        #expect(near(steppedOutgoingLowPassHz(0.45, filterStrength, beats, glide), outgoingLowPassHz(0.25, filterStrength), 1e-9))
        #expect(near(steppedOutgoingLowPassHz(0.475, filterStrength, beats, glide), outgoingLowPassHz(0.375, filterStrength), 1e-9))
        #expect(near(steppedOutgoingLowPassHz(0.5, filterStrength, beats, glide), outgoingLowPassHz(0.5, filterStrength), 1e-9))
        #expect(near(steppedOutgoingLowPassHz(1, filterStrength, beats, glide), outgoingLowPassHz(1, filterStrength), 1e-9))
    }

    @Test func aPlanOnTheBeatStepsItsLowPass() {
        let plan = plan("same-tempo")
        let beats = plan.beatProgress()
        #expect(beats.count == 15)
        #expect(near(beats[0], 0.0625, 0.002))
        #expect(near(plan.outgoingLowPassAt(beats[0] + 0.01), plan.outgoingLowPassAt(beats[1] - 0.035), 1e-9))
    }

    @Test func beatMatchEasesBackAfterTheBlend() {
        #expect(near(beatMatchRateAt(1.03, 2_000, 8_000), 1.03, 1e-12))
        #expect(near(beatMatchRateAt(1.03, 8_000, 8_000), 1.03, 1e-12))
        #expect(near(beatMatchRateAt(1.03, 10_500, 8_000), 1.015, 1e-12))
        #expect(near(beatMatchRateAt(1.03, 13_000, 8_000), 1, 1e-12))
        #expect(plan("same-tempo").incomingRateAt(1_000) == 1)
    }

    @Test func foldingTreatsHalfAndDoubleTimeAsTheSame() {
        #expect(near(foldTempoRatio(2), 1, 1e-12))
        #expect(near(foldTempoRatio(0.5), 1, 1e-12))
        #expect(near(foldTempoRatio(1.2), 1.2, 1e-12))
    }
}
