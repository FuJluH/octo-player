import Foundation
import Testing
@testable import OctoKit

/// A server can send a song as another file than it listed (a whole FLAC for a listed preview):
/// what is saved or held of one file is never continued with another's bytes.
@Suite struct StreamShapeTests {
    @Test func anAnswerSaysItsTypeAndWholeLength() {
        let part = streamShapeOf(status: 206, contentType: "audio/flac; charset=binary", contentRange: "bytes 100-199/31415926",
                                 contentLength: 100)
        #expect(part == StreamShape(type: "audio/flac", total: 31_415_926))
        let whole = streamShapeOf(status: 200, contentType: "audio/mp4", contentRange: nil, contentLength: 4_000_000)
        #expect(whole == StreamShape(type: "audio/mp4", total: 4_000_000))
        // A stream made on the way names no length, and plain bytes name no file.
        #expect(streamShapeOf(status: 200, contentType: "application/octet-stream", contentRange: nil, contentLength: -1)
            == StreamShape(type: nil, total: nil))
        #expect(streamShapeOf(status: 206, contentType: "audio/mpeg", contentRange: "bytes 0-99/*", contentLength: 100).total == nil)
    }

    @Test func anotherTypeOrLengthIsAnotherFile() {
        let preview = StreamShape(type: "audio/mp4", total: 4_000_000)
        #expect(preview.differs(from: StreamShape(type: "audio/flac", total: 31_000_000)))
        #expect(preview.differs(from: StreamShape(type: "audio/mp4", total: 4_100_000)))
        #expect(!preview.differs(from: StreamShape(type: "AUDIO/MP4", total: 4_000_000)))
        // What one side leaves out is no difference: a stream with no length is not another file.
        #expect(!preview.differs(from: StreamShape(type: "audio/mp4", total: nil)))
        #expect(!StreamShape(type: nil, total: nil).differs(from: StreamShape(type: "audio/flac", total: 31_000_000)))
    }

    @Test func aSavedPreviewGoesWhenTheServerSendsAFlac() {
        var index = StreamCacheIndex(enabled: true)
        index.describe("find", contentLength: 4_000_000, mimeType: "audio/mp4", nowMs: 1)
        index.wrote("find", offset: 0, count: 1_000_000, freshFile: true, nowMs: 1)
        let same = index.answered("find", StreamShape(type: "audio/mp4", total: 4_000_000))
        #expect(!same)
        #expect(index.isPartlySaved("find"))
        let flac = index.answered("find", StreamShape(type: "audio/flac", total: 31_000_000))
        #expect(flac)
        #expect(index.entries["find"] == nil)
        #expect(!index.isPartlySaved("find"))
        let dropped = index.takeDropped()
        #expect(dropped == ["find"])
        // Nothing saved: nothing to let go.
        let none = index.answered("other", StreamShape(type: "audio/flac", total: 1))
        #expect(!none)
    }

    @Test func aFindAsksWithTheCapLikeALosslessSong() {
        // The listed 128 kbps is the preview's: the server may send a whole FLAC in its place.
        let ref = findStreamRef(sourceId: "server:a", serverId: "x1", mimeType: "audio/mp4")
        #expect(ref.bitrate == nil)
        #expect(ref.request(.mp3(kbps: 192)) == StreamRequest(192))
        // Listed with its preview's bitrate, the same song would have asked for the file as it is.
        #expect(StreamRef(sourceId: "server:a", serverId: "x1", mimeType: "audio/mp4", bitrate: 128_000).request(.mp3(kbps: 192))
            == StreamRequest(nil))
    }

    @Test func anotherFileMidSongIsNotShownAsItsOwnFailure() {
        #expect(playFailureOf(PlayError(.sourceChanged)) == .other)
    }
}
