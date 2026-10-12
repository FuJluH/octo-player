import Foundation
import Testing
@testable import OctoKit

private func rgb(_ r: Int, _ g: Int, _ b: Int) -> UInt32 { 0xFF00_0000 | UInt32(r) << 16 | UInt32(g) << 8 | UInt32(b) }
private func channels(_ argb: UInt32) -> [Int] { [Int((argb >> 16) & 0xFF), Int((argb >> 8) & 0xFF), Int(argb & 0xFF)] }
private func washNear(_ a: Float, _ b: Float, _ within: Float) -> Bool { abs(a - b) <= within }
private func washNear(_ a: Double, _ b: Double, _ within: Double) -> Bool { abs(a - b) <= within }

private let frame60 = 16_666_667

/// A cover the swap tests can tell apart by name.
private final class Picture {
    let name: String
    init(_ name: String) { self.name = name }
}

@Suite struct WashClockTest {
    @Test func framesAreDrawnOnlyAsOftenAsTheLimitAllows() {
        let clock = WashClock(30)
        clock.start(0)
        var drawn = 0
        for i in 1...60 where clock.tick(i * frame60, target: 30, bpm: BaseBpm, speed: 1, moving: true) { drawn += 1 }
        #expect(drawn == 30)
    }

    @Test func theDriftDoesNotDependOnTheFrameRate() {
        let slow = WashClock(30)
        slow.start(0)
        let quick = WashClock(60)
        quick.start(0)
        for i in 1...120 {
            _ = slow.tick(i * frame60, target: 30, bpm: BaseBpm, speed: 0.25, moving: true)
            _ = quick.tick(i * frame60, target: 60, bpm: BaseBpm, speed: 0.25, moving: true)
        }
        #expect(washNear(quick.motion.time, slow.motion.time, 1e-3))
        #expect(quick.motion.time > 0)
    }

    @Test func betweenFramesTheClockRestsUntilNearlyDue() {
        let clock = WashClock(30)
        clock.start(0)
        #expect(clock.tick(2 * frame60, target: 30, bpm: BaseBpm, speed: 1, moving: true))
        #expect(clock.restNanos(2 * frame60) == 26_666_666 - RestMarginNanos)
        let woken = 2 * frame60 + clock.restNanos(2 * frame60)
        #expect(woken > 3 * frame60 && woken < 4 * frame60)
        #expect(clock.tick(4 * frame60, target: 30, bpm: BaseBpm, speed: 1, moving: true))
        let quick = WashClock(60)
        quick.start(0)
        _ = quick.tick(frame60, target: 60, bpm: BaseBpm, speed: 1, moving: true)
        #expect(quick.restNanos(frame60) < frame60 - RestMarginNanos)
        #expect(clock.restNanos(10 * frame60) == 0)
    }

    @Test func heldStillOnlyTheCoverFadeRuns() {
        let clock = WashClock(60)
        clock.fade.start(0)
        clock.fade.start(10_000)
        #expect(clock.busy(false))
        clock.start(0)
        for i in 1...40 { _ = clock.tick(i * frame60, target: 60, bpm: BaseBpm, speed: 1, moving: false) }
        #expect(clock.motion.time == 0)
        #expect(!clock.fade.running)
        #expect(!clock.busy(false))
    }

    @Test func hiddenKeepsTheLastLimitRatherThanStopping() {
        let clock = WashClock(60)
        clock.start(0)
        _ = clock.tick(frame60, target: 0, bpm: BaseBpm, speed: 1, moving: true)
        #expect(clock.rate.limit == 60)
    }

