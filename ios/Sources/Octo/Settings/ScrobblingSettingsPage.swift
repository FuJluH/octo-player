import OctoKit
import SwiftUI

/// Sending plays to ListenBrainz straight from the phone, with or without a server.
struct ScrobblingSettingsPage: View {
    var highlight: String?
    @Environment(\.openURL) private var openURL
    @State private var settings = AppSettings.shared
    @State private var sync = ListenBrainzSync.shared
    /// The token as typed. Only held here while connecting, never saved as it is.
    @State private var token = ""
    @State private var checking = false
    @State private var problem: String?
    @FocusState private var typing: Bool

    var body: some View {
        let prefs = settings.listenBrainz
        SettingsPageFrame(title: SettingsPage.scrobbling.title, highlight: highlight) {
            SettingsGroup(title: "ListenBrainz", mark: { ListenBrainzMark() }) {
                ToggleRow(SettingsIndex.listenBrainz, isOn: prefs.enabled, helper: "The songs you play, on your profile.", onChange: sync.setEnabled)
                if prefs.enabled && prefs.connected {
                    if prefs.needsAttention {
                        NoteRow("The saved token stopped working. Paste a new one; plays wait here until then.", color: OctoColor.error)
                    } else {
                        InfoRow(nil, title: "Connected as", value: prefs.user ?? "")
                    }
                    if sync.queued > 0 {
                        InfoRow(nil, title: "Waiting to send", value: SettingsSummaries.grouped(sync.queued))
                    }
                }
            }
            if prefs.enabled {
                if !prefs.connected || prefs.needsAttention {
                    SettingsGroup(title: "Connect", icon: SettingsIcon.key) {
                        NoteRow("Paste the user token from your ListenBrainz settings. It stays encrypted on this phone.")
                        ActionRow(nil, title: "Open ListenBrainz settings") { openURL(listenBrainzTokenPage) }
                        tokenEntry
                    }
                }
                if prefs.connected {
                    SettingsGroup(footer: "If your server already sends its plays, choose Only songs on this phone so none count twice.") {
                        ChoiceRow(SettingsIndex.sendPlays, value: prefs.sendPlays.label, question: SettingsQuestion(
                            SettingsIndex.sendPlays.title, SendPlays.allCases, current: prefs.sendPlays,
                            answer: { SettingsAnswer($0.label, $0.detail) }, pick: sync.setSendPlays))
                        ToggleRow(SettingsIndex.nowPlaying, isOn: prefs.nowPlaying, helper: "Shown on your profile while it plays.",
                                  onChange: sync.setNowPlaying)
                    }
                    SettingsGroup {
                        ActionRow(SettingsIndex.scrobblingDisconnect, chevron: false, destructive: true) {
                            token = ""
                            problem = nil
                            Task { await sync.disconnect() }
                        }
                    }
                }
            }
        }
    }

    /// The field the token is pasted into, Connect beside it, and what went wrong under them.
    private var tokenEntry: some View {
        VStack(alignment: .leading, spacing: 0) {
            HStack(spacing: 10) {
                SecureField("User token", text: Binding(get: { token }, set: { token = $0.trimmingCharacters(in: .whitespacesAndNewlines) }))
                    .font(.octoBody)
                    .textInputAutocapitalization(.never)
                    .autocorrectionDisabled()
                    .textContentType(.password)
                    .submitLabel(.done)
                    .focused($typing)
                    .onSubmit(connect)
                    .padding(.horizontal, 14)
                    .frame(height: 48)
                    .background(OctoColor.accent.opacity(typing ? 0.15 : 0.10), in: RoundedRectangle(cornerRadius: 12, style: .continuous))
                    .overlay(RoundedRectangle(cornerRadius: 12, style: .continuous)
                        .stroke(OctoColor.accent.opacity(typing ? 0.6 : 0.1), lineWidth: typing ? 1.5 : 1))
                Button(action: connect) {
                    ZStack {
                        Text("Connect").opacity(checking ? 0 : 1)
                        if checking { ProgressView().controlSize(.small) }
                    }
                    .font(.octoBodySmall.weight(.semibold))
                }
                .buttonStyle(.glassProminent)
                .tint(OctoColor.accent)
                .disabled(token.isEmpty || checking)
            }
            .padding(.horizontal, 16)
            .padding(.vertical, 12)
            if let problem {
                Text(problem)
                    .font(.octoCaption)
                    .foregroundStyle(OctoColor.error)
                    .padding(.horizontal, 16)
                    .padding(.bottom, 12)
            }
        }
    }

    private func connect() {
        guard !checking, !token.isEmpty else { return }
        checking = true
        problem = nil
        Task {
            let check = await sync.connect(token)
            switch check {
            case .valid:
                problem = nil
                token = ""
            case .invalid: problem = "ListenBrainz did not accept that token. Copy it again from your settings page."
            case .unreachable: problem = "Couldn't reach ListenBrainz. Check the connection and try again."
            }
            checking = false
        }
    }
}
