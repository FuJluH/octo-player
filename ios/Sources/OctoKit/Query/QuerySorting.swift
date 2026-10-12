import Foundation

/// Each name's sort key, worked out once per sort.
private final class SortKeys {
    private var known: [String: String] = [:]

    func of(_ text: String?) -> String {
        let text = text ?? ""
        if let key = known[text] { return key }
        let key = naturalSortKey(text)
        known[text] = key
        return key
    }
}

/// Songs in the chosen order, with the same keys and tie-breaks the song lists use: names by
/// their sort key (so "The Beatles" files under B), missing years and dates last whichever way,
/// an album's songs kept in album order among ties, and plays by the listening order.
public func sortSongsBy<F: SongFields>(_ songs: [F.Item], _ by: QuerySort.By, descending down: Bool, fields: F) -> [F.Item] {
    if by == .folderOrder { return down ? songs.reversed() : songs }
    // Every key a tie-break reads, worked out once a song.
    let keys = SortKeys()
    let titles = songs.map { keys.of(fields.title($0)) }
    let artists = songs.map { keys.of(fields.artist($0)) }
    let albums = songs.map { keys.of(fields.album($0)) }
    let albumIds = songs.map { fields.albumId($0) ?? "" }
    let discs = songs.map { fields.disc($0) ?? 0 }
    let tracks = songs.map { fields.track($0) ?? 0 }
    let ids = songs.map { fields.id($0) }
    // An album's songs in the album's own order: disc, then track.
    let inAlbum: (Int, Int) -> Int = { a, b in
        threeWay(albums[a], albums[b])
            .then(threeWay(albumIds[a], albumIds[b]))
            .then(threeWay(discs[a], discs[b]))
            .then(threeWay(tracks[a], tracks[b]))
            .then(threeWay(titles[a], titles[b]))
            .then(threeWay(ids[a], ids[b]))
    }
    let byTitle: (Int, Int) -> Int = { a, b in
        threeWay(titles[a], titles[b]).then(threeWay(artists[a], artists[b])).then(threeWay(ids[a], ids[b]))
    }
    let places: [Int]
    switch by {
    case .title:
        places = sortedPlaces(songs.count, descending: down, key: { titles[$0] }, ties: byTitle)
    case .artist:
        places = sortedPlaces(songs.count, descending: down, key: { artists[$0] }, ties: inAlbum)
    case .album:
        places = sortedPlaces(songs.count, descending: down, key: { albums[$0] }, ties: { a, b in
            threeWay(artists[a], artists[b]).then(inAlbum(a, b))
        })
    case .year:
        places = sortedPlaces(songs.count, descending: down, key: { fields.year(songs[$0]).flatMap { $0 > 0 ? $0 : nil } },
                              ties: inAlbum)
    case .length:
        places = sortedPlaces(songs.count, descending: down, key: { place -> Int? in
            let seconds = fields.seconds(songs[place])
            return seconds > 0 ? seconds : nil
        }, ties: byTitle)
    case .recentlyAdded:
        places = sortedPlaces(songs.count, descending: down, key: { fields.addedAt(songs[$0]) }, ties: inAlbum)
    case .mostPlayed, .recentlyPlayed:
        let base = sortedPlaces(songs.count, descending: false, key: { titles[$0] }, ties: byTitle)
        // Of two places with one id, the later one's listening counts.
        var listening: [String: Heard] = [:]
        for (place, song) in songs.enumerated() {
            listening[ids[place]] = Heard(plays: Int(fields.plays(song)), lastPlayedAt: fields.lastPlayedAt(song) ?? 0)
        }
        places = byListening(base, id: { ids[$0] }, listening: listening, mostPlayed: by == .mostPlayed, descending: down)
    case .rating:
        places = sortedPlaces(songs.count, descending: down, key: { place -> Int? in
            let rating = fields.rating(songs[place])
            return rating > 0 ? rating : nil
        }, ties: byTitle)
    case .liked, .dateLiked:
        places = sortedPlaces(songs.count, descending: down, key: { fields.likedAt(songs[$0]) }, ties: byTitle)
    case .folderOrder:
        places = Array(songs.indices)
    }
    return places.map { songs[$0] }
}

/// -1, 0 or 1 as `a` comes before, beside or after `b`.
private func threeWay<V: Comparable>(_ a: V, _ b: V) -> Int { a < b ? -1 : (b < a ? 1 : 0) }

private extension Int {
    /// This comparison, or `next` when it is a tie.
    func then(_ next: @autoclosure () -> Int) -> Int { self != 0 ? self : next() }
}

/// The places 0 to `count` sorted by one key the chosen way, with places missing it last either
/// way, then by `ties`, which always run the same way, then by place. Each key is worked out once.
private func sortedPlaces<K: Comparable>(_ count: Int, descending: Bool, key: (Int) -> K?, ties: (Int, Int) -> Int) -> [Int] {
    let keys = (0..<count).map(key)
    return (0..<count).sorted { a, b in
        let byKey: Int
        switch (keys[a], keys[b]) {
        case (nil, nil): byKey = 0
        case (nil, _): byKey = 1
        case (_, nil): byKey = -1
        case let (ka?, kb?): byKey = descending ? threeWay(kb, ka) : threeWay(ka, kb)
        }
        if byKey != 0 { return byKey < 0 }
        let tie = ties(a, b)
        if tie != 0 { return tie < 0 }
        return a < b
    }
}

/// How much a song was listened to: how many plays, and when the last was.
private struct Heard {
    let plays: Int
    let lastPlayedAt: Int64
}

/// `base` reordered by listening. Played items come first when descending (most or latest first)
/// and last when ascending; items never played keep their place from `base` among themselves, and
/// so do ties.
private func byListening<T>(_ base: [T], id: (T) -> String, listening: [String: Heard], mostPlayed: Bool,
                            descending: Bool) -> [T] {
    var played: [(item: T, heard: Heard, place: Int)] = []
    var never: [T] = []
    for (place, item) in base.enumerated() {
        if let heard = listening[id(item)], mostPlayed ? heard.plays > 0 : heard.lastPlayedAt > 0 {
            played.append((item, heard, place))
        } else {
            never.append(item)
        }
    }
    played.sort { a, b in
        let order = mostPlayed
            ? threeWay(a.heard.plays, b.heard.plays).then(threeWay(a.heard.lastPlayedAt, b.heard.lastPlayedAt))
            : threeWay(a.heard.lastPlayedAt, b.heard.lastPlayedAt).then(threeWay(a.heard.plays, b.heard.plays))
        let directed = descending ? -order : order
        if directed != 0 { return directed < 0 }
        return a.place < b.place
    }
    let listened = played.map(\.item)
    return descending ? listened + never : never + listened
}
