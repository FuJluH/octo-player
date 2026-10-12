import Foundation

// Favorite albums and artists are kept in step with stars on the server exactly as liked songs
// are (reconcileStars): the same three-way comparison with the last state both sides agreed on.
// What differs is only how a library album or artist finds its server copies.

/// Album or artist, for the favorites kept in step with a server.
public enum FavoriteKind: String, Sendable, CaseIterable {
    case album = "Album"
    case artist = "Artist"

    /// Where the server ids both sides last agreed were starred are kept, for one server account:
    /// ids only mean something on the server they came from.
    public func syncedKey(account: String) -> String {
        (self == .album ? "synced_albums" : "synced_artists") + "@\(account)"
    }
}

/// The server copies of library albums (or artists), one library album per server album: the one
/// that took most of its songs when the library was merged, or on a tie the one that kept the
/// server album's own id. A server album never counts for two library albums, since a star there
/// would then read as starred for both. Ids the library made up because the server gave none
/// ("album:..." or "artist:...") cannot be starred and are left out.
public func serverCopiesOf(_ counts: [CopyCount], sourceId: String) -> [ServerCopy] {
    let prefix = "\(sourceId):"
    return groupInOrder(counts, by: \.serverRowId).compactMap { row, links in
        guard row.hasPrefix(prefix) else { return nil }
        let serverId = String(row.dropFirst(prefix.count))
        if serverId.isEmpty || serverId.hasPrefix("album:") || serverId.hasPrefix("artist:") { return nil }
        guard let best = links.dropFirst().reduce(links.first, { best, link in
            guard let best else { return link }
            return copyRanksBelow(best, link, row: row) ? link : best
        }) else { return nil }
        return ServerCopy(trackId: best.libraryId, serverId: serverId)
    }
}

/// Whether `a` ranks below `b` as a server row's copy: fewer songs, then not keeping the row's
/// id, then the smaller library id.
private func copyRanksBelow(_ a: CopyCount, _ b: CopyCount, row: String) -> Bool {
    if a.songs != b.songs { return a.songs < b.songs }
    let aKept = a.libraryId == row
    let bKept = b.libraryId == row
    if aKept != bKept { return !aKept }
    return a.libraryId < b.libraryId
}

extension Array where Element == ServerCopy {
    /// The server ids one library album or artist is starred through.
    public func serverIdsOf(_ libraryId: String) -> [String] {
        filter { $0.trackId == libraryId }.map(\.serverId).sorted()
    }
}

/// The server ids to star (or unstar) for one change made on the phone: none once a newer change
/// undid it (`likedNow` is how it stands now), or when the album or artist is only on the phone.
public func idsToSend(_ copies: [ServerCopy], libraryId: String, liked: Bool, likedNow: Bool) -> [String] {
    liked != likedNow ? [] : copies.serverIdsOf(libraryId)
}

/// How long to wait before each new try at sending a change, in milliseconds. After the last, the
/// next sync of the library sends it.
public let favoriteRetryWaits: [Int64] = [5_000, 30_000, 120_000]

/// Runs `attempt` until it says it is done, pausing for each wait in `waits` (milliseconds)
/// before each new try. False when every try failed.
public func retriedAfterWaits(
    _ waits: [Int64],
    pause: (Int64) async throws -> Void = { try await listeningPauseMs($0) },
    attempt: () async throws -> Bool
) async rethrows -> Bool {
    if try await attempt() { return true }
    for wait in waits {
        try await pause(wait)
        if try await attempt() { return true }
    }
    return false
}

/// How many albums or artists go in one star or unstar call.
public let favoriteBatchSize = 50

/// Sends ids in sorted batches of `favoriteBatchSize` through `call`, and hands back the ids whose
/// batch did not go through. Only stopped work is passed on as an error.
public func favoriteBatchFailures(_ ids: Set<String>, _ call: ([String]) async throws -> Void) async throws -> Set<String> {
    let sorted = ids.sorted()
    var failed = Set<String>()
    for start in stride(from: 0, to: sorted.count, by: favoriteBatchSize) {
        let batch = Array(sorted[start..<Swift.min(start + favoriteBatchSize, sorted.count)])
        do {
            try await call(batch)
        } catch {
            if isCancellation(error) { throw error }
            failed.formUnion(batch)
        }
    }
    return failed
}

/// When each library album or artist was starred on the server, the earliest of its copies', for
/// a favorite that comes from the server to keep that time. Library ids with no known time are
/// left out.
public func starredTimes(_ copies: [ServerCopy], _ starredAt: [String: Int64?]) -> [String: Int64] {
    var times: [String: Int64] = [:]
    for copy in copies {
        guard let known = starredAt[copy.serverId], let time = known else { continue }
        times[copy.trackId] = Swift.min(times[copy.trackId] ?? time, time)
    }
    return times
}

/// Waits `ms` milliseconds; stopped work ends the wait early.
public func listeningPauseMs(_ ms: Int64) async throws {
    try await Task.sleep(nanoseconds: UInt64(max(ms, 0)) * 1_000_000)
}
