package app.winters.octo.desktop.lyrics

import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.ui.ImageComposeScene
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.unit.Density
import app.winters.octo.lyrics.LyricsLook
import org.jetbrains.skia.Bitmap
import org.jetbrains.skia.EncodedImageFormat
import org.jetbrains.skia.Image
import org.jetbrains.skia.ImageInfo
import org.junit.Assume.assumeTrue
import org.junit.Test
import java.io.File
import kotlin.math.abs

// Pictures of the flowing lyrics at set moments of a song, each held long
// enough for anything made in the background to arrive, written to
// build/shots/lyrics/. With OCTO_SHOTS_REFERENCE set to a folder of earlier
// pictures, each is compared with its namesake there and the difference
// printed, to show a change in how the lines are drawn left them looking
// the same. Only runs when asked:
// OCTO_SHOTS=1 ./gradlew :desktop:test --tests '*LyricsLookShotsTest*'.
class LyricsLookShotsTest {
    @Test
    fun drawTheLyricsAtSetMoments() {
        assumeTrue(System.getenv("OCTO_SHOTS") == "1")
        val out = File("build/shots/lyrics").apply { mkdirs() }
        val reference = System.getenv("OCTO_SHOTS_REFERENCE")?.let(::File)
        val lyrics = madeUpLyrics()
        for (density in listOf(1f, 2f)) {
            for (moment in MOMENTS) {
                var sceneNanos = 0L
                val scene = ImageComposeScene((720 * density).toInt(), (900 * density).toInt(), Density(density)) {
                    Box(Modifier.fillMaxSize().background(Color(0xFF101014))) {
                        FlowingLyrics(
                            lyrics,
                            playing = true,
                            trackKey = "shots",
                            positionMs = { START_MS + sceneNanos / 1_000_000 },
                            speed = { 1f },
                            offsetMs = 0,
                            outputOffsetMs = 0,
                            look = LyricsLook(),
                            calm = false,
                            onSeek = {},
                        )
                    }
                }
                // Played at 30 frames a second up to the moment, then held
                // there (frames at the same moment move nothing) while the
                // background work catches up.
                while (sceneNanos < moment) {
                    scene.render(sceneNanos).close()
                    sceneNanos += FRAME_NANOS
                }
                sceneNanos = moment
                val until = System.nanoTime() + HOLD_NANOS
                while (System.nanoTime() < until) {
                    scene.render(sceneNanos).close()
                    Thread.sleep(10)
                }
                val image = scene.render(sceneNanos)
                scene.close()
                val name = "lyrics-${density.toInt()}x-${moment / 1_000_000}ms.png"
                File(out, name).writeBytes(image.encodeToData(EncodedImageFormat.PNG)!!.bytes)
                reference?.let { File(it, name) }?.takeIf { it.exists() }?.let { earlier ->
                    val (largest, mean, changed) = difference(Image.makeFromEncoded(earlier.readBytes()), image, File(out, "diff-$name"))
                    println("%-28s largest %3d  mean %.3f  pixels changed by more than 8: %d".format(name, largest, mean, changed))
                }
                image.close()
            }
        }
    }

    // The largest difference in any colour of any pixel, the mean over all
    // of them, and how many pixels differ by more than a few steps. Where
    // they differ is written to `map`, eight times brighter.
    private fun difference(a: Image, b: Image, map: File): Triple<Int, Double, Int> {
        val first = Bitmap.makeFromImage(a)
        val second = Bitmap.makeFromImage(b)
        val shades = ByteArray(first.width * first.height * 4)
        var largest = 0
        var total = 0L
        var changed = 0
        for (y in 0 until minOf(first.height, second.height)) {
            for (x in 0 until minOf(first.width, second.width)) {
                val p = first.getColor(x, y)
                val q = second.getColor(x, y)
                var most = 0
                for (shift in intArrayOf(0, 8, 16, 24)) {
                    val d = abs((p shr shift and 0xFF) - (q shr shift and 0xFF))
                    total += d
                    most = maxOf(most, d)
                }
                largest = maxOf(largest, most)
                if (most > 8) changed++
                val shade = minOf(255, most * 8).toByte()
                val at = (y * first.width + x) * 4
                shades[at] = shade
                shades[at + 1] = shade
                shades[at + 2] = shade
                shades[at + 3] = 0xFF.toByte()
            }
        }
        Image.makeRaster(ImageInfo.makeN32Premul(first.width, first.height), shades, first.width * 4).use {
            map.writeBytes(it.encodeToData(EncodedImageFormat.PNG)!!.bytes)
        }
        return Triple(largest, total.toDouble() / (first.width * first.height * 4), changed)
    }

    private companion object {
        const val START_MS = 20_000L
        const val FRAME_NANOS = 33_333_333L
        const val HOLD_NANOS = 1_500_000_000L

        // Mid-line, just after a line change, a while later, and in the
        // interlude.
        val MOMENTS = listOf(1_000_000_000L, 2_300_000_000L, 9_000_000_000L, 22_000_000_000L)
    }
}
