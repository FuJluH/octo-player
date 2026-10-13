import Foundation
import Testing
@testable import OctoKit

@Suite struct ServerPlacesTests {
    @Test func aPlaceIsReadFromTheServer() async throws {
        let server = FakeServer()
        server.ok(#""place":{"code":"78701","name":"Austin","state":"TX","country":"us","latitude":30.27,"longitude":"-97.74"}"#)
        let place = try await server.client().place(.code("78701", country: "US"))
        #expect(place == OctoPlace(code: "78701", name: "Austin", state: "TX", country: "US", latitude: 30.27, longitude: -97.74))
        #expect(place?.livePlace == LivePlace(latitude: 30.27, longitude: -97.74, label: "Austin, TX", state: "Texas", countryCode: "US"))
        let asked = try #require(server.requests.first)
        #expect(asked.endpoint == "getPlace")
        #expect(asked.query["code"] == "78701" && asked.query["country"] == "US")
        #expect(asked.query["name"] == nil && asked.query["latitude"] == nil)
    }

    @Test func anUnknownPlaceIsNone() async throws {
        let server = FakeServer()
        server.error(70, "No such place")
        #expect(try await server.client().place(.city("Nowhere", state: "", country: "US")) == nil)
    }

    @Test func anotherErrorIsThrown() async {
        let server = FakeServer()
        server.error(0, "Broken")
        await #expect(throws: OctoError.self) { try await server.client().place(.code("1", country: "US")) }
    }

    @Test func eachQuerySendsOnlyItsOwnValues() {
        func names(_ query: PlaceQuery) -> [String] { query.params.map(\.0) }
        #expect(names(.code("10115", country: "de")) == ["code", "country"])
        #expect(PlaceQuery.code("10115", country: "de").params.last?.1 == "DE")
        #expect(names(.city("Austin", state: "TX", country: "US")) == ["name", "state", "country"])
        let near = PlaceQuery.near(latitude: 30.26715, longitude: -97.74306).params
        #expect(near.map(\.0) == ["latitude", "longitude"] && near.map(\.1) == ["30.27", "-97.74"])
    }

    @Test func typedWordsBecomeACodeOrACity() {
        #expect(PlaceQuery.typed(" 78701 ", country: "US") == .code("78701", country: "US"))
        #expect(PlaceQuery.typed("SW1A 1AA", country: "GB") == .code("SW1A 1AA", country: "GB"))
        #expect(PlaceQuery.typed("Austin, TX", country: "US") == .city("Austin", state: "TX", country: "US"))
        #expect(PlaceQuery.typed("Berlin", country: "DE") == .city("Berlin", state: "", country: "DE"))
    }

    @Test func theExtensionIsSeenWithOrWithoutItsVersion() {
        #expect(serverLooksUpPlaces(["octoFamily:1", "octoPlaces:1"]))
        #expect(serverLooksUpPlaces(["octoPlaces"]))
        #expect(!serverLooksUpPlaces(["octoPlacesOld:1", "formPost:1"]))
    }
}
