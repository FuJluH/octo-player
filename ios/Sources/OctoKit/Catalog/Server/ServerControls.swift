import Foundation

// Controls for the signed-in server beyond its library: shared links, a library scan, radio
// stations, and who is listening. Each is offered only when the server supports it; what the
// server refuses is remembered for the session. The rules below are what those controls decide.

private let shareDayMs: Int64 = 24 * 60 * 60 * 1000

/// How long a shared link lasts.
public enum ShareExpiry: String, Sendable, CaseIterable {
    case never = "Never"
    case day = "Day"
    case week = "Week"
    case month = "Month"

    public var label: String {
        switch self {
        case .never: "Never"
        case .day: "1 day"
        case .week: "1 week"
        case .month: "1 month"
        }
    }

    /// How long the link lasts, or nil for good.
    public var lengthMs: Int64? {
        switch self {
        case .never: nil
        case .day: shareDayMs
        case .week: 7 * shareDayMs
        case .month: 30 * shareDayMs
        }
    }
}

/// When a link made now stops working, in milliseconds since 1970, or nil for never.
public func shareExpiresAt(_ expiry: ShareExpiry, now: Int64) -> Int64? { expiry.lengthMs.map { now + $0 } }

/// Whether a failure means the server does not share at all: sharing is switched off (error 50
/// or 70, which reads as not found), or the call is not there (HTTP 501).
public func sharingUnavailable(_ error: Error) -> Bool {
    switch error as? OctoError {
    case .notFound: true
    case .server(let code, _): code == 50 || code == 70
    case .http(let status): status == 501
    default: false
    }
}

/// A server album id from a library song's album, when the song came from that server's album
/// list: "<source>:<album id>". Albums made up from loose songs ("album:...") are not on the
/// server.
public func serverAlbumIdOf(_ sourceId: String, _ albumId: String) -> String? {
    let prefix = "\(sourceId):"
    guard albumId.hasPrefix(prefix) else { return nil }
    let id = String(albumId.dropFirst(prefix.count))
    return id.hasPrefix("album:") || id.isEmpty ? nil : id
}

/// The server's id for a library song on it, for sharing: the lowest id among its copies on the
/// server in use.
public func serverSongId(copies: [SourceTrack], serverInUse: String) -> String? {
    copies.filter { $0.sourceId == serverInUse }.map(\.nativeId).min { $0.utf16.lexicographicallyPrecedes($1.utf16) }
}

/// The server's id for a library album, when its songs came from one album there: the album most
/// of its songs' copies on the server in use belong to, the first one seen among equals.
public func serverAlbumId(copies: [SourceTrack], serverInUse: String) -> String? {
    var counts: [String: Int] = [:]
    var order: [String] = []
    for copy in copies where copy.sourceId == serverInUse {
        guard let album = serverAlbumIdOf(serverInUse, copy.albumId) else { continue }
        if counts[album] == nil { order.append(album) }
        counts[album, default: 0] += 1
    }
    var best: String?
    for album in order where best.map({ (counts[album] ?? 0) > (counts[$0] ?? 0) }) ?? true { best = album }
    return best
}

/// How far a library scan has come.
public enum ServerScanState: Sendable, Equatable {
    case idle
    case scanning(count: Int64)
    case finished
    case failed(message: String)
}

/// How often a running scan is asked how far it has come.
public let serverScanPollMs: Int64 = 2_000

/// Follows a scan's answers. Some servers answer before the scan has begun, so until it has been
/// seen running, "not scanning" is believed only on the second answer in a row.
public struct ServerScanPoll: Sendable, Equatable {
    public private(set) var seenRunning: Bool
    public private(set) var quiet = 0

    /// Starts from the answer to the request to scan.
    public init(started scanning: Bool) { seenRunning = scanning }

    /// Takes the next answer; true once the scan is over.
    public mutating func isDone(scanning: Bool) -> Bool {
        if scanning {
            seenRunning = true
            quiet = 0
            return false
        }
        if seenRunning { return true }
        quiet += 1
        return quiet >= 2
    }
}

/// What a failed scan says: only an admin may scan (error 50), or it could not start.
public func serverScanFailedWords(_ error: Error) -> String {
    if case .server(let code, _)? = error as? OctoError, code == 50 { return "Only an admin can scan this server." }
    return "The scan could not start just now."
}

/// Whether a now playing entry is this account on one of its own Octo players: the same user,
/// any case, on a player whose name starts with `ourClient`, any case.
public func isOwnPlayer(username: String, playerName: String?, account: String,
                        ourClient: String = SubsonicClient.clientName) -> Bool {
    username.lowercased() == account.lowercased() && (playerName ?? "").lowercased().hasPrefix(ourClient.lowercased())
}

/// Who is listening now, as shown: other people, and this account on other players. This
/// account's own Octo players are left out.
public func othersListening<Entry>(_ entries: [Entry], username: String, ourClient: String = SubsonicClient.clientName,
                                   user: (Entry) -> String, player: (Entry) -> String?) -> [Entry] {
    entries.filter { !isOwnPlayer(username: user($0), playerName: player($0), account: username, ourClient: ourClient) }
}

/// Whether a radio station belongs to Octo itself: a station Octo makes from your listening
/// carries its own id as its cover. The server still has the final say, refusing to change one.
public func looksGenerated(stationId: String, coverArt: String?, isOcto: Bool) -> Bool { isOcto && coverArt == stationId }

public func looksGenerated(_ station: RadioStation, isOcto: Bool) -> Bool {
    looksGenerated(stationId: station.id, coverArt: station.coverArt, isOcto: isOcto)
}

/// Whether a failed station change means the server will not change it (not found, or error 50):
/// it is then marked read-only, and its edit actions go away.
public func stationChangeRefused(_ error: Error) -> Bool {
    switch error as? OctoError {
    case .notFound: true
    case .server(let code, _): code == 50
    default: false
    }
}

/// The stations each kept server refused to change, by its id and theirs, with more marked.
public func markingReadOnly(_ refused: [String: Set<String>], account: String,
                            stations: some Sequence<String>) -> [String: Set<String>] {
    var marked = refused
    marked[account, default: []].formUnion(stations)
    return marked
}
