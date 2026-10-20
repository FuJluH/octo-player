import Foundation
import Observation
import OctoKit

/// One queue entry as fetching ahead sees it: the song and its queue address (a server song's
/// `octo-stream` address, or anything else, which is never fetched).
struct PrefetchEntry: Equatable {
    var trackId: String
    var uri: String
}

/// The queue as fetching ahead sees it. The player hands it over whenever what comes next changes:
/// the song, the queue, playing or paused, shuffle, repeat.
struct PrefetchQueue: Equatable {
    var entries: [PrefetchEntry]
    /// Every queue place in the order they play (shuffled when shuffle is on).
    var playOrder: [Int]
    var current: Int
    var repeatMode: PrefetchRepeat
    var playing: Bool
    /// Fetching ahead is only for the phone's own playing.
    var casting: Bool = false

    static let empty = PrefetchQueue(entries: [], playOrder: [], current: 0, repeatMode: .off, playing: false)
}

/// While music plays, fetches the next few server songs of the queue whole into the saved songs,
/// so they start at once and still play if the connection drops: 5 s after a song starts, one
/// after another. How many depends on the connection (Wi-Fi and mobile data have their own
/// counts). Any change to what comes next, or to the settings, starts it over; pausing stops it.
/// Songs found online are never fetched ahead, only saved as they play. Each song is pinned to
/// the request it will play with and signed as its fetch goes out, through the same chain a deck
/// opens it with.
@MainActor
final class Prefetcher {
    private let settings: AppSettings
    private let connectivity: Connectivity
    private let cache: StreamCache
    private var queue = PrefetchQueue.empty
    /// The songs being fetched, so the same list is not started twice.
    private var ahead: [PrefetchEntry] = []
    private var job: Task<Void, Never>?
    private var watch: Watch<OfflinePrefs>?
    /// The server in use and the stream size, as a deck would open a song now.
    var context: @MainActor () -> StreamContext? = { nil }

    init(settings: AppSettings = .shared, connectivity: Connectivity, cache: StreamCache = .shared) {
        self.settings = settings
        self.connectivity = connectivity
        self.cache = cache
        watch = Watch({ [weak settings] in settings?.offline ?? OfflinePrefs() }) { [weak self] _ in self?.refresh() }
        connectivity.onChange { [weak self] in self?.refresh() }
    }

    /// What comes next changed.
    func update(_ queue: PrefetchQueue) {
        guard queue != self.queue else { return }
        self.queue = queue
        refresh()
    }

    private func refresh() {
        Task { [weak self] in
            guard let self else { return }
            let next = await upcoming()
            if next == ahead, job != nil { return }
            stop()
            ahead = next
            guard !next.isEmpty else { return }
            job = Task { [weak self] in
                try? await Task.sleep(for: .milliseconds(prefetchStartAfterMs))
                for entry in next {
                    if Task.isCancelled { return }
                    guard let self, let context = self.context() else { return }
                    let fetched = await Self.fetch(entry.uri, context: context)
                    // What the saved songs take up is measured again after each try.
                    await SettingsFeeds.shared.measureCache()
                    guard fetched else {
                        playbackLog.info("fetch ahead stopped")
                        return
                    }
                }
            }
        }
    }

    private func stop() {
        job?.cancel()
        job = nil
        ahead = []
    }

    /// The server songs among the next ones in play order, finds left out.
    private func upcoming() async -> [PrefetchEntry] {
        guard !queue.casting else { return [] }
        let count = prefetchCount(cacheEnabled: await cache.enabled, onWifi: connectivity.onWifi, online: connectivity.online,
                                  prefs: settings.offline, lowData: connectivity.lowData)
        let entries = queue.entries
        let places = prefetchAhead(playOrder: queue.playOrder, current: queue.current, repeatMode: queue.repeatMode,
                                   playing: queue.playing, count: count) { place in
            place < entries.count
                && prefetchFetchable(trackId: entries[place].trackId, isServerStream: parseStreamUri(entries[place].uri) != nil)
        }
        return places.map { entries[$0] }
    }

    /// How pinning and signing went: nothing to fetch (not a server song, not kept, or saved
    /// whole already), a song to fetch under its saved name, or a refusal (no connection, no
    /// server) that stops the run.
    private enum Preparing: Sendable {
        case skip
        case fetch(key: String, request: URLRequest)
        case stop
    }

    /// Saves one song whole unless it already is. False when fetching should stop, such as when
    /// the connection is gone or the server refused.
    nonisolated private static func fetch(_ uri: String, context: StreamContext) async -> Bool {
        // Pinning and signing wait on other threads, so they run away from the main thread.
        let preparing: Preparing = await withCheckedContinuation { done in
            DispatchQueue.global(qos: .utility).async {
                guard let ref = parseStreamUri(uri) else { return done.resume(returning: .skip) }
                let pinned = context.pinned(ref)
                guard let key = context.savedKey(pinned) else { return done.resume(returning: .skip) }
                if (try? blocking({ await StreamCache.shared.isFullySaved(key) })) == true {
                    return done.resume(returning: .skip)
                }
                guard let request = try? context.sign(pinned) else { return done.resume(returning: .stop) }
                done.resume(returning: .fetch(key: key, request: request))
            }
        }
        let key: String, request: URLRequest
        switch preparing {
        case .skip: return true
        case .stop: return false
        case .fetch(let savedKey, let signed): (key, request) = (savedKey, signed)
        }
        do {
            let (file, response) = try await ServerTrust.shared.session.download(for: request)
            defer { try? FileManager.default.removeItem(at: file) }
            guard let http = response as? HTTPURLResponse, (200..<300).contains(http.statusCode),
                  let handle = try? FileHandle(forReadingFrom: file)
            else { return false }
            defer { try? handle.close() }
            let cache = StreamCache.shared
            // A part saved earlier of another file (the server's listed preview, say) goes first.
            let size = (try? FileManager.default.attributesOfItem(atPath: file.path)[.size] as? Int64) ?? nil
            await cache.answered(key, contentLength: size, mimeType: http.mimeType)
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
