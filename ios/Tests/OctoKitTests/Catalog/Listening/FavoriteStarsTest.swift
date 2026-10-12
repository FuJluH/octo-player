import Foundation
import Testing
@testable import OctoKit

@Suite struct FavoriteStarsTest {
    let server = "server:music.example"

    func row(_ native: String) -> String { "\(server):\(native)" }

    func count(_ serverRow: String, _ library: String, _ songs: Int) -> CopyCount {
        CopyCount(serverRowId: serverRow, libraryId: library, songs: songs)
    }

    @Test func aServerAlbumMergedIntoAPhoneAlbumIsThatAlbumsCopy() {
        let counts = [count(row("al1"), "device:album:1", 12)]
        #expect(serverCopiesOf(counts, sourceId: server) == [ServerCopy(trackId: "device:album:1", serverId: "al1")])
    }

    @Test func aServerAlbumSplitOverTwoLibraryAlbumsBelongsToTheOneWithMostOfItsSongs() {
        // A deluxe edition: 12 songs matched the phone's album, 3 bonus songs stayed in an album
        // of the server's own.
        let counts = [
            count(row("deluxe"), "device:album:1", 12),
            count(row("deluxe"), row("deluxe"), 3),
        ]
        #expect(serverCopiesOf(counts, sourceId: server) == [ServerCopy(trackId: "device:album:1", serverId: "deluxe")])
    }

    @Test func aTieGoesToTheLibraryAlbumThatKeptTheServersId() {
        let counts = [
            count(row("al1"), "device:album:1", 4),
            count(row("al1"), row("al1"), 4),
        ]
        #expect(serverCopiesOf(counts, sourceId: server) == [ServerCopy(trackId: row("al1"), serverId: "al1")])
    }

    @Test func twoServerAlbumsCanBothBeCopiesOfOneLibraryAlbum() {
        let counts = [
            count(row("a"), "device:album:1", 5),
            count(row("b"), "device:album:1", 2),
        ]
        let copies = serverCopiesOf(counts, sourceId: server)
        #expect(copies.serverIdsOf("device:album:1") == ["a", "b"])
    }

    @Test func madeUpIdsAndOtherServersAreLeftOut() {
        let counts = [
            count(row("album:some key"), "device:album:1", 5),
            count(row("artist:some one"), "device:artist:one", 5),
            count("server:elsewhere:x", "device:album:2", 5),
            count("device:album:3", "device:album:3", 5),
        ]
        #expect(serverCopiesOf(counts, sourceId: server).isEmpty)
    }

    // The planning is the song stars' planning, run on albums and artists.

    let albums = [ServerCopy(trackId: "device:album:1", serverId: "al1"), ServerCopy(trackId: "server:x:al2", serverId: "al2")]

    @Test func aFavoriteAlbumOnThePhoneStarsItsServerAlbum() {
        let plan = reconcileStars(albums, liked: ["device:album:1"], starred: [], synced: [])
        #expect(plan.star == ["al1"])
        #expect(plan.synced == ["al1"])
    }

    @Test func aStarredAlbumOnTheServerBecomesAFavorite() {
        let plan = reconcileStars(albums, liked: [], starred: ["al2"], synced: [])
        #expect(plan.like == ["server:x:al2"])
        #expect(plan.star.isEmpty && plan.unstar.isEmpty)
    }

    @Test func anAlbumUnstarredOnTheServerStopsBeingAFavorite() {
        let plan = reconcileStars(albums, liked: ["device:album:1"], starred: [], synced: ["al1"])
        #expect(plan.unlike == ["device:album:1"])
        #expect(plan.synced.isEmpty)
    }

    @Test func anAlbumRemovedFromFavoritesOnThePhoneIsUnstarred() {
        let plan = reconcileStars(albums, liked: [], starred: ["al1"], synced: ["al1"])
        #expect(plan.unstar == ["al1"])
        #expect(plan.like.isEmpty)
    }

    @Test func aPhoneOnlyAlbumIsNeverSentAnywhere() {
        // "device:album:9" has no server copy at all.
        let plan = reconcileStars(albums, liked: ["device:album:9"], starred: [], synced: [])
        #expect(plan.star.isEmpty && plan.unstar.isEmpty && plan.like.isEmpty && plan.unlike.isEmpty)
    }

    @Test func artistsFollowTheSameRules() {
        let counts = [
            count(row("ar1"), "device:artist:radiohead", 40),
            count(row("ar1"), row("ar1"), 0),
            count(row("ar2"), row("ar2"), 0),
        ]
        let artists = serverCopiesOf(counts, sourceId: server)
        #expect(Set(artists) == [ServerCopy(trackId: "device:artist:radiohead", serverId: "ar1"), ServerCopy(trackId: row("ar2"), serverId: "ar2")])
        let plan = reconcileStars(artists, liked: ["device:artist:radiohead"], starred: ["ar2"], synced: [])
        #expect(plan.star == ["ar1"])
        #expect(plan.like == [row("ar2")])
        #expect(plan.synced == ["ar1", "ar2"])
    }

    // Keeping and sending.

    @Test func eachKindKeepsItsRecordPerAccount() {
        #expect(FavoriteKind.album.syncedKey(account: "acct") == "synced_albums@acct")
        #expect(FavoriteKind.artist.syncedKey(account: "acct") == "synced_artists@acct")
    }

    @Test func batchesGoInOrderAndOnlyFailedOnesComeBack() async throws {
        let ids = Set((1...120).map { String(format: "id%03d", $0) })
        let seen = BatchLog()
        let failed = try await favoriteBatchFailures(ids) { batch in
            seen.add(batch)
            if batch.first == "id051" { throw OctoError.http(500) }
        }
        #expect(seen.batches.map(\.count) == [50, 50, 20])
        #expect(seen.batches.flatMap { $0 } == ids.sorted())
        #expect(failed == Set(seen.batches[1]))
    }

    @Test func aFavoriteFromTheServerKeepsTheEarliestStarTime() {
        let copies = [
            ServerCopy(trackId: "lib1", serverId: "a"),
            ServerCopy(trackId: "lib1", serverId: "b"),
            ServerCopy(trackId: "lib2", serverId: "c"),
        ]
        let times = starredTimes(copies, ["a": 500, "b": 300, "c": nil])
        #expect(times == ["lib1": 300])
    }
}

/// The batches a call was handed, in order.
final class BatchLog: @unchecked Sendable {
    private let lock = NSLock()
    private var all: [[String]] = []

    func add(_ batch: [String]) {
        lock.lock()
        all.append(batch)
        lock.unlock()
    }

    var batches: [[String]] {
        lock.lock()
        defer { lock.unlock() }
        return all
    }
}
