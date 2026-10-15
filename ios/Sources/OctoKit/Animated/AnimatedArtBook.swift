import Foundation

/// How long an album the server could not answer for is left alone, in ms.
public let animatedNotNowPauseMs: Int64 = 2 * 60_000
/// How long a server that has animated art off, or does not offer it, is left alone before it
/// is asked again, in ms.
public let animatedServerOffPauseMs: Int64 = 30 * 60_000
/// How long a server that could not say whether it offers animated art is left alone, in ms.
public let animatedServerUnknownPauseMs: Int64 = 60_000

/// What is known of an album's animated art right now.
public enum KnownArt: Sendable, Equatable {
    case has(AnimatedArt)
    case hasNone
    case unknown
}

/// The animated art of the albums asked about this session, for one server. Each album is asked
/// once (two asks at the same time share one call), and its answer is kept, "none" too. An
/// answer the server could not give just now is not kept, and the album is left alone for a
/// while. Nothing is asked of a server that does not list octoAnimatedArt, or has it off.
public final class AnimatedArtBook: @unchecked Sendable {
    /// How many albums' answers are kept, newest use last.
    static let kept = 512

    private let offered: @Sendable () async -> Bool?
    private let ask: @Sendable (String) async -> AnimatedArtAnswer
    private let now: @Sendable () -> Int64
    private let lock = NSLock()

    /// Answers by album: art, or nil for none. `order` holds the albums by last use.
    private var known: [String: AnimatedArt?] = [:]
    private var order: [String] = []
    private var asking: [String: Task<AnimatedArt?, Never>] = [:]
    private var leftAlone: [String: Int64] = [:]

    /// Whether the server offers animated art, and until when that holds.
    private var offeredAnswer: Bool?
    private var offeredUntil: Int64 = 0
    private var offeredCheck: Task<Bool, Never>?

    private var counted = 0
    /// Told each time an answer arrives, for views that follow the book.
    public var changed: (@Sendable () -> Void)?

    /// `offered` says whether the server lists octoAnimatedArt, nil when it could not be asked;
    /// `ask` asks the server about one album.
    public init(offered: @escaping @Sendable () async -> Bool?, ask: @escaping @Sendable (String) async -> AnimatedArtAnswer,
                now: @escaping @Sendable () -> Int64 = { Int64(Date().timeIntervalSince1970 * 1000) }) {
        self.offered = offered
        self.ask = ask
        self.now = now
    }

    /// Counts up each time an answer arrives.
    public var version: Int { lock.withLock { counted } }

    /// What is known of the album right now, without asking.
    public func peek(_ albumId: String) -> KnownArt {
        lock.withLock { peekLocked(albumId) }
    }

    private func peekLocked(_ albumId: String) -> KnownArt {
        guard let held = known[albumId] else { return .unknown }
        used(albumId)
        return held.map(KnownArt.has) ?? .hasNone
    }

    /// Keeps the art getAlbum came with. getAlbum without art says nothing, so only art is kept.
    public func note(_ albumId: String, _ art: AnimatedArt?) {
        guard let art, !art.isEmpty else { return }
        lock.withLock {
            store(albumId, art)
            offeredAnswer = true
            offeredUntil = .max
            counted += 1
        }
        changed?()
    }

    /// The album's animated art, asking the server when it is not known yet; nil when the album
    /// has none or the server cannot say.
    public func art(_ albumId: String) async -> AnimatedArt? {
        if albumId.trimmingCharacters(in: .whitespaces).isEmpty { return nil }
        switch peek(albumId) {
        case .has(let art): return art
        case .hasNone: return nil
        case .unknown: break
        }
        return await asked(albumId)?.value
    }

    /// Asks about these albums now, without waiting, so their art is ready when they come up
    /// (the next song's, say). The task answers once every ask is done.
    @discardableResult
    public func ahead(_ albumIds: [String]) -> Task<Void, Never> {
        var seen = Set<String>()
        let ids = albumIds.filter { id in
            seen.insert(id).inserted && !id.trimmingCharacters(in: .whitespaces).isEmpty && peek(id) == .unknown
        }
        return Task {
            await withTaskGroup(of: Void.self) { group in
                for id in ids { group.addTask { _ = await self.art(id) } }
            }
        }
    }

    /// The one call for the album, started if none is running; nil while the album or the
    /// server is left alone.
    private func asked(_ albumId: String) async -> Task<AnimatedArt?, Never>? {
        guard await serverOffers() else { return nil }
        return lock.withLock { () -> Task<AnimatedArt?, Never>? in
            if let running = asking[albumId] { return running }
            if (leftAlone[albumId] ?? 0) > now() { return nil }
            let task = Task<AnimatedArt?, Never> {
                let answer = await self.ask(albumId)
                return self.keep(albumId, answer)
            }
            asking[albumId] = task
            return task
        }
    }

    private func keep(_ albumId: String, _ answer: AnimatedArtAnswer) -> AnimatedArt? {
        var art: AnimatedArt?
        lock.withLock {
            asking[albumId] = nil
            switch answer {
            case .found(let found):
                art = found
                store(albumId, found)
            case .none:
                store(albumId, nil)
            case .off:
                offeredAnswer = false
                offeredUntil = now() + animatedServerOffPauseMs
            case .notNow:
                leftAlone[albumId] = now() + animatedNotNowPauseMs
            }
            if leftAlone.count > Self.kept {
                let at = now()
                leftAlone = leftAlone.filter { $0.value > at }
            }
            counted += 1
        }
        changed?()
        return art
    }

    /// Whether the server offers animated art, asked once and kept for a while; a server that
    /// could not be asked is asked again a minute later.
    private func serverOffers() async -> Bool {
        let check: Task<Bool, Never> = lock.withLock {
            if offeredUntil > now() { return Task { [answer = offeredAnswer] in answer == true } }
            if let running = offeredCheck { return running }
            let task = Task<Bool, Never> {
                let listed = await self.offered()
                self.lock.withLock {
                    self.offeredAnswer = listed
                    switch listed {
                    case true?: self.offeredUntil = .max
                    case false?: self.offeredUntil = self.now() + animatedServerOffPauseMs
                    case nil: self.offeredUntil = self.now() + animatedServerUnknownPauseMs
                    }
                    self.offeredCheck = nil
                }
                return listed == true
            }
            offeredCheck = task
            return task
        }
        return await check.value
    }

    /// Kept under the lock: the answer, the album marked as just used, the oldest let go.
    private func store(_ albumId: String, _ art: AnimatedArt?) {
        known[albumId] = .some(art)
        used(albumId)
        while order.count > Self.kept {
            known[order.removeFirst()] = nil
        }
    }

    private func used(_ albumId: String) {
        if let at = order.lastIndex(of: albumId) { order.remove(at: at) }
        order.append(albumId)
    }
}
