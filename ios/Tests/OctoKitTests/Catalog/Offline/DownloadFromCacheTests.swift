import Foundation
import Testing
@testable import OctoKit

@Suite struct DownloadFromCacheTests {
    @Test func aDownloadFindsTheSongPlayedAtTheSameSize() {
        let ref = StreamRef(sourceId: "s1", serverId: "42", mimeType: "audio/flac", bitrate: 900_000)
        let played = streamCacheKey("s1", ref, phoneRequest(ref.mimeType, ref.bitrate, .mp3(kbps: 192)))
        #expect(downloadCacheKey(sourceId: "s1", serverId: "42", mimeType: "audio/flac", maxKbps: 192) == played)
        let original = streamCacheKey("s1", ref, phoneRequest(ref.mimeType, ref.bitrate, .original))
        #expect(downloadCacheKey(sourceId: "s1", serverId: "42", mimeType: "audio/flac", maxKbps: nil) == original)
    }

    @Test func anotherSizeIsAnotherSong() {
        #expect(downloadCacheKey(sourceId: "s1", serverId: "42", mimeType: "audio/flac", maxKbps: 128)
            != downloadCacheKey(sourceId: "s1", serverId: "42", mimeType: "audio/flac", maxKbps: nil))
    }

    @Test func downloadsSayTheyAreOfflineCopies() {
        #expect(octoPurposeHeader == "X-Octo-Purpose")
        #expect(octoPurposeOffline == "offline")
    }
}
