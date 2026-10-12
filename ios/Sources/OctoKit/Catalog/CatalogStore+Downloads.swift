import Foundation

/// A download as the Downloads page shows it: with its artwork and length.
public struct DownloadListRow: Sendable, Hashable, Identifiable {
    public var trackId: String
    public var sourceId: String
    public var serverId: String
    public var title: String
    public var artist: String
    public var artwork: String?
    public var sizeBytes: Int64
    public var state: DownloadStatus
    public var progress: Float
    public var reason: String
    /// When it was asked for, for ordering the list.
    public var addedAt: Int64
    /// Whether the song is marked explicit, while the library has it.
    public var explicit: Bool?

    public var id: String { "\(sourceId)|\(serverId)" }
}

/// A playlist song, for keeping playlists downloaded.
public struct PlaylistMember: Sendable, Hashable {
    public var playlistId: String
    public var trackId: String
}

/// Songs kept on the phone as files.
extension CatalogStore {
    public func allDownloads() throws -> [KeptDownload] {
        try db.rows(KeptDownload.self, "SELECT * FROM download")
    }

    /// Downloads in the page's order: downloading, queued, failed, done, then newest asked, then title.
    public func downloadRows() throws -> [DownloadListRow] {
        try db.query("""
            SELECT d.trackId, d.sourceId, d.serverId, d.title, d.artist, t.artwork, d.sizeBytes, d.state, d.progress, d.reason,
                d.addedAt, t.explicit
            FROM download d LEFT JOIN track t ON t.id = d.trackId
            ORDER BY CASE d.state WHEN 'Downloading' THEN 0 WHEN 'Queued' THEN 1 WHEN 'Failed' THEN 2 ELSE 3 END, d.addedAt DESC, d.title
            """) { row in
            DownloadListRow(trackId: row.string("trackId"), sourceId: row.string("sourceId"), serverId: row.string("serverId"),
                            title: row.string("title"), artist: row.string("artist"), artwork: row.optionalString("artwork"),
                            sizeBytes: row.int64("sizeBytes"), state: DownloadStatus(rawValue: row.string("state")) ?? .queued,
                            progress: row.float("progress"), reason: row.string("reason"), addedAt: row.int64("addedAt"),
                            explicit: row.optionalBool("explicit"))
        }
    }

    /// Finished downloads of these library songs.
    public func doneDownloads(for trackIds: [String]) throws -> [KeptDownload] {
        try trackIds.catalogChunks(lookupChunk).flatMap { chunk in
            try db.rows(KeptDownload.self, "SELECT * FROM download WHERE state = 'Done' AND trackId IN (\(marks(chunk.count)))", Array(chunk))
        }
    }

    public func downloads(forTrack trackId: String) throws -> [KeptDownload] {
        try db.rows(KeptDownload.self, "SELECT * FROM download WHERE trackId = ?", [trackId])
    }

    /// The oldest download from this server still waiting.
    public func nextQueuedDownload(_ sourceId: String) throws -> KeptDownload? {
        try db.rows(KeptDownload.self, "SELECT * FROM download WHERE state = 'Queued' AND sourceId = ? ORDER BY addedAt, title LIMIT 1",
                    [sourceId]).first
    }

    public func download(_ sourceId: String, _ serverId: String) throws -> KeptDownload? {
        try db.rows(KeptDownload.self, "SELECT * FROM download WHERE sourceId = ? AND serverId = ?", [sourceId, serverId]).first
    }

    public func upsertDownloads(_ rows: [KeptDownload]) throws {
        try db.insert(rows, .replace)
        changed(.downloads)
    }

    public func setDownloadReason(_ sourceId: String, _ serverId: String, reason: String) throws {
        try db.run("UPDATE download SET reason = ? WHERE sourceId = ? AND serverId = ?", [reason, sourceId, serverId])
        changed(.downloads)
    }

    public func setDownloadState(_ sourceId: String, _ serverId: String, state: DownloadStatus, progress: Float) throws {
        try db.run("UPDATE download SET state = ?, progress = ? WHERE sourceId = ? AND serverId = ?",
                   [state.rawValue, progress, sourceId, serverId])
        changed(.downloads)
    }

    public func finishDownload(_ sourceId: String, _ serverId: String, path: String, size: Int64, format: String?) throws {
        try db.run("""
            UPDATE download SET state = 'Done', progress = 1, path = ?, sizeBytes = ?, format = ?
            WHERE sourceId = ? AND serverId = ?
            """, [path, size, format, sourceId, serverId])
        changed(.downloads)
    }

    /// A download cut short when the app last closed waits again.
    public func requeueInterruptedDownloads() throws {
        try db.run("UPDATE download SET state = 'Queued', progress = 0 WHERE state = 'Downloading'")
        changed(.downloads)
    }

    public func deleteDownload(_ sourceId: String, _ serverId: String) throws {
        try db.run("DELETE FROM download WHERE sourceId = ? AND serverId = ?", [sourceId, serverId])
        changed(.downloads)
    }

    /// After the library is rebuilt: each download follows its server song to the library song it
    /// is now part of.
    func relinkDownloads() throws {
        try db.run("""
            UPDATE download SET trackId = COALESCE((
                SELECT CASE WHEN s.mergedId = '' THEN s.id ELSE s.mergedId END FROM source_track s
                WHERE s.sourceId = download.sourceId AND s.nativeId = download.serverId LIMIT 1
            ), trackId)
            """)
    }

    /// The songs of these playlists.
    public func playlistMembers(_ playlistIds: [String]) throws -> [PlaylistMember] {
        try playlistIds.catalogChunks(lookupChunk).flatMap { chunk in
            try db.query("SELECT playlistId, trackId FROM playlist_item WHERE playlistId IN (\(marks(chunk.count)))", Array(chunk)) {
                PlaylistMember(playlistId: $0.string("playlistId"), trackId: $0.string("trackId"))
            }
        }
    }

    /// The songs of one playlist, library songs only.
    public func playlistTrackIds(_ playlistId: String) throws -> [String] {
        try db.strings("SELECT i.trackId FROM playlist_item i JOIN track t ON t.id = i.trackId WHERE i.playlistId = ? ORDER BY i.position",
                       [playlistId])
    }

    /// The server copies of these library songs.
    public func serverCopies(of trackIds: [String]) throws -> [SourceTrack] {
        try trackIds.catalogChunks(lookupChunk).flatMap { chunk in
            try db.rows(SourceTrack.self, "SELECT * FROM source_track WHERE mergedId IN (\(marks(chunk.count))) AND sourceId LIKE 'server:%'",
                        Array(chunk))
        }
    }

    /// One server song, as the last sync saw it.
    public func serverCopy(_ sourceId: String, _ serverId: String) throws -> SourceTrack? {
        try db.rows(SourceTrack.self, "SELECT * FROM source_track WHERE sourceId = ? AND nativeId = ? LIMIT 1", [sourceId, serverId]).first
    }

    /// Which of these library songs can be downloaded: on a server and not on the phone.
    public func downloadable(_ trackIds: [String]) throws -> [String] {
        try trackIds.catalogChunks(lookupChunk).flatMap { chunk in
            try db.strings("""
                SELECT DISTINCT t.id FROM track t JOIN source_track s ON s.mergedId = t.id
                WHERE t.onPhone = 0 AND s.sourceId LIKE 'server:%' AND t.id IN (\(marks(chunk.count)))
                """, Array(chunk))
        }
    }
}