    @Test func aCoverArrivingMidFadeStartsFromWhatShows() {
        let fade = CoverFade()
        let swap = CoverSwap<Picture>()
        let blend = { (old: Picture, new: Picture, mix: Float) in Picture("\(old.name)+\(new.name)@\(Int(mix * 100))") }
        let first = swap.arrive(Picture("a"), fade, 0, blend: blend)
        #expect(first.from.name == "a" && first.to.name == "a")
        let second = swap.arrive(Picture("b"), fade, 10_000, blend: blend)
        #expect(second.from.name == "a" && second.to.name == "b")
        fade.advance(50)
        let mix = fade.mix
        let third = swap.arrive(Picture("c"), fade, 10_050, blend: blend)
        #expect(third.from.name == "a+b@\(Int(mix * 100))" && third.to.name == "c")
        fade.advance(1_000)
        let d = Picture("d")
        let fourth = swap.arrive(d, fade, 20_000, blend: blend)
        #expect(fourth.from.name == "c" && fourth.to.name == "d")
        #expect(swap.new === d)
    }

    @Test func theDollyRunsFromNinetyPercentToFull() {
        #expect(washNear(dollyScale(0), 0.9, 1e-6))
        #expect(washNear(dollyScale(0.5), 0.95, 1e-6))
        #expect(washNear(dollyScale(1), 1, 1e-6))
    }
}

@Suite struct WashColorTest {
    @Test func contrastPushesChannelsAwayFromTheMiddle() {
        let only = washColorMatrix(WashTuning(contrast: 1.3, saturation: 1, brightnessCap: 1))
        #expect(channels(applyColorMatrix(rgb(200, 100, 50), only)) == [222, 92, 27])
        #expect(channels(applyColorMatrix(rgb(128, 250, 10), only)) == [128, 255, 0])
    }

    @Test func saturationMixesAwayFromGray() {
        let only = washColorMatrix(WashTuning(contrast: 1, saturation: 1.8, brightnessCap: 1))
        #expect(channels(applyColorMatrix(rgb(200, 100, 50), only)) == [255, 81, 0])
        #expect(channels(applyColorMatrix(rgb(90, 90, 90), only)) == [90, 90, 90])
        let none = washColorMatrix(WashTuning(contrast: 1, saturation: 0, brightnessCap: 1))
        #expect(channels(applyColorMatrix(rgb(200, 100, 50), none)) == [124, 124, 124])
    }

    @Test func theOneMatrixIsContrastThenSaturation() {
        let matrix = washColorMatrix(WashTuning())
        let (r, g, b): (Float, Float, Float) = (150, 110, 90)
        func contrast(_ c: Float) -> Float { (c / 255 - 0.5) * 1.3 * 255 + 127.5 }
        let cr = contrast(r)
        let cg = contrast(g)
        let cb = contrast(b)
        let gray = 0.299 * cr + 0.587 * cg + 0.114 * cb
        let expected = [cr, cg, cb].map { gray + 1.8 * ($0 - gray) }
        let actual = (0...2).map { row in matrix[row * 5] * r + matrix[row * 5 + 1] * g + matrix[row * 5 + 2] * b + matrix[row * 5 + 4] }
        for (e, a) in zip(expected, actual) { #expect(washNear(e, a, 0.01)) }
        #expect(Array(matrix.dropFirst(15)) == [0, 0, 0, 1, 0])
    }

    @Test func theBrightnessCapDarkensByHowFarOverItIs() {
        #expect(channels(capBrightness(rgb(200, 200, 200), 0.5)) == [86, 86, 86])
        #expect(capBrightness(rgb(100, 100, 100), 0.5) == rgb(100, 100, 100))
        #expect(capBrightness(rgb(250, 10, 10), 0.5) == rgb(250, 10, 10))
        #expect(channels(capBrightness(rgb(255, 255, 255), 0.5)) == [0, 0, 0])
        #expect(capBrightness(rgb(255, 255, 255), 1) == rgb(255, 255, 255))
    }

    @Test func theCapRunsOverAWholePicture() {
        var pixels = [rgb(200, 200, 200), rgb(100, 100, 100)]
        capBrightness(&pixels, 0.5)
        #expect(channels(pixels[0]) == [86, 86, 86])
        #expect(pixels[1] == rgb(100, 100, 100))
    }

    @Test func capKeepsAlpha() {
        let half: UInt32 = 0x80 << 24 | 200 << 16 | 200 << 8 | 200
        #expect(capBrightness(half, 0.5) >> 24 == 0x80)
    }

    @Test func contrastAgainstWhite() {
        #expect(washNear(contrastRatio(rgb(0, 0, 0), rgb(255, 255, 255)), 21, 0.01))
        #expect(washNear(contrastRatio(rgb(255, 255, 255), rgb(255, 255, 255)), 1, 0.001))
        #expect(washNear(relativeLuminance(rgb(255, 255, 255)), 1, 0.0001))
        #expect(washNear(relativeLuminance(rgb(128, 128, 128)), 0.2159, 0.001))
    }

    @Test func theLightTestNeedsBothHalves() {
        #expect(!washIsLight(rgb(140, 140, 140)))
        #expect(washIsLight(rgb(200, 200, 200)))
    }
}

@Suite struct WashFadeTest {
    @Test func theFirstCoverShowsAtOnce() {
        #expect(coverFadeMs(nil, 5_000) == 0)
    }

