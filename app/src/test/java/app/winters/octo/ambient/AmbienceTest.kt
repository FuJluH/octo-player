package app.winters.octo.ambient

import androidx.navigation3.runtime.NavKey
import app.winters.octo.backup.Backup
import app.winters.octo.backup.BackupRead
import app.winters.octo.backup.decodeBackup
import app.winters.octo.backup.encodeBackup
import app.winters.octo.player.PlayerPrefs
import app.winters.octo.ui.nav.AlbumRoute
import app.winters.octo.ui.nav.AlbumsRoute
import app.winters.octo.ui.nav.ArtistRoute
import app.winters.octo.ui.nav.ArtistsRoute
import app.winters.octo.ui.nav.DownloadsRoute
import app.winters.octo.ui.nav.EditConnectionRoute
import app.winters.octo.ui.nav.FoldersRoute
import app.winters.octo.ui.nav.GenreRoute
import app.winters.octo.ui.nav.GenresRoute
import app.winters.octo.ui.nav.HomeRoute
import app.winters.octo.ui.nav.LibraryRoute
import app.winters.octo.ui.nav.LikedRoute
import app.winters.octo.ui.nav.OctoAdminRoute
import app.winters.octo.ui.nav.OnlineAlbumRoute
import app.winters.octo.ui.nav.OnlineArtistRoute
import app.winters.octo.ui.nav.PlaylistRoute
import app.winters.octo.ui.nav.PlaylistsRoute
import app.winters.octo.ui.nav.RadioStationsRoute
import app.winters.octo.ui.nav.SearchRoute
import app.winters.octo.ui.nav.SettingsPageRoute
import app.winters.octo.ui.nav.SettingsRoute
import app.winters.octo.ui.nav.SharesRoute
import app.winters.octo.ui.nav.SignInRoute
import app.winters.octo.ui.nav.SongsRoute
import app.winters.octo.ui.nav.SoundRoute
import app.winters.octo.ui.settings.SettingsPage
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test
import kotlin.math.abs

class AmbienceTest {
    private val white = 0xFFFFFFFF.toInt()

    // OctoColors.Accent, the colour of secondary text and labels.
    private val accent = 0xFF97B1B9.toInt()

    // Every colour on a 16-step grid of each channel: 4,096 colours, from
    // black to white through every hue, neon included.
    private val everyColour = sequence {
        for (r in 0..255 step 17) for (g in 0..255 step 17) for (b in 0..255 step 17) {
            yield((0xFF shl 24) or (r shl 16) or (g shl 8) or b)
        }
    }

    @Test
    fun whiteTextKeepsAaOnTheBrightestGlow() {
        everyColour.forEach { colour ->
            val field = composite(ambientColor(colour), ambientAlpha(AmbientStrength.Rich))
            val ratio = contrast(white, field)
            assertTrue("white on %08X gives %.2f".format(colour, ratio), ratio >= 4.5)
        }
    }

    @Test
    fun accentTextKeepsAaOnTheBrightestGlow() {
        everyColour.forEach { colour ->
            val field = composite(ambientColor(colour), ambientAlpha(AmbientStrength.Rich))
            val ratio = contrast(accent, field)
            assertTrue("accent on %08X gives %.2f".format(colour, ratio), ratio >= 4.5)
        }
    }

    @Test
    fun theClampHoldsLightnessAndSaturation() {
        // White becomes a middle grey, and pure red a dark, softened red.
        assertEquals(0xFF808080.toInt(), ambientColor(white))
        assertEquals(0xFFC63939.toInt(), ambientColor(0xFFFF0000.toInt()))
        everyColour.forEach { colour ->
            val clamped = ambientColor(colour)
            val channels = listOf(16, 8, 0).map { ((clamped shr it) and 0xFF) / 255f }
            val high = channels.max()
            val low = channels.min()
            val lightness = (high + low) / 2f
            val saturation = if (high == low) 0f else (high - low) / (1f - abs(2f * lightness - 1f))
            assertTrue("%08X lightness %.3f".format(colour, lightness), lightness <= AmbientMaxLightness + 0.01f)
            assertTrue("%08X saturation %.3f".format(colour, saturation), saturation <= AmbientMaxSaturation + 0.02f)
        }
    }

