import Foundation

// Words and rules for the server's extras: library scans, shared links, who is listening, and
// internet radio stations.

private let hourMs: Int64 = 60 * 60 * 1_000
private let dayMs: Int64 = 24 * hourMs

/// The words for a library scan in the Server card.
public func scanLabel(_ state: ServerScanState) -> String {
    switch state {
    case .idle: "Scan library now"
    case .scanning(let count): count > 0 ? "Scanning, \(SettingsSummaries.grouped(Int(count))) songs" : "Scanning"
    case .finished: "Scan finished"
    case .failed(let message): message
    }
}

/// What a link shares: its description, or its first song.
public func shareTitle(_ share: ServerShare) -> String {
    if let description = share.description, !description.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { return description }
    if let title = share.entry.first?.title, !title.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty { return title }
    return "Shared link"
}

/// How much it holds, when it expires and how often it was opened, on one line.
public func shareDetails(_ share: ServerShare, nowMs: Int64) -> String {
    let songs: String? = switch share.entry.count {
    case 0: nil
    case 1: "1 song"
    default: "\(share.entry.count) songs"
    }
    let visits = switch share.visitCount {
    case 0: "No visits"
    case 1: "1 visit"
    default: "\(SettingsSummaries.grouped(Int(share.visitCount))) visits"
    }
    return [songs, expiryLabel(expiresAtMs: shareExpiresAtMs(share), nowMs: nowMs), visits].compactMap { $0 }.joined(separator: " • ")
}

/// When a link stops working, in milliseconds since 1970: its expiry read as an instant or a
/// date and time with an offset. A time with no zone, or anything else, is nil, so the link
/// reads as never expiring.
public func shareExpiresAtMs(_ share: ServerShare) -> Int64? {
    serverTime(share.expires).map(Int64.init)
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

/// A listener's row: the song, then who, on which player, and when it started.
public func listenerTitle(_ entry: ServerNowPlaying) -> String {
    [entry.title, entry.artist ?? ""].filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }.joined(separator: " · ")
}

public func listenerLine(_ entry: ServerNowPlaying) -> String {
    [entry.username, entry.playerName ?? "", minutesAgo(entry.minutesAgo)]
        .filter { !$0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }.joined(separator: " · ")
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
public func stationLine(_ station: ServerStationDetails, readOnly: Bool) -> String {
    if readOnly { return "Made by the server" }
    if isStreamAddress(station.streamUrl), let host = URLComponents(string: station.streamUrl.trimmingCharacters(in: .whitespacesAndNewlines))?.host {
        return host
    }
    return station.streamUrl
}