    @Test func skippingFadesQuicker() {
        #expect(coverFadeMs(1_000, 1_800) == 300)
        #expect(coverFadeMs(1_000, 2_499) == 300)
        #expect(coverFadeMs(1_000, 2_500) == 500)
        #expect(coverFadeMs(1_000, 60_000) == 500)
    }

    @Test func easeInOutCubicIsSlowAtBothEnds() {
        #expect(easeInOutCubic(0) == 0)
        #expect(washNear(easeInOutCubic(0.25), 0.0625, 1e-6))
        #expect(washNear(easeInOutCubic(0.5), 0.5, 1e-6))
        #expect(washNear(easeInOutCubic(0.75), 0.9375, 1e-6))
        #expect(easeInOutCubic(1) == 1)
        #expect(easeInOutCubic(-1) == 0)
        #expect(easeInOutCubic(2) == 1)
        for i in 0...100 {
            let x = Float(i) / 100
            #expect(washNear(1 - easeInOutCubic(x), easeInOutCubic(1 - x), 1e-5))
            if i > 0 { #expect(easeInOutCubic(x) >= easeInOutCubic(x - 0.01)) }
        }
    }

    @Test func aFadeRunsItsLengthOnTheClock() {
        let fade = CoverFade()
        #expect(fade.start(1_000) == 0)
        #expect(!fade.running)
        #expect(fade.mix == 1)
        #expect(fade.start(10_000) == 500)
        #expect(fade.running)
        #expect(fade.mix == 0)
        fade.advance(250)
        #expect(washNear(fade.mix, 0.5, 1e-6))
        fade.advance(250)
        #expect(!fade.running)
        #expect(fade.start(10_900) == 300)
        fade.advance(75)
        #expect(washNear(fade.mix, easeInOutCubic(0.25), 1e-6))
        fade.advance(225)
        #expect(fade.mix == 1)
    }
}

@Suite struct WashLayersTest {
    /// The copies table written out as its formulas: offset across, offset down and turn at time t
    /// and rotation r.
    private struct Row {
        let name: String
        let opacity: Float
        let zoom: Float
        let breathes: Bool
        let x: (Float) -> Float
        let y: (Float) -> Float
        let turn: (Float, Float) -> Float
    }

