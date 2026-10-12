import Foundation
import Testing
@testable import OctoKit

/// Which library songs are in a family member's own library on the server in use.
@Suite struct PersonalSongsTests {
    let server = "server:family.test"

    func track(_ native: String, _ title: String, personal: Bool) -> SourceTrack {
        SourceTrack(id: "\(server):\(native)", sourceId: server, nativeId: native, title: title, searchKey: searchKey(title),
                    sortKey: sortKey(title), artist: "Adele", artistId: "\(server):artist", album: "25", albumId: "\(server):album",
                    durationMs: 200_000, addedAt: 100, personal: personal)
    }

    @Test func onlyTheMembersOwnSongsCount() async throws {
        let store = try CatalogStore(path: ":memory:")
        try await store.replaceSource(server, tracks: [track("1", "Hello", personal: true), track("2", "Water Under the Bridge", personal: false)],
                                      albums: [], artists: [])
        try await store.rebuild(serverInUse: server)
        #expect(try await store.personalTrackIds(server) == ["\(server):1"])
        #expect(try await store.marksPersonal(server))
    }

    @Test func aServerThatMarksNoneHasNone() async throws {
        let store = try CatalogStore(path: ":memory:")
        try await store.replaceSource(server, tracks: [track("1", "Hello", personal: false)], albums: [], artists: [])
        try await store.rebuild(serverInUse: server)
        #expect(try await store.personalTrackIds(server).isEmpty)
        #expect(try await !store.marksPersonal(server))
    }
}
