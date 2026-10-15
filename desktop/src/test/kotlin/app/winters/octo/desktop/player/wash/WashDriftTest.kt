package app.winters.octo.desktop.player.wash

import androidx.compose.ui.ImageComposeScene
import androidx.compose.ui.unit.Density
import app.winters.octo.player.immersive.WashTuning
import app.winters.octo.player.immersive.paceBpm
import org.jetbrains.skia.Bitmap
import org.jetbrains.skia.Image
import kotlin.math.PI
import kotlin.math.abs
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertTrue

// The background must drift, not flicker. A turn once went to Skia in the
// wrong unit and spun the picture thousands of times too fast: frames a
// tenth of a second apart were different pictures, a strobe.
class WashDriftTest {
    @Test
    fun aTurnIsTheAngleAsked() {
        val quarter = WashRenderer().turned((PI / 2).toFloat()).mat
        assertEquals(0f, quarter[0], 1e-5f)
        assertEquals(-1f, quarter[1], 1e-5f)
        assertEquals(1f, quarter[3], 1e-5f)
        assertEquals(0f, quarter[4], 1e-5f)
    }

    @Test
    fun aTenthOfASecondChangesThePictureOnlyALittle() {
        val icon = app.winters.octo.desktop.system.OctopusArt.icon(512, shape = null)
        val cover = WashCovers.prepared("drift-test", icon, WashTuning())
        // The full player's own pace, faster than the sign-in's.
        val scene = ImageComposeScene(320, 200, Density(1f)) {
            ImmersiveWash(cover, paceBpm(null, false), 60, 0.25f, moving = true, dolly = { 1f })
        }
        val tenth = 100_000_000L
        var t = 0L
        var last: IntArray? = null
        val changes = mutableListOf<Double>()
        repeat(40) { i ->
            repeat(6) { scene.render(t); t += tenth / 6 }
            val now = pixels(scene.render(t))
            // Past the fade in.
            if (i > 20) last?.let { changes += change(it, now) }
            last = now
        }
        scene.close()
        // A strobe changed every pixel by about 30 levels in a tenth of a
        // second; a drift moves a couple at most (the grain alone is half one).
        assertTrue(changes.average() < 3.0, "the picture changed by ${changes.average()} levels in a tenth of a second")
    }

    private fun pixels(image: Image): IntArray {
        val bitmap = Bitmap.makeFromImage(image)
        return IntArray(bitmap.width * bitmap.height) { i -> bitmap.getColor(i % bitmap.width, i / bitmap.width) }
    }

    private fun change(a: IntArray, b: IntArray): Double {
        var sum = 0L
        for (i in a.indices) {
            val x = a[i]
            val y = b[i]
            sum += abs((x shr 16 and 0xFF) - (y shr 16 and 0xFF)) + abs((x shr 8 and 0xFF) - (y shr 8 and 0xFF)) + abs((x and 0xFF) - (y and 0xFF))
        }
        return sum.toDouble() / a.size / 3
    }
}
