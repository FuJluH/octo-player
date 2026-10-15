import Foundation
import Testing
@testable import OctoKit

/// The list of saved songs: what counts as saved, what goes when room runs out, and how a song
/// whose server file was swapped is let go.
@Suite struct StreamCacheIndexTest {
    let flac = StreamRef(sourceId: "server:a", serverId: "tr-42", mimeType: "audio/flac", bitrate: 900_000)

    func sized(_ size: Int64) -> StreamRef {
        var ref = flac
        ref.size = size
        return ref
    }

    /// A song saved whole under `key`, `length` bytes long, last played at `touched`.
    func whole(_ index: inout StreamCacheIndex, _ key: String, _ length: Int64, touched: Int64 = 0, described: Bool = true) {
        if described { index.describe(key, contentLength: length, mimeType: "audio/flac", nowMs: touched) }
        index.wrote(key, offset: 0, count: length, freshFile: true, nowMs: touched)
    }

    @Test func aSongSavedAsItPlaysCountsAsWhole() {
        var index = StreamCacheIndex(enabled: true)
        index.describe("a", contentLength: 1_000, mimeType: "audio/flac", nowMs: 1)
        index.wrote("a", offset: 0, count: 400, freshFile: true, nowMs: 2)
        #expect(index.isPartlySaved("a") && !index.isFullySaved("a"))
        index.wrote("a", offset: 400, count: 600, freshFile: false, nowMs: 3)
        #expect(index.isFullySaved("a"))
        #expect(index.entries["a"]?.pieces == [[0, 1_000]])
        #expect(index.usedBytes() == 1_000)
    }

    @Test func aSongDescribedBeforeItsFirstBytesKeepsItsLength() {
        // The answer's length is noted, then a check for the song's file finds none yet: the
        // length must not be forgotten, or the song would never count as whole.
        var index = StreamCacheIndex(enabled: true)
        index.describe("a", contentLength: 1_000, mimeType: "audio/flac", nowMs: 1)
        index.fileGone("a")
        index.wrote("a", offset: 0, count: 1_000, freshFile: true, nowMs: 2)
        #expect(index.entries["a"]?.contentLength == 1_000)
        #expect(index.entries["a"]?.mimeType == "audio/flac")
        #expect(index.isFullySaved("a"))
    }

    @Test func aSongWhoseFileIsGoneIsForgotten() {
        var index = StreamCacheIndex(enabled: true)
        whole(&index, "a", 1_000)
        index.fileGone("a")
        #expect(index.entries["a"] == nil)
        // A new file starts over: pieces listed for the old one no longer count.
        whole(&index, "b", 1_000)
        index.wrote("b", offset: 500, count: 100, freshFile: true, nowMs: 5)
        #expect(index.entries["b"]?.pieces == [[500, 100]])
        #expect(!index.isFullySaved("b"))
    }

    @Test func aStreamThatEndedShortTakesItsRealLength() {
        // A stream made on the way says it will be longer than it turns out.
        var index = StreamCacheIndex(enabled: true)
        index.describe("a", contentLength: 1_200, mimeType: "audio/mpeg", nowMs: 1)
        index.wrote("a", offset: 0, count: 1_150, freshFile: true, nowMs: 2)
        #expect(!index.isFullySaved("a"))
        index.describe("a", contentLength: 1_150, mimeType: nil, nowMs: 3)
        #expect(index.isFullySaved("a"))
        #expect(index.entries["a"]?.mimeType == "audio/mpeg")
    }

    @Test func nothingIsSavedWhileSongsAreNotKept() {
        var index = StreamCacheIndex()
        whole(&index, "a", 1_000)
        #expect(index.entries.isEmpty)
        #expect(!index.isPartlySaved("a") && index.savedRun("a", from: 0) == 0)
    }

    @Test func theLeastRecentlyPlayedSongsGoWholeToMakeRoom() {
        var index = StreamCacheIndex(enabled: true)
        whole(&index, "old", 300, touched: 10)
        whole(&index, "mid", 300, touched: 20)
        whole(&index, "new", 300, touched: 30)
        // A song played again is the last to go.
        index.touch("old", nowMs: 40)
        #expect(index.evictions(limitBytes: 900, incoming: 100) == ["mid"])
        #expect(index.evictions(limitBytes: 900, incoming: 400) == ["mid", "new"])
        // The song being saved now never goes.
        #expect(index.evictions(limitBytes: 900, incoming: 400, keeping: "new") == ["mid"])
        #expect(index.evictions(limitBytes: nil, incoming: 10_000).isEmpty)
        index.remove(["mid"])
        #expect(index.fullySavedKeys() == ["old", "new"])
    }

