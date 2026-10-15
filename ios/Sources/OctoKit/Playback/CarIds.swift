import Foundation

/// Everything a car can browse to, and the id each is known by. A song keeps the list it was
/// found in, so choosing it plays that list from that song.
public indirect enum CarNode: Sendable, Hashable {
    case root
    case recent
    case playlists
    case albums
    case artists
    case liked
    case mostPlayed
    case album(String)
    case artist(String)
    case playlist(String)
    case song(trackId: String, list: CarNode?)
}

private let songPrefix = "song:"
private let inMarker = "|in:"

public func carId(_ node: CarNode) -> String {
    switch node {
    case .root: "root"
    case .recent: "tab:recent"
    case .playlists: "tab:playlists"
    case .albums: "tab:albums"
    case .artists: "tab:artists"
    case .liked: "liked"
    case .mostPlayed: "mostplayed"
    case .album(let id): "album:\(id)"
    case .artist(let id): "artist:\(id)"
    case .playlist(let id): "playlist:\(id)"
    case .song(let trackId, let list): songPrefix + trackId + (list.map { inMarker + carId($0) } ?? "")
    }
}

/// Reads an id back. A plain song id, as the app itself sends, is not a car id, so this returns
/// nil for it.
public func parseCarId(_ id: String) -> CarNode? {
    switch id {
    case "root": return .root
    case "tab:recent": return .recent
    case "tab:playlists": return .playlists
    case "tab:albums": return .albums
    case "tab:artists": return .artists
    case "liked": return .liked
    case "mostplayed": return .mostPlayed
    default: break
    }
    if id.hasPrefix("album:") { return .album(String(id.dropFirst("album:".count))) }
    if id.hasPrefix("artist:") { return .artist(String(id.dropFirst("artist:".count))) }
    if id.hasPrefix("playlist:") { return .playlist(String(id.dropFirst("playlist:".count))) }
    if id.hasPrefix(songPrefix) {
        let rest = String(id.dropFirst(songPrefix.count))
        guard let cut = rest.range(of: inMarker) else { return .song(trackId: rest, list: nil) }
        return .song(trackId: String(rest[..<cut.lowerBound]), list: parseCarId(String(rest[cut.upperBound...])))
    }
    return nil
}

/// Where to start in a list of songs: at the chosen song, or the top if it is no longer there.
public func startIndex(_ trackIds: [String], _ chosen: String?) -> Int {
    guard let chosen, let found = trackIds.firstIndex(of: chosen) else { return 0 }
    return found
}

/// What stands beside the playback buttons on the lock screen for the song on now: its heart;
/// for a song found online, which cannot be liked yet, a download while none has been asked for;
/// or nothing, as for a station.
public enum NotificationHeart: Sendable, Equatable {
    case like(liked: Bool)
    case download
    case none
}

public func notificationHeart(_ trackId: String?, isFind: Bool, liked: Set<String>, downloads: [String: DownloadState]) -> NotificationHeart {
    guard let trackId, !isRadio(trackId) else { return .none }
    if !isFind { return .like(liked: liked.contains(trackId)) }
    return (downloads[trackId] ?? .none) == .none ? .download : .none
}

public func notificationHeart(_ trackId: String?, liked: Set<String>, downloads: [String: DownloadState]) -> NotificationHeart {
    notificationHeart(trackId, isFind: trackId.map(isFind) ?? false, liked: liked, downloads: downloads)
}
