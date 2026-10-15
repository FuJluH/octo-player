package app.winters.octo.desktop.system

import app.winters.octo.desktop.audio.EnginePlayer
import app.winters.octo.desktop.audio.FakeEngine
import app.winters.octo.desktop.audio.LocalOrServer
import app.winters.octo.desktop.audio.SongAddress
import app.winters.octo.desktop.audio.SongSources
import app.winters.octo.desktop.liveradio.liveSong
import app.winters.octo.liveradio.LiveStation
import app.winters.octo.liveradio.radioId
import app.winters.octo.subsonic.Song
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test
import kotlin.random.Random

// The taskbar's buttons and the mini player's menu while a station plays.
class LiveTaskbarTest {
    private val engine = FakeEngine()
    private val sources = LocalOrServer(
        object : SongSources {
            override fun addressOf(song: Song) = SongAddress("https://octo.example/stream?id=${song.id}")
        },
    )
    private val player = EnginePlayer(engine, sources, Random(1), clock = { 0L })
    private val stations = (1..3).map { n -> liveSong(LiveStation("u$n", "Station $n", "https://radio$n.example/live").radioId()) }

    @Test
    fun aStationOnAirShowsStopInTheMiddle() {
        player.play(stations, 1)
        val buttons = taskbarViewOf(player.state.value, 0).buttons
        assertTrue(buttons.live)
        assertTrue(buttons.playing)
        assertEquals("Stop", buttons.toggleTip)
        assertEquals("Next station", buttons.nextTip)
        assertEquals("Previous station", buttons.previousTip)
        // Stopped, it offers Play.
        player.pause()
        assertEquals("Play", taskbarViewOf(player.state.value, 0).buttons.toggleTip)
    }

    @Test
    fun aSongKeepsPause() {
        player.play(listOf(Song("s1", "Airbag", duration = 284)), 0)
        val buttons = taskbarViewOf(player.state.value, 0).buttons
        assertFalse(buttons.live)
        assertEquals("Pause", buttons.toggleTip)
        assertEquals("Next", buttons.nextTip)
    }

    @Test
    fun theStopIconIsASquareWherePauseWas() {
        val size = 16
        val songs = taskbarIconPixels(size, taskbarIconColour(lightTaskbar = false))
        val live = taskbarIconPixels(size, taskbarIconColour(lightTaskbar = false), stop = true)
        val third = size * size * 8 until size * size * 12
        assertFalse(songs.copyOfRange(third.first, third.last + 1).contentEquals(live.copyOfRange(third.first, third.last + 1)))
        // The other three are the same.
        assertTrue(songs.copyOfRange(0, size * size * 8).contentEquals(live.copyOfRange(0, size * size * 8)))
        // The square covers its middle, where the gap between the pause bars is.
        val middle = size * size * 8 + ((size / 2) * size + size / 2) * 4 + 3
        assertTrue((live[middle].toInt() and 0xFF) > 200)
    }

    @Test
    fun theMiniMenuOpensUnderItsButtonOrOverItNearTheBottom() {
        val anchor = MiniMenuAnchor(left = 100f, top = 500f, bottom = 530f)
        assertEquals(530f, miniMenuTop(anchor, height = 200f, screenTop = 0f, screenBottom = 1040f), 0f)
        assertEquals(300f, miniMenuTop(anchor, height = 200f, screenTop = 0f, screenBottom = 600f), 0f)
        // Never above the top of the screen.
        assertEquals(0f, miniMenuTop(anchor, height = 700f, screenTop = 0f, screenBottom = 600f), 0f)
    }
}
