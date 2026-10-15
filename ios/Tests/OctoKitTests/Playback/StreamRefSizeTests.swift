import Foundation
import Testing
@testable import OctoKit

/// Saved copies in memory: each name with its whole length (nil when not known), and any noted size.
private struct Saved: SavedCopies {
    var copies: [String: Int64?]
    var noted: [String: Int64] = [:]
    var dropped: [String] = []

    init(_ copies: [String: Int64?]) { self.copies = copies }

    func has(_ key: String) -> Bool { copies[key] != nil }
    func length(_ key: String) -> Int64? { copies[key] ?? nil }
    func notedSize(_ key: String) -> Int64? { noted[key] }

    mutating func note(_ key: String, size: Int64) { noted[key] = size }

    mutating func drop(_ key: String) {
        copies[key] = nil
        noted[key] = nil
        dropped.append(key)
    }
}

/// A server song's file size in its queue address and its saved name, so a file the server swapped
/// under the same id is never played from an old copy.
@Suite struct StreamRefSizeTests {
    let flac = StreamRef(sourceId: "server:music.example", serverId: "tr-42", mimeType: "audio/flac", bitrate: 900_000)
    let raw = StreamRequest(nil)

    func sized(_ size: Int64) -> StreamRef {
        var ref = flac
        ref.size = size
        return ref
    }

    @Test func theFileSizeReadsBackToo() {
        let ref = sized(31_000_000)
        #expect(parseStreamUri(streamUri(ref)) == ref)
        let pinned = ref.pin(StreamRequest(192))
        #expect(parseStreamUri(streamUri(pinned)) == pinned)
        // An address from before sizes were carried has none.
        #expect(parseStreamUri("octo-stream://song/tr-42?source=server%3Aa&mime=audio%2Fflac")?.size == nil)
        // A size of nothing is no size.
        #expect(StreamRef(sourceId: nil, serverId: "1", mimeType: nil, bitrate: nil, size: 0).size == nil)
    }

    @Test func aNewFileUnderTheSameIdIsItsOwnCopy() {
        let live = streamCacheKey("server:a", sized(31_000_000), raw)
        let studio = streamCacheKey("server:a", sized(28_500_000), raw)
        #expect(live == "server:a|tr-42|audio/flac|raw|31000000")
        #expect(live != studio)
        // A song with no size, such as one found online, keeps the plain name.
        #expect(streamCacheKey("server:a", flac, raw) == "server:a|tr-42|audio/flac|raw")
    }

    @Test func aKeyLosesItsSizeOnlyWhenItHasOne() {
        #expect(cacheKeyWithoutSize("server:a|tr-42|audio/flac|raw|31000000") == "server:a|tr-42|audio/flac|raw")
        #expect(cacheKeyWithoutSize("server:a|tr-42|audio/flac|192|31000000") == "server:a|tr-42|audio/flac|192")
        #expect(cacheKeyWithoutSize("server:a|tr-42|audio/flac|192") == "server:a|tr-42|audio/flac|192")
        #expect(cacheKeyWithoutSize("server:a|tr-42|unknown|raw") == "server:a|tr-42|unknown|raw")
        #expect(cacheKeyWithoutSize("plain") == "plain")
    }

    @Test func theSongOfASavedKeyLeavesTheSizeOut() {
        #expect(savedSongOf("server:a|tr-42|audio/flac|raw|31000000") == "server:a|tr-42")
        #expect(savedSongOf("server:a|tr-42|audio/flac|192") == "server:a|tr-42")
    }

    @Test func aCopyUnderTheFullNameIsUsed() {
        let ref = sized(28_500_000)
        let full = streamCacheKey("server:a", ref, raw)
        var saved = Saved([full: 28_500_000])
        #expect(savedCopyKey("server:a", ref, raw, &saved) == full)
        #expect(saved.dropped.isEmpty)
    }

    @Test func anOlderCopyOfTheSameFileStillPlays() {
        let older = streamCacheKey("server:a", flac, raw)
        var saved = Saved([older: 31_000_000])
        #expect(savedCopyKey("server:a", sized(31_000_000), raw, &saved) == older)
        #expect(saved.noted[older] == 31_000_000)
        #expect(saved.dropped.isEmpty)
    }