    private let table: [Row] = [
        Row(name: "Base", opacity: 1.0, zoom: 3.0, breathes: false, x: { _ in 0 }, y: { _ in 0 }, turn: { _, _ in 0 }),
        Row(name: "Parallax 1", opacity: 0.60, zoom: 3.0, breathes: true, x: { 0.10 + 0.08 * sin(0.25 * $0) },
            y: { 0.10 + 0.06 * cos(0.25 * $0) }, turn: { _, r in 0.5 * r }),
        Row(name: "Parallax 2", opacity: 0.30, zoom: 3.8, breathes: true, x: { 0.25 + 0.08 * sin(0.25 * $0 + 2.4) },
            y: { 0.25 + 0.06 * cos(0.25 * $0 + 2.4) }, turn: { _, r in 0.5 * r + 0.15 }),
        Row(name: "Parallax 3", opacity: 0.20, zoom: 4.6, breathes: true, x: { 0.40 + 0.08 * sin(0.25 * $0 + 4.8) },
            y: { 0.40 + 0.06 * cos(0.25 * $0 + 4.8) }, turn: { _, r in 0.5 * r + 0.30 }),
        Row(name: "Primary", opacity: 0.85, zoom: 2.4, breathes: true, x: { 0.05 * sin(0.5 * $0) },
            y: { 0.04 * cos(0.5 * $0) }, turn: { t, r in r + 0.02 * sin(0.5 * t) }),
        Row(name: "Secondary", opacity: 0.70, zoom: 2.0, breathes: true, x: { 0.30 + 0.06 * sin(0.5 * $0 + 1) },
            y: { 0.30 + 0.05 * cos(0.5 * $0 + 1) }, turn: { t, r in -0.5 * r + 0.02 * sin(0.7 * t + 1) }),
        Row(name: "Tertiary", opacity: 0.55, zoom: 1.8, breathes: true, x: { -0.20 + 0.07 * sin(0.4 * $0) },
            y: { 0.40 + 0.05 * cos(0.3 * $0) }, turn: { t, r in 0.8 * r + 0.02 * sin(0.8 * t + 2) }),
        Row(name: "Fourth", opacity: 0.40, zoom: 2.2, breathes: true, x: { 0.40 + 0.08 * sin(0.35 * $0 + 3) },
            y: { -0.10 + 0.06 * cos(0.25 * $0 + 3) }, turn: { t, r in 1.5 * r + 0.02 * sin(0.6 * t + 3) }),
    ]

    @Test func theCopiesMatchTheTable() {
        #expect(table.map(\.name) == WashCopies.map(\.name))
        for (row, copy) in zip(table, WashCopies) {
            #expect(row.opacity == copy.opacity)
            #expect(row.zoom == copy.zoom)
            #expect(row.breathes == copy.breathes)
            for t: Float in [0, 1.3, 7.7, 42, 100] {
                for r: Float in [-5, 0, 0.6, 6] {
                    #expect(washNear(row.x(t), copy.offsetX(t), 1e-3), "\(row.name) x at \(t)")
                    #expect(washNear(row.y(t), copy.offsetY(t), 1e-3), "\(row.name) y at \(t)")
                    #expect(washNear(row.turn(t, r), copy.angle(t, r), 1e-5), "\(row.name) turn at \(t), \(r)")
                }
            }
        }
    }

    @Test func theParallaxPhasesStepByTheGoldenAngle() {
        let phases = WashCopies.filter { $0.name.hasPrefix("Parallax") }.map(\.xPhase)
        #expect(phases == [0, 2.39996, 4.79992])
    }

    @Test func breathingMagnifiesEveryCopyButTheBase() {
        #expect(WashCopies[0].magnification(1.1) == 3)
        #expect(washNear(WashCopies[4].magnification(1.1), 2.4 * 1.1, 1e-6))
    }

    @Test func offsetComesBeforeZoomAndTurnAboutTheCenter() {
        let base = WashCopies[0]
        let (u, v) = copySample(base, 0, 0, 1, 0.5, 0.5)
        #expect(washNear(u, 0.5, 1e-6) && washNear(v, 0.5, 1e-6))
        let (u2, _) = copySample(base, 0, 0, 1, 0.8, 0.5)
        #expect(washNear(u2, 0.6, 1e-6))
        let p1 = WashCopies[1]
        let r: Float = 0.4
        let (u3, v3) = copySample(p1, 0, r, 1, 0.5, 0.5)
        let a = 0.5 * r
        #expect(washNear(u3, 0.5 + (cos(a) * 0.1 - sin(a) * 0.16) / 3, 1e-5))
        #expect(washNear(v3, 0.5 + (sin(a) * 0.1 + cos(a) * 0.16) / 3, 1e-5))
    }

