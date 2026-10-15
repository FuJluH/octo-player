import Foundation
import Testing
@testable import OctoKit

@Suite struct ServerLyricsTest {
    private let text = "Café naïve 日本"

    // Bytes: "Café " is 0..5 (é is two), "naïve " 6..12 (ï is two), 日 13..15 and 本 16..18
    // (three each), both ends included.
    private let cues = [
        Cue(start: 1_000, end: 1_500, value: "Café ", byteStart: 0, byteEnd: 5),
        Cue(start: 1_500, end: 2_500, value: "naïve ", byteStart: 6, byteEnd: 12),
        Cue(start: 2_500, end: 3_000, value: "日", byteStart: 13, byteEnd: 15),
        Cue(start: 3_000, end: 3_500, value: "本", byteStart: 16, byteEnd: 18),
    ]

    @Test func byteOffsetsBecomeCharacterRanges() {
        let words = cueWords(CueLine(index: 0, start: 1_000, end: 3_500, value: text, cue: cues))
        #expect(words.map { text.utf16Slice($0.from, $0.to) } == ["Café ", "naïve ", "日", "本"])
        #expect(words.map { [$0.from, $0.to] } == [[0, 5], [5, 11], [11, 12], [12, 13]])
        #expect(words.map(\.text) == cues.map(\.value))
    }

    @Test func lettersBuiltFromTwoCharsKeepBothChars() {
        // The note is four bytes and two UTF-16 units.
        let line = "🎵 la"
        let words = cueWords(
            CueLine(value: line, cue: [Cue(start: 0, end: 500, value: "note", byteStart: 0, byteEnd: 3), Cue(start: 500, end: 900, value: " la", byteStart: 4, byteEnd: 6)])
        )
        #expect(words.map { [$0.from, $0.to] } == [[0, 2], [2, 5]])
    }

    @Test func anEndInsideALetterTakesTheWholeLetter() {
        let range = Utf8Positions("日本").charRange(1, 3)
        #expect(range == 0..<2)
    }

    @Test func cuesOutsideTheTextAreLeftOut() {
        let words = cueWords(CueLine(value: "ab", cue: [
            Cue(start: 0, end: 1, value: "a", byteStart: 0, byteEnd: 0),
            Cue(start: 1, end: 2, value: "?", byteStart: 1, byteEnd: 9),
            Cue(start: 2, end: 3, value: "?", byteStart: 1, byteEnd: 0),
        ]))
        #expect(words.count == 1)
    }

    @Test func missingEndsComeFromTheNextCue() {
        let words = cueWords(CueLine(end: 900, value: "a b", cue: [
            Cue(start: 0, end: nil, value: "a ", byteStart: 0, byteEnd: 1),
            Cue(start: 400, end: nil, value: "b", byteStart: 2, byteEnd: 2),
        ]))
        #expect(words.map(\.endMs) == [400, 900])
    }

    private func enhanced() -> [StructuredLyrics] {
        [
            StructuredLyrics(
                lang: "fra",
                synced: true,
                line: [LyricsLine(start: 1_000, value: "\(text) (écho)"), LyricsLine(start: 4_000, value: ""), LyricsLine(start: 9_000, value: "Fin")],
                offset: -100,
                kind: "main",
                agents: [LyricsAgent(id: "lead", role: "main", name: "Lead"), LyricsAgent(id: "backing", role: "bg")],
                cueLine: [
                    CueLine(index: 0, agentId: "lead", start: 1_000, end: 3_500, value: text, cue: cues),
                    CueLine(index: 0, agentId: "backing", start: 2_000, end: 3_500, value: "(écho)",
                            cue: [Cue(start: 2_000, end: 3_500, value: "(écho)", byteStart: 0, byteEnd: 6)]),
                ]
            ),
            StructuredLyrics(
                lang: "eng",
                synced: true,
                line: [LyricsLine(start: 1_000, value: "Naive coffee Japan"), LyricsLine(start: 4_000, value: ""), LyricsLine(start: 9_000, value: "End")],
                kind: "translation"
            ),
            StructuredLyrics(lang: "und", synced: false, line: [LyricsLine(value: text)]),
        ]
    }

    @Test func mapsTheSyncedMainLyricsWithWordsBackingAndTranslation() throws {
        let lyrics = try #require(serverLyrics(enhanced(), language: "en"))
        #expect(lyrics.synced)
        #expect(lyrics.source == .server)
        let first = lyrics.lines.first!
        // The offset of -100 makes every time later by 100.
        #expect(first.startMs == 1_100)
        #expect(first.text == text)
        #expect(first.words.first!.startMs == 1_100)
        #expect(first.backingText == "(écho)")
        #expect(first.backing.count == 1)
        #expect(first.backing[0].from == 0 && first.backing[0].to == 6)
        #expect(first.agent == "Lead")
        #expect(first.translation == "Naive coffee Japan")
        #expect(first.endMs == 3_600)
        #expect(lyrics.lines[1].isGap)
        #expect(lyrics.lines[2].translation == "End")
    }

    @Test func noTranslationWhenThePhoneReadsTheSongsLanguage() throws {
        let lyrics = try #require(serverLyrics(enhanced(), language: "fr"))
        #expect(lyrics.lines.first!.translation == nil)
    }

    @Test func aLineSungOnlyByBackingVoicesIsMarked() throws {
        let lyrics = try #require(
            serverLyrics(
                [
                    StructuredLyrics(
                        synced: true,
                        line: [LyricsLine(start: 0, value: "ooh")],
                        agents: [LyricsAgent(id: "lead", role: "main"), LyricsAgent(id: "choir", role: "bg")],
                        cueLine: [CueLine(index: 0, agentId: "choir", start: 0, end: 800, value: "ooh",
                                          cue: [Cue(start: 0, end: 800, value: "ooh", byteStart: 0, byteEnd: 2)])]
                    ),
                ],
                language: "en"
            )
        )
        #expect(lyrics.lines.count == 1)
        #expect(lyrics.lines[0].background)
        #expect(lyrics.lines[0].text == "ooh")
    }

    @Test func plainServerLyricsStayPlain() throws {
        let lyrics = try #require(serverLyrics([enhanced().last!], language: "en"))
        #expect(!lyrics.synced)
        #expect(lyrics.lines.count == 1)
        #expect(lyrics.lines[0].text == text)
    }

    @Test func nothingUsableIsNull() {
        #expect(serverLyrics([], language: "en") == nil)
        #expect(serverLyrics([StructuredLyrics(synced: true, line: [LyricsLine(start: 0, value: "x")], kind: "translation")], language: "en") == nil)
    }

    @Test func languagesMatchInTwoOrThreeLetters() {
        #expect(sameLanguage("en", "eng"))
        #expect(sameLanguage("fra", "fr"))
        #expect(!sameLanguage("ko", "en"))
    }
}
