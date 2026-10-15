import Foundation
import Testing
@testable import OctoKit

@Suite struct ArtworkRefTest {
    /// A server cover's parts, or nil for anything else.
    private func server(_ ref: ArtworkRef?) -> (sourceId: String, coverId: String, online: Bool, fallbackId: String?)? {
        guard case .server(let sourceId, let coverId, let online, let fallbackId) = ref else { return nil }
        return (sourceId, coverId, online, fallbackId)
    }

    @Test func roundTrips() {
        let art = ArtworkRef.device(key: "album:5", uri: "content://media/external/audio/media/9")
        #expect(ArtworkRef.decode(art.encode()) == art)
    }

    @Test func serverCoverRoundTripsWithAPortInItsSource() {
        let art = ArtworkRef.server(sourceId: "server:10.0.0.5:4533", coverId: "al-27olR01OlsFec4YYFzCF6M_6ab000f2")
        #expect(art.encode() == "server:server:10.0.0.5:4533|al-27olR01OlsFec4YYFzCF6M_6ab000f2")
        #expect(ArtworkRef.decode(art.encode()) == art)
    }

    @Test func aCoverFoundOnlineRoundTripsAndStaysOnline() throws {
        let stored = onlineArtwork("server:10.0.0.5:4533", "tr-9")
        #expect(stored == "online:server:10.0.0.5:4533|tr-9")
        let art = try #require(server(ArtworkRef.decode(stored)))
        #expect(art.online)
        #expect(art.sourceId == "server:10.0.0.5:4533")
        #expect(art.coverId == "tr-9")
    }

    @Test func aLibraryCoverIsNotOnline() throws {
        #expect(try #require(server(ArtworkRef.decode("server:server:x|al-1"))).online == false)
    }

    @Test func aStoredStationCoverDecodesAsItWasAndIsDrawn() throws {
        // As the phone has always written a station's cover.
        let stored = "server:server:10.0.0.5:4533|or3kZ9QpLmN2xY7wV1bC0a"
        let art = try #require(ArtworkRef.decode(stored))
        #expect(art == ArtworkRef.server(sourceId: "server:10.0.0.5:4533", coverId: "or3kZ9QpLmN2xY7wV1bC0a"))
        #expect(art.drawn)
        #expect(try #require(server(art)).online == false)
        #expect(art.encode() == stored)
    }

    @Test func libraryAndOnlineCoversAreNotDrawn() throws {
        #expect(try #require(ArtworkRef.decode("server:server:x|al-1")).drawn == false)
        #expect(try #require(ArtworkRef.decode("online:server:x|tr-9")).drawn == false)
        // Something found online is never Octo's own list, whatever its id.
        #expect(ArtworkRef.server(sourceId: "server:x", coverId: "og8Hf2Kd9LzQw3Rt5Yu7Ip", online: true).drawn == false)
    }

    @Test func noCoverIdMeansNoOnlineCover() {
        #expect(onlineArtwork("server:x", nil) == nil)
        #expect(onlineArtwork("server:x", "") == nil)
    }

    @Test func aCoverWithAFallbackRoundTrips() {
        let art = ArtworkRef.server(sourceId: "server:10.0.0.5:4533", coverId: "al-27olR01OlsFec4YYFzCF6M_6ab000f2",
                                    fallbackId: "mf-6vmwLNYasJeYulqr0ZxrZJ_2298d43e")
        #expect(art.encode() == "server:server:10.0.0.5:4533|al-27olR01OlsFec4YYFzCF6M_6ab000f2|mf-6vmwLNYasJeYulqr0ZxrZJ_2298d43e")
        #expect(ArtworkRef.decode(art.encode()) == art)
    }

    @Test func aFallbackThatIsTheCoverItselfIsNotWritten() {
        #expect(ArtworkRef.server(sourceId: "server:x", coverId: "al-1", fallbackId: "al-1").encode() == "server:server:x|al-1")
        #expect(ArtworkRef.server(sourceId: "server:x", coverId: "al-1", fallbackId: "").encode() == "server:server:x|al-1")
    }

    @Test func aCoverStoredBeforeFallbacksHasNone() throws {
        #expect(try #require(server(ArtworkRef.decode("server:server:x|al-1"))).fallbackId == nil)
        #expect(try #require(server(ArtworkRef.decode("online:server:x|tr-9"))).fallbackId == nil)
    }

    @Test func unknownIsNull() {
        #expect(ArtworkRef.decode("ftp:x") == nil)
        #expect(ArtworkRef.decode(nil) == nil)
    }
}
