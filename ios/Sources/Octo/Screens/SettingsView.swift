import OctoKit
import SwiftUI

struct SettingsView: View {
    @Environment(Session.self) private var session
    @Environment(Player.self) private var player
    @Environment(Router.self) private var router
    @Environment(SoundStore.self) private var sound
    @State private var removing: StoredServer?
    @State private var switching: String?

    var body: some View {
        @Bindable var session = session
        List {
            Section {
                ScreenTitle("Settings")
                    .listRowInsets(EdgeInsets())
                    .listRowBackground(Color.clear)
                    .listRowSeparator(.hidden)
            }
            Section {
                accountCard
                    .listRowInsets(EdgeInsets(top: 4, leading: 20, bottom: 4, trailing: 20))
                    .listRowBackground(Color.clear)
                    .listRowSeparator(.hidden)
            }
            Section {
                NavigationLink(value: Route.sound) {
                    Label {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("Sound").font(.octoBody)
                            Text(SoundEdits.soundSummary(sound.current)).font(.octoCaption).foregroundStyle(OctoColor.textMuted)
                        }
                    } icon: {
                        Image(systemName: "slider.horizontal.3").foregroundStyle(OctoColor.accent)
                    }
                }
            } header: {
                Text("Listening")
            }
            if !session.servers.isEmpty {
                Section {
                    ForEach(session.servers) { server in serverRow(server) }
                    Button {
                        router.signIn = .add
                    } label: {
                        Label("Add a server", systemImage: "plus")
                    }
                } header: {
                    Text("Your servers")
                }
            }
            Section {
                Picker("Quality", selection: $session.quality) {
                    ForEach(StreamQuality.choices, id: \.self) { quality in
                        Text(name(of: quality)).tag(quality)
                    }
                }
            } header: {
                Text("Streaming")
            } footer: {
                Text("Original plays each file as it is. Formats the iPhone can't open are turned into MP3 by the server.")
            }
            Section("About") {
                LabeledContent("Version", value: Session.appVersion)
            }
        }
        .scrollContentBackground(.hidden)
        .background(OctoColor.background)
        .barClearance()
        .confirmationDialog(removing.map { "Remove \($0.name)?" } ?? "", isPresented: Binding(get: { removing != nil }, set: { if !$0 { removing = nil } }), titleVisibility: .visible) {
            Button("Remove", role: .destructive) {
                if let removing {
                    if removing.id == session.activeId { player.stop() }
                    session.remove(removing.id)
                }
                removing = nil
            }
        }
    }

    /// The card at the top: the server in use, or a way to connect one.
    @ViewBuilder
    private var accountCard: some View {
        Button {
            if session.servers.isEmpty { router.signIn = .signIn }
        } label: {
            HStack(spacing: 14) {
                Image(systemName: session.active == nil ? "server.rack" : "checkmark.circle.fill")
                    .font(.system(size: 22))
                    .foregroundStyle(OctoColor.accent)
                    .frame(width: 32)
                VStack(alignment: .leading, spacing: 2) {
                    Text(cardTitle).font(.octoBody).foregroundStyle(.white)
                    Text(cardDetail).font(.octoCaption).foregroundStyle(OctoColor.textMuted)
                }
                Spacer()
                if session.servers.isEmpty {
                    Image(systemName: "chevron.right").foregroundStyle(OctoColor.textMuted)
                }
            }
            .padding(16)
            .frame(maxWidth: .infinity, alignment: .leading)
            .glassEffect(.regular, in: .rect(cornerRadius: 20))
        }
        .buttonStyle(.plain)
    }

    private var cardTitle: String {
        if let active = session.active, session.client != nil { return active.name }
        return session.servers.isEmpty ? "Connect a music server" : "Your servers"
    }

    private var cardDetail: String {
        if let active = session.active, session.client != nil {
            let place = active.homeAddress == nil ? "" : (session.atHome ? " · Connected at home" : " · Connected away")
            return active.account + place
        }
        return session.servers.isEmpty ? "Add the music on your own server" : "Signed out. Sign in to one, or add another."
    }

    private func serverRow(_ server: StoredServer) -> some View {
        let inUse = server.id == session.activeId && session.client != nil
        return HStack(spacing: 12) {
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(server.name).font(.octoBody)
                    if inUse {
                        Text("In use")
                            .font(.system(size: 11, weight: .semibold))
                            .padding(.horizontal, 7).padding(.vertical, 2)
                            .background(OctoColor.accent.opacity(0.2), in: Capsule())
                    }
                }
                Text(server.account).font(.octoCaption).foregroundStyle(OctoColor.textMuted)
                Text(status(server, inUse: inUse)).font(.octoCaption).foregroundStyle(OctoColor.textMuted)
            }
            Spacer()
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
                Image(systemName: "ellipsis").frame(width: 32, height: 32)
            }
        }
    }

    private func status(_ server: StoredServer, inUse: Bool) -> String {
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
            let previous = session.active?.name
            try await session.switchTo(server.id)
            router.show(previous.map { _ in "Now on \(server.name)." } ?? "Now on \(server.name).", done: true)
        } catch SignInFailure.needsPassword(_, let words) {
            router.show(words)
            router.signIn = .again(server)
        } catch {
            router.show(error.localizedDescription)
        }
    }

    private func name(of quality: StreamQuality) -> String {
        switch quality {
        case .original: "Original"
        case .mp3(let kbps): "\(kbps) kbps"
        }
    }
}
