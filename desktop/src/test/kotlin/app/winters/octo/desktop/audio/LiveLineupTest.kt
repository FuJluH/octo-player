package app.winters.octo.desktop.audio

import app.winters.octo.audio.EngineEvent
import app.winters.octo.audio.ErrorKind
import app.winters.octo.desktop.liveradio.liveSong
import app.winters.octo.desktop.player.DesktopPlayer
import app.winters.octo.desktop.player.RepeatMode
import app.winters.octo.desktop.player.SilentPlayer
import app.winters.octo.liveradio.LiveStation
import app.winters.octo.liveradio.radioId
import app.winters.octo.subsonic.Song
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test
import kotlin.random.Random

// The live player's stations: the list a station was started from is
// queued in its order, Back and Next step through it and stop at its ends,
// and shuffle, repeat and a failing stream never move it on by itself.
class LiveLineupTest {
    private val sources = LocalOrServer(
        object : SongSources {
            override fun addressOf(song: Song) = SongAddress("https://octo.example/stream?id=${song.id}")
        },
    )
    private var now = 0L

    private fun station(n: Int) = liveSong(LiveStation("u$n", "Station $n", "https://radio$n.example/live", codec = "MP3", bitrate = 128).radioId())

    private val stations = (1..3).map(::station)

    private fun engine(): Pair<FakeEngine, EnginePlayer> {
        val engine = FakeEngine()
        return engine to EnginePlayer(engine, sources, Random(1), clock = { now })
    }

    private fun DesktopPlayer.on(): String = state.value.live!!.shown.station

    @Test
    fun backAndNextStepThroughTheListAndStopAtItsEnds() {
        val (engine, player) = engine()
        player.play(stations, 1)
        assertEquals("Station 2", player.on())
        val lineup = player.state.value.live!!.lineup
        assertTrue(lineup.shows && lineup.hasPrevious && lineup.hasNext)
        // The engine holds the station alone; each step opens the next afresh.
        assertEquals(1, engine.queue.size)
        player.next()
        assertEquals("Station 3", player.on())
        assertEquals("load 1 at 0 from 0 playing", engine.calls.last())
        assertFalse(player.state.value.live!!.lineup.hasNext)
        val calls = engine.calls.size
        player.next()
        assertEquals("Station 3", player.on())
        assertEquals("no step past the last station", calls, engine.calls.size)
        player.previous()
        player.previous()
        assertEquals("Station 1", player.on())
        // Back on a station goes to the station before, never starts it over.
        player.previous()
        assertEquals("Station 1", player.on())
        assertFalse(engine.calls.any { it.startsWith("seek") })
        player.close()
    }

    @Test
    fun oneStationShowsNoBackOrNext() {
        val (_, player) = engine()
        player.play(listOf(stations[0]), 0)
        val lineup = player.state.value.live!!.lineup
        assertFalse(lineup.shows)
        assertFalse(lineup.hasNext)
        assertFalse(lineup.hasPrevious)
        player.close()
    }

    @Test
    fun shuffleAndRepeatLeaveALineupInItsOrder() {
        val (engine, player) = engine()
        player.setRepeat(RepeatMode.All)
        player.play(stations, 0, shuffle = true)
        assertEquals(stations.map { it.id }, (player.state.value.played + player.state.value.current!! + player.state.value.upcoming).map { it.song.id })
        // The engine never repeats a station by itself.
        assertEquals("repeat OFF", engine.calls.last { it.startsWith("repeat") })
        player.setShuffle(true)
        assertEquals(listOf("Station 2", "Station 3"), player.state.value.upcoming.map { it.song.title })
        player.next()
        player.next()
        player.next()
        assertEquals("repeat all does not go round a lineup", "Station 3", player.on())
        // The listener's repeat comes back for songs.
        player.play(listOf(Song("s1", "Song", duration = 200)), 0)
        assertEquals("repeat ALL", engine.calls.last { it.startsWith("repeat") })
        assertEquals(RepeatMode.All, player.state.value.repeat)
        player.close()
    }

    @Test
    fun aStationThatFailsStaysWhereItIs() {
        val (engine, player) = engine()
        player.play(stations, 0)
        val item = engine.queue.single().id
        engine.emit(EngineEvent.Error(ErrorKind.NETWORK, "the live stream stopped and did not come back", item))
        engine.emit(EngineEvent.QueueEnded)
        assertEquals("Station 1", player.on())
        assertFalse(player.state.value.playing)
        assertTrue(player.state.value.problem != null)
        player.close()
    }

    @Test
    fun stopLetsTheStreamGoAndPlayJoinsItAfresh() {
        val (engine, player) = engine()
        player.play(stations, 0)
        val radio = engine.queue.single().id
        engine.emit(EngineEvent.TrackStarted(radio, 0u, null))
        engine.emit(EngineEvent.StreamTitle(radio, "Reef Project - True Clown", ""))
        assertTrue(player.state.value.live!!.named)
        player.pause()
        assertEquals("stop", engine.calls.last())
        assertFalse(player.state.value.playing)
        // What it named is no longer on air.
        assertFalse(player.state.value.live!!.named)
        player.resume()
        assertEquals("load 1 at 0 from 0 playing", engine.calls.last())
        assertTrue(player.state.value.playing)
        player.close()
    }

    @Test
    fun aStationWaitingToPlayHoldsNoConnection() {
        val (engine, player) = engine()
        player.addToQueue(listOf(stations[0]))
        assertEquals("load 0 at 0 from 0 paused", engine.calls.last())
        assertNull(engine.queue.firstOrNull())
        player.resume()
        assertEquals("load 1 at 0 from 0 playing", engine.calls.last())
        player.close()
    }

    @Test
    fun theSilentPlayerStepsTheSameWay() {
        val player = SilentPlayer(clock = { now })
        player.setRepeat(RepeatMode.All)
        player.play(stations, 2, shuffle = true)
        assertEquals("Station 3", player.on())
        player.next()
        assertEquals("Station 3", player.on())
        player.previous()
        assertEquals("Station 2", player.on())
        // Its place is how long it has been listened to.
        now += 65_000
        assertEquals(65_000, player.positionMs())
        player.pause()
        player.resume()
        assertEquals("Play starts the station afresh", 0, player.positionMs())
        player.close()
    }

    @Test
    fun songsAfterALineupShuffleAsTheListenerSet() {
        val (_, player) = engine()
        player.setShuffle(true)
        player.play(stations, 0, shuffle = false)
        assertTrue("a lineup keeps the setting", player.state.value.shuffle)
        player.close()
    }
}
