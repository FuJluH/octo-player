package app.winters.octo.animated

import app.winters.octo.subsonic.AnimatedArt
import app.winters.octo.subsonic.AnimatedClip
import org.junit.Assert.assertEquals
import org.junit.Test

class PlayerLoopsTest {
    private val square = AnimatedClip(video = "https://cdn.example.com/square.m3u8", width = 1080, height = 1080)
    private val tall = AnimatedClip(video = "https://cdn.example.com/tall.m3u8", width = 1080, height = 1440)
    private val both = AnimatedArt(square, tall)

    @Test
    fun uprightTheSettingDecides() {
        assertEquals(PlayerLoop.Cover(square), playerLoop(AnimatedArtSetting.Square, both, upright = true, live = false))
        assertEquals(PlayerLoop.Backdrop(tall), playerLoop(AnimatedArtSetting.FullScreen, both, upright = true, live = false))
        assertEquals(PlayerLoop.None, playerLoop(AnimatedArtSetting.Off, both, upright = true, live = false))
        // Full screen with no tall loop plays the square one in the cover's place.
        assertEquals(PlayerLoop.Cover(square), playerLoop(AnimatedArtSetting.FullScreen, AnimatedArt(square = square), upright = true, live = false))
    }

    @Test
    fun sidewaysTheSquareLoopPlaysInTheCoversPlace() {
        assertEquals(PlayerLoop.Cover(square), playerLoop(AnimatedArtSetting.FullScreen, both, upright = false, live = false))
        assertEquals(PlayerLoop.None, playerLoop(AnimatedArtSetting.FullScreen, AnimatedArt(tall = tall), upright = false, live = false))
        assertEquals(PlayerLoop.None, playerLoop(AnimatedArtSetting.Off, both, upright = false, live = false))
    }

    @Test
    fun aStationShowsNone() {
        assertEquals(PlayerLoop.None, playerLoop(AnimatedArtSetting.FullScreen, both, upright = true, live = true))
        assertEquals(PlayerLoop.None, playerLoop(AnimatedArtSetting.Square, both, upright = true, live = true))
    }

    @Test
    fun aLoopCoversItsSpaceWithoutBars() {
        // A 3:4 loop on a tall phone: as tall as the screen, cut at the sides.
        assertEquals(2376 to 3168, coverSize(1440, 3168, 0.75f))
        // A square loop in a square: as it is.
        assertEquals(600 to 600, coverSize(600, 600, 1f))
        // A wide space: as wide as the space, cut at the top and bottom.
        assertEquals(1000 to 1333, coverSize(1000, 500, 0.75f))
        assertEquals(0 to 0, coverSize(0, 0, 1f))
    }
}
