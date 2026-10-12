import Foundation
import Testing
@testable import OctoKit

@Suite struct OfflineSettingsTest {
    @Test func aNewInstallGetsTheDefaults() {
        let prefs = OfflinePrefs()
        #expect(prefs.cacheSize == .gb2)
        #expect(prefs.prefetchWifi == 3 && prefs.prefetchMobile == 1)
        #expect(prefs.downloadQuality == .original)
        #expect(prefs.wifiOnly && !prefs.streamOnWifi && !prefs.keepLiked && prefs.keptPlaylists.isEmpty)
    }

    @Test func sizesAreBinaryGigabytesWithTheirLabels() {
        #expect(CacheSize.allCases.map(\.label) == ["Off", "1 GB", "2 GB", "5 GB", "10 GB"])
        #expect(CacheSize.allCases.map(\.bytes) == [0, 1_073_741_824, 2_147_483_648, 5_368_709_120, 10_737_418_240])
    }

    @Test func songsAheadStayWithinZeroToTen() {
        #expect(prefetchClamped(-1) == 0)
        #expect(prefetchClamped(11) == 10)
        #expect(prefetchClamped(4) == 4)
    }

    @Test func theSettingsSurviveBeingStored() throws {
        let prefs = OfflinePrefs(cacheSize: .gb10, prefetchWifi: 7, prefetchMobile: 0, downloadQuality: .mp3(kbps: 192),
                                 wifiOnly: false, streamOnWifi: true, keepLiked: true, keptPlaylists: ["b", "a"])
        let data = try JSONEncoder().encode(prefs)
        #expect(try JSONDecoder().decode(OfflinePrefs.self, from: data) == prefs)
        let text = try #require(String(data: data, encoding: .utf8))
        #expect(text.contains("\"downloadQuality\":\"Kbps192\""))
        #expect(text.contains("\"cacheSize\":\"Gb10\""))
    }

    @Test func missingOrUnknownValuesReadAsTheirDefaults() throws {
        let json = #"{"cacheSize":"Gb3","prefetchWifi":40,"downloadQuality":"Kbps999","keptPlaylists":["p1"]}"#
        let prefs = try JSONDecoder().decode(OfflinePrefs.self, from: Data(json.utf8))
        #expect(prefs == OfflinePrefs(prefetchWifi: 10, keptPlaylists: ["p1"]))
    }

    @Test func removeAllStopsEveryRuleAndABackupAddsItsPlaylists() {
        var prefs = OfflinePrefs(keepLiked: true, keptPlaylists: ["a"])
        prefs.setPlaylistKept("b", true)
        prefs.setPlaylistKept("a", false)
        #expect(prefs.keptPlaylists == ["b"])
        let restored = prefs.restoring(OfflinePrefs(cacheSize: .off, prefetchWifi: 12, keptPlaylists: ["c"]))
        #expect(restored.cacheSize == .off && restored.prefetchWifi == 10 && restored.keptPlaylists == ["b", "c"])
        prefs.clearRules()
        #expect(!prefs.keepLiked && prefs.keptPlaylists.isEmpty)
    }
}
