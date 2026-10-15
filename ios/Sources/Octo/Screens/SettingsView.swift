import OctoKit
import SwiftUI

/// Settings' front page: the account, a search across every setting, and the categories, each
/// with a line on how it is set now.
struct SettingsView: View {
    @Environment(Session.self) private var session
    @Environment(Router.self) private var router
    @Environment(SoundStore.self) private var sound
    @SceneStorage("settings.query") private var query = ""
    @State private var navigator = SettingsNavigator.shared
    @State private var settings = AppSettings.shared
    @State private var phone = PhoneMusic.shared
    @State private var feeds = SettingsFeeds.shared
    @State private var updates = AppUpdates.shared
    @State private var serverUpdates = ServerUpdates.shared
    @State private var listenBrainz = ListenBrainzSync.shared
    @State private var driven: SettingsRoute?
    @FocusState private var searching: Bool

    var body: some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 20) {
                ScreenTitle("Settings")
                accountCard
                searchField
                if !query.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    results(searchSettings(query))
                } else {
                    categories
                }
            }
            .padding(.top, 8)
        }
        .scrollIndicators(.hidden)
        .scrollDismissesKeyboard(.immediately)
        .barClearance()
        .settingsRoutes()
        .navigationDestination(item: $driven) { SettingsDestination(route: $0) }
        .task {
            AccountQualityModel.shared.attach(session)
            #if DEBUG
            SettingsNavigator.session = session
            #endif
            settings.attach(session: session) { AccountQualityModel.shared.appPicks }
            phone.start()
            listenBrainz.start()
            updates.start()
            serverUpdates.start(session)
        }
        // The account's quality is read at start and whenever the account in use changes.
        .task(id: "\(session.activeId ?? "")|\(session.client != nil)|\(session.profile?.extensions.count ?? -1)") {
            await AccountQualityModel.shared.load()
        }
        .onChange(of: navigator.request) { _, request in
            guard let request else { return }
            navigator.request = nil
            switch request {
            case .page(let route): driven = route
            case .search(let text): query = text
            }
        }
    }

    // MARK: Account card

    /// The server signed in to and how it is doing, and the music on the phone.
    private var accountCard: some View {
        SettingsGroup(inset: iconRowInset) {
            serverRow
            AccountRow(icon: SettingsIcon.phone, title: SettingsSummaries.phoneLine(phone.access, songs: phone.songCount), lines: []) { label in
                NavigationLink(value: SettingsRoute(.library)) { label }
            }
        }
    }

    @ViewBuilder
    private var serverRow: some View {
        if let active = session.active, session.client != nil {
            let problem = feeds.syncProblem
            let status = problem ?? SettingsSummaries.serverStatus(
                syncing: feeds.syncing,
                place: active.homeAddress == nil ? nil : (session.atHome ? .home : .away),
                syncedAt: syncedAt(active.id),
                now: now
            )
            AccountRow(icon: SettingsIcon.cloud, title: active.name, lines: [
                (active.username.isEmpty ? "Signed in with a key" : active.username, OctoColor.textSecondary),
                (status, problem != nil ? OctoColor.error : OctoColor.textMuted),
            ]) { label in NavigationLink(value: SettingsRoute(.server)) { label } }
        } else if session.servers.isEmpty {
            AccountRow(icon: SettingsIcon.cloud, title: "Connect a music server",
                       lines: [("Add the music on your own server", OctoColor.textMuted)]) { label in
                Button { router.signIn = .signIn } label: { label }
            }
        } else {
            // Servers are kept, none in use: the list is where to go.
            AccountRow(icon: SettingsIcon.cloud, title: "Your servers",
                       lines: [("Signed out. Sign in to one, or add another.", OctoColor.textMuted)]) { label in
                NavigationLink(value: SettingsRoute(.server)) { label }
            }
        }
    }

    // MARK: Search

    private var searchField: some View {
        SettingsSearchField(placeholder: "Search settings", text: $query, focused: $searching)
            .submitLabel(.search)
            .onSubmit { searching = false }
            .padding(.horizontal, 16)
    }

    /// What a search found: each setting, with the page it is on.
    private func results(_ found: [SettingEntry]) -> some View {
        SettingsGroup {
            if found.isEmpty { NoteRow("No settings match.") }
            ForEach(found) { entry in
                if entry.page == .sound {
                    LinkRow(nil, title: entry.title, helper: entry.place, to: Route.sound)
                } else {
                    LinkRow(nil, title: entry.title, helper: entry.place, to: SettingsRoute(entry.page, highlight: entry.id))
                }
            }
        }
    }

    // MARK: Categories

    private var categories: some View {
        let player = settings.player
        let serverLine: String = {
            guard let active = session.active, session.client != nil else { return "Not connected" }
            return SettingsSummaries.serverStatus(syncing: feeds.syncing, place: nil, syncedAt: syncedAt(active.id), now: now)
        }()
        return VStack(spacing: 20) {
            SettingsGroup(title: "Listening", inset: iconRowInset) {
                CategoryRow(icon: SettingsIcon.playback, title: SettingsPage.playback.title,
                            summary: SettingsSummaries.playback(player), to: SettingsRoute(.playback))
                CategoryRow(icon: SettingsIcon.sound, title: SettingsPage.sound.title,
                            summary: SoundEdits.soundSummary(sound.current), to: Route.sound)
                CategoryRow(icon: SettingsIcon.radio, title: SettingsPage.radio.title,
                            summary: SettingsSummaries.radio(player), to: SettingsRoute(.radio))
                CategoryRow(icon: SettingsIcon.appearance, title: SettingsPage.appearance.title,
                            summary: SettingsSummaries.appearance(player.ambient, liveBackground: player.liveBackground),
                            to: SettingsRoute(.appearance))
            }
            SettingsGroup(title: "Your music", inset: iconRowInset) {
                CategoryRow(icon: SettingsIcon.library, title: SettingsPage.library.title,
                            summary: SettingsSummaries.library(phone.access, songs: phone.songCount, folders: libraryFolders),
                            to: SettingsRoute(.library))
                CategoryRow(icon: SettingsIcon.cloud, title: SettingsPage.server.title, summary: serverLine, to: SettingsRoute(.server),
                            badged: serverUpdates.showsDot)
                CategoryRow(icon: SettingsIcon.download, title: SettingsPage.streaming.title,
                            summary: SettingsSummaries.streaming(settings.stream, settings.offline), to: SettingsRoute(.streaming))
                CategoryRow(icon: SettingsIcon.audioQuality, title: SettingsPage.audioQuality.title,
                            summary: SettingsSummaries.audioQuality, to: SettingsRoute(.audioQuality))
            }
            SettingsGroup(title: "Lyrics and history", inset: iconRowInset) {
                CategoryRow(icon: SettingsIcon.lyrics, title: SettingsPage.lyrics.title,
                            summary: SettingsSummaries.lyrics(online: player.lyricsOnline, keepScreenOn: settings.keepScreenOn),
                            to: SettingsRoute(.lyrics))
                CategoryRow(icon: SettingsIcon.scrobbling, title: SettingsPage.scrobbling.title,
                            summary: SettingsSummaries.scrobbling(settings.listenBrainz), to: SettingsRoute(.scrobbling))
            }
            SettingsGroup(title: "This app", inset: iconRowInset) {
                CategoryRow(icon: SettingsIcon.backup, title: SettingsPage.backup.title, summary: SettingsSummaries.backup,
                            to: SettingsRoute(.backup))
                // A ready update shows here, quietly, in place of the version.
                CategoryRow(icon: SettingsIcon.info, title: SettingsPage.about.title,
                            summary: SettingsSummaries.about(version: Session.appVersion, updateReady: updates.state.ready?.version),
                            to: SettingsRoute(.about))
            }
        }
    }

    /// The phone's folders with whether each counts.
    private var libraryFolders: [MusicFolder] {
        phone.folders.map { MusicFolder($0.name, songs: $0.songs, included: !settings.excludedFolders.contains($0.name)) }
    }

    /// The last copy's time, only when it belongs to this server.
    private func syncedAt(_ serverId: String) -> Int64? {
        guard let last = feeds.lastSync, last.serverId == serverId else { return nil }
        return Int64(last.at.timeIntervalSince1970 * 1000)
    }

    /// Now, read again every half minute while the page shows, for "Synced 5 min ago".
    private var now: Int64 {
        Int64(SettingsClock.shared.now.timeIntervalSince1970 * 1000)
    }
}

