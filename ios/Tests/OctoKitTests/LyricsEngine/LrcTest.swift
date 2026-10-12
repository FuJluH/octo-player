import Foundation
import Testing
@testable import OctoKit

@Suite struct LrcTest {
    private func parse(_ text: String) -> Lyrics { parseLyricsText(text, source: .lyricsFile)! }

    @Test func readsStampsInEveryWrittenForm() {
        let lyrics = parse(
            """
            [00:01.5]half
            [00:02.25]quarter
            [00:03.125]eighth
            [00:04]whole
            [01:05:50]colon
            """
        )
        #expect(lyrics.synced)
        #expect(lyrics.lines.map(\.startMs) == [1_500, 2_250, 3_125, 4_000, 65_500])
        #expect(lyrics.lines.last!.text == "colon")
    }

    @Test func aLineWithSeveralStampsIsSungAtEach() {
        let lyrics = parse(
            """
            [00:10.00][00:40.00]Chorus line
            [00:20.00]Verse line
            """
        )
        #expect(lyrics.lines.map(\.startMs) == [10_000, 20_000, 40_000])
        #expect(lyrics.lines.map(\.text) == ["Chorus line", "Verse line", "Chorus line"])
    }

    @Test func tagsAreSkippedAndTheOffsetMovesEveryLine() {
        let lyrics = parse(
            """
            [ar:Someone]
            [ti:Something]
            [length: 03:20]
            [offset:+500]
            [00:10.00]Sooner
            [00:00.20]Never before the start
            """
        )
        #expect(lyrics.lines.map(\.startMs) == [0, 9_500])
        #expect(lyrics.lines[1].text == "Sooner")

        let later = parse("[offset:-250]\n[00:10.00]Later")
        #expect(later.lines.count == 1)
        #expect(later.lines[0].startMs == 10_250)
    }

    @Test func emptyTimedLinesAreGaps() {
        let lyrics = parse("[00:01.00]One\n[00:05.00]\n[00:20.00]Two")
        #expect(lyrics.lines.count == 3)
        #expect(lyrics.lines[1].isGap)
        #expect(!lyrics.lines[0].isGap)
    }

    @Test func wordStampsTimeEachWord() {
        let lyrics = parse("[00:12.00]<00:12.00>Hello <00:12.50>naïve <00:13.20>world<00:14.00>")
        #expect(lyrics.lines.count == 1)
        let line = lyrics.lines[0]
        #expect(line.text == "Hello naïve world")
        #expect(line.words.map(\.startMs) == [12_000, 12_500, 13_200])
        #expect(line.words.map(\.endMs) == [12_500, 13_200, 14_000])
        #expect(line.words.map { line.text.utf16Slice($0.from, min($0.to, line.text.utf16.count)) } == ["Hello ", "naïve ", "world"])
        #expect(line.endMs == 14_000)
    }

    @Test func textBeforeTheFirstWordStampStartsWithTheLine() {
        let lines = parse("[00:05.00]Oh <00:06.00>yes").lines
        #expect(lines.count == 1)
        let line = lines[0]
        #expect(line.text == "Oh yes")
        #expect(line.words.first!.startMs == 5_000)
        #expect(line.words.first!.endMs == 6_000)
    }

    @Test func wordStampsMoveWithTheOffset() {
        let lines = parse("[offset:1000]\n[00:05.00]<00:05.00>a <00:06.00>b").lines
        #expect(lines.count == 1)
        let line = lines[0]
        #expect(line.startMs == 4_000)
        #expect(line.words.map(\.startMs) == [4_000, 5_000])
    }

    @Test func backingLinesJoinTheLineBefore() {
        let lines = parse("[00:05.00]Lead line\n[bg: <00:06.00>ooh <00:07.00>aah]").lines
        #expect(lines.count == 1)
        let line = lines[0]
        #expect(line.backingText == "ooh aah")
        #expect(line.backing.count == 2)
    }

    @Test func linesComeOutInTimeOrder() {
        let lyrics = parse("[00:30.00]Third\n[00:10.00]First\n[00:20.00]Second")
        #expect(lyrics.lines.map(\.text) == ["First", "Second", "Third"])
    }

    @Test func textWithoutStampsIsPlain() {
        let lyrics = parse("[ar:Someone]\nFirst line\n\n\n\nSecond verse\n\n")
        #expect(!lyrics.synced)
        #expect(lyrics.lines.map(\.text) == ["First line", "", "Second verse"])
    }

    @Test func windowsLineEndsAndAByteOrderMarkAreFine() {
        let lyrics = parse("\u{FEFF}" + "[00:01.00]One\r\n[00:02.00]Two\r\n")
        #expect(lyrics.lines.map(\.text) == ["One", "Two"])
    }

    @Test func nothingToShowIsNull() {
        #expect(parseLyricsText("", source: .songFile) == nil)
        #expect(parseLyricsText("[ar:Someone]\n[ti:Nothing]", source: .songFile) == nil)
        #expect(parseLyricsText("[00:01.00]\n[00:02.00]", source: .songFile) == nil)
    }
}
