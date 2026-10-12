import Foundation

// The SQL behind each list's order, for the catalog's tables (track, album, artist,
// liked_track). Every piece of it is a constant here, picked by the option; nothing the listener
// types or the library holds is ever written into the text. Values such as a genre's name are
// bound to ? marks instead.
//
// Only the first key follows the chosen direction. The keys after it break ties the same way
// whichever way the list runs, so an album's songs stay in album order in a list of newest first.

/// A query and the values for its ? marks, in order.
public struct SqlQuery: Equatable, Sendable {
    public var sql: String
    public var args: [String]
    public var readsLikes: Bool

    public init(sql: String, args: [String], readsLikes: Bool) {
        self.sql = sql
        self.args = args
        self.readsLikes = readsLikes
    }
}

/// Which songs a song query lists.
public enum SongScope: Equatable, Sendable {
    case all
    case genre(String)
    case liked
}

/// One key of an ORDER BY. A key that follows the direction runs the way the listener chose;
/// any other always runs as written.
private struct SqlKey {
    var expr: String
    var follows = false
    var descending = false
}

private func chosen(_ expr: String) -> SqlKey { SqlKey(expr: expr, follows: true) }

/// Missing values (no year, no rating) go last whichever way the list runs.
private func missingLast(_ test: String) -> SqlKey { SqlKey(expr: test) }

private func orderBy(_ keys: [SqlKey], _ descending: Bool) -> String {
    keys.map { key in
        let down = key.follows ? descending : key.descending
        return down ? "\(key.expr) DESC" : key.expr
    }.joined(separator: ", ")
}

// Songs. `t` is the song; `al` and `ar` its album and album artist.
private let songTitle = "t.sortKey"
private let songArtist = "COALESCE(ar.sortKey, LOWER(t.artist))"
private let songAlbum = "COALESCE(al.sortKey, LOWER(t.album))"
private let songLiked = "EXISTS(SELECT 1 FROM liked_track lk WHERE lk.trackId = t.id)"
private let songLikedAt = "(SELECT lk.likedAt FROM liked_track lk WHERE lk.trackId = t.id)"

/// An album's songs in the album's own order.
private var inAlbumSql: [SqlKey] {
    [SqlKey(expr: "t.albumId"), SqlKey(expr: "t.albumOrder"), SqlKey(expr: songTitle), SqlKey(expr: "t.id")]
}

private func songSqlKeys(_ sort: SongSort) -> [SqlKey] {
    switch sort {
    // Orders by plays are put together from the library in title order and the listening
    // history; so is a folder's.
    case .title, .mostPlayed, .recentlyPlayed, .folderOrder:
        [chosen(songTitle), SqlKey(expr: songArtist), SqlKey(expr: "t.id")]
    case .artist: [chosen(songArtist), SqlKey(expr: songAlbum)] + inAlbumSql
    case .album: [chosen(songAlbum), SqlKey(expr: songArtist)] + inAlbumSql
    case .recentlyAdded: [chosen("t.addedAt")] + inAlbumSql
    case .year: [missingLast("t.year IS NULL"), chosen("t.year"), SqlKey(expr: songAlbum)] + inAlbumSql
    case .length: [chosen("t.durationMs"), SqlKey(expr: songTitle), SqlKey(expr: "t.id")]
    case .rating:
        [missingLast("t.rating = 0"), chosen("t.rating"), SqlKey(expr: songLiked, descending: true), SqlKey(expr: songTitle),
         SqlKey(expr: "t.id")]
    case .liked: [chosen(songLiked), SqlKey(expr: songTitle), SqlKey(expr: "t.id")]
    case .dateLiked: [missingLast("\(songLikedAt) IS NULL"), chosen(songLikedAt), SqlKey(expr: songTitle), SqlKey(expr: "t.id")]
    }
}

/// The name a song files under in a list ordered by name.
private func songSqlHeading(_ sort: SongSort) -> String {
    switch sort {
    case .title: songTitle
    case .artist: songArtist
    case .album: songAlbum
    default: "NULL"
    }
}

