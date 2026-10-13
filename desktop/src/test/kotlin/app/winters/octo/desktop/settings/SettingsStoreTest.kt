package app.winters.octo.desktop.settings

import app.winters.octo.covers.PlaylistCoverStyle
import app.winters.octo.desktop.system.SystemPrefs
import app.winters.octo.sound.EqFilter
import app.winters.octo.sound.EqMode
import app.winters.octo.sound.FilterType
import app.winters.octo.sound.ReplayGainMode
import app.winters.octo.sound.SoundSettings
import app.winters.octo.subsonic.AuthMode
import app.winters.octo.update.InstallWhen
import app.winters.octo.update.UpdatePrefs
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Rule
import org.junit.Test
import app.winters.octo.desktop.listening.listeningFolder
import app.winters.octo.livelists.accountKey
import org.junit.rules.TemporaryFolder
import java.io.File

class SettingsStoreTest {
    @get:Rule val folder = TemporaryFolder()

    private fun file() = File(folder.root, "octo/${SettingsStore.FILE_NAME}")

    @Test
    fun everySettingSurvivesARestart() {
        val home = SavedServer("http://music.test/", "winters", AuthMode.LegacyPassword, "navidrome", "0.58.0", true, listOf("songLyrics:1"), id = "h1", label = "Home")
        val changed = AppSettings(
            window = WindowSpot(10f, 20f, 1400f, 900f, maximized = true),
            systemTitleBar = true,
            server = home,
            servers = listOf(home, SavedServer("https://work.test/", "brandon", id = "w1", label = "Work", signedOut = true)),
            activeServer = "h1",
            appearance = Appearance(ambientGlow = false, glowStrength = 0.8f, ambience = AmbienceStyle.Immersive, ambienceMotion = AmbienceMotion.Full),
            playback = PlaybackPrefs(volume = 0.3f, crossfadeSeconds = 6, outputDevice = "usb:dac", speed = 1.25f, keepPitch = false, pitchSemitones = -2),
            songSort = "Year:desc",
            sidePanel = "queue",
        )
        SettingsStore(file()).update { changed }
        assertEquals(changed, SettingsStore(file()).current)
    }

    // Every setting the Settings and Sound pages change, away from its
    // default, reads back the same.
    @Test
    fun everySettingOnTheSettingsAndSoundPagesSurvivesARestart() {
        val changed = AppSettings(
            systemTitleBar = true,
            appearance = Appearance(
                ambientGlow = true,
                glowStrength = 0.3f,
                calmMotion = true,
                wash = WashPrefs(moving = false, speed = 60, useBpm = false, brightnessCap = 35),
                ambience = AmbienceStyle.Immersive,
                ambienceMotion = AmbienceMotion.Still,
                textSize = 115,
                playlistCovers = PlaylistCoverStyle.Mosaic,
            ),
            playback = PlaybackPrefs(crossfadeSeconds = 4, speed = 0.75f, keepPitch = false, pitchSemitones = 3, autoplay = false),
            lyrics = LyricsPrefs(online = false),
            listening = ListeningPrefs(reportPlays = false, syncQueue = false),
            system = SystemPrefs(closeToTray = true, nowPlayingNotices = true, miniPlayerOpen = true),
            sound = SoundPrefs(
                perOutput = true,
                profiles = mapOf(
                    "usb:dac" to SoundSettings(
                        eqEnabled = true,
                        mode = EqMode.Parametric,
                        filters = listOf(EqFilter(FilterType.LowShelf, 90f, 3f, 0.7f)),
                        preset = null,
                        preampDb = -3f,
                        autoPreamp = false,
                        replayGain = ReplayGainMode.Smart,
                        replayGainPreampDb = 2f,
                        replayGainFallbackDb = -4f,
                        preventClipping = false,
                        limiter = false,
                        balance = -0.2f,
                        mono = true,
                    ),
                ),
                presets = listOf(SavedCurve("Mine", List(10) { it.toFloat() })),
            ),
            updates = UpdatePrefs(checkAutomatically = false, install = InstallWhen.OnQuit, earlyVersions = true),
        )
        SettingsStore(file()).update { changed }
        assertEquals(changed, SettingsStore(file()).current)
    }

