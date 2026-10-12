import Foundation

// Plays on the phone and plays on the server, counted together. Octo records every play on the
// phone and also sends plays of songs with a server copy to the server, so the server's count
// holds Octo's own plays too. Octo remembers the plays it sent each server song, and takes off the
// ones the server's count already holds: those that started no later than the server's last play.

/// The plays Octo sent the server for one song: how many the server's record is known to hold,
/// and the start times of newer ones.
public struct SentPlays: Sendable, Equatable {
    public var folded: Int
    public var recent: [Int64]

    public init(folded: Int = 0, recent: [Int64] = []) {
        self.folded = folded
        self.recent = recent
    }
}

/// The server may keep times to the second only.
private let serverTimeSlackMs: Int64 = 999

private func isHeld(_ startedAt: Int64, _ serverLastPlayedAt: Int64?) -> Bool {
    guard let serverLastPlayedAt else { return false }
    return startedAt <= serverLastPlayedAt + serverTimeSlackMs
}

extension Optional where Wrapped == SentPlays {
    /// How many of the plays Octo sent the server's record holds.
    public func heldBy(_ serverLastPlayedAt: Int64?) -> Int {
        guard let sent = self else { return 0 }
        return sent.folded + sent.recent.filter { isHeld($0, serverLastPlayedAt) }.count
    }
}

extension Dictionary where Key == String, Value == SentPlays {
    public func plusSent(_ serverId: String, _ startedAt: Int64) -> [String: SentPlays] {
        var next = self
        var before = self[serverId] ?? SentPlays()
        before.recent = (before.recent + [startedAt]).sorted()
        next[serverId] = before
        return next
    }

    /// After a sync: plays the server's record now holds become a plain number, and songs the
    /// server no longer has are forgotten.
    public func foldedInto(_ lastPlayed: [String: Int64?]) -> [String: SentPlays] {
        var next: [String: SentPlays] = [:]
        for (id, sent) in self {
            guard let last = lastPlayed[id] else { continue }
            let held = sent.recent.filter { isHeld($0, last) }
            let newer = sent.recent.filter { !isHeld($0, last) }
            next[id] = SentPlays(folded: sent.folded + held.count, recent: newer)
        }
        return next
    }
}

/// Each song's plays on the phone plus the server's plays that are not Octo's own, and the later
/// of the two last plays. A song played only on the server joins the list.
public func withServerPlays(_ local: [PlayedTrack], _ server: [ServerPlayedTrack], _ sent: [String: SentPlays]) -> [PlayedTrack] {
    var order: [String] = []
    var byId: [String: PlayedTrack] = [:]
    for row in local {
        if byId[row.track.id] == nil { order.append(row.track.id) }
        byId[row.track.id] = row
    }
    for copy in server {
        let others = max(copy.serverPlays - sent[copy.serverId].heldBy(copy.serverLastPlayedAt), 0)
        let last = copy.serverLastPlayedAt ?? 0
        if var mine = byId[copy.track.id] {
            mine.plays += others
            mine.lastPlayedAt = max(mine.lastPlayedAt, last)
            byId[copy.track.id] = mine
        } else {
            order.append(copy.track.id)
            byId[copy.track.id] = PlayedTrack(track: copy.track, plays: others, lastPlayedAt: last)
        }
    }
    return order.compactMap { byId[$0] }.filter { $0.plays > 0 }
}

/// Each album once, at the later of its last play on the phone and on the server.
public func withServerAlbumPlays(_ local: [PlayedAlbum], _ server: [PlayedAlbum]) -> [PlayedAlbum] {
    groupInOrder(local + server, by: \.album.id).map { _, rows in
        rows.enumerated().max { a, b in
            a.element.lastPlayedAt != b.element.lastPlayedAt ? a.element.lastPlayedAt < b.element.lastPlayedAt : a.offset > b.offset
        }!.element
    }
}

/// Stored one song per line: "<folded> <start>,<start> <server id>".
public func encodeSent(_ sent: [String: SentPlays]) -> Set<String> {
    Set(sent.map { id, plays in "\(plays.folded) \(plays.recent.map(String.init).joined(separator: ",")) \(id)" })
}

public func decodeSent(_ lines: Set<String>) -> [String: SentPlays] {
    var found: [String: SentPlays] = [:]
    for line in lines {
        let parts = line.split(separator: " ", maxSplits: 2, omittingEmptySubsequences: false).map(String.init)
        guard let folded = parts.first.flatMap(kotlinInt), parts.count > 2, !parts[2].isEmpty else { continue }
        let recent = parts[1].split(separator: ",", omittingEmptySubsequences: false).compactMap { Int64(String($0)) }
        found[parts[2]] = SentPlays(folded: folded, recent: recent)
    }
    return found
}
