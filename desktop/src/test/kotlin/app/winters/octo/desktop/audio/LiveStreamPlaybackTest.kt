package app.winters.octo.desktop.audio

import app.winters.octo.audio.EngineEvent
import app.winters.octo.desktop.listening.HeardPlay
import app.winters.octo.desktop.listening.PlayCounter
import app.winters.octo.desktop.player.PlayerState
import app.winters.octo.desktop.player.QueueEntry
import app.winters.octo.desktop.queue.serverQueueOf
import app.winters.octo.desktop.liveradio.liveSong
import app.winters.octo.liveradio.LiveStation
import app.winters.octo.liveradio.liveCodecLine
import app.winters.octo.liveradio.radioId
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
    fun theSongOnAirShowsWithItsArtistAndTheStation() {
        val engine = FakeEngine()
        val player = EnginePlayer(engine, sources, Random(1), clock = { now })
        player.play(listOf(station, song), 0)
        // The engine holds the station alone, so a stream that fails stops there.
        assertEquals("load 1 at 0 from 0 playing", engine.calls.last())
        assertTrue(engine.queue[0].live)
        val radio = engine.queue[0].id
        engine.emit(EngineEvent.TrackStarted(radio, 0u, null))
        // Until the stream names what it plays, the station's name.
        assertEquals("Jazz FM" to "Live radio", player.state.value.current!!.song.let { it.title to it.artist })
        engine.emit(EngineEvent.StreamTitle(radio, "Miles Davis - So What", ""))
        val shown = player.state.value.current!!.song
        assertEquals("So What" to "Miles Davis", shown.title to shown.artist)
        assertEquals("Jazz FM", shown.album)
        assertEquals("Miles Davis · Jazz FM", player.state.value.live!!.shown.subtitle)
        assertEquals(station.id, shown.id)
        // The queue keeps the station as it is, so a saved queue does too.
        assertEquals("Jazz FM", player.state.value.queue.first().song.title)
        // A title for an entry no longer queued changes nothing.
        engine.emit(EngineEvent.StreamTitle("q:999", "Other - Thing", ""))
        assertEquals("So What", player.state.value.current!!.song.title)
        // A live stream takes no seek, and starts where its station is.
        player.seekTo(60_000)
        assertFalse(engine.calls.any { it.startsWith("seek") })
        player.close()
    }

    @Test
    fun aSongPlayingShowsNoLiveSide() {
        val engine = FakeEngine()
        val player = EnginePlayer(engine, sources, Random(1), clock = { now })
        player.play(listOf(song), 0)
        engine.emit(EngineEvent.StreamTitle(engine.queue[0].id, "Other - Thing", ""))
        assertNull(player.state.value.live)
        assertEquals("Song", player.state.value.current!!.song.title)
        player.close()
    }

    // KIIS FM's iHeart titles, as the stream sent them on 2026-10-13.
    private val kiis = LiveStation("u-kiis", "102.7 KIIS FM", "https://stream.revma.ihrhls.com/zc185", favicon = "https://i.iheart.com/v3/re/assets.brands/2ebe", codec = "AAC", bitrate = 128, country = "The United States Of America", countryCode = "US", state = "California", tags = listOf("pop"))
    private val kiisSong = "Ariana Grande - text=\"Petal\" song_spot=\"M\" MediaBaseId=\"3246947\" itunesTrackId=\"0\" " +
        "amgTrackId=\"-1\" amgArtistId=\"0\" TAID=\"0\" TPID=\"421089822\" cartcutId=\"0447960001\" " +
        "amgArtworkURL=\"https://i.iheart.com/v3/catalog/track/421089822?ops=fit(200,200),format(%22jpeg%22)\" " +
        "length=\"00:02:59\" unsID=\"-1\" spotInstanceId=\"-1\""
    private val kiisSpot = "LA's #1 Hit Music Station - text=\"102.7 KIIS FM\" song_spot=\"T\" MediaBaseId=\"0\" " +
        "itunesTrackId=\"0\" amgTrackId=\"0\" amgArtistId=\"0\" TAID=\"0\" TPID=\"0\" cartcutId=\"0\" amgArtworkURL=\"\" " +
        "length=\"00:00:00\" unsID=\"0\" spotInstanceId=\"-1\""

    @Test
    fun kiisShowsTheSongItsArtistAndArtworkNotItsRawTitle() {
        val engine = FakeEngine()
        val player = EnginePlayer(engine, sources, Random(1), clock = { now })
        player.play(listOf(liveSongOf(kiis)), 0)
        val radio = engine.queue[0].id
        engine.emit(EngineEvent.StreamTitle(radio, kiisSong, ""))
        val live = player.state.value.live!!
        assertEquals("Petal", player.state.value.current!!.song.title)
        assertEquals("Ariana Grande", player.state.value.current!!.song.artist)
        assertEquals("Ariana Grande · 102.7 KIIS FM", live.shown.subtitle)
        // iHeart is asked for its artwork at the size the player draws.
        assertEquals("https://i.iheart.com/v3/catalog/track/421089822?ops=fit(600,600),format(%22jpeg%22)", live.shown.cover)
        assertEquals("AAC 128 kbps", liveCodecLine(live.shown.details))
        assertEquals("Ariana Grande - Petal", live.songName)
        // A spot names no song: the station, with its tagline, and its logo.
        engine.emit(EngineEvent.StreamTitle(radio, kiisSpot, ""))
        val spot = player.state.value.live!!
        assertFalse(spot.named)
        assertEquals("102.7 KIIS FM", player.state.value.current!!.song.title)
        assertEquals("LA's #1 Hit Music Station", spot.shown.subtitle)
        assertEquals("LA's #1 Hit Music Station", player.state.value.current!!.song.artist)
        assertEquals(kiis.favicon, spot.shown.cover)
        // Nothing named at all: where the station is and what it plays.
        engine.emit(EngineEvent.StreamTitle(radio, "", ""))
        assertEquals("California, The United States Of America · Pop", player.state.value.live!!.shown.subtitle)
        player.close()
    }

    @Test
    fun somaFmsStreamUrlIsTheArtwork() {
        val engine = FakeEngine()
        val player = EnginePlayer(engine, sources, Random(1), clock = { now })
        player.play(listOf(liveSong(radioId("https://ice1.somafm.com/groovesalad-128-mp3", "Groove Salad"))), 0)
        engine.emit(EngineEvent.StreamTitle(engine.queue[0].id, "Reef Project - True Clown", "https://somafm.com/logos/512/groovesalad512.jpg"))
        val live = player.state.value.live!!
        assertEquals("True Clown", live.shown.title)
        assertEquals("Reef Project · Groove Salad", live.shown.subtitle)
        assertEquals("https://somafm.com/logos/512/groovesalad512.jpg", live.shown.cover)
        player.close()
    }

    private fun liveSongOf(station: LiveStation) = liveSong(station.radioId())

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

    @Test
    fun aStationMarkedAsHlsOpensAsHls() {
        val marked = Song(radioId(stream, "Jazz FM") + ":hls", "Jazz FM")
        assertTrue(queueItem(QueueEntry(1, marked), sources).hls)
        assertEquals(stream, queueItem(QueueEntry(1, marked), sources).source)
        assertFalse(queueItem(QueueEntry(2, station), sources).hls)
        assertFalse(queueItem(QueueEntry(3, song), sources).hls)
    }

    @Test
    fun anEmptyStreamTitleShowsTheStationAgain() {
        val engine = FakeEngine()
        val player = EnginePlayer(engine, sources, Random(1), clock = { now })
        player.play(listOf(station), 0)
        val radio = engine.queue[0].id
        engine.emit(EngineEvent.TrackStarted(radio, 0u, null))
        engine.emit(EngineEvent.StreamTitle(radio, "Miles Davis - So What", ""))
        engine.emit(EngineEvent.StreamTitle(radio, "", ""))
        assertEquals("Jazz FM" to "Live radio", player.state.value.current!!.song.let { it.title to it.artist })
        player.close()
    }

    // After a long pause the engine opens a station again where it is now;
    // that start is no time round on repeat.
    @Test
    fun aStationStartedAgainIsNoRound() {
        val engine = FakeEngine()
        val player = EnginePlayer(engine, sources, Random(1), clock = { now })
        player.play(listOf(station), 0)
        val radio = engine.queue[0].id
        engine.emit(EngineEvent.TrackStarted(radio, 0u, null))
        engine.emit(EngineEvent.TrackStarted(radio, 0u, null))
        assertEquals(0, player.state.value.rounds)
        player.close()
    }
}
