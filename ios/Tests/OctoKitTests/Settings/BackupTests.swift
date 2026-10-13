import Foundation
import Testing
@testable import OctoKit

@Suite struct BackupTests {
    private func track(_ id: String, _ title: String, _ artist: String, _ album: String = "Album", ms: Int64 = 200_000,
                       relink: String = "") -> BackupTrack {
        BackupTrack(id: id, relinkKey: relink, title: title, artist: artist, album: album, durationMs: ms)
    }

    private var full: Backup {
        var b = Backup()
        b.createdAt = 1_758_000_000_000
        var player = PlayerPrefs()
        player.crossfade = true
        player.crossfadeSeconds = 4
        player.speed = 1.25
        player.keepPitch = false
        player.skipSilence = true
        player.resumeBluetooth = true
        b.player = player
        b.streaming = StreamPrefs(copies: .bestQuality, wifi: .mp3(kbps: 320), mobile: .mp3(kbps: 128))
        var parametric = SoundSettings()
        parametric.eqEnabled = true
        parametric.mode = .parametric
        parametric.preampDb = -3
        b.sound = SoundBackup(perOutput: true, profiles: ["all": SoundSettings(), "bluetooth:AA:BB": parametric])
        b.presets = [PresetBackup("Mine", (0..<10).map(Double.init))]
        b.library = LibraryBackup(excludedFolders: ["Podcasts"], syncQueue: false, newPlaylistsOnServer: true)
        b.server = ServerBackup(address: "https://music.example.com", username: "brandon")
        b.playlists = [PlaylistBackup("Road trip", [SongKey(relinkKey: "k1", title: "Nightcall", artist: "Kavinsky", album: "OutRun", durationMs: 258_000)])]
        b.likes = [SongKey(relinkKey: "k1", title: "Nightcall", artist: "Kavinsky", album: "OutRun")]
        b.ratings = [RatedSong(SongKey(relinkKey: "k2", title: "Genesis", artist: "Justice", album: "Cross"), 5)]
        return b
    }

    @Test func aBackupReadsBackTheSame() {
        let text = BackupFile.encode(full)
        #expect(BackupFile.decode(text) == .read(full))
        #expect(text.contains("\"version\": 1"))
        #expect(text.contains("\"kind\": \"octo-settings\""))
        #expect(text.hasPrefix("{\n    \"kind\""))
    }

    @Test func everyPlayerSettingIsWritten() {
        var backup = Backup()
        backup.player = PlayerPrefs()
        let text = BackupFile.encode(backup)
        for key in ["liveBackground", "crossfade", "crossfadeSeconds", "lyricsOnline", "speed", "keepPitch", "pitchSemitones", "skipSilence",
                    "resumeWired", "resumeBluetooth", "resumeAlways", "smartTransitions", "filterSweeps", "matchTempo", "radioDiscovery", "crossfadeCurve",
                    "ambient", "background", "castRenderers", "castKeepPlaying", "libraryOnly", "reduceMotion"] {
            #expect(text.contains("\"\(key)\""), "\(key) is missing")
        }
        #expect(text.contains("\"contrast\": 1.3"))
        #expect(text.contains("\"speed\": 1.0"))
    }

    @Test func neverHoldsSecrets() {
        let text = BackupFile.encode(full).lowercased()
        for word in ["password", "token", "apikey", "api_key", "secret", "header", "certificate", "alias"] {
            #expect(!text.contains(word), "\(word) is in the backup")
        }
    }

    @Test func aServerAddressLosesAnythingSecretWrittenIntoIt() {
        #expect(BackupFile.plainAddress("https://me:hunter2@music.example.com/?t=abc&s=salt") == "https://music.example.com")
        #expect(BackupFile.plainAddress("http://10.0.0.5:4533/music/") == "http://10.0.0.5:4533/music")
        #expect(BackupFile.plainAddress("music.example.com?u=me&p=x") == "music.example.com")
    }

    @Test func otherFilesAreRefused() {
        #expect(BackupFile.decode("not json") == .notABackup)
        #expect(BackupFile.decode(#"{"kind": "something-else", "version": 1}"#) == .notABackup)
        #expect(BackupFile.decode(#"{"kind": "octo-settings", "version": 2}"#) == .tooNew)
        #expect(BackupFile.decode("[1, 2]") == .notABackup)
    }

