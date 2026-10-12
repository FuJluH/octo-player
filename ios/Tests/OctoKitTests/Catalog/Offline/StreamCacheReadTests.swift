import Foundation
import Testing
@testable import OctoKit

@Suite struct StreamCacheReadTests {
    func ranges(_ parts: [Range<Int64>]) -> ByteRanges {
        var out = ByteRanges()
        for part in parts { out.insert(part) }
        return out
    }

    @Test func theServerIsAskedOnlyUpToTheNextSavedPart() {
        let saved = ranges([0..<100, 300..<400])
        #expect(streamCacheGapEnd(saved, from: 100) == 299)
        #expect(streamCacheGapEnd(saved, from: 250) == 299)
    }

    @Test func pastTheLastSavedPartTheRestOfTheSongIsAskedFor() {
        let saved = ranges([0..<100, 300..<400])
        #expect(streamCacheGapEnd(saved, from: 400) == nil)
        #expect(streamCacheGapEnd(ByteRanges(), from: 0) == nil)
    }

    @Test func theUsedAmountIsTheSavedPiecesOnly() {
        let spans = [
            StreamCacheSpan(key: "a", position: 0, length: 100, lastTouchedMs: 0),
            StreamCacheSpan(key: "a", position: 300, length: 50, lastTouchedMs: 0),
            StreamCacheSpan(key: "b", position: 0, length: 25, lastTouchedMs: 0),
        ]
        #expect(streamCacheUsedBytes(spans) == 175)
        #expect(streamCacheUsedBytes([]) == 0)
    }
}
