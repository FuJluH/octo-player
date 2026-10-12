import Foundation

/// A playlist as its list shows it: name, how many songs, how long, and the covers for its
/// picture.
public struct PlaylistSummary: Sendable, Hashable, Identifiable {
    public var id: String
    public var name: String
    public var songCount: Int
    public var durationMs: Int64
    public var covers: [String]
    /// Kept in step with a copy on the server.
    public var onServer: Bool
    /// When it was made and last changed, for ordering the list.
    public var createdAt: Int64
    public var updatedAt: Int64
    /// Which of Octo's notice lists it is, as the server marks it.
    public var octoNotice: String?

    public init(id: String, name: String, songCount: Int, durationMs: Int64, covers: [String], onServer: Bool = false,
                createdAt: Int64 = 0, updatedAt: Int64 = 0, octoNotice: String? = nil) {
        self.id = id
        self.name = name
        self.songCount = songCount
        self.durationMs = durationMs
        self.covers = covers
        self.onServer = onServer
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.octoNotice = octoNotice
    }
}

/// A song on a playlist, as far as asking before adding it again goes.
public struct PlaylistHolding: Sendable, Hashable {
    public var playlistId: String
    public var trackId: String

    public init(playlistId: String, trackId: String) {
        self.playlistId = playlistId
        self.trackId = trackId
    }
}

/// One song of a playlist, as much of it as the list of playlists needs.
public struct PlaylistEntry: Sendable, Hashable {
    public var playlistId: String
    public var albumId: String
    public var durationMs: Int64
    public var artwork: String?

    public init(playlistId: String, albumId: String, durationMs: Int64, artwork: String?) {
        self.playlistId = playlistId
        self.albumId = albumId
        self.durationMs = durationMs
        self.artwork = artwork
    }
}

/// A song on a playlist page, with the row it came from so it can be moved or taken out.
public struct PlaylistTrack: Sendable, Hashable, Identifiable {
    public var itemId: Int64
    public var track: LibraryTrack

    public var id: Int64 { itemId }

    public init(itemId: Int64, track: LibraryTrack) {
        self.itemId = itemId
        self.track = track
    }
}

/// Up to four covers for a playlist's picture, one per album in the order the songs come. Songs
/// with no artwork are skipped.
public func mosaicCovers(_ albumArt: [(album: String, art: String?)]) -> [String] {
    var seen = Set<String>()
    var covers: [String] = []
    for (album, art) in albumArt {
        guard let art else { continue }
        guard seen.insert(album).inserted else { continue }
        covers.append(art)
        if covers.count == 4 { break }
    }
    return covers
}

/// Every playlist with its totals, in the order the playlists were given. Entries are expected
/// in play order within each playlist.
public func summarize(_ playlists: [PlaylistRow], _ entries: [PlaylistEntry]) -> [PlaylistSummary] {
    var byPlaylist: [String: [PlaylistEntry]] = [:]
    for entry in entries { byPlaylist[entry.playlistId, default: []].append(entry) }
    return playlists.map { playlist in
        let songs = byPlaylist[playlist.id] ?? []
        return PlaylistSummary(
            id: playlist.id,
            name: playlist.name,
            songCount: songs.count,
            durationMs: songs.reduce(0) { $0 + $1.durationMs },
            covers: mosaicCovers(songs.map { ($0.albumId, $0.artwork) }),
            onServer: playlist.sourceId != nil,
            createdAt: playlist.createdAt,
            updatedAt: playlist.updatedAt,
            octoNotice: playlist.octoNotice
        )
    }
}

/// New rows for songs added to the end of a playlist, numbered on from `start`.
public func appendedItems(_ playlistId: String, start: Int, tracks: [LibraryTrack]) -> [PlaylistItem] {
    tracks.enumerated().map { offset, track in
        PlaylistItem(playlistId: playlistId, trackId: track.id, relinkKey: track.relinkKey, position: start + offset)
    }
}

/// The rows numbered 0, 1, 2... in the order given, closing any gaps.
public func renumbered(_ items: [PlaylistItem]) -> [PlaylistItem] {
    items.enumerated().map { index, item in
        var item = item
        item.position = index
        return item
    }
}

/// Puts a row taken out back at the place it had, `item.position`, and renumbers. A place past
/// the end puts it last. A row already there changes nothing.
public func restoredItems(_ items: [PlaylistItem], _ item: PlaylistItem) -> [PlaylistItem] {
    if items.contains(where: { $0.id == item.id }) { return items }
    let at = min(max(item.position, 0), items.count)
    var all = items
    all.insert(item, at: at)
    return renumbered(all)
}

/// Moves one row into the place of another, the one it was dropped on, and renumbers. Rows are
/// expected in play order. Unknown ids change nothing.
public func movedItem(_ items: [PlaylistItem], itemId: Int64, targetId: Int64) -> [PlaylistItem] {
    guard let from = items.firstIndex(where: { $0.id == itemId }),
          let to = items.firstIndex(where: { $0.id == targetId })
    else { return items }
    var all = items
    all.insert(all.remove(at: from), at: to)
    return renumbered(all)
}
