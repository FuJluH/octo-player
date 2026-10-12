import OctoKit
import SwiftUI

/// Settings > Server and sync: the servers kept on this phone, and for the one in use where it
/// is, who is signed in, what it is and offers, how fresh the copy of its library is, what else
/// it has, and signing out.
struct ServerPage: View {
    let highlight: String?
    @Environment(Session.self) private var session
    @Environment(ServerSync.self) private var sync
    @Environment(Accounts.self) private var accounts
    @Environment(ServerControls.self) private var controls
    @Environment(Router.self) private var router
    @Environment(Prompts.self) private var prompts
    @Environment(ServerSwitch.self) private var serverSwitch
    @State private var changingPassword = false
    @State private var navigator = SettingsNavigator.shared
    @State private var folders: [ServerMusicFolder]?
    @State private var folderProblem: String?
    @State private var pickingFolder = false
    @State private var look: (answerMs: Int64?, scan: ServerScanStatus?)?
    @State private var listening: [ServerNowPlaying] = []
    @Environment(\.dataServices) private var data
    @State private var queueSync = ServerSyncChoices().syncQueue

    var body: some View {
        SettingsPageFrame(title: SettingsPage.server.title, highlight: highlight) {
            if !session.servers.isEmpty { ServersSection(changePassword: { changingPassword = true }) }
            if let server = session.active, session.client != nil {
                connection(server)
                facts(server)
                syncGroup(server)
                onTheServer
                if !listening.isEmpty {
                    SettingsGroup(title: SettingsIndex.listeningNow.title, icon: SettingsIcon.listeners) {
                        ForEach(listening) { entry in
                            InfoRow(nil, title: listenerTitle(entry), value: "", helper: listenerLine(entry))
                        }
                    }
                }
                SettingsGroup {
                    ActionRow(SettingsIndex.disconnect, chevron: false, destructive: true, action: askSignOut)
                }
            } else if session.servers.isEmpty {
                SettingsGroup(footer: "Your server's music joins your library here.") {
                    ActionRow(SettingsIndex.connectServer) { router.signIn = .signIn }
                }
            }
        }
        .glassPopup(isPresented: $changingPassword, title: "Change password", usesPressSpot: false, maxWidth: 400) {
            ChangePasswordForm { changingPassword = false }
        }
        .task(id: session.client == nil ? nil : session.activeId) { await lookAgain() }
        .task(id: session.client == nil ? nil : session.activeId) { await watchListening() }
        .task(id: session.activeId) { _ = try? await controls.shares() }
        .onChange(of: session.activeId) { folderProblem = nil }
        .onChange(of: navigator.popup, initial: true) { _, popup in openAsked(popup) }
    }

    // MARK: Connection

    private func connection(_ server: StoredServer) -> some View {
        SettingsGroup(title: "Connection", icon: "globe") {
            InfoRow(SettingsIndex.serverAddress, value: ServerAddress.shown(server.address))
            if let place = session.place {
                InfoRow(SettingsIndex.serverConnection, value: place == .home ? "Connected at home" : "Connected away")
            }
            InfoRow(SettingsIndex.serverUser, value: server.username.isEmpty ? "API key" : server.username)
            FolderRow(value: session.folder(for: server.id)?.name ?? "All") { Task { await openFolders() } }
                .choicePopover(isPresented: $pickingFolder, question: folderQuestion(server))
            if let folderProblem { NoteRow(folderProblem, color: OctoColor.error) }
            ActionRow(SettingsIndex.editConnection) { router.signIn = .editConnection(server) }
            if server.mode != .apiKey {
                ActionRow(SettingsIndex.changePassword) { changingPassword = true }
            }
            if session.runsOcto {
                AccountLinkRow(entry: SettingsIndex.octoAdmin, route: .admin)
                AccountLinkRow(entry: SettingsIndex.importMusic, route: .imports)
            }
            if session.family {
                AccountLinkRow(entry: SettingsIndex.family, route: .family)
                AccountLinkRow(entry: SettingsIndex.signInElsewhere, route: .family) { accounts.family.model.handOver.open() }
            }
        }
    }

    /// Reads the server's folders; when that fails a note says so and nothing opens.
    private func openFolders() async {
        guard let client = session.client else { return }
        do {
            folders = try await client.serverMusicFolders()
            folderProblem = nil
            pickingFolder = true
        } catch {
            folderProblem = "Couldn't read the server's music folders."
        }
    }

    private func folderQuestion(_ server: StoredServer) -> SettingsQuestion {
        let listed = folders ?? []
        let chosen = session.folder(for: server.id)
        let picked = listed.firstIndex { $0.id == chosen?.id }.map { $0 + 1 } ?? 0
        let answers = [SettingsAnswer("All", "Every folder on the server")] + listed.map { SettingsAnswer($0.name) }
        return SettingsQuestion(title: "Music folder", answers: answers, selected: picked) { index in
            let folder = index == 0 ? nil : listed[index - 1]
            guard folder?.id != chosen?.id else { return }
            session.setFolder(folder, for: server.id)
            sync.chooseMusicFolder(folder?.id, for: server.id)
        }
    }

