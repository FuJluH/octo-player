import Foundation
import Testing
@testable import OctoKit

@Suite struct LyricsTimingTest {
    let lines = [
        LyricLine(startMs: 0, text: ""),
        LyricLine(startMs: 10_000, text: "first"),
        LyricLine(startMs: 20_000, text: "second"),
    ]

    @Test func noOffsetChangesNothing() {
        #expect(lyricsClock(12_345, 0) == 12_345)
        #expect(heardAt(10_000, 0) == 10_000)
    }

    @Test func laterWordsLightUpLater() {
        #expect(lines.lineAt(lyricsClock(10_250, 500)) == 0)
        #expect(lines.lineAt(lyricsClock(10_500, 500)) == 1)
    }

    @Test func earlierWordsLightUpSooner() {
        #expect(lines.lineAt(lyricsClock(9_750, -250)) == 1)
        #expect(lines.lineAt(lyricsClock(9_700, -250)) == 0)
    }

    @Test func aTapPlaysFromWhereTheLineIsHeard() {
        #expect(heardAt(20_000, 750) == 20_750)
        #expect(heardAt(20_000, -1_000) == 19_000)
        #expect(lines.lineAt(lyricsClock(heardAt(20_000, 750), 750)) == 2)
        #expect(lines.lineAt(lyricsClock(heardAt(20_000, -1_000), -1_000)) == 2)
    }

    @Test func aTapNeverSeeksBeforeTheStart() {
        #expect(heardAt(0, -2_000) == 0)
        #expect(heardAt(1_000, -1_250) == 0)
    }

    @Test func stepsAreATwentiethOfASecondAndStopAtTheLimit() {
        #expect(stepTiming(0, 1) == 50)
        #expect(stepTiming(-250, -1) == -300)
        #expect(stepTiming(50, -1) == 0)
        #expect(stepTiming(TIMING_LIMIT_MS, 1) == TIMING_LIMIT_MS)
        #expect(stepTiming(-TIMING_LIMIT_MS, -3) == -TIMING_LIMIT_MS)
        #expect(stepTiming(LyricsOutputTiming.limitMs - 20, 1, limitMs: LyricsOutputTiming.limitMs) == LyricsOutputTiming.limitMs)
        #expect(LyricsOutputTiming.step(-LyricsOutputTiming.limitMs, steps: -1) == -LyricsOutputTiming.limitMs)
    }

    @Test func anOutputNeverMovedStartsFromItsAutomaticTiming() {
        let outputs = ["bluetooth:AA:BB": -150, "speaker": 50, "usb:DAC": 0]
        let speaker = AudioOutput(key: "speaker", label: "Phone speaker")
        #expect(outputTimingIn(outputs, AudioOutput(key: "bluetooth:AA:BB", label: "Buds")).ms == -150)
        #expect(outputTimingIn(outputs, speaker).ms == 50)
        #expect(outputTimingIn(outputs, AudioOutput(key: "usb:DAC", label: "DAC")) == (0, false))
        #expect(outputTimingIn(outputs, AudioOutput(key: "wired", label: "Headphones")) == (-300, true))
        #expect(outputTimingIn(outputs, AudioOutput(key: "bluetooth:CC:DD", label: "Buds")) == (-500, true))
        #expect(outputTimingIn([:], speaker).ms == -300)
    }

    @Test func movingAnOutputStartsFromItsAutomaticTiming() {
        #expect(LyricsOutputTiming.step(LyricsOutputTiming.automatic("bluetooth:AA"), steps: -1) == -550)
        #expect(LyricsOutputTiming.step(LyricsOutputTiming.automatic("speaker"), steps: 1) == -250)
    }

    @Test func earbudsKeepTheTimingSavedUnderAnyOfTheirAddresses() {
        let earbuds = AudioOutput(key: "bluetooth:Enco X3", label: "Enco X3", formerKeys: ["bluetooth:AA:01", "bluetooth:AA:02"])
        #expect(outputTimingIn(["bluetooth:AA:02": -500], earbuds).ms == -500)
        #expect(outputTimingIn(["bluetooth:AA:02": -500, "bluetooth:Enco X3": -250], earbuds).ms == -250)
        #expect(outputTimingIn(["speaker": 50], earbuds) == (-500, true))
        #expect(outputTimingIn(["bluetooth:AA:01": -250], earbuds) == (-250, false))
    }

    @Test func theSongsAndTheOutputsTimingAddUp() {
        let total = totalOffset(songMs: 250, outputMs: -100)
        #expect(total == 150)
        #expect(lines.lineAt(lyricsClock(20_149, total)) == 1)
        #expect(lines.lineAt(lyricsClock(20_150, total)) == 2)
        #expect(heardAt(20_000, total) == 20_150)
    }

    @Test func theScreenLeadIsTwoFramesAtItsRefreshRate() {
        #expect(screenLeadMs(60) == -33)
        #expect(screenLeadMs(90) == -22)
        #expect(screenLeadMs(120) == -17)
        #expect(screenLeadMs(0) == -33)
        #expect(screenLeadMs(.nan) == -33)
    }

    @Test func theMenuLineNamesWhatWasMoved() {
        #expect(timingSummary(0, 0, "Galaxy Buds") == nil)
        #expect(timingSummary(250, 0, "Galaxy Buds") == "This song +0.25 s")
        #expect(timingSummary(0, -150, "Galaxy Buds") == "Galaxy Buds -0.15 s")
        #expect(timingSummary(-100, 50, "Phone speaker") == "This song -0.1 s · Phone speaker +0.05 s")
        #expect(timingSummary(0, -500, "Galaxy Buds", outputAutomatic: true) == nil)
        #expect(timingSummary(250, -300, "Phone speaker", outputAutomatic: true) == "This song +0.25 s")
    }

    @Test func aSongsOffsetReadsInPlainWords() {
        #expect(LyricsOutputTiming.label(0) == "In time")
        #expect(LyricsOutputTiming.label(250) == "0.25 s later")
        #expect(LyricsOutputTiming.label(-1_750) == "1.75 s earlier")
        #expect(LyricsOutputTiming.label(10_000) == "10 s later")
        #expect(LyricsOutputTiming.signed(-TIMING_LIMIT_MS) == "-10 s")
    }
}
