import Foundation

/// Where a server's own things may go: its main and home addresses. Its extra headers and this
/// install's id and name go only to those origins (scheme, host and port), and its client
/// certificate only to those hosts.
public struct ServerScope: Sendable, Equatable {
    public private(set) var origins: Set<String>
    public private(set) var hosts: Set<String>

    /// The headers every request may carry wherever it goes; any other one is the server's own.
    static let plainHeaders: Set<String> = [
        "accept", "accept-encoding", "accept-language", "content-length", "content-type", "if-range", "range", "user-agent",
    ]

    public init(_ addresses: [URL] = []) {
        origins = Set(addresses.compactMap(ServerAddress.origin))
        hosts = Set(addresses.compactMap { $0.host?.lowercased() }.filter { !$0.isEmpty })
    }

    public var isEmpty: Bool { origins.isEmpty }

    /// Whether a request to this address goes to the server.
    public func covers(_ url: URL?) -> Bool {
        guard let origin = url.flatMap(ServerAddress.origin) else { return false }
        return origins.contains(origin)
    }

    /// Whether this host is one of the server's own. With no host to go by, it is not.
    public func isOwnHost(_ host: String?) -> Bool {
        guard let host, !host.isEmpty else { return false }
        return hosts.contains(host.lowercased())
    }

    /// The names of the headers a redirected request has to lose: none while it stays at the
    /// server's addresses or where it was first sent; elsewhere every header but the plain ones.
    public func headersToDrop(_ headers: [String: String], to url: URL?, first: URL?) -> [String] {
        if covers(url) { return [] }
        if let to = url.flatMap(ServerAddress.origin), let from = first.flatMap(ServerAddress.origin), to == from { return [] }
        return headers.keys.filter { !Self.plainHeaders.contains($0.lowercased()) }.sorted()
    }
}
