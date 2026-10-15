import Foundation
import Testing
@testable import OctoKit

@Suite struct LyricMapperTest {
    private func synced(_ lines: LyricLine...) -> Lyrics { Lyrics(synced: true, lines: lines, source: .server) }

    // A line whose words are its space-separated parts, each `each` ms long.
    private func worded(_ start: Int, _ text: String, each: Int = 500) -> LyricLine {
        var at = 0
        let all = text.units
        var words: [LyricWord] = []
        for (index, word) in text.split(separator: " ", omittingEmptySubsequences: false).map(String.init).enumerated() {
            let piece = word.units
            var from = at
            while from + piece.count <= all.count && Array(all[from..<(from + piece.count)]) != piece { from += 1 }
            at = from + piece.count
            words.append(LyricWord(startMs: start + index * each, endMs: start + (index + 1) * each, text: word, from: from, to: from + piece.count))
        }
        return LyricLine(startMs: start, endMs: start + words.count * each, text: text, words: words)
    }

    @Test func directionComesFromTheFirstLetterWithOne() {
        #expect(isRtl("שלום עולם"))
        #expect(isRtl("مرحبا"))
        #expect(isRtl("ܫܠܡܐ"))
        #expect(isRtl("ހެލޯ"))
        #expect(isRtl("ߊߟߎ"))
        // Numbers and brackets have no direction of their own.
        #expect(isRtl("123 (שלום) hello"))
        #expect(!isRtl("hello שלום"))
        #expect(!isRtl("..."))
    }

    @Test func rightToLeftAndDuetDecideTheSide() {
        func side(rtl: Bool, duet: Bool) -> Bool {
            SyncLine(index: 0, text: "x", words: [], start: 0.0, end: 1.0, rtl: rtl, isDuet: duet).alignRight
        }
        #expect(!side(rtl: false, duet: false))
        #expect(side(rtl: false, duet: true))
        #expect(side(rtl: true, duet: false))
        #expect(!side(rtl: true, duet: true))
    }

    @Test func theMappedLinesKeepTheirDirectionAndDuet() {
        let lines = LyricMapper.map(
            synced(
                LyricLine(startMs: 0, text: "שלום"),
                LyricLine(startMs: 1_000, text: "hello", duet: true),
                LyricLine(startMs: 2_000, text: "שלום", duet: true)
            )
        )
        #expect(lines.map(\.alignRight) == [true, true, false])
    }

    @Test func aTranslationOrRomanizationTheSameAsTheLineIsDropped() {
        let lines = LyricMapper.map(
            synced(
                LyricLine(startMs: 0, text: "Hello world", translation: "hello  WORLD", romanization: "HelloWorld"),
                LyricLine(startMs: 1_000, text: "こんにちは", translation: "Hello", romanization: "konnichiwa")
            )
        )
        #expect(lines[0].translation == nil)
        #expect(lines[0].romanization == nil)
        #expect(lines[1].translation == "Hello")
        #expect(lines[1].romanization == "konnichiwa")
    }

    @Test func syllablesOfOneWordStayTogether() {
        let text = "Hello world"
        let line = LyricLine(
            startMs: 0,
            endMs: 1_500,
            text: text,
            words: [
                LyricWord(startMs: 0, endMs: 300, text: "Hel", from: 0, to: 3),
                LyricWord(startMs: 300, endMs: 700, text: "lo", from: 3, to: 5),
                LyricWord(startMs: 800, endMs: 1_500, text: "world", from: 6, to: 11),
            ]
        )
        let mapped = LyricMapper.map(synced(line))
        #expect(mapped.count == 1)
        let words = mapped[0].words
        #expect(words.map(\.text) == ["Hel", "lo", "world"])
        #expect(words.map(\.trailingSpace) == [false, true, true])
        #expect(near(0.3, words[0].end, 1e-12))
        #expect(near(0.8, words[2].start, 1e-12))
    }

    @Test func wordsCarryingTheirOwnSpacesEndGroups() {
        // Pieces the way timed LRC gives them, spaces inside the pieces.
        let text = "so long"
        let line = LyricLine(
            startMs: 0,
            text: text,
            words: [LyricWord(startMs: 0, endMs: 400, text: "so ", from: 0, to: 3), LyricWord(startMs: 400, endMs: 900, text: "long", from: 3, to: 7)]
        )
        let mapped = LyricMapper.map(synced(line))
        #expect(mapped.count == 1)
        let words = mapped[0].words
        #expect(words.map(\.text) == ["so", "long"])
        #expect(words.map(\.trailingSpace) == [true, true])
    }

    @Test func aLineTimedByLineGetsOneWordAcrossIt() {
        let lines = LyricMapper.map(synced(LyricLine(startMs: 1_000, text: "no word timing"), LyricLine(startMs: 3_000, text: "next")))
        let first = lines.first!
        #expect(first.isLineTimed)
        #expect(first.words.count == 1)
        #expect(first.words[0].text == "no word timing")
        #expect(near(1.0, first.words[0].start, 0.0))
        #expect(near(3.0, first.words[0].end, 0.0))
    }

