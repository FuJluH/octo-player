import Foundation
import Testing
@testable import OctoKit

/// The library database end to end: sources in, the merge, reads, and what follows songs whose
/// ids change.
@Suite struct CatalogStoreTest {
    let server = "server:music.test"

    func track(_ source: String, _ native: String, _ title: String, album: String = "album", ms: Int64 = 200_000, no: Int? = nil,
               played: Int? = nil, lastPlayed: Int64? = nil, rating: Int? = nil) -> SourceTrack {
        SourceTrack(id: "\(source):\(native)", sourceId: source, nativeId: native, title: title, searchKey: searchKey(title),
                    sortKey: sortKey(title), artist: "Drake", artistId: "\(source):artist", album: "Views", albumId: "\(source):\(album)",
                    trackNo: no, durationMs: ms, addedAt: 100, artwork: "\(source)-art",
                    relinkKey: relinkKey(albumArtist: "Drake", album: "Views", disc: nil, track: no, title: title, durationMs: ms),
                    playCount: played, lastPlayedAt: lastPlayed, rating: rating)
    }

    func album(_ source: String, _ native: String = "album", songs: Int) -> SourceAlbum {
        SourceAlbum(id: "\(source):\(native)", sourceId: source, nativeId: native, title: "Views", searchKey: "views drake", sortKey: "views",
                    artist: "Drake", artistId: "\(source):artist", songCount: songs, durationMs: 0, addedAt: 100)
    }

    func artist(_ source: String) -> SourceArtist {
        SourceArtist(id: "\(source):artist", sourceId: source, name: "Drake", searchKey: "drake", sortKey: "drake", albumCount: 1, songCount: 2)
    }

    func store() throws -> CatalogStore { try CatalogStore(path: ":memory:") }

    func fillServer(_ store: CatalogStore) async throws {
        try await store.replaceSource(server,
                                      tracks: [track(server, "1", "Hotline Bling", no: 1, played: 3, lastPlayed: 5_000, rating: 4),
                                               track(server, "2", "One Dance", no: 2)],
                                      albums: [album(server, songs: 2)], artists: [artist(server)])
    }

    @Test func aServersSongsJoinOnlyWhileItIsInUse() async throws {
        let store = try store()
        try await fillServer(store)
        try await store.rebuild(serverInUse: nil)
        #expect(try await store.libraryTrackCount() == 0)
        try await store.rebuild(serverInUse: server)
        #expect(try await store.libraryTrackCount() == 2)
        #expect(try await store.albumTracks("\(server):album").map(\.title) == ["Hotline Bling", "One Dance"])
        #expect(try await store.searchTracks("hotline", limit: 10).map(\.id) == ["\(server):1"])
        // An artist's name finds the artist's songs, after any song whose title holds it.
        #expect(try await store.searchTracks("drake", limit: 10).map(\.title) == ["Hotline Bling", "One Dance"])
        #expect(try await store.copies("\(server):1").map(\.nativeId) == ["1"])
        // Left out again, its copies are no library song's.
        try await store.rebuild(serverInUse: nil)
        #expect(try await store.copies("\(server):1").isEmpty)
    }

    @Test func aLikeFollowsTheSongWhenThePhonesCopyTakesItsPlace() async throws {
        let store = try store()
        try await fillServer(store)
        try await store.rebuild(serverInUse: server)
        try await store.like(LikedTrack(trackId: "\(server):1", relinkKey: "", likedAt: 10))
        try await store.addPlay(PlayEvent(trackId: "\(server):1", relinkKey: "", startedAt: 20, playedMs: 1, durationMs: 1))
        try await store.replaceSource(deviceSource, tracks: [track(deviceSource, "9", "Hotline Bling", no: 1)],
                                      albums: [album(deviceSource, songs: 1)], artists: [artist(deviceSource)])
        try await store.rebuild(serverInUse: server)
        #expect(try await store.likedIds() == ["\(deviceSource):9"])
        #expect(try await store.playedTracks().map(\.track.id) == ["\(deviceSource):9"])
        // The server's rating shows on the phone's song.
        #expect(try await store.track("\(deviceSource):9")?.rating == 4)
        #expect(try await store.track("\(deviceSource):9")?.onPhone == true)
    }

