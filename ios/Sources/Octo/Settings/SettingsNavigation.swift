import OctoKit
import SwiftUI

/// A settings page to open, and the row a search result pointed at on it.
struct SettingsRoute: Hashable {
    var page: SettingsPage
    var highlight: String?

    init(_ page: SettingsPage, highlight: String? = nil) {
        self.page = page
        self.highlight = highlight
    }
}

/// Pages a settings page opens that are not settings pages themselves.
enum SettingsSideRoute: Hashable {
    case downloads
}

/// A page or popup asked for from outside the pages (the debug launch steps).
@MainActor
@Observable
final class SettingsNavigator {
    static let shared = SettingsNavigator()

    enum Request: Equatable {
        case page(SettingsRoute)
        case search(String)
    }

    var request: Request?
    /// The popup the page in front should open, by the id of the row that opens it.
    var popup: String?
    var whatsNewOpen = false

    private init() {}

    /// Runs one debug launch step:
    /// - `settings:PAGE` opens a settings page (`playback`, `sound`, `radio`, `appearance`, `library`,
    ///   `server`, `streaming`, `audioquality`, `lyrics`, `scrobbling`, `backup`, `about`), and
    ///   `settings:PAGE@ROW` lights that row as a search result does; `settings:homesections`
    ///   opens the Home sections page
    /// - `settings-search:TEXT` types TEXT into the front page's search
    /// - `popup:NAME` opens that popover, sheet or question on the page in front: `speed`,
    ///   `change_password`, `disconnect` and `remove_server` (Server and sync), `delete_link`
    ///   (Shared links, the first), `add_station` (Stations on your server, for an admin),
    ///   `reset_password` (Family, the first member), `paste_list` and `remove_list` (Import, the
    ///   first list), `rename_live_list` and `delete_live_list` (a live list), `save_playlist`
    ///   (Up next), `reset_home_sections` (Home sections). A choice row's answers and every other menu are system menus, which only a
    ///   finger opens.
    /// - `whatsnew` opens About and its What's new panel
    /// - `settings-state:NAME` shows a state a page reaches only with outside help (see
    ///   `driveState`)
    func drive(_ name: String, _ value: String, router: Router) async {
        switch name {
        case "settings":
            router.drive = .tab(.settings)
            try? await Task.sleep(for: .milliseconds(300))
            if value.lowercased() == "homesections" {
                router.go(.homeSections)
                return
            }
            let parts = value.split(separator: "@", maxSplits: 1).map(String.init)
            guard let page = SettingsPage.allCases.first(where: { $0.rawValue.lowercased() == parts.first?.lowercased() }) else { return }
            request = .page(SettingsRoute(page, highlight: parts.count > 1 ? parts[1] : nil))
        case "settings-search":
            router.drive = .tab(.settings)
            request = .search(value)
        case "popup":
            popup = value
        case "whatsnew":
            router.drive = .tab(.settings)
            try? await Task.sleep(for: .milliseconds(300))
            request = .page(SettingsRoute(.about))
            try? await Task.sleep(for: .milliseconds(600))
            whatsNewOpen = true
        #if DEBUG
        case "settings-state":
            await driveState(value)
        #endif
        default:
            break
        }
    }

    #if DEBUG
    /// States a page reaches only with outside help, for checking them on the phone:
    /// - `backup-review` reads a backup of this phone's settings as if from a file, showing the
    ///   review before a restore; `backup-saved`, `backup-failed` and `backup-problem` show
    ///   those notes
    /// - `scrobbling-connected` shows ListenBrainz connected as "octo-check" (no token is
    ///   kept, so sending marks it as needing a new one); `scrobbling-attention` shows the token
    ///   needing replacing; Disconnect on the page clears either
    /// - `updates-on` shows the update controls in a test build, and `updates-check` checks now
    /// - `crossfade-fixed` turns crossfade on and smart transitions off, so the crossfade curve
    ///   can be picked; `crossfade-smart` turns smart transitions back on
    private func driveState(_ state: String) async {
        let session = SettingsNavigator.session
        switch state {
        case "backup-review":
            guard let session else { return }
            let backup = await Backups.shared.make(session: session)
            await BackupModel.shared.review(backup)
        case "backup-saved": BackupModel.shared.saved(true)
        case "backup-failed": BackupModel.shared.saved(false)
        case "backup-problem": await BackupModel.shared.open(URL(fileURLWithPath: "/dev/null"))
        case "scrobbling-connected", "scrobbling-attention":
            let store = AppSettings.shared.listenBrainzStore
            store.set(true, forKey: AppSettings.Keys.enabled)
            store.set(true, forKey: AppSettings.Keys.tokenSealed)
            store.set("octo-check", forKey: AppSettings.Keys.user)
            store.set(state == "scrobbling-attention", forKey: AppSettings.Keys.needsAttention)
            AppSettings.shared.refreshListenBrainz()
        case "updates-on": AppUpdates.shared.showControls()
        case "updates-check": AppUpdates.shared.checkNow()
        case "crossfade-fixed":
            AppSettings.shared.setCrossfade(true)
            AppSettings.shared.setSmartTransitions(false)
        case "crossfade-smart": AppSettings.shared.setSmartTransitions(true)
        default: break
        }
    }

    /// The session, for steps that need it.
    static weak var session: Session?
    #endif
}

extension View {
    /// Runs `open` when a launch step asks the page in front for `name` (`popup:NAME`).
    func opensWhenAsked(_ name: String, _ open: @escaping () -> Void) -> some View {
        modifier(AskedPopup(name: name, open: open))
    }
}

private struct AskedPopup: ViewModifier {
    let name: String
    let open: () -> Void
    @State private var navigator = SettingsNavigator.shared

    func body(content: Content) -> some View {
        content.onChange(of: navigator.popup, initial: true) { _, popup in
            guard popup == name else { return }
            navigator.popup = nil
            open()
        }
    }
}

/// Opens the page a settings route names.
struct SettingsDestination: View {
    let route: SettingsRoute

    var body: some View {
        switch route.page {
        case .playback: PlaybackSettingsPage(highlight: route.highlight)
        case .sound: SoundPage().detailPage()
        case .radio: RadioSettingsPage(highlight: route.highlight)
        case .appearance: AppearanceSettingsPage(highlight: route.highlight)
        case .library: LibrarySettingsPage(highlight: route.highlight)
        case .server: ServerPage(highlight: route.highlight)
        case .streaming: StreamingSettingsPage(highlight: route.highlight)
        case .audioQuality: AudioQualitySettingsPage(highlight: route.highlight)
        case .lyrics: LyricsSettingsPage(highlight: route.highlight)
        case .scrobbling: ScrobblingSettingsPage(highlight: route.highlight)
        case .backup: BackupSettingsPage(highlight: route.highlight)
        case .about: AboutSettingsPage(highlight: route.highlight)
        }
    }
}

extension View {
    /// Every page the Settings tab opens, pushed onto its own stack.
    func settingsRoutes() -> some View {
        navigationDestination(for: SettingsRoute.self) { route in
            SettingsDestination(route: route)
        }
        .navigationDestination(for: SettingsSideRoute.self) { route in
            switch route {
            case .downloads: DownloadsPage().background { PageBackdrop(page: .downloads, route: nil) }.detailPage()
            }
        }
        .accountRoutes()
    }
}

