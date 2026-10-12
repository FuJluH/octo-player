import Foundation

/// A library song a server has a play record for, one row per server copy.
public struct ServerPlayedTrack: Sendable, Hashable {
    public var track: LibraryTrack
    public var serverId: String
    public var serverPlays: Int
    public var serverLastPlayedAt: Int64?

    public init(track: LibraryTrack, serverId: String, serverPlays: Int, serverLastPlayedAt: Int64?) {
        self.track = track
        self.serverId = serverId
        self.serverPlays = serverPlays
        self.serverLastPlayedAt = serverLastPlayedAt
    }
}

/// A like, rating or playlist song with what the library knows of the song, for a backup. The
/// song fields are nil when the library no longer has it.
public struct SongKeyRow: Sendable, Hashable {
    public var playlistId: String?
    public var relinkKey: String
    public var title: String?
    public var artist: String?
    public var album: String?
    public var durationMs: Int64?
    public var rating: Int?
}

/// Things the listener made: likes, ratings, playlists, plays and the saved queue.
extension CatalogStore {
    // MARK: Likes

    public func likedIds() throws -> [String] {
        try db.strings("SELECT trackId FROM liked_track")
    }

    public func like(_ row: LikedTrack) throws {
        try db.insert([row], .ignore)
        changed(.likes)
    }

    public func likeAll(_ rows: [LikedTrack]) throws {
        try db.insert(rows, .ignore)
        changed(.likes)
    }

    public func unlike(_ trackId: String) throws {
        try db.run("DELETE FROM liked_track WHERE trackId = ?", [trackId])
        changed(.likes)
    }

    public func isLiked(_ trackId: String) throws -> Bool {
        try db.scalar("SELECT EXISTS(SELECT 1 FROM liked_track WHERE trackId = ?)", [trackId]) != 0
    }

    public func likedRow(_ trackId: String) throws -> LikedTrack? {
        try db.rows(LikedTrack.self, "SELECT * FROM liked_track WHERE trackId = ?", [trackId]).first
    }

    /// Liked songs the library still has, newest like first.
    public func likedTracks() throws -> [LibraryTrack] {
        try db.rows(LibraryTrack.self, "SELECT t.* FROM liked_track l JOIN track t ON t.id = l.trackId ORDER BY l.likedAt DESC")
    }

    public func likedCount() throws -> Int {
        Int(try db.scalar("SELECT COUNT(*) FROM liked_track l JOIN track t ON t.id = l.trackId"))
    }

    // MARK: Ratings made on the phone

    public func ratings() throws -> [TrackRating] {
        try db.rows(TrackRating.self, "SELECT * FROM track_rating")
    }

    public func rating(_ trackId: String) throws -> Int? {
        try db.first("SELECT rating FROM track_rating WHERE trackId = ?", [trackId]) { $0.int64(at: 0) }.map { Int($0) }
    }

    public func rate(_ row: TrackRating) throws {
        try db.insert([row], .replace)
        changed(.ratings)
    }

    public func unrate(_ trackId: String) throws {
        try db.run("DELETE FROM track_rating WHERE trackId = ?", [trackId])
        changed(.ratings)
    }

    /// The rating the library shows for one song.
    public func showRating(_ trackId: String, _ rating: Int) throws {
        try db.run("UPDATE track SET rating = ? WHERE id = ?", [rating, trackId])
        changed([.library, .ratings])
    }

    /// After the library is rebuilt: songs no server rated show the rating made on the phone.
    func showPhoneRatings() throws {
        try db.run("""
            UPDATE track SET rating = (SELECT r.rating FROM track_rating r WHERE r.trackId = track.id)
            WHERE rating = 0 AND id IN (SELECT trackId FROM track_rating)
            """)
    }

    // MARK: For a backup

    public func likedSongKeys() throws -> [SongKeyRow] {
        try songKeys("""
            SELECT NULL AS playlistId, l.relinkKey, t.title, t.artist, t.album, t.durationMs, NULL AS rating
            FROM liked_track l LEFT JOIN track t ON t.id = l.trackId
            ORDER BY l.likedAt
            """)
    }

    public func ratedSongKeys() throws -> [SongKeyRow] {
        try songKeys("""
            SELECT NULL AS playlistId, r.relinkKey, t.title, t.artist, t.album, t.durationMs, r.rating
            FROM track_rating r LEFT JOIN track t ON t.id = r.trackId
            ORDER BY r.ratedAt
            """)
    }

