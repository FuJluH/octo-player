import Foundation
import Testing
@testable import OctoKit

@Suite struct StreamCacheUsedTests {
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