    @Test func theWarpNumbers() {
        #expect(washNear(WarpAmplitude, 0.17578, 1e-5))
        for (a, b) in zip(WarpScales, [Float(0.0175), 0.0105, 0.021]) { #expect(washNear(a, b, 1e-6)) }
        #expect(WarpRest == [0.25, 0.5, 0.75])
    }

    @Test func dividersAtRestLeaveThePictureAlone() {
        let rest: [Float] = [0.25, 0.5, 0.75]
        for i in 0...100 {
            let x = Float(i) / 100
            #expect(washNear(warpX(x, rest), x, 1e-6))
        }
    }

    @Test func theDividersStayInOrderWithRoomBetween() {
        var tightest: Float = 1
        for y in stride(from: 0, to: 512, by: 7) {
            for r: Float in [-6.2, -2, 0, 0.7, 3, 6.2] {
                for p in 0..<63 {
                    let d = warpDividers(Float(y), r, Float(p) / 10)
                    let gaps = [d[0], d[1] - d[0], d[2] - d[1], 1 - d[2]]
                    for gap in gaps where gap < WarpMinBand - 1e-6 { Issue.record("gap \(gap) at \(y), \(r), \(p)") }
                    tightest = min(tightest, gaps.min() ?? 1)
                }
            }
        }
        #expect(washNear(tightest, WarpMinBand, 1e-4))
    }

    @Test func theRemapIsMonotonicAndCoversTheWidth() {
        for y: Float in [0, 100, 311, 511] {
            for p: Float in [0, 1, 2.5, 4, 5.5] {
                let d = warpDividers(y, 5, p)
                #expect(washNear(warpX(0, d), 0, 1e-6))
                #expect(washNear(warpX(1, d), 1, 1e-5))
                var last: Float = -1
                for i in 0...1000 {
                    let sx = warpX(Float(i) / 1000, d)
                    if sx < last - 1e-6 { Issue.record("not monotonic at \(i)") }
                    last = sx
                }
                #expect(washNear(warpX(d[0], d), 0.25, 1e-5))
                #expect(washNear(warpX(d[1], d), 0.5, 1e-5))
                #expect(washNear(warpX(d[2], d), 0.75, 1e-5))
            }
        }
    }
}

@Suite struct WashMotionTest {
    private let twoPi = Float.pi * 2

    @Test func kScalesByTempoAndFrameLimit() {
        #expect(washNear(frameFactor(120, 60), 1, 1e-6))
        #expect(washNear(frameFactor(60, 60), 0.5, 1e-6))
        #expect(washNear(frameFactor(120, 30), 2, 1e-6))
        #expect(washNear(frameFactor(120, 120), 0.5, 1e-6))
    }

    @Test func aSixtyBpmSongDriftsAtHalfTheSpeed() {
        let slow = WashMotion()
        let quick = WashMotion()
        for _ in 0..<60 {
            slow.step(frameFactor(60, 60), 60, 1 / 60)
            quick.step(frameFactor(120, 60), 120, 1 / 60)
        }
        #expect(washNear(quick.time, 0.96, 1e-4))
        #expect(washNear(slow.time, quick.time / 2, 1e-4))
    }

    @Test func theSpeedDoesNotDependOnTheFrameRate() {
        let sixty = WashMotion()
        let thirty = WashMotion()
        for _ in 0..<60 { sixty.step(frameFactor(120, 60), 120, 1 / 60) }
        for _ in 0..<30 { thirty.step(frameFactor(120, 30), 120, 1 / 30) }
        #expect(washNear(sixty.time, thirty.time, 1e-4))
        #expect(washNear(sixty.turn, thirty.turn, 1e-4))
    }

    @Test func theWarpRipplesFasterOnQuickSongsButNeverSlower() {
        func warpAfterASecond(_ bpm: Float) -> Float {
            let motion = WashMotion()
            for _ in 0..<60 { motion.step(frameFactor(bpm, 60), bpm, 1 / 60) }
            return motion.warpPhase
        }
        #expect(washNear(warpAfterASecond(60), 0.48, 1e-4))
        #expect(washNear(warpAfterASecond(120), 0.96, 1e-4))
        #expect(washNear(warpAfterASecond(240), 3.84, 1e-3))
    }