    public func phonePlaylistSongKeys() throws -> [SongKeyRow] {
        try songKeys("""
            SELECT i.playlistId, i.relinkKey, COALESCE(t.title, o.title) AS title, COALESCE(t.artist, o.artist) AS artist,
                COALESCE(t.album, o.album) AS album, COALESCE(t.durationMs, o.durationMs) AS durationMs, NULL AS rating
            FROM playlist_item i JOIN playlist p ON p.id = i.playlistId
                LEFT JOIN track t ON t.id = i.trackId LEFT JOIN online_song o ON o.id = i.trackId
            WHERE p.sourceId IS NULL
            ORDER BY i.playlistId, i.position
            """)
    }

    private func songKeys(_ sql: String) throws -> [SongKeyRow] {
        try db.query(sql) { row in
            SongKeyRow(playlistId: row.optionalString("playlistId"), relinkKey: row.string("relinkKey"),
                       title: row.optionalString("title"), artist: row.optionalString("artist"), album: row.optionalString("album"),
                       durationMs: row.optionalInt64("durationMs"), rating: row.optionalInt("rating"))
        }
    }

    // MARK: Playlists

    /// Every playlist, the one changed last first.
    public func playlists() throws -> [PlaylistRow] {
        try db.rows(PlaylistRow.self, "SELECT * FROM playlist ORDER BY updatedAt DESC")
    }

    public func playlist(_ id: String) throws -> PlaylistRow? {
        try db.rows(PlaylistRow.self, "SELECT * FROM playlist WHERE id = ?", [id]).first
    }

    /// Every playlist song the library still has, in play order; a song found online counts too.
    public func playlistEntries() throws -> [PlaylistEntry] {
        try db.query("""
            SELECT playlistId, albumId, durationMs, artwork FROM (
                SELECT i.playlistId, i.position, t.albumId, t.durationMs, t.artwork
                FROM playlist_item i JOIN track t ON t.id = i.trackId
                UNION ALL
                SELECT i.playlistId, i.position, COALESCE(o.albumId, ''), o.durationMs,
                    CASE WHEN o.coverId IS NULL THEN NULL ELSE 'online:' || o.sourceId || '|' || o.coverId END
                FROM playlist_item i JOIN online_song o ON o.id = i.trackId
            )
            ORDER BY playlistId, position
            """) { row in
            PlaylistEntry(playlistId: row.string("playlistId"), albumId: row.string("albumId"), durationMs: row.int64("durationMs"),
                          artwork: row.optionalString("artwork"))
        }
    }

    /// Playlists as their list shows them, in the order given by `playlists()`, the ones shown
    /// with `serverInUse`.
    public func playlistSummaries(serverInUse: String?) throws -> [PlaylistSummary] {
        summarize(try playlists().filter { $0.shownWith(serverInUse) }, try playlistEntries())
    }

    /// A playlist's songs in play order: library songs, and songs found online shaped like them.
    public func playlistTracks(_ id: String) throws -> [PlaylistTrack] {
        try db.query("""
            SELECT itemId, id, sourceId, nativeId, title, searchKey, sortKey, artist, artistId, album, albumId,
                trackNo, discNo, year, durationMs, addedAt, mimeType, sizeBytes, artwork, uri, albumOrder,
                relinkKey, genre, onPhone, rating, explicit
            FROM (
                SELECT i.id AS itemId, i.position AS position, t.id, t.sourceId, t.nativeId, t.title, t.searchKey,
                    t.sortKey, t.artist, t.artistId, t.album, t.albumId, t.trackNo, t.discNo, t.year, t.durationMs,
                    t.addedAt, t.mimeType, t.sizeBytes, t.artwork, t.uri, t.albumOrder, t.relinkKey, t.genre,
                    t.onPhone, t.rating, t.explicit
                FROM playlist_item i JOIN track t ON t.id = i.trackId
                WHERE i.playlistId = ?
                UNION ALL
                SELECT i.id, i.position, o.id, o.sourceId, o.nativeId, o.title, LOWER(o.title), LOWER(o.title),
                    o.artist, '', o.album, '', NULL, NULL, NULL, o.durationMs, 0, o.mimeType, NULL,
                    CASE WHEN o.coverId IS NULL THEN NULL ELSE 'online:' || o.sourceId || '|' || o.coverId END,
                    NULL, 0, '', '', 0, 0, o.explicit
                FROM playlist_item i JOIN online_song o ON o.id = i.trackId
                WHERE i.playlistId = ?
            )
            ORDER BY position
            """, [id, id]) { PlaylistTrack(itemId: $0.int64("itemId"), track: LibraryTrack(row: $0)) }
    }

