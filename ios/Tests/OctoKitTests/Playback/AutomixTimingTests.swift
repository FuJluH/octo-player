import Foundation
import Testing
@testable import OctoKit

@Suite struct AutomixTimingTest {
    func plan(start: Int = 180_000, entry: Int = 4_000, overlap: Int = 8_000, rate: Double? = nil, beatMs: Double? = 500) -> TransitionPlan {
        TransitionPlan(startMs: start, entryMs: entry, overlapMs: overlap, kind: .blend, k: blendCurve, filterStrength: filterStrength,
                       beatMatchRate: rate, beatMs: beatMs, beatAnchorMs: beatMs.map { _ in 0 }, late: false, headroomDb: 1, reason: "test")
    }

    @Test func theRunUpStartsSoTheEntryLandsOnTheStart() {
        let p = plan()
        #expect(p.preRollFromMs() == 1_500)
        #expect(abs(p.preRollAtMs() - 177_500) < 1e-9)
        #expect(abs(p.incomingAtMs(180_000) - 4_000) < 1e-9)
        let early = plan(entry: 1_000)
        #expect(early.preRollFromMs() == 0)
        #expect(abs(early.preRollAtMs() - 179_000) < 1e-9)
    }

    @Test func aTempoMatchedSongRunsUpAtItsRate() {
        let p = plan(rate: 1.02)
        #expect(p.preRollFromMs() == 4_000 - 2_550)
        #expect(abs(p.preRollAtMs() - (180_000 - 2_550 / 1.02)) < 1e-9)
        #expect(abs(p.incomingAtMs(180_500) - 4_510) < 1e-9)
        #expect(abs(p.alignmentErrorMs(180_500, 4_510)) < 1e-9)
        #expect(abs(p.alignmentErrorMs(180_500, 4_520.2) - 10) < 1e-9)
    }

    /// A deck that starts late and stops a while on every move, the way an audio output does.
    final class Decks {
        let plan: TransitionPlan
        let seekLag: Int
        var now = 0
        let runUpAt: Double
        var incoming: Double
        var resumesAt: Int

        init(_ plan: TransitionPlan, startLag: Int, seekLag: Int) {
            self.plan = plan
            self.seekLag = seekLag
            runUpAt = plan.preRollAtMs()
            incoming = Double(plan.preRollFromMs())
            resumesAt = startLag
        }

        var outgoing: Double { runUpAt + Double(now) }
        var playing: Bool { now >= resumesAt }

        func tick(_ ms: Int) {
            for _ in 0..<ms {
                now += 1
                if playing { incoming += plan.incomingRate() }
            }
        }

        func seek(_ to: Int) {
            incoming = Double(to)
            resumesAt = now + seekLag
        }
    }

    func align(_ decks: Decks) -> (errorMs: Double?, locked: Bool, seeks: Int) {
        let aligner = Aligner(decks.plan)
        var seeks = 0
        while true {
            switch aligner.observe(nowMs: decks.now, outgoingMs: decks.outgoing, incomingMs: decks.incoming, incomingPlaying: decks.playing) {
            case .settled(let error, let locked): return (error, locked, seeks)
            case .seek(let to):
                seeks += 1
                decks.seek(to)
            case .wait: break
            }
            decks.tick(40)
        }
    }

    @Test func aLateStartIsMovedIntoLineBeforeTheBlend() {
        let decks = Decks(plan(), startLag: 180, seekLag: 90)
        let settled = align(decks)
        #expect(abs(settled.errorMs!) < barLockToleranceMs, "\(String(describing: settled.errorMs))")
        #expect(settled.locked)
        #expect((1...alignMostSeeks).contains(settled.seeks))
        #expect(decks.outgoing < Double(plan().startMs))
        #expect(abs(plan().alignmentErrorMs(decks.outgoing, decks.incoming)) < barLockToleranceMs)
    }

    @Test func aTempoMatchedSongIsLinedUpToo() {
        let decks = Decks(plan(rate: 0.97), startLag: 250, seekLag: 140)
        let settled = align(decks)
        #expect(settled.locked, "\(String(describing: settled.errorMs))")
    }

    @Test func aDeckThatIsAlreadyInLineIsLeftAlone() {
        let settled = align(Decks(plan(), startLag: 0, seekLag: 90))
        #expect(settled.seeks == 0)
        #expect(settled.locked)
    }

