import Foundation
import Testing
@testable import OctoKit

@Suite struct ServerArtworkTest {
    let library = ArtworkRef.server(sourceId: "server:music.example", coverId: "al-1")
    let found = ArtworkRef.server(sourceId: "server:music.example", coverId: "al-1", online: true)
    let station = ArtworkRef.server(sourceId: "server:music.example", coverId: "or3kZ9QpLmN2xY7wV1bC0a")
    let day: Int64 = 24 * 60 * 60 * 1000

    // 2026-09-29T12:00Z, on day 20725.
    let noon: Int64 = 1_790_683_200_000

    @Test func libraryCoversKeepTheKeysTheyWereCachedUnder() {
        // The same keys as before covers found online were kept apart, so nothing already on the
        // phone is fetched again.
        #expect(serverCoverKey(library) == "server-art:server:music.example|al-1")
        #expect(serverCoverDiskKey(library, px: 300) == "server-art:server:music.example|al-1|300")
    }

    @Test func coversFoundOnlineStartAfreshUnderTheirVersion() {
        #expect(serverCoverKey(found) == "online-art:v\(onlineCoverVersion):server:music.example|al-1")
        #expect(serverCoverDiskKey(found, px: 300) == "online-art:v\(onlineCoverVersion):server:music.example|al-1|300")
        #expect(onlineCoverVersion >= 2)
    }

    @Test func theSameCoverIdOnlineAndInTheLibraryNeverShareACacheEntry() {
        #expect(serverCoverKey(library) != serverCoverKey(found))
        for px in [150, 300, 600, 1200] { #expect(serverCoverDiskKey(library, px: px) != serverCoverDiskKey(found, px: px)) }
    }

    @Test func aStationsCoverIsKeptUnderItsVersionAndTheDay() {
        #expect(serverCoverKey(station, nowMs: noon)
            == "drawn-art:v\(drawnCoverVersion):20725:server:music.example|or3kZ9QpLmN2xY7wV1bC0a")
        #expect(serverCoverDiskKey(station, px: 300, nowMs: noon)
            == "drawn-art:v\(drawnCoverVersion):20725:server:music.example|or3kZ9QpLmN2xY7wV1bC0a|300")
    }

    @Test func aStationsCoverIsAskedForAgainTheNextDay() {
        #expect(serverCoverKey(station, nowMs: 20725 * day) == serverCoverKey(station, nowMs: 20726 * day - 1))
        #expect(serverCoverKey(station, nowMs: 20725 * day) != serverCoverKey(station, nowMs: 20726 * day))
    }

    @Test func aStationsCoverNeverUsesTheKeyItWasCachedUnderForever() {
        // What the phone kept a station's cover under before, for good.
        #expect(serverCoverKey(station, nowMs: noon) != "server-art:server:music.example|or3kZ9QpLmN2xY7wV1bC0a")
    }

    @Test func libraryAndOnlineCoversDoNotChangeWithTheDay() {
        #expect(serverCoverKey(library, nowMs: 0) == serverCoverKey(library, nowMs: noon))
        #expect(serverCoverKey(found, nowMs: 0) == serverCoverKey(found, nowMs: noon))
    }

    @Test func aRealCoverIsNotAStandInAndIsLeftWholeForTheDecoder() {
        let bytes = (0..<120_000).map { UInt8($0 % 251) }
        #expect(!serverCoverMayBeStandIn(length: Int64(bytes.count)))
        #expect(!serverCoverIsStandIn(bytes))
        #expect(bytes.count == 120_000)
    }

    @Test func aCoverAsLongAsTheStandInIsReadThroughAndStillWhole() {
        let bytes = [UInt8](repeating: 7, count: 69_228)
        #expect(serverCoverMayBeStandIn(length: Int64(bytes.count)))
        #expect(!serverCoverIsStandIn(bytes))
        #expect(bytes.allSatisfy { $0 == 7 } && bytes.count == 69_228)
    }

    @Test func aCoverWithAFallbackIsKeptUnderItsOwnKey() {
        let withFallback = ArtworkRef.server(sourceId: "server:music.example", coverId: "al-1", fallbackId: "mf-2")
        #expect(serverCoverKey(library) == serverCoverKey(withFallback))
    }

    @Test func coversAreAskedForAtTheSmallestSizeThatServes() {
        #expect(serverCoverSize(wanted: 100) == 150)
        #expect(serverCoverSize(wanted: 150) == 150)
        #expect(serverCoverSize(wanted: 151) == 300)
        #expect(serverCoverSize(wanted: 2000) == 1200)
        #expect(serverCoverSize(wanted: 0) == 600)
    }

    @Test func theFallbackIsTriedAfterTheCoverFromTheSameServer() throws {
        let art = ArtworkRef.server(sourceId: "server:music.example", coverId: "al-1", fallbackId: "mf-2")
        let tries = try #require(serverCoverTries(art, signedInSource: "server:music.example", wantedPx: 280))
        #expect(tries == [
            ServerCoverTry(coverId: "al-1", px: 300, diskKey: "server-art:server:music.example|al-1|300"),
            ServerCoverTry(coverId: "mf-2", px: 300, diskKey: "server-art:server:music.example|mf-2|300"),
        ])
        // A size the server answered with its stand-in this run is not asked for again.
        let left = serverCoverTries(art, signedInSource: "server:music.example", wantedPx: 280,
                                    standIns: ["server-art:server:music.example|al-1|300"])
        #expect(left?.map(\.coverId) == ["mf-2"])
        // Another server's cover, or a phone picture, is not drawn here.
        #expect(serverCoverTries(art, signedInSource: "server:other", wantedPx: 280) == nil)
        #expect(serverCoverTries(.device(key: "k", uri: "u"), signedInSource: "server:music.example", wantedPx: 280) == nil)
        #expect(serverCoverKey(.device(key: "k", uri: "u")) == nil)
    }
}
