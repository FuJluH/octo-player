package app.winters.octo.player.immersive

import app.winters.octo.player.MESH_FULL_FPS
import app.winters.octo.player.PlayerPrefs
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Test

class BackgroundPrefsTest {
    @Test
    fun theDefaultsAreTheSpecs() {
        val prefs = BackgroundPrefs()
        assertEquals(BackgroundMode.Default, prefs.mode)
        assertEquals(50, prefs.brightnessCap)
        assertEquals(180, prefs.saturation)
        assertEquals(1.3f, prefs.contrast)
        assertEquals(true, prefs.useBpm)
        assertEquals(60, prefs.fps)
        // Slower than the full pace, so it reads as an ambience.
        assertEquals(25, prefs.speed)
        assertEquals(WashTuning(1.3f, 1.8f, 0.5f), prefs.tuning)
    }

    @Test
    fun oddSavedValuesAreHeldToTheRanges() {
        val odd = BackgroundPrefs(brightnessCap = 5, saturation = 900, contrast = 9f, fps = 45, speed = 0).sane()
        assertEquals(20, odd.brightnessCap)
        assertEquals(300, odd.saturation)
        assertEquals(2f, odd.contrast)
        assertEquals(60, odd.fps)
        assertEquals(5, odd.speed)
    }

    @Test
    fun olderPhonesShowTheStillArtworkForTheWash() {
        assertEquals(BackgroundMode.Default, drawnMode(BackgroundMode.Default, 33))
        assertEquals(BackgroundMode.Artwork, drawnMode(BackgroundMode.Default, 32))
        assertEquals(BackgroundMode.Artwork, drawnMode(BackgroundMode.Default, 29))
        assertEquals(BackgroundMode.Classic, drawnMode(BackgroundMode.Classic, 29))
        assertEquals(BackgroundMode.Colour, drawnMode(BackgroundMode.Colour, 29))
    }

    @Test
    fun aMovingBackgroundNamesItsFrameLimit() {
        val wash = PlayerPrefs(background = BackgroundPrefs(fps = 30))
        // The wash moves playing or not, at its own limit.
        assertEquals(30, movingBackgroundFps(wash, 33, playing = true))
        assertEquals(30, movingBackgroundFps(wash, 33, playing = false))
        // Faster limits draw at 30, all the slow drift needs.
        assertEquals(30, movingBackgroundFps(PlayerPrefs(background = BackgroundPrefs(fps = 120)), 33, playing = true))
        // Older phones show the still artwork instead.
        assertNull(movingBackgroundFps(wash, 32, playing = true))
        assertNull(movingBackgroundFps(wash.copy(liveBackground = false), 33, playing = true))
        // The classic mesh at its full rate while music plays only.
        val mesh = PlayerPrefs(background = BackgroundPrefs(mode = BackgroundMode.Classic))
        assertEquals(MESH_FULL_FPS, movingBackgroundFps(mesh, 33, playing = true))
        assertNull(movingBackgroundFps(mesh, 33, playing = false))
        assertNull(movingBackgroundFps(mesh, 32, playing = true))
        assertNull(movingBackgroundFps(PlayerPrefs(background = BackgroundPrefs(mode = BackgroundMode.Colour)), 33, playing = true))
    }

    @Test
    fun theWashDrawsAtThirtyWhateverAnOldSettingSays() {
        assertEquals(30, WashMaxFps)
        assertEquals(30, movingBackgroundFps(PlayerPrefs(background = BackgroundPrefs(fps = 90)), 33, playing = true))
        // An old saved rate still reads back.
        assertEquals(90, BackgroundPrefs(fps = 90).sane().fps)
    }

    @Test
    fun theDollyRunsFromNinetyPercentToFull() {
        assertEquals(0.9f, dollyScale(0f), 1e-6f)
        assertEquals(1f, dollyScale(1f), 1e-6f)
    }
}
