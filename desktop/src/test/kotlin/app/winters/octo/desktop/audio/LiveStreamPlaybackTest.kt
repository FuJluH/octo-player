package app.winters.octo.desktop.audio

import app.winters.octo.audio.EngineEvent
import app.winters.octo.desktop.listening.HeardPlay
import app.winters.octo.desktop.listening.PlayCounter
import app.winters.octo.desktop.player.PlayerState
import app.winters.octo.desktop.player.QueueEntry
import app.winters.octo.desktop.queue.serverQueueOf
import app.winters.octo.playback.radioId
import app.winters.octo.subsonic.Song
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test
import kotlin.random.Random

// Live radio on the desktop: played from the station's own address as
// a live stream, its stream's titles shown as the song, and never a play.
class LiveStreamPlaybackTest {
    private val stream = "https://radio.example:8443/jazz.aac?listen=1"
    private val station = Song(radioId(stream, "Jazz FM"), "Jazz FM", artist = "Live radio")
    private val song = Song("s1", "Song", artist = "Someone", duration = 200)
    private var now = 0L

    // The server's songs come with its own headers, which a station must not get.
    private val sources = LocalOrServer(
        object : SongSources {
            override fun addressOf(song: Song) = SongAddress("https://octo.example/stream?id=${song.id}", mapOf("X-Octo" to "secret"))
        },
    )

    @Test
    fun aStationPlaysFromItsOwnAddressWithNoHeaders() {
        assertEquals(SongAddress(stream), sources.addressOf(station))
        assertEquals("secret", sources.addressOf(song)?.headers?.get("X-Octo"))
    }

    @Test
    fun aStationIsALiveItemWithNoLength() {
        // Even a length listed for it is left out.
        val item = queueItem(QueueEntry(7, station.copy(duration = 180)), sources)
        assertTrue(item.live)
        assertNull(item.durationMs)
        assertEquals(stream, item.source)
        assertEquals(emptyList<Any>(), item.headers)
        val other = queueItem(QueueEntry(8, song), sources)
        assertFalse(other.live)
        assertEquals(200_000uL, other.durationMs)
    }

    @Test
    fun theStreamsTitleShowsAsTheSongAndTheStationAsTheArtist() {
        val engine = FakeEngine()
        val player = EnginePlayer(engine, sources, Random(1), clock = { now })
        player.play(listOf(station, song), 0)
        assertEquals("load 2 at 0 from 0 playing", engine.calls.single())
        assertTrue(engine.queue[0].live)
        val radio = engine.queue[0].id
        engine.emit(EngineEvent.TrackStarted(radio, 0u, null))
        // Until the stream names what it plays, the station's name.
        assertEquals("Jazz FM" to "Live radio", player.state.value.current!!.song.let { it.title to it.artist })
        engine.emit(EngineEvent.StreamTitle(radio, "Miles Davis - So What"))
        val shown = player.state.value.current!!.song
        assertEquals("Miles Davis - So What" to "Jazz FM", shown.title to shown.artist)
        assertEquals(station.id, shown.id)
        // The queue keeps the station as it is, so a saved queue does too.
        assertEquals("Jazz FM", player.state.value.queue.first().song.title)
        // A title for an entry no longer queued changes nothing.
        engine.emit(EngineEvent.StreamTitle("q:999", "Other - Thing"))
        assertEquals("Miles Davis - So What", player.state.value.current!!.song.title)
        // A live stream takes no seek, and starts where its station is.
        player.seekTo(60_000)
        assertFalse(engine.calls.any { it.startsWith("seek") })
        player.close()
    }

    @Test
    fun aStreamTitleShowsOnlyOnAStation() {
        val live = onAir(station, " Miles Davis - So What ")
        assertEquals("Miles Davis - So What" to "Jazz FM", live.title to live.artist)
        assertEquals(station.id, live.id)
        assertEquals(station, onAir(station, null))
        assertEquals(station, onAir(station, "  "))
        assertEquals(song, onAir(song, "Other - Thing"))
        // A station with no name shows its address.
        val unnamed = Song(radioId(stream), stream)
        assertEquals(stream, onAir(unnamed, "A - B").artist)
    }

    @Test
    fun aStationIsNeverAPlayNorAnnounced() {
        val started = mutableListOf<String>()
        val counted = mutableListOf<HeardPlay>()
        val counter = PlayCounter({ started += it.id }, { counted += it }, clock = { now })
        counter.update(PlayerState(current = QueueEntry(1, station), playing = true))
        now += 3_600_000
        counter.check()
        assertNull(counter.msUntilCounted())
        counter.update(PlayerState(current = QueueEntry(2, song), playing = true))
        assertEquals(listOf("s1"), started)
        assertEquals(emptyList<HeardPlay>(), counted)
    }

    @Test
    fun theServersQueueLeavesStationsOut() {
        val entries = listOf(QueueEntry(1, song), QueueEntry(2, station), QueueEntry(3, Song("s2", "Two")))
        val onServer = serverQueueOf(PlayerState(queue = entries, played = entries.take(1), current = entries[1], upcoming = entries.drop(2)), 5_000)!!
        assertEquals(listOf("s1", "s2"), onServer.ids)
        // The station playing is not there: the next song takes its place, from its start.
        assertEquals(1, onServer.index)
        assertEquals(0, onServer.positionMs)
    }
}