    // MARK: Server

    private func facts(_ server: StoredServer) -> some View {
        SettingsGroup(title: "Server", icon: SettingsIcon.info) {
            InfoRow(SettingsIndex.serverKind,
                    value: serverKind(server.serverType ?? session.profile?.info.type, server.serverVersion ?? session.profile?.info.serverVersion),
                    helper: offersOf(session.extensions))
            if let ms = look?.answerMs {
                InfoRow(SettingsIndex.serverAnswer, value: "\(ms) ms")
            }
            if let words = scanWords(look?.scan, nowMs: epochNowMs()) {
                InfoRow(SettingsIndex.serverScan, value: "", helper: words)
            }
        }
    }

    /// One quick look for each session: how fast it answers and how its folders scan stands.
    private func lookAgain() async {
        look = nil
        guard session.client != nil else { return }
        look = await session.look()
    }

    // MARK: Sync

    private func syncGroup(_ server: StoredServer) -> some View {
        let copy = sync.last.flatMap { $0.sourceId == server.sourceId ? $0 : nil }
        return SettingsGroup(title: "Sync", icon: SettingsIcon.sync) {
            InfoRow(SettingsIndex.lastSynced, value: copy.map { SettingsSummaries.timeAgo($0.at, now: epochNowMs()) } ?? "Not yet")
            if let copy {
                InfoRow(nil, title: "Songs", value: SettingsSummaries.grouped(Int(copy.songs)))
                InfoRow(nil, title: "Albums", value: SettingsSummaries.grouped(Int(copy.albums)))
            }
            ActionRow(SettingsIndex.syncNow, chevron: false, busy: sync.syncing) { sync.syncNow() }
            if let problem = sync.problem { NoteRow(problem, color: OctoColor.error) }
            ToggleRow(SettingsIndex.queueSync, isOn: queueSync,
                      helper: "Keeps what's playing on the server, so you can pick up where another device left off.") { on in
                queueSync = on
                ServerSyncChoices().setSyncQueue(on)
            }
            ToggleRow(SettingsIndex.playlistsToServer, isOn: data?.playlistSync.newOnServer ?? false,
                      helper: "New playlists are made on your server too.") { on in
                data?.playlistSync.setNewOnServer(on)
            }
        }
    }

    // MARK: On the server

    private var onTheServer: some View {
        return SettingsGroup(title: "On the server", icon: SettingsIcon.cloud) {
            if controls.sharing { AccountLinkRow(entry: SettingsIndex.shares, route: .shares) }
            AccountLinkRow(entry: SettingsIndex.radioStations, route: .radioStations)
            if controls.isAdmin {
                let scan = controls.scan
                let scanning = if case .scanning = scan { true } else { false }
                let failed = if case .failed = scan { true } else { false }
                ActionRow(SettingsIndex.scanServer, title: scanLabel(scan), chevron: false, busy: scanning, destructive: failed) {
                    controls.startScan()
                }
            }
        }
    }

    /// Who is listening, read at once and then every minute while the page shows.
    private func watchListening() async {
        listening = []
        guard session.client != nil else { return }
        while !Task.isCancelled {
            listening = (try? await controls.othersListening()) ?? []
            try? await Task.sleep(for: .seconds(60))
        }
    }

    // MARK: Sign out

    /// A popup asked for from outside the page, by the id of the row that opens it.
    private func openAsked(_ popup: String?) {
        switch popup {
        case SettingsIndex.changePassword.id: changingPassword = true
        case SettingsIndex.disconnect.id: askSignOut()
        case SettingsIndex.serverMusicFolder.id: Task { await openFolders() }
        default: return
        }
        navigator.popup = nil
    }

    /// Asks beside the row before signing out of the server in use.
    private func askSignOut() {
        prompts.confirm("Sign out of \(session.active?.name ?? "the server")?",
                        detail: "Its music leaves your library on this phone until you sign in again. It stays in your list, and nothing on the server changes.",
                        confirm: "Sign out") {
            if let id = session.activeId { serverSwitch.signOut(id) }
        }
    }
}

/// The Music folder row: its title, the folder in use at the end, and the small chevron of a
/// choice. The answers open beside it once the server's folders are read.
private struct FolderRow: View {
    let value: String
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            RowFrame(entry: SettingsIndex.serverMusicFolder) {
                Text(SettingsIndex.serverMusicFolder.title).font(.octoBody).foregroundStyle(OctoColor.textPrimary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                Text(value)
                    .font(.octoBodySmall)
                    .foregroundStyle(OctoColor.textSecondary)
                    .multilineTextAlignment(.trailing)
                    .lineLimit(2)
                    .layoutPriority(-1)
                Image(systemName: SettingsIcon.chevron)
                    .font(.system(size: 13, weight: .semibold))
                    .frame(width: 18, height: 18)
                    .foregroundStyle(OctoColor.textMuted)
                    .accessibilityHidden(true)
            }
        }
        .buttonStyle(SettingsRowPress())
        .accessibilityLabel(SettingsIndex.serverMusicFolder.title)
        .accessibilityValue(value)
    }
}
