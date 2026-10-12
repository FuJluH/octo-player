import Foundation

// Keeps playlists on the phone and on the server the same, both ways. Each linked playlist is
// compared with what both sides last agreed on: the phone's side changed when it was edited after
// that (updatedAt past syncedAt), the server's when its changed time or song count differ from the
// ones noted then. Only one side changed: that side's playlist is copied to the other. Both
// changed: the server wins for the songs, and a name changed on the phone wins over the server's
// and is sent there. A playlist gone from the server goes from the phone too, unless it was
// changed here since; then it stays as a playlist only on the phone.

/// Octo's stations are also read-only playlists with ids starting "or".
private let stationPrefix = "or"

/// A server playlist as the list of them shows it. The stamp is its changed time and song count
/// together, which move whenever it changes.
public struct ServerPlaylist: Sendable, Hashable {
    public var id: String
    public var name: String
    public var stamp: String

    public init(_ id: String, _ name: String, _ stamp: String) {
        self.id = id
        self.name = name
        self.stamp = stamp
    }
}

/// A playlist on the phone linked to a server one, and what both sides last agreed on.
public struct LinkedPlaylist: Sendable, Hashable {
    public var localId: String
    public var serverId: String
    public var name: String
    /// Changed on the phone since both sides last agreed.
    public var edited: Bool
    public var syncedName: String?
    public var syncedStamp: String?

    public init(_ localId: String, _ serverId: String, _ name: String, _ edited: Bool, _ syncedName: String?, _ syncedStamp: String?) {
        self.localId = localId
        self.serverId = serverId
        self.name = name
        self.edited = edited
        self.syncedName = syncedName
        self.syncedStamp = syncedStamp
    }
}

public enum PlaylistStep: Sendable, Hashable {
    /// New on the server: make a copy on the phone.
    case importing(serverId: String, stamp: String)
    /// Take the server's songs. With `keepName` the phone's name stays and is sent to the server;
    /// otherwise the server's name is taken too.
    case pull(localId: String, serverId: String, stamp: String, keepName: Bool)
    /// Send the phone's songs and name.
    case push(localId: String, serverId: String)
    /// Make a playlist from the phone on the server, and link the two.
    case create(localId: String)
    /// Gone from the server and not changed here: delete the phone's copy.
    case remove(localId: String)
    /// Gone from the server, or no longer one to keep in step, but changed here: keep it as a
    /// playlist only on the phone.
    case unlink(localId: String)
    /// Deleted on the phone: delete it on the server.
    case deleteOnServer(serverId: String)
    /// A deletion still waiting for a playlist the server no longer has.
    case forgetDeletion(serverId: String)
}

public func stampOf(_ changed: String?, _ songCount: Int) -> String { "\(changed ?? "")|\(songCount)" }

/// Server playlists worth a copy on the phone: the signed-in user's own, leaving out read-only
/// ones and stations, which the stations shelf shows.
public func importable(_ playlists: [ServerPlaylistInfo], stationIds: Set<String>, username: String) -> [ServerPlaylistInfo] {
    playlists.filter { !$0.readonly && !stationIds.contains($0.id) && ownedBy($0.owner, username) }
}

/// How long the phone's copy of the server's playlists counts as fresh when the playlists come on
/// screen.
public let playlistsFreshMs: Int64 = 60_000

/// Whether the server's playlists are worth bringing in again now.
public func playlistsStale(_ now: Int64, _ lastMs: Int64) -> Bool { now - lastMs >= playlistsFreshMs }

/// Playlists that could be stations the server did not mark read-only, so the list of stations is
/// worth asking for.
public func stationSuspects(_ playlists: [ServerPlaylistInfo]) -> [ServerPlaylistInfo] {
    playlists.filter { !$0.readonly && $0.id.hasPrefix(stationPrefix) }
}

/// A playlist with no owner named, or when the user is not known, counts as the user's own.
private func ownedBy(_ owner: String?, _ username: String) -> Bool {
    guard let owner, !trimmed(owner).isEmpty else { return true }
    return trimmed(username).isEmpty || owner.lowercased() == username.lowercased()
}

