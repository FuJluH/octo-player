import Foundation
#if canImport(FoundationNetworking)
import FoundationNetworking
#endif

struct PlayQueueBody: Decodable {
    let playQueue: ServerPlayQueue?
    let playQueueByIndex: ServerPlayQueue?
}

struct TransitionProfileBody: Decodable {
    let transitionProfile: TransitionProfileAnswer?
}

extension SubsonicClient {
    /// The signed address of a server song for one request: its id there and the request's
    /// parameters. A fresh signature every time, so never keep it.
    public func streamURL(serverId: String, request: StreamRequest) -> URL {
        url("stream", [("id", serverId)] + request.params)
    }

    /// A song's transition profile, or `ready = false` while the server has none. Only for
    /// servers that list the octoTransitions extension.
    public func transitionProfile(_ id: String) async throws -> TransitionProfileAnswer {
        let body: TransitionProfileBody = try await get("getTransitionProfile", [("id", id)], key: nil)
        return body.transitionProfile ?? TransitionProfileAnswer(id: id)
    }

    /// The queue saved on the server by place in the list, or nil when none is.
    public func playQueueByIndex() async throws -> ServerPlayQueue? {
        let body: PlayQueueBody = try await get("getPlayQueueByIndex", key: nil)
        return body.playQueueByIndex.flatMap { $0.entry.isEmpty ? nil : $0 }
    }

    /// The older form, where the current song is named by id.
    public func playQueue() async throws -> ServerPlayQueue? {
        let body: PlayQueueBody = try await get("getPlayQueue", key: nil)
        return body.playQueue.flatMap { $0.entry.isEmpty ? nil : $0 }
    }

    /// Saves the queue, with the current song as its place in the list.
    public func savePlayQueueByIndex(_ ids: [String], currentIndex: Int, positionMs: Int) async throws {
        try await call("savePlayQueueByIndex", queueSaveParams(ids, currentIndex: currentIndex, positionMs: positionMs, indexBased: true))
    }

    /// Saves the queue, with the current song named by id.
    public func savePlayQueue(_ ids: [String], currentIndex: Int, positionMs: Int) async throws {
        try await call("savePlayQueue", queueSaveParams(ids, currentIndex: currentIndex, positionMs: positionMs, indexBased: false))
    }
}

/// Whether a response to a request for its first byte shows the server sends parts of the song
/// when asked: it says which part it sent.
public func answersRanges(_ headers: [String: [String]]) -> Bool {
    headers.contains { key, values in key.caseInsensitiveCompare("Content-Range") == .orderedSame && values.contains { !$0.trimmingCharacters(in: .whitespaces).isEmpty } }
}

/// The server song an item plays: its id there, when it is from the server `sourceId` names.
public func serverSongOf(_ uri: String?, sourceId: String) -> String? {
    guard let uri, let ref = parseStreamUri(uri) else { return nil }
    return ref.sourceId == nil || ref.sourceId == sourceId ? ref.serverId : nil
}

/// What the profiles need to know of the server in use.
public struct ProfileSession: Sendable {
    public var sourceId: String
    public var isOcto: Bool
    public var extensions: [String]
    public var client: SubsonicClient

    public init(sourceId: String, isOcto: Bool, extensions: [String], client: SubsonicClient) {
        self.sourceId = sourceId
        self.isOcto = isOcto
        self.extensions = extensions
        self.client = client
    }
}

/// Songs' transition profiles for the crossfade, from the server that holds the songs, each song
/// named by the address the queue plays it from. Asks the signed-in server, when it makes them,
/// and keeps what it says for the server in use.
public final class ServerProfiles: @unchecked Sendable {
    private let session: @Sendable () -> ProfileSession?
    private let lock = NSLock()
    /// The server the kept profiles are from, and whether it makes them.
    private var server: String?
    private var offers: Bool?
    private var profiles: TransitionProfiles?

    public init(session: @escaping @Sendable () -> ProfileSession?) {
        self.session = session
    }

    /// The kept profiles for the server in use, new ones when it changed.
    private func forSession(_ session: ProfileSession) -> TransitionProfiles {
        lock.withLock {
            if server != session.sourceId || profiles == nil {
                server = session.sourceId
                offers = session.extensions.contains("\(octoTransitions):1") ? true : nil
                profiles = TransitionProfiles(fetch: { [weak self] id in await self?.ask(session, id) })
            }
            return profiles!
        }
    }

    private func ask(_ session: ProfileSession, _ id: String) async -> TransitionProfileAnswer? {
        var yes = lock.withLock { offers }
        if yes == nil {
            yes = await session.client.supportsIfKnown(octoTransitions)
            if let said = yes { lock.withLock { offers = said } }
        }
        guard yes == true else { return nil }
        return try? await session.client.transitionProfile(id)
    }

    /// The profile of the song at `uri`, when it is already here.
    public func cached(_ uri: String?) -> TransitionProfile? {
        guard let session = session(), session.isOcto, let id = serverSongOf(uri, sourceId: session.sourceId) else { return nil }
        return forSession(session).cached(id)
    }

    /// Asks for the profile of the song at `uri` and hands it, or nil when the server has none,
    /// to `done` on the main thread. False when there is nothing to ask: not a song from the server
    /// in use, or a server that makes no profiles.
    public func request(_ uri: String?, done: @escaping @MainActor @Sendable (TransitionProfile?) -> Void) -> Bool {
        guard let session = session(), session.isOcto, let id = serverSongOf(uri, sourceId: session.sourceId) else { return false }
        let profiles = forSession(session)
        if lock.withLock({ offers }) == false { return false }
        Task {
            let profile = await profiles.profile(id)
            await MainActor.run { done(profile) }
        }
        return true
    }
}