    /// How many songs of a playlist kept with a server have no copy there.
    public func phoneOnlyCount(_ id: String) throws -> Int {
        Int(try db.scalar("""
            SELECT COUNT(*) FROM playlist_item i JOIN playlist p ON p.id = i.playlistId
            WHERE i.playlistId = ? AND p.sourceId IS NOT NULL AND i.serverSongId IS NULL
              AND i.trackId NOT LIKE 'find:%'
              AND NOT EXISTS (SELECT 1 FROM source_track s WHERE s.mergedId = i.trackId AND s.sourceId = p.sourceId)
            """, [id]))
    }

    public func insertPlaylist(_ row: PlaylistRow) throws {
        try db.insert([row])
        changed(.playlists)
    }

    /// A change always moves updatedAt forward, even if the clock went back.
    public func renamePlaylist(_ id: String, name: String, now: Int64) throws {
        try db.run("UPDATE playlist SET name = ?, updatedAt = MAX(?, updatedAt + 1) WHERE id = ?", [name, now, id])
        changed(.playlists)
    }

    func touchPlaylist(_ id: String, now: Int64) throws {
        try db.run("UPDATE playlist SET updatedAt = MAX(?, updatedAt + 1) WHERE id = ?", [now, id])
    }

    public func playlistRow(_ id: String) throws -> PlaylistRow? { try playlist(id) }

    /// Every playlist kept with this server, made there or waiting to be.
    public func serverPlaylists(_ sourceId: String) throws -> [PlaylistRow] {
        try db.rows(PlaylistRow.self, "SELECT * FROM playlist WHERE sourceId = ?", [sourceId])
    }

    public func phonePlaylists() throws -> [PlaylistRow] {
        try db.rows(PlaylistRow.self, "SELECT * FROM playlist WHERE sourceId IS NULL")
    }

    /// Marks a playlist to be made on this server. It is linked once made.
    public func keepOnServer(_ id: String, sourceId: String) throws {
        try db.run("UPDATE playlist SET sourceId = ? WHERE id = ? AND sourceId IS NULL", [sourceId, id])
        changed(.playlists)
    }

    public func linkPlaylist(_ id: String, serverId: String, sourceId: String, syncedAt: Int64, name: String, stamp: String) throws {
        try db.run("""
            UPDATE playlist SET serverId = ?, sourceId = ?, syncedAt = ?, syncedName = ?, serverStamp = ? WHERE id = ?
            """, [serverId, sourceId, syncedAt, name, stamp, id])
        changed(.playlists)
    }

    public func markNotice(_ id: String, notice: String?) throws {
        try db.run("UPDATE playlist SET octoNotice = ? WHERE id = ?", [notice, id])
        changed(.playlists)
    }

    public func markSynced(_ id: String, syncedAt: Int64, name: String, stamp: String) throws {
        try db.run("UPDATE playlist SET syncedAt = ?, syncedName = ?, serverStamp = ? WHERE id = ?", [syncedAt, name, stamp, id])
        changed(.playlists)
    }

    /// Turns a playlist back into one only on the phone.
    public func unlinkPlaylist(_ id: String) throws {
        try db.run("""
            UPDATE playlist SET serverId = NULL, sourceId = NULL, syncedAt = NULL, syncedName = NULL, serverStamp = NULL,
                octoNotice = NULL
            WHERE id = ?
            """, [id])
        changed(.playlists)
    }

    /// Every playlist kept with this server goes back to being only on the phone.
    public func unlinkServer(_ sourceId: String) throws {
        try db.run("""
            UPDATE playlist SET serverId = NULL, sourceId = NULL, syncedAt = NULL, syncedName = NULL, serverStamp = NULL
            WHERE sourceId = ?
            """, [sourceId])
        changed(.playlists)
    }

