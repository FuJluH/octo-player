import Foundation

// Words and rules for the server's extras: library scans, shared links, who is listening, and
// internet radio stations.

private let hourMs: Int64 = 60 * 60 * 1_000
private let dayMs: Int64 = 24 * hourMs

/// How far a library scan has come.
public enum ScanState: Sendable, Equatable {
    case idle
    case scanning(Int64)
    case finished
    case failed(String)
}

/// The words for a library scan in the Server card.
public func scanLabel(_ state: ScanState, locale: Locale = .current) -> String {
    switch state {
    case .idle: "Scan library now"
    case .scanning(let count): count > 0 ? "Scanning, \(groupedCount(count, locale: locale)) songs" : "Scanning"
    case .finished: "Scan finished"
    case .failed(let message): message
    }
}

/// What a scan failure says.
public func scanFailedWords(_ error: Error) -> String {
    if case .server(50, _) = SubsonicError(error) { return "Only an admin can scan this server." }
    return "The scan could not start just now."
}

/// What a link shares: its description, or its first song.
public func shareTitle(_ share: Share) -> String {
    if let description = share.description, !description.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { return description }
    if let title = share.entry.first?.title, !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { return title }
    return "Shared link"
}

/// How much it holds, when it expires and how often it was opened, on one line.
public func shareDetails(_ share: Share, nowMs: Int64, locale: Locale = .current) -> String {
    let songs: String? = switch share.entry.count {
    case 0: nil
    case 1: "1 song"
    default: "\(share.entry.count) songs"
    }
    let visits = switch share.visitCount {
    case 0: "No visits"
    case 1: "1 visit"
    default: "\(groupedCount(share.visitCount, locale: locale)) visits"
    }
    return [songs, expiryLabel(expiresAtMs: serverTime(share.expires), nowMs: nowMs), visits].compactMap { $0 }.joined(separator: " • ")
}

/// When a link stops working, in words.
public func expiryLabel(expiresAtMs: Int64?, nowMs: Int64) -> String {
    guard let expiresAtMs, expiresAtMs > 0 else { return "Never expires" }
    let left = expiresAtMs - nowMs
    if left <= 0 { return "Expired" }
    if left < hourMs { return "Expires within the hour" }
    if left < dayMs {
        let hours = left / hourMs
        return hours == 1 ? "Expires in 1 hour" : "Expires in \(hours) hours"
    }
    let days = (left + dayMs / 2) / dayMs
    return days == 1 ? "Expires in 1 day" : "Expires in \(days) days"
}

/// How long ago someone started a song, from the server's minutes.
public func minutesAgo(_ minutes: Int) -> String {
    if minutes <= 0 { return "Just now" }
    if minutes == 1 { return "1 minute ago" }
    if minutes < 60 { return "\(minutes) minutes ago" }
    if minutes < 120 { return "1 hour ago" }
    return "\(minutes / 60) hours ago"
}

/// How long a shared link lasts.
public enum ShareExpiry: CaseIterable, Sendable {
    case never, day, week, month

    public var label: String {
        switch self {
        case .never: "Never"
        case .day: "1 day"
        case .week: "1 week"
        case .month: "1 month"
        }
    }

    public var lengthMs: Int64? {
        switch self {
        case .never: nil
        case .day: dayMs
        case .week: 7 * dayMs
        case .month: 30 * dayMs
        }
    }
}

/// When a link made now stops working, in milliseconds since 1970, or nil for never.
public func shareExpiresAt(_ expiry: ShareExpiry, nowMs: Int64) -> Int64? {
    expiry.lengthMs.map { nowMs + $0 }
}

/// Whether a failure means the server does not share at all: sharing is switched off (error 50
/// or 70), or the call is not there (HTTP 501).
public func sharingUnavailable(_ error: Error) -> Bool {
    switch SubsonicError(error) {
    case .notFound: true
    case .server(let code, _): code == 50 || code == 70
    case .notSubsonic(_, let status): status == 501
    default: false
    }
}

/// A server album id from a library song's album, when the song came from that server's album
/// list: "<source>:<album id>". Albums made up from loose songs ("album:...") are not on the server.
public func serverAlbumIdOf(sourceId: String, albumId: String) -> String? {
    let prefix = sourceId + ":"
    guard albumId.hasPrefix(prefix) else { return nil }
    let rest = String(albumId.dropFirst(prefix.count))
    return rest.isEmpty || rest.hasPrefix("album:") ? nil : rest
}

/// The client name this app gives the server, which its player names start with.
public let ourClientName = "Octo"

/// Who is listening now, as shown: other people, and this account on other players. The
/// phone's own entry is left out.
public func othersListening(_ entries: [NowPlayingEntry], username: String, ourClient: String = ourClientName) -> [NowPlayingEntry] {
    entries.filter { entry in
        !(entry.username.caseInsensitiveCompare(username) == .orderedSame
            && (entry.playerName ?? "").lowercased().hasPrefix(ourClient.lowercased()))
    }
}

/// A listener's row: the song, then who, on which player, and when it started.
public func listenerTitle(_ entry: NowPlayingEntry) -> String {
    [entry.title, entry.artist ?? ""].filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }.joined(separator: " · ")
}

public func listenerLine(_ entry: NowPlayingEntry) -> String {
    [entry.username, entry.playerName ?? "", minutesAgo(entry.minutesAgo)]
        .filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }.joined(separator: " · ")
}

/// Whether a radio station belongs to Octo itself: a station Octo makes from your listening
/// carries its own id as its cover.
public func looksGenerated(_ station: RadioStationDetails, isOcto: Bool) -> Bool {
    isOcto && station.coverArt == station.id
}

/// Whether a station refusal means the server keeps the station as it is: not found (Octo's
/// answer for its own) or not allowed.
public func refusesStationChange(_ error: Error) -> Bool {
    switch SubsonicError(error) {
    case .notFound: true
    case .server(50, _): true
    default: false
    }
}

/// An http or https address with a host, the only kind a station can stream from.
public func isStreamAddress(_ text: String) -> Bool {
    let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
    guard let parts = URLComponents(string: trimmed), let scheme = parts.scheme?.lowercased(),
          scheme == "http" || scheme == "https", let host = parts.host, !host.isEmpty
    else { return false }
    return true
}

/// The station form: a name, its stream and an optional home page.
public struct StationDraft: Sendable, Equatable {
    public var id: String?
    public var name: String
    public var stream: String
    public var homePage: String

    public init(_ id: String? = nil, _ name: String = "", _ stream: String = "", _ homePage: String = "") {
        self.id = id
        self.name = name
        self.stream = stream
        self.homePage = homePage
    }

    /// Save is offered once the name is there, the stream is an address, and the home page is
    /// blank or an address too.
    public var ready: Bool {
        !name.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty && isStreamAddress(stream)
            && (homePage.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty || isStreamAddress(homePage))
    }
}

/// A station's second line: whose it is, or where it streams from.
public func stationLine(_ station: RadioStationDetails, readOnly: Bool) -> String {
    if readOnly { return "Made by the server" }
    if isStreamAddress(station.streamUrl), let host = URLComponents(string: station.streamUrl.trimmingCharacters(in: .whitespacesAndNewlines))?.host {
        return host
    }
    return station.streamUrl
}