    @Test
    fun darkMutedColoursPassUnchanged() {
        val slate = 0xFF203040.toInt()
        val clamped = ambientColor(slate)
        listOf(16, 8, 0).forEach { shift ->
            assertTrue(abs(((slate shr shift) and 0xFF) - ((clamped shr shift) and 0xFF)) <= 1)
        }
    }

    @Test
    fun strengthMapsToAFaintAlpha() {
        assertEquals(0f, ambientAlpha(AmbientStrength.Off))
        val subtle = ambientAlpha(AmbientStrength.Subtle)
        val rich = ambientAlpha(AmbientStrength.Rich)
        assertTrue(subtle in 0.10f..0.25f)
        assertTrue(rich in 0.10f..0.25f)
        assertTrue(rich > subtle)
        // The bar's glass takes less colour than the page at every strength.
        AmbientStrength.entries.forEach { assertTrue(barTintAlpha(it) <= ambientAlpha(it)) }
        assertEquals(0f, barTintAlpha(AmbientStrength.Off))
    }

    @Test
    fun everyPageBelongsToAnArea() {
        mapOf<NavKey, AmbientArea>(
            HomeRoute to AmbientArea.Home,
            SearchRoute to AmbientArea.Search,
            LibraryRoute to AmbientArea.Library,
            AlbumsRoute to AmbientArea.Library,
            ArtistsRoute to AmbientArea.Library,
            SongsRoute to AmbientArea.Library,
            GenresRoute to AmbientArea.Library,
            GenreRoute("Jazz") to AmbientArea.Library,
            FoldersRoute to AmbientArea.Library,
            PlaylistsRoute to AmbientArea.Library,
            PlaylistRoute("p") to AmbientArea.Library,
            LikedRoute to AmbientArea.Library,
            DownloadsRoute to AmbientArea.Library,
            AlbumRoute("a") to AmbientArea.Library,
            ArtistRoute("a") to AmbientArea.Library,
            OnlineAlbumRoute("a") to AmbientArea.Library,
            OnlineArtistRoute("a") to AmbientArea.Library,
            SettingsRoute to AmbientArea.Settings,
            SettingsPageRoute(SettingsPage.Playback) to AmbientArea.Settings,
            SettingsPageRoute(SettingsPage.About, "version") to AmbientArea.Settings,
            SoundRoute to AmbientArea.Settings,
            SignInRoute to AmbientArea.Settings,
            EditConnectionRoute to AmbientArea.Settings,
            OctoAdminRoute to AmbientArea.Settings,
            SharesRoute to AmbientArea.Settings,
            RadioStationsRoute to AmbientArea.Settings,
        ).forEach { (route, area) -> assertEquals("$route", area, areaOf(route)) }
        assertNull(areaOf(null))
        assertNull(areaOf(object : NavKey {}))
    }

    private fun source(
        route: NavKey?,
        prefs: AmbientPrefs? = AmbientPrefs(),
        page: String? = null,
        playing: Boolean = true,
    ) = ambientSource(prefs, route, page, hasTrack = playing, playingArtwork = "song-cover")

    @Test
    fun pagesGlowWithTheSongOnNow() {
        assertEquals(AmbientSource.Playing("song-cover"), source(HomeRoute))
        assertEquals(AmbientSource.Playing("song-cover"), source(SearchRoute))
        assertEquals(AmbientSource.Playing("song-cover"), source(PlaylistRoute("p")))
        assertEquals(AmbientSource.Playing("song-cover"), source(SoundRoute))
    }