    /// Every playlist kept with a server not among these goes back to being only on the phone.
    public func unlinkServersExcept(_ kept: [String]) throws {
        let condition = kept.isEmpty ? "sourceId IS NOT NULL" : "sourceId IS NOT NULL AND sourceId NOT IN (\(marks(kept.count)))"
        try db.run("""
            UPDATE playlist SET serverId = NULL, sourceId = NULL, syncedAt = NULL, syncedName = NULL, serverStamp = NULL
            WHERE \(condition)
            """, kept)
        changed(.playlists)
    }

    /// Deletes a playlist unless it changed since it was read.
    public func deleteUnchangedPlaylist(_ id: String, updatedAt: Int64) throws {
        try db.run("DELETE FROM playlist WHERE id = ? AND updatedAt = ?", [id, updatedAt])
        changed(.playlists)
    }

    func clearPlaylistItems(_ id: String) throws {
        try db.run("DELETE FROM playlist_item WHERE playlistId = ?", [id])
    }

    public func updatePlaylistRow(_ row: PlaylistRow) throws {
        try writePlaylistRow(row)
        changed(.playlists)
    }

    /// Writes every field of a playlist in place, keeping its songs.
    private func writePlaylistRow(_ row: PlaylistRow) throws {
        try db.run("""
            UPDATE playlist SET name = ?, createdAt = ?, updatedAt = ?, serverId = ?, sourceId = ?, syncedAt = ?,
                syncedName = ?, serverStamp = ?, octoNotice = ?
            WHERE id = ?
            """, [row.name, row.createdAt, row.updatedAt, row.serverId, row.sourceId, row.syncedAt, row.syncedName,
                  row.serverStamp, row.octoNotice, row.id])
    }

    /// A server playlist's phone copy, with its songs, in one go.
    public func insertServerPlaylist(_ row: PlaylistRow, items: [PlaylistItem]) throws {
        try batch {
            try db.insert([row])
            _ = try insertPlaylistItems(items)
            changed(.playlists)
        }
    }

    /// Swaps in the server's songs and saves the playlist as `updated`, unless it changed on the
    /// phone since it was read as `expected`. Answers whether it did.
    public func takeServerSongs(expected: PlaylistRow, items: [PlaylistItem], updated: PlaylistRow) throws -> Bool {
        try batch {
            guard let current = try playlist(expected.id), current.updatedAt == expected.updatedAt else { return false }
            try clearPlaylistItems(expected.id)
            _ = try insertPlaylistItems(items)
            try writePlaylistRow(updated)
            changed(.playlists)
            return true
        }
    }

    /// Its songs go with it.
    public func deletePlaylist(_ id: String) throws {
        try db.run("DELETE FROM playlist WHERE id = ?", [id])
        changed(.playlists)
    }

    public func playlistItems(_ id: String) throws -> [PlaylistItem] {
        try db.rows(PlaylistItem.self, "SELECT * FROM playlist_item WHERE playlistId = ? ORDER BY position", [id])
    }

    /// Answers the new rows' ids.
    func insertPlaylistItems(_ rows: [PlaylistItem]) throws -> [Int64] {
        try db.transaction {
            var ids: [Int64] = []
            for row in rows {
                try db.run(PlaylistItem.insertSQL(.abort), row.values)
                ids.append(db.lastInsertRowId)
            }
            return ids
        }
    }

    private func updatePlaylistItems(_ rows: [PlaylistItem]) throws {
        try db.runEach("UPDATE playlist_item SET playlistId = ?, trackId = ?, relinkKey = ?, position = ?, serverSongId = ? WHERE id = ?",
                       rows.map { [$0.playlistId, $0.trackId, $0.relinkKey, $0.position, $0.serverSongId, $0.id] })
    }

    private func deletePlaylistItem(_ itemId: Int64) throws {
        try db.run("DELETE FROM playlist_item WHERE id = ?", [itemId])
    }

    /// Writes only the playlist rows whose place changed.
    private func savePlaces(_ before: [PlaylistItem], _ after: [PlaylistItem]) throws {
        let unchanged = Set(before)
        try updatePlaylistItems(after.filter { !unchanged.contains($0) })
    }

