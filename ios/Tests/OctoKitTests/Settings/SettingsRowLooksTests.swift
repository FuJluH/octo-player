import Foundation
import Testing
@testable import OctoKit

@Suite struct SettingsRowLooksTests {
    @Test func theCurveRowSaysWhyItCannotBeChosenAndWhichSwitchFreesIt() {
        let smart = curveRowLook(.linear, smartTransitions: true)
        #expect(!smart.choosable)
        #expect(smart.value == smartCurveValue)
        // The reason names the switch by the title it has on the page.
        #expect(smart.helper.contains("Turn off \(SettingsIndex.smartTransitions.title)"))
        #expect(!smart.helper.contains("Automix"))
        #expect(smart.helper == "Smart transitions picks the curve for each blend. Turn off Smart transitions, just below, to choose one.")
        #expect(curveRowLook(.linear, smartTransitions: false) == RowLook(choosable: true, value: "Linear", helper: FadeCurve.linear.detail))
    }

    @Test func discoveryShowsTheChoiceAndWhatItMeans() {
        #expect(discoveryRowLook(.lots, libraryOnly: false, where: "Library") ==
            RowLook(choosable: true, value: RadioDiscovery.lots.label, helper: RadioDiscovery.lots.detail))
    }

    @Test func libraryOnlyTakesDiscoveryOverAndSaysWhereToTurnItOff() {
        let look = discoveryRowLook(.lots, libraryOnly: true, where: "Library")
        #expect(!look.choosable)
        #expect(look.value == RadioDiscovery.libraryOnly.label)
        #expect(look.helper.hasPrefix("\(LibraryOnlyWords.setting) is on in Library"))
        #expect(look.helper.hasSuffix("Turn it off there to choose."))
    }

    @Test func radioHasASongRadioPartAndALiveRadioPart() {
        let radio = SettingsIndex.all.filter { $0.page == .radio }
        #expect(radio.map(\.title) == ["Discovery", "Adventure", "Artist variety", "Favorites more often", "Find stations near you",
                                       "Stations on your server"])
        #expect(radio.prefix(4).allSatisfy { $0.section == RadioWords.songRadio })
        #expect(radio.suffix(2).allSatisfy { $0.section == RadioWords.liveRadio })
        #expect(SettingsPage.radio.title == "Radio")
        #expect(SettingsPage.allCases.firstIndex(of: .radio) == SettingsPage.allCases.firstIndex(of: .sound)! + 1)
        #expect(!SettingsIndex.all.contains { $0.page == .playback && $0.keywords.contains("song radio") })
    }

    @Test func searchFindsBothPartsOfRadio() {
        let found = searchSettings("live radio").map(\.id)
        #expect(found.contains("live_radio_near"))
        #expect(found.contains("radio_stations"))
        #expect(searchSettings("song radio").map(\.id).contains("radio_discovery"))
        #expect(searchSettings("near me").first?.id == "live_radio_near")
        #expect(searchSettings("accent").first?.id == "accent_color")
        #expect(searchSettings("glass").first?.id == "accent_glass")
        #expect(searchSettings("colour").map(\.id).contains("accent_color"))
    }

    @Test func theRadioLineSaysHowSongRadioIsTuned() {
        var prefs = PlayerPrefs()
        #expect(SettingsSummaries.radio(prefs) == "Song radio \(RadioDiscovery.balanced.label.lowercased()) · Live radio")
        prefs.libraryOnly = true
        #expect(SettingsSummaries.radio(prefs) == "Song radio from your library · Live radio")
    }

    @Test func noLongDashesOrBritishSpellingInTheNewWords() {
        let words = [smartPicksTheCurve, smartCurveValue, RadioWords.songRadioAbout, RadioWords.liveRadioAbout, RadioWords.findNearHelp,
                     RadioWords.stationsHelp, RadioWords.stationsSignedOut, RadioWords.stationsNotAdmin, GlassTintWords.help,
                     GlassTintWords.same] + AccentChoice.allCases.map(\.help)
        for text in words {
            #expect(!text.contains("\u{2014}") && !text.contains("\u{2013}"), "\(text)")
            for british in ["colour", "centre", "grey", "favourite"] { #expect(!text.lowercased().contains(british), "\(text)") }
        }
    }
}
