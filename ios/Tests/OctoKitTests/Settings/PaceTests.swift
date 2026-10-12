import Foundation
import Testing
@testable import OctoKit

@Suite struct PaceTests {
    @Test func speedsNearADetentSettleOnIt() {
        #expect(Pace.snapSpeed(0.97) == 1)
        #expect(Pace.snapSpeed(1.03) == 1)
        #expect(Pace.snapSpeed(0.72) == 0.75)
        #expect(Pace.snapSpeed(1.28) == 1.25)
        #expect(Pace.snapSpeed(1.46) == 1.5)
    }

    @Test func betweenDetentsTheSpeedMovesInSmallSteps() {
        #expect(Pace.snapSpeed(1.09) == 1.1)
        #expect(Pace.snapSpeed(1.16) == 1.15)
        #expect(Pace.snapSpeed(1.86) == 1.85)
        #expect(Pace.snapSpeed(0.61) == 0.6)
    }

    @Test func speedStaysInsideItsRange() {
        #expect(Pace.snapSpeed(0.1) == 0.5)
        #expect(Pace.snapSpeed(3) == 2)
        #expect(Pace.speedAt(-1) == 0.5)
        #expect(Pace.speedAt(2) == 2)
    }

    @Test func theSliderEndsAreTheSlowestAndFastest() {
        #expect(Pace.speedAt(0) == 0.5)
        #expect(Pace.speedAt(1) == 2)
        #expect(Pace.speedAt(Pace.speedFraction(1)) == 1)
        #expect(abs(Pace.speedFraction(1) - 1.0 / 3.0) < 0.0001)
        for detent in Pace.speedDetents {
            #expect(Pace.speedAt(Pace.speedFraction(detent)) == detent)
        }
    }

    @Test func keepingPitchLeavesItWhereItWas() {
        #expect(Pace.of(speed: 1.5, keepPitch: true, semitones: 0) == Pace(speed: 1.5, pitch: 1))
    }

    @Test func withoutKeepPitchItFollowsTheSpeed() {
        #expect(Pace.of(speed: 1.25, keepPitch: false, semitones: 0) == Pace(speed: 1.25, pitch: 1.25))
    }

    @Test func semitonesShiftThePitchEitherWay() {
        #expect(abs(Pace.of(speed: 1, keepPitch: true, semitones: 6).pitch - 1.4142) < 0.001)
        #expect(abs(Pace.of(speed: 1, keepPitch: true, semitones: -6).pitch - 0.7071) < 0.001)
        #expect(Pace.of(speed: 1, keepPitch: true, semitones: 6) == Pace.of(speed: 1, keepPitch: true, semitones: 9))
        #expect(abs(Pace.of(speed: 1.5, keepPitch: false, semitones: 6).pitch - 1.5 * 1.4142) < 0.001)
    }

    @Test func semitoneSliderSnapsToWholeSteps() {
        #expect(Pace.semitonesAt(0) == -6)
        #expect(Pace.semitonesAt(0.5) == 0)
        #expect(Pace.semitonesAt(1) == 6)
        #expect(Pace.semitonesAt(Pace.semitonesFraction(2)) == 2)
        #expect(Pace.semitonesAt(0.55) == 1)
    }

    @Test func labelsDropTrailingZeros() {
        #expect(Pace.speedLabel(1) == "1x")
        #expect(Pace.speedLabel(2) == "2x")
        #expect(Pace.speedLabel(1.5) == "1.5x")
        #expect(Pace.speedLabel(1.25) == "1.25x")
        #expect(Pace.speedLabel(0.75) == "0.75x")
        #expect(Pace.speedLabel(1.05) == "1.05x")
        #expect(Pace.semitonesLabel(2) == "+2 st")
        #expect(Pace.semitonesLabel(-3) == "-3 st")
        #expect(Pace.semitonesLabel(0) == "0 st")
    }
}

@Suite struct SettingsValuesTests {
    @Test func startAfterChoicesGrowAndTheDefaultIsOneSecond() {
        #expect(StartAfter.allCases.map(\.ms) == [250, 1_000, 2_500, 5_000, 10_000])
        #expect(StartAfter.short.label == "1 second")
        #expect(StreamPrefs().startAfter == .short)
        for words in StartAfter.allCases.map(\.label) + [StartAfter.settingName, StartAfter.help] {
            #expect(!words.contains("\u{2014}") && !words.contains("\u{2013}"))
        }
    }

    @Test func storedNamesReadBackAndUnknownOnesFallBack() {
        #expect(StreamQuality.stored("Kbps320", or: .original) == .mp3(kbps: 320))
        #expect(StreamQuality.stored("Original", or: .mp3(kbps: 128)) == .original)
        #expect(StreamQuality.stored(nil, or: .original) == .original)
        #expect(StreamQuality.stored("Kbps999", or: .original) == .original)
        #expect(RadioDiscovery.stored("MostlyNew", or: .balanced) == .mostlyNew)
        #expect(RadioDiscovery.stored("Nonsense", or: .balanced) == .balanced)
        #expect(BackgroundMode.stored("Colour", or: .immersive) == .color)
        #expect(BackgroundMode.immersive.storedName == "Default")
        #expect(CacheSize.stored("Gb500", or: .gb2) == .gb2)
        #expect(SendPlays.stored("Sometimes", or: .all) == .all)
    }

    @Test func sizesAndLabels() {
        #expect(CacheSize.allCases.map(\.label) == ["Off", "1 GB", "2 GB", "5 GB", "10 GB"])
        #expect(CacheSize.gb2.bytes == 2 * 1_073_741_824)
        #expect(StreamQuality.allCases.map(\.label) == ["Original", "320 kbps", "256 kbps", "192 kbps", "128 kbps"])
        #expect(StreamQuality.mp3(kbps: 320).downloadLabel == "320 kbps MP3")
        #expect(StreamQuality.original.downloadLabel == "Original")
    }

