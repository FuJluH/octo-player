import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

/// A play waiting to reach the server: which server song, and when it started.
public struct PendingPlay: Sendable, Hashable {
    public var serverId: String
    public var startedAt: Int64

    public init(serverId: String, startedAt: Int64) {
        self.serverId = serverId
        self.startedAt = startedAt
    }
}

/// How many plays may wait. Past that the oldest are let go.
public let maxPendingPlays = 500

extension Array where Element == PendingPlay {
    /// The waiting plays with one more, oldest first, so the server hears them in the order they
    /// happened. Each play waits once.
    public func plusPlay(_ play: PendingPlay) -> [PendingPlay] {
        var seen = Set<PendingPlay>()
        let distinct = (self + [play]).filter { seen.insert($0).inserted }
        let ordered = distinct.enumerated().sorted { a, b in
            a.element.startedAt != b.element.startedAt ? a.element.startedAt < b.element.startedAt : a.offset < b.offset
        }.map(\.element)
        return Array(ordered.suffix(maxPendingPlays))
    }
}

/// Whether a failed send is worth trying again: the server could not be reached, answered
/// strangely, or refused the login. A server that refused the play itself (an unknown song, say)
/// would refuse it again, and work that was stopped is not tried again.
public func worthRetrying(_ error: Error) -> Bool {
    if isCancellation(error) { return false }
    if let octo = error as? OctoError {
        switch octo {
        case .notSubsonic, .http, .wrongCredentials: return true
        case .authUnsupported, .notFound, .server: return false
        }
    }
    return error is URLError
}

/// Stored one play per line: "<start> <server id>".
public func encodePending(_ plays: [PendingPlay]) -> Set<String> {
    Set(plays.map { "\($0.startedAt) \($0.serverId)" })
}

public func decodePending(_ lines: Set<String>) -> [PendingPlay] {
    let plays: [PendingPlay] = lines.compactMap { line in
        let parts = line.split(separator: " ", maxSplits: 1, omittingEmptySubsequences: false).map(String.init)
        guard let start = parts.first.flatMap(pendingStart), parts.count > 1, !parts[1].isEmpty else { return nil }
        return PendingPlay(serverId: parts[1], startedAt: start)
    }
    return plays.sorted { a, b in a.startedAt != b.startedAt ? a.startedAt < b.startedAt : a.serverId < b.serverId }
}

/// A start time written plainly, with an optional sign.
private func pendingStart(_ text: String) -> Int64? {
    var digits = Substring(text)
    if digits.first == "+" || digits.first == "-" { digits = digits.dropFirst() }
    guard !digits.isEmpty, digits.allSatisfy({ $0.isASCII && $0.isNumber }) else { return nil }
    return Int64(text)
}
