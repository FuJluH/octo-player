import Foundation
import Testing
@testable import OctoKit

// Which online lyrics are the song playing, and what the online library is asked, always against
// a local stand-in, never the real one.
@Suite struct LyricsMatchTest {
    private let server = StubLibrary()

    private func answer(_ body: String, code: Int = 200) {
        server.answer(body, code: code)
    }

    private func copy(_ title: String, _ artist: String, seconds: Double = 170.0, words: String = "Found") -> String {
        #"{"id":1,"trackName":"\#(title)","artistName":"\#(artist)","albumName":"Album","duration":\#(seconds),"syncedLyrics":"[00:01.00] \#(words)"}"#
    }

    private func found(_ body: String, _ title: String, _ artist: String, ms: Int = 169_500) -> String? {
        bestSearchMatch("[\(body)]", title: title, artist: artist, album: "Album", durationMs: ms)?.lines.first?.text
    }

    private let dollar = "$"

    @Test func stylizedNamesFindTheirLyrics() {
        #expect(found(copy("Suicide", "Suicideboys"), "\(dollar)UICIDE", "\(dollar)uicideboy\(dollar)") == "Found")
        #expect(found(copy("Ultimate \(dollar)uicide", "\(dollar)uicideboy\(dollar)"), "\(dollar)UICIDE", "\(dollar)uicideboy\(dollar)") == nil)
    }

    @Test func aCurlyApostropheFindsTheStraightOne() {
        #expect(found(copy("Huntin' Wabbitz", "\(dollar)uicideboy\(dollar)"), "Huntin’ Wabbitz", "\(dollar)uicideboy\(dollar)") == "Found")
    }

    @Test func creditsJoinedWithACommaOfTheirOwnStillMatch() {
        #expect(found(copy("Real Friends (Explicit)", "Kanye West、Ty Dolla \(dollar)ign"), "Real Friends", "Kanye West") == "Found")
        #expect(found(copy("Can't Tell Me Nothing", "Ye (侃爷)"), "Can't Tell Me Nothing", "Kanye West") == "Found")
    }

    @Test func aKnownNameIsNotItsFirstWord() {
        #expect(found(copy("EARFQUAKE", "Tyler, The Creator"), "EARFQUAKE", "Tyler The Creator") == "Found")
        #expect(found(copy("EARFQUAKE", "Tyler"), "EARFQUAKE", "Tyler, The Creator") == nil)
    }

    @Test func aCleanEditCarriesTheSongsLyrics() {
        // The same words at the same times, a few bleeped: good lyrics for either, both ways
        // round.
        #expect(found(copy("Movie Star (Clean)", "Jack Harlow"), "Movie Star", "Jack Harlow") == "Found")
        #expect(found(copy("Movie Star", "Jack Harlow"), "Movie Star (Clean)", "Jack Harlow") == "Found")
        #expect(sameLyricsSong("Movie Star", wantArtist: "Jack Harlow", gotTitle: "Movie Star (Clean)", gotArtist: "Jack Harlow、Pharrell Williams"))
        // Other versions still never stand in.
        #expect(found(copy("Movie Star (Remix)", "Jack Harlow"), "Movie Star", "Jack Harlow") == nil)
        #expect(found(copy("Movie Star (Live)", "Jack Harlow"), "Movie Star (Clean)", "Jack Harlow") == nil)
    }

    @Test func searchesKeepTheArtistAndStopAtThree() {
        #expect(
            lyricsSearches("\(dollar)UICIDE", artist: "\(dollar)uicideboy\(dollar)")
                == [SongQuery(title: "\(dollar)UICIDE", artist: "\(dollar)uicideboy\(dollar)"), SongQuery(title: "SUICIDE", artist: "suicideboys")]
        )
        #expect(
            lyricsSearches("Too Good (feat. Rihanna)", artist: "Drake feat. Rihanna").map(\.text)
                == ["Drake feat. Rihanna Too Good (feat. Rihanna)", "Drake feat. Rihanna Too Good", "Drake Too Good"]
        )
        #expect(lyricsSearches("Song", artist: "Artist") == [SongQuery(title: "Song", artist: "Artist")])
    }

    @Test func theLookupTriesTheNextSearchWhenOneFindsNothing() async throws {
        answer(#"{"code":404}"#, code: 404)
        answer("[]")
        answer("[\(copy("Suicide", "Suicideboys"))]")
        let lyrics = try await OnlineLyrics(session: server.session, base: server.base)
            .find("\(dollar)UICIDE", artist: "\(dollar)uicideboy\(dollar)", album: "", durationMs: 170_000)
        #expect(lyrics?.lines.first?.text == "Found")
        #expect(encodedPath(server.takeRequest()) == "/api/get")
        let first = server.takeRequest()
        #expect(queryParameter(first, "artist_name") == "\(dollar)uicideboy\(dollar)")
        let second = server.takeRequest()
        #expect(queryParameter(second, "track_name") == "SUICIDE")
        #expect(queryParameter(second, "artist_name") == "suicideboys")
    }

    @Test func theCopiesToChooseFromComeFromTheFirstSearchThatHasAny() async throws {
        answer("[]")
        answer("[\(copy("Suicide (Live)", "Suicideboys"))]")
        let copies = try await OnlineLyrics(session: server.session, base: server.base)
            .copiesOf("\(dollar)UICIDE", artist: "\(dollar)uicideboy\(dollar)", album: "", durationMs: 0)
        // A live take stays in the list, since the listener picks.
        #expect(copies.map(\.title) == ["Suicide (Live)"])
        #expect(server.requestCount == 2)
    }
}
