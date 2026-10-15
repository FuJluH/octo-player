import Foundation

/// A song asked for from this device that has not reached the library: the id it was asked for
/// with on the server, when it was asked for (milliseconds since 1970), and whether it was asked
/// for with its whole album.
public struct AskedSong: Sendable, Equatable, Hashable {
    public var serverId: String
    public var askedAt: Int64
    public var album: Bool

    public init(serverId: String, askedAt: Int64, album: Bool = false) {
        self.serverId = serverId
        self.askedAt = askedAt
        self.album = album
    }
}

/// The longest a song asked for here is taken as on its way while no list asked for after it has
/// come back, as when the server cannot be reached.
public let askedUnlistedMs: Int64 = 2 * 60_000

/// The longest a song asked for with its album is taken as on its way while no list shows it: the
/// server lists an album's songs only once it starts on the album, which can wait behind other
/// downloads.
public let askedAlbumUnlistedMs: Int64 = 30 * 60_000

/// Whether a song asked for that the server's lists do not show is still taken as on its way.
/// The server lists a song's download before it answers the ask, so the first list asked for
/// after the ask settles it: not on that list, it is not on its way (refused, forgotten, or ended
/// and cleared). Until such a list comes back it is, for `askedUnlistedMs` at most. A song asked
/// for with its album waits for the album instead, for `askedAlbumUnlistedMs` at most.
/// `listedSince` is when the newest list that came back was asked for, or nil before any did.
public func stillAsked(_ ask: AskedSong, listedSince: Int64?, now: Int64) -> Bool {
    let age = now - ask.askedAt
    if ask.album { return age >= 0 && age < askedAlbumUnlistedMs }
    return age >= 0 && age < askedUnlistedMs && (listedSince == nil || listedSince! < ask.askedAt)
}

/// How long until `stillAsked` turns false for `ask` by the clock alone, or nil when it already
/// is.
public func stillAskedForMs(_ ask: AskedSong, listedSince: Int64?, now: Int64) -> Int64? {
    guard stillAsked(ask, listedSince: listedSince, now: now) else { return nil }
    return ask.askedAt + (ask.album ? askedAlbumUnlistedMs : askedUnlistedMs) - now
}
