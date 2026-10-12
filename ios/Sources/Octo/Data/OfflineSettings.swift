import Foundation
import Observation
import OctoKit

/// What to keep on the phone for playing without a connection: the saved songs' size, how many
/// songs to fetch ahead, and the downloads' quality and rules. Kept on the phone as one record.
@MainActor
@Observable
final class OfflineSettings {
    private(set) var prefs: OfflinePrefs

    @ObservationIgnored private let key = "offline.prefs"
    @ObservationIgnored private let cache: StreamCache

    init(cache: StreamCache = .shared) {
        self.cache = cache
        if let data = UserDefaults.standard.data(forKey: key), let saved = try? JSONDecoder().decode(OfflinePrefs.self, from: data) {
            prefs = saved
        } else {
            prefs = OfflinePrefs()
        }
        let size = prefs.cacheSize
        // Nothing is kept or let go until the size is known.
        Task { await cache.setSize(size) }
    }

    private func change(_ edit: (inout OfflinePrefs) -> Void) {
        var next = prefs
        edit(&next)
        guard next != prefs else { return }
        prefs = next
        if let data = try? JSONEncoder().encode(next) { UserDefaults.standard.set(data, forKey: key) }
    }

    func setCacheSize(_ size: CacheSize) {
        change { $0.cacheSize = size }
        Task { await cache.setSize(size) }
    }

    func setPrefetchWifi(_ count: Int) { change { $0.prefetchWifi = prefetchClamped(count) } }
    func setPrefetchMobile(_ count: Int) { change { $0.prefetchMobile = prefetchClamped(count) } }
    func setDownloadQuality(_ quality: StreamQuality) { change { $0.downloadQuality = quality } }
    func setWifiOnly(_ on: Bool) { change { $0.wifiOnly = on } }
    func setStreamOnWifi(_ on: Bool) { change { $0.streamOnWifi = on } }
    func setKeepLiked(_ on: Bool) { change { $0.keepLiked = on } }
    func setPlaylistKept(_ id: String, _ kept: Bool) { change { $0.setPlaylistKept(id, kept) } }
    func clearRules() { change { $0.clearRules() } }

    /// Puts back the settings from a backup in one go.
    func restore(_ backup: OfflinePrefs) {
        change { $0 = $0.restoring(backup) }
        let size = prefs.cacheSize
        Task { await cache.setSize(size) }
    }
}
