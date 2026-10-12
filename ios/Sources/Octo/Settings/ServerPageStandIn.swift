import OctoKit
import SwiftUI

/// The servers kept on this phone, until the full Server and sync page is in: switch, sign in
/// again, edit, sign out or remove each one, and add another.
struct ServerPageStandIn: View {
    var highlight: String?
    @Environment(Session.self) private var session
    @Environment(Player.self) private var player
    @Environment(Router.self) private var router
    @State private var removing: StoredServer?
    @State private var switching: String?

    var body: some View {
        SettingsPageFrame(title: SettingsPage.server.title, highlight: highlight) {
            if session.servers.isEmpty {
                SettingsGroup {
                    ActionRow(SettingsIndex.connectServer, helper: SettingsIndex.connectServer.summary) { router.signIn = .signIn }
                }
            } else {
                SettingsGroup(title: "Your servers", icon: "externaldrive.connected.to.line.below") {
                    ForEach(session.servers) { server in serverRow(server) }
                    ActionRow(SettingsIndex.addServer) { router.signIn = .add }
                }
            }
        }
        .confirmationDialog(removing.map { "Remove \($0.name)?" } ?? "", isPresented: Binding(get: { removing != nil }, set: { if !$0 { removing = nil } }),
                            titleVisibility: .visible) {
            Button("Remove", role: .destructive) {
                if let removing {
                    if removing.id == session.activeId { player.stop() }
                    session.remove(removing.id)
                }
                removing = nil
            }
        }
    }

    private func serverRow(_ server: StoredServer) -> some View {
        let inUse = server.id == session.activeId && session.client != nil
        return HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(server.name).font(.octoBody).foregroundStyle(OctoColor.textPrimary)
                    if inUse {
                        Text("In use")
                            .font(.system(size: 11, weight: .semibold))
                            .padding(.horizontal, 7).padding(.vertical, 2)
                            .background(OctoColor.accent.opacity(0.2), in: Capsule())
                    }
                }
                Text(server.account).font(.octoCaption).foregroundStyle(OctoColor.textMuted)
                Text(status(server)).font(.octoCaption).foregroundStyle(OctoColor.textMuted)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
            if !inUse {
                Button(server.signedOut ? "Sign in" : "Switch") { Task { await use(server) } }
                    .buttonStyle(.glass)
                    .disabled(switching != nil)
            }
            Menu {
                Button("Edit") { router.signIn = .edit(server) }
                if server.signedOut {
                    Button("Sign in") { router.signIn = .again(server) }
                } else {
                    Button("Sign out") {
                        if inUse { player.stop() }
                        session.signOut(server.id)
                    }
                }
                Button("Remove", role: .destructive) { removing = server }
            } label: {
                Image(systemName: "ellipsis").frame(width: 32, height: 32).foregroundStyle(OctoColor.textPrimary)
            }
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 12)
        .frame(minHeight: 56)
    }

    private func status(_ server: StoredServer) -> String {
        if switching == server.id { return "Switching to it now" }
        if server.signedOut { return "Signed out. Sign in again to use it." }
        return server.kind.isEmpty ? "Subsonic" : server.kind
    }

    private func use(_ server: StoredServer) async {
        if server.signedOut {
            router.signIn = .again(server)
            return
        }
        switching = server.id
        defer { switching = nil }
        do {
            try await session.switchTo(server.id)
            router.show("Now on \(server.name).", done: true)
        } catch SignInFailure.needsPassword(_, let words) {
            router.show(words)
            router.signIn = .again(server)
        } catch {
            router.show(error.localizedDescription)
        }
    }
}