    @Test func wordsThatDoNotCoverTheLineFallBackToTheWholeLine() {
        let line = LyricLine(startMs: 0, endMs: 1_000, text: "two words", words: [LyricWord(startMs: 0, endMs: 500, text: "two", from: 0, to: 3)])
        let mapped = LyricMapper.map(synced(line))
        #expect(mapped.count == 1)
        #expect(mapped[0].isLineTimed)
    }

    @Test func aLongWaitBetweenLinesGetsAnInterlude() {
        let lines = LyricMapper.map(synced(worded(0, "one two"), worded(11_000, "three four")))
        #expect(lines.count == 3)
        let gap = lines[1]
        #expect(gap.isInterlude)
        #expect(near(1.0, gap.start, 0.0))
        #expect(near(11.0, gap.end, 0.0))
        #expect(gap.words.isEmpty)
        #expect(lines.map(\.index) == [0, 1, 2])
    }

    @Test func aShortWaitStretchesTheLineInstead() {
        let lines = LyricMapper.map(synced(worded(0, "one two"), worded(3_000, "three")))
        #expect(lines.count == 2)
        #expect(!lines.contains { $0.isInterlude })
        #expect(near(3.0, lines[0].end, 0.0))
    }

    @Test func aLateFirstLineGetsAnInterludeBeforeIt() {
        let lines = LyricMapper.map(synced(worded(8_000, "late start")))
        #expect(lines[0].isInterlude)
        #expect(near(0.0, lines[0].start, 0.0))
        #expect(near(8.0, lines[0].end, 0.0))
        let early = LyricMapper.map(synced(worded(2_000, "early start")))
        #expect(!early[0].isInterlude)
    }

    @Test func anEmptySourceLineIsAnInterludeWhenThereIsRoom() {
        let lines = LyricMapper.map(
            synced(
                LyricLine(startMs: 0, text: "verse"),
                LyricLine(startMs: 4_000, text: ""),
                LyricLine(startMs: 7_000, text: "chorus"),
                LyricLine(startMs: 9_000, text: ""),
                LyricLine(startMs: 10_000, text: "tag")
            )
        )
        #expect(lines.map(\.text) == ["verse", "", "chorus", "tag"])
        #expect(lines[1].isInterlude)
        #expect(near(4.0, lines[1].start, 0.0))
        #expect(near(7.0, lines[1].end, 0.0))
        // The one-second gap was too short for dots; the line before it holds on.
        #expect(near(10.0, lines[2].end, 0.0))
    }

    @Test func backingVocalsFollowTheirLineWithoutBrackets() {
        var line = worded(0, "hold on")
        line.backingText = "(ooh yeah)"
        line.backing = [LyricWord(startMs: 200, endMs: 600, text: "(ooh", from: 0, to: 4), LyricWord(startMs: 600, endMs: 1_000, text: "yeah)", from: 5, to: 10)]
        line.duet = true
        let lines = LyricMapper.map(synced(line))
        #expect(lines.count == 2)
        let backing = lines[1]
        #expect(backing.isBackground)
        #expect(backing.text == "ooh yeah")
        #expect(backing.words.map(\.text) == ["ooh", "yeah"])
        #expect(near(0.2, backing.start, 1e-12))
        #expect(near(1.0, backing.end, 1e-12))
        #expect(backing.isDuet)
    }

    @Test func aLineOnlyBackingVoicesSingIsABackgroundLine() {
        let lines = LyricMapper.map(synced(LyricLine(startMs: 0, text: "(la la)", background: true)))
        #expect(lines.count == 1)
        #expect(lines[0].isBackground)
        #expect(lines[0].text == "la la")
    }

    @Test func aCreditLineOnlyWhenWritersAreKnown() {
        let lyrics = synced(worded(0, "one"), worded(1_000, "two"))
        #expect(!LyricMapper.map(lyrics).contains { $0.isCredit })
        let credited = LyricMapper.map(lyrics, writers: ["A", "B", "C"])
        let credit = credited.last!
        #expect(credit.isCredit)
        #expect(credit.text == "Written by A, B & C")
        #expect(near(1.5, credit.start, 0.0))
        #expect(near(Double.infinity, credit.end, 0.0))
    }

    @Test func creditLinesFromTheSourceAreSkipped() {
        let lines = LyricMapper.map(
            synced(LyricLine(startMs: 0, text: "作词 : Someone"), LyricLine(startMs: 1_000, text: "Written by: Someone"), LyricLine(startMs: 2_000, text: "the song"))
        )
        #expect(lines.filter { !$0.isInterlude }.map(\.text) == ["the song"])
    }

    @Test func plainLyricsGiveNothing() {
        #expect(LyricMapper.map(Lyrics(synced: false, lines: [LyricLine(text: "a")], source: .online)).isEmpty)
    }
}
