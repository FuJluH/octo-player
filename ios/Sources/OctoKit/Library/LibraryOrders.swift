import Foundation

// Every library list in the order the listener chose. Only the first key follows the chosen
// direction; the keys after it break ties the same way whichever way the list runs, so an
// album's songs stay in album order in a list of newest first. Missing values (no year, no
// rating, never liked) go last whichever way the list runs.

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
        let first = mostPlayed ? (a.plays, b.plays) : (Int(clamping: a.lastPlayedAt), Int(clamping: b.lastPlayedAt))
        if first.0 != first.1 { return first.0 < first.1 ? -1 : 1 }
        let second = mostPlayed ? (Int(clamping: a.lastPlayedAt), Int(clamping: b.lastPlayedAt)) : (a.plays, b.plays)
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

/// One key of an order that can be missing: missing ones go last either way.
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
public func sortedByKey<T, K: Comparable>(_ items: [T], descending: Bool, key: (T) -> K?,
                                          ties: (T, T) -> Bool) -> [T] {
    let keys = items.map(key)
    let order = items.indices.sorted { a, b in
        let ka = keys[a]
        let kb = keys[b]
        switch (ka, kb) {
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

/// Builds a "comes before" test from keys compared in turn, each the way it is written.
public func ascending<T>(_ keys: ((T) -> SortKey)...) -> (T, T) -> Bool {
    { a, b in
        for key in keys {
            let ka = key(a)
            let kb = key(b)
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

// MARK: Songs

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

/// A key that runs as written, one that follows the chosen direction, or a test that puts
/// missing values last.
private enum Key<T> {
    case asWritten((T) -> SortKey)
    case chosen((T) -> SortKey)
    case asWrittenDescending((T) -> SortKey)
    case missingLast((T) -> Bool)
}

private func order<T>(_ items: [T], keys: [Key<T>], descending: Bool) -> [T] {
    items.sorted { a, b in
        for key in keys {
            switch key {
            case .asWritten(let k):
                let x = k(a), y = k(b)
                if x != y { return x < y }
            case .asWrittenDescending(let k):
                let x = k(a), y = k(b)
                if x != y { return y < x }
            case .chosen(let k):
                let x = k(a), y = k(b)
                if x != y { return descending ? y < x : x < y }
            case .missingLast(let missing):
                let x = missing(a), y = missing(b)
                if x != y { return !x }
            }
        }
        return false
    }
}

private var inAlbumOrder: [Key<ShownSong>] {
    [.asWritten { .text($0.albumId) }, .asWritten { .int(Int64($0.albumOrder)) },
     .asWritten { .text($0.sortKey) }, .asWritten { .text($0.id) }]
}

private func songKeys(_ sort: SongSort) -> [Key<ShownSong>] {
    switch sort {
    case .title, .mostPlayed, .recentlyPlayed, .folderOrder:
        [.chosen { .text($0.sortKey) }, .asWritten { .text($0.artistKey) }, .asWritten { .text($0.id) }]
    case .artist:
        [.chosen { .text($0.artistKey) }, .asWritten { .text($0.albumKey) }] + inAlbumOrder
    case .album:
        [.chosen { .text($0.albumKey) }, .asWritten { .text($0.artistKey) }] + inAlbumOrder
    case .recentlyAdded:
        [.chosen { .int($0.addedAt) }] + inAlbumOrder
    case .year:
        [.missingLast { $0.year == nil }, .chosen { .int(Int64($0.year ?? 0)) }, .asWritten { .text($0.albumKey) }] + inAlbumOrder
    case .length:
        [.chosen { .int($0.durationMs) }, .asWritten { .text($0.sortKey) }, .asWritten { .text($0.id) }]
    case .rating:
        [.missingLast { $0.rating == 0 }, .chosen { .int(Int64($0.rating)) }, .asWrittenDescending { .int($0.liked ? 1 : 0) },
         .asWritten { .text($0.sortKey) }, .asWritten { .text($0.id) }]
    case .liked:
        [.chosen { .int($0.liked ? 1 : 0) }, .asWritten { .text($0.sortKey) }, .asWritten { .text($0.id) }]
    case .dateLiked:
        [.missingLast { $0.likedAt == nil }, .chosen { .int($0.likedAt ?? 0) }, .asWritten { .text($0.sortKey) },
         .asWritten { .text($0.id) }]
    }
}

/// The name a song files under in a list ordered by name.
private func songHeading(_ sort: SongSort, _ track: ShownSong) -> String? {
    switch sort {
    case .title: track.sortKey
    case .artist: track.artistKey
    case .album: track.albumKey
    default: nil
    }
}

/// Songs in an order. Orders by plays are put together from the title order and each song's
/// listening; they have no headings.
public func sortSongs(_ tracks: [ShownSong], _ order: ListOrder) -> Sorted<ShownSong> {
    let sort = order.by.song ?? .title
    let sorted = OctoKit.order(tracks, keys: songKeys(sort), descending: order.descending)
    if sort.byListening {
        var listening: [String: Listening] = [:]
        for track in tracks { listening[track.id] = Listening(plays: track.plays, lastPlayedAt: track.lastPlayedAt) }
        return Sorted(items: byListening(sorted, id: \.id, listening: listening, mostPlayed: sort == .mostPlayed,
                                         descending: order.descending),
                      order: order, headings: nil)
    }
    let headings = sort.byName ? sorted.map { songHeading(sort, $0) ?? "" } : nil
    return Sorted(items: sorted, order: order, headings: headings)
}

/// The liked songs only, in an order.
public func likedSongs(_ tracks: [ShownSong], _ order: ListOrder) -> Sorted<ShownSong> {
    sortSongs(tracks.filter(\.liked), order)
}

/// A genre's songs: those whose genre is the name, ignoring case.
public func genreSongs(_ tracks: [ShownSong], genre: String, _ order: ListOrder) -> Sorted<ShownSong> {
    let name = genre.lowercased()
    return sortSongs(tracks.filter { $0.genre.lowercased() == name }, order)
}

// MARK: Albums

private func albumKeys(_ sort: AlbumSort) -> [Key<ShownAlbum>] {
    switch sort {
    case .title, .mostPlayed, .recentlyPlayed:
        [.chosen { .text($0.sortKey) }, .asWritten { .text($0.artistKey) }, .asWritten { .text($0.id) }]
    case .artist:
        [.chosen { .text($0.artistKey) }, .asWritten { .text($0.sortKey) }, .asWritten { .text($0.id) }]
    case .year:
        [.missingLast { $0.year == nil }, .chosen { .int(Int64($0.year ?? 0)) }, .asWritten { .text($0.artistKey) },
         .asWritten { .text($0.sortKey) }, .asWritten { .text($0.id) }]
    case .recentlyAdded:
        [.chosen { .int($0.addedAt) }, .asWritten { .text($0.sortKey) }, .asWritten { .text($0.id) }]
    case .songCount:
        [.chosen { .int(Int64($0.songCount)) }, .asWritten { .text($0.sortKey) }, .asWritten { .text($0.id) }]
    case .length:
        [.chosen { .int($0.durationMs) }, .asWritten { .text($0.sortKey) }, .asWritten { .text($0.id) }]
    }
}

/// Albums in an order. Headings only for Title and Artist.
public func sortAlbums(_ albums: [ShownAlbum], _ order: ListOrder) -> Sorted<ShownAlbum> {
    let sort = order.by.album ?? .title
    let sorted = OctoKit.order(albums, keys: albumKeys(sort), descending: order.descending)
    if sort.byListening {
        var listening: [String: Listening] = [:]
        for album in albums { listening[album.id] = Listening(plays: album.plays, lastPlayedAt: album.lastPlayedAt) }
        return Sorted(items: byListening(sorted, id: \.id, listening: listening, mostPlayed: sort == .mostPlayed,
                                         descending: order.descending),
                      order: order, headings: nil)
    }
    let headings: [String]? = switch sort {
    case .title: sorted.map(\.sortKey)
    case .artist: sorted.map(\.artistKey)
    default: nil
    }
    return Sorted(items: sorted, order: order, headings: headings)
}

// MARK: Artists

private func artistKeys(_ sort: ArtistSort) -> [Key<ShownArtist>] {
    switch sort {
    case .name, .mostPlayed, .recentlyPlayed: [.chosen { .text($0.sortKey) }, .asWritten { .text($0.id) }]
    case .songCount: [.chosen { .int(Int64($0.songCount)) }, .asWritten { .text($0.sortKey) }, .asWritten { .text($0.id) }]
    case .albumCount: [.chosen { .int(Int64($0.albumCount)) }, .asWritten { .text($0.sortKey) }, .asWritten { .text($0.id) }]
    case .recentlyAdded: [.chosen { .int($0.addedAt) }, .asWritten { .text($0.sortKey) }, .asWritten { .text($0.id) }]
    }
}

/// Artists in an order. Headings only for Name.
public func sortArtists(_ artists: [ShownArtist], _ order: ListOrder) -> Sorted<ShownArtist> {
    let sort = order.by.artist ?? .name
    let sorted = OctoKit.order(artists, keys: artistKeys(sort), descending: order.descending)
    if sort.byListening {
        var listening: [String: Listening] = [:]
        for artist in artists { listening[artist.id] = Listening(plays: artist.plays, lastPlayedAt: artist.lastPlayedAt) }
        return Sorted(items: byListening(sorted, id: \.id, listening: listening, mostPlayed: sort == .mostPlayed,
                                         descending: order.descending),
                      order: order, headings: nil)
    }
    return Sorted(items: sorted, order: order, headings: sort == .name ? sorted.map(\.sortKey) : nil)
}

// MARK: Short lists

/// Playlists: by when changed or made, or song count, ties by name then id; or by name.
public func sortPlaylists(_ playlists: [ShownPlaylist], _ order: ListOrder) -> [ShownPlaylist] {
    let byName = ascending({ (p: ShownPlaylist) in .text(sortKey(p.name)) }, { .text($0.id) })
    let descending = order.descending
    switch order.by.playlist {
    case .recentlyChanged: return sortedByKey(playlists, descending: descending, key: { $0.updatedAt }, ties: byName)
    case .recentlyCreated: return sortedByKey(playlists, descending: descending, key: { $0.createdAt }, ties: byName)
    case .songCount: return sortedByKey(playlists, descending: descending, key: { $0.songCount }, ties: byName)
    default: return sortedByKey(playlists, descending: descending, key: { sortKey($0.name) }, ties: ascending({ .text($0.id) }))
    }
}

/// A folder's songs. By artist here means the song's own artist.
public func sortFolderSongs(_ songs: [ShownSong], _ order: ListOrder) -> [ShownSong] {
    let descending = order.descending
    let inAlbum: [(ShownSong) -> SortKey] = [
        { .text($0.albumId) }, { .int(Int64($0.albumOrder)) }, { .text($0.sortKey) }, { .text($0.id) },
    ]
    func then(_ first: @escaping (ShownSong) -> SortKey, _ rest: [(ShownSong) -> SortKey]) -> (ShownSong, ShownSong) -> Bool {
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
        return sortedByKey(songs, descending: descending, key: { $0.sortKey },
                           ties: ascending({ .text(sortKey($0.artist)) }, { .text($0.id) }))
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

// MARK: Listening of albums and artists

/// Each album's listening: its songs' plays added up, and the latest play of any of them, with
/// the server's album history (`albumsPlayed`, the last time each album was played) too.
public func albumListening(_ tracks: [ShownSong], albumsPlayed: [String: Int64] = [:]) -> [String: Listening] {
    var byAlbum: [String: Listening] = [:]
    for track in tracks where track.plays > 0 || track.lastPlayedAt > 0 {
        if let before = byAlbum[track.albumId] {
            byAlbum[track.albumId] = Listening(plays: before.plays + track.plays, lastPlayedAt: max(before.lastPlayedAt, track.lastPlayedAt))
        } else {
            byAlbum[track.albumId] = Listening(plays: track.plays, lastPlayedAt: track.lastPlayedAt)
        }
    }
    for (albumId, at) in albumsPlayed {
        if let before = byAlbum[albumId] {
            byAlbum[albumId] = Listening(plays: before.plays, lastPlayedAt: max(before.lastPlayedAt, at))
        } else {
            byAlbum[albumId] = Listening(plays: 0, lastPlayedAt: at)
        }
    }
    return byAlbum
}

/// Each artist's listening, from their songs, grouped by `artistId`.
public func artistListening(_ tracks: [ShownSong], artistId: (ShownSong) -> String = \.artistId) -> [String: Listening] {
    var byArtist: [String: Listening] = [:]
    for track in tracks where track.plays > 0 || track.lastPlayedAt > 0 {
        let id = artistId(track)
        if let before = byArtist[id] {
            byArtist[id] = Listening(plays: before.plays + track.plays, lastPlayedAt: max(before.lastPlayedAt, track.lastPlayedAt))
        } else {
            byArtist[id] = Listening(plays: track.plays, lastPlayedAt: track.lastPlayedAt)
        }
    }
    return byArtist
}