    @Test func anOlderCopyOfAnotherFileIsLetGoAndTheNewFileLoads() {
        // The live take was saved; the server now has the studio one under the same id.
        let ref = sized(28_500_000)
        let older = streamCacheKey("server:a", flac, raw)
        var saved = Saved([older: 31_000_000])
        #expect(savedCopyKey("server:a", ref, raw, &saved) == streamCacheKey("server:a", ref, raw))
        #expect(saved.dropped == [older])
    }

    @Test func anOlderCopyOfUnknownLengthIsLetGo() {
        let older = streamCacheKey("server:a", flac, raw)
        var saved = Saved([older: nil])
        // Nothing says the copy is of the file the server has now.
        #expect(savedCopyKey("server:a", sized(31_000_000), raw, &saved) == streamCacheKey("server:a", sized(31_000_000), raw))
        #expect(saved.dropped == [older])
    }

    @Test func anOlderSmallerCopyIsKeptUntilItsFileChanges() {
        let small = StreamRequest(192)
        let older = streamCacheKey("server:a", flac, small)
        var saved = Saved([older: 7_000_000])
        // Nothing tells which file it came from, so it plays, and the size is noted.
        #expect(savedCopyKey("server:a", sized(31_000_000), small, &saved) == older)
        #expect(saved.noted[older] == 31_000_000)
        #expect(savedCopyKey("server:a", sized(31_000_000), small, &saved) == older)
        // Then the file is swapped: the noted size no longer matches.
        let swapped = sized(28_500_000)
        #expect(savedCopyKey("server:a", swapped, small, &saved) == streamCacheKey("server:a", swapped, small))
        #expect(saved.dropped == [older])
    }

    @Test func aSongWithNoSizeUsesThePlainName() {
        let plain = streamCacheKey("server:a", flac, raw)
        var saved = Saved([plain: 5])
        #expect(savedCopyKey("server:a", flac, raw, &saved) == plain)
        #expect(saved.dropped.isEmpty && saved.noted.isEmpty)
    }

    @Test func choosingASizeLooksUnderTheNamesTheSavedCopiesHave() {
        // A whole copy of the file as it is, saved before names carried sizes, still wins over streaming 128.
        let ref = sized(31_000_000)
        let older = streamCacheKey("server:a", flac, raw)
        var saved = Saved([older: 31_000_000])
        var keys: [StreamRequest: String] = [:]
        for request in requestVariants(ref) { keys[request] = savedCopyKey("server:a", ref, request, &saved) }
        let snapshot = saved
        #expect(chooseRequest("server:a", ref, .mp3(kbps: 128), fullySaved: { snapshot.has($0) }, keyOf: { keys[$0]! }) == raw)
        // Once the file is swapped, the old copy is not picked.
        let swapped = sized(28_500_000)
        keys = [:]
        for request in requestVariants(swapped) { keys[request] = savedCopyKey("server:a", swapped, request, &saved) }
        let after = saved
        #expect(chooseRequest("server:a", swapped, .mp3(kbps: 128), fullySaved: { after.has($0) }, keyOf: { keys[$0]! }) == StreamRequest(128))
    }

    @Test func aServerSongCarriesItsFileSizeIntoTheQueue() throws {
        let json = #"{"id":"tr-42","title":"Nightcall","contentType":"audio/flac","bitRate":900,"size":31000000}"#
        let song = try JSONDecoder().decode(Song.self, from: Data(json.utf8))
        #expect(song.size == 31_000_000)
        let item = queueItem(song, sourceId: "server:a", quality: .original)
        #expect(parseStreamUri(item.uri)?.size == 31_000_000)
        // A song found online keeps the plain name.
        var find = song
        find.isExternal = true
        #expect(parseStreamUri(queueItem(find, sourceId: "server:a", quality: .original).uri)?.size == nil)
        // A size sent as text or with no size at all.
        let text = try JSONDecoder().decode(Song.self, from: Data(#"{"id":"1","size":"2048"}"#.utf8))
        #expect(text.size == 2_048)
        #expect(try JSONDecoder().decode(Song.self, from: Data(#"{"id":"1"}"#.utf8)).size == nil)
    }
}
