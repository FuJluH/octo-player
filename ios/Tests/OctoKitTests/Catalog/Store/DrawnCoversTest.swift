import Foundation
import Testing
@testable import OctoKit

@Suite struct DrawnCoversTest {
    private let station = "or3kZ9QpLmN2xY7wV1bC0a"
    private let mix = "og8Hf2Kd9LzQw3Rt5Yu7Ip"
    private let day: Int64 = 24 * 60 * 60 * 1000

    // 2026-09-29T12:00Z, on day 20725.
    private let noon: Int64 = 1_790_683_200_000

    @Test func octoStationsAndMixesAreDrawn() {
        #expect(isDrawnCoverId(station))
        #expect(isDrawnCoverId(mix))
    }

    @Test func libraryCoversAreNot() {
        // Navidrome's cover ids, a Navidrome playlist's id, and Octo's fixed placeholder.
        for id in ["al-27olR01OlsFec4YYFzCF6M_6ab000f2", "pl-08q5UDZiuD3n5Ct2m6J6Tu_0", "08q5UDZiuD3n5Ct2m6J6Tu", "mf-1", "octo-radio", "tr-9"] {
            #expect(!isDrawnCoverId(id), "\(id)")
        }
    }

    @Test func onlyTheWholeShapeCounts() {
        #expect(!isDrawnCoverId("or3kZ9QpLmN2xY7wV1bC0"))
        #expect(!isDrawnCoverId("or3kZ9QpLmN2xY7wV1bC0ab"))
        #expect(!isDrawnCoverId("or3kZ9QpLmN2xY7wV1bC-a"))
        #expect(!isDrawnCoverId("oa3kZ9QpLmN2xY7wV1bC0a"))
        #expect(!isDrawnCoverId(""))
    }

    @Test func aDayIsOneBucketInUtc() {
        #expect(drawnCoverDay(0) == 0)
        #expect(drawnCoverDay(day - 1) == 0)
        #expect(drawnCoverDay(day) == 1)
        #expect(drawnCoverDay(noon) == 20725)
    }

    @Test func theStampCarriesTheVersionAndTheDay() {
        #expect(drawnCoverStamp(noon) == "v\(drawnCoverVersion):20725")
        #expect(drawnCoverStamp(20725 * day) == drawnCoverStamp(20726 * day - 1))
        #expect(drawnCoverStamp(20725 * day) != drawnCoverStamp(20726 * day))
    }
}
