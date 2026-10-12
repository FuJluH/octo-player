import Foundation

/// A favorite album with when it became one, for the Favorites page.
public struct LikedAlbum: Sendable, Hashable {
    public var album: LibraryAlbum
    public var likedAt: Int64

    public init(album: LibraryAlbum, likedAt: Int64) {
        self.album = album
        self.likedAt = likedAt
    }
}

public struct LikedArtist: Sendable, Hashable {
    public var artist: LibraryArtist
    public var likedAt: Int64

    public init(artist: LibraryArtist, likedAt: Int64) {
        self.artist = artist
        self.likedAt = likedAt
    }
}

/// A library album or artist id and its search key, for finding one again.
public struct KeyedId: Sendable, Hashable {
    public var id: String
    public var searchKey: String

    public init(id: String, searchKey: String) {
        self.id = id
        self.searchKey = searchKey
    }
}

/// How many songs of one source album (or artist) row went into one library album (or artist)
/// when the library was merged.
public struct CopyCount: Sendable, Hashable {
    public var serverRowId: String
    public var libraryId: String
    public var songs: Int

    public init(serverRowId: String, libraryId: String, songs: Int) {
        self.serverRowId = serverRowId
        self.libraryId = libraryId
        self.songs = songs
    }
}

/// Home holds at most this many pins.
public let pinLimit = 12

/// A favorite or pin that points at something by id, with its relink key.
public struct Held: Sendable, Hashable {
    public var id: String
    public var relinkKey: String

    public init(id: String, relinkKey: String) {
        self.id = id
        self.relinkKey = relinkKey
    }
}

/// A held id that moves to the library id it now lives under.
public struct Relink: Sendable, Hashable {
    public var from: String
    public var to: String

    public init(from: String, to: String) {
        self.from = from
        self.to = to
    }
}

/// Which held ids should move after a rebuild, the way liked songs do: only ids the library no
/// longer has move, and never onto an id already held (that one stays as it was). An album or
/// artist that merged into another follows it (`merged`, from `mergedInto`). Failing that, it
/// moves to the id with the same relink key; when several share it, the first by id wins.
public func relinks(_ held: [Held], present: Set<String>, byKey: [String: [String]],
                    merged: [String: String] = [:]) -> [Relink] {
    var taken = Set(held.map(\.id))
    var moves: [Relink] = []
    for row in held.sorted(by: { $0.id < $1.id }) {
        if present.contains(row.id) { continue }
        let followed = merged[row.id].flatMap { present.contains($0) ? $0 : nil }
        let to: String?
        if let followed {
            to = taken.contains(followed) ? nil : followed
        } else if row.relinkKey.isEmpty {
            to = nil
        } else {
            to = (byKey[row.relinkKey] ?? []).sorted().first { !taken.contains($0) }
        }
        guard let to else { continue }
        taken.insert(to)
        moves.append(Relink(from: row.id, to: to))
    }
    return moves
}

/// Where each album (or artist) the library no longer has under its own id went when the
/// sources were merged: the library one that took most of its songs, the first by id on a tie.
public func mergedInto(_ counts: [CopyCount]) -> [String: String] {
    var groups: [String: [CopyCount]] = [:]
    for count in counts { groups[count.serverRowId, default: []].append(count) }
    return groups.mapValues { links in
        links.sorted { a, b in a.songs != b.songs ? a.songs > b.songs : a.libraryId < b.libraryId }[0].libraryId
    }
}

/// Pins in row order.
public func inPinOrder(_ pins: [PinnedItem]) -> [PinnedItem] {
    pins.sorted { a, b in
        if a.position != b.position { return a.position < b.position }
        if a.kind != b.kind { return a.kind < b.kind }
        return a.itemId < b.itemId
    }
}

private func renumberedPins(_ pins: [PinnedItem]) -> [PinnedItem] {
    pins.enumerated().map { index, pin in
        var pin = pin
        pin.position = index
        return pin
    }
}

/// The pins with one more at the end. `showing` is how many pins Home can show now (pins whose
/// album, artist or playlist is gone do not count). Nil when Home is full. Pinning something
/// already pinned changes nothing.
public func withPin(_ pins: [PinnedItem], add: PinnedItem, showing: Int) -> [PinnedItem]? {
    let ordered = inPinOrder(pins)
    if ordered.contains(where: { $0.kind == add.kind && $0.itemId == add.itemId }) { return ordered }
    if showing >= pinLimit { return nil }
    return renumberedPins(ordered + [add])
}

/// The pins without one, the rest closed up.
public func withoutPin(_ pins: [PinnedItem], kind: String, itemId: String) -> [PinnedItem] {
    renumberedPins(inPinOrder(pins).filter { !($0.kind == kind && $0.itemId == itemId) })
}

/// The pins with one moved to the front, the rest keeping their order.
public func movedToFront(_ pins: [PinnedItem], kind: String, itemId: String) -> [PinnedItem] {
    let ordered = inPinOrder(pins)
    guard let moving = ordered.first(where: { $0.kind == kind && $0.itemId == itemId }) else { return ordered }
    return renumberedPins([moving] + ordered.filter { $0 != moving })
}
