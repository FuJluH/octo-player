import Foundation
import Testing
@testable import OctoKit

@Suite struct PrefetchFollowTests {
    @Test func thePlayersRepeatReadsTheSame() {
        #expect(prefetchRepeat(.off) == .off)
        #expect(prefetchRepeat(.one) == .one)
        #expect(prefetchRepeat(.all) == .all)
    }

    @Test func onlyServerSongsAreFetched() {
        let server = streamUri(StreamRef(sourceId: "s1", serverId: "42", mimeType: "audio/flac", bitrate: nil))
        #expect(prefetchIsServerStream(server))
        #expect(!prefetchIsServerStream("file:///var/mobile/song.mp3"))
        #expect(!prefetchIsServerStream("ipod-library://item/item.mp3?id=1"))
        #expect(!prefetchIsServerStream("https://radio.example/stream"))
    }

    /// Repeat one from the player reads as no repeat once the queue is walked.
    @Test func repeatOneFromThePlayerStopsAtTheEnd() {
        #expect(prefetchAhead(playOrder: [0, 1, 2], current: 1, repeatMode: prefetchRepeat(.one), count: 3, fetchable: { _ in true }) == [2])
    }
}
