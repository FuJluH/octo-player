import Foundation
import Testing
@testable import OctoKit

@Suite struct StreamQualityMoveTests {
    @Test func theOldSizeMovesOnce() {
        #expect(movedStreamQuality(oldKbps: 128, alreadyMoved: false, sizesChosen: false) == .mp3(kbps: 128))
        #expect(movedStreamQuality(oldKbps: 0, alreadyMoved: false, sizesChosen: false) == .original)
        #expect(movedStreamQuality(oldKbps: 128, alreadyMoved: true, sizesChosen: false) == nil)
    }

    @Test func nothingMovesWithoutAnOldSize() {
        #expect(movedStreamQuality(oldKbps: nil, alreadyMoved: false, sizesChosen: false) == nil)
    }

    /// Only mobile data was set to 128 kbps, and the size in use was written back as the old
    /// value: Wi-Fi stays as it was, whether or not the move was already done.
    @Test func aChosenSizeIsNeverOverwritten() {
        #expect(movedStreamQuality(oldKbps: 128, alreadyMoved: false, sizesChosen: true) == nil)
        #expect(movedStreamQuality(oldKbps: 128, alreadyMoved: true, sizesChosen: true) == nil)
    }
}