    @Test func aDeckThatNeverPlaysInTimeGoesAheadUnmeasured() {
        let settled = align(Decks(plan(), startLag: 5_000, seekLag: 90))
        #expect(settled.seeks == 0)
        #expect(settled.errorMs == nil)
        #expect(!settled.locked)
    }

    @Test func aMoveThatKeepsMissingStopsAndTheBlendGoesSmooth() {
        let p = plan()
        let aligner = Aligner(p)
        let misses = [-40.0, 40.0, -40.0, 40.0]
        var now = 0
        var outgoing = p.preRollAtMs()
        var incoming = Double(p.preRollFromMs()) - 100
        var seeks = 0
        var locked: Bool?
        while locked == nil {
            switch aligner.observe(nowMs: now, outgoingMs: outgoing, incomingMs: incoming, incomingPlaying: true) {
            case .settled(_, let isLocked): locked = isLocked
            case .seek(let to):
                incoming = Double(to) + misses[seeks]
                seeks += 1
            case .wait: break
            }
            now += 20
            outgoing += 20
            incoming += 20
        }
        #expect(seeks == alignMostSeeks)
        #expect(locked == false)
        #expect(outgoing <= Double(p.startMs))
    }

    /// 20 s of a kick every half second (120 BPM) with a quiet tone under it.
    func beatEnvelope() -> SectionEnvelope {
        let rate = 44_100
        let builder = EnvelopeBuilder(sampleRate: rate, channels: 1, startMs: 0)
        let samples = (0..<(rate * 20)).map { n -> Float in
            let sinceKick = Double(n % (rate / 2)) / Double(rate)
            return Float(0.6 * exp(-sinceKick * 30) * sin(2 * Double.pi * 60 * Double(n) / Double(rate))
                + 0.05 * sin(2 * Double.pi * 880 * Double(n) / Double(rate)))
        }
        builder.push(samples)
        return builder.build()
    }

    @Test func theScoutsHandTheSongsTagTempoToTheAnalysis() {
        let envelope = beatEnvelope()
        #expect(abs(tailAnalyzer(nil)(envelope).features.tempo!.bpm - 120) <= 1)
        #expect(abs(tailAnalyzer(61)(envelope).features.tempo!.bpm - 60) <= 1)
        #expect(abs(headAnalyzer(61)(envelope).features.tempo!.bpm - 60) <= 1)
    }

    @Test func aSpareParkedWhereItShouldBeIsNotMovedAgain() {
        #expect(!needsRepark(1_500, 1_500))
        #expect(!needsRepark(1_520, 1_500))
        #expect(needsRepark(0, 1_500))
        #expect(needsRepark(1_500, 0))
    }

    @Test func aRebufferIsNotAPause() {
        #expect(isRebuffering(playWhenReady: true, state: .buffering, suppression: .none))
        #expect(!isRebuffering(playWhenReady: false, state: .buffering, suppression: .none))
        #expect(!isRebuffering(playWhenReady: false, state: .ready, suppression: .none))
        #expect(!isRebuffering(playWhenReady: true, state: .ready, suppression: .interruption))
        #expect(!isRebuffering(playWhenReady: true, state: .buffering, suppression: .interruption))
        #expect(!isRebuffering(playWhenReady: true, state: .ended, suppression: .none))
    }

    @Test func theFixedCrossfadeLastsAsLongAtAnySpeed() {
        let settings = AutomixSettings(maxOverlapMs: 8_000, smart: false)
        let a = FadeSong(albumId: "a", albumOrder: 1, durationMs: 200_000)
        let b = FadeSong(albumId: "b", albumOrder: 1, durationMs: 200_000)
        let plan = planTransition(current: a, next: b, tail: nil, head: nil, settings: settings.atSpeed(1.5),
                                  context: TransitionContext(nowMs: 100_000, pace: 1.5))
        #expect(plan.overlapMs == 12_000)
        #expect(plan.startMs == 188_000)
        #expect(settings.atSpeed(1) == settings)
        #expect(settings.atSpeed(0.5).maxOverlapMs == 4_000)
    }
}

@Suite struct BlendTimingTest {
    let playing = FadeSong(albumId: "a", albumOrder: 3, durationMs: 200_000)
    /// A radio song from outside the library: listed with no length.
    let outside = FadeSong(albumId: nil, albumOrder: nil, durationMs: 0)

