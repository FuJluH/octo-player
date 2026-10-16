import Foundation

/// A genre on the Genres page: its name, how many songs, and a cover from one of its albums.
public struct GenreSummary: Sendable, Hashable {
    public var name: String
    public var songCount: Int
    public var artwork: String?
}

/// Reading the merged library.
extension CatalogStore {
    /// The newest albums, by when they were added.
    public func recentAlbums(limit: Int) throws -> [LibraryAlbum] {
        try db.rows(LibraryAlbum.self, "SELECT * FROM album ORDER BY addedAt DESC LIMIT ?", [limit])
    }

    public func randomAlbums(limit: Int) throws -> [LibraryAlbum] {
        try db.rows(LibraryAlbum.self, "SELECT * FROM album ORDER BY RANDOM() LIMIT ?", [limit])
    }

    public func randomArtists(limit: Int) throws -> [LibraryArtist] {
        try db.rows(LibraryArtist.self, "SELECT * FROM artist ORDER BY RANDOM() LIMIT ?", [limit])
    }

    /// Every library song, A to Z.
    public func allTracks() throws -> [LibraryTrack] {
        try db.rows(LibraryTrack.self, "SELECT * FROM track ORDER BY sortKey")
    }

    /// Every album, A to Z.
    public func allAlbums() throws -> [LibraryAlbum] {
        try db.rows(LibraryAlbum.self, "SELECT * FROM album ORDER BY sortKey")
    }

    /// Every artist, A to Z.
    public func allArtists() throws -> [LibraryArtist] {
        try db.rows(LibraryArtist.self, "SELECT * FROM artist ORDER BY sortKey")
    }

    /// Every song in one genre, for picking songs to keep playing.
    public func genreTrackIds(_ name: String) throws -> [String] {
        try db.strings("SELECT id FROM track WHERE genre = ? COLLATE NOCASE", [name])
    }

    public func album(_ id: String) throws -> LibraryAlbum? {
        try db.rows(LibraryAlbum.self, "SELECT * FROM album WHERE id = ?", [id]).first
    }

    public func track(_ id: String) throws -> LibraryTrack? {
        try db.rows(LibraryTrack.self, "SELECT * FROM track WHERE id = ?", [id]).first
    }

    public func artist(_ id: String) throws -> LibraryArtist? {
        try db.rows(LibraryArtist.self, "SELECT * FROM artist WHERE id = ?", [id]).first
    }

    /// The library songs with these ids, in no particular order.
    public func tracksByIdsUnordered(_ ids: [String]) throws -> [LibraryTrack] {
        try ids.catalogChunks(lookupChunk).flatMap { chunk in
            try db.rows(LibraryTrack.self, "SELECT * FROM track WHERE id IN (\(marks(chunk.count)))", Array(chunk))
        }
    }

    /// The library songs with these ids, in the order asked; ids the library lacks are left out.
    public func tracks(ids: [String]) throws -> [LibraryTrack] {
        var byId: [String: LibraryTrack] = [:]
        for track in try tracksByIdsUnordered(ids) { byId[track.id] = track }
        return ids.compactMap { byId[$0] }
    }

    public func albumTrackIds(_ albumId: String) throws -> [String] {
        try db.strings("SELECT id FROM track WHERE albumId = ? ORDER BY albumOrder", [albumId])
    }

    public func allTrackIds() throws -> [String] {
        try db.strings("SELECT id FROM track ORDER BY sortKey")
    }

    /// An album's songs in album order.
    public func albumTracks(_ albumId: String) throws -> [LibraryTrack] {
        try db.rows(LibraryTrack.self, "SELECT * FROM track WHERE albumId = ? ORDER BY albumOrder", [albumId])
    }

    /// An artist's songs, album by album, newest album first, each in its own order.
    public func artistTracks(_ artistId: String) throws -> [LibraryTrack] {
        try db.rows(LibraryTrack.self, """
            SELECT t.* FROM track t LEFT JOIN album a ON a.id = t.albumId
            WHERE t.artistId = ?
            ORDER BY COALESCE(a.year, 0) DESC, a.sortKey, t.albumId, t.albumOrder
            """, [artistId])
    }

    /// Every song's album and artist, album by album in the same order, for playing whole lists of
    /// albums or artists.
    public func trackPlaces() throws -> [TrackPlace] {
        try db.query("""
            SELECT t.id AS id, t.albumId AS albumId, t.artistId AS artistId
            FROM track t LEFT JOIN album a ON a.id = t.albumId
            ORDER BY COALESCE(a.year, 0) DESC, a.sortKey, t.albumId, t.albumOrder
            """) { TrackPlace(id: $0.string("id"), albumId: $0.string("albumId"), artistId: $0.string("artistId")) }
    }

    /// An artist's albums, newest first.
    public func artistAlbums(_ artistId: String) throws -> [LibraryAlbum] {
        try db.rows(LibraryAlbum.self, "SELECT * FROM album WHERE artistId = ? ORDER BY year DESC, sortKey", [artistId])
    }

