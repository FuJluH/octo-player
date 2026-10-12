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
        case popup(String)
        case whatsNew
    }

    var request: Request?
    /// The popup the page in front should open, by the id of the row that opens it.
    var popup: String?
    var whatsNewOpen = false

    private init() {}

    /// Runs one debug launch step:
    /// - `settings:PAGE` opens a settings page (`playback`, `sound`, `appearance`, `library`,
    ///   `server`, `streaming`, `audioquality`, `lyrics`, `scrobbling`, `backup`, `about`), and
    ///   `settings:PAGE@ROW` lights that row as a search result does
    /// - `settings-search:TEXT` types TEXT into the front page's search
    /// - `popup:ROW` opens the popup of that row on the page in front (`speed`, or any choice
    ///   row's id such as `radio_discovery`, `ambient`, `cache_size`)
    /// - `whatsnew` opens About and its What's new panel
    func drive(_ name: String, _ value: String, router: Router) async {
        switch name {
        case "settings":
            router.drive = .tab(.settings)
            try? await Task.sleep(for: .milliseconds(300))
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
        default:
            break
        }
    }
}

/// Opens the page a settings route names. Sound and Server and sync are built by their own
/// parts of the app; until they are in, these pages stand in for them.
struct SettingsDestination: View {
    let route: SettingsRoute

    var body: some View {
        switch route.page {
        case .playback: PlaybackSettingsPage(highlight: route.highlight)
        case .sound: SoundPageStandIn()
        case .appearance: AppearanceSettingsPage(highlight: route.highlight)
        case .library: LibrarySettingsPage(highlight: route.highlight)
        case .server: ServerPageStandIn(highlight: route.highlight)
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
            case .downloads: DownloadsStandIn()
            }
        }
    }
}

/// Where the Sound page goes once its part of the app is in.
private struct SoundPageStandIn: View {
    var body: some View {
        SettingsPageFrame(title: SettingsPage.sound.title) {
            SettingsGroup {
                NoteRow("The equalizer, loudness, balance and headphone correction for each output.")
            }
        }
    }
}

/// Where the Downloads screen goes once its part of the app is in.
private struct DownloadsStandIn: View {
    var body: some View {
        SettingsPageFrame(title: "Downloads") {
            SettingsGroup {
                NoteRow("What is downloaded, and how much room it takes.")
            }
        }
    }
}
