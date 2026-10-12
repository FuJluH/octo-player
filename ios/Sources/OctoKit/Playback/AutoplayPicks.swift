import Foundation

/// How many songs Autoplay adds at a time. When they run out, it adds more.
public let autoplayBatch = 10

/// What Autoplay adds: the server's songs like the last one, in its order, when it has any not
/// excluded; otherwise songs by the same artist, then in the same genre, as given (the caller
/// shuffles each). Songs in `exclude` (the queue, and the last 50 played) are never picked, nor
/// is any twice.
public func autoplayPicks(similar: [String], sameArtist: [String], sameGenre: [String], exclude: Set<String>,
                          limit: Int = autoplayBatch) -> [String] {
    let fromServer = distinctInOrder(similar.filter { !exclude.contains($0) })
    if !fromServer.isEmpty { return Array(fromServer.prefix(limit)) }
    return Array(distinctInOrder((sameArtist + sameGenre).filter { !exclude.contains($0) }).prefix(limit))
}

/// The items with any repeat after the first left out.
func distinctInOrder<T: Hashable>(_ items: [T]) -> [T] {
    var seen = Set<T>()
    return items.filter { seen.insert($0).inserted }
}