    /// Genres by name, leaving out songs with none; case is ignored so sources agree.
    public func genres() throws -> [GenreSummary] {
        try db.query("""
            SELECT genre AS name, COUNT(*) AS songCount, MIN(artwork) AS artwork FROM track WHERE genre != ''
            GROUP BY genre COLLATE NOCASE ORDER BY genre COLLATE NOCASE
            """) { GenreSummary(name: $0.string("name"), songCount: $0.int("songCount"), artwork: $0.optionalString("artwork")) }
    }

    public func genreAlbums(_ name: String) throws -> [LibraryAlbum] {
        try db.rows(LibraryAlbum.self, """
            SELECT * FROM album WHERE id IN (SELECT albumId FROM track WHERE genre = ? COLLATE NOCASE) ORDER BY sortKey
            """, [name])
    }

    /// Artists whose search key holds `query` (already folded with `searchKey`), A to Z.
    public func searchArtists(_ query: String, limit: Int) throws -> [LibraryArtist] {
        try db.rows(LibraryArtist.self, "SELECT * FROM artist WHERE searchKey LIKE '%' || ? || '%' ORDER BY sortKey LIMIT ?",
                    [query, limit])
    }

    public func searchAlbums(_ query: String, limit: Int) throws -> [LibraryAlbum] {
        try db.rows(LibraryAlbum.self, "SELECT * FROM album WHERE searchKey LIKE '%' || ? || '%' ORDER BY sortKey LIMIT ?",
                    [query, limit])
    }

    /// Songs whose title holds the words, then those whose artist does (an artist's name matched
    /// as typed, accents and all), each by title.
    public func searchTracks(_ query: String, limit: Int) throws -> [LibraryTrack] {
        try db.rows(LibraryTrack.self,
                    "SELECT * FROM track WHERE searchKey LIKE '%' || ?1 || '%' OR lower(artist) LIKE '%' || ?1 || '%' "
                        + "ORDER BY searchKey LIKE '%' || ?1 || '%' DESC, sortKey LIMIT ?2",
                    [query, limit])
    }

    /// Exact title lookups, for telling whether something the server found is already in the
    /// library.
    public func tracksWithKeys(_ keys: [String]) throws -> [LibraryTrack] {
        try keys.catalogChunks(lookupChunk).flatMap { chunk in
            try db.rows(LibraryTrack.self, "SELECT * FROM track WHERE searchKey IN (\(marks(chunk.count)))", Array(chunk))
        }
    }

    public func albumsWithKeys(_ keys: [String]) throws -> [LibraryAlbum] {
        try keys.catalogChunks(lookupChunk).flatMap { chunk in
            try db.rows(LibraryAlbum.self, "SELECT * FROM album WHERE searchKey IN (\(marks(chunk.count)))", Array(chunk))
        }
    }

    public func artistsWithKeys(_ keys: [String]) throws -> [LibraryArtist] {
        try keys.catalogChunks(lookupChunk).flatMap { chunk in
            try db.rows(LibraryArtist.self, "SELECT * FROM artist WHERE searchKey IN (\(marks(chunk.count)))", Array(chunk))
        }
    }

    /// How many library songs came from one source.
    public func trackCount(sourceId: String) throws -> Int {
        Int(try db.scalar("SELECT COUNT(*) FROM track WHERE sourceId = ?", [sourceId]))
    }

    /// Every song in the library, from the phone and the server together.
    public func libraryTrackCount() throws -> Int {
        Int(try db.scalar("SELECT COUNT(*) FROM track"))
    }

    public func albumCount() throws -> Int { Int(try db.scalar("SELECT COUNT(*) FROM album")) }

    public func artistCount() throws -> Int { Int(try db.scalar("SELECT COUNT(*) FROM artist")) }

    /// Swaps in the whole merged library at once, so pages never read a half-written one.
    func replaceAll(_ tracks: [LibraryTrack], _ albums: [LibraryAlbum], _ artists: [LibraryArtist]) throws {
        try db.transaction {
            try db.execute("DELETE FROM track; DELETE FROM album; DELETE FROM artist;")
            for chunk in artists.catalogChunks(500) { try db.insert(Array(chunk)) }
            for chunk in albums.catalogChunks(500) { try db.insert(Array(chunk)) }
            for chunk in tracks.catalogChunks(500) { try db.insert(Array(chunk)) }
        }
        changed(.library)
    }

    // MARK: Tags read from phone files

    public func fileTags() throws -> [FileTagsRow] {
        try db.rows(FileTagsRow.self, "SELECT * FROM file_tags")
    }

    public func upsertFileTags(_ rows: [FileTagsRow]) throws {
        try db.insert(rows, .replace)
    }

    public func deleteFileTags(_ ids: [Int64]) throws {
        try db.transaction {
            for chunk in ids.catalogChunks(lookupChunk) {
                try db.run("DELETE FROM file_tags WHERE mediaId IN (\(marks(chunk.count)))", Array(chunk))
            }
        }
    }
}
