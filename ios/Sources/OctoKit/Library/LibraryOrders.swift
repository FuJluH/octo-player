import Foundation

// Orders put together in memory: by plays, the short lists (playlists, downloads, a folder's
// songs, favorites) and the listening of albums and artists. The long lists are ordered by
// SortQueries' SQL.

/// How much something was listened to: how many plays, and when the last was.
public struct Listening: Hashable, Sendable {
    public var plays: Int
    public var lastPlayedAt: Int64

    public init(plays: Int, lastPlayedAt: Int64) {
        self.plays = plays
        self.lastPlayedAt = lastPlayedAt
    }
}

/// `base` reordered by listening. Played items come first when descending (most or latest
/// first) and last when ascending; items never played keep their place from `base` among
/// themselves, and so do ties.
public func byListening<T>(_ base: [T], id: (T) -> String, listening: [String: Listening], mostPlayed: Bool,
                           descending: Bool) -> [T] {
    var played: [(offset: Int, item: T, heard: Listening)] = []
    var never: [T] = []
    for (offset, item) in base.enumerated() {
        if let heard = listening[id(item)], mostPlayed ? heard.plays > 0 : heard.lastPlayedAt > 0 {
            played.append((offset, item, heard))
        } else {
            never.append(item)
        }
    }
    func compare(_ a: Listening, _ b: Listening) -> Int {
        let first = mostPlayed ? (Int64(a.plays), Int64(b.plays)) : (a.lastPlayedAt, b.lastPlayedAt)
        if first.0 != first.1 { return first.0 < first.1 ? -1 : 1 }
        let second = mostPlayed ? (a.lastPlayedAt, b.lastPlayedAt) : (Int64(a.plays), Int64(b.plays))
        if second.0 != second.1 { return second.0 < second.1 ? -1 : 1 }
        return 0
    }
    // Stable: ties keep the order they had in `base`.
    played.sort { a, b in
        let c = compare(a.heard, b.heard)
        if c != 0 { return descending ? c > 0 : c < 0 }
        return a.offset < b.offset
    }
    let listened = played.map(\.item)
    return descending ? listened + never : never + listened
}

/// One key of an in-memory order.
public enum SortKey: Comparable, Sendable {
    case int(Int64)
    case text(String)

    public static func < (a: SortKey, b: SortKey) -> Bool {
        switch (a, b) {
        case (.int(let x), .int(let y)): x < y
        case (.text(let x), .text(let y)): x < y
        case (.int, .text): true
        case (.text, .int): false
        }
    }
}

/// Sorts by one key the chosen way, with items missing it last either way, then by `ties`,
/// which always run the same way. Each key is worked out once.
public func sortedByKey<T, K: Comparable>(_ items: [T], descending: Bool, key: (T) -> K?, ties: (T, T) -> Bool) -> [T] {
    let keys = items.map(key)
    let order = items.indices.sorted { a, b in
        switch (keys[a], keys[b]) {
        case (nil, nil): break
        case (nil, _): return false
        case (_, nil): return true
        case (let x?, let y?):
            if x != y { return descending ? y < x : x < y }
        }
        if ties(items[a], items[b]) { return true }
        if ties(items[b], items[a]) { return false }
        return a < b
    }
    return order.map { items[$0] }
}

/// A "comes before" test from keys compared in turn, each the way it is written.
public func ascending<T>(_ keys: ((T) -> SortKey)...) -> (T, T) -> Bool {
    { a, b in
        for key in keys {
            let ka = key(a), kb = key(b)
            if ka != kb { return ka < kb }
        }
        return false
    }
}

/// Favorite albums or artists: by when they became favorites, or by name (the sort key of an
/// album's title or an artist's name).
public func sortFavorites<T>(_ items: [T], order: ListOrder, likedAt: (T) -> Int64, name: (T) -> String,
                             id: (T) -> String) -> [T] {
    if order.by == .favorite(.name) {
        return sortedByKey(items, descending: order.descending, key: name, ties: { id($0) < id($1) })
    }
    return sortedByKey(items, descending: order.descending, key: likedAt, ties: { a, b in
        let na = name(a), nb = name(b)
        return na != nb ? na < nb : id(a) < id(b)
    })
}

/// A list in the order it was asked for. When the order is by name, each item's name to file it
/// under a letter; nil otherwise.
public struct Sorted<T: Sendable>: Sendable {
    public var items: [T]
    public var order: ListOrder
    public var headings: [String]?

    public init(items: [T], order: ListOrder, headings: [String]?) {
        self.items = items
        self.order = order
        self.headings = headings
    }
}

/// Playlists: by when changed or made, or song count, ties by name key then id; or by name.
public func sortPlaylists(_ playlists: [PlaylistSummary], _ order: ListOrder) -> [PlaylistSummary] {
    let byName = ascending({ (p: PlaylistSummary) in .text(sortKey(p.name)) }, { .text($0.id) })
    let descending = order.descending
    switch order.by.playlist {
    case .recentlyChanged: return sortedByKey(playlists, descending: descending, key: { $0.updatedAt }, ties: byName)
    case .recentlyCreated: return sortedByKey(playlists, descending: descending, key: { $0.createdAt }, ties: byName)
    case .songCount: return sortedByKey(playlists, descending: descending, key: { $0.songCount }, ties: byName)
    default: return sortedByKey(playlists, descending: descending, key: { sortKey($0.name) }, ties: ascending({ .text($0.id) }))
    }
}