    @Test
    fun aMissingFileStartsFromTheDefaults() {
        assertEquals(AppSettings(), SettingsStore(file()).current)
        assertFalse("nothing is written until something changes", file().exists())
    }

    @Test
    fun anUnreadableFileIsSetAsideNotDeleted() {
        file().parentFile.mkdirs()
        file().writeText("{ this is not json")
        val store = SettingsStore(file())
        assertEquals(AppSettings(), store.current)
        val aside = file().parentFile.listFiles().orEmpty().filter { it.name.startsWith("settings.unreadable-") }
        assertEquals(1, aside.size)
        assertEquals("{ this is not json", aside.single().readText())
    }

    @Test
    fun settingsFromANewerVersionStillRead() {
        file().parentFile.mkdirs()
        file().writeText("""{"sidePanel":"lyrics","somethingNew":{"a":1},"appearance":{"glowStrength":0.2,"futureKnob":true}}""")
        val read = SettingsStore(file()).current
        assertEquals("lyrics", read.sidePanel)
        assertEquals(0.2f, read.appearance.glowStrength)
        assertTrue(read.appearance.ambientGlow)
    }

    @Test
    fun noPasswordIsEverWritten() {
        SettingsStore(file()).update { it.copy(server = SavedServer("http://music.test/", "winters")) }
        val text = file().readText()
        assertFalse(text.contains("password", ignoreCase = true))
        assertFalse("no temporary file is left behind", File(file().parentFile, "settings.json.tmp").exists())
    }

    @Test
    fun theSettingsFolderFollowsEachSystem() {
        val env = mapOf("APPDATA" to "C:\\Users\\b\\AppData\\Roaming", "LOCALAPPDATA" to "C:\\Users\\b\\AppData\\Local")
        val windows = AppPlaces.forSystem(DesktopOs.Windows, env::get, "C:\\Users\\b")
        assertEquals(File("C:\\Users\\b\\AppData\\Roaming", "Octo"), windows.config)
        assertEquals(File(File("C:\\Users\\b\\AppData\\Local", "Octo"), "Cache"), windows.cache)
        val mac = AppPlaces.forSystem(DesktopOs.Mac, { null }, "/Users/b")
        assertEquals(File("/Users/b", "Library/Application Support/Octo"), mac.config)
        val linux = AppPlaces.forSystem(DesktopOs.Linux, { null }, "/home/b")
        assertEquals(File("/home/b/.config", "octo"), linux.config)
        assertEquals(File("/home/b/.cache", "octo"), linux.cache)
        val xdg = AppPlaces.forSystem(DesktopOs.Linux, mapOf("XDG_CONFIG_HOME" to "/x/conf")::get, "/home/b")
        assertEquals(File("/x/conf", "octo"), xdg.config)
        // OCTO_PROFILE_DIR puts everything in one folder of its own.
        val separate = AppPlaces.forSystem(DesktopOs.Windows, (env + ("OCTO_PROFILE_DIR" to "D:/octo-test"))::get, "C:/Users/b")
        assertEquals(File("D:/octo-test", "config"), separate.config)
        assertEquals(File("D:/octo-test", "cache"), separate.cache)
        assertTrue(separateProfile(mapOf("OCTO_PROFILE_DIR" to "D:/octo-test")::get))
        assertFalse(separateProfile(env::get))
    }

    @Test
    fun aDragIsOneWriteAndNothingWaitingIsLost() {
        val store = SettingsStore(file(), writeDelayMs = 60_000)
        repeat(60) { step -> store.update { it.copy(playback = it.playback.copy(volume = step / 100f)) } }
        // Kept in memory at once, not yet written.
        assertEquals(0.59f, store.current.playback.volume)
        assertFalse(file().exists())
        store.flush()
        assertEquals(0.59f, SettingsStore(file()).current.playback.volume)
    }

