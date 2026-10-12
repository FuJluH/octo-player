import Foundation

// The server calls the account part adds: password changes, and the play queue the server keeps.

/// The play queue a server keeps for the signed-in user. The older form names the current song
/// by id; the index-based form gives its place in the list.
public struct ServerPlayQueue: Decodable, Sendable, Equatable {
    public var entry: [Song]
    public var current: String?
    public var currentIndex: Int?
    public var position: Int64
    public var username: String?
    public var changed: String?
    public var changedBy: String?

    enum CodingKeys: String, CodingKey { case entry, current, currentIndex, position, username, changed, changedBy }

    public init(from decoder: Decoder) throws {
        let c = try decoder.container(keyedBy: CodingKeys.self)
        entry = c.list(.entry)
        current = c.string(.current)
        currentIndex = c.int(.currentIndex)
        position = c.long(.position) ?? 0
        username = c.string(.username)
        changed = c.string(.changed)
        changedBy = c.string(.changedBy)
    }

    init() {
        entry = []
        position = 0
    }
}

/// The OpenSubsonic extension for saving the queue by place in the list.
public let indexBasedQueue = "indexBasedQueue"

/// What a queue save sends: every song id in order, and where playback is. In the index-based
/// form the current song is its place in the list; otherwise it is the song's id. An empty
/// queue sends no current song.
public func queueSaveParams(_ ids: [String], currentIndex: Int, positionMs: Int64, indexBased: Bool) -> [(String, String)] {
    var params = ids.map { ("id", $0) }
    guard ids.indices.contains(currentIndex) else { return params }
    params.append(indexBased ? ("currentIndex", "\(currentIndex)") : ("current", ids[currentIndex]))
    params.append(("position", "\(max(0, positionMs))"))
    return params
}

extension SubsonicClient {
    /// Gives a user a new password, in a form body, never in the address.
    public func changePassword(username: String, password: String) async throws {
        try await postForm("changePassword", [("username", username), ("password", password)])
    }

    /// A family member's own password, which the server checks against the current one. Every
    /// other app and device then needs the new one.
    public func changeFamilyPassword(current: String, next: String) async throws {
        try await postForm("changeFamilyPassword", [("current", current), ("next", next)])
    }

    /// The queue saved on the server, or nil when none is.
    public func playQueue(indexBased: Bool) async throws -> ServerPlayQueue? {
        let queue: ServerPlayQueue = try await answer(indexBased ? "getPlayQueueByIndex" : "getPlayQueue",
                                                key: indexBased ? "playQueueByIndex" : "playQueue", fallback: ServerPlayQueue())
        return queue.entry.isEmpty ? nil : queue
    }

    /// Saves the queue on the server.
    public func savePlayQueue(_ ids: [String], currentIndex: Int, positionMs: Int64, indexBased: Bool) async throws {
        try await answerOK(indexBased ? "savePlayQueueByIndex" : "savePlayQueue",
                           queueSaveParams(ids, currentIndex: currentIndex, positionMs: positionMs, indexBased: indexBased))
    }
}
