package app.winters.octo.desktop.ui

import app.winters.octo.desktop.system.OctopusPainter
import androidx.compose.ui.graphics.painter.Painter
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue
import androidx.compose.ui.ImageComposeScene
import androidx.compose.ui.graphics.painter.BitmapPainter
import androidx.compose.ui.graphics.toComposeImageBitmap
import androidx.compose.ui.unit.Density
import org.jetbrains.skia.EncodedImageFormat
import org.jetbrains.skia.Image
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test
import java.io.File

// The opening's octopus on a clock the test moves: it comes in within a
// moment, says so once, and fades away only after the app has drawn.
// OCTO_SHOTS=1 also saves frames as build/shots/opening-*.png to look at.
class OpeningTest {
    private val octopus = OctopusPainter()

    private class Run(calm: Boolean, octopus: Painter) {
        var leaving by mutableStateOf(false)
        var entered = 0
        var gone = 0
        val scene = ImageComposeScene(720, 450, Density(1.5f)) {
            Opening(octopus, calm = calm, leaving = leaving, onEntered = { entered++ }, onGone = { gone++ })
        }

        fun at(ms: Long) = scene.render(ms * 1_000_000)
    }

    private fun save(image: org.jetbrains.skia.Image, name: String) {
        if (System.getenv("OCTO_SHOTS") != "1") return
        val out = File("build/shots").apply { mkdirs() }
        File(out, "$name.png").writeBytes(image.encodeToData(EncodedImageFormat.PNG)!!.bytes)
    }

    @Test
    fun theOctopusComesInWithinAMomentAndSaysSoOnce() {
        val run = Run(calm = false, octopus)
        var t = 0L
        save(run.at(t), "opening-0000")
        while (run.entered == 0 && t < 1_000) {
            t += 16
            val frame = run.at(t)
            if (t in listOf(48L, 96L, 160L, 240L)) save(frame, "opening-%04d".format(t))
        }
        assertEquals(1, run.entered)
        assertTrue("in within half a second, not $t ms", t in 100..500)
        repeat(40) { t += 16; run.at(t) }
        save(run.at(t), "opening-settled")
        assertEquals("said once", 1, run.entered)
        assertEquals(0, run.gone)
        run.scene.close()
    }

    @Test
    fun itFadesAwayOnlyOnceTheAppHasDrawn() {
        val run = Run(calm = false, octopus)
        var t = 0L
        repeat(40) { t += 16; run.at(t) }
        run.leaving = true
        t += 16; run.at(t)
        assertEquals("not before the app's own frames", 0, run.gone)
        while (run.gone == 0 && t < 2_000) {
            t += 16
            val frame = run.at(t)
            if (run.gone == 0 && t % 64 == 0L) save(frame, "opening-leave-%04d".format(t))
        }
        assertEquals(1, run.gone)
        assertTrue(t < 2_000)
        run.scene.close()
    }

    @Test
    fun calmMotionOnlyFadesInQuickly() {
        val run = Run(calm = true, octopus)
        var t = 0L
        run.at(t)
        while (run.entered == 0 && t < 1_000) { t += 16; run.at(t) }
        assertEquals(1, run.entered)
        assertTrue("a quick fade, not $t ms", t <= 260)
        assertFalse(run.gone > 0)
        run.scene.close()
    }
}
