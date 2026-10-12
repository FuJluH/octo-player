import Foundation

// Home's rediscovery shelves: albums worth going back to, found by plain questions about the
// library's own play counts and dates. Nothing is guessed or recommended; the same library always
// gives the same shelves.

/// How one album has been listened to, from its songs.
public struct AlbumListening: Sendable, Hashable {
    public var id: String
    /// Songs the album holds.
    public var songs: Int
    /// Of them, the songs played at least once.
    public var playedSongs: Int
    /// Plays of all its songs together.
    public var plays: Int64
    /// The latest play of any of its songs, or nil when none has a date.
    public var lastPlayed: Int64?
    /// When the album came into the library, or nil when unknown.
    public var added: Int64?

    public init(id: String, songs: Int, playedSongs: Int, plays: Int64, lastPlayed: Int64?, added: Int64?) {
        self.id = id
        self.songs = songs
        self.playedSongs = playedSongs
        self.plays = plays
        self.lastPlayed = lastPlayed
        self.added = added
    }

    public var played: Bool { playedSongs > 0 || plays > 0 || lastPlayed != nil }
}

/// How long an album must have gone unplayed to count as not played lately.
public let quietDays = 180

/// How many albums each of Home's rediscovery shelves holds.
public let rediscoveryShelf = 20

private let rediscoveryDayMs: Int64 = 24 * 60 * 60 * 1000

/// The albums `keep` takes, ordered by `before` (nil on a tie), then by id, then as given, and cut
/// to `limit`.
private func rankedAlbums<T>(_ albums: [T], of: (T) -> AlbumListening, limit: Int, keep: (AlbumListening) -> Bool,
                             before: (AlbumListening, AlbumListening) -> Bool?) -> [T] {
    let kept = albums.enumerated().map { (offset: $0.offset, item: $0.element, listening: of($0.element)) }.filter { keep($0.listening) }
    let sorted = kept.sorted { a, b in
        if let first = before(a.listening, b.listening) { return first }
        if a.listening.id != b.listening.id { return a.listening.id < b.listening.id }
        return a.offset < b.offset
    }
    return sorted.prefix(max(0, limit)).map(\.item)
}

/// Albums played before but not in the last six months, the most played first: old favorites
/// that dropped out of rotation. Of two played as often, the one played longest ago first.
public func notPlayedLately<T>(_ albums: [T], of: (T) -> AlbumListening, now: Int64, limit: Int = .max) -> [T] {
    let before = now - Int64(quietDays) * rediscoveryDayMs
    return rankedAlbums(albums, of: of, limit: limit, keep: { a in a.lastPlayed.map { $0 < before } ?? false }) { a, b in
        if a.plays != b.plays { return a.plays > b.plays }
        let la = a.lastPlayed ?? .min, lb = b.lastPlayed ?? .min
        return la != lb ? la < lb : nil
    }
}

/// Albums started but not played through: some of their songs have plays and some have none. The
/// most recently played first.
public func neverFinished<T>(_ albums: [T], of: (T) -> AlbumListening, limit: Int = .max) -> [T] {
    rankedAlbums(albums, of: of, limit: limit, keep: { $0.playedSongs > 0 && $0.playedSongs < $0.songs }) { a, b in
        let la = a.lastPlayed ?? .min, lb = b.lastPlayed ?? .min
        return la != lb ? la > lb : nil
    }
}

/// Albums none of whose songs has ever been played, the newest added first.
public func neverPlayed<T>(_ albums: [T], of: (T) -> AlbumListening, limit: Int = .max) -> [T] {
    rankedAlbums(albums, of: of, limit: limit, keep: { !$0.played }) { a, b in
        let aa = a.added ?? .min, ab = b.added ?? .min
        return aa != ab ? aa > ab : nil
    }
}

/// Albums by how often their songs were played, the most first; of two played as often, the one
/// played more recently. Albums never played are left out.
public func mostPlayedAlbums<T>(_ albums: [T], of: (T) -> AlbumListening, limit: Int = .max) -> [T] {
    rankedAlbums(albums, of: of, limit: limit, keep: { $0.plays > 0 }) { a, b in
        if a.plays != b.plays { return a.plays > b.plays }
        let la = a.lastPlayed ?? .min, lb = b.lastPlayed ?? .min
        return la != lb ? la > lb : nil
    }
}

