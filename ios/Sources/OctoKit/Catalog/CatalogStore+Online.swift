import Foundation

/// What the server says about a find now, with what the app already knew: whether a download was
/// asked for, what it became, and a length learned from playing it when the server still sends
/// none.
public func keptFind(_ now: OnlineSong, _ before: OnlineSong) -> OnlineSong {
    var kept = now
    kept.requestedAt = before.requestedAt
    kept.adoptedId = before.adoptedId
    kept.durationMs = now.durationMs > 0 ? now.durationMs : before.durationMs
    return kept
}

/// Songs found online that are not in the library.
extension CatalogStore {
    public func finds(_ ids: [String]) throws -> [OnlineSong] {
        try ids.catalogChunks(lookupChunk).flatMap { chunk in
            try db.rows(OnlineSong.self, "SELECT * FROM online_song WHERE id IN (\(marks(chunk.count)))", Array(chunk))
        }
    }

    public func find(_ id: String) throws -> OnlineSong? {
        try db.rows(OnlineSong.self, "SELECT * FROM online_song WHERE id = ?", [id]).first
    }

    /// Every find with a download asked for.
    public func requestedFinds() throws -> [OnlineSong] {
        try db.rows(OnlineSong.self, "SELECT * FROM online_song WHERE requestedAt > 0")
    }

    /// Downloads asked for that have not turned up in the library yet.
    public func waitingFinds() throws -> [OnlineSong] {
        try db.rows(OnlineSong.self, "SELECT * FROM online_song WHERE requestedAt > 0 AND adoptedId = ''")
    }

    /// Every find kept, of one server.
    public func finds(sourceId: String) throws -> [OnlineSong] {
        try db.rows(OnlineSong.self, "SELECT * FROM online_song WHERE sourceId = ?", [sourceId])
    }

    public func insertFinds(_ rows: [OnlineSong]) throws {
        try db.insert(rows, .replace)
        changed(.finds)
    }

    public func setRequested(_ id: String, at: Int64) throws {
        try db.run("UPDATE online_song SET requestedAt = ? WHERE id = ?", [at, id])
        changed(.finds)
    }

    /// Links a find to the library song it became.
    public func adopt(_ id: String, trackId: String) throws {
        try db.run("UPDATE online_song SET adoptedId = ? WHERE id = ?", [trackId, id])
        changed(.finds)
    }

    /// Gives a find the length the player measured. Answers how many rows took it.
    @discardableResult
    public func setFindLength(_ id: String, durationMs: Int64) throws -> Int {
        try db.run("UPDATE online_song SET durationMs = ? WHERE id = ?", [durationMs, id])
        let count = db.changes
        if count > 0 { changed(.finds) }
        return count
    }

    /// Stores what the server says about these songs now, keeping what the app knows about each,
    /// and answers them as stored.
    @discardableResult
    public func keepFinds(_ rows: [OnlineSong]) throws -> [OnlineSong] {
        if rows.isEmpty { return rows }
        return try batch {
            var before: [String: OnlineSong] = [:]
            for row in try finds(rows.map(\.id)) { before[row.id] = row }
            let kept = rows.map { row in before[row.id].map { keptFind(row, $0) } ?? row }
            try insertFinds(kept)
            return kept
        }
    }

    /// Lets go of finds from servers no longer kept, and this server's old ones nothing needs: not
    /// asked for, and not in the saved queue or a playlist. `queued` is the saved queue's songs,
    /// when it is kept outside the library.
    public func pruneFinds(sourceId: String, kept: [String], before: Int64, queued: [String] = []) throws {
        let notKept = kept.isEmpty ? "1" : "sourceId NOT IN (\(marks(kept.count)))"
        let inQueue = Array(Set(queued.filter(isFind)))
        let notQueued = inQueue.isEmpty ? "" : "AND id NOT IN (\(marks(inQueue.count)))"
        try db.run("""
            DELETE FROM online_song WHERE \(notKept) OR (
                sourceId = ? AND requestedAt = 0 AND seenAt < ? AND id NOT IN (SELECT trackId FROM queue_item)
                AND id NOT IN (SELECT trackId FROM playlist_item) \(notQueued)
            )
            """, (kept as [any SQLBindable]) + [sourceId, before] + (inQueue as [any SQLBindable]))
        if db.changes > 0 { changed(.finds) }
    }

    public func clearFinds() throws {
        try db.run("DELETE FROM online_song")
        changed(.finds)
    }
}
