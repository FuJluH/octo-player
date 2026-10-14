package app.winters.octo.desktop.system

import app.winters.octo.audio.EngineEvent
import app.winters.octo.desktop.audio.EnginePlayer
import app.winters.octo.desktop.audio.FakeEngine
import app.winters.octo.desktop.audio.Heard
import app.winters.octo.desktop.audio.LocalOrServer
import app.winters.octo.desktop.audio.SongAddress
import app.winters.octo.desktop.audio.SongSources
import app.winters.octo.desktop.liveradio.liveSong
import app.winters.octo.liveradio.LiveStation
import app.winters.octo.liveradio.radioId
import app.winters.octo.playback.radioId
import app.winters.octo.subsonic.Song
import kotlinx.coroutines.ExperimentalCoroutinesApi
import kotlinx.coroutines.test.TestScope
import kotlinx.coroutines.test.UnconfinedTestDispatcher
import kotlinx.coroutines.test.runCurrent
import kotlinx.coroutines.test.runTest
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test
import java.io.File
import kotlin.coroutines.EmptyCoroutineContext
import kotlin.random.Random

// The system's player while a station plays: the song on air, no length
// and nothing to seek, the station's pictures, and next and previous
// changing station along its lineup.
@OptIn(ExperimentalCoroutinesApi::class)
class LiveMediaSessionTest {
    private var clock = 0L
    private val engine = FakeEngine()
    private val sources = LocalOrServer(
        object : SongSources {
            override fun addressOf(song: Song) = SongAddress("https://octo.example/stream?id=${song.id}")
        },
    )
    private val player = EnginePlayer(engine, sources, Random(1), clock = { clock })
    private val stations = (1..3).map { n ->
        liveSong(LiveStation("u$n", "Station $n", "https://radio$n.example/live", favicon = if (n == 2) "" else "https://radio$n.example/logo.png").radioId())
    }

    // The pictures asked for: by web address, or the drawn cover.
    private val asked = ArrayList<String>()
    private val covers = object : CoverSource {
        override suspend fun load(coverId: String): CoverArt? = null

        override suspend fun live(now: NowPlaying): CoverArt {
            asked += now.artUrl ?: "drawn ${now.station}"
            return CoverArt(byteArrayOf(1), File("x.img"))
        }
    }

    private fun TestScope.started(controls: FakeControls): MediaSession {
        val session = MediaSession(player, controls, covers, backgroundScope, clock = { clock }, checkEveryMs = 1_000, refreshEveryMs = 5_000, startOn = EmptyCoroutineContext)
        session.start()
        runCurrent()
        return session
    }

    @Test
    fun theSongOnAirShowsWithNoLengthAndNoPlace() = runTest(UnconfinedTestDispatcher()) {
        val controls = FakeControls()
        val session = started(controls)
        player.play(stations, 0)
        runCurrent()
        val radio = engine.queue.single().id
        engine.emit(EngineEvent.StreamTitle(radio, "Reef Project - True Clown", "https://somafm.com/logos/512/groovesalad512.jpg"))
        runCurrent()
        val now = nowPlayingOf(player.state.value)!!
        assertEquals("True Clown", now.title)
        assertEquals("Reef Project", now.artist)
        assertEquals("Station 1", now.album)
        assertEquals(0, now.durationMs)
        assertTrue(now.live)
        assertEquals(0.0, now.rate, 0.0)
        assertEquals("https://somafm.com/logos/512/groovesalad512.jpg", now.artUrl)
        assertTrue(controls.calls.contains("track True Clown with cover"))
        assertEquals("https://somafm.com/logos/512/groovesalad512.jpg", asked.last())
        // However long it has been listened to, the system is told no place.
        controls.calls.clear()
        engine.heard = Heard(radio, 90_000.0, null)
        clock += 6_000
        session.check()
        assertTrue(controls.calls.all { it.endsWith("at 0") })
        // Nothing to seek.
        controls.events!!(SystemEvent.SeekTo(30_000))
        controls.events!!(SystemEvent.SeekBy(5_000))
        runCurrent()
        assertFalse(engine.calls.any { it.startsWith("seek") })
        assertFalse(controls.calls.any { it.contains("jumped") })
        // The system's linux side has no length and cannot seek.
        assertFalse(Mpris.metadata(now, null).containsKey("mpris:length"))
        assertEquals(false, Mpris.playerProperties(now, 1.0)["CanSeek"])
        player.close()
    }

    @Test
    fun nextAndPreviousChangeStationAndStopAtTheEnds() = runTest(UnconfinedTestDispatcher()) {
        val controls = FakeControls()
        started(controls)
        player.play(stations, 0)
        runCurrent()
        var now = nowPlayingOf(player.state.value)!!
        assertFalse("no station before the first", now.canPrevious)
        assertTrue(now.canNext)
        assertEquals("the logo, while it names no song", "https://radio1.example/logo.png", asked.last())
        controls.events!!(SystemEvent.Next)
        runCurrent()
        now = nowPlayingOf(player.state.value)!!
        assertEquals("Station 2", now.title)
        assertTrue(now.canPrevious && now.canNext)
        assertEquals("a station with no logo has its drawn cover", "drawn Station 2", asked.last())
        controls.events!!(SystemEvent.Next)
        controls.events!!(SystemEvent.Next)
        runCurrent()
        now = nowPlayingOf(player.state.value)!!
        assertEquals("Station 3", now.title)
        assertFalse(now.canNext)
        // Previous changes station; it never starts this one over.
        controls.events!!(SystemEvent.Previous)
        runCurrent()
        assertEquals("Station 2", nowPlayingOf(player.state.value)!!.title)
        assertFalse(engine.calls.any { it.startsWith("seek") })
        // Stop lets the stream go; Play joins it afresh.
        controls.events!!(SystemEvent.Stop)
        runCurrent()
        assertEquals("stop", engine.calls.last())
        controls.events!!(SystemEvent.Play)
        runCurrent()
        assertEquals("load 1 at 0 from 0 playing", engine.calls.last())
        player.close()
    }

    @Test
    fun oneStationHasNoNextOrPrevious() {
        player.play(listOf(liveSong(radioId("https://one.example/live", "One"))), 0)
        val now = nowPlayingOf(player.state.value)!!
        assertFalse(now.canNext)
        assertFalse(now.canPrevious)
        assertEquals(null, now.artUrl)
        player.close()
    }
}
