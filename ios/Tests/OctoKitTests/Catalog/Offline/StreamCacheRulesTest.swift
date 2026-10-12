import Foundation
import Testing
@testable import OctoKit

@Suite struct StreamCacheRulesTest {
    func span(_ key: String, _ position: Int64, _ length: Int64, touched: Int64 = 0) -> StreamCacheSpan {
        StreamCacheSpan(key: key, position: position, length: length, lastTouchedMs: touched)
    }

    @Test func aSongIsSavedWholeOnlyWhenItsPiecesCoverItsLength() {
        let pieces = [span("a", 0, 400), span("a", 400, 600)]
        #expect(streamCacheIsFullySaved(enabled: true, contentLength: 1_000, spans: pieces))
        #expect(!streamCacheIsFullySaved(enabled: true, contentLength: 1_001, spans: pieces))
        // A gap in the middle.
        #expect(!streamCacheIsFullySaved(enabled: true, contentLength: 1_000, spans: [span("a", 0, 400), span("a", 500, 500)]))
        // The start missing.
        #expect(!streamCacheIsFullySaved(enabled: true, contentLength: 600, spans: [span("a", 400, 600)]))
    }

    @Test func aSongOfUnknownLengthIsNeverSavedWhole() {
        #expect(!streamCacheIsFullySaved(enabled: true, contentLength: nil, spans: [span("a", 0, 1_000)]))
        #expect(!streamCacheIsFullySaved(enabled: true, contentLength: 0, spans: [span("a", 0, 1_000)]))
    }

    @Test func nothingCountsWhileSongsAreNotKept() {
        #expect(!streamCacheIsFullySaved(enabled: false, contentLength: 1_000, spans: [span("a", 0, 1_000)]))
        #expect(!streamCacheIsPartlySaved(enabled: false, spans: [span("a", 0, 10)]))
        #expect(streamCacheIsPartlySaved(enabled: true, spans: [span("a", 300, 10)]))
        #expect(!streamCacheIsPartlySaved(enabled: true, spans: []))
        #expect(streamCacheFullySavedKeys(enabled: false, lengths: ["a": 10], spans: [span("a", 0, 10)]).isEmpty)
        #expect(!streamCacheEnabled(.off) && streamCacheEnabled(.gb2))
    }

    @Test func theWholeSongsAreFoundByName() {
        let spans = [span("a", 0, 10), span("b", 0, 5), span("c", 0, 10)]
        #expect(streamCacheFullySavedKeys(enabled: true, lengths: ["a": 10, "b": 10], spans: spans) == ["a"])
    }

    @Test func theLeastRecentlyPlayedGoFirstUntilItFits() {
        let spans = [span("new", 0, 300, touched: 30), span("old", 0, 300, touched: 10), span("mid", 0, 300, touched: 20)]
        #expect(streamCacheEvictions(spans, limitBytes: 600).map(\.key) == ["old"])
        #expect(streamCacheEvictions(spans, limitBytes: 300).map(\.key) == ["old", "mid"])
        #expect(streamCacheEvictions(spans, limitBytes: 900).isEmpty)
        // Room for a song on its way.
        #expect(streamCacheEvictions(spans, limitBytes: 900, incomingBytes: 100).map(\.key) == ["old"])
    }

    @Test func nothingGoesBeforeTheSizeIsKnown() {
        #expect(streamCacheEvictions([span("a", 0, Int64(1) << 40)], limitBytes: nil).isEmpty)
    }
}
