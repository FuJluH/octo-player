import Foundation

/// The phone's own music, as a source.
public let deviceSource = "device"

/// Whose library is in place when no server is: the phone's music alone.
public let phoneLibrary = "phone"

/// Whether a source's music joins the library: the phone's own always, a server's only while it
/// is the one in use.
public func inLibrary(_ sourceId: String, serverInUse: String?) -> Bool {
    !isServerSource(sourceId) || sourceId == serverInUse
}

/// A server song that is in the library, and the library song it is.
public struct ServerLink: Sendable, Hashable {
    public var serverId: String
    public var trackId: String
}

/// A server's copy of a library song: its id on the server, and when the server last saw it played.
public struct ServerCopy: Sendable, Hashable {
    public var trackId: String
    public var serverId: String
    public var lastPlayedAt: Int64?

    public init(trackId: String, serverId: String, lastPlayedAt: Int64? = nil) {
        self.trackId = trackId
        self.serverId = serverId
        self.lastPlayedAt = lastPlayedAt
    }
}

/// A server's copy of a library song and the listener's rating of it there, 0 for none.
public struct RatingCopy: Sendable, Hashable {
    public var trackId: String
    public var serverId: String
    public var rating: Int

    public init(trackId: String, serverId: String, rating: Int) {
        self.trackId = trackId
        self.serverId = serverId
        self.rating = rating
    }
}

/// What each source has, before merging, and the merge itself.
extension CatalogStore {
    public func sourceIds() throws -> [String] {
        try db.strings("SELECT DISTINCT sourceId FROM source_track UNION SELECT DISTINCT sourceId FROM source_album")
    }

    public func sourceTracks(_ sourceId: String) throws -> [SourceTrack] {
        try db.rows(SourceTrack.self, "SELECT * FROM source_track WHERE sourceId = ?", [sourceId])
    }

    public func sourceAlbums(_ sourceId: String) throws -> [SourceAlbum] {
        try db.rows(SourceAlbum.self, "SELECT * FROM source_album WHERE sourceId = ?", [sourceId])
    }

    public func sourceArtists(_ sourceId: String) throws -> [SourceArtist] {
        try db.rows(SourceArtist.self, "SELECT * FROM source_artist WHERE sourceId = ?", [sourceId])
    }

    /// Whether a source marks any song as in a family member's own library.
    public func marksPersonal(_ sourceId: String) throws -> Bool {
        try db.scalar("SELECT EXISTS(SELECT 1 FROM source_track WHERE sourceId = ? AND personal = 1)", [sourceId]) != 0
    }

    /// Every copy of one library song, from every source that has it.
    public func copies(_ trackId: String) throws -> [SourceTrack] {
        try db.rows(SourceTrack.self, "SELECT * FROM source_track WHERE mergedId = ?", [trackId])
    }

    /// Every copy of many library songs at once, in no particular order.
    public func copies(of trackIds: [String]) throws -> [SourceTrack] {
        try trackIds.catalogChunks(lookupChunk).flatMap { chunk in
            try db.rows(SourceTrack.self, "SELECT * FROM source_track WHERE mergedId IN (\(marks(chunk.count)))", Array(chunk))
        }
    }

    /// Every server copy already merged into a library song.
    public func serverCopies() throws -> [ServerCopy] {
        try db.query("""
            SELECT mergedId AS trackId, nativeId AS serverId, lastPlayedAt
            FROM source_track WHERE sourceId LIKE 'server:%' AND mergedId != ''
            """) { ServerCopy(trackId: $0.string("trackId"), serverId: $0.string("serverId"), lastPlayedAt: $0.optionalInt64("lastPlayedAt")) }
    }

    /// Every server copy already merged into a library song, with its rating there.
    public func serverRatings() throws -> [RatingCopy] {
        try db.query("""
            SELECT mergedId AS trackId, nativeId AS serverId, COALESCE(rating, 0) AS rating
            FROM source_track WHERE sourceId LIKE 'server:%' AND mergedId != ''
            """) { RatingCopy(trackId: $0.string("trackId"), serverId: $0.string("serverId"), rating: $0.int("rating")) }
    }

    /// Notes a rating on a library song's server copies, as sent or about to be.
    public func setServerRating(_ trackId: String, _ rating: Int) throws {
        try db.run("UPDATE source_track SET rating = ? WHERE mergedId = ? AND sourceId LIKE 'server:%'", [rating, trackId])
        changed(.sources)
    }

    /// Which of these server song ids are in the library, and the library song each one is.
    public func libraryLinks(_ sourceId: String, _ serverIds: [String]) throws -> [ServerLink] {
        try serverIds.catalogChunks(lookupChunk).flatMap { chunk in
            try db.query("""
                SELECT nativeId AS serverId, CASE WHEN mergedId = '' THEN id ELSE mergedId END AS trackId
                FROM source_track WHERE sourceId = ? AND nativeId IN (\(marks(chunk.count)))
                """, [sourceId] + Array(chunk)) { ServerLink(serverId: $0.string("serverId"), trackId: $0.string("trackId")) }
        }
    }

