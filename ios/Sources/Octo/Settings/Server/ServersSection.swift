import OctoKit
import SwiftUI

/// Server and sync > Your servers: the servers kept on this phone, the one in use on the darker
/// pill, Switch (or Sign in) for the others, each one's menu, and adding another.
struct ServersSection: View {
    let changePassword: () -> Void
    @Environment(Session.self) private var session
    @Environment(ServerSync.self) private var sync
    @Environment(Router.self) private var router
    @Environment(ServerSwitch.self) private var serverSwitch
    @State private var checks: [String: ServerCheck] = [:]
    @State private var removing: StoredServer?

    var body: some View {
        let inUse = session.client == nil ? nil : session.active
        SettingsGroup(title: SettingsIndex.yourServers.title, icon: "server.rack") {
            ForEach(Array(session.servers.enumerated()), id: \.element.id) { index, server in
                row(server, inUse: server.id == inUse?.id, entry: index == 0 ? SettingsIndex.yourServers : nil)
            }
            ActionRow(SettingsIndex.addServer,
                      helper: "Keep another server here and switch to it in one tap. You stay on \(inUse?.name ?? "this one") while you add it.") {
                router.signIn = .add
            }
        }
        .task(id: CheckKey(inUse: inUse?.id, count: session.servers.count)) { await checkAll() }
        .opensWhenAsked("remove_server") { removing = session.servers.first }
    }

    private struct CheckKey: Hashable {
        let inUse: String?
        let count: Int
    }

    /// Every kept server is asked how it is, all at once; earlier answers stay until replaced.
    private func checkAll() async {
        for server in session.servers {
            let id = server.id
            Task { checks[id] = await session.check(id) }
        }
    }

    private func row(_ server: StoredServer, inUse: Bool, entry: SettingEntry?) -> some View {
        let switchingThis = serverSwitch.switching == server.id
        let check = checks[server.id]
        return RowFrame(entry: entry, minHeight: 64) {
            VStack(alignment: .leading, spacing: 1) {
                HStack(spacing: 8) {
                    Text(server.name)
                        .font(.octoBody)
                        .foregroundStyle(server.signedOut ? OctoColor.textSecondary : OctoColor.textPrimary)
                        .lineLimit(1)
                    if inUse { Text("In use").font(.octoCaption).foregroundStyle(OctoColor.textSecondary) }
                }
                Text(accountLine(username: server.username, address: ServerAddress.written(server.address)))
                    .font(.octoCaption)
                    .foregroundStyle(OctoColor.textMuted)
                    .lineLimit(1)
                Text(statusLine(serverType: server.serverType, serverVersion: server.serverVersion, signedOut: server.signedOut,
                                check: check, switching: switchingThis, inUse: inUse))
                    .font(.octoCaption)
                    .foregroundStyle(!inUse && check?.isWarning == true ? OctoColor.signalOrange : OctoColor.textMuted)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            if switchingThis {
                HStack(spacing: 8) {
                    ProgressView().controlSize(.mini).tint(OctoColor.textSecondary).frame(width: 16, height: 16)
                    Text("Switching").font(.octoCaption).foregroundStyle(OctoColor.textSecondary)
                }
            } else if !inUse {
                Button(server.signedOut ? "Sign in" : "Switch") { Task { await use(server) } }
                    .font(.system(size: 14, weight: .semibold))
                    .foregroundStyle(serverSwitch.switching != nil ? OctoColor.textMuted : OctoColor.accent)
                    .padding(.horizontal, 4)
                    .padding(.vertical, 10)
                    .buttonStyle(.plain)
                    .disabled(serverSwitch.switching != nil)
            }
            Menu {
                Section(server.name) {
                    Button("Edit") { router.signIn = .edit(server) }
                    if inUse && server.mode != .apiKey { Button("Change password", action: changePassword) }
                    if server.signedOut {
                        Button("Sign in") { router.signIn = .again(server) }
                    } else {
                        Button("Sign out") { signOut(server, inUse: inUse) }
                    }
                    Button("Remove", role: .destructive) { removing = server }
                }
            } label: {
                Image(systemName: "ellipsis")
                    .font(.system(size: 16, weight: .semibold))
                    .foregroundStyle(OctoColor.textSecondary)
                    .frame(width: 20, height: 20)
                    .padding(8)
                    .contentShape(Rectangle())
            }
            .menuOrder(.fixed)
            .accessibilityLabel("More for \(server.name)")
            .confirmationDialog("Remove \(server.name)?",
                                isPresented: Binding(get: { removing?.id == server.id }, set: { if !$0 { removing = nil } }),
                                titleVisibility: .visible) {
                Button("Remove", role: .destructive) { remove(server, forgetHere: false) }
                Button("Remove, and also delete what's kept here for it", role: .destructive) { remove(server, forgetHere: true) }
            } message: {
                Text(removeDetail(inUse: inUse))
            }
        }
        .background {
            if inUse {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .fill(Color.black.opacity(0.3))
                    .padding(.horizontal, 6)
                    .padding(.vertical, 4)
            }
        }
        .accessibilityAddTraits(inUse ? .isSelected : [])
    }

    private func use(_ server: StoredServer) async {
        if server.signedOut {
            router.signIn = .again(server)
            return
        }
        switch await serverSwitch.switchTo(server.id) {
        case .done(let notice): if let notice { router.done(notice) }
        case .needsPassword(_, let note): router.signIn = .again(server, note: note)
        case .failed(let words): router.show(words)
        }
    }

    /// Acts at once with no question: the one in use stops its library copy first.
    private func signOut(_ server: StoredServer, inUse: Bool) {
        serverSwitch.signOut(server.id)
    }

    /// What removing does, and what each way of removing keeps on this phone.
    private func removeDetail(inUse: Bool) -> String {
        "It leaves your list and Octo forgets its password." + (inUse ? " You'll be signed out of it now." : "")
            + " Your music and playlists stay on the server.\n\n"
            + "Remove keeps its queue, live lists and downloads on this phone, in case you add it again. "
            + "Also deleting what's kept here for it takes them off this phone too."
    }

    private func remove(_ server: StoredServer, forgetHere: Bool) {
        removing = nil
        router.show("Removed \(server.name).", done: true)
        serverSwitch.remove(server.id, forgetHere: forgetHere)
    }
}