public func songQuery(_ sort: SongSort, descending: Bool, scope: SongScope) -> SqlQuery {
    let from = scope == .liked ? "liked_track l JOIN track t ON t.id = l.trackId" : "track t"
    var whereClause = ""
    var args: [String] = []
    if case .genre(let name) = scope {
        whereClause = "WHERE t.genre = ? COLLATE NOCASE"
        args = [name]
    }
    let sql = "SELECT t.*, \(songSqlHeading(sort)) AS heading FROM \(from) "
        + "LEFT JOIN album al ON al.id = t.albumId LEFT JOIN artist ar ON ar.id = t.artistId "
        + (whereClause.isEmpty ? "" : "\(whereClause) ")
        + "ORDER BY \(orderBy(songSqlKeys(sort), descending))"
    let readsLikes = scope == .liked || sort == .rating || sort == .liked || sort == .dateLiked
    return SqlQuery(sql: sql, args: args, readsLikes: readsLikes)
}

// Albums. `a` is the album; `ar` its artist.
private let albumTitle = "a.sortKey"
private let albumArtist = "COALESCE(ar.sortKey, LOWER(a.artist))"

private func albumSqlKeys(_ sort: AlbumSort) -> [SqlKey] {
    switch sort {
    case .title, .mostPlayed, .recentlyPlayed: [chosen(albumTitle), SqlKey(expr: albumArtist), SqlKey(expr: "a.id")]
    case .artist: [chosen(albumArtist), SqlKey(expr: albumTitle), SqlKey(expr: "a.id")]
    case .year:
        [missingLast("a.year IS NULL"), chosen("a.year"), SqlKey(expr: albumArtist), SqlKey(expr: albumTitle), SqlKey(expr: "a.id")]
    case .recentlyAdded: [chosen("a.addedAt"), SqlKey(expr: albumTitle), SqlKey(expr: "a.id")]
    case .songCount: [chosen("a.songCount"), SqlKey(expr: albumTitle), SqlKey(expr: "a.id")]
    case .length: [chosen("a.durationMs"), SqlKey(expr: albumTitle), SqlKey(expr: "a.id")]
    }
}

private func albumSqlHeading(_ sort: AlbumSort) -> String {
    switch sort {
    case .title: albumTitle
    case .artist: albumArtist
    default: "NULL"
    }
}

/// Every album, or one artist's.
public func albumQuery(_ sort: AlbumSort, descending: Bool, artistId: String? = nil) -> SqlQuery {
    let whereClause = artistId != nil ? "WHERE a.artistId = ? " : ""
    let sql = "SELECT a.*, \(albumSqlHeading(sort)) AS heading FROM album a "
        + "LEFT JOIN artist ar ON ar.id = a.artistId " + whereClause
        + "ORDER BY \(orderBy(albumSqlKeys(sort), descending))"
    return SqlQuery(sql: sql, args: artistId.map { [$0] } ?? [], readsLikes: false)
}

// Artists. `r` is the artist.
private let artistName = "r.sortKey"

/// When the newest song by the artist came into the library.
private let artistAdded = "(SELECT MAX(t.addedAt) FROM track t WHERE t.artistId = r.id)"

private func artistSqlKeys(_ sort: ArtistSort) -> [SqlKey] {
    switch sort {
    case .name, .mostPlayed, .recentlyPlayed: [chosen(artistName), SqlKey(expr: "r.id")]
    case .songCount: [chosen("r.songCount"), SqlKey(expr: artistName), SqlKey(expr: "r.id")]
    case .albumCount: [chosen("r.albumCount"), SqlKey(expr: artistName), SqlKey(expr: "r.id")]
    case .recentlyAdded: [chosen(artistAdded), SqlKey(expr: artistName), SqlKey(expr: "r.id")]
    }
}

public func artistQuery(_ sort: ArtistSort, descending: Bool) -> SqlQuery {
    let heading = sort == .name ? artistName : "NULL"
    let sql = "SELECT r.*, \(heading) AS heading FROM artist r ORDER BY \(orderBy(artistSqlKeys(sort), descending))"
    return SqlQuery(sql: sql, args: [], readsLikes: false)
}
