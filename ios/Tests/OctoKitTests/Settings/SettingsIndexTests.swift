import Foundation
import Testing
@testable import OctoKit

/// The long dashes, which the app's words never use.
private let longDashes: [Character] = ["\u{2014}", "\u{2013}"]

@Suite struct SettingsIndexTests {
    private func titles(_ query: String, _ entries: [SettingEntry] = SettingsIndex.all) -> [String] {
        searchSettings(query, in: entries).map(\.title)
    }

    @Test func everySettingHasItsOwnIdAndATitle() {
        let ids = SettingsIndex.all.map(\.id)
        #expect(ids.count == Set(ids).count)
        #expect(SettingsIndex.all.allSatisfy { !$0.title.trimmingCharacters(in: .whitespaces).isEmpty })
        #expect(SettingsIndex.byId("crossfade") == SettingsIndex.crossfade)
    }

    @Test func everyPageHasSettings() {
        for page in SettingsPage.allCases {
            #expect(SettingsIndex.all.contains { $0.page == page }, "\(page) is empty")
        }
    }

    @Test func noLongDashesInWhatPeopleRead() {
        for entry in SettingsIndex.all {
            for text in [entry.title, entry.summary, entry.place] + entry.keywords {
                #expect(!text.contains { longDashes.contains($0) }, "\(text)")
            }
        }
    }

    @Test func nothingTypedFindsNothing() {
        #expect(titles("").isEmpty)
        #expect(titles("   ").isEmpty)
        #expect(titles("-- ?").isEmpty)
    }

    @Test func theTitleComesFirst() {
        #expect(Array(titles("crossfade").prefix(2)) == ["Crossfade", "Crossfade curve"])
        #expect(titles("CROSS").first == "Crossfade")
    }

    @Test func otherWordsFindASetting() {
        #expect(titles("gapless").first == "Crossfade")
        #expect(titles("semitones").first == "Speed")
        #expect(titles("tempo").contains("Speed"))
        #expect(titles("replaygain").contains("Loudness"))
    }

    @Test func punctuationAndAccentsDoNotMatter() {
        #expect(titles("wifi").contains("Streaming on Wi-Fi"))
        #expect(titles("whats new").contains("What's new"))
        #expect(titles("Whät's").contains("What's new"))
    }

    @Test func everyWordMustBeFound() {
        // Both words in the title first, then "mobile" with the page's name.
        #expect(titles("streaming mobile") == ["Streaming on mobile data", "Fetch ahead on mobile data", "Download on Wi-Fi only"])
        #expect(titles("crossfade bluetooth").isEmpty)
    }

    @Test func shortWordsOnlyMatchTheStartOfAWord() {
        #expect(titles("eq").first == "Equalizer")
        #expect(titles("ss").isEmpty)
    }

    @Test func aResultSaysWhereItLives() {
        #expect(SettingsIndex.ambientHome.place == "Appearance · Where it shows")
        #expect(SettingsIndex.lyricsOnline.place == "Lyrics")
        #expect(SettingsIndex.radioDiscovery.place == "Radio · Song radio")
        #expect(SettingsIndex.radioStations.place == "Radio · Live radio")
        #expect(SettingsIndex.checkUpdates.place == "About · Updates")
        #expect(SettingsIndex.musicFolders.place == "Library")
    }

    @Test func titlesRankAboveOtherWordsAboveTheSummary() {
        let entries = [
            SettingEntry("summary", .lyrics, "Other", "screen stuff"),
            SettingEntry("keyword", .lyrics, "Keep awake", "", ["screen"]),
            SettingEntry("inside", .lyrics, "Full screen mode"),
            SettingEntry("start", .lyrics, "Screen"),
            SettingEntry("none", .lyrics, "Nothing", "at all"),
        ]
        #expect(searchSettings("screen", in: entries).map(\.id) == ["start", "inside", "keyword", "summary"])
    }

    @Test func wordsCanBeSpreadOverTitleAndOtherWords() {
        let entries = [
            SettingEntry("spread", .playback, "Resume", "", ["bluetooth"]),
            SettingEntry("title", .playback, "Resume on bluetooth"),
        ]
        #expect(searchSettings("resume bluetooth", in: entries).map(\.id) == ["title", "spread"])
        // The page's name counts as another word; both rank the same, so they keep the order
        // they are written in.
        #expect(searchSettings("playback resume", in: entries).map(\.id) == ["spread", "title"])
    }

    @Test func theAudioQualityEntriesSitAmongStreamingInTheirOrder() {
        let ids = SettingsIndex.all.map(\.id)
        let wifi = ids.firstIndex(of: "stream_wifi")!
        let start = ids.firstIndex(of: "start_after")!
        let mobile = ids.firstIndex(of: "stream_mobile")!
        let cache = ids.firstIndex(of: "cache_size")!
        #expect(wifi < start && start < mobile && mobile < cache)
    }

    @Test func titlesUseUSSpelling() {
        #expect(SettingsIndex.ambient.title == "Ambient color from the artwork")
        #expect(SettingsIndex.all.allSatisfy { !$0.title.contains("colour") && !$0.title.contains("favourite") })
    }

    @Test func normalizingKeepsLettersDigitsAndSingleSpaces() {
        #expect(settingsNormalized("  Wi-Fi   Ön! 2 ") == "wifi on 2")
        #expect(settingsNormalized("What's  new") == "whats new")
    }

    @Test func theServerPagesRowsAreFound() {
        #expect(titles("password").contains("Change password"))
        #expect(searchSettings("version").contains(SettingsIndex.serverKind))
    }
}
