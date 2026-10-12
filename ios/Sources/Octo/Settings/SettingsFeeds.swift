import Foundation
import MediaPlayer
import Observation
import OctoKit
import UIKit

/// What the settings pages show that other parts of the app keep: the server library copy and
/// the cache of songs played lately. Each part sets what it knows; the pages only read.
@MainActor
@Observable
final class SettingsFeeds {
    static let shared = SettingsFeeds()

    /// When a server's library was last copied, by the kept server's id.
    struct LastSync: Equatable {
        var serverId: String
        var at: Date
    }

    var syncing = false
    /// Why the last copy failed, in words, while it is the latest news.
    var syncProblem: String?
    var lastSync: LastSync?

    /// How much the cache of songs played lately holds now.
    private(set) var cacheUsed: Int64 = 0

    /// Where songs played lately are kept: the app's caches, under "media".
    nonisolated static var cacheFolder: URL {
        FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask)[0].appendingPathComponent("media", isDirectory: true)
    }

    /// Measures the cache again: the bytes of the songs saved in it, off the main thread.
    func measureCache() async {
        let used = await StreamCache.shared.usedBytes()
        if cacheUsed != used { cacheUsed = used }
    }

    /// Removes every saved song at once, then measures again.
    func clearCache() async {
        await StreamCache.shared.clear()
        await measureCache()
    }
}

/// The music on this phone: whether Octo may read it, how many songs there are, and looking
/// for new ones. On iPhone this is the phone's own music library.
@MainActor
@Observable
final class PhoneMusic {
    static let shared = PhoneMusic()

    private(set) var access: PhoneAccess = .notAsked
    private(set) var songCount = 0
    private(set) var scanning = false
    /// The top-level folders of the phone's music, once a scan has listed them.
    var folders: [MusicFolder] = []

    @ObservationIgnored private var started = false
    @ObservationIgnored private var settle: Task<Void, Never>?

    /// What does the work once the app's own music library runs: asking for access and looking
    /// for music go to it, and it reports back through `show`.
    struct Work {
        var requestAccess: @MainActor () -> Void
        var rescan: @MainActor () async -> Void
    }

    @ObservationIgnored var work: Work?

    /// What the app's music library found, for the pages to show.
    func show(access: PhoneAccess, songCount: Int, scanning: Bool, folders: [MusicFolder]) {
        if self.access != access { self.access = access }
        if self.songCount != songCount { self.songCount = songCount }
        if self.scanning != scanning { self.scanning = scanning }
        if self.folders != folders { self.folders = folders }
    }

    private init() {}

    /// Reads the access at start, scans once when allowed, and watches the library for changes.
    func start() {
        guard !started else { return }
        started = true
        if work != nil { return }
        access = Self.currentAccess()
        if access == .granted {
            watchLibrary()
            Task { await rescan() }
        }
        NotificationCenter.default.addObserver(forName: UIApplication.didBecomeActiveNotification, object: nil, queue: .main) { _ in
            MainActor.assumeIsolated { PhoneMusic.shared.checkAgain() }
        }
    }

    /// Asks for access when the phone still can; once refused, opens the app's page in the
    /// phone's Settings instead.
    func requestAccess() {
        if let work { return work.requestAccess() }
        switch access {
        case .granted: return
        case .deniedForever:
            if let url = URL(string: UIApplication.openSettingsURLString) { UIApplication.shared.open(url) }
        case .notAsked, .denied:
            MPMediaLibrary.requestAuthorization { _ in
                Task { @MainActor in
                    let now = Self.currentAccess()
                    PhoneMusic.shared.access = now
                    if now == .granted {
                        PhoneMusic.shared.watchLibrary()
                        await PhoneMusic.shared.rescan()
                    }
                }
            }
        }
    }

    /// Counts the phone's songs again. Nothing happens without access; scans never overlap.
    func rescan() async {
        if let work { return await work.rescan() }
        guard access == .granted, !scanning else { return }
        scanning = true
        defer { scanning = false }
        songCount = await Task.detached { Self.countSongs() }.value
    }

    /// Each time the app comes back, the access is read again: newly allowed starts a scan.
    private func checkAgain() {
        let now = Self.currentAccess()
        guard now != access else { return }
        let was = access
        access = now
        if now == .granted, was != .granted {
            watchLibrary()
            Task { await rescan() }
        }
    }

    private func watchLibrary() {
        MPMediaLibrary.default().beginGeneratingLibraryChangeNotifications()
        NotificationCenter.default.addObserver(forName: .MPMediaLibraryDidChange, object: nil, queue: .main) { _ in
            MainActor.assumeIsolated {
                // Waits for the library to stop changing before looking again.
                PhoneMusic.shared.settle?.cancel()
                PhoneMusic.shared.settle = Task {
                    try? await Task.sleep(for: .seconds(2))
                    guard !Task.isCancelled else { return }
                    await PhoneMusic.shared.rescan()
                }
            }
        }
    }

    private static func currentAccess() -> PhoneAccess {
        switch MPMediaLibrary.authorizationStatus() {
        case .authorized: .granted
        case .notDetermined: .notAsked
        case .denied, .restricted: .deniedForever
        @unknown default: .notAsked
        }
    }

    /// Songs that are on the phone itself, not ones that only stream from the cloud.
    nonisolated private static func countSongs() -> Int {
        let query = MPMediaQuery.songs()
        query.addFilterPredicate(MPMediaPropertyPredicate(value: false, forProperty: MPMediaItemPropertyIsCloudItem))
        return query.items?.count ?? 0
    }
}