    @Test func theRotationTurnsBackPastAFullTurnEitherWay() {
        let motion = WashMotion()
        #expect(motion.direction == 1)
        var frames = 0
        while motion.direction > 0 && frames < 100_000 {
            motion.step(1, 120, 1 / 60)
            frames += 1
        }
        #expect(motion.rotation > twoPi)
        let seconds = Float(frames) / 60
        #expect((90...110).contains(seconds), "\(seconds) s")
        while motion.direction < 0 && frames < 100_000 {
            motion.step(1, 120, 1 / 60)
            frames += 1
        }
        #expect(motion.rotation < -twoPi)
        #expect(motion.direction == 1)
    }

    @Test func theRotationIsAboutSixHundredthsOfARadianASecond() {
        let motion = WashMotion()
        for _ in 0..<60 { motion.step(1, 120, 1 / 60) }
        #expect(washNear(motion.rotation, 0.06, 0.001))
    }

    @Test func breathingStaysBetweenPointNineAndOnePointOne() {
        let motion = WashMotion()
        var low: Float = 2
        var high: Float = 0
        for _ in 0..<20_000 {
            motion.step(40, 120, 0)
            low = min(low, motion.breathing)
            high = max(high, motion.breathing)
        }
        #expect(washNear(low, 0.9, 0.001))
        #expect(washNear(high, 1.1, 0.001))
    }

    @Test func breathingIsAVerySlowSwell() {
        let motion = WashMotion()
        for _ in 0..<60 { motion.step(1, 120, 1 / 60) }
        #expect(washNear(motion.breathPhase, 60 * 0.016 / 120, 1e-6))
    }

    @Test func theFinalPassTurnsOnceInAboutFiftyTwoSeconds() {
        let motion = WashMotion()
        var frames = 0
        var last: Float = 0
        while frames < 10_000 {
            motion.step(frameFactor(120, 60), 120, 1 / 60)
            frames += 1
            if motion.turn < last { break }
            last = motion.turn
        }
        #expect(washNear(Float(frames) / 60, 52.36, 0.1))
    }

    @Test func aPulseBoostsTheRotationAndFades() {
        let motion = WashMotion()
        #expect(motion.pulseBoost == 1)
        motion.beat()
        #expect(motion.pulseBoost == 3)
        motion.step(1, 120, 1)
        #expect(washNear(motion.pulseBoost, 2, 1e-6))
        for _ in 0..<10 { motion.beat() }
        #expect(motion.pulseBoost == 10)
    }

    @Test func theFrameRateFollowsWhereTheBackgroundIs() {
        #expect(targetFps(.focused, 60, powerSave: false) == 60)
        #expect(targetFps(.focused, 60, powerSave: true) == 30)
        #expect(targetFps(.focused, 30, powerSave: true) == 30)
        #expect(targetFps(.focused, 120, powerSave: false) == 120)
        #expect(targetFps(.unfocused, 60, powerSave: false) == 10)
        #expect(targetFps(.hidden, 60, powerSave: false) == 0)
    }

    @Test func rateChangesEaseInByEightPercentAFrame() {
        let rate = FrameRate(60)
        #expect(washNear(rate.ease(10), 56, 1e-4))
        #expect(washNear(rate.ease(10), 56 + (10 - 56) * 0.08, 1e-4))
        for _ in 0..<200 { rate.ease(10) }
        #expect(rate.limit == 10)
        #expect(rate.ease(0) == 10)
    }

    @Test func framesAreDrawnOnlyWhenDue() {
        let sixtieth = 16_666_667
        #expect(frameDue(sixtieth, 60))
        #expect(frameDue(sixtieth - 1_000_000, 60))
        #expect(!frameDue(sixtieth / 2, 60))
        #expect(!frameDue(sixtieth * 4, 0))
        #expect(washNear(framesElapsed(sixtieth, 60), 1, 0.001))
        #expect(framesElapsed(5_000_000_000, 60) == 3)
    }

    @Test func theSongsTempoIsUsedWhenWanted() {
        #expect(paceBpm(90, useBpm: true) == 90)
        #expect(paceBpm(90, useBpm: false) == 120)
        #expect(paceBpm(nil, useBpm: true) == 120)
        #expect(paceBpm(0, useBpm: true) == 120)
        #expect(paceBpm(999, useBpm: true) == 240)
    }
}

@Suite struct WashReadingTest {
    private let page = rgb(0x0C, 0x0C, 0x0D)
    private let accent = rgb(0x97, 0xB1, 0xB9)
    private let white = rgb(255, 255, 255)

