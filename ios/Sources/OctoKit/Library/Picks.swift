import Foundation

/// Which songs of a list are picked, by their keys: a song's id, or its row on a playlist page
/// where a song can be there twice. Nothing picked means the list is not selecting: taking the
/// last one off ends it.
public struct Picks: Equatable, Sendable {
    public var keys: Set<String>

    public init(_ keys: Set<String> = []) { self.keys = keys }

    public var active: Bool { !keys.isEmpty }

    public func start(_ key: String) -> Picks { Picks([key]) }

    public func toggle(_ key: String) -> Picks {
        var next = keys
        if next.contains(key) { next.remove(key) } else { next.insert(key) }
        return Picks(next)
    }

    /// Drops songs no longer in the list, such as one just removed.
    public func keepOnly(_ present: Set<String>) -> Picks {
        keys.allSatisfy(present.contains) ? self : Picks(keys.intersection(present))
    }

    /// The picked items in the list's own order.
    public func inOrder<T>(_ list: [T], key: (T) -> String) -> [T] { list.filter { keys.contains(key($0)) } }
}