    /// Adds songs at the end. Answers the new rows' ids, so the add can be taken back.
    @discardableResult
    public func addToPlaylist(_ id: String, tracks: [LibraryTrack], now: Int64) throws -> [Int64] {
        try batch {
            let start = (try playlistItems(id).last?.position).map { $0 + 1 } ?? 0
            let added = try insertPlaylistItems(appendedItems(id, start: start, tracks: tracks))
            try touchPlaylist(id, now: now)
            changed(.playlists)
            return added
        }
    }

    /// Answers the row taken out, its position set to the place it had, so it can be put back
    /// there. Nil when it was already gone.
    public func removeFromPlaylist(_ id: String, itemId: Int64, now: Int64) throws -> PlaylistItem? {
        try batch {
            let items = try playlistItems(id)
            guard let index = items.firstIndex(where: { $0.id == itemId }) else { return nil }
            try deletePlaylistItem(itemId)
            let rest = try playlistItems(id)
            try savePlaces(rest, renumbered(rest))
            try touchPlaylist(id, now: now)
            changed(.playlists)
            var removed = items[index]
            removed.position = index
            return removed
        }
    }

    /// Takes out several rows at once, such as the songs just added.
    public func removeItemsFromPlaylist(_ id: String, itemIds: [Int64], now: Int64) throws {
        try batch {
            for itemId in itemIds { try deletePlaylistItem(itemId) }
            let rest = try playlistItems(id)
            try savePlaces(rest, renumbered(rest))
            try touchPlaylist(id, now: now)
            changed(.playlists)
        }
    }

    /// Puts a row taken out back where it was, with its own id, unless the playlist is gone or the
    /// row is back already.
    public func restoreToPlaylist(_ id: String, item: PlaylistItem, now: Int64) throws {
        try batch {
            guard try playlist(id) != nil else { return }
            let items = try playlistItems(id)
            if items.contains(where: { $0.id == item.id }) { return }
            let after = restoredItems(items, item)
            _ = try insertPlaylistItems(after.filter { $0.id == item.id })
            try savePlaces(items, after.filter { $0.id != item.id })
            try touchPlaylist(id, now: now)
            changed(.playlists)
        }
    }

    /// Which of these songs each playlist has, to ask before a song goes on one twice.
    public func playlistHoldings(_ trackIds: [String]) throws -> [PlaylistHolding] {
        try trackIds.catalogChunks(lookupChunk).flatMap { chunk in
            try db.query("SELECT DISTINCT playlistId, trackId FROM playlist_item WHERE trackId IN (\(marks(chunk.count)))",
                         Array(chunk)) { PlaylistHolding(playlistId: $0.string("playlistId"), trackId: $0.string("trackId")) }
        }
    }

    public func moveInPlaylist(_ id: String, itemId: Int64, targetId: Int64, now: Int64) throws {
        try batch {
            let items = try playlistItems(id)
            try savePlaces(items, movedItem(items, itemId: itemId, targetId: targetId))
            try touchPlaylist(id, now: now)
            changed(.playlists)
        }
    }

    // MARK: Plays

    public func addPlay(_ row: PlayEvent) throws {
        try db.insert([row])
        changed(.plays)
    }

    /// Every played song the library still has; songs that are gone drop out.
    public func playedTracks() throws -> [PlayedTrack] {
        try playedTracks("""
            SELECT t.*, COUNT(*) AS plays, MAX(p.startedAt) AS lastPlayedAt
            FROM play_event p JOIN track t ON t.id = p.trackId
            GROUP BY t.id
            """, [])
    }

    /// Played songs counted from a moment on.
    public func playedTracks(since: Int64) throws -> [PlayedTrack] {
        try playedTracks("""
            SELECT t.*, COUNT(*) AS plays, MAX(p.startedAt) AS lastPlayedAt
            FROM play_event p JOIN track t ON t.id = p.trackId
            WHERE p.startedAt >= ?
            GROUP BY t.id
            """, [since])
    }

    private func playedTracks(_ sql: String, _ args: [any SQLBindable]) throws -> [PlayedTrack] {
        try db.query(sql, args) { PlayedTrack(track: LibraryTrack(row: $0), plays: $0.int("plays"), lastPlayedAt: $0.int64("lastPlayedAt")) }
    }

