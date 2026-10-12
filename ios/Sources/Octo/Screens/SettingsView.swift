import OctoKit
import SwiftUI

struct SettingsView: View {
    @Environment(Session.self) private var session
    @Environment(Player.self) private var player

    var body: some View {
        @Bindable var session = session
        Form {
            Section("Server") {
                LabeledContent("Address", value: session.serverName)
                LabeledContent("Signed in as", value: session.client?.credentials.username ?? "")
                LabeledContent("Server", value: serverKind)
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
            Section {
                Button("Sign Out", role: .destructive) {
                    player.stop()
                    session.signOut()
                }
            }
            Section("About") {
                LabeledContent("Version", value: Session.appVersion)
            }
        }
        .navigationTitle("Settings")
    }

    private var serverKind: String {
        guard let info = session.profile?.info else { return "…" }
        if session.isOcto { return "Octo " + (info.serverVersion ?? "") }
        return [info.type?.capitalized, info.serverVersion].compactMap { $0 }.joined(separator: " ")
    }

    private func name(of quality: StreamQuality) -> String {
        switch quality {
        case .original: "Original"
        case .mp3(let kbps): "\(kbps) kbps"
        }
    }
}
