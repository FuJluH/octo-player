import Foundation

// Keeps likes on the phone and stars on the server the same, both ways. Each side is compared with
// the last state both agreed on (the synced record, kept as server song ids), which tells which
// side changed: a like or star added on one side is added on the other, and a removal on either
// side wins over the copy the other side still has.

/// What brings both sides together, and the record to keep once it is done.
public struct StarPlan: Sendable, Equatable {
    /// Server songs to star.
    public var star: Set<String>
    /// Server songs to unstar.
    public var unstar: Set<String>
    /// Library songs to like.
    public var like: Set<String>
    /// Library songs to unlike.
    public var unlike: Set<String>
    /// The server songs both sides will agree are starred.
    public var synced: Set<String>

    public init(star: Set<String> = [], unstar: Set<String> = [], like: Set<String> = [], unlike: Set<String> = [],
                synced: Set<String> = []) {
        self.star = star
        self.unstar = unstar
        self.like = like
        self.unlike = unlike
        self.synced = synced
    }
}

/// The plan that brings `liked` library songs and `starred` server songs together, given the
/// `synced` record of what both last agreed on.
public func reconcileStars(_ copies: [ServerCopy], liked: Set<String>, starred: Set<String>, synced: Set<String>) -> StarPlan {
    let known = Set(copies.map(\.serverId))
    // A song that lost its server copy keeps its record, in case it returns.
    var record = synced.filter { !known.contains($0) }
    var star = Set<String>()
    var unstar = Set<String>()
    var like = Set<String>()
    var unlike = Set<String>()
    for (song, songCopies) in groupInOrder(copies, by: \.trackId) {
        let ids = songCopies.map(\.serverId)
        let here = liked.contains(song)
        let there = ids.contains { starred.contains($0) }
        let before = ids.contains { synced.contains($0) }
        if here && there {
            // Both agree it is liked.
            record.formUnion(ids.filter { starred.contains($0) })
        } else if here && before {
            // Unstarred on the server since the last sync.
            unlike.insert(song)
        } else if here {
            // Liked on the phone since the last sync, or before ever syncing.
            star.formUnion(ids)
            record.formUnion(ids)
        } else if there && before {
            // Unliked on the phone since the last sync.
            unstar.formUnion(ids.filter { starred.contains($0) })
        } else if there {
            // Starred on the server since the last sync.
            like.insert(song)
            record.formUnion(ids.filter { starred.contains($0) })
        }
    }
    return StarPlan(star: star, unstar: unstar, like: like, unlike: unlike, synced: record)
}

extension StarPlan {
    /// The record once the plan was carried out. A star that did not reach the server is left
    /// out, so the next sync tries it again; an unstar that did not is kept, for the same reason.
    public func settled(starFailed: Set<String>, unstarFailed: Set<String>) -> Set<String> {
        synced.subtracting(starFailed).union(unstarFailed)
    }
}

/// A server time like "2026-09-19T01:44:59.636933547Z", in milliseconds. Nil for anything else.
public func parseServerTime(_ text: String?) -> Int64? {
    epochMs(text)
}
