import Foundation

/// Favorite albums and artists, and pins on Home.
extension CatalogStore {
    // MARK: Favorite albums

    public func likedAlbumIds() throws -> [String] {
        try db.strings("SELECT albumId FROM liked_album")
    }

    public func likeAlbums(_ rows: [LikedAlbumRow]) throws {
        try db.insert(rows, .ignore)
        changed(.favorites)
    }

    public func unlikeAlbum(_ albumId: String) throws {
        try db.run("DELETE FROM liked_album WHERE albumId = ?", [albumId])
        changed(.favorites)
    }

    /// Favorite albums the library still has.
    public func likedAlbums() throws -> [LikedAlbum] {
        try db.query("SELECT a.*, l.likedAt AS likedAt FROM liked_album l JOIN album a ON a.id = l.albumId") {
            LikedAlbum(album: LibraryAlbum(row: $0), likedAt: $0.int64("likedAt"))
        }
    }

    public func likedAlbumRows() throws -> [LikedAlbumRow] {
        try db.rows(LikedAlbumRow.self, "SELECT * FROM liked_album")
    }

    // MARK: Favorite artists

    public func likedArtistIds() throws -> [String] {
        try db.strings("SELECT artistId FROM liked_artist")
    }

    public func likeArtists(_ rows: [LikedArtistRow]) throws {
        try db.insert(rows, .ignore)
        changed(.favorites)
    }

    public func unlikeArtist(_ artistId: String) throws {
        try db.run("DELETE FROM liked_artist WHERE artistId = ?", [artistId])
        changed(.favorites)
    }

    /// Favorite artists the library still has.
    public func likedArtists() throws -> [LikedArtist] {
        try db.query("SELECT r.*, l.likedAt AS likedAt FROM liked_artist l JOIN artist r ON r.id = l.artistId") {
            LikedArtist(artist: LibraryArtist(row: $0), likedAt: $0.int64("likedAt"))
        }
    }

    public func likedArtistRows() throws -> [LikedArtistRow] {
        try db.rows(LikedArtistRow.self, "SELECT * FROM liked_artist")
    }

    // MARK: Keys

    public func albumKey(_ id: String) throws -> KeyedId? {
        try db.first("SELECT id, searchKey FROM album WHERE id = ?", [id]) { KeyedId(id: $0.string("id"), searchKey: $0.string("searchKey")) }
    }

    public func artistKey(_ id: String) throws -> KeyedId? {
        try db.first("SELECT id, searchKey FROM artist WHERE id = ?", [id]) { KeyedId(id: $0.string("id"), searchKey: $0.string("searchKey")) }
    }

    func albumKeys() throws -> [KeyedId] {
        try db.query("SELECT id, searchKey FROM album") { KeyedId(id: $0.string("id"), searchKey: $0.string("searchKey")) }
    }

    func artistKeys() throws -> [KeyedId] {
        try db.query("SELECT id, searchKey FROM artist") { KeyedId(id: $0.string("id"), searchKey: $0.string("searchKey")) }
    }

    /// Which library album each server album's songs went into, and how many.
    public func serverAlbumCounts(_ sourceId: String) throws -> [CopyCount] {
        try copyCounts("""
            SELECT sa.id AS serverRowId, t.albumId AS libraryId, COUNT(*) AS songs
            FROM source_album sa JOIN source_track st ON st.albumId = sa.id JOIN track t ON t.id = st.mergedId
            WHERE sa.sourceId = ?
            GROUP BY sa.id, t.albumId
            """, [sourceId])
    }

    /// The same for a server's artists (a song's artist is its album artist), plus server artists
    /// the library kept under their own id.
    public func serverArtistCounts(_ sourceId: String) throws -> [CopyCount] {
        try copyCounts("""
            SELECT sr.id AS serverRowId, t.artistId AS libraryId, COUNT(*) AS songs
            FROM source_artist sr JOIN source_track st ON st.artistId = sr.id JOIN track t ON t.id = st.mergedId
            WHERE sr.sourceId = ?
            GROUP BY sr.id, t.artistId
            UNION ALL
            SELECT sr.id, sr.id, 0 FROM source_artist sr JOIN artist r ON r.id = sr.id
            WHERE sr.sourceId = ?
            """, [sourceId, sourceId])
    }

    func albumCopyCounts(_ ids: [String]) throws -> [CopyCount] {
        try ids.catalogChunks(lookupChunk).flatMap { chunk in
            try copyCounts("""
                SELECT st.albumId AS serverRowId, t.albumId AS libraryId, COUNT(*) AS songs
                FROM source_track st JOIN track t ON t.id = st.mergedId
                WHERE st.albumId IN (\(marks(chunk.count)))
                GROUP BY st.albumId, t.albumId
                """, Array(chunk))
        }
    }

    func artistCopyCounts(_ ids: [String]) throws -> [CopyCount] {
        try ids.catalogChunks(lookupChunk).flatMap { chunk in
            try copyCounts("""
                SELECT st.artistId AS serverRowId, t.artistId AS libraryId, COUNT(*) AS songs
                FROM source_track st JOIN track t ON t.id = st.mergedId
                WHERE st.artistId IN (\(marks(chunk.count)))
                GROUP BY st.artistId, t.artistId
                """, Array(chunk))
        }
    }