    /// The latest plays one by one, newest first, of songs the library still has.
    public func recentPlays(limit: Int) throws -> [PlayedAt] {
        try db.query("""
            SELECT t.*, p.startedAt AS startedAt
            FROM play_event p JOIN track t ON t.id = p.trackId
            ORDER BY p.startedAt DESC
            LIMIT ?
            """, [limit]) { PlayedAt(track: LibraryTrack(row: $0), startedAt: $0.int64("startedAt")) }
    }

    /// Every album with a played song that the library still has.
    public func playedAlbums() throws -> [PlayedAlbum] {
        try db.query("""
            SELECT a.*, MAX(p.startedAt) AS lastPlayedAt
            FROM play_event p JOIN track t ON t.id = p.trackId JOIN album a ON a.id = t.albumId
            GROUP BY a.id
            """) { PlayedAlbum(album: LibraryAlbum(row: $0), lastPlayedAt: $0.int64("lastPlayedAt")) }
    }

    /// Library songs a server has a play record for, one row per server copy.
    public func serverPlayedTracks() throws -> [ServerPlayedTrack] {
        try db.query("""
            SELECT t.*, s.nativeId AS serverId, COALESCE(s.playCount, 0) AS serverPlays, s.lastPlayedAt AS serverLastPlayedAt
            FROM source_track s JOIN track t ON t.id = s.mergedId
            WHERE s.sourceId LIKE 'server:%' AND (s.playCount > 0 OR s.lastPlayedAt IS NOT NULL)
            """) { row in
            ServerPlayedTrack(track: LibraryTrack(row: row), serverId: row.string("serverId"), serverPlays: row.int("serverPlays"),
                              serverLastPlayedAt: row.optionalInt64("serverLastPlayedAt"))
        }
    }

    /// Every album in the library with a song a server saw played.
    public func serverPlayedAlbums() throws -> [PlayedAlbum] {
        try db.query("""
            SELECT a.*, MAX(s.lastPlayedAt) AS lastPlayedAt
            FROM source_track s JOIN track t ON t.id = s.mergedId JOIN album a ON a.id = t.albumId
            WHERE s.sourceId LIKE 'server:%' AND s.lastPlayedAt IS NOT NULL
            GROUP BY a.id
            """) { PlayedAlbum(album: LibraryAlbum(row: $0), lastPlayedAt: $0.int64("lastPlayedAt")) }
    }

    // MARK: The saved queue

    public func queueItems() throws -> [QueueItemRow] {
        try db.rows(QueueItemRow.self, "SELECT * FROM queue_item ORDER BY position")
    }

    public func queueState() throws -> QueueStateRow? {
        try db.rows(QueueStateRow.self, "SELECT * FROM queue_state WHERE id = 0").first
    }

    /// Replaces the saved queue in one go, so a half-written queue is never read back.
    public func saveQueue(_ items: [QueueItemRow], state: QueueStateRow) throws {
        try batch {
            try db.run("DELETE FROM queue_item")
            for chunk in items.catalogChunks(500) { try db.insert(Array(chunk), .replace) }
            try db.insert([state], .replace)
            changed(.queue)
        }
    }

    // MARK: Following songs whose ids changed

    /// A merged copy is followed first, since it is certain; the relink key catches the rest.
    func relinkAll() throws {
        try db.transaction {
            for table in ["liked_track", "play_event", "playlist_item", "track_rating"] {
                let ignore = table == "liked_track" || table == "track_rating" ? "OR IGNORE " : ""
                try db.run("""
                    UPDATE \(ignore)\(table)
                    SET trackId = (SELECT s.mergedId FROM source_track s WHERE s.id = \(table).trackId)
                    WHERE trackId NOT IN (SELECT id FROM track)
                      AND EXISTS (SELECT 1 FROM source_track s JOIN track t ON t.id = s.mergedId WHERE s.id = \(table).trackId)
                    """)
            }
            for table in ["liked_track", "play_event", "playlist_item", "track_rating"] {
                let ignore = table == "liked_track" || table == "track_rating" ? "OR IGNORE " : ""
                try db.run("""
                    UPDATE \(ignore)\(table)
                    SET trackId = (SELECT t.id FROM track t WHERE t.relinkKey = \(table).relinkKey LIMIT 1)
                    WHERE trackId NOT IN (SELECT id FROM track)
                      AND EXISTS (SELECT 1 FROM track t WHERE t.relinkKey = \(table).relinkKey AND t.relinkKey != '')
                    """)
            }
        }
    }
}
