package app.winters.octo.desktop.lyrics

import androidx.compose.runtime.CompositionLocalProvider
import androidx.compose.runtime.currentComposer
import androidx.compose.runtime.tooling.CompositionData
import androidx.compose.runtime.tooling.CompositionGroup
import androidx.compose.runtime.tooling.LocalInspectionTables
import androidx.compose.ui.ImageComposeScene
import androidx.compose.ui.unit.Density
import app.winters.octo.desktop.perf.Recompositions
import app.winters.octo.lyrics.LyricsLook
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertTrue
import org.junit.Test
import java.util.Collections

// While a song plays, the flowing lyrics compose nothing frame to frame,
// draw again only the lines whose words move, and show the lines resting
// at a blur from blurred copies rather than blurring them every frame.
class FlowingFramesTest {
    private val frame = 16_666_667L

    @Test
    fun playingRedrawsOnlyMovingLinesAndBlursFromCopies() {
        val tables = Collections.synchronizedSet(HashSet<CompositionData>())
        var main: CompositionData? = null
        var nanos = 0L
        val scene = ImageComposeScene(480, 640, Density(1f)) {
            main = currentComposer.compositionData
            CompositionLocalProvider(LocalInspectionTables provides tables) {
                FlowingLyrics(
                    madeUpLyrics(),
                    playing = true,
                    trackKey = "frames",
                    positionMs = { 20_000L + nanos / 1_000_000 },
                    speed = { 1f },
                    offsetMs = 0,
                    outputOffsetMs = 0,
                    look = LyricsLook(),
                    calm = false,
                    onSeek = {},
                )
            }
        }
        // Two seconds of song, with time for the copies to be made.
        repeat(120) {
            scene.render(nanos).close()
            nanos += frame
            Thread.sleep(2)
        }
        val engine = main?.lyricEngine()
        assertNotNull("the engine", engine)
        engine!!
        val pictures = synchronized(tables) { tables.toList() }.firstNotNullOfOrNull { it.linePictures() }
        assertNotNull("the lines' pictures", pictures)
        pictures!!

        // One second more, counted.
        val counted = 60
        var redrawn = 0
        var onScreen = 0
        var blurred = 0
        var copied = 0
        val recompositions = Recompositions()
        repeat(counted) {
            val before = IntArray(engine.states.size) { engine.states[it].drawVersion.intValue }
            scene.render(nanos).close()
            nanos += frame
            Thread.sleep(2)
            val shown = engine.shown.value
            onScreen += shown.count()
            redrawn += shown.count { before[it] != engine.states[it].drawVersion.intValue }
            for (index in shown) {
                if (blurPx(engine.states[index], 1f) <= 0f) continue
                blurred++
                if (pictures.line(index).copy.value != null) copied++
            }
        }
        val (scopes, _) = recompositions.take()
        recompositions.close()
        scene.close()
        println("Over $counted frames: $scopes scopes composed, $redrawn of $onScreen lines drawn again, $copied of $blurred blurred lines from copies")

        assertTrue("composing $scopes scopes in $counted frames", scopes < counted / 2)
        assertTrue("redrawing $redrawn of $onScreen lines", redrawn * 4 < onScreen)
        assertTrue("$copied of $blurred blurred lines from copies", copied * 2 > blurred)
    }

    private fun CompositionData.linePictures(): LinePictures? {
        fun walk(group: CompositionGroup): LinePictures? {
            group.data.forEach { if (it is LinePictures) return it }
            group.compositionGroups.forEach { child -> walk(child)?.let { return it } }
            return null
        }
        compositionGroups.forEach { group -> walk(group)?.let { return it } }
        return null
    }
}
