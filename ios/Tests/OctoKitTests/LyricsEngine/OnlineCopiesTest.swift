import Foundation
import Testing
@testable import OctoKit

// The copies the lyrics menu offers from the online library, always against a local stand-in,
// never the real one.
@Suite struct OnlineCopiesTest {
    private let server = StubLibrary()

    private func library() -> OnlineLyrics { OnlineLyrics(session: server.session, base: server.base) }

    private func answer(_ body: String, code: Int = 200) {
        server.answer(body, code: code)
    }

    private let search = """
        [
            {"id":1,"trackName":"Song","artistName":"Artist","albumName":"Other","duration":260.0,"syncedLyrics":"[00:01.00] Live take"},
            {"id":2,"trackName":"Song","artistName":"Artist","albumName":"Album","duration":201.0,"plainLyrics":"Plain words"},
            {"id":3,"trackName":"Song (Club Remix)","artistName":"Artist","albumName":"Remixes","duration":300.0,"syncedLyrics":"[00:01.00] Remix"},
            {"id":4,"trackName":"Song","artistName":"Artist","albumName":"Album","duration":202.0,"syncedLyrics":"[00:01.00] Same album"},
            {"id":5,"trackName":"Another Song","artistName":"Artist","duration":201.0,"syncedLyrics":"[00:01.00] Not this song"},
            {"id":6,"trackName":"Song","artistName":"Someone Else","duration":201.0,"syncedLyrics":"[00:01.00] Theirs"},
            {"id":7,"trackName":"Song","artistName":"Artist","duration":201.0}
        ]
        """

    @Test func theExactMatchKeepsItsNumber() async throws {
        answer(#"{"id":42,"trackName":"Song","artistName":"Artist","albumName":"Album","duration":201.0,"syncedLyrics":"[00:01.00] Hello"}"#)
        let copy = try #require(try await library().exact("Song", artist: "Artist", album: "Album", durationMs: 201_000))
        #expect(copy.id == 42)
        #expect(copy.lyrics.onlineId == 42)
        #expect(copy.durationMs == 201_000)
        #expect(copy.album == "Album")
        #expect(copy.lyrics.synced)
        #expect(encodedPath(server.takeRequest()) == "/api/get")
    }

    @Test func aSearchThatFailsIsNotTakenForNoLyrics() async {
        answer(#"{"code":404}"#, code: 404)
        answer("busy", code: 503)
        var failed: Error?
        do {
            _ = try await library().find("Song", artist: "Artist", album: "Album", durationMs: 201_000)
        } catch {
            failed = error
        }
        #expect(failed is OnlineLyricsError)
    }

    @Test func plainLyricsStandWhenTheSearchFails() async throws {
        answer(#"{"id":9,"trackName":"Song","artistName":"Artist","plainLyrics":"Plain words"}"#)
        answer("busy", code: 503)
        let found = try await library().find("Song", artist: "Artist", album: "Album", durationMs: 201_000)
        #expect(found?.lines.count == 1)
        #expect(found?.lines.first?.text == "Plain words")
    }

    @Test func noExactMatchIsNoCopy() async throws {
        answer(#"{"code":404}"#, code: 404)
        #expect(try await library().exact("Song", artist: "Artist", album: "", durationMs: 0) == nil)
    }

    @Test func theSongsCopiesKeepEveryVersionOfItByItsArtist() async throws {
        answer(search)
        let copies = try await library().copiesOf("Song", artist: "Artist", album: "Album", durationMs: 201_000)
        // Other songs, other artists' songs and copies with no words are left out; a remix stays,
        // named, since the listener picks. Timed copies come first, the same album first among
        // them.
        #expect(copies.map(\.id) == [4, 1, 3, 2])
        #expect(copies[2].title == "Song (Club Remix)")
        #expect(copies.last!.lyrics.synced == false)
        let request = server.takeRequest()
        #expect(encodedPath(request) == "/api/search")
        #expect(queryParameter(request, "track_name") == "Song")
        #expect(queryParameter(request, "artist_name") == "Artist")
    }

    @Test func aSearchByHandTakesWhateverTheLibraryFinds() async throws {
        answer(search)
        let copies = try await library().search("  song artist ")
        // Only copies with no words at all are left out.
        #expect(copies.map(\.id) == [1, 2, 3, 4, 5, 6])
        let request = server.takeRequest()
        #expect(encodedPath(request) == "/api/search")
        #expect(queryParameter(request, "q") == "song artist")
        #expect(queryParameter(request, "track_name") == nil)
    }

    @Test func aPickedCopyIsFetchedAgainByItsNumber() async throws {
        answer(#"{"id":4,"trackName":"Song","artistName":"Artist","syncedLyrics":"[00:01.00] Same album"}"#)
        let lyrics = try #require(try await library().byId(4))
        #expect(lyrics.lines.first?.text == "Same album")
        #expect(lyrics.onlineId == 4)
        #expect(encodedPath(server.takeRequest()) == "/api/get/4")

        answer(#"{"code":404}"#, code: 404)
        #expect(try await library().byId(5) == nil)
    }

    @Test func theAutomaticLookupStillTakesOnlyTheSameRecording() async throws {
        // Nothing timed from the exact lookup, so the search is asked: the remix and the other
        // songs never stand in.
        answer(#"{"id":2,"trackName":"Song","artistName":"Artist","plainLyrics":"Plain words"}"#)
        answer(search)
        let found = try #require(try await library().find("Song", artist: "Artist", album: "Album", durationMs: 201_000))
        #expect(found.lines.first?.text == "Same album")
        #expect(found.onlineId == 4)
    }
}