    @Test func aRelinkKeyFindsASongWhoseIdChanged() async throws {
        let store = try store()
        let first = track(deviceSource, "1", "Intro", no: 1)
        try await store.replaceSource(deviceSource, tracks: [first], albums: [album(deviceSource, songs: 1)], artists: [artist(deviceSource)])
        try await store.rebuild(serverInUse: nil)
        try await store.rate(TrackRating(trackId: first.id, relinkKey: first.relinkKey, rating: 5, ratedAt: 1))
        // The file got a new id; its relink key is the same.
        try await store.replaceSource(deviceSource, tracks: [track(deviceSource, "2", "Intro", no: 1)], albums: [album(deviceSource, songs: 1)],
                                      artists: [artist(deviceSource)])
        try await store.rebuild(serverInUse: nil)
        #expect(try await store.ratings().map(\.trackId) == ["\(deviceSource):2"])
        // Songs no server rated show the phone's rating.
        #expect(try await store.track("\(deviceSource):2")?.rating == 5)
    }

    @Test func playlistEditsRenumberAndUndo() async throws {
        let store = try store()
        try await fillServer(store)
        try await store.rebuild(serverInUse: server)
        let songs = try await store.allTracks()
        try await store.insertPlaylist(PlaylistRow(id: "p", name: "Mine", createdAt: 1, updatedAt: 1))
        let added = try await store.addToPlaylist("p", tracks: songs + songs, now: 0)
        #expect(added.count == 4)
        #expect(try await store.playlist("p")?.updatedAt == 2)
        let removed = try #require(try await store.removeFromPlaylist("p", itemId: added[1], now: 0))
        #expect(removed.position == 1)
        #expect(try await store.playlistItems("p").map(\.position) == [0, 1, 2])
        try await store.restoreToPlaylist("p", item: removed, now: 0)
        #expect(try await store.playlistItems("p").map(\.id) == added)
        try await store.moveInPlaylist("p", itemId: added[3], targetId: added[0], now: 0)
        #expect(try await store.playlistItems("p").map(\.id) == [added[3], added[0], added[1], added[2]])
        let summary = try await store.playlistSummaries(serverInUse: nil)
        #expect(summary.first?.songCount == 4)
        #expect(summary.first?.covers == ["\(server)-art"])
        try await store.deletePlaylist("p")
        #expect(try await store.playlistItems("p").isEmpty)
    }

    @Test func findsKeepWhatTheAppKnew() async throws {
        let store = try store()
        let find = OnlineSong(id: findId("x"), sourceId: server, nativeId: "x", title: "Found", artist: "Someone", durationMs: 90_000,
                              seenAt: 1, requestedAt: 5)
        try await store.insertFinds([find])
        var again = find
        again.durationMs = 0
        again.requestedAt = 0
        again.seenAt = 9
        let kept = try await store.keepFinds([again])
        #expect(kept.first?.requestedAt == 5)
        #expect(kept.first?.durationMs == 90_000)
        #expect(kept.first?.seenAt == 9)
        // A server no longer kept takes its finds with it.
        try await store.pruneFinds(sourceId: server, kept: [], before: 0)
        #expect(try await store.find(findId("x")) == nil)
    }

    @Test func oldFindsGoUnlessTheSavedQueueHoldsThem() async throws {
        let store = try store()
        let old = [findId("q"), findId("gone")].map {
            OnlineSong(id: $0, sourceId: server, nativeId: String($0.dropFirst(findPrefix.count)), title: "Found", artist: "Someone",
                       durationMs: 90_000, seenAt: 1, requestedAt: 0)
        }
        try await store.insertFinds(old)
        try await store.pruneFinds(sourceId: server, kept: [server], before: 100, queued: ["device:1", findId("q")])
        #expect(try await store.find(findId("q")) != nil)
        #expect(try await store.find(findId("gone")) == nil)
    }

    @Test func listenersHearAboutChanges() async throws {
        let store = try store()
        let heard = Heard()
        await store.listen { heard.add($0) }
        try await store.like(LikedTrack(trackId: "a", relinkKey: "", likedAt: 1))
        #expect(heard.all.contains(.likes))
    }
}

final class Heard: @unchecked Sendable {
    private let lock = NSLock()
    private var changes: [CatalogChange] = []
    func add(_ change: CatalogChange) { lock.withLock { changes.append(change) } }
    var all: CatalogChange { lock.withLock { changes.reduce([]) { $0.union($1) } } }
}
