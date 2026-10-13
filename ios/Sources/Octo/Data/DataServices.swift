import Foundation
import Observation
import OctoKit
import SwiftUI

/// Everything that keeps the library and the listener's things: made once at start, each part
/// handed to the pages through the environment.
@MainActor
final class DataServices {
    let session: Session
    let library: Library
    let connectivity: Connectivity
    let serverSync: ServerSync
    let discovery: ServerDiscovery
    let downloads: Downloads
    let listening: ListeningSync
    let favoriteSync: FavoriteSync
    let playlistSync: PlaylistSync
    let likes: LikeStore
    let ratings: RatingStore
    let playlists: PlaylistStore
    let favorites: FavoriteStore
    let pins: PinStore
    let plays: PlayStore
    let serverSwitch: ServerSwitch
    let device: DeviceLibrary
    let offline: OfflineDownloads
    let marks: OfflineMarkings
    let prefetcher: Prefetcher
    let controls: ServerControls
    let refresh: LibraryRefresh

    /// The saved songs, kept on the phone as they play.
    var streamCache: StreamCache { .shared }
    private var watches: [AnyObject] = []
    private var links: SettingsLinks?
    /// The last cache size change, so the next one waits for it and the sizes apply in order.
    private var resize: Task<Void, Never>?

    /// `announce` shows a line: the words, and whether it marks something done.
    init(session: Session, announce: @escaping @MainActor (String, Bool) -> Void) {
        self.session = session
        library = Library.open()
        connectivity = Connectivity()
        serverSync = ServerSync(session: session, library: library)
        discovery = ServerDiscovery(session: session, library: library)
        listening = ListeningSync(session: session, library: library, sync: serverSync)
        favoriteSync = FavoriteSync(session: session, library: library, sync: serverSync)
        downloads = Downloads(session: session, library: library, sync: serverSync, announce: announce)
        playlistSync = PlaylistSync(session: session, library: library, discovery: discovery, sync: serverSync)
        likes = LikeStore(library: library, listening: listening)
        ratings = RatingStore(library: library, listening: listening)
        playlists = PlaylistStore(library: library, sync: playlistSync)
        favorites = FavoriteStore(library: library, sync: favoriteSync)
        pins = PinStore(library: library)
        plays = PlayStore(library: library, listening: listening)
        device = DeviceLibrary(library: library)
        offline = OfflineDownloads(session: session, library: library, connectivity: connectivity, sync: serverSync) { words in announce(words, false) }
        marks = OfflineMarkings(downloads: offline, connectivity: connectivity)
        prefetcher = Prefetcher(connectivity: connectivity)
        prefetcher.context = { [weak session] in session.map { StreamContext.now($0) } }
        controls = ServerControls(session: session, library: library, sync: serverSync)
        refresh = LibraryRefresh(device: device, sync: serverSync, downloads: downloads, session: session)
        serverSwitch = ServerSwitch(session: session, library: library, sync: serverSync, listening: listening,
                                    favorites: favoriteSync, playlists: playlistSync)
        let offline = offline
        serverSwitch.onForgetDownloads { sourceId in await offline.forgetSource(sourceId) }
        // Covers named by a bare id are the server in use's.
        Covers.signedInSource.withLock { $0 = session.inUse?.sourceId }
        watches.append(Watch({ [weak session] in session?.inUse?.sourceId }) { source in
            Covers.signedInSource.withLock { $0 = source }
        })
    }

    /// Starts the work that runs on its own: the phone's music, copying the server's library,
    /// downloads, the cache of songs played lately at its chosen size, and what the settings pages
    /// show of them.
    func start() {
        links = SettingsLinks(device: device, sync: serverSync)
        device.start()
        serverSync.start()
        offline.start()
        let settings = AppSettings.shared
        // Each new size is measured again once the cache has taken it, so what was let go shows.
        resize = Task { await Self.applySize(to: settings.offline.cacheSize, after: nil) }
        watches.append(Watch({ settings.offline.cacheSize }) { [weak self] size in
            guard let self else { return }
            let before = resize
            resize = Task { await Self.applySize(to: size, after: before) }
        })
        // The list of saved songs is written as the app leaves the screen, since the system may
        // close it without a word once it is in the background.
        watches.append(NotificationCenter.default.addObserver(forName: UIApplication.didEnterBackgroundNotification, object: nil,
                                                              queue: .main) { _ in
            Task { await StreamCache.shared.save() }
        })
    }

    private static func applySize(to size: CacheSize, after before: Task<Void, Never>?) async {
        await before?.value
        await StreamCache.shared.setSize(size)
        await SettingsFeeds.shared.measureCache()
    }
}

extension View {
    /// Hands every data part to the pages below; pulling down on a library page runs the
    /// library's refresh.
    func dataEnvironment(_ data: DataServices) -> some View {
        let refresh = data.refresh
        return environment(data.library)
            .environment(data.serverSync)
            .environment(data.likes)
            .environment(data.favorites)
            .environment(data.pins)
            .environment(data.serverSwitch)
            .environment(data.device)
            .environment(data.offline)
            .environment(data.marks)
            .environment(data.controls)
            .environment(data.connectivity)
            .environment(\.dataServices, data)
            .environment(\.refreshLibrary, { @MainActor in await refresh.refresh() })
    }
}

private struct DataServicesKey: EnvironmentKey {
    static let defaultValue: DataServices? = nil
}

extension EnvironmentValues {
    /// Every data part, for the ones that are not observed (stores whose changes show through the
    /// library's versions).
    var dataServices: DataServices? {
        get { self[DataServicesKey.self] }
        set { self[DataServicesKey.self] = newValue }
    }
}
