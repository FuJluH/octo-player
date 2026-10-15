package app.winters.octo.desktop.ui

import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.runtime.CompositionLocalProvider
import androidx.compose.ui.ExperimentalComposeUiApi
import androidx.compose.ui.ImageComposeScene
import androidx.compose.ui.Modifier
import androidx.compose.ui.geometry.Rect
import androidx.compose.ui.semantics.SemanticsNode
import androidx.compose.ui.unit.Density
import app.winters.octo.design.ProvideWindowLook
import app.winters.octo.desktop.a11y.A11yScene
import app.winters.octo.desktop.a11y.name
import app.winters.octo.desktop.library.LocalCovers
import app.winters.octo.desktop.system.MINI_SQUARE_HEIGHT
import app.winters.octo.desktop.system.MINI_SQUARE_WIDTH
import app.winters.octo.desktop.system.MiniActions
import app.winters.octo.desktop.system.MiniPlayerView
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
import javax.swing.SwingUtilities
import kotlin.math.abs

// The row of the song's name in the full player and the mini player's
// cover shape, measured from the pixels drawn: the heart's middle on the
// middle of the name's capitals, the heart a step quieter than the name,
// and the artist close under the name. With OCTO_SHOTS=1 it saves the
// pictures (to OCTO_SHOTS_DIR, else build/shots).
@OptIn(ExperimentalComposeUiApi::class)
class TitleRowTest {
    @get:Rule val folder = TemporaryFolder()

    // A dark cover, so the words stay white over the wash.
    private val cover: ByteArray = run {
        val surface = Surface.makeRasterN32Premul(300, 300)
        surface.canvas.clear(0xFF1B2A4A.toInt())
        surface.canvas.drawCircle(150f, 150f, 60f, Paint().apply { color = 0xFF3A4A70.toInt() })
        surface.makeImageSnapshot().encodeToData(EncodedImageFormat.PNG)!!.bytes
    }

    @Test(timeout = 300_000)
    fun theFullPlayersHeartSitsOnTheNamesCapitals() {
        A11yScene(folder.newFolder(), cover = cover, coverId = "title-row").use { s ->
            s.onUi {
                s.app.play(s.app.library!!.index!!.songs.filter { it.title == "Airbag" }, 0)
                s.app.player.togglePlay()
                s.app.fullPlayer = true
                s.app.playerPanel?.let(s.app::togglePlayerPanel)
            }
            val image = s.settle(2_500)
            save(image, "title-row-full-player")
            val row = measure(image, s.nodes(merged = true), "Airbag", "Radiohead", "Add to favorites")
            report("full player", row)
            assertTrue("the heart is on the name's capitals: $row", abs(row.heartMiddle - row.capMiddle) <= 1.5f)
            assertTrue("the heart is quieter than the name: $row", row.heartInk < row.titleInk * 0.85f)
            assertTrue("the artist sits close under the name: $row", row.artistGap in 2f..14f)
        }
    }

    @Test(timeout = 300_000)
    fun theMiniPlayersHeartSitsOnTheNamesCapitals() {
        A11yScene(folder.newFolder(), cover = cover, coverId = "title-row-mini").use { s ->
            s.onUi {
                s.app.play(s.app.library!!.index!!.songs.filter { it.title == "Airbag" }, 0)
                s.app.player.togglePlay()
            }
            s.settle(500).close()
            lateinit var mini: ImageComposeScene
            SwingUtilities.invokeAndWait {
                mini = ImageComposeScene(MINI_SQUARE_WIDTH.toInt(), MINI_SQUARE_HEIGHT.toInt(), Density(1f)) {
                    ProvideWindowLook(reduceMotion = false) {
                        CompositionLocalProvider(LocalCovers provides s.app.connection?.client) {
                            Box(Modifier.fillMaxSize()) {
                                MiniPlayerView(s.app, panel = null, pinned = false, actions = MiniActions({}, { _, _ -> }, {}, {}), dragArea = {})
                            }
                        }
                    }
                }
            }
            try {
                var image: Image? = null
                val begin = System.nanoTime()
                while (System.nanoTime() - begin < 2_000_000_000L) {
                    image?.close()
                    SwingUtilities.invokeAndWait { image = mini.render(System.nanoTime()) }
                    Thread.sleep(30)
                }
                save(image!!, "title-row-mini-cover")
                val nodes = mutableListOf<SemanticsNode>()
                fun walk(node: SemanticsNode) {
                    nodes += node
                    node.children.forEach(::walk)
                }
                mini.semanticsOwners.forEach { walk(it.rootSemanticsNode) }
                val row = measure(image!!, nodes, "Airbag", "Radiohead", "Add to favorites")
                report("mini player", row)
                assertTrue("the heart is on the name's capitals: $row", abs(row.heartMiddle - row.capMiddle) <= 1.5f)
                assertTrue("the heart is quieter than the name: $row", row.heartInk < row.titleInk * 0.85f)
            } finally {
                SwingUtilities.invokeAndWait { mini.close() }
            }
        }
    }