    @Test func theRequestPickedPlaysTheSavedCopyOfTheFileTheServerHasNow() {
        var index = StreamCacheIndex(enabled: true)
        let ref = sized(31_000_000)
        let full = streamCacheKey("server:a", ref, StreamRequest(nil))
        whole(&index, full, 31_000_000)
        // On mobile data, 192 kbps would be asked for, but the whole file as it is is saved.
        let picked = pickSavedRequest("server:a", ref, .mp3(kbps: 192), &index)
        #expect(picked.request == StreamRequest(nil))
        #expect(picked.key == full)
        // Nothing saved: what the connection asks for, under its full name.
        var empty = StreamCacheIndex(enabled: true)
        let fresh = pickSavedRequest("server:a", ref, .mp3(kbps: 192), &empty)
        #expect(fresh.request == StreamRequest(192))
        #expect(fresh.key == streamCacheKey("server:a", ref, StreamRequest(192)))
        // A pinned request stays.
        let pinned = pickSavedRequest("server:a", ref.pin(StreamRequest(128)), .original, &index)
        #expect(pinned.request == StreamRequest(128))
    }

    @Test func aCopySavedBeforeNamesCarriedSizesStillPlaysWhileItIsTheFile() {
        var index = StreamCacheIndex(enabled: true)
        let older = streamCacheKey("server:a", flac, StreamRequest(nil))
        whole(&index, older, 31_000_000)
        let picked = pickSavedRequest("server:a", sized(31_000_000), .original, &index)
        #expect(picked.key == older)
        #expect(index.notedSize(older) == 31_000_000)
        #expect(index.takeDropped().isEmpty)
    }

    @Test func aCopyOfAFileTheServerSwappedIsLetGo() {
        // The live take was saved and played; the server now has the studio take under the same id.
        var index = StreamCacheIndex(enabled: true)
        let older = streamCacheKey("server:a", flac, StreamRequest(nil))
        whole(&index, older, 31_000_000)
        let studio = sized(28_500_000)
        let picked = pickSavedRequest("server:a", studio, .original, &index)
        #expect(picked.key == streamCacheKey("server:a", studio, StreamRequest(nil)))
        #expect(!index.isPartlySaved(older))
        #expect(index.takeDropped() == [older])
        #expect(index.takeDropped().isEmpty)
        // Saved under its full name, the new file is its own copy from then on.
        whole(&index, picked.key, 28_500_000)
        #expect(pickSavedRequest("server:a", studio, .original, &index).key == picked.key)
        #expect(index.isFullySaved(picked.key))
    }

    @Test func aCopyWhoseLengthWasLostIsCheckedByWhatIsSavedFromTheStart() {
        // A copy saved whole whose length was never noted: its bytes from the start are the file.
        var index = StreamCacheIndex(enabled: true)
        let older = streamCacheKey("server:a", flac, StreamRequest(nil))
        whole(&index, older, 31_000_000, described: false)
        #expect(!index.isFullySaved(older))
        #expect(pickSavedRequest("server:a", sized(31_000_000), .original, &index).key == older)
        // Noting the size gave it its length back, so it plays from the phone.
        #expect(index.isFullySaved(older))
        // Cut short, the same copy is not known to be the file and goes.
        var short = StreamCacheIndex(enabled: true)
        whole(&short, older, 12_000_000, described: false)
        #expect(pickSavedRequest("server:a", sized(31_000_000), .original, &short).key != older)
        #expect(short.takeDropped() == [older])
    }

    @Test func theListReadsBackFromItsOlderShape() throws {
        // Lists written before the server's file size was noted have no such field.
        let json = #"{"k":{"contentLength":10,"mimeType":"audio/flac","pieces":[[0,10]],"lastTouchedMs":5}}"#
        let entries = try JSONDecoder().decode([String: StreamCacheEntry].self, from: Data(json.utf8))
        let index = StreamCacheIndex(entries: entries, enabled: true)
        #expect(index.isFullySaved("k"))
        #expect(index.notedSize("k") == nil)
    }
}
