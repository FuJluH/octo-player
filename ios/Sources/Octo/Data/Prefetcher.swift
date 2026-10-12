import Foundation
import Observation
import OctoKit

/// One queue entry as fetching ahead sees it: the song, and its queue address when it is a
/// server song (nil for anything else).
struct PrefetchEntry: Equatable, Sendable {
    var trackId: String
    var stream: String?
}

/// The queue as fetching ahead sees it. It is read again whenever what comes next changes: the
/// song, the queue, playing or paused, shuffle, repeat.
struct PrefetchQueue: Equatable, Sendable {
    var entries: [PrefetchEntry]
    /// Every queue place in the order they play (shuffled when shuffle is on).
    var playOrder: [Int]
    var current: Int
    var repeatMode: PrefetchRepeat
    var playing: Bool

    static let empty = PrefetchQueue(entries: [], playOrder: [], current: 0, repeatMode: .off, playing: false)
}

extension PrefetchQueue {
    /// The player's queue as fetching ahead sees it.
    init(_ queue: PlayQueue, playing: Bool) {
        entries = queue.items.map { PrefetchEntry(trackId: $0.trackId, stream: prefetchIsServerStream($0.uri) ? $0.uri : nil) }
        playOrder = queue.playOrder()
        current = queue.current
        repeatMode = prefetchRepeat(queue.repeatMode)
        self.playing = playing
    }
}

/// While music plays, fetches the next few server songs of the queue whole into the saved songs,
/// so they start at once and still play if the connection drops: 5 s after the last change, one
/// after another. How many depends on the connection (Wi-Fi and mobile data have their own
/// counts). Any change to what comes next, or to the settings, starts it over; pausing stops it,
/// mid-song too. Songs found online are never fetched ahead, only saved as they play. AirPlay
/// plays from the phone, so it fetches ahead like the phone's own speaker.
@MainActor
final class Prefetcher {
    private let session: Session
    private let settings: AppSettings
    private let connectivity: Connectivity
    private let cache: StreamCache
    private var queue = PrefetchQueue.empty
    /// The addresses of the songs being fetched, so the same list is not started twice.
    private var ahead: [String] = []
    private var job: Task<Void, Never>?
    /// Counts the looks at what comes next, so only the latest one acts.
    private var looks = 0
    private var watches: [AnyObject] = []

    init(session: Session, settings: AppSettings = .shared, connectivity: Connectivity, cache: StreamCache = .shared) {
        self.session = session
        self.settings = settings
        self.connectivity = connectivity
        self.cache = cache
        watches.append(Watch({ [weak settings] in settings?.offline ?? OfflinePrefs() }) { [weak self] _ in self?.refresh() })
        connectivity.onChange { [weak self] in self?.refresh() }
    }

    /// Follows the player from now on: each change to its song, queue, playing or paused,
    /// shuffle or repeat reads the queue again.
    func follow(_ player: Player) {
        watches.append(Watch({ [weak player] () -> PrefetchQueue? in
            guard let player else { return nil }
            // What the player shows of its queue, read so any change to it is heard.
            _ = (player.items, player.index, player.repeatMode, player.shuffled, player.isPlaying)
            return PrefetchQueue(player.engine.queue, playing: player.isPlaying)
        }) { [weak self] queue in self?.update(queue ?? .empty) })
        update(PrefetchQueue(player.engine.queue, playing: player.isPlaying))
    }

    /// What comes next changed.
    func update(_ queue: PrefetchQueue) {
        self.queue = queue
        refresh()
    }

    private func refresh() {
        looks += 1
        let look = looks
        Task { [weak self] in
            guard let self else { return }
            let enabled = await cache.enabled
            guard look == looks else { return }
            let next = upcoming(cacheEnabled: enabled)
            if next == ahead, job != nil { return }
            stop()
            ahead = next
            guard !next.isEmpty else { return }
            job = Task { [weak self] in
                try? await Task.sleep(for: .milliseconds(prefetchStartAfterMs))
                for stream in next {
                    if Task.isCancelled { return }
                    guard let self, await self.fetch(stream) else { break }
                }
                // Done, or stopped at a connection error: the same list may start again.
                if !Task.isCancelled { self?.job = nil }
            }
        }
    }

    private func stop() {
        job?.cancel()
        job = nil
        ahead = []
    }

    /// The addresses of the server songs among the next ones in play order, finds left out.
    private func upcoming(cacheEnabled: Bool) -> [String] {
        let count = prefetchCount(cacheEnabled: cacheEnabled, onWifi: connectivity.onWifi, online: connectivity.online,
                                  prefs: settings.offline)
        let entries = queue.entries
        let places = prefetchAhead(playOrder: queue.playOrder, current: queue.current, repeatMode: queue.repeatMode,
                                   playing: queue.playing, count: count) { place in
            place < entries.count && prefetchFetchable(trackId: entries[place].trackId, isServerStream: entries[place].stream != nil)
        }
        return places.compactMap { entries[$0].stream }
    }

    /// Saves one song whole at the size it will play, unless it already is. False when fetching
    /// should stop, such as when the connection is gone. The cache is measured again after each
    /// try.
    private func fetch(_ stream: String) async -> Bool {
        guard let ref = parseStreamUri(stream) else { return true }
        switch await Self.prepare(ref, context: StreamContext.now(session)) {
        case .skip:
            return true
        case .stop:
            await SettingsFeeds.shared.measureCache()
            return false
        case .fetch(let key, let request):
            let fetched = await Self.save(request, key: key, cache: cache)
            await SettingsFeeds.shared.measureCache()
            return fetched
        }
    }

    private enum Prepared: Sendable {
        case skip
        case stop
        case fetch(key: String, request: URLRequest)
    }

    /// Fixes the request the song will play with, the way playing it does, and signs it. Runs on
    /// a thread that may wait, since both look at the saved songs and the sign-in.
    nonisolated private static func prepare(_ ref: StreamRef, context: StreamContext) async -> Prepared {
        await withCheckedContinuation { done in
            DispatchQueue.global(qos: .utility).async {
                let pinned = context.pinned(ref)
                guard let key = context.savedKey(pinned) else { return done.resume(returning: .skip) }
                if (try? blocking({ await StreamCache.shared.isFullySaved(key) })) == true { return done.resume(returning: .skip) }
                guard let request = try? context.sign(pinned) else { return done.resume(returning: .stop) }
                done.resume(returning: .fetch(key: key, request: request))
            }
        }
    }

    /// Downloads the whole song into the saved songs. False on any failure.
    nonisolated private static func save(_ request: URLRequest, key: String, cache: StreamCache) async -> Bool {
        do {
            let (file, response) = try await ServerTrust.shared.session.download(for: request)
            defer { try? FileManager.default.removeItem(at: file) }
            guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode),
                  let handle = try? FileHandle(forReadingFrom: file)
            else { return false }
            defer { try? handle.close() }
            var offset: Int64 = 0
            while let chunk = try handle.read(upToCount: 1 << 20), !chunk.isEmpty {
                if Task.isCancelled { return false }
                await cache.write(key, offset: offset, data: chunk)
                offset += Int64(chunk.count)
            }
            await cache.describe(key, contentLength: offset, mimeType: http.mimeType)
            await cache.save()
            return true
        } catch {
            return false
        }
    }
}