/// Downloads on their way stay at the top as they were (downloading, then waiting, then
/// failed); the finished ones below go in the chosen order.
public func sortDownloads<T>(_ rows: [T], _ order: ListOrder, done: (T) -> Bool, title: (T) -> String, id: (T) -> String,
                             size: (T) -> Int64, addedAt: (T) -> Int64) -> [T] {
    let finished = rows.filter(done)
    let active = rows.filter { !done($0) }
    let byTitle: (T, T) -> Bool = { a, b in
        let ka = sortKey(title(a)), kb = sortKey(title(b))
        return ka != kb ? ka < kb : id(a) < id(b)
    }
    let descending = order.descending
    let sorted: [T] = switch order.by.download {
    case .title: sortedByKey(finished, descending: descending, key: { sortKey(title($0)) }, ties: { id($0) < id($1) })
    case .size: sortedByKey(finished, descending: descending, key: size, ties: byTitle)
    default: sortedByKey(finished, descending: descending, key: addedAt, ties: byTitle)
    }
    return active + sorted
}

/// A folder's songs. By artist here means the song's own artist.
public func sortFolderSongs(_ songs: [LibraryTrack], _ order: ListOrder) -> [LibraryTrack] {
    let descending = order.descending
    let inAlbum: [(LibraryTrack) -> SortKey] = [
        { .text($0.albumId) }, { .int(Int64($0.albumOrder)) }, { .text($0.sortKey) }, { .text($0.id) },
    ]
    func then(_ first: @escaping (LibraryTrack) -> SortKey, _ rest: [(LibraryTrack) -> SortKey]) -> (LibraryTrack, LibraryTrack) -> Bool {
        let all = [first] + rest
        return { a, b in
            for key in all {
                let x = key(a), y = key(b)
                if x != y { return x < y }
            }
            return false
        }
    }
    switch order.by.song {
    case .title:
        return sortedByKey(songs, descending: descending, key: { $0.sortKey }, ties: ascending({ .text(sortKey($0.artist)) }, { .text($0.id) }))
    case .artist:
        return sortedByKey(songs, descending: descending, key: { sortKey($0.artist) }, ties: then({ .text(sortKey($0.album)) }, inAlbum))
    case .album:
        return sortedByKey(songs, descending: descending, key: { sortKey($0.album) }, ties: then({ .text(sortKey($0.artist)) }, inAlbum))
    case .recentlyAdded:
        return sortedByKey(songs, descending: descending, key: { $0.addedAt }, ties: then(inAlbum[0], Array(inAlbum.dropFirst())))
    case .year:
        return sortedByKey(songs, descending: descending, key: { $0.year }, ties: then({ .text(sortKey($0.album)) }, inAlbum))
    case .length:
        return sortedByKey(songs, descending: descending, key: { $0.durationMs }, ties: ascending({ .text($0.sortKey) }, { .text($0.id) }))
    default:
        return descending ? songs.reversed() : songs
    }
}

// MARK: Listening of songs, albums and artists

/// Each song's listening, by song id.
public func songListening(_ played: [PlayedTrack]) -> [String: Listening] {
    var out: [String: Listening] = [:]
    for row in played { out[row.track.id] = Listening(plays: row.plays, lastPlayedAt: row.lastPlayedAt) }
    return out
}

/// Each album's listening: its songs' plays added up, and the latest play of any of them, the
/// server's album history included.
public func albumListening(_ played: [PlayedTrack], _ albums: [PlayedAlbum]) -> [String: Listening] {
    var byAlbum: [String: Listening] = [:]
    for song in played {
        if let before = byAlbum[song.track.albumId] {
            byAlbum[song.track.albumId] = Listening(plays: before.plays + song.plays, lastPlayedAt: max(before.lastPlayedAt, song.lastPlayedAt))
        } else {
            byAlbum[song.track.albumId] = Listening(plays: song.plays, lastPlayedAt: song.lastPlayedAt)
        }
    }
    for album in albums {
        if let before = byAlbum[album.album.id] {
            byAlbum[album.album.id] = Listening(plays: before.plays, lastPlayedAt: max(before.lastPlayedAt, album.lastPlayedAt))
        } else {
            byAlbum[album.album.id] = Listening(plays: 0, lastPlayedAt: album.lastPlayedAt)
        }
    }
    return byAlbum
}

/// Each artist's listening, from the songs on their albums.
public func artistListening(_ played: [PlayedTrack]) -> [String: Listening] {
    var byArtist: [String: Listening] = [:]
    for song in played {
        let id = song.track.artistId
        if let before = byArtist[id] {
            byArtist[id] = Listening(plays: before.plays + song.plays, lastPlayedAt: max(before.lastPlayedAt, song.lastPlayedAt))
        } else {
            byArtist[id] = Listening(plays: song.plays, lastPlayedAt: song.lastPlayedAt)
        }
    }
    return byArtist
}
