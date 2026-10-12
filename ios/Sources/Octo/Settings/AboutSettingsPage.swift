import OctoKit
import SwiftUI

/// Which Octo this is, what's new in it, and looking for a newer one.
struct AboutSettingsPage: View {
    var highlight: String?
    @Environment(\.openURL) private var openURL
    @State private var settings = AppSettings.shared
    @State private var updates = AppUpdates.shared
    @State private var navigator = SettingsNavigator.shared
    @State private var whatsNewOpen = false

    var body: some View {
        let state = updates.state
        SettingsPageFrame(title: SettingsPage.about.title, highlight: highlight) {
            SettingsGroup {
                InfoRow(SettingsIndex.version, value: Session.appVersion)
                if let ready = state.ready {
                    ActionRow(nil, title: "Update ready: \(ready.version)", helper: "Install it the way you put Octo on this iPhone.",
                              trailing: "Open", enabled: ready.page != nil) {
                        if let page = ready.page { openURL(page) }
                    }
                    let notes = ready.notes.trimmingCharacters(in: .whitespacesAndNewlines)
                    if !notes.isEmpty { NoteRow(notes, color: OctoColor.textSecondary) }
                }
                ActionRow(SettingsIndex.whatsNew) { whatsNewOpen = true }
            }
            SettingsGroup(title: "Updates", icon: SettingsIcon.sync) {
                if let off = state.off {
                    NoteRow(off)
                } else {
                    ToggleRow(SettingsIndex.checkUpdates, isOn: settings.checkUpdatesAutomatically, helper: "Every few hours.",
                              onChange: settings.setCheckUpdatesAutomatically)
                    ToggleRow(SettingsIndex.earlyVersions, isOn: settings.earlyVersions, helper: "Before they're finished. Can have rough edges.",
                              onChange: settings.setEarlyVersions)
                    ActionRow(SettingsIndex.checkNow, helper: state.line, chevron: false, busy: state.checking) { updates.checkNow() }
                }
            }
            credit
        }
        .whatsNewPanel(isPresented: $whatsNewOpen)
        .onChange(of: navigator.whatsNewOpen, initial: true) { _, open in
            if open {
                navigator.whatsNewOpen = false
                whatsNewOpen = true
            }
        }
    }

    /// One centered line: "Made by Winters with" and a small heart, read as one.
    private var credit: some View {
        HStack(spacing: 4) {
            Text("Made by Winters with").font(.octoCaption.italic()).foregroundStyle(OctoColor.textMuted)
            Image(systemName: SettingsIcon.liked).font(.system(size: 10)).frame(width: 12, height: 12).foregroundStyle(OctoColor.textMuted)
        }
        .frame(maxWidth: .infinity)
        .padding(.horizontal, 32)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Made by Winters with love")
    }
}
