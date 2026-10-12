import Foundation
import Testing
@testable import OctoKit

@Suite struct OfflineMarksTest {
    func track(_ id: String, onPhone: Bool, nativeId: String? = nil) -> LibraryTrack {
        LibraryTrack(id: id, sourceId: "server:music.example", nativeId: nativeId ?? id, title: "", searchKey: "", sortKey: "",
                     artist: "", artistId: "", album: "", albumId: "", trackNo: nil, discNo: nil, year: nil, durationMs: 0,
                     addedAt: 0, mimeType: "audio/flac", sizeBytes: nil, artwork: nil, uri: nil, onPhone: onPhone)
    }

    @Test func aSavedKeyNamesItsSong() {
        // A saved song's key: its server, its id there, its type and the size asked for.
        let key = "server:music.example|tr-1|audio/flac|192"
        #expect(savedSongOf(key) == savedSong("server:music.example", "tr-1"))
    }

    @Test func withNoConnectionOnlySongsThatCannotPlayAreFaint() {
        let marks = OfflineMarks(downloaded: ["down"], offline: true, saved: [savedSong("server:music.example", "cached")])
        #expect(!marks.isOutOfReach(track("phone", onPhone: true)))
        #expect(!marks.isOutOfReach(track("down", onPhone: false)))
        #expect(!marks.isOutOfReach(track("x", onPhone: false, nativeId: "cached")))
        #expect(marks.isOutOfReach(track("stream", onPhone: false)))
        // With a connection, everything can play.
        var online = marks
        online.offline = false
        #expect(!online.isOutOfReach(track("stream", onPhone: false)))
    }
}
