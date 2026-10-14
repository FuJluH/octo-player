package app.winters.octo.backup

import app.winters.octo.catalog.PinKind
import app.winters.octo.catalog.TrackEntity
import app.winters.octo.listening.SendPlays
import app.winters.octo.liveradio.KeptStations
import app.winters.octo.liveradio.LiveStation
import app.winters.octo.offline.CacheSize
import app.winters.octo.offline.OfflinePrefs
import app.winters.octo.playback.CopyPreference
import app.winters.octo.playback.FadeCurve
import app.winters.octo.playback.StreamQuality
import app.winters.octo.player.PlayerPrefs
import app.winters.octo.player.StreamPrefs
import app.winters.octo.playlists.BYTE_ORDER_MARK
import app.winters.octo.sound.Crossfeed
import app.winters.octo.sound.CrossfeedPreset
import app.winters.octo.sound.EqMode
import app.winters.octo.sound.SoundSettings
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class BackupTest {
    private fun track(id: String, title: String, artist: String, album: String = "Album", ms: Long = 200_000, relink: String = "") = TrackEntity(
        id = id, sourceId = "device", nativeId = id, title = title, searchKey = title.lowercase(), sortKey = title.lowercase(),
        artist = artist, artistId = "a", album = album, albumId = "al", trackNo = null, discNo = null, year = null,
        durationMs = ms, addedAt = 0, mimeType = null, sizeBytes = null, artwork = null, uri = null, relinkKey = relink,
    )

    private val full = Backup(
        createdAt = 1_758_000_000_000,
        player = PlayerPrefs(crossfade = true, crossfadeSeconds = 4, crossfadeCurve = FadeCurve.SCurve, speed = 1.25f, keepPitch = false, skipSilence = true, resumeBluetooth = true),
        streaming = StreamPrefs(CopyPreference.BestQuality, StreamQuality.Kbps320, StreamQuality.Kbps128),
        sound = SoundBackup(
            perOutput = true,
            profiles = mapOf(
                "all" to SoundSettings(),
                "bluetooth:AA:BB" to SoundSettings(eqEnabled = true, mode = EqMode.Parametric, preampDb = -3f, crossfeed = Crossfeed(on = true, preset = CrossfeedPreset.Custom, cutHz = 900, feedDb = 8f)),
            ),
        ),
        presets = listOf(PresetBackup("Mine", List(10) { it.toFloat() })),
        library = LibraryBackup(excludedFolders = listOf("Podcasts"), syncQueue = false, newPlaylistsOnServer = true),
        server = ServerBackup("https://music.example.com", "brandon"),
        playlists = listOf(PlaylistBackup("Road trip", listOf(SongKey("k1", "Nightcall", "Kavinsky", "OutRun", 258_000)))),
        likes = listOf(SongKey("k1", "Nightcall", "Kavinsky", "OutRun")),
        ratings = listOf(RatedSong(SongKey("k2", "Genesis", "Justice", "Cross"), 5)),
    )

    @Test
    fun aBackupReadsBackTheSame() {
        val text = encodeBackup(full)
        assertEquals(BackupRead.Read(full), decodeBackup(text))
        assertTrue(text.contains("\"version\": 1"))
        assertTrue(text.contains("\"kind\": \"octo-settings\""))
    }

    @Test
    fun everyPlayerSettingIsWritten() {
        val text = encodeBackup(Backup(player = PlayerPrefs()))
        listOf(
            "liveBackground", "crossfade", "crossfadeSeconds", "lyricsOnline", "speed", "keepPitch", "pitchSemitones",
            "skipSilence", "resumeWired", "resumeBluetooth", "resumeAlways", "smartTransitions", "filterSweeps", "matchTempo", "crossfadeCurve",
        ).forEach { assertTrue("$it is missing", text.contains("\"$it\"")) }
    }

    @Test
    fun keptLiveStationsReadBackTheSame() {
        val kept = KeptStations()
            .keep(LiveStation("u1", "KEXP", "https://kexp.example/live.aac", favicon = "https://kexp.example/icon.png", codec = "AAC", bitrate = 128, state = "Washington", countryCode = "US", tags = listOf("indie")))
            .keep(LiveStation("u2", "FIP", "https://fip.example/hls.m3u8", hls = true, country = "France"))
        val backup = Backup(keptStations = kept.stations)
        val read = decodeBackup(encodeBackup(backup)) as BackupRead.Read
        assertEquals(kept.stations, read.backup.keptStations)
        assertTrue(describeBackup(backup).contains("2 kept live radio stations"))
        // A backup made before stations were kept has none.
        assertTrue((decodeBackup("{\"kind\": \"octo-settings\"}") as BackupRead.Read).backup.keptStations.isEmpty())
    }

    @Test
    fun anUnknownCrossfadeCurveReadsAsTheDefault() {
        val text = encodeBackup(Backup(player = PlayerPrefs(crossfadeCurve = FadeCurve.Linear))).replace("\"Linear\"", "\"Bungee\"")
        val read = decodeBackup(text) as BackupRead.Read
        assertEquals(FadeCurve.EqualPower, read.backup.player?.crossfadeCurve)
    }

    @Test
    fun neverHoldsSecrets() {
        val text = encodeBackup(full).lowercase()
        listOf("password", "token", "apikey", "api_key", "secret", "header", "certificate", "alias").forEach {
            assertFalse("$it is in the backup", text.contains(it))
        }
    }

    @Test
    fun aServerAddressLosesAnythingSecretWrittenIntoIt() {
        assertEquals("https://music.example.com", plainAddress("https://me:hunter2@music.example.com/?t=abc&s=salt"))
        assertEquals("http://10.0.0.5:4533/music", plainAddress("http://10.0.0.5:4533/music/"))
        assertEquals("music.example.com", plainAddress("music.example.com?u=me&p=x"))
    }

    @Test
    fun otherFilesAreRefused() {
        assertEquals(BackupRead.NotABackup, decodeBackup("not json"))
        assertEquals(BackupRead.NotABackup, decodeBackup("{\"kind\": \"something-else\", \"version\": 1}"))
        assertEquals(BackupRead.TooNew, decodeBackup("{\"kind\": \"octo-settings\", \"version\": 2}"))
    }

    @Test
    fun anOlderOrSmallerBackupStillReads() {
        val read = decodeBackup(BYTE_ORDER_MARK + "{\"kind\": \"octo-settings\", \"version\": 1, \"player\": {\"crossfade\": true}, \"extra\": 5}")
        val backup = (read as BackupRead.Read).backup
        assertEquals(PlayerPrefs(crossfade = true), backup.player)
        assertEquals(null, backup.sound)
        assertTrue(backup.playlists.isEmpty())
    }

    @Test
    fun anUnknownChoiceFallsBackToItsDefault() {
        val read = decodeBackup("{\"kind\": \"octo-settings\", \"streaming\": {\"copies\": \"Nonsense\", \"wifi\": \"Kbps256\"}}")
        val streaming = (read as BackupRead.Read).backup.streaming
        assertEquals(StreamPrefs(wifi = StreamQuality.Kbps256), streaming)
    }

    @Test
    fun songsAreFoundByRelinkKeyFirst() {
        val library = listOf(track("a", "Renamed", "Someone", relink = "k1"), track("b", "Nightcall", "Kavinsky", "OutRun"))
        assertEquals("a", SongFinder(library).find(SongKey("k1", "Nightcall", "Kavinsky", "OutRun")))
    }

    @Test
    fun thenByTitleArtistAndAlbum() {
        val library = listOf(
            track("live", "Nightcall", "Kavinsky", "Live", ms = 300_000),
            track("studio", "Nightcall", "Kavinsky", "OutRun", ms = 258_000),
        )
        val finder = SongFinder(library)
        assertEquals("studio", finder.find(SongKey("gone", "Nightcall", "Kavinsky", "OutRun")))
        // Another album: the same song by the same artist, nearest in length.
        assertEquals("studio", finder.find(SongKey("", "Nightcall", "Kavinsky", "Best Of", 259_000)))
        // Someone else's song of the same name is not it.
        assertEquals(null, finder.find(SongKey("", "Nightcall", "London Grammar", "If You Wait")))
        assertEquals(null, finder.find(SongKey("", "", "", "")))
    }

    @Test
    fun restorePlanMatchesAndCounts() {
        val library = listOf(track("n", "Nightcall", "Kavinsky", "OutRun", relink = "k1"), track("g", "Genesis", "Justice", "Cross"))
        val backup = full.copy(
            playlists = listOf(
                PlaylistBackup("Road trip", listOf(SongKey("k1"), SongKey("", "Genesis", "Justice", "Cross"), SongKey("x", "Gone", "Nobody"))),
                PlaylistBackup("Old one", listOf(SongKey("k1"))),
            ),
            likes = listOf(SongKey("k1"), SongKey("k1"), SongKey("missing", "Missing", "Nobody")),
            ratings = listOf(RatedSong(SongKey("", "Genesis", "Justice", "Cross"), 4), RatedSong(SongKey("k1"), 9)),
        )
        val plan = planRestore(backup, library, existingPlaylists = listOf(" old ONE "))
        assertEquals(listOf(PlaylistPlan("Road trip", listOf("n", "g"), 3)), plan.playlists)
        assertEquals(listOf("Old one"), plan.skippedPlaylists)
        assertEquals(listOf("n"), plan.likes)
        assertEquals(3, plan.likesTotal)
        // A rating outside 1 to 5 is dropped.
        assertEquals(mapOf("g" to 4), plan.ratings)
        assertEquals(2, plan.ratingsTotal)
        assertEquals(
            listOf(
                "Playlists: 2 of 3 songs found",
                "Already here, left as they are: Old one",
                "Likes: 1 of 3 found",
                "Ratings: 1 of 2 found",
            ),
            describePlan(plan),
        )
    }

    @Test
    fun describesWhatABackupHolds() {
        assertEquals(
            listOf(
                "Settings: player, streaming, sound, library",
                "1 output with its own sound",
                "1 equalizer preset",
                "1 playlist, 1 song",
                "1 liked song",
                "1 rating",
                "Server: https://music.example.com as brandon. Sign in again to use it.",
            ),
            describeBackup(full),
        )
    }

    private val withFavourites = full.copy(
        favouriteAlbums = listOf(HeldKey("outrun kavinsky", "OutRun", "Kavinsky"), HeldKey("gone", "Cross", "Justice")),
        favouriteArtists = listOf(HeldKey("kavinsky", "Kavinsky")),
        pins = listOf(
            PinBackup("album", HeldKey("outrun kavinsky", "OutRun", "Kavinsky")),
            PinBackup("playlist", HeldKey(name = "Road trip")),
            PinBackup("artist", HeldKey("", "Justice")),
            PinBackup("something-new", HeldKey("x")),
        ),
        lyrics = LyricsBackup(keepScreenOn = false, offsets = listOf(LyricsOffsetBackup(SongKey("k1", "Nightcall", "Kavinsky", "OutRun"), 750))),
    )

    private val albums = listOf(
        Named("al-outrun", "outrun kavinsky", "OutRun", "Kavinsky"),
        Named("al-cross", "cross justice", "Cross", "Justice"),
    )
    private val artists = listOf(Named("ar-kavinsky", "kavinsky", "Kavinsky"), Named("ar-justice", "justice", "Justice"))

    @Test
    fun favouritesPinsAndLyricsReadBackTheSame() {
        val text = encodeBackup(withFavourites)
        assertEquals(BackupRead.Read(withFavourites), decodeBackup(text))
        // An app from before favourites reads the rest and leaves them be.
        val older = decodeBackup("{\"kind\": \"octo-settings\", \"version\": 1}") as BackupRead.Read
        assertTrue(older.backup.favouriteAlbums.isEmpty() && older.backup.pins.isEmpty())
        assertEquals(null, older.backup.lyrics)
    }

    @Test
    fun albumsAndArtistsAreFoundByRelinkKeyThenByName() {
        val finder = NameFinder(albums + Named("al-other", "renamed", "Renamed", "Someone"))
        assertEquals("al-outrun", finder.find(HeldKey("outrun kavinsky", "Something else")))
        // The key is gone: the same name by the same artist, punctuation aside.
        assertEquals("al-cross", finder.find(HeldKey("old key", "Cross!", "JUSTICE")))
        assertEquals(null, finder.find(HeldKey("old key", "Cross", "Someone else")))
        assertEquals(null, finder.find(HeldKey("")))
        // Two with the same key: the first by id, every time.
        val twins = NameFinder(listOf(Named("b", "same", "Same"), Named("a", "same", "Same")))
        assertEquals("a", twins.find(HeldKey("same")))
    }

    @Test
    fun restorePlanFindsFavouritesPinsAndLyrics() {
        val library = listOf(track("n", "Nightcall", "Kavinsky", "OutRun", relink = "k1"))
        val plan = planRestore(withFavourites, library, existingPlaylists = emptyList(), albums = albums, artists = artists)
        assertEquals(listOf("al-outrun", "al-cross"), plan.favouriteAlbums)
        assertEquals(2, plan.favouriteAlbumsTotal)
        assertEquals(listOf("ar-kavinsky"), plan.favouriteArtists)
        // The playlist pin is found by the playlist the restore makes; a pin
        // of a kind this app does not know is left out.
        assertEquals(
            listOf(PinPlan(PinKind.Album, "al-outrun"), PinPlan(PinKind.Playlist, "Road trip"), PinPlan(PinKind.Artist, "ar-justice")),
            plan.pins,
        )
        assertEquals(4, plan.pinsTotal)
        assertEquals(mapOf("n" to 750L), plan.lyricsOffsets)
        assertEquals(
            listOf(
                "Playlists: 1 of 1 song found",
                "Likes: 1 of 1 found",
                "Ratings: 0 of 1 found",
                "Favorite albums: 2 of 2 found",
                "Favorite artists: 1 of 1 found",
                "Pins: 3 of 4 found",
                "Lyrics timing: 1 of 1 songs found",
            ),
            describePlan(plan),
        )
    }

    @Test
    fun aPlaylistPinNeedsItsPlaylist() {
        val backup = withFavourites.copy(playlists = emptyList())
        val none = planRestore(backup, emptyList(), existingPlaylists = emptyList(), albums = albums, artists = artists)
        assertTrue(none.pins.none { it.kind == PinKind.Playlist })
        val here = planRestore(backup, emptyList(), existingPlaylists = listOf("road TRIP"), albums = albums, artists = artists)
        assertTrue(PinPlan(PinKind.Playlist, "Road trip") in here.pins)
    }

    @Test
    fun eachOutputsLyricsTimingGoesThroughTheBackupAndBack() {
        val backup = Backup(
            lyrics = LyricsBackup(
                offsets = listOf(LyricsOffsetBackup(SongKey("k1", "Nightcall", "Kavinsky", "OutRun"), 750)),
                outputOffsets = mapOf("bluetooth:AA:BB:CC:DD:EE:FF" to -150L, "speaker" to 50L),
            ),
        )
        val text = encodeBackup(backup)
        assertEquals(BackupRead.Read(backup), decodeBackup(text))
        assertTrue(text.contains("\"version\": 1"))
        assertTrue("Lyrics timing for 2 sound outputs" in describeBackup(backup))
        // A backup from before output timing reads with none, and says nothing of it.
        val older = decodeBackup(
            "{\"kind\": \"octo-settings\", \"version\": 1, \"lyrics\": {\"keepScreenOn\": false, \"offsets\": []}}",
        ) as BackupRead.Read
        assertEquals(emptyMap<String, Long>(), older.backup.lyrics?.outputOffsets)
        assertTrue(describeBackup(older.backup).none { "sound output" in it })
    }

    @Test
    fun describesFavouritesPinsAndLyrics() {
        val lines = describeBackup(withFavourites)
        assertEquals("Settings: player, streaming, sound, library, lyrics", lines.first())
        assertTrue("2 favorite albums" in lines)
        assertTrue("1 favorite artist" in lines)
        assertTrue("4 pins on Home" in lines)
        assertTrue("Lyrics timing for 1 song" in lines)
    }

    private val withEverything = full.copy(
        offline = OfflineBackup(
            cacheSize = CacheSize.Gb10,
            prefetchWifi = 5,
            prefetchMobile = 0,
            downloadQuality = StreamQuality.Kbps320,
            wifiOnly = false,
            streamOnWifi = true,
            keepLiked = true,
            keptPlaylists = listOf("Road trip", "Gone"),
        ),
        listenBrainz = ListenBrainzBackup(enabled = true, sendPlays = SendPlays.PhoneOnly, nowPlaying = false),
        sortOrders = mapOf("songs" to "RecentlyAdded:desc", "albums" to "Year:asc"),
    )

    @Test
    fun offlineScrobblingAndSortOrdersReadBackTheSame() {
        val text = encodeBackup(withEverything)
        assertEquals(BackupRead.Read(withEverything), decodeBackup(text))
        assertTrue(text.contains("\"version\": 1"))
    }

    @Test
    fun aBackupFromBeforeTheseSettingsLeavesThemAlone() {
        val older = (decodeBackup(encodeBackup(full)) as BackupRead.Read).backup
        assertEquals(null, older.offline)
        assertEquals(null, older.listenBrainz)
        assertTrue(older.sortOrders.isEmpty())
        // A part with only some fields gets the defaults for the rest.
        val partial = decodeBackup(
            "{\"kind\": \"octo-settings\", \"version\": 1, \"offline\": {\"keepLiked\": true, \"cacheSize\": \"Gb500\"}, " +
                "\"listenBrainz\": {\"sendPlays\": \"Sometimes\"}}",
        ) as BackupRead.Read
        assertEquals(OfflineBackup(keepLiked = true), partial.backup.offline)
        assertEquals(ListenBrainzBackup(), partial.backup.listenBrainz)
    }

    @Test
    fun offlineSettingsGoThroughTheBackupAndBack() {
        val prefs = OfflinePrefs(
            cacheSize = CacheSize.Off,
            prefetchWifi = 7,
            prefetchMobile = 2,
            downloadQuality = StreamQuality.Kbps128,
            wifiOnly = false,
            streamOnWifi = true,
            keepLiked = true,
            keptPlaylists = setOf("p1", "p2", "gone"),
        )
        // Kept playlists travel by name; one no longer here is left out.
        val saved = prefs.toBackup(mapOf("p1" to "Road trip", "p2" to "Gym"))
        assertEquals(listOf("Gym", "Road trip"), saved.keptPlaylists)
        assertEquals(prefs.copy(keptPlaylists = setOf("n1", "n2")), saved.toPrefs(setOf("n1", "n2")))
        // A new install's settings read back as a new install's settings.
        assertEquals(OfflinePrefs(), OfflinePrefs().toBackup(emptyMap()).toPrefs())
    }

    @Test
    fun neverHoldsTheListenBrainzConnection() {
        val text = encodeBackup(withEverything).lowercase()
        listOf("token", "user\"", "sealed", "attention").forEach { assertFalse("$it is in the backup", text.contains(it)) }
    }

    @Test
    fun keptPlaylistsAreFoundByName() {
        val plan = planRestore(withEverything, emptyList(), existingPlaylists = listOf(" old one "))
        // "Road trip" is made by the restore; "Gone" is nowhere.
        assertEquals(listOf("Road trip"), plan.keptPlaylists)
        assertEquals(2, plan.keptPlaylistsTotal)
        assertTrue("Kept downloaded: 1 of 2 playlists found" in describePlan(plan))
        val here = planRestore(withEverything.copy(playlists = emptyList()), emptyList(), existingPlaylists = listOf("GONE"))
        assertEquals(listOf("Gone"), here.keptPlaylists)
    }

    @Test
    fun describesOfflineScrobblingAndSortOrders() {
        val lines = describeBackup(withEverything)
        assertEquals("Settings: player, streaming, sound, library, cache and downloads, scrobbling, sort orders", lines.first())
        assertTrue("2 playlists kept downloaded" in lines)
        assertTrue("ListenBrainz: connect again to send plays." in lines)
        val off = describeBackup(withEverything.copy(listenBrainz = ListenBrainzBackup(enabled = false)))
        assertTrue(off.none { it.startsWith("ListenBrainz") })
    }

    @Test
    fun homeSectionsGoThroughTheBackupAndBack() {
        val backup = Backup(homeSections = "charts,-pinned,recentlyPlayed")
        val text = encodeBackup(backup)
        assertTrue(text.contains("\"homeSections\": \"charts,-pinned,recentlyPlayed\""))
        assertTrue("it comes before the sort orders", text.indexOf("\"homeSections\"") < text.indexOf("\"sortOrders\""))
        assertEquals(BackupRead.Read(backup), decodeBackup(text))
        assertEquals("Settings: home sections", describeBackup(backup).first())
    }

    @Test
    fun aBackupWithoutHomeSectionsLeavesThemAlone() {
        val text = encodeBackup(Backup())
        assertFalse(text.contains("homeSections"))
        val read = decodeBackup("{\"kind\": \"octo-settings\", \"homeSections\": null}") as BackupRead.Read
        assertEquals(null, read.backup.homeSections)
        assertEquals(BackupRead.NotABackup, decodeBackup("{\"kind\": \"octo-settings\", \"homeSections\": [\"charts\"]}"))
    }
}
