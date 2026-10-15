import OctoKit
import SwiftUI

/// Radio, in two parts that say which is which: song radio, which Octo mixes from your music when a
/// radio is started from a song, album or artist (and for Autoplay), and live radio, the stations
/// on the air.
struct RadioSettingsPage: View {
    var highlight: String?
    @Environment(Session.self) private var session
    @State private var settings = AppSettings.shared

    var body: some View {
        let prefs = settings.player
        SettingsPageFrame(title: SettingsPage.radio.title, highlight: highlight) {
            SettingsGroup(title: RadioWords.songRadio, footer: RadioWords.songRadioAbout) {
                let discovery = discoveryRowLook(prefs.radioDiscovery, libraryOnly: prefs.libraryOnly, where: "\(SettingsPage.library.title) settings")
                ChoiceRow(SettingsIndex.radioDiscovery, value: discovery.value, helper: discovery.helper, enabled: discovery.choosable,
                          question: SettingsQuestion(
                              SettingsIndex.radioDiscovery.title, RadioDiscovery.allCases, current: prefs.radioDiscovery,
                              answer: { SettingsAnswer($0.label, $0.detail) }, pick: settings.setRadioDiscovery))
                ChoiceRow(SettingsIndex.radioAdventure, value: prefs.radioAdventure.label, helper: prefs.radioAdventure.detail,
                          question: SettingsQuestion(
                              SettingsIndex.radioAdventure.title, RadioAdventure.allCases, current: prefs.radioAdventure,
                              answer: { SettingsAnswer($0.label, $0.detail) }, pick: settings.setRadioAdventure))
                ChoiceRow(SettingsIndex.radioVariety, value: prefs.radioVariety.label, helper: prefs.radioVariety.detail,
                          question: SettingsQuestion(
                              SettingsIndex.radioVariety.title, RadioVariety.allCases, current: prefs.radioVariety,
                              answer: { SettingsAnswer($0.label, $0.detail) }, pick: settings.setRadioVariety))
                ToggleRow(SettingsIndex.radioFavorites, isOn: prefs.radioFavorites, helper: RadioWords.favoritesHelp,
                          onChange: settings.setRadioFavorites)
            }
            SettingsGroup(title: RadioWords.liveRadio, footer: RadioWords.liveRadioAbout) {
                LinkRow(SettingsIndex.liveRadioNear, helper: RadioWords.findNearHelp, to: Route.liveRadioNear)
                if session.client != nil {
                    LinkRow(SettingsIndex.radioStations, helper: RadioWords.stationsHelp, to: AccountRoute.radioStations)
                } else {
                    ActionRow(SettingsIndex.radioStations, helper: RadioWords.stationsSignedOut, enabled: false) {}
                }
            }
        }
    }
}