/// The time, moving on every half minute, for lines like "Synced 5 min ago".
@MainActor
@Observable
final class SettingsClock {
    static let shared = SettingsClock()
    private(set) var now = Date()

    private init() {
        Task { @MainActor in
            while true {
                try? await Task.sleep(for: .seconds(30))
                SettingsClock.shared.now = Date()
            }
        }
    }
}

/// One row of the account card: an icon tile, a title and lines under it in their own colors,
/// and a chevron. `wrap` makes the row a button or a link.
private struct AccountRow<Wrapped: View>: View {
    let icon: String
    let title: String
    let lines: [(String, Color)]
    let wrap: (AnyView) -> Wrapped

    init(icon: String, title: String, lines: [(String, Color)], @ViewBuilder wrap: @escaping (AnyView) -> Wrapped) {
        self.icon = icon
        self.title = title
        self.lines = lines
        self.wrap = wrap
    }

    var body: some View {
        wrap(AnyView(label)).buttonStyle(SettingsRowPress())
    }

    private var label: some View {
        HStack(spacing: 16) {
            IconTile(icon: icon)
            VStack(alignment: .leading, spacing: 0) {
                Text(title).font(.octoBody).foregroundStyle(OctoColor.textPrimary).fixedSize(horizontal: false, vertical: true)
                ForEach(Array(lines.enumerated()), id: \.offset) { _, line in
                    Text(line.0).font(.octoCaption).foregroundStyle(line.1).lineLimit(1)
                }
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            Image(systemName: SettingsIcon.chevron)
                .font(.system(size: 14, weight: .semibold))
                .frame(width: 20, height: 20)
                .foregroundStyle(OctoColor.textMuted)
                .accessibilityHidden(true)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .frame(maxWidth: .infinity, minHeight: 56, alignment: .leading)
        .contentShape(Rectangle())
    }
}

/// A one-line glass field: a faint accent fill that deepens with a ring while typing, a muted
/// search mark at its end while empty, and a clear button once something is typed.
struct SettingsSearchField: View {
    let placeholder: String
    @Binding var text: String
    var focused: FocusState<Bool>.Binding

    var body: some View {
        let on = focused.wrappedValue
        HStack(spacing: 8) {
            TextField(placeholder, text: $text)
                .font(.octoBody)
                .foregroundStyle(OctoColor.textPrimary)
                .textInputAutocapitalization(.never)
                .autocorrectionDisabled()
                .focused(focused)
            if text.isEmpty {
                Image(systemName: SettingsIcon.search)
                    .font(.system(size: 17))
                    .frame(width: 20, height: 20)
                    .foregroundStyle(OctoColor.textMuted)
                    .accessibilityHidden(true)
            } else {
                Button { text = "" } label: {
                    Image(systemName: SettingsIcon.close)
                        .font(.system(size: 15, weight: .semibold))
                        .frame(width: 20, height: 20)
                        .foregroundStyle(OctoColor.textMuted)
                }
                .buttonStyle(.plain)
                .accessibilityLabel("Clear search")
            }
        }
        .padding(.horizontal, 14)
        .frame(height: 48)
        .background(OctoColor.accent.opacity(on ? 0.15 : 0.10), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
        .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous).stroke(OctoColor.accent.opacity(on ? 0.6 : 0.1), lineWidth: on ? 1.5 : 1))
        .glassEffect(Glass.octo, in: .rect(cornerRadius: 12))
        .animation(.easeOut(duration: 0.2), value: on)
    }
}