    @Test
    fun systemsAreToldApartByName() {
        assertEquals(DesktopOs.Windows, currentOs("Windows 11"))
        assertEquals(DesktopOs.Mac, currentOs("Mac OS X"))
        assertEquals(DesktopOs.Linux, currentOs("Linux"))
    }

    @Test
    fun theFrameIsKeptAndAnOldFileGetsItsDefaults() {
        file().apply { parentFile.mkdirs() }.writeText("""{"sidePanel":"info"}""")
        val old = SettingsStore(file(), 0).current
        assertEquals(240f, old.frame.sidebarWidth)
        assertTrue(old.frame.showTimeLeft)
        val store = SettingsStore(file(), 0)
        store.update { it.copy(frame = it.frame.copy(sidebarRail = true, panelWidth = 400f, pinnedPlaylists = listOf("p2", "p1"), foldedGroups = setOf("library"))) }
        val read = SettingsStore(file(), 0).current.frame
        assertTrue(read.sidebarRail)
        assertEquals(400f, read.panelWidth)
        assertEquals(listOf("p2", "p1"), read.pinnedPlaylists)
        assertEquals(setOf("library"), read.foldedGroups)
    }

    @Test
    fun theAmbienceIsKeptAndAnOldFileKeepsTheGlow() {
        // A file from before Immersive: the glow, as it was.
        file().apply { parentFile.mkdirs() }.writeText("""{"appearance":{"ambientGlow":true,"glowStrength":0.7}}""")
        val old = SettingsStore(file(), 0).current.appearance
        assertEquals(AmbienceStyle.Glow, old.ambience)
        assertEquals(AmbienceMotion.Gentle, old.ambienceMotion)
        assertEquals(0.7f, old.glowStrength)
        SettingsStore(file(), 0).update { it.copy(appearance = it.appearance.copy(ambience = AmbienceStyle.Immersive, ambienceMotion = AmbienceMotion.Still)) }
        val read = SettingsStore(file(), 0).current.appearance
        assertEquals(AmbienceStyle.Immersive, read.ambience)
        assertEquals(AmbienceMotion.Still, read.ambienceMotion)
        assertEquals(0.7f, read.glowStrength)
        // A choice a newer version added reads as the default.
        file().writeText("""{"appearance":{"ambience":"Aurora","ambienceMotion":"Wild"}}""")
        val newer = SettingsStore(file(), 0).current.appearance
        assertEquals(AmbienceStyle.Glow, newer.ambience)
        assertEquals(AmbienceMotion.Gentle, newer.ambienceMotion)
    }

    // Playlist covers are designed unless the listener picked the mosaics,
    // and a file from before the choice existed reads as designed.
    @Test
    fun playlistCoversKeepTheirChoice() {
        assertEquals(PlaylistCoverStyle.Designed, AppSettings().appearance.playlistCovers)
        SettingsStore(file()).update { it.copy(appearance = it.appearance.copy(playlistCovers = PlaylistCoverStyle.Mosaic)) }
        assertEquals(PlaylistCoverStyle.Mosaic, SettingsStore(file()).current.appearance.playlistCovers)
        file().writeText("""{"appearance":{"ambientGlow":false}}""")
        val old = SettingsStore(file()).current.appearance
        assertEquals(PlaylistCoverStyle.Designed, old.playlistCovers)
        assertFalse(old.ambientGlow)
    }

    // A settings file from before there could be several servers, as the
    // last such version wrote it.
    private val oneServerFile = """{"systemTitleBar":false,"server":{"address":"https://music.test/","username":"winters","authMode":"Token","serverType":"octo","serverVersion":"0.9.0","openSubsonic":true,"extensions":["songLyrics:1"],"home":null,"headerNames":["X-Token"],"rememberSignIn":true}}"""