    private func prepared(_ argb: UInt32, _ tuning: WashTuning = WashTuning()) -> [UInt32] {
        [UInt32](repeating: prepareColor(argb, tuning), count: 64 * 64)
    }

    @Test func thePeakIsTheBrightestFewAsTheFinalPassLeavesThem() {
        let pixels = (0..<1000).map { $0 % 20 == 0 ? rgb(0, 200, 0) : rgb(0, 0, 0) }
        let peak = washPeak(pixels, step: 1)
        #expect(washNear(Float(Int(200 * FinalGain)), Float((peak >> 8) & 0xFF), 1))
        let speck = (0..<1000).map { $0 == 500 ? rgb(255, 255, 255) : rgb(10, 10, 10) }
        #expect(washPeak(speck, step: 1) == rgb(9, 9, 9))
    }

    @Test func aDarkCoverShowsAsMuchAsAsked() {
        let navy = washPeak(prepared(rgb(0x10, 0x18, 0x30)))
        #expect(washNear(readableAlpha(navy, page, accent, 4.5, 0.9), 0.9, 1e-6))
    }

    @Test func aBrightCoverShowsFainterSoTheWordsStillRead() {
        for cover in [rgb(255, 224, 0), rgb(0, 255, 0), rgb(0xF4, 0xEE, 0xDC), rgb(255, 255, 255), rgb(0, 255, 255)] {
            let peak = washPeak(prepared(cover))
            let alpha = readableAlpha(peak, page, accent, 4.5, 0.9)
            let behind = overlay(peak, alpha, page)
            #expect(contrastRatio(accent, behind) >= 4.5)
            #expect(contrastRatio(white, behind) >= 7)
            if alpha < 0.9 { #expect(contrastRatio(accent, overlay(peak, alpha + 0.02, page)) < 4.5) }
        }
        #expect(readableAlpha(washPeak(prepared(rgb(255, 224, 0))), page, accent, 4.5, 0.9) > 0.25)
    }

    @Test func overlayMixesChannelByChannel() {
        #expect(overlay(white, 0, page) == page)
        #expect(overlay(white, 1, page) == white)
        #expect(overlay(white, 0.5, page) == rgb(134, 134, 134))
    }

    /// A 512 square, prepared, of `ground` with a disc of `shape` in the middle a third across.
    private func square(_ ground: UInt32, _ shape: UInt32, _ tuning: WashTuning = WashTuning()) -> [UInt32] {
        let g = prepareColor(ground, tuning)
        let s = prepareColor(shape, tuning)
        return (0..<(512 * 512)).map { i in
            let x = i % 512 - 256
            let y = i / 512 - 256
            return x * x + y * y < 90 * 90 ? s : g
        }
    }

    private func worst(_ ink: WashInk, _ range: WashRange) -> Double {
        let words = ink.dark ? DarkInkArgb : white
        return min(contrastRatio(words, overlay(range.low, ink.show, page)), contrastRatio(words, overlay(range.high, ink.show, page)))
    }

    @Test func theRangeIsTheDarkestAndBrightestPatch() {
        let range = washRange(square(rgb(0x3A, 0xA6, 0xA0), rgb(0x1B, 0x2A, 0x4A)), 512)
        #expect(relativeLuminance(range.high) > 0.3)
        #expect(relativeLuminance(range.low) < 0.05)
        let speck = (0..<(512 * 512)).map { $0 == 1000 ? white : rgb(10, 10, 10) }
        #expect(washRange(speck, 512).high == rgb(10, 10, 10))
        #expect(WashRange.of(rgb(200, 200, 200), rgb(1, 2, 3)) == WashRange(rgb(1, 2, 3), rgb(200, 200, 200)))
    }

    @Test func aCoverLightInPlacesAndDarkInOthersGetsWhiteWordsAndADim() {
        let range = washRange(square(rgb(0x3A, 0xA6, 0xA0), rgb(0x1B, 0x2A, 0x4A)), 512).scaled(FinalGain)
        let ink = inkOver(range, page)
        #expect(!ink.dark)
        #expect(ink.show < 1)
        #expect(worst(ink, range) >= 4.5)
    }

    @Test func everyCoverReadsWhicheverWordsItGets() {
        let covers = [
            (rgb(0x10, 0x18, 0x30), rgb(0x8A, 0x1C, 0x3C)),
            (rgb(0x3A, 0xA6, 0xA0), rgb(0x1B, 0x2A, 0x4A)),
            (rgb(0xFF, 0xE0, 0x00), rgb(0xFF, 0x8A, 0x00)),
            (rgb(0xFF, 0xFF, 0xFF), rgb(0xF2, 0xEA, 0xD8)),
            (rgb(0x00, 0xFF, 0x40), rgb(0xB0, 0xFF, 0x00)),
        ]
        for tuning in [WashTuning(), WashTuning(brightnessCap: 1), WashTuning(contrast: 2, saturation: 3, brightnessCap: 1)] {
            for (ground, shape) in covers {
                let range = washRange(square(ground, shape, tuning), 512).scaled(FinalGain)
                let ink = inkOver(range, page)
                #expect(worst(ink, range) >= 4.5, "\(String(ground, radix: 16)) at \(tuning): \(ink)")
            }
        }
    }

    @Test func wordsGoDarkOverAWashLightAllOver() {
        let range = washRange(square(rgb(0xF4, 0xEE, 0xDC), rgb(0xF2, 0xEA, 0xD8), WashTuning(contrast: 1, saturation: 1, brightnessCap: 1)), 512)
        #expect(inkOver(range, page) == WashInk(dark: true, show: 1))
        #expect(inkOver(WashRange.of(rgb(0x10, 0x18, 0x30), rgb(0x40, 0x10, 0x20)), page) == WashInk(dark: false, show: 1))
    }

    @Test func theChoices() {
        #expect(FpsChoices == [30, 60, 90, 120])
        #expect(BrightnessCapRange == 20...100)
        #expect(SpeedRange == 5...100)
    }
}

@Suite struct WashShadersTest {
    @Test func theBlurTaps() {
        #expect(BlurTaps.count == 9)
        #expect(washNear(BlurStepAcross, 0.9, 1e-6))
        #expect(washNear(BlurStepDown, 1.2, 1e-6))
        #expect(washNear(BlurPassGain, 0.8743, 1e-4))
    }

