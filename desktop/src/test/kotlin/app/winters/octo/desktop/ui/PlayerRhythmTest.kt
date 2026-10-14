package app.winters.octo.desktop.ui

import app.winters.octo.audio.EngineEvent
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
import org.jetbrains.skia.Bitmap
import org.jetbrains.skia.EncodedImageFormat
import org.jetbrains.skia.Image
import org.jetbrains.skia.Paint
import org.jetbrains.skia.Surface
import org.junit.Assert.assertTrue
import org.junit.Rule
import org.junit.Test
import org.junit.rules.TemporaryFolder
import java.io.File
import kotlin.math.abs
import kotlin.random.Random

// The full player's rhythm, in a large window and a small one: the cover
// sits at the same place for a song and for a station, so switching never
// moves it, and nothing below it is cut off. With OCTO_SHOTS=1 it saves
// pictures (to OCTO_SHOTS_DIR, else build/shots).
class PlayerRhythmTest {
    @get:Rule val folder = TemporaryFolder()

    // A teal cover with a warm disc, which every song and the song on air share.
    private val cover: ByteArray = run {
        val surface = Surface.makeRasterN32Premul(300, 300)
        surface.canvas.clear(0xFF3AA6A0.toInt())
        surface.canvas.drawCircle(150f, 150f, 60f, Paint().apply { color = 0xFFE0703A.toInt() })
        surface.makeImageSnapshot().encodeToData(EncodedImageFormat.PNG)!!.bytes
    }

    // The first row, going down the middle of the player's column, where
    // the cover's teal shows.
    private fun coverTop(image: Image, x: Int): Int {
        val bitmap = Bitmap.makeFromImage(image)
        for (y in 0 until image.height) {
            val c = bitmap.getColor(x, y)
            val r = (c shr 16) and 0xFF
            val g = (c shr 8) and 0xFF
            val b = c and 0xFF
            if (abs(r - 0x3A) < 24 && abs(g - 0xA6) < 24 && abs(b - 0xA0) < 24) return y
        }
        return -1
    }

    @Test(timeout = 600_000)
    fun theCoverStaysPutFromSongToStationAtEverySize() {
        for ((width, height) in listOf(1440 to 900, 960 to 600)) {
            val engine = FakeEngine()
            val sources = LocalOrServer(object : SongSources { override fun addressOf(song: Song) = SongAddress("https://octo.example/${song.id}") })
            A11yScene(folder.newFolder(), width = width, height = height, cover = cover, coverId = "rhythm-$width", player = EnginePlayer(engine, sources, Random(1))).use { s ->
                val x = width / 2 + 8
                s.onUi {
                    s.app.play(s.app.library!!.index!!.songs.filter { it.title == "Airbag" }, 0)
                    s.app.fullPlayer = true
                    // No panel beside it, so the column is in the middle.
                    s.app.playerPanel?.let(s.app::togglePlayerPanel)
                }
                val song = s.settle(2_500)
                val songTop = coverTop(song, x)
                save(song, "player-song-${width}x$height")
                val songBottom = bottomOf(s, "Volume")

                s.onUi { s.app.playStations(listOf(LiveStation("u1", "KROQ 106.7", "https://stream.example/kroq", state = "California").radioId()), 0, "Live radio") }
                engine.emit(EngineEvent.StreamTitle(engine.queue.single().id, "Radiohead - Airbag", ""))
                s.waitFor { s.app.liveHeart.match != null }
                val live = s.settle(2_500)
                val liveTop = coverTop(live, x)
                save(live, "player-live-${width}x$height")
                val liveBottom = bottomOf(s, "Volume")

                assertTrue("the cover shows ($songTop, $liveTop)", songTop > 0 && liveTop > 0)
                assertTrue("the cover stays put at ${width}x$height: song $songTop, live $liveTop", abs(songTop - liveTop) <= 2)
                assertTrue("the volume fits at ${width}x$height: song $songBottom, live $liveBottom", songBottom <= height && liveBottom <= height)
            }
        }
    }

    // Where the lowest control by this name ends, in the window.
    private fun bottomOf(s: A11yScene, name: String): Float =
        s.nodes(merged = true).filter { it.name() == name }.maxOfOrNull { it.boundsInRoot.bottom } ?: Float.MAX_VALUE

    private fun save(image: Image, name: String) {
        if (System.getenv("OCTO_SHOTS") != "1") return
        val out = File(System.getenv("OCTO_SHOTS_DIR") ?: "build/shots").apply { mkdirs() }
        File(out, "$name.png").writeBytes(image.encodeToData(EncodedImageFormat.PNG)!!.bytes)
    }
}
