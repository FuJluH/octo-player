import Foundation
import Testing
@testable import OctoKit

@Suite struct StandInCoversTest {
    private let record: [UInt8] = (0..<40).map { UInt8(truncatingIfNeeded: $0 * 7) }
    private var standIns: StandIns { StandIns([record.count: [Hashes.sha256Hex(record)]]) }

    @Test func theStandInIsKnownByItsBytes() {
        #expect(standIns.isStandIn(Array(record)))
    }

    @Test func aPictureOfTheSameLengthIsARealOne() {
        var cover = record
        cover[10] = 1
        #expect(!standIns.isStandIn(cover))
    }

    @Test func onlyAPictureOfAStandInsLengthIsReadThrough() {
        #expect(standIns.mayBe(40))
        #expect(!standIns.mayBe(39))
        #expect(!standIns.mayBe(41))
        #expect(!standIns.mayBe(0))
        #expect(standIns.longest == 40)
    }

    @Test func navidromesRecordIsKnown() {
        #expect(standInCovers.mayBe(69_228))
        #expect(standInCovers.longest == 69_228)
        // A real cover that happens to be as long is still a cover.
        #expect(!standInCovers.isStandIn([UInt8](repeating: 0, count: 69_228)))
    }

    @Test func digestsAreLowerCaseHex() {
        // The SHA-256 of "abc", from FIPS 180-2.
        #expect(Hashes.sha256Hex(Array("abc".utf8)) == "ba7816bf8f01cfea414140de5dae2223b00361a396177a9cb410ff61f20015ad")
    }
}