    @Test func thePlatformBlurMatchesTheTapsSpread() {
        #expect(washNear(BlurSigmaTaps, 3.44, 0.01))
        #expect(washNear(blurSigmaTexels(BlurStepAcross), 4.38, 0.01))
        #expect(washNear(blurSigmaTexels(BlurStepDown), 5.84, 0.01))
        let across = blurRadiusFor(blurSigmaTexels(BlurStepAcross))
        let down = blurRadiusFor(blurSigmaTexels(BlurStepDown))
        #expect(washNear(across, 6.72, 0.02))
        #expect(washNear(down, 9.25, 0.02))
        #expect(washNear(0.57735 * across + 0.5, blurSigmaTexels(BlurStepAcross), 1e-4))
        #expect(blurRadiusFor(0.2) == 0)
        #expect(washNear(blurSigmaFor(across), blurSigmaTexels(BlurStepAcross), 1e-4))
    }

    @Test func theFinalGainCarriesTheBlursDimming() {
        let four = BlurPassGain * BlurPassGain * BlurPassGain * BlurPassGain
        #expect(washNear(FinalGain, 1.5 * four, 1e-6))
        #expect(washNear(FinalGain, 0.876, 0.001))
    }

    @Test func theWashBlurIsWidenedOnThePhone() {
        #expect(washNear(WashBlurSigmaAcross, blurSigmaFor(blurRadiusFor(blurSigmaTexels(BlurStepAcross)) * 2.5), 1e-5))
        #expect(WashBlurSigmaDown > WashBlurSigmaAcross)
    }
}
