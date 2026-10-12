import Foundation
import Testing
@testable import OctoKit

// The server's word cues, exactly as an Octo server sends them, through to the words the flowing
// view lights one by one.
@Suite struct ServerCuesTest {
    // "Café " is bytes 0..5 (é is two); "日本語" is 0..8, three bytes a letter.
    private let answer = """
        {"subsonic-response":{"status":"ok","version":"1.16.1","lyricsList":{"structuredLyrics":[
          {"lang":"xxx","synced":true,"offset":0,"kind":"main",
           "line":[{"start":1000,"value":"Café au lait"},{"start":4000,"value":"日本語の歌"},{"start":7000,"value":"Plain line"}],
           "cueLine":[
             {"index":0,"start":1000,"end":3500,"value":"Café au lait","cue":[
               {"start":1000,"end":1500,"byteStart":0,"byteEnd":5,"value":"Café "},
               {"start":1500,"end":2500,"byteStart":6,"byteEnd":8,"value":"au "},
               {"start":2500,"end":3500,"byteStart":9,"byteEnd":12,"value":"lait"}]},
             {"index":1,"start":4000,"end":6500,"value":"日本語の歌","cue":[
               {"start":4000,"end":5000,"byteStart":0,"byteEnd":8,"value":"日本語"},
               {"start":5000,"end":5500,"byteStart":9,"byteEnd":11,"value":"の"},
               {"start":5500,"end":6500,"byteStart":12,"byteEnd":14,"value":"歌"}]}]}]}}}
        """

    private func parsed() throws -> Lyrics {
        let list: LyricsListBody = try SubsonicClient.decode(Data(answer.utf8), key: "lyricsList")
        return try #require(serverLyrics(list.structuredLyrics, language: "fr"))
    }

    @Test func theFlowingViewLightsEachWord() throws {
        let lines = LyricMapper.map(try parsed()).filter { !$0.isInterlude }
        let cafe = lines[0]
        #expect(!cafe.isLineTimed)
        #expect(cafe.words.map(\.text) == ["Café", "au", "lait"])
        #expect(cafe.words.map(\.start) == [1.0, 1.5, 2.5])
        #expect(cafe.words.map(\.end) == [1.5, 2.5, 3.5])
        #expect(cafe.words.map(\.trailingSpace) == [true, true, true])

        // No spaces between the words of a Japanese line, so none are drawn.
        let song = lines[1]
        #expect(!song.isLineTimed)
        #expect(song.words.map(\.text) == ["日本語", "の", "歌"])
        #expect(song.words.map(\.trailingSpace) == [false, false, true])

        let plain = lines[2]
        #expect(plain.isLineTimed)
        #expect(plain.text == "Plain line")
    }

    @Test func spacesACueLineStartsWithDoNotMoveItsWords() throws {
        let line = CueLine(
            index: 0,
            start: 0,
            value: "  Café noir",
            cue: [
                Cue(start: 0, end: 500, value: "  Café ", byteStart: 0, byteEnd: 7),
                Cue(start: 500, end: 900, value: "noir", byteStart: 8, byteEnd: 11),
            ]
        )
        let lyrics = try #require(
            serverLyrics(
                [
                    StructuredLyrics(
                        synced: true,
                        line: [LyricsLine(start: 0, value: "  Café noir")],
                        cueLine: [line]
                    ),
                ],
                language: nil
            )
        )
        #expect(lyrics.lines.count == 1)
        let only = lyrics.lines[0]
        #expect(only.text == "Café noir")
        #expect(only.words.map { only.text.utf16Slice($0.from, $0.to) } == ["Café ", "noir"])
    }
}