    @Test func anOlderOrSmallerBackupStillReads() {
        guard case .read(let backup) = BackupFile.decode("\u{FEFF}" + #"{"kind": "octo-settings", "version": 1, "player": {"crossfade": true}, "extra": 5}"#)
        else { Issue.record("not read"); return }
        var expected = PlayerPrefs()
        expected.crossfade = true
        #expect(backup.player == expected)
        #expect(backup.sound == nil)
        #expect(backup.playlists.isEmpty)
        // No kind at all is still a backup.
        if case .read = BackupFile.decode(#"{"version": 1}"#) {} else { Issue.record("a file with no kind was refused") }
    }

    @Test func anUnknownChoiceFallsBackToItsDefault() {
        guard case .read(let backup) = BackupFile.decode(#"{"kind": "octo-settings", "streaming": {"copies": "Nonsense", "wifi": "Kbps256"}}"#)
        else { Issue.record("not read"); return }
        #expect(backup.streaming == StreamPrefs(wifi: .mp3(kbps: 256)))
    }

    @Test func songsAreFoundByRelinkKeyFirst() {
        let library = [track("a", "Renamed", "Someone", relink: "k1"), track("b", "Nightcall", "Kavinsky", "OutRun")]
        #expect(SongFinder(library).find(SongKey(relinkKey: "k1", title: "Nightcall", artist: "Kavinsky", album: "OutRun")) == "a")
    }

    @Test func thenByTitleArtistAndAlbum() {
        let library = [track("live", "Nightcall", "Kavinsky", "Live", ms: 300_000), track("studio", "Nightcall", "Kavinsky", "OutRun", ms: 258_000)]
        let finder = SongFinder(library)
        #expect(finder.find(SongKey(relinkKey: "gone", title: "Nightcall", artist: "Kavinsky", album: "OutRun")) == "studio")
        #expect(finder.find(SongKey(title: "Nightcall", artist: "Kavinsky", album: "Best Of", durationMs: 259_000)) == "studio")
        // Someone else's song of the same name is not it.
        #expect(finder.find(SongKey(title: "Nightcall", artist: "London Grammar", album: "If You Wait")) == nil)
        #expect(finder.find(SongKey()) == nil)
    }

    @Test func restorePlanMatchesAndCounts() {
        let library = [track("n", "Nightcall", "Kavinsky", "OutRun", relink: "k1"), track("g", "Genesis", "Justice", "Cross")]
        var backup = full
        backup.playlists = [
            PlaylistBackup("Road trip", [SongKey(relinkKey: "k1"), SongKey(title: "Genesis", artist: "Justice", album: "Cross"),
                                         SongKey(relinkKey: "x", title: "Gone", artist: "Nobody")]),
            PlaylistBackup("Old one", [SongKey(relinkKey: "k1")]),
        ]
        backup.likes = [SongKey(relinkKey: "k1"), SongKey(relinkKey: "k1"), SongKey(relinkKey: "missing", title: "Missing", artist: "Nobody")]
        backup.ratings = [RatedSong(SongKey(title: "Genesis", artist: "Justice", album: "Cross"), 4), RatedSong(SongKey(relinkKey: "k1"), 9)]
        let plan = BackupPlanner.plan(backup, library: library, existingPlaylists: [" old ONE "])
        #expect(plan.playlists == [PlaylistPlan(name: "Road trip", trackIds: ["n", "g"], total: 3)])
        #expect(plan.skippedPlaylists == ["Old one"])
        #expect(plan.likes == ["n"])
        #expect(plan.likesTotal == 3)
        #expect(plan.ratings == ["g": 4])
        #expect(plan.ratingsTotal == 2)
        #expect(BackupPlanner.describe(plan) == [
            "Playlists: 2 of 3 songs found",
            "Already here, left as they are: Old one",
            "Likes: 1 of 3 found",
            "Ratings: 1 of 2 found",
        ])
    }

    @Test func describesWhatABackupHolds() {
        #expect(BackupPlanner.describe(full) == [
            "Settings: player, streaming, sound, library",
            "1 output with its own sound",
            "1 equalizer preset",
            "1 playlist, 1 song",
            "1 liked song",
            "1 rating",
            "Server: https://music.example.com as brandon. Sign in again to use it.",
        ])
    }

    private var withFavorites: Backup {
        var b = full
        b.favoriteAlbums = [HeldKey(relinkKey: "outrun kavinsky", name: "OutRun", artist: "Kavinsky"), HeldKey(relinkKey: "gone", name: "Cross", artist: "Justice")]
        b.favoriteArtists = [HeldKey(relinkKey: "kavinsky", name: "Kavinsky")]
        b.pins = [
            PinBackup("album", HeldKey(relinkKey: "outrun kavinsky", name: "OutRun", artist: "Kavinsky")),
            PinBackup("playlist", HeldKey(name: "Road trip")),
            PinBackup("artist", HeldKey(name: "Justice")),
            PinBackup("something-new", HeldKey(relinkKey: "x")),
        ]
        b.lyrics = LyricsBackup(keepScreenOn: false, offsets: [LyricsOffsetBackup(SongKey(relinkKey: "k1", title: "Nightcall", artist: "Kavinsky", album: "OutRun"), 750)])
        return b
    }

    private let albums = [NamedItem(id: "al-outrun", relinkKey: "outrun kavinsky", name: "OutRun", artist: "Kavinsky"),
                          NamedItem(id: "al-cross", relinkKey: "cross justice", name: "Cross", artist: "Justice")]
    private let artists = [NamedItem(id: "ar-kavinsky", relinkKey: "kavinsky", name: "Kavinsky"), NamedItem(id: "ar-justice", relinkKey: "justice", name: "Justice")]

    @Test func favoritesPinsAndLyricsReadBackTheSame() {
        let text = BackupFile.encode(withFavorites)
        #expect(BackupFile.decode(text) == .read(withFavorites))
        #expect(text.contains("\"favouriteAlbums\""))
        guard case .read(let older) = BackupFile.decode(#"{"kind": "octo-settings", "version": 1}"#) else { Issue.record("not read"); return }
        #expect(older.favoriteAlbums.isEmpty && older.pins.isEmpty)
        #expect(older.lyrics == nil)
    }

    @Test func albumsAndArtistsAreFoundByRelinkKeyThenByName() {
        let finder = NameFinder(albums + [NamedItem(id: "al-other", relinkKey: "renamed", name: "Renamed", artist: "Someone")])
        #expect(finder.find(HeldKey(relinkKey: "outrun kavinsky", name: "Something else")) == "al-outrun")
        #expect(finder.find(HeldKey(relinkKey: "old key", name: "Cross!", artist: "JUSTICE")) == "al-cross")
        #expect(finder.find(HeldKey(relinkKey: "old key", name: "Cross", artist: "Someone else")) == nil)
        #expect(finder.find(HeldKey()) == nil)
        let twins = NameFinder([NamedItem(id: "b", relinkKey: "same", name: "Same"), NamedItem(id: "a", relinkKey: "same", name: "Same")])
        #expect(twins.find(HeldKey(relinkKey: "same")) == "a")
    }

    @Test func restorePlanFindsFavoritesPinsAndLyrics() {
        let library = [track("n", "Nightcall", "Kavinsky", "OutRun", relink: "k1")]
        let plan = BackupPlanner.plan(withFavorites, library: library, existingPlaylists: [], albums: albums, artists: artists)
        #expect(plan.favoriteAlbums == ["al-outrun", "al-cross"])
        #expect(plan.favoriteAlbumsTotal == 2)
        #expect(plan.favoriteArtists == ["ar-kavinsky"])
        #expect(plan.pins == [PinPlan(kind: .album, target: "al-outrun"), PinPlan(kind: .playlist, target: "Road trip"),
                              PinPlan(kind: .artist, target: "ar-justice")])
        #expect(plan.pinsTotal == 4)
        #expect(plan.lyricsOffsets == ["n": 750])
        #expect(BackupPlanner.describe(plan) == [
            "Playlists: 1 of 1 song found",
            "Likes: 1 of 1 found",
            "Ratings: 0 of 1 found",
            "Favorite albums: 2 of 2 found",
            "Favorite artists: 1 of 1 found",
            "Pins: 3 of 4 found",
            "Lyrics timing: 1 of 1 songs found",
        ])
    }

    @Test func aPlaylistPinNeedsItsPlaylist() {
        var backup = withFavorites
        backup.playlists = []
        let none = BackupPlanner.plan(backup, library: [], existingPlaylists: [], albums: albums, artists: artists)
        #expect(!none.pins.contains { $0.kind == .playlist })
        let here = BackupPlanner.plan(backup, library: [], existingPlaylists: ["road TRIP"], albums: albums, artists: artists)
        #expect(here.pins.contains(PinPlan(kind: .playlist, target: "Road trip")))
    }

    @Test func eachOutputsLyricsTimingGoesThroughTheBackupAndBack() {
        var backup = Backup()
        backup.lyrics = LyricsBackup(offsets: [LyricsOffsetBackup(SongKey(relinkKey: "k1", title: "Nightcall", artist: "Kavinsky", album: "OutRun"), 750)],
                                     outputOffsets: ["bluetooth:AA:BB:CC:DD:EE:FF": -150, "speaker": 50])
        let text = BackupFile.encode(backup)
        #expect(BackupFile.decode(text) == .read(backup))
        #expect(BackupPlanner.describe(backup).contains("Lyrics timing for 2 sound outputs"))
        guard case .read(let older) = BackupFile.decode(#"{"kind": "octo-settings", "version": 1, "lyrics": {"keepScreenOn": false, "offsets": []}}"#)
        else { Issue.record("not read"); return }
        #expect(older.lyrics?.outputOffsets == [:])
        #expect(!BackupPlanner.describe(older).contains { $0.contains("sound output") })
    }

    @Test func describesFavoritesPinsAndLyrics() {
        let lines = BackupPlanner.describe(withFavorites)
        #expect(lines.first == "Settings: player, streaming, sound, library, lyrics")
        #expect(lines.contains("2 favorite albums"))
        #expect(lines.contains("1 favorite artist"))
        #expect(lines.contains("4 pins on Home"))
        #expect(lines.contains("Lyrics timing for 1 song"))
    }

    private var withEverything: Backup {
        var b = full
        var offline = OfflinePrefs()
        offline.cacheSize = .gb10
        offline.prefetchWifi = 5
        offline.prefetchMobile = 0
        offline.downloadQuality = .mp3(kbps: 320)
        offline.wifiOnly = false
        offline.streamOnWifi = true
        offline.keepLiked = true
        offline.keptPlaylists = ["Gone", "Road trip"]
        b.offline = offline
        b.listenBrainz = ListenBrainzBackup(enabled: true, sendPlays: .phoneOnly, nowPlaying: false)
        b.sortOrders = ["songs": "RecentlyAdded:desc", "albums": "Year:asc"]
        return b
    }

    @Test func offlineScrobblingAndSortOrdersReadBackTheSame() {
        let text = BackupFile.encode(withEverything)
        #expect(BackupFile.decode(text) == .read(withEverything))
    }

    @Test func aBackupFromBeforeTheseSettingsLeavesThemAlone() {
        guard case .read(let older) = BackupFile.decode(BackupFile.encode(full)) else { Issue.record("not read"); return }
        #expect(older.offline == nil)
        #expect(older.listenBrainz == nil)
        #expect(older.sortOrders.isEmpty)
        guard case .read(let partial) = BackupFile.decode(
            #"{"kind": "octo-settings", "version": 1, "offline": {"keepLiked": true, "cacheSize": "Gb500"}, "listenBrainz": {"sendPlays": "Sometimes"}}"#)
        else { Issue.record("not read"); return }
        var expected = OfflinePrefs()
        expected.keepLiked = true
        #expect(partial.offline == expected)
        #expect(partial.listenBrainz == ListenBrainzBackup())
    }

    @Test func neverHoldsTheListenBrainzConnection() {
        let text = BackupFile.encode(withEverything).lowercased()
        for word in ["token", "user\"", "sealed", "attention"] { #expect(!text.contains(word), "\(word) is in the backup") }
    }

    @Test func keptPlaylistsAreFoundByName() {
        let plan = BackupPlanner.plan(withEverything, library: [], existingPlaylists: [" old one "])
        #expect(plan.keptPlaylists == ["Road trip"])
        #expect(plan.keptPlaylistsTotal == 2)
        #expect(BackupPlanner.describe(plan).contains("Kept downloaded: 1 of 2 playlists found"))
        var noPlaylists = withEverything
        noPlaylists.playlists = []
        #expect(BackupPlanner.plan(noPlaylists, library: [], existingPlaylists: ["GONE"]).keptPlaylists == ["Gone"])
    }

    @Test func describesOfflineScrobblingAndSortOrders() {
        let lines = BackupPlanner.describe(withEverything)
        #expect(lines.first == "Settings: player, streaming, sound, library, cache and downloads, scrobbling, sort orders")
        #expect(lines.contains("2 playlists kept downloaded"))
        #expect(lines.contains("ListenBrainz: connect again to send plays."))
        var off = withEverything
        off.listenBrainz = ListenBrainzBackup(enabled: false)
        #expect(!BackupPlanner.describe(off).contains { $0.hasPrefix("ListenBrainz") })
    }

    @Test func soundIsWrittenTheWayTheOtherAppsWriteIt() {
        var backup = Backup()
        var settings = SoundSettings()
        settings.mode = .parametric
        settings.filters = [EqFilter(type: .lowShelf, frequency: 100, gainDb: 3)]
        settings.replayGain = .album
        backup.sound = SoundBackup(perOutput: true, profiles: ["speaker": settings])
        let text = BackupFile.encode(backup)
        #expect(text.contains("\"mode\": \"Parametric\""))
        #expect(text.contains("\"type\": \"LowShelf\""))
        #expect(text.contains("\"replayGain\": \"Album\""))
        #expect(!text.contains("\"id\""))
        guard case .read(let read) = BackupFile.decode(text), let back = read.sound?.profiles["speaker"] else { Issue.record("not read"); return }
        #expect(back.mode == .parametric)
        #expect(back.filters.first?.type == .lowShelf)
        #expect(back.filters.first?.gainDb == 3)
        #expect(back.replayGain == .album)
    }

    @Test func emptyListsAndMapsAreWrittenOnOneLine() {
        let text = BackupFile.encode(Backup())
        #expect(text.contains("\"presets\": []"))
        #expect(text.contains("\"likes\": []"))
        #expect(text.contains("\"sortOrders\": {}"))
        #expect(!text.contains("[\n"))
        #expect(OrderedJSON.object([("a", .array([])), ("b", .object([]))]).pretty() == "{\n    \"a\": [],\n    \"b\": {}\n}")
    }

    @Test func sortOrdersAreWrittenInTheListsOrder() {
        var backup = Backup()
        backup.sortOrders = ["favourites": "Name:asc", "albums": "Year:asc", "songs": "Title:desc", "liked": "DateLiked:desc"]
        let text = BackupFile.encode(backup)
        let places = ["\"songs\"", "\"liked\"", "\"albums\"", "\"favourites\""].map { text.range(of: $0)?.lowerBound }
        #expect(places.allSatisfy { $0 != nil })
        #expect(zip(places, places.dropFirst()).allSatisfy { a, b in a! < b! })
    }

    @Test func aFieldOfTheWrongKindRefusesTheWholeFile() {
        for text in [
            #"{"kind": "octo-settings", "likes": "x"}"#,
            #"{"kind": "octo-settings", "player": 5}"#,
            #"{"kind": "octo-settings", "player": {"crossfade": "yes"}}"#,
            #"{"kind": "octo-settings", "player": {"crossfadeSeconds": 4.5}}"#,
            #"{"kind": "octo-settings", "player": {"crossfadeSeconds": 3000000000}}"#,
            #"{"kind": "octo-settings", "streaming": {"wifi": 320}}"#,
            #"{"kind": "octo-settings", "likes": [{"title": 5}]}"#,
            #"{"kind": "octo-settings", "likes": [null]}"#,
            #"{"kind": "octo-settings", "ratings": [{"song": {}}]}"#,
            #"{"kind": "octo-settings", "playlists": [{"songs": []}]}"#,
            #"{"kind": "octo-settings", "pins": [{"kind": "album", "item": null}]}"#,
            #"{"kind": "octo-settings", "sortOrders": {"songs": 1}}"#,
            #"{"kind": "octo-settings", "sound": {"profiles": {"all": {"filters": [{"gainDb": 3}]}}}}"#,
            #"{"kind": "octo-settings", "lyrics": {"outputOffsets": {"speaker": "soon"}}}"#,
            #"{"kind": 5}"#,
            #"{"version": "one"}"#,
        ] {
            #expect(BackupFile.decode(text) == .notABackup, "\(text) was read")
        }
    }

    @Test func aNullTakesTheFieldsDefault() {
        guard case .read(let backup) = BackupFile.decode(
            #"{"kind": null, "version": null, "likes": null, "player": {"crossfade": null, "speed": null}, "lyrics": {"look": null, "offsets": null}}"#)
        else { Issue.record("not read"); return }
        #expect(backup.likes.isEmpty)
        #expect(backup.player == PlayerPrefs())
        #expect(backup.lyrics == LyricsBackup())
        guard case .read(let handMade) = BackupFile.decode(#"{"sound": {"profiles": {"all": {"preset": null}}}}"#)
        else { Issue.record("not read"); return }
        #expect(handMade.sound?.profiles["all"]?.preset == nil)
    }

    @Test func numbersWrittenInQuotesStillRead() {
        guard case .read(let backup) = BackupFile.decode(#"{"player": {"crossfadeSeconds": "4", "speed": "1.25"}}"#)
        else { Issue.record("not read"); return }
        #expect(backup.player?.crossfadeSeconds == 4)
        #expect(backup.player?.speed == 1.25)
        #expect(BackupFile.decode(#"{"kind": "octo-settings", "version": "2"}"#) == .tooNew)
    }

    @Test func aFieldWrittenTwiceKeepsItsLastValue() {
        guard case .read(let backup) = BackupFile.decode(#"{"player": {"crossfade": true, "crossfade": false}}"#)
        else { Issue.record("not read"); return }
        #expect(backup.player?.crossfade == false)
    }

    @Test func unknownSoundAndLookChoicesFallBackToTheirDefaults() {
        let text = #"""
            {"sound": {"perOutput": true, "profiles": {"all": {"eqEnabled": true, "mode": "Wavy", "replayGain": "Loud",
              "filters": [{"type": "Notch", "frequency": 100, "gainDb": 2}]}}},
             "lyrics": {"look": {"style": "Bouncy", "glow": 150}}}
            """#
        guard case .read(let backup) = BackupFile.decode(text), let sound = backup.sound?.profiles["all"]
        else { Issue.record("not read"); return }
        #expect(sound.eqEnabled)
        #expect(sound.mode == .graphic)
        #expect(sound.replayGain == .off)
        #expect(sound.filters.first?.type == .peak)
        #expect(sound.filters.first?.gainDb == 2)
        #expect(backup.lyrics?.look?.style == .flowing)
        #expect(backup.lyrics?.look?.glow == 150)
    }

    @Test func bytesThatAreNotUTF8StillRead() {
        let bytes: [UInt8] = [0xEF, 0xBB, 0xBF] + Array(#"{"kind": "octo-settings", "playlists": [{"name": "Caf"#.utf8) + [0xE9]
            + Array(#""}]}"#.utf8)
        guard case .read(let backup) = BackupFile.decode(Data(bytes)) else { Issue.record("not read"); return }
        #expect(backup.playlists.map(\.name) == ["Caf\u{FFFD}"])
    }

    @Test func onlyStrictJSONReads() {
        for text in [#"{"kind": "octo-settings",}"#, #"{"kind": "octo-settings"} x"#, "{// note\n}", #"{'kind': 'octo-settings'}"#, ""] {
            #expect(BackupFile.decode(text) == .notABackup, "\(text) was read")
        }
        guard case .read(let backup) = BackupFile.decode(#"{"playlists": [{"name": "Café 🎵 \"live\"\n"}]}"#)
        else { Issue.record("not read"); return }
        #expect(backup.playlists.map(\.name) == ["Caf\u{E9} \u{1F3B5} \"live\"\n"])
    }

    @Test func theSuggestedNameCarriesTheDate() {
        var calendar = Calendar(identifier: .gregorian)
        calendar.timeZone = TimeZone(identifier: "UTC")!
        #expect(BackupFile.suggestedName(Date(timeIntervalSince1970: 1_791_676_800), calendar: calendar) == "Octo backup 2026-10-11.json")
    }

    @Test func homeSectionsGoThroughTheBackupAndBack() {
        var backup = Backup()
        backup.homeSections = "charts,-pinned,recentlyPlayed"
        let text = BackupFile.encode(backup)
        #expect(text.contains(#""homeSections": "charts,-pinned,recentlyPlayed""#))
        #expect(BackupFile.decode(text) == .read(backup))
        #expect(BackupPlanner.describe(backup).first == "Settings: home sections")
    }

    @Test func aBackupWithoutHomeSectionsLeavesThemAlone() {
        let text = BackupFile.encode(Backup())
        #expect(!text.contains("homeSections"))
        guard case .read(let read) = BackupFile.decode(#"{"kind": "octo-settings", "homeSections": null}"#) else { Issue.record("not read"); return }
        #expect(read.homeSections == nil)
        #expect(BackupFile.decode(#"{"kind": "octo-settings", "homeSections": ["charts"]}"#) == .notABackup)
    }
}