    private func copyCounts(_ sql: String, _ args: [any SQLBindable]) throws -> [CopyCount] {
        try db.query(sql, args) { CopyCount(serverRowId: $0.string(at: 0), libraryId: $0.string(at: 1), songs: Int($0.int64(at: 2))) }
    }

    // MARK: Pins

    public func pins() throws -> [PinnedItem] {
        try db.rows(PinnedItem.self, "SELECT * FROM pinned_item ORDER BY position")
    }

    /// Pins whose album, artist or playlist the library still has, in row order.
    public func shownPins() throws -> [PinnedItem] {
        try db.rows(PinnedItem.self, """
            SELECT * FROM pinned_item p
            WHERE (p.kind = 'album' AND p.itemId IN (SELECT id FROM album))
               OR (p.kind = 'artist' AND p.itemId IN (SELECT id FROM artist))
               OR (p.kind = 'playlist' AND p.itemId IN (SELECT id FROM playlist))
            ORDER BY p.position
            """)
    }

    func shownPinCount() throws -> Int {
        Int(try db.scalar("""
            SELECT COUNT(*) FROM pinned_item p
            WHERE (p.kind = 'album' AND p.itemId IN (SELECT id FROM album))
               OR (p.kind = 'artist' AND p.itemId IN (SELECT id FROM artist))
               OR (p.kind = 'playlist' AND p.itemId IN (SELECT id FROM playlist))
            """))
    }

    /// Swaps in the whole row of pins in one go.
    public func savePins(_ rows: [PinnedItem]) throws {
        try db.transaction {
            try db.run("DELETE FROM pinned_item")
            try db.insert(rows, .replace)
        }
        changed(.pins)
    }

    /// Adds a pin at the end of the row. False when Home is full.
    public func pin(_ row: PinnedItem) throws -> Bool {
        try batch {
            var last = row
            last.position = Int.max
            guard let next = withPin(try pins(), add: last, showing: try shownPinCount()) else { return false }
            try savePins(next)
            return true
        }
    }

    public func unpin(kind: String, itemId: String) throws {
        try batch { try savePins(withoutPin(try pins(), kind: kind, itemId: itemId)) }
    }

    public func moveToFront(kind: String, itemId: String) throws {
        try batch { try savePins(movedToFront(try pins(), kind: kind, itemId: itemId)) }
    }

    // MARK: Following albums and artists whose ids changed

    /// After the library is rebuilt: favorites and pins whose album or artist id vanished follow
    /// the one their songs merged into, or failing that the one now filed under the same key.
    func relinkFavorites() throws {
        let pins = try pins()
        let likedAlbums = try likedAlbumRows()
        let likedArtists = try likedArtistRows()
        if pins.isEmpty && likedAlbums.isEmpty && likedArtists.isEmpty { return }
        let albums = try albumKeys()
        let albumIds = Set(albums.map(\.id))
        let albumsByKey = Dictionary(grouping: albums, by: \.searchKey).mapValues { $0.map(\.id) }
        let artists = try artistKeys()
        let artistIds = Set(artists.map(\.id))
        let artistsByKey = Dictionary(grouping: artists, by: \.searchKey).mapValues { $0.map(\.id) }

        func held(_ kind: PinKind) -> [Held] { pins.filter { $0.kind == kind.rawValue }.map { Held(id: $0.itemId, relinkKey: $0.relinkKey) } }
        let heldAlbums = likedAlbums.map { Held(id: $0.albumId, relinkKey: $0.relinkKey) }
        let heldArtists = likedArtists.map { Held(id: $0.artistId, relinkKey: $0.relinkKey) }
        let pinnedAlbums = held(.album)
        let pinnedArtists = held(.artist)

        func vanished(_ rows: [Held], _ present: Set<String>) -> [String] { unique(rows.map(\.id).filter { !present.contains($0) }) }
        let albumsMerged = mergedInto(try albumCopyCounts(vanished(heldAlbums + pinnedAlbums, albumIds)))
        let artistsMerged = mergedInto(try artistCopyCounts(vanished(heldArtists + pinnedArtists, artistIds)))

        try db.transaction {
            for move in relinks(heldAlbums, present: albumIds, byKey: albumsByKey, merged: albumsMerged) {
                try db.run("UPDATE OR IGNORE liked_album SET albumId = ? WHERE albumId = ?", [move.to, move.from])
            }
            for move in relinks(heldArtists, present: artistIds, byKey: artistsByKey, merged: artistsMerged) {
                try db.run("UPDATE OR IGNORE liked_artist SET artistId = ? WHERE artistId = ?", [move.to, move.from])
            }
            for move in relinks(pinnedAlbums, present: albumIds, byKey: albumsByKey, merged: albumsMerged) {
                try db.run("UPDATE OR IGNORE pinned_item SET itemId = ? WHERE kind = ? AND itemId = ?", [move.to, PinKind.album.rawValue, move.from])
            }
            for move in relinks(pinnedArtists, present: artistIds, byKey: artistsByKey, merged: artistsMerged) {
                try db.run("UPDATE OR IGNORE pinned_item SET itemId = ? WHERE kind = ? AND itemId = ?", [move.to, PinKind.artist.rawValue, move.from])
            }
        }
    }
}
