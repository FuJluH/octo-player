package app.winters.octo.desktop.animated

import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.runtime.mutableStateOf
import androidx.compose.ui.ImageComposeScene
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.unit.Density
import app.winters.octo.animated.AnimatedArtSetting
import app.winters.octo.animated.LoopPlay
import app.winters.octo.audio.loopVideoAvailable
import app.winters.octo.desktop.FakeServer
import app.winters.octo.desktop.server.Connection
import app.winters.octo.desktop.settings.Appearance
import app.winters.octo.desktop.settings.SavedServer
import app.winters.octo.desktop.settings.animatedArtSetting
import app.winters.octo.desktop.ui.DarkInk
import app.winters.octo.subsonic.AnimatedArt
import app.winters.octo.subsonic.AnimatedArtAnswer
import app.winters.octo.subsonic.AnimatedClip
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.async
import kotlinx.coroutines.awaitAll
import kotlinx.coroutines.cancel
import kotlinx.coroutines.runBlocking
import okhttp3.OkHttpClient
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Assume.assumeTrue
import org.junit.Rule
import org.junit.Test
import org.junit.rules.TemporaryFolder
import java.io.File
import javax.swing.SwingUtilities
import kotlin.math.pow

class AnimatedArtTest {
    @get:Rule val folder = TemporaryFolder()

    // The engine's own test loop: 1 s of H.264 at 24 frames a second,
    // 90x90, red over blue.
    private val fixture = File("../audio-engine/tests/fixtures/loop-red-blue.mp4")

    // A server with one album's square loop and its still, the way Octo
    // passes them on: a master playlist, a version's playlist naming one
    // file, the file, and the still.
    private fun serverWithLoop(): FakeServer = FakeServer().apply {
        answer("getAnimatedArt", """"animatedArt":{"square":{"video":"animated/t1/square.m3u8","poster":"animated/t1/square.jpg","color":"203040","width":90,"height":90}}""")
        answer("getOpenSubsonicExtensions", """"openSubsonicExtensions":[{"name":"octoAnimatedArt","versions":[1]}]""")
        file(
            "square.m3u8",
            "#EXTM3U\n#EXT-X-STREAM-INF:BANDWIDTH=300000,CODECS=\"avc1.64001f\",RESOLUTION=90x90\nv90.m3u8\n".toByteArray(),
        )
        file(
            "v90.m3u8",
            ("#EXTM3U\n#EXT-X-TARGETDURATION:1\n#EXT-X-MAP:URI=\"loop.mp4\",BYTERANGE=\"800@0\"\n" +
                "#EXTINF:1.0,\n#EXT-X-BYTERANGE:1469@800\nloop.mp4\n#EXT-X-ENDLIST\n").toByteArray(),
        )
        file("loop.mp4", fixture.readBytes())
        file("square.jpg", byteArrayOf(1, 2, 3))
    }

    private fun connectionTo(server: FakeServer) =
        Connection(server.client(), SavedServer(server.address, "winters", extensions = listOf("octoAnimatedArt:1")))

    @Test
    fun aDownloadedAlbumKeepsItsLoopAndAnswerAndLetsThemGoWithIt() = runBlocking {
        serverWithLoop().use { server ->
            val client = server.client()
            val kept = KeptLoops(OkHttpClient()) { folder.root }
            kept.keep("srv", setOf("al1")) { client.animatedArt(it) }
            val art = kept.art("srv", "al1")
            assertNotNull(art)
            assertEquals(90, art!!.square!!.width)
            val loop = kept.loop("srv", "al1", LoopShape.Square)
            assertNotNull(loop)
            assertTrue(loop!!.readBytes().contentEquals(fixture.readBytes()))
            assertNotNull(kept.poster("srv", "al1", LoopShape.Square))
            // Asked once: the answer is kept.
            kept.keep("srv", setOf("al1")) { client.animatedArt(it) }
            assertEquals(1, server.endpoints().count { it == "getAnimatedArt" })
            // The album's last song gone, its loops go too.
            kept.keep("srv", emptySet()) { client.animatedArt(it) }
            assertNull(kept.loop("srv", "al1", LoopShape.Square))
            assertNull(kept.art("srv", "al1"))
        }
    }

