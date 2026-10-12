import Foundation
import Testing
@testable import OctoKit

@Suite struct SettingsSummariesTests {
    let minute: Int64 = 60_000
    let now: Int64 = 1_758_000_000_000

    private func player(_ change: (inout PlayerPrefs) -> Void) -> PlayerPrefs {
        var prefs = PlayerPrefs()
        change(&prefs)
        return prefs
    }

    @Test func playback() {
        #expect(SettingsSummaries.playback(PlayerPrefs()) == "Gapless · Autoplay")
        #expect(SettingsSummaries.playback(player { $0.crossfade = true }) == "Crossfade 8 s · Autoplay")
        #expect(SettingsSummaries.playback(player {
            $0.crossfade = true
            $0.crossfadeSeconds = 4
            $0.speed = 1.25
            $0.autoplay = false
            $0.skipSilence = true
        }) == "Crossfade 4 s · 1.25x · Skip silence")
        // Never more than three parts.
        #expect(SettingsSummaries.playback(player {
            $0.speed = 2
            $0.skipSilence = true
        }) == "Gapless · 2x · Autoplay")
        // Normal speed with the pitch moved still says the speed.
        #expect(SettingsSummaries.playback(player { $0.keepPitch = false }) == "Gapless · 1x · Autoplay")
    }

    @Test func appearance() {
        #expect(SettingsSummaries.appearance(AmbientPrefs(), liveBackground: true) == "Subtle glow · Live background")
        var off = AmbientPrefs()
        off.strength = .off
        #expect(SettingsSummaries.appearance(off, liveBackground: false) == "No glow")
        var rich = AmbientPrefs()
        rich.strength = .rich
        #expect(SettingsSummaries.appearance(rich, liveBackground: false) == "Rich glow")
    }

    @Test func library() {
        let folders = [MusicFolder("Music", songs: 2_000, included: true), MusicFolder("Podcasts", songs: 40, included: false)]
        #expect(SettingsSummaries.library(.granted, songs: 2_357, folders: folders) == "2,357 songs · 1 folder left out")
        #expect(SettingsSummaries.library(.granted, songs: 1, folders: []) == "1 song")
        #expect(SettingsSummaries.library(.denied, songs: 0, folders: folders) == "Music on this phone not allowed yet")
        #expect(SettingsSummaries.library(.deniedForever, songs: 0, folders: []) == "Music on this phone not allowed yet")
        #expect(SettingsSummaries.phoneLine(.granted, songs: 2_357) == "2,357 songs on this phone")
        #expect(SettingsSummaries.phoneLine(.granted, songs: 1) == "1 song on this phone")
        #expect(SettingsSummaries.phoneLine(.notAsked, songs: 0) == "Allow access to the music on this phone")
    }

    @Test func howLongAgo() {
        #expect(SettingsSummaries.syncedAgo(now - 20_000, now: now) == "Synced just now")
        #expect(SettingsSummaries.syncedAgo(now - 5 * minute, now: now) == "Synced 5 min ago")
        #expect(SettingsSummaries.syncedAgo(now - 3 * 60 * minute, now: now) == "Synced 3 hr ago")
        #expect(SettingsSummaries.syncedAgo(now - 30 * 60 * minute, now: now) == "Synced yesterday")
        #expect(SettingsSummaries.syncedAgo(now - 4 * 24 * 60 * minute, now: now) == "Synced 4 days ago")
        // A clock that moved back is not "in the future".
        #expect(SettingsSummaries.timeAgo(now + minute, now: now) == "Just now")
    }

    @Test func server() {
        #expect(SettingsSummaries.serverStatus(syncing: true, place: .home, syncedAt: now, now: now) == "Syncing…")
        #expect(SettingsSummaries.serverStatus(syncing: false, place: .home, syncedAt: now - 5 * minute, now: now)
            == "Connected at home · Synced 5 min ago")
        #expect(SettingsSummaries.serverStatus(syncing: false, place: .away, syncedAt: nil, now: now) == "Connected away · Not synced yet")
        #expect(SettingsSummaries.serverStatus(syncing: false, place: nil, syncedAt: now, now: now) == "Synced just now")
    }

    @Test func streaming() {
        #expect(SettingsSummaries.streaming(StreamPrefs(), OfflinePrefs()) == "Wi-Fi Original · mobile Original · 2 GB cache")
        var offline = OfflinePrefs()
        offline.cacheSize = .off
        #expect(SettingsSummaries.streaming(StreamPrefs(wifi: .mp3(kbps: 320), mobile: .mp3(kbps: 128)), offline)
            == "Wi-Fi 320 kbps · mobile 128 kbps · no cache")
    }

    @Test func lyrics() {
        #expect(SettingsSummaries.lyrics(online: true, keepScreenOn: true) == "Found online · Screen stays on")
        #expect(SettingsSummaries.lyrics(online: false, keepScreenOn: false) == "From your music only")
    }

    @Test func scrobbling() {
        #expect(SettingsSummaries.scrobbling(ListenBrainzPrefs()) == "Off")
        #expect(SettingsSummaries.scrobbling(ListenBrainzPrefs(enabled: true)) == "Not connected yet")
        #expect(SettingsSummaries.scrobbling(ListenBrainzPrefs(enabled: true, user: "me", needsAttention: true)) == "Needs a new token")
        #expect(SettingsSummaries.scrobbling(ListenBrainzPrefs(enabled: true, user: "me")) == "ListenBrainz as me")
    }

    @Test func aboutAndBackup() {
        #expect(SettingsSummaries.about(version: "1.2") == "Version 1.2")
        #expect(SettingsSummaries.about(version: "1.2", updateReady: "1.3.0") == "Update ready: 1.3.0")
        #expect(SettingsSummaries.backup == "Settings, playlists, likes and favorites")
    }

    @Test func linesUseTheMiddleDotAndNoDashes() {
        let lines = [
            SettingsSummaries.playback(player {
                $0.crossfade = true
                $0.speed = 1.5
            }),
            SettingsSummaries.streaming(StreamPrefs(), OfflinePrefs()),
            SettingsSummaries.serverStatus(syncing: false, place: .home, syncedAt: now, now: now),
        ]
        for line in lines {
            #expect(line.contains(" · "), "\(line)")
            #expect(!line.contains("\u{2014}") && !line.contains("\u{2013}"), "\(line)")
        }
    }

    @Test func countsGroupThousands() {
        #expect(SettingsSummaries.grouped(0) == "0")
        #expect(SettingsSummaries.grouped(999) == "999")
        #expect(SettingsSummaries.grouped(1_234) == "1,234")
        #expect(SettingsSummaries.grouped(1_234_567) == "1,234,567")
        #expect(SettingsSummaries.grouped(1_234_567, locale: Locale(identifier: "de_DE")) == "1.234.567")
        #expect(SettingsSummaries.grouped(-1_234, locale: Locale(identifier: "en_US")) == "-1,234")
        #expect(SettingsSummaries.count(0, one: "song", many: "songs") == "0 songs")
    }

    @Test func sizesReadInTheirUnits() {
        #expect(SettingsWords.sizeLabel(0) == "0 KB")
        #expect(SettingsWords.sizeLabel(1) == "1 KB")
        #expect(SettingsWords.sizeLabel(1_400_000) == "1.3 MB")
        #expect(SettingsWords.sizeLabel(Int64(1.3 * Double(1 << 30))) == "1.3 GB")
    }

    @Test func fetchAheadWordsAndCounts() {
        #expect(SettingsWords.ahead(0) == "Off")
        #expect(SettingsWords.ahead(1) == "1 song")
        #expect(SettingsWords.ahead(5) == "5 songs")
        #expect(SettingsWords.aheadCounts(including: 3) == [0, 1, 2, 3, 5, 10])
        #expect(SettingsWords.aheadCounts(including: 7) == [0, 1, 2, 3, 5, 7, 10])
    }

    @Test func theSpeedRowSaysHowThePitchFollows() {
        #expect(SettingsWords.paceLabel(PlayerPrefs()) == "1x")
        #expect(SettingsWords.paceLabel(player { $0.speed = 1.25 }) == "1.25x, voices keep their pitch")
        #expect(SettingsWords.paceLabel(player {
            $0.speed = 0.75
            $0.keepPitch = false
            $0.pitchSemitones = -2
        }) == "0.75x, pitch follows the speed, shifted -2 st")
        #expect(SettingsWords.paceLabel(player { $0.pitchSemitones = 3 }) == "1x, shifted 3 st")
        #expect(SettingsWords.paceLabel(player { $0.keepPitch = false }) == "1x")
    }

    @Test func qualityLinesSayTheirSizes() {
        #expect(SettingsWords.downloadDetail(.mp3(kbps: 320)) == "About 10 MB for a 4 minute song")
        #expect(SettingsWords.downloadDetail(.mp3(kbps: 128)) == "About 4 MB for a 4 minute song")
        #expect(SettingsWords.streamDetail(.mp3(kbps: 320)) == "MP3, about 144 MB an hour")
        #expect(SettingsWords.streamDetail(.mp3(kbps: 256)) == "MP3, about 115 MB an hour")
        #expect(SettingsWords.streamDetail(.mp3(kbps: 192)) == "MP3, about 86 MB an hour")
        #expect(SettingsWords.streamDetail(.mp3(kbps: 128)) == "MP3, about 58 MB an hour")
        #expect(SettingsWords.streamDetail(.original) == nil)
    }

}
