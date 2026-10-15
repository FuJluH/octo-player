import Foundation
import Testing
@testable import OctoKit

@Suite struct MadeForYouTest {
    /// A playlist as the server sends it.
    private func playlist(_ id: String, _ name: String = "", songCount: Int = 0, coverArt: String? = nil, readonly: Bool = false,
                          octoList: String? = nil) throws -> Playlist {
        var json: [String: Any] = ["id": id, "name": name, "songCount": songCount, "readonly": readonly]
        if let coverArt { json["coverArt"] = coverArt }
        if let octoList { json["octoList"] = octoList }
        return try JSONDecoder().decode(Playlist.self, from: JSONSerialization.data(withJSONObject: json))
    }

    // Only the lists Octo marks, in kind order, each with its cover and how many songs it holds.
    @Test func theListsComeInKindOrderWithTheirSongCounts() throws {
        let playlists = [
            try playlist("mine", "Road trip", songCount: 12),
            try playlist("og-deep", "Deep Cuts", songCount: 30, readonly: true, octoList: "deepCuts"),
            try playlist("og-new", "New Releases", songCount: 24, coverArt: "og-new-cover", readonly: true, octoList: "newReleases"),
            try playlist("og-re", "Rediscover", songCount: 50, readonly: true, octoList: "rediscover"),
        ]
        let lists = madeForYouLists(playlists, sourceId: "src1")
        #expect(lists.map(\.id) == ["og-new", "og-re", "og-deep"])
        #expect(lists.map(\.songCount) == [24, 50, 30])
        #expect(lists.first?.artwork == ArtworkRef.server(sourceId: "src1", coverId: "og-new-cover").encode())
        #expect(lists.dropFirst().first?.artwork == ArtworkRef.server(sourceId: "src1", coverId: "og-re").encode(),
                "a list without a cover is drawn from its id")
    }

    @Test func likedSongsComesFirst() throws {
        let playlists = [
            try playlist("og-new", "New Releases", readonly: true, octoList: "newReleases"),
            try playlist("og-liked", "Liked Songs", readonly: true, octoList: "liked"),
        ]
        #expect(madeForYouLists(playlists, sourceId: "src1").map(\.id) == ["og-liked", "og-new"])
    }

    @Test func aServerWithoutTheListsHasNone() throws {
        #expect(madeForYouLists([try playlist("a"), try playlist("b", readonly: true)], sourceId: "src1").isEmpty)
    }
}
