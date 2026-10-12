import Foundation
import Observation
import OctoKit

/// One queue entry as fetching ahead sees it: the song, where it streams from (nil for anything
/// that is not a server song), and the key it is saved under.
struct PrefetchEntry: Equatable {
    var trackId: String
    var url: URL?
    var key: String?
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
/// Songs found online are never fetched ahead, only saved as they play.
@MainActor
final class Prefetcher {
    private let settings: OfflineSettings
    private let connectivity: Connectivity
    private let cache: StreamCache
    private var queue = PrefetchQueue.empty
    /// The songs being fetched, so the same list is not started twice.
    private var ahead: [PrefetchEntry] = []
    private var job: Task<Void, Never>?
    private var watch: Watch<OfflinePrefs>?
    /// The headers the server needs on every request, and the trusted session.
    var headers: @MainActor () -> [String: String] = { [:] }

    init(settings: OfflineSettings, connectivity: Connectivity, cache: StreamCache = .shared) {
        self.settings = settings
        self.connectivity = connectivity
        self.cache = cache
        watch = Watch({ [weak settings] in settings?.prefs ?? OfflinePrefs() }) { [weak self] _ in self?.refresh() }
        connectivity.onChange { [weak self] in self?.refresh() }
    }

    /// What comes next changed.
    func update(_ queue: PrefetchQueue) {
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
            let headers = headers()
            job = Task { [weak self] in
                try? await Task.sleep(for: .milliseconds(prefetchStartAfterMs))
                for entry in next {
                    if Task.isCancelled { return }
                    guard let self, await self.fetch(entry, headers: headers) else { return }
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
                                  prefs: settings.prefs)
        let entries = queue.entries
        let places = prefetchAhead(playOrder: queue.playOrder, current: queue.current, repeatMode: queue.repeatMode,
                                   playing: queue.playing, count: count) { place in
            place < entries.count && prefetchFetchable(trackId: entries[place].trackId, isServerStream: entries[place].url != nil)
        }
        return places.map { entries[$0] }
    }

    /// Saves one song whole unless it already is. False when fetching should stop, such as when
    /// the connection is gone.
    private func fetch(_ entry: PrefetchEntry, headers: [String: String]) async -> Bool {
        guard let url = entry.url, let key = entry.key else { return true }
        if await cache.isFullySaved(key) { return true }
        var request = URLRequest(url: url)
        for (name, value) in headers { request.setValue(value, forHTTPHeaderField: name) }
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