    @Test
    fun theOneServerOfAnOlderFileBecomesAListOfOneStillInUse() {
        file().parentFile.mkdirs()
        file().writeText(oneServerFile)
        val read = SettingsStore(file()).current
        val kept = read.servers.single()
        assertEquals("the id is the folder older versions made", accountKey("winters", "https://music.test/"), kept.id)
        assertEquals(listOf("X-Token"), kept.headerNames)
        assertEquals(kept.id, read.activeServer)
        assertEquals("still signed in", kept, read.server)
        assertEquals("music.test", kept.name)
        assertEquals(listeningFolder(folder.root, "winters", "https://music.test/"), listeningFolder(folder.root, kept))
    }

    @Test
    fun theListIsWrittenOnceAnythingChanges() {
        file().parentFile.mkdirs()
        file().writeText(oneServerFile)
        SettingsStore(file()).update { it.copy(sidePanel = "queue") }
        val text = file().readText()
        assertTrue(text.contains("\"servers\""))
        assertTrue(text.contains("\"activeServer\": \"${accountKey("winters", "https://music.test/")}\""))
        // An older Octo still finds the server in use where it looks.
        assertTrue(text.contains("\"server\": {"))
    }

    @Test
    fun aServerAnOlderOctoSignedInToSinceBecomesTheOneInUse() {
        val home = SavedServer("https://home.test/", "winters", id = "h", label = "Home")
        val work = SavedServer("https://work.test/", "brandon", id = "w", label = "Work")
        SettingsStore(file()).update { it.copy(servers = listOf(home, work), activeServer = "h") }
        // An older Octo reads only `server`, and writes it back changed.
        val older = file().readText().replace(Regex("\"server\": \\{[^}]*\\}"),"\"server\": {\"address\": \"https://work.test/\", \"username\": \"brandon\"}")
        assertTrue(older != file().readText())
        file().writeText(older)
        val read = SettingsStore(file()).current
        assertEquals("w", read.activeServer)
        assertEquals(listOf("h", "w"), read.servers.map { it.id })
        assertEquals("its label is kept", "Work", read.servers[1].label)
    }

    @Test
    fun aServerAnOlderOctoSignedOutOfLeavesNoneInUse() {
        val home = SavedServer("https://home.test/", "winters", id = "h")
        SettingsStore(file()).update { it.copy(servers = listOf(home), activeServer = "h") }
        file().writeText(file().readText().replace(Regex("\"server\": \\{[^}]*\\}"), "\"server\": null"))
        val read = SettingsStore(file()).current
        assertNull(read.activeServer)
        assertNull(read.server)
        assertEquals(listOf("h"), read.servers.map { it.id })
    }

    @Test
    fun theServerInUseIsAlwaysTheOneWrittenForOlderVersions() {
        val store = SettingsStore(file())
        val home = SavedServer("https://home.test/", "winters", id = "h")
        val work = SavedServer("https://work.test/", "brandon", id = "w")
        store.update { it.copy(servers = listOf(home, work), activeServer = "w") }
        assertEquals(work, store.current.server)
        store.update { it.copy(activeServer = "h") }
        assertEquals(home, store.current.server)
        // A server taken off the list is no longer in use.
        store.update { it.copy(servers = listOf(work)) }
        assertNull(store.current.activeServer)
        assertNull(store.current.server)
        // Setting `server` alone reads the way an older Octo's file does.
        store.update { it.copy(server = home) }
        assertEquals(listOf("w", "h"), store.current.servers.map { it.id })
        assertEquals("h", store.current.activeServer)
    }

    // Home's order is kept under the same key as on the phone.
    @Test
    fun homeSectionsAreKeptUnderTheirOwnKey() {
        val stored = "charts,-pinned,recentlyPlayed"
        SettingsStore(file()).update { it.copy(appearance = it.appearance.copy(homeSections = stored)) }
        assertTrue(file().readText().contains("\"home_sections\": \"$stored\"") || file().readText().contains("\"home_sections\":\"$stored\""))
        assertEquals(stored, SettingsStore(file()).current.appearance.homeSections)
        assertNull(AppSettings().appearance.homeSections)
    }
}