    @Test
    fun anAlbumWithNoneIsNotAskedAgainAndAnOutageIs() = runBlocking {
        val kept = KeptLoops(OkHttpClient()) { folder.root }
        var asked = 0
        kept.keep("srv", setOf("none")) { asked++; AnimatedArtAnswer.None }
        kept.keep("srv", setOf("none")) { asked++; AnimatedArtAnswer.None }
        assertEquals(1, asked)
        assertNull(kept.art("srv", "none"))
        var tries = 0
        kept.keep("srv", setOf("later")) { tries++; AnimatedArtAnswer.NotNow }
        kept.keep("srv", setOf("later")) { tries++; AnimatedArtAnswer.NotNow }
        assertEquals(2, tries)
    }

    @Test
    fun theModelFetchesALoopToTheShelfOnceAndPrefersAKeptOne() = runBlocking {
        serverWithLoop().use { server ->
            val connection = connectionTo(server)
            val scope = CoroutineScope(SupervisorJob() + Dispatchers.IO)
            val kept = KeptLoops(OkHttpClient()) { File(folder.root, "offline") }
            val model = AnimatedArtModel(OkHttpClient(), scope, { connection }, kept)
            model.shelf = app.winters.octo.animated.LoopShelf(File(folder.root, "shelf"), LOOP_SHELF_BYTES)
            model.follow(connection)
            val art = model.book!!.art("al1")!!
            val clip = art.square!!
            val both = listOf(
                scope.async { model.loopFile("al1", LoopShape.Square, clip, 90, 90) },
                scope.async { model.loopFile("al1", LoopShape.Square, clip, 90, 90) },
            ).awaitAll()
            assertNotNull(both[0])
            assertEquals(both[0], both[1])
            assertEquals(1, server.endpoints().count { it == "loop.mp4" })
            // A downloaded album's own loop plays instead.
            kept.keep(connection.server.id, setOf("al1")) { connection.client.animatedArt(it) }
            val own = model.loopFile("al1", LoopShape.Square, clip, 90, 90)
            assertTrue(own!!.path.contains(KEPT_LOOPS))
            scope.cancel()
        }
    }

    @Test
    fun theSettingReadsItsKeysAndFallsBackToSquare() {
        assertEquals(AnimatedArtSetting.Square, Appearance().animatedArtSetting)
        assertEquals(AnimatedArtSetting.FullScreen, Appearance(animatedArt = "full_screen").animatedArtSetting)
        assertEquals(AnimatedArtSetting.Off, Appearance(animatedArt = "off").animatedArtSetting)
        assertEquals(AnimatedArtSetting.Square, Appearance(animatedArt = "moving").animatedArtSetting)
    }

    @Test
    fun theTallLoopKeepsItsShapeAndIsGoneBeforeTheTitle() {
        // Alone in a 1440x900 player: as tall as the player, 3:4, centered.
        val alone = tallPlacement(900f, 0f, 1440f, 720f, titleTop = 640f, aspect = 0.75f, gap = 0f, leastRamp = 96f)
        assertEquals(675f, alone.width, 0.01f)
        assertEquals(900f, alone.height, 0.01f)
        assertEquals(382.5f, alone.x, 0.01f)
        // Sharp down to an eased band that is gone right at the title.
        assertEquals(640f, alone.fadeEnd, 0.01f)
        assertEquals(496f, alone.fadeStart, 0.01f)
        // Beside the lyrics: as wide as the cover's side, from the left edge.
        val beside = tallPlacement(900f, 0f, 520f, 276f, titleTop = 640f, aspect = 0.75f, gap = 0f, leastRamp = 96f)
        assertEquals(520f, beside.width, 0.01f)
        assertEquals(693.33f, beside.height, 0.01f)
        assertEquals(0f, beside.x, 0.01f)
        // Never enlarged past the player's height, whatever the space.
        val wide = tallPlacement(600f, 0f, 3000f, 1500f, titleTop = null, aspect = 0.75f, gap = 0f, leastRamp = 96f)
        assertEquals(600f, wide.height, 0.01f)
        assertEquals(600f, wide.fadeEnd, 0.01f)
    }

