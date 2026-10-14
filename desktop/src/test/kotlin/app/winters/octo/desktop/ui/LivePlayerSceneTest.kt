package app.winters.octo.desktop.ui

import app.winters.octo.audio.EngineEvent
import app.winters.octo.desktop.SidePanel
import app.winters.octo.desktop.a11y.A11yScene
import app.winters.octo.desktop.a11y.name
import app.winters.octo.desktop.audio.EnginePlayer
import app.winters.octo.desktop.audio.FakeEngine
import app.winters.octo.desktop.audio.LocalOrServer
import app.winters.octo.desktop.audio.SongAddress
import app.winters.octo.desktop.audio.SongSources
import app.winters.octo.desktop.playStations
import app.winters.octo.liveradio.LiveStation
import app.winters.octo.liveradio.radioId
import app.winters.octo.subsonic.Song
import org.jetbrains.skia.EncodedImageFormat
import org.jetbrains.skia.Paint
import org.jetbrains.skia.Surface
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Rule
import org.junit.Test
import org.junit.rules.TemporaryFolder
import java.io.File
import kotlin.random.Random

// The live player in the whole window: the song on air with its artist
// and the station, LIVE in place of the seek line, Stop, Back and Next by
// station, the heart for the song, and no shuffle, repeat or lyrics. With
// OCTO_SHOTS=1 it also saves pictures (to OCTO_SHOTS_DIR, else build/shots).
class LivePlayerSceneTest {
    @get:Rule val folder = TemporaryFolder()

    private fun picture(ground: Int, disc: Int): ByteArray {
        val surface = Surface.makeRasterN32Premul(300, 300)
        surface.canvas.clear(ground)
        surface.canvas.drawCircle(150f, 150f, 90f, Paint().apply { color = disc })
        return surface.makeImageSnapshot().encodeToData(EncodedImageFormat.PNG)!!.bytes
    }

    private fun song(server: String) = "Ariana Grande - text=\"Petal\" song_spot=\"M\" MediaBaseId=\"3246947\" itunesTrackId=\"0\" " +
        "amgTrackId=\"-1\" amgArtistId=\"0\" TAID=\"0\" TPID=\"421089822\" cartcutId=\"0447960001\" " +
        "amgArtworkURL=\"${server}art/petal.png\" length=\"00:02:59\" unsID=\"-1\" spotInstanceId=\"-1\""

    private val spot = "LA's #1 Hit Music Station - text=\"102.7 KIIS FM\" song_spot=\"T\" MediaBaseId=\"0\" " +
        "itunesTrackId=\"0\" amgTrackId=\"0\" amgArtistId=\"0\" TAID=\"0\" TPID=\"0\" cartcutId=\"0\" amgArtworkURL=\"\" " +
        "length=\"00:00:00\" unsID=\"0\" spotInstanceId=\"-1\""

    @Test(timeout = 600_000)
    fun theLivePlayerShowsTheSongOnAirAndNoSeekLine() {
        val engine = FakeEngine()
        val sources = LocalOrServer(object : SongSources { override fun addressOf(song: Song) = SongAddress("https://octo.example/${song.id}") })
        val player = EnginePlayer(engine, sources, Random(1))
        A11yScene(folder.newFolder(), player = player).use { s ->
            s.server.file("petal.png", picture(0xFFE8B4C8.toInt(), 0xFF7A3B69.toInt()))
            s.server.file("kiis.png", picture(0xFFFFFFFF.toInt(), 0xFFD6202F.toInt()))
            // Octo has the song on air, with its own cover, which the player shows.
            s.server.answer("search3", """"searchResult3":{"song":[{"id":"petal-1","title":"Petal","artist":"Ariana Grande","album":"eternal sunshine","coverArt":"petal-c","duration":180}]}""")
            s.server.file("getCoverArt", picture(0xFF2B3F6B.toInt(), 0xFFF2C14E.toInt()))
            val kiis = LiveStation(
                "u-kiis", "102.7 KIIS FM", "https://stream.revma.ihrhls.com/zc185", favicon = "${s.server.address}art/kiis.png",
                codec = "AAC", bitrate = 128, country = "The United States Of America", countryCode = "US", state = "California", tags = listOf("pop", "top 40"),
            )
            val others = listOf(
                LiveStation("u-kroq", "KROQ 106.7", "https://stream.example/kroq", codec = "MP3", bitrate = 128, state = "California", tags = listOf("alternative")),
                LiveStation("u-kpcc", "LAist 89.3", "https://stream.example/kpcc", codec = "AAC", bitrate = 64, state = "California", tags = listOf("news")),
            )
            s.onUi {
                s.app.playStations((listOf(kiis) + others).map { it.radioId() }, 0, "Live radio near you")
                s.app.fullPlayer = true
            }
            engine.emit(EngineEvent.StreamTitle(engine.queue.single().id, song(s.server.address), ""))
            s.waitFor { s.app.liveHeart.match != null }
            s.render(6)
            var names = s.nodes(merged = true).map { it.name() }
            listOf("Live", "Stop", "Next station", "Previous station", "Heart Petal by Ariana Grande", "Petal", "Ariana Grande · 102.7 KIIS FM").forEach {
                assertTrue("shows $it", names.contains(it))
            }
            listOf("Song position", "Shuffle", "Repeat", "Lyrics").forEach { assertFalse("no $it", names.contains(it)) }
            shot(s, "live-player-song")

            // A spot: the station, its tagline, and no heart.
            engine.emit(EngineEvent.StreamTitle(engine.queue.single().id, spot, ""))
            s.render(6)
            names = s.nodes(merged = true).map { it.name() }
            assertTrue(names.contains("102.7 KIIS FM"))
            assertTrue(names.contains("LA's #1 Hit Music Station"))
            assertFalse(names.any { it.startsWith("Heart ") || it.endsWith("Petal by Ariana Grande to your library") || it == "Search for Petal by Ariana Grande" })
            shot(s, "live-player-station")

            // The stations being surfed, the one playing marked.
            s.onUi { s.app.togglePlayerPanel(SidePanel.Queue) }
            s.render(6)
            names = s.nodes(merged = true).map { it.name() }
            assertTrue(names.contains("102.7 KIIS FM, playing"))
            assertTrue(names.contains("Play KROQ 106.7"))
            shot(s, "live-player-stations")

            // Next station: one with no logo shows its drawn cover.
            s.onUi {
                s.app.togglePlayerPanel(SidePanel.Queue)
                s.app.player.next()
            }
            s.render(6)
            names = s.nodes(merged = true).map { it.name() }
            assertTrue(names.contains("KROQ 106.7"))
            assertTrue(names.contains("California · Alternative"))
            shot(s, "live-player-no-logo")
            s.onUi { s.app.player.previous() }

            // The player bar, with the song named again.
            engine.emit(EngineEvent.StreamTitle(engine.queue.single().id, song(s.server.address), ""))
            s.onUi { s.app.fullPlayer = false }
            s.render(6)
            names = s.nodes(merged = true).map { it.name() }
            assertTrue(names.contains("Live"))
            assertTrue(names.contains("Heart Petal by Ariana Grande"))
            assertFalse(names.contains("Song position"))
            shot(s, "live-bar")
        }
    }

    private fun shot(s: A11yScene, name: String) {
        val image = s.settle(1_500)
        if (System.getenv("OCTO_SHOTS") != "1") return
        val out = File(System.getenv("OCTO_SHOTS_DIR") ?: "build/shots").apply { mkdirs() }
        File(out, "$name.png").writeBytes(image.encodeToData(EncodedImageFormat.PNG)!!.bytes)
    }
}
