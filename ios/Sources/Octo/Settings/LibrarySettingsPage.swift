import OctoKit
import SwiftUI

/// The music on this phone: access to it, how much there is, looking for new music, songs found
/// online, and which folders count.
struct LibrarySettingsPage: View {
    var highlight: String?
    @State private var settings = AppSettings.shared
    @State private var phone = PhoneMusic.shared

    var body: some View {
        let granted = phone.access == .granted
        SettingsPageFrame(title: SettingsPage.library.title, highlight: highlight) {
            SettingsGroup(title: "Music on this phone", icon: SettingsIcon.phone) {
                if granted {
                    InfoRow(SettingsIndex.phoneAccess, value: "Allowed")
                } else {
                    ActionRow(SettingsIndex.phoneAccess, helper: "Not allowed", trailing: phone.access.buttonLabel) { phone.requestAccess() }
                }
                InfoRow(SettingsIndex.phoneSongs, value: SettingsSummaries.grouped(phone.songCount))
                ActionRow(SettingsIndex.rescan, helper: phone.scanning ? "Looking for music…" : nil, chevron: false, busy: phone.scanning,
                          enabled: granted) {
                    Task { await phone.rescan() }
                }
            }
            SettingsGroup(title: "Songs found online", icon: SettingsIcon.addToLibrary) {
                ToggleRow(SettingsIndex.libraryOnly, isOn: settings.player.libraryOnly, helper: LibraryOnlyWords.help,
                          onChange: settings.setLibraryOnly)
            }
            if !phone.folders.isEmpty {
                SettingsGroup(title: SettingsIndex.musicFolders.title, icon: SettingsIcon.folder) {
                    NoteRow("Switch a folder off to leave it out.", entry: SettingsIndex.musicFolders)
                    ForEach(phone.folders, id: \.name) { folder in
                        ToggleRow(nil, title: folder.name.isEmpty ? "Phone storage" : folder.name,
                                  isOn: !settings.excludedFolders.contains(folder.name),
                                  helper: "\(SettingsSummaries.grouped(folder.songs)) songs") { on in
                            settings.setFolderIncluded(folder.name, on)
                            Task { await phone.rescan() }
                        }
                    }
                }
            }
        }
    }
}
