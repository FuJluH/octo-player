import Foundation
import Testing
@testable import OctoKit

@Suite struct LyricsTest {
    private let lines = [
        LyricLine(startMs: 1_000, text: "one"),
        LyricLine(startMs: 4_000, text: "two"),
        LyricLine(startMs: 4_000, text: "two again"),
        LyricLine(startMs: 9_000, text: "three"),
    ]

    @Test func theLineBeingSungIsTheLastOneStarted() {
        #expect(lines.lineAt(0) == -1)
        #expect(lines.lineAt(999) == -1)
        #expect(lines.lineAt(1_000) == 0)
        #expect(lines.lineAt(3_999) == 0)
        // Two lines at one time: the later of them.
        #expect(lines.lineAt(4_000) == 2)
        #expect(lines.lineAt(9_000) == 3)
        #expect(lines.lineAt(600_000) == 3)
        #expect([LyricLine]().lineAt(5_000) == -1)
    }

    @Test func longWaitsGetAGapLine() {
        let lyrics = Lyrics(
            synced: true,
            lines: [
                LyricLine(startMs: 8_000, endMs: 10_000, text: "late start"),
                LyricLine(startMs: 20_000, text: "after a wait"),
            ],
            source: .server
        )
        let shown = lyrics.shownLines()
        #expect(shown.map(\.startMs) == [0, 8_000, 10_000, 20_000])
        #expect(shown[0].isGap)
        #expect(shown[2].isGap)
        #expect(shown.endOf(2) == 20_000)
    }

    @Test func songFileTagsPreferTimedText() {
        let tags: [(key: String, value: [String])] = [
            ("LYRICS", ["Plain words"]),
            ("UNSYNCEDLYRICS", ["[00:01.00]Timed words"]),
        ]
        #expect(songFileLyrics(tags) == "[00:01.00]Timed words")
        #expect(songFileLyrics([(key: "lyrics:eng", value: ["Described"])]) == "Described")
        #expect(songFileLyrics([(key: "TITLE", value: ["Not lyrics"]), (key: "LYRICS", value: [" "])]) == nil)
    }

    @Test func theOnlineLookupSendsOnlyWhatItNeeds() {
        let url = lookupUrl(URL(string: "https://lyrics.example")!, title: "Song", artist: "Artist", album: "", durationMs: 201_600)
        #expect(encodedPath(url) == "/api/get")
        #expect(queryParameter(url, "track_name") == "Song")
        #expect(queryParameter(url, "artist_name") == "Artist")
        #expect(queryParameter(url, "duration") == "202")
        #expect(queryParameter(url, "album_name") == nil)
        #expect(querySize(url) == 3)
    }

    @Test func theOnlineAnswerPrefersSyncedLyrics() {
        let both = libraryLyrics(#"{"id":1,"instrumental":false,"plainLyrics":"Hello","syncedLyrics":"[00:01.00] Hello"}"#)
        #expect(both!.synced)
        #expect(both!.source == .online)
        let plainOnly = libraryLyrics(#"{"plainLyrics":"Hello","syncedLyrics":null}"#)
        #expect(!plainOnly!.synced)
        #expect(libraryLyrics(#"{"instrumental":true}"#)!.instrumental)
        #expect(libraryLyrics(#"{"plainLyrics":null,"syncedLyrics":null}"#) == nil)
        #expect(libraryLyrics("not json") == nil)
    }

    @Test func searchFindsATimedCopyOfTheSameRecording() {
        let body = """
            [
                {"trackName":"Song","artistName":"Artist","albumName":"Other","duration":201.0,"plainLyrics":"Hi","syncedLyrics":null},
                {"trackName":"Song","artistName":"Artist","albumName":"Live","duration":260.0,"syncedLyrics":"[00:01.00] Live take"},
                {"trackName":"Song","artistName":"Artist","albumName":"Other","duration":202.5,"syncedLyrics":"[00:01.00] Close"},
                {"trackName":"song!","artistName":"ARTIST","albumName":"Album","duration":203.9,"syncedLyrics":"[00:01.00] Same album"}
            ]
            """
        // Same album wins among copies of the right length; the live one is too long.
        #expect(bestSearchMatch(body, title: "Song", artist: "Artist", album: "Album", durationMs: 201_600)!.lines.first!.text == "Same album")
        #expect(bestSearchMatch(body, title: "Song", artist: "Artist", album: "Nothing like it", durationMs: 201_600)!.lines.first!.text == "Close")
        #expect(bestSearchMatch(
            #"[{"trackName":"Song","artistName":"Artist","duration":201.0,"plainLyrics":"Hi"}]"#,
            title: "Song", artist: "Artist", album: "", durationMs: 201_000
        ) == nil)
        #expect(bestSearchMatch("not json", title: "Song", artist: "Artist", album: "", durationMs: 0) == nil)
    }

    @Test func searchNeverTakesAnotherSongOfTheSameLength() {
        // What the library answered for "$UICIDE": other songs by the same artist, one of them
        // within a second of its length.
        let body = """
            [
                {"trackName":"Ultimate $uicide","artistName":"$uicideboy$","albumName":"High Tide","duration":170.0,"syncedLyrics":"[00:01.00] Wrong song"},
                {"trackName":"Black $uicide","artistName":"$uicideboy$","albumName":"Black $uicide","duration":170.0,"syncedLyrics":"[00:01.00] Also wrong"}
            ]
            """
        #expect(bestSearchMatch(body, title: "$UICIDE", artist: "$uicideboy$", album: "Sing Me a Lullaby", durationMs: 169_000) == nil)
        // Another artist's song of the same name is not it either.
        let other = #"[{"trackName":"Song","artistName":"Someone Else","duration":200.0,"syncedLyrics":"[00:01.00] Theirs"}]"#
        #expect(bestSearchMatch(other, title: "Song", artist: "Artist", album: "", durationMs: 200_000) == nil)
        // Nor a remix of it.
        let remix = #"[{"trackName":"Song (Club Remix)","artistName":"Artist","duration":200.0,"syncedLyrics":"[00:01.00] Remix"}]"#
        #expect(bestSearchMatch(remix, title: "Song", artist: "Artist", album: "", durationMs: 200_000) == nil)
    }

    @Test func searchAsksByTitleAndArtistOnly() {
        let url = searchUrl(URL(string: "https://lyrics.example")!, title: "Song", artist: "Artist")
        #expect(encodedPath(url) == "/api/search")
        #expect(queryParameter(url, "track_name") == "Song")
        #expect(queryParameter(url, "artist_name") == "Artist")
        #expect(queryParameter(url, "duration") == nil)
    }
}
