import AppIntents
import Observation
import OctoIntents
import OctoSystem

/// What Siri, Spotlight and the Shortcuts app offer for Octo without being set up: play
/// something from the library, shuffle everything, carry on, the liked songs, the newest albums,
/// an album mix, and radio.
struct OctoShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(intent: PlayItemIntent(), phrases: [
            "Play \(\.$item) in \(.applicationName)",
            "Play \(\.$item) on \(.applicationName)",
        ], shortTitle: "Play", systemImageName: "play.fill")
        AppShortcut(intent: PlayMusicIntent(), phrases: [
            "Play music in \(.applicationName)",
            "Shuffle my music in \(.applicationName)",
        ], shortTitle: "Shuffle all", systemImageName: "shuffle")
        AppShortcut(intent: ResumeIntent(), phrases: [
            "Resume \(.applicationName)",
            "Carry on in \(.applicationName)",
        ], shortTitle: "Resume", systemImageName: "music.note.list")
        AppShortcut(intent: PlayLikedIntent(), phrases: [
            "Play my Liked songs in \(.applicationName)",
            "Shuffle my Liked songs in \(.applicationName)",
        ], shortTitle: "Liked songs", systemImageName: "heart.fill")
        AppShortcut(intent: PlayRecentlyAddedIntent(), phrases: [
            "Play recently added in \(.applicationName)",
            "Play my newest albums in \(.applicationName)",
        ], shortTitle: "Recently added", systemImageName: "square.stack.fill")
        AppShortcut(intent: PlayAlbumMixIntent(), phrases: [
            "Play an album mix in \(.applicationName)",
        ], shortTitle: "Album mix", systemImageName: "shuffle")
        AppShortcut(intent: StartRadioIntent(), phrases: [
            "Start radio from \(\.$item) in \(.applicationName)",
            "Start \(\.$item) radio in \(.applicationName)",
        ], shortTitle: "Start radio", systemImageName: "dot.radiowaves.left.and.right")
    }
}

/// Everything the app answers from the system besides its screens: the widgets' shelf and
/// buttons, Siri and Shortcuts, set up once as the app starts.
@MainActor
enum SystemHooks {
    private(set) static var updates: WidgetUpdates?
    private static var actions: SystemActions?
    private static var namesTask: Task<Void, Never>?

    static func start(player: Player, router: Router) {
        guard actions == nil else { return }
        let actions = SystemActions(player: player, router: router)
        Self.actions = actions
        SystemActions.shared = actions
        OctoIntentHost.handler = actions
        let updates = WidgetUpdates(player: player)
        Self.updates = updates
        updates.start()
        SiriAccess.askWhenReady(library: player.data?.library)
        if let library = player.data?.library {
            OctoShortcuts.updateAppShortcutParameters()
            followNames(library)
        }
    }

    /// Siri learns the names of the library's playlists, artists and albums again whenever they
    /// change, a few seconds after the last change.
    private static func followNames(_ library: Library) {
        withObservationTracking {
            _ = library.libraryVersion
            _ = library.playlistsVersion
            _ = library.likesVersion
        } onChange: {
            Task { @MainActor in
                namesTask?.cancel()
                namesTask = Task {
                    try? await Task.sleep(for: .seconds(5))
                    guard !Task.isCancelled else { return }
                    OctoShortcuts.updateAppShortcutParameters()
                }
                followNames(library)
            }
        }
    }
}

/// The intents the app takes from OctoIntents.
struct OctoAppIntents: AppIntentsPackage {
    static var includedPackages: [any AppIntentsPackage.Type] { [OctoIntentsPackage.self] }
}