    /// A source album's own id on its source, by the id the library keeps.
    public func albumNativeId(_ id: String) throws -> String? {
        try db.strings("SELECT nativeId FROM source_album WHERE id = ?", [id]).first
    }

    /// Which of these server album ids are in the library.
    public func knownAlbums(_ sourceId: String, _ serverIds: [String]) throws -> [String] {
        try serverIds.catalogChunks(lookupChunk).flatMap { chunk in
            try db.strings("SELECT nativeId FROM source_album WHERE sourceId = ? AND nativeId IN (\(marks(chunk.count)))",
                           [sourceId] + Array(chunk))
        }
    }

    /// One source's artists filed under this name.
    public func artistsNamed(_ sourceId: String, key: String) throws -> [SourceArtist] {
        try db.rows(SourceArtist.self, "SELECT * FROM source_artist WHERE sourceId = ? AND searchKey = ?", [sourceId, key])
    }

    /// Which of these artist rows, by "<source>:<server id>", are in the library.
    public func knownArtists(_ ids: [String]) throws -> [String] {
        try ids.catalogChunks(lookupChunk).flatMap { chunk in
            try db.strings("SELECT id FROM source_artist WHERE id IN (\(marks(chunk.count)))", Array(chunk))
        }
    }

    /// Swaps in everything one source has, in one go.
    public func replaceSource(_ sourceId: String, tracks: [SourceTrack], albums: [SourceAlbum], artists: [SourceArtist]) throws {
        try db.transaction {
            try deleteSourceRows(sourceId)
            for chunk in artists.catalogChunks(500) { try db.insert(Array(chunk), .replace) }
            for chunk in albums.catalogChunks(500) { try db.insert(Array(chunk), .replace) }
            for chunk in tracks.catalogChunks(500) { try db.insert(Array(chunk), .replace) }
        }
        changed(.sources)
    }

    /// Adds rows to a source, replacing any with the same id.
    public func insertSourceRows(tracks: [SourceTrack] = [], albums: [SourceAlbum] = [], artists: [SourceArtist] = []) throws {
        try db.transaction {
            try db.insert(artists, .replace)
            try db.insert(albums, .replace)
            try db.insert(tracks, .replace)
        }
        changed(.sources)
    }

    public func deleteSource(_ sourceId: String) throws {
        try db.transaction { try deleteSourceRows(sourceId) }
        changed(.sources)
    }

    private func deleteSourceRows(_ sourceId: String) throws {
        try db.run("DELETE FROM source_track WHERE sourceId = ?", [sourceId])
        try db.run("DELETE FROM source_album WHERE sourceId = ?", [sourceId])
        try db.run("DELETE FROM source_artist WHERE sourceId = ?", [sourceId])
    }

    // MARK: The merge

    /// Rebuilds the library from what the sources have: only the phone and `serverInUse` join, the
    /// phone first so its songs keep their ids. Copies of sources left out lose their library song,
    /// so nothing that looks up a song's copies finds them. Afterwards likes, plays, playlist songs
    /// and ratings follow songs whose ids changed, so do favorite albums and artists and pins, and
    /// songs no server rated show the phone's rating. Returns the merged library.
    @discardableResult
    public func rebuild(serverInUse: String?) throws -> MergedCatalog {
        let all = try sourceIds()
            .filter { inLibrary($0, serverInUse: serverInUse) }
            .sorted { ($0 == deviceSource ? "" : $0) < ($1 == deviceSource ? "" : $1) }
            .map { id in
                SourceCatalog(sourceId: id, onPhone: id == deviceSource, tracks: try sourceTracks(id), albums: try sourceAlbums(id),
                              artists: try sourceArtists(id))
            }
        let merged = mergeCatalogs(all)
        try batch {
            try replaceAll(merged.tracks, merged.albums, merged.artists)
            let kept = all.map(\.sourceId)
            if kept.isEmpty {
                try db.run("UPDATE source_track SET mergedId = '' WHERE mergedId != ''")
            } else {
                try db.run("UPDATE source_track SET mergedId = '' WHERE mergedId != '' AND sourceId NOT IN (\(marks(kept.count)))", kept)
            }
            // Each copy remembers its library song, so playback can find them all.
            let rows: [[any SQLBindable]] = all.flatMap(\.tracks).map { [merged.mergedIds[$0.id] ?? $0.id, $0.id] }
            try db.runEach("UPDATE source_track SET mergedId = ? WHERE id = ?", rows)
            try relinkAll()
            try relinkFavorites()
            try showPhoneRatings()
            try relinkDownloads()
            changed([.library, .sources, .likes, .ratings, .plays, .playlists, .favorites, .pins, .downloads])
        }
        return merged
    }
}
