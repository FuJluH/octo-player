import Foundation

// Keeps ratings on the phone and on the server the same, both ways. Each side is compared with the
// last rating both agreed on (the synced record, kept per server song, with no entry meaning no
// rating), which tells which side changed. The side that changed wins; when both did, the phone's
// wins, since it is the change made here last. A rating is 1 to 5 stars, and 0 is none.

/// What one song's server copies should be set to.
public struct RatingSend: Sendable, Equatable {
    public var serverIds: [String]
    public var rating: Int

    public init(serverIds: [String], rating: Int) {
        self.serverIds = serverIds
        self.rating = rating
    }
}

/// What brings both sides together, and the record to keep once it is done.
public struct RatingPlan: Sendable, Equatable {
    /// Library songs whose server copies change, and to what.
    public var send: [String: RatingSend]
    /// Library songs whose rating on the phone changes, and to what.
    public var adopt: [String: Int]
    /// The ratings both sides will agree on, by server song.
    public var synced: [String: Int]

    public init(send: [String: RatingSend] = [:], adopt: [String: Int] = [:], synced: [String: Int] = [:]) {
        self.send = send
        self.adopt = adopt
        self.synced = synced
    }
}

/// The plan that brings the phone's `local` ratings (by library song) and the server copies'
/// ratings together, given the `synced` record of what both last agreed on.
public func reconcileRatings(_ copies: [RatingCopy], local: [String: Int], synced: [String: Int]) -> RatingPlan {
    let known = Set(copies.map(\.serverId))
    // A song that lost its server copy keeps its record, in case it returns.
    var record = synced.filter { !known.contains($0.key) }
    var send: [String: RatingSend] = [:]
    var adopt: [String: Int] = [:]
    for (song, songCopies) in groupInOrder(copies, by: \.trackId) {
        let ordered = songCopies.enumerated().sorted { a, b in
            a.element.serverId != b.element.serverId ? a.element.serverId < b.element.serverId : a.offset < b.offset
        }.map(\.element)
        let ids = ordered.map(\.serverId)
        let here = local[song] ?? 0
        let before = ids.lazy.compactMap { synced[$0] }.first ?? 0
        // The server's rating: a copy that moved from the record, if any.
        let there = ordered.first { $0.rating != before }?.rating ?? before
        let target = here != before ? here : there
        if ordered.contains(where: { $0.rating != target }) { send[song] = RatingSend(serverIds: ids, rating: target) }
        if here != target { adopt[song] = target }
        if target > 0 { for id in ids { record[id] = target } }
    }
    return RatingPlan(send: send, adopt: adopt, synced: record)
}

extension RatingPlan {
    /// The record once the plan was carried out. A song whose server copies were not all set keeps
    /// its old record, so the next sync sees the phone's change again and sends it again: that is
    /// how a rating made offline waits.
    public func settled(failed: Set<String>, before: [String: Int]) -> [String: Int] {
        var result = synced
        for song in failed {
            for id in send[song]?.serverIds ?? [] {
                result[id] = before[id]
            }
        }
        return result
    }
}

/// A rating in range: 1 to 5 stars, anything else none.
public func cleanRating(_ rating: Int?) -> Int {
    guard let rating, (1...5).contains(rating) else { return 0 }
    return rating
}

/// Stored one server song per line: "<rating> <server id>".
public func encodeRatings(_ ratings: [String: Int]) -> Set<String> {
    Set(ratings.filter { (1...5).contains($0.value) }.map { id, rating in "\(rating) \(id)" })
}

public func decodeRatings(_ lines: Set<String>) -> [String: Int] {
    var found: [String: Int] = [:]
    for line in lines {
        let parts = line.split(separator: " ", maxSplits: 1, omittingEmptySubsequences: false).map(String.init)
        guard let rating = parts.first.flatMap(kotlinInt), (1...5).contains(rating),
              parts.count > 1, !parts[1].isEmpty else { continue }
        found[parts[1]] = rating
    }
    return found
}