/// Home's three rediscovery shelves, each at most `limit` long. An album shows on one shelf only:
/// one that fits two keeps the first, in the order Home shows them.
public struct Rediscovery<T> {
    public var notPlayedLately: [T]
    public var neverFinished: [T]
    public var neverPlayed: [T]

    public init(notPlayedLately: [T] = [], neverFinished: [T] = [], neverPlayed: [T] = []) {
        self.notPlayedLately = notPlayedLately
        self.neverFinished = neverFinished
        self.neverPlayed = neverPlayed
    }

    public var isEmpty: Bool { notPlayedLately.isEmpty && neverFinished.isEmpty && neverPlayed.isEmpty }
}

extension Rediscovery: Equatable where T: Equatable {}
extension Rediscovery: Hashable where T: Hashable {}
extension Rediscovery: Sendable where T: Sendable {}

public func rediscovery<T>(_ albums: [T], of: (T) -> AlbumListening, now: Int64, limit: Int) -> Rediscovery<T> {
    let quiet = notPlayedLately(albums, of: of, now: now, limit: limit)
    let shown = Set(quiet.map { of($0).id })
    return Rediscovery(
        notPlayedLately: quiet,
        neverFinished: neverFinished(albums.filter { !shown.contains(of($0).id) }, of: of, limit: limit),
        neverPlayed: neverPlayed(albums, of: of, limit: limit)
    )
}

/// Each album's listening, by album id, from the songs a Subsonic library lists. An album with no
/// songs listed falls back to its own counts. The album's own play date and count join in, since a
/// server can know of plays its songs no longer carry.
public func albumListening(_ albums: [ServerAlbum], _ songs: [ServerSong]) -> [String: AlbumListening] {
    var byAlbum: [String: [ServerSong]] = [:]
    for song in songs {
        guard let albumId = song.albumId else { continue }
        byAlbum[albumId, default: []].append(song)
    }
    var listening: [String: AlbumListening] = [:]
    for album in albums {
        let own = byAlbum[album.id] ?? []
        let songTimes = own.compactMap { epochMs($0.played) }
        let songPlays = own.reduce(Int64(0)) { $0 + ($1.playCount ?? 0) }
        let playedSongs = own.filter { ($0.playCount ?? 0) > 0 || epochMs($0.played) != nil }.count
        let lastPlayed = [songTimes.max(), epochMs(album.played)].compactMap { $0 }.max()
        listening[album.id] = AlbumListening(
            id: album.id,
            songs: own.isEmpty ? album.songCount : own.count,
            playedSongs: playedSongs,
            plays: max(songPlays, album.playCount),
            lastPlayed: lastPlayed,
            added: epochMs(album.created)
        )
    }
    return listening
}

/// Each album's listening, for the rediscovery shelves, from the songs played here and on the
/// server together. A song listed twice counts once.
public func albumListening(_ albums: [LibraryAlbum], played: [PlayedTrack]) -> @Sendable (LibraryAlbum) -> AlbumListening {
    var byAlbum: [String: [PlayedTrack]] = [:]
    for row in played { byAlbum[row.track.albumId, default: []].append(row) }
    var listening: [String: AlbumListening] = [:]
    for album in albums {
        var seen = Set<String>()
        let songs = (byAlbum[album.id] ?? []).filter { seen.insert($0.track.id).inserted }
        listening[album.id] = AlbumListening(
            id: album.id,
            songs: album.songCount,
            playedSongs: songs.filter { $0.plays > 0 }.count,
            plays: songs.reduce(Int64(0)) { $0 + Int64($1.plays) },
            lastPlayed: songs.map(\.lastPlayedAt).max().flatMap { $0 > 0 ? $0 : nil },
            added: album.addedAt > 0 ? album.addedAt : nil
        )
    }
    let shown = listening
    return { album in
        shown[album.id] ?? AlbumListening(id: album.id, songs: album.songCount, playedSongs: 0, plays: 0, lastPlayed: nil,
                                          added: album.addedAt > 0 ? album.addedAt : nil)
    }
}

/// Home's rediscovery shelves: not played in six months, never finished, never played. Worked out
/// from the whole library, so run off the main thread.
public func homeRediscovery(_ albums: [LibraryAlbum], played: [PlayedTrack], now: Int64) -> Rediscovery<LibraryAlbum> {
    rediscovery(albums, of: albumListening(albums, played: played), now: now, limit: rediscoveryShelf)
}
