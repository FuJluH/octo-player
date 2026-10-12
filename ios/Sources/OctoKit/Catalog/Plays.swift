import Foundation

/// A song still in the library, with how often and when it was last played.
public struct PlayedTrack: Sendable, Hashable {
    public var track: LibraryTrack
    public var plays: Int
    public var lastPlayedAt: Int64

    public init(track: LibraryTrack, plays: Int, lastPlayedAt: Int64) {
        self.track = track
        self.plays = plays
        self.lastPlayedAt = lastPlayedAt
    }
}

/// One play of a song still in the library, and when it started.
public struct PlayedAt: Sendable, Hashable {
    public var track: LibraryTrack
    public var startedAt: Int64

    public init(track: LibraryTrack, startedAt: Int64) {
        self.track = track
        self.startedAt = startedAt
    }
}

/// An album still in the library, with when any of its songs was last played.
public struct PlayedAlbum: Sendable, Hashable {
    public var album: LibraryAlbum
    public var lastPlayedAt: Int64

    public init(album: LibraryAlbum, lastPlayedAt: Int64) {
        self.album = album
        self.lastPlayedAt = lastPlayedAt
    }
}

/// Albums by their latest play, newest first.
public func byLatestPlay(_ albums: [PlayedAlbum], limit: Int) -> [LibraryAlbum] {
    Array(albums.sorted { a, b in
        if a.lastPlayedAt != b.lastPlayedAt { return a.lastPlayedAt > b.lastPlayedAt }
        return a.album.id < b.album.id
    }.prefix(limit).map(\.album))
}

/// Songs by how often they were played. Of two played as often, the one played more recently
/// comes first; the id keeps the order steady after that.
public func byPlayCount(_ tracks: [PlayedTrack], limit: Int) -> [LibraryTrack] {
    Array(tracks.sorted { a, b in
        if a.plays != b.plays { return a.plays > b.plays }
        if a.lastPlayedAt != b.lastPlayedAt { return a.lastPlayedAt > b.lastPlayedAt }
        return a.track.id < b.track.id
    }.prefix(limit).map(\.track))
}

/// An artist's songs, given album by album. Once any of them has been played, the most played
/// come first (of two played as often, the one played last), and the rest follow in the order
/// given.
public func artistSongOrder(_ tracks: [LibraryTrack], played: [PlayedTrack]) -> [LibraryTrack] {
    // A song listed twice counts by its last row.
    var plays: [String: PlayedTrack] = [:]
    for row in played { plays[row.track.id] = row }
    let heard = tracks.compactMap { track in plays[track.id].map { (track: track, play: $0) } }
    let rest = tracks.filter { plays[$0.id] == nil }
    if heard.isEmpty { return tracks }
    let sorted = heard.enumerated().sorted { a, b in
        let pa = a.element.play, pb = b.element.play
        if pa.plays != pb.plays { return pa.plays > pb.plays }
        if pa.lastPlayedAt != pb.lastPlayedAt { return pa.lastPlayedAt > pb.lastPlayedAt }
        return a.offset < b.offset
    }.map(\.element.track)
    return sorted + rest
}

/// Where a song sits: its album and its artist.
public struct TrackPlace: Sendable, Hashable {
    public var id: String
    public var albumId: String
    public var artistId: String

    public init(id: String, albumId: String, artistId: String) {
        self.id = id
        self.albumId = albumId
        self.artistId = artistId
    }
}

/// The songs of whole groups (albums or artists) in the groups' order, each group's songs in the
/// order given. Groups not listed are left out.
public func songsInGroupOrder(_ places: [TrackPlace], groupOf: (TrackPlace) -> String, groups: [String]) -> [String] {
    var byGroup: [String: [String]] = [:]
    for place in places { byGroup[groupOf(place), default: []].append(place.id) }
    var seen = Set<String>()
    return groups.filter { seen.insert($0).inserted }.flatMap { byGroup[$0] ?? [] }
}
