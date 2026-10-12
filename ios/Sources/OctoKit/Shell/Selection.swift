import Foundation

/// A song in a list that can be picked: the key it is picked by, which is its id, or its row
/// on a playlist page where a song can be there twice.
public struct Pickable: Sendable, Equatable {
    public let key: String
    public let song: Song

    public init(key: String, song: Song) {
        self.key = key
        self.song = song
    }

    /// A song picked by its own id.
    public init(_ song: Song) {
        self.init(key: song.id, song: song)
    }
}

/// Which songs are picked. Nothing picked means the list is not selecting: taking the last one
/// off ends it.
public struct Picks: Sendable, Equatable {
    public let keys: Set<String>

    public init(_ keys: Set<String> = []) {
        self.keys = keys
    }

    public var active: Bool { !keys.isEmpty }

    public func start(_ key: String) -> Picks { Picks([key]) }

    public func toggle(_ key: String) -> Picks {
        keys.contains(key) ? Picks(keys.subtracting([key])) : Picks(keys.union([key]))
    }

    /// Drops songs no longer in the list, such as one just removed.
    public func keepOnly(_ present: Set<String>) -> Picks {
        keys.allSatisfy(present.contains) ? self : Picks(keys.intersection(present))
    }

    /// The picked songs in the list's own order.
    public func inOrder(_ list: [Pickable]) -> [Pickable] { list.filter { keys.contains($0.key) } }
}

/// How many are picked, as the selection bar says it.
public func selectedWords(_ count: Int) -> String { count == 1 ? "1 selected" : "\(count) selected" }