    @Test
    fun albumAndArtistPagesGlowWithTheirOwnArtwork() {
        assertEquals(AmbientSource.Page("album-cover"), source(AlbumRoute("a"), page = "album-cover"))
        assertEquals(AmbientSource.Page("artist-photo"), source(OnlineArtistRoute("a"), page = "artist-photo"))
        // Even with nothing playing.
        assertEquals(AmbientSource.Page("album-cover"), source(AlbumRoute("a"), page = "album-cover", playing = false))
        // Until that is switched off, or the page has no cover yet.
        val songOnly = AmbientPrefs(pageArtwork = false)
        assertEquals(AmbientSource.Playing("song-cover"), source(AlbumRoute("a"), songOnly, page = "album-cover"))
        assertEquals(AmbientSource.Playing("song-cover"), source(AlbumRoute("a"), page = null))
        // Only album and artist pages have artwork of their own.
        assertEquals(AmbientSource.Playing("song-cover"), source(PlaylistRoute("p"), page = "album-cover"))
    }

    @Test
    fun areasSwitchedOffStayPlain() {
        val prefs = AmbientPrefs(home = false, library = false, search = false, settings = false)
        listOf(HomeRoute, SearchRoute, LibraryRoute, AlbumRoute("a"), SettingsRoute).forEach {
            assertEquals(AmbientSource.None, source(it, prefs, page = "album-cover"))
        }
        val onlySearch = AmbientPrefs(home = false, library = false, settings = false)
        assertEquals(AmbientSource.Playing("song-cover"), source(SearchRoute, onlySearch))
        assertEquals(AmbientSource.None, source(HomeRoute, onlySearch))
    }

    @Test
    fun offUnreadAndSilenceStayPlain() {
        val off = AmbientPrefs(strength = AmbientStrength.Off)
        assertEquals(AmbientSource.None, source(HomeRoute, off))
        assertEquals(AmbientSource.None, source(AlbumRoute("a"), off, page = "album-cover"))
        assertFalse(off.tintsBar)
        // Settings not read yet.
        assertEquals(AmbientSource.None, source(HomeRoute, prefs = null))
        // Nothing loaded to take colours from.
        assertEquals(AmbientSource.None, source(HomeRoute, playing = false))
        // A page no area claims.
        assertEquals(AmbientSource.None, source(object : NavKey {}))
    }

    @Test
    fun theBarTintHasItsOwnSwitch() {
        assertTrue(AmbientPrefs().tintsBar)
        assertFalse(AmbientPrefs(bar = false).tintsBar)
        // The bar is not an area: switching every page off leaves it be.
        assertTrue(AmbientPrefs(home = false, library = false, search = false, settings = false).tintsBar)
    }

    @Test
    fun defaultsAreSubtleEverywhere() {
        val prefs = AmbientPrefs()
        assertEquals(AmbientStrength.Subtle, prefs.strength)
        AmbientArea.entries.forEach { assertTrue(prefs.shows(it)) }
        assertTrue(prefs.pageArtwork)
    }

    @Test
    fun aBackupKeepsTheAmbientSettings() {
        val ambient = AmbientPrefs(strength = AmbientStrength.Rich, search = false, bar = false, pageArtwork = false)
        val backup = Backup(player = PlayerPrefs(ambient = ambient))
        assertEquals(BackupRead.Read(backup), decodeBackup(encodeBackup(backup)))
    }

    @Test
    fun anUnknownStrengthInABackupFallsBackToTheDefault() {
        val text = encodeBackup(Backup(player = PlayerPrefs(ambient = AmbientPrefs(strength = AmbientStrength.Rich))))
            .replace("\"Rich\"", "\"Blinding\"")
        val read = decodeBackup(text) as BackupRead.Read
        assertEquals(AmbientStrength.Subtle, read.backup.player?.ambient?.strength)
    }

    @Test
    fun theGlowStepsOnceASecondSubtleAndTwiceRich() {
        assertEquals(1_000L, driftFrameMs(ambientAlpha(AmbientStrength.Subtle)))
        assertEquals(500L, driftFrameMs(ambientAlpha(AmbientStrength.Rich)))
    }
}