    @Test
    fun theFillsToneGivesTheWordsFullContrast() {
        fun lum(c: Float) = if (c <= 0.03928f) c / 12.92 else ((c + 0.055) / 1.055).pow(2.4)
        fun luminance(r: Float, g: Float, b: Float) = 0.2126 * lum(r) + 0.7152 * lum(g) + 0.0722 * lum(b)
        // A bright sky: dark words, or white ones on a darkened fill; either
        // way 4.5:1 over nearly all of it.
        val sky = List(400) { i -> Triple(0.2f + (i % 20) / 100f, 0.4f, 0.9f) }
        val tone = fillTone(sky)
        val worst = sky.map { (r, g, b) ->
            val k = tone.scale * (1 - tone.lift)
            luminance(r * k + tone.lift, g * k + tone.lift, b * k + tone.lift)
        }.sorted()
        if (tone.white) {
            assertTrue(1.05 / (worst[(worst.size * 0.95).toInt()] + 0.05) >= 4.4)
        } else {
            assertTrue((worst[(worst.size * 0.05).toInt()] + 0.05) / (luminance(DarkInk.red, DarkInk.green, DarkInk.blue) + 0.05) >= 4.4)
        }
        // A dark fill keeps white words as it is.
        val night = List(100) { Triple(0.05f, 0.05f, 0.1f) }
        assertEquals(FillTone(true, 1f, 0f), fillTone(night))
        // A pale one takes dark words.
        val paper = List(100) { Triple(0.95f, 0.93f, 0.9f) }
        assertFalse(fillTone(paper).white)
    }

    @Test
    fun wordsOnAColorPickTheReadableInk() {
        assertEquals(Color.White, inkOn(Color(0xFF101012)))
        assertEquals(DarkInk, inkOn(Color(0xFFF4F0E8)))
    }

    @Test
    fun aBackdropTakesTheClipsColorElseTheCovers() {
        assertEquals(Color(0xFF203040), backdropColor(AnimatedClip(video = "v", color = "203040"), 0x00FF0000))
        assertEquals(Color(0xFFFF0000), backdropColor(AnimatedClip(video = "v"), 0xFFFF0000.toInt()))
    }

    @Test(timeout = 60_000)
    fun aLoopPlaysItsFramesAndHeldItStops() {
        assumeTrue(fixture.isFile && runCatching { loopVideoAvailable() }.getOrDefault(false))
        val play = mutableStateOf(LoopPlay.Play)
        val scene = ImageComposeScene(90, 90, Density(1f)) {
            Box(Modifier.fillMaxSize().background(Color.Black)) { LoopFrames(fixture, play.value, Modifier.fillMaxSize()) }
        }
        fun frame(): Pair<Int, Int> {
            var top = 0
            var bottom = 0
            SwingUtilities.invokeAndWait {
                val image = scene.render(System.nanoTime())
                val bitmap = org.jetbrains.skia.Bitmap.makeFromImage(image)
                top = bitmap.getColor(45, 10)
                bottom = bitmap.getColor(45, 80)
                bitmap.close()
                image.close()
            }
            return top to bottom
        }
        try {
            val until = System.currentTimeMillis() + 5_000
            var seen = frame()
            while (System.currentTimeMillis() < until && (seen.first shr 16 and 0xFF) < 200) {
                Thread.sleep(30)
                seen = frame()
            }
            // Faded in from nothing over black: red over blue.
            assertTrue("top ${Integer.toHexString(seen.first)}", (seen.first shr 16 and 0xFF) > 200 && (seen.first and 0xFF) < 60)
            assertTrue("bottom ${Integer.toHexString(seen.second)}", (seen.second and 0xFF) > 200 && (seen.second shr 16 and 0xFF) < 60)
            // Held, the frame stays.
            repeat(20) { frame(); Thread.sleep(30) }
            play.value = LoopPlay.Hold
            repeat(5) { frame(); Thread.sleep(30) }
            val held = frame()
            repeat(10) { frame(); Thread.sleep(30) }
            assertEquals(held, frame())
        } finally {
            SwingUtilities.invokeAndWait { scene.close() }
        }
    }
}