    @Test func anUnknownLengthComesFromTheSpareOnceItHasOpened() {
        #expect(nextSongLengthMs(listedMs: 0, spareMs: nil) == 0)
        #expect(nextSongLengthMs(listedMs: 0, spareMs: 214_000) == 214_000)
        #expect(nextSongLengthMs(listedMs: 190_000, spareMs: 214_000) == 214_000)
        #expect(nextSongLengthMs(listedMs: 190_000, spareMs: nil) == 190_000)
        #expect(nextSongLengthMs(listedMs: 0, spareMs: 0) == 0)
        #expect(nextSongLengthMs(listedMs: 190_000, spareMs: 0) == 190_000)
    }

    @Test func aRadioSongWithItsRealLengthBlends() {
        var measured = outside
        measured.durationMs = nextSongLengthMs(listedMs: 0, spareMs: 214_000)
        #expect(crossfadeLength(playing, measured, fadeMs: 6_000, repeatOne: false, stopAtEndOfSong: false) == 6_000)
    }

    @Test func onlyAnUnknownLengthIsWaitedOn() {
        #expect(waitsOnLength(playing, outside, fadeMs: 6_000, repeatOne: false, stopAtEndOfSong: false))
        var known = outside
        known.durationMs = 190_000
        #expect(!waitsOnLength(playing, known, fadeMs: 6_000, repeatOne: false, stopAtEndOfSong: false))
        #expect(!waitsOnLength(playing, outside, fadeMs: 0, repeatOne: false, stopAtEndOfSong: false))
        #expect(!waitsOnLength(playing, outside, fadeMs: 6_000, repeatOne: true, stopAtEndOfSong: false))
        #expect(!waitsOnLength(playing, outside, fadeMs: 6_000, repeatOne: false, stopAtEndOfSong: true))
        var sameAlbum = outside
        sameAlbum.albumId = "a"
        sameAlbum.albumOrder = 4
        #expect(!waitsOnLength(playing, sameAlbum, fadeMs: 6_000, repeatOne: false, stopAtEndOfSong: false))
        #expect(!waitsOnLength(playing, nil, fadeMs: 6_000, repeatOne: false, stopAtEndOfSong: false))
    }

    @Test func anUnknownLengthLoadsFifteenSecondsBeforeTheLongestBlend() {
        #expect(loadLeadMs(blendMs: 0, fadeMs: 6_000, lengthKnown: false) == 21_000)
        #expect(loadLeadMs(blendMs: 6_000, fadeMs: 6_000, lengthKnown: true) == 11_000)
    }
}

/// When a stream has enough to start, by the "Start playing after" setting.
@Suite struct LoadControlTest {
    @Test func aStreamStartsAtTheSetAmountAndNotBefore() {
        #expect(!hasEnoughToStart(bufferedUs: 2_499_000, speed: 1, rebuffering: false, startAfterMs: 2_500))
        #expect(hasEnoughToStart(bufferedUs: 2_500_000, speed: 1, rebuffering: false, startAfterMs: 2_500))
        #expect(hasEnoughToStart(bufferedUs: 250_000, speed: 1, rebuffering: false, startAfterMs: StartAfter.instant.ms))
        #expect(!hasEnoughToStart(bufferedUs: 250_000, speed: 1, rebuffering: false, startAfterMs: StartAfter.short.ms))
    }

    @Test func theWaitIsInPlayingTime() {
        #expect(!hasEnoughToStart(bufferedUs: 1_500_000, speed: 2, rebuffering: false, startAfterMs: 1_000))
        #expect(hasEnoughToStart(bufferedUs: 2_000_000, speed: 2, rebuffering: false, startAfterMs: 1_000))
    }

    @Test func afterRunningDryItWaitsAtLeastTwoSeconds() {
        #expect(!hasEnoughToStart(bufferedUs: 1_000_000, speed: 1, rebuffering: true, startAfterMs: 250))
        #expect(hasEnoughToStart(bufferedUs: 2_000_000, speed: 1, rebuffering: true, startAfterMs: 250))
        #expect(!hasEnoughToStart(bufferedUs: 4_000_000, speed: 1, rebuffering: true, startAfterMs: 5_000))
    }

    @Test func filesOnThePhoneKeepTheirOwnRule() {
        #expect(isLocalScheme("file"))
        #expect(isLocalScheme("ipod-library"))
        #expect(isLocalScheme("FILE"))
        #expect(!isLocalScheme("https"))
        #expect(!isLocalScheme(nil))
    }
}