    @Test func radioTuningAsksForMoreWhenMostlyOutside() {
        #expect(RadioTuning().suggestions == 50)
        #expect(RadioTuning(discovery: .lots).suggestions == 100)
        #expect(RadioTuning(discovery: .mostlyNew).suggestions == 100)
        #expect(RadioDiscovery.allCases.map(\.share) == [0, 0.15, 0.35, 0.6, 0.85])
    }

    @Test func playerDefaultsAreWhatANewInstallGets() {
        let prefs = PlayerPrefs()
        #expect(!prefs.crossfade && prefs.crossfadeSeconds == 8 && prefs.smartTransitions && prefs.filterSweeps && !prefs.matchTempo)
        #expect(prefs.speed == 1 && prefs.keepPitch && prefs.pitchSemitones == 0 && prefs.paceIsDefault)
        #expect(!prefs.skipSilence && prefs.autoplay)
        #expect(prefs.radioDiscovery == .balanced && prefs.radioAdventure == .balanced && prefs.radioVariety == .normal && !prefs.radioFavorites)
        #expect(!prefs.resumeWired && !prefs.resumeBluetooth && !prefs.resumeAlways)
        #expect(prefs.castRenderers && !prefs.castKeepPlaying && !prefs.libraryOnly && !prefs.reduceMotion && prefs.liveBackground)
        #expect(prefs.crossfadeMs == 0)
    }

    @Test func saneHoldsValuesToTheirRanges() {
        var prefs = PlayerPrefs()
        prefs.crossfadeSeconds = 40
        prefs.speed = 1.16
        prefs.pitchSemitones = -9
        prefs.background.fps = 45
        prefs.background.contrast = 3
        prefs.background.brightnessCap = 5
        let held = prefs.sane()
        #expect(held.crossfadeSeconds == 16)
        #expect(held.speed == 1.15)
        #expect(held.pitchSemitones == -6)
        #expect(held.background.fps == 60)
        #expect(held.background.contrast == 2)
        #expect(held.background.brightnessCap == 20)
    }

    @Test func savedPlayerSettingsReadWithDefaultsForWhatIsMissing() throws {
        let json = #"{"crossfade": true, "radioDiscovery": "Nonsense", "background": {"mode": "Colour"}, "ambient": {"strength": "Wild"}}"#
        let prefs = try JSONDecoder().decode(PlayerPrefs.self, from: Data(json.utf8))
        #expect(prefs.crossfade)
        #expect(prefs.crossfadeSeconds == 8)
        #expect(prefs.radioDiscovery == .balanced)
        #expect(prefs.background.mode == .color)
        #expect(prefs.background.saturation == 180)
        #expect(prefs.ambient.strength == .subtle)
        let stream = try JSONDecoder().decode(StreamPrefs.self, from: Data(#"{"copies": "Nonsense", "wifi": "Kbps256"}"#.utf8))
        #expect(stream.copies == .phoneFirst)
        #expect(stream.wifi == .mp3(kbps: 256))
        #expect(stream.mobile == .original)
    }

    @Test func ambientAreasFollowTheStrength() {
        var prefs = AmbientPrefs()
        #expect(prefs.shows(.home) && prefs.tintsBar)
        prefs.home = false
        #expect(!prefs.shows(.home) && prefs.shows(.library))
        prefs.strength = .off
        #expect(!prefs.shows(.library) && !prefs.tintsBar)
        #expect(AmbientStrength.subtle.glowAlpha == 0.14 && AmbientStrength.rich.barTintAlpha == 0.10)
    }

    @Test func listenBrainzStates() {
        #expect(!ListenBrainzPrefs().connected)
        #expect(ListenBrainzPrefs(enabled: true, user: "me").sends)
        #expect(!ListenBrainzPrefs(enabled: true, user: "me", needsAttention: true).sends)
        #expect(ListenBrainzPrefs(enabled: true, user: "me", needsAttention: true).keepsPlays)
    }
}

@Suite struct OutputTimingTests {
    @Test func automaticTimingDependsOnBluetooth() {
        #expect(LyricsOutputTiming.automatic("bluetooth:Pods") == -500)
        #expect(LyricsOutputTiming.automatic("speaker") == -300)
        #expect(LyricsOutputTiming.about("bluetooth:Pods", automatic: true)
            == "Every song on this output. Automatic: 0.5 s earlier, the usual for Bluetooth.")
        #expect(LyricsOutputTiming.about("wired", automatic: true)
            == "Every song on this output. Automatic: 0.3 s earlier, the usual for a speaker or a cable.")
        #expect(LyricsOutputTiming.about("wired", automatic: false) == "Every song on this output.")
    }

    @Test func timingsReadAsSignedSeconds() {
        #expect(LyricsOutputTiming.signed(0) == "0 s")
        #expect(LyricsOutputTiming.signed(750) == "+0.75 s")
        #expect(LyricsOutputTiming.signed(-300) == "-0.3 s")
        #expect(LyricsOutputTiming.signed(-1_500) == "-1.5 s")
        #expect(LyricsOutputTiming.signed(2_000) == "+2 s")
        #expect(LyricsOutputTiming.label(0) == "In time")
        #expect(LyricsOutputTiming.label(250) == "0.25 s later")
    }

    @Test func stepsStopAtTheLimit() {
        #expect(LyricsOutputTiming.step(0, steps: 1) == 50)
        #expect(LyricsOutputTiming.step(1_980, steps: 1) == 2_000)
        #expect(LyricsOutputTiming.step(-2_000, steps: -1) == -2_000)
    }
}