    // Where the name's capitals and the heart are drawn, in pixels down the
    // picture, how bright each is, and the room between the name and the
    // artist under it.
    data class TitleRow(val capTop: Int, val baseline: Int, val heartTop: Int, val heartBottom: Int, val artistGap: Float, val titleInk: Float, val heartInk: Float) {
        val capMiddle: Float get() = (capTop + baseline) / 2f
        val heartMiddle: Float get() = (heartTop + heartBottom) / 2f
    }

    private fun measure(image: Image, nodes: List<SemanticsNode>, title: String, artist: String, heart: String): TitleRow {
        val bitmap = Bitmap.makeFromImage(image)
        fun boundsOf(name: String): Rect = nodes.filter { it.name() == name }.maxByOrNull { it.boundsInRoot.top }?.boundsInRoot
            ?: error("no $name in ${nodes.mapNotNull { it.name() }}")
        val titleBox = boundsOf(title)
        val artistBox = boundsOf(artist)
        val heartBox = boundsOf(heart)
        // The first capital: the leftmost columns of the name.
        val capHeight = titleBox.height * 0.5f
        val letter = ink(bitmap, titleBox.left.toInt(), (titleBox.left + capHeight * 0.6f).toInt(), titleBox.top.toInt(), titleBox.bottom.toInt())
        val words = ink(bitmap, titleBox.left.toInt(), titleBox.right.toInt(), titleBox.top.toInt(), titleBox.bottom.toInt())
        val artistInk = ink(bitmap, artistBox.left.toInt(), (artistBox.left + artistBox.height * 0.4f).toInt(), artistBox.top.toInt(), artistBox.bottom.toInt())
        val glyph = ink(bitmap, heartBox.left.toInt(), heartBox.right.toInt(), heartBox.top.toInt(), heartBox.bottom.toInt())
        return TitleRow(letter.top, letter.bottom, glyph.top, glyph.bottom, (artistInk.top - words.bottom).toFloat(), letter.brightest, glyph.brightest)
    }

    private class Ink(val top: Int, val bottom: Int, val brightest: Float)

    // The rows of a box holding words or an icon lighter than what is
    // around them, and the brightest of it, against the box's corner.
    private fun ink(bitmap: Bitmap, left: Int, right: Int, top: Int, bottom: Int): Ink {
        val back = light(bitmap.getColor(left.coerceAtLeast(0), top.coerceAtLeast(0)))
        var first = -1
        var last = -1
        var brightest = 0f
        for (y in top.coerceAtLeast(0) until bottom.coerceAtMost(bitmap.height)) {
            for (x in left.coerceAtLeast(0) until right.coerceAtMost(bitmap.width)) {
                val l = light(bitmap.getColor(x, y))
                if (l - back > INK_STEP) {
                    if (first < 0) first = y
                    last = y
                    brightest = maxOf(brightest, l)
                }
            }
        }
        return Ink(first, last, brightest)
    }

    private fun light(argb: Int): Float = 0.2126f * (argb shr 16 and 0xFF) + 0.7152f * (argb shr 8 and 0xFF) + 0.0722f * (argb and 0xFF)

    private fun report(where: String, row: TitleRow) {
        println(
            "$where: capitals ${row.capTop}..${row.baseline} (middle ${row.capMiddle}), heart ${row.heartTop}..${row.heartBottom} (middle ${row.heartMiddle}), " +
                "off by ${row.heartMiddle - row.capMiddle} px; name ink ${row.titleInk}, heart ink ${row.heartInk}; name to artist ${row.artistGap} px",
        )
    }

    private fun save(image: Image, name: String) {
        if (System.getenv("OCTO_SHOTS") != "1") return
        val out = File(System.getenv("OCTO_SHOTS_DIR") ?: "build/shots").apply { mkdirs() }
        File(out, "$name.png").writeBytes(image.encodeToData(EncodedImageFormat.PNG)!!.bytes)
    }

    private companion object {
        const val INK_STEP = 60f
    }
}