/// Everything that brings both sides together. `others` are server playlists that exist but are
/// not to be kept in step; `waiting` are phone playlists to be made on the server; `deleted` are
/// server playlists deleted on the phone and not yet on the server.
public func planPlaylists(server: [ServerPlaylist], others: Set<String>, linked: [LinkedPlaylist], waiting: [String],
                          deleted: Set<String>) -> [PlaylistStep] {
    var byId: [String: ServerPlaylist] = [:]
    for playlist in server where byId[playlist.id] == nil { byId[playlist.id] = playlist }
    var steps: [PlaylistStep] = []
    for id in deleted.sorted() {
        steps.append(byId[id] != nil ? .deleteOnServer(serverId: id) : .forgetDeletion(serverId: id))
    }
    for playlist in linked {
        if let step = planLinked(byId[playlist.serverId], playlist, stillThere: others.contains(playlist.serverId)) { steps.append(step) }
    }
    let known = Set(linked.map(\.serverId))
    for playlist in server where !known.contains(playlist.id) && !deleted.contains(playlist.id) {
        steps.append(.importing(serverId: playlist.id, stamp: playlist.stamp))
    }
    steps += waiting.map { .create(localId: $0) }
    return steps
}

/// What one linked playlist needs, given the server's playlist (nil when the server no longer
/// lists it as one to keep). Nil when both agree.
public func planLinked(_ server: ServerPlaylist?, _ playlist: LinkedPlaylist, stillThere: Bool = false) -> PlaylistStep? {
    guard let server else {
        return playlist.edited || stillThere ? .unlink(localId: playlist.localId) : .remove(localId: playlist.localId)
    }
    let serverChanged = server.stamp != playlist.syncedStamp
    if serverChanged && playlist.edited {
        // Both changed: the server's songs, and the phone's name if it was renamed here.
        let renamedHere = playlist.name != playlist.syncedName && playlist.name != server.name
        return .pull(localId: playlist.localId, serverId: server.id, stamp: server.stamp, keepName: renamedHere)
    }
    if serverChanged { return .pull(localId: playlist.localId, serverId: server.id, stamp: server.stamp, keepName: false) }
    if playlist.edited { return .push(localId: playlist.localId, serverId: server.id) }
    return nil
}

/// One song of a phone playlist as syncing sees it.
public struct PlaylistSyncRow: Sendable, Hashable {
    public var trackId: String
    public var serverSongId: String?

    public init(_ trackId: String, _ serverSongId: String? = nil) {
        self.trackId = trackId
        self.serverSongId = serverSongId
    }
}

/// The server song to send for a row: the copy it came from while the song still has it,
/// otherwise the song's copy on the server (the same one every time), otherwise the server song it
/// came from, like a find. Nil for a song only on the phone, which the server's copy goes without.
public func serverSongFor(_ row: PlaylistSyncRow, _ copies: [String]) -> String? {
    if let serverSongId = row.serverSongId, copies.contains(serverSongId) { return serverSongId }
    if let lowest = copies.min() { return lowest }
    if isFind(row.trackId) { return String(row.trackId.dropFirst(findPrefix.count)) }
    return row.serverSongId
}

/// A server playlist's songs as phone rows: each server song with the library song or find it is.
/// `trackIds` line up with `serverSongIds`.
public func serverRows(_ serverSongIds: [String], _ trackIds: [String]) -> [PlaylistSyncRow] {
    zip(serverSongIds, trackIds).map { PlaylistSyncRow($1, $0) }
}

/// The rows after taking the server's songs: the server's in its order, with each song only on the
/// phone kept after the song it followed here, or at the start when none came before it.
public func withPhoneOnly(_ server: [PlaylistSyncRow], _ local: [PlaylistSyncRow],
                          phoneOnly: (PlaylistSyncRow) -> Bool) -> [PlaylistSyncRow] {
    var firstAt: [String: Int] = [:]
    for (index, row) in server.enumerated() where firstAt[row.trackId] == nil { firstAt[row.trackId] = index }
    var after: [Int: [PlaylistSyncRow]] = [:]
    var anchor = -1
    for row in local {
        if phoneOnly(row) {
            after[anchor, default: []].append(row)
        } else if let at = firstAt[row.trackId] {
            anchor = at
        }
    }
    var rows = after[-1] ?? []
    for (index, row) in server.enumerated() {
        rows.append(row)
        rows += after[index] ?? []
    }
    return rows
}

/// The line under a playlist kept with a server that holds songs only on this phone.
public func phoneOnlyNote(_ count: Int) -> String {
    count == 1
        ? "1 song is only on this phone and is not in the server's copy"
        : "\(count) songs are only on this phone and are not in the server's copy"
}
