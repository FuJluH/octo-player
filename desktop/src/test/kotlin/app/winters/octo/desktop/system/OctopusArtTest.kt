package app.winters.octo.desktop.system

import org.jetbrains.skia.Bitmap
import org.jetbrains.skia.Image
import org.jetbrains.skia.Surface
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Assume.assumeTrue
import org.junit.Test
import java.io.File
import kotlin.math.abs
import kotlin.math.sqrt

// The octopus drawn from its vector: placed by how far its ink reaches, as
// tools/appicon/make_app_icon.py places it, and drawn as the pictures it
// replaces were.
class OctopusArtTest {
    // How far the ink reaches from the box's centre, measured as the icon
    // script measures it: on a drawing four times the size, ink is alpha
    // over half.
    private fun measuredReach(): Float {
        val w = (OctopusArt.Width * 4).toInt()
        val h = (OctopusArt.Height * 4).toInt()
        val surface = Surface.makeRasterN32Premul(maxOf(w, h), maxOf(w, h))
        // Drawn at a share of Reach over the side, the octopus is at its own
        // size, its box centred in the square.
        val side = maxOf(OctopusArt.Width, OctopusArt.Height)
        surface.canvas.scale(4f, 4f)
        OctopusArt.drawOctopus(surface.canvas, side, OctopusArt.Reach / side)
        val bitmap = Bitmap.makeFromImage(surface.makeImageSnapshot())
        val centre = side * 2f
        var far = 0f
        for (y in 0 until bitmap.height) for (x in 0 until bitmap.width) {
            if ((bitmap.getColor(x, y) ushr 24) > 127) {
                val d = sqrt((x + 0.5f - centre) * (x + 0.5f - centre) + (y + 0.5f - centre) * (y + 0.5f - centre))
                if (d > far) far = d
            }
        }
        return far / 4f
    }

    @Test
    fun theOctopusIsPlacedByItsInksReach() {
        val reach = measuredReach()
        println("measured reach $reach")
        assertEquals(OctopusArt.Reach, reach, 0.5f)
    }

    @Test
    fun theIconHasClearCornersAndTheTileInItsMiddle() {
        for (size in WindowIconSizes) {
            val bitmap = Bitmap.makeFromImage(OctopusArt.icon(size))
            assertTrue("$size corner", (bitmap.getColor(0, 0) ushr 24) < 64)
            assertEquals("$size middle", 255, bitmap.getColor(size / 2, size / 2) ushr 24)
        }
    }

    // With OCTO_OLD_OPENING naming the opening's old 336 picture, the
    // octopus drawn from the vector at that size matches it.
    @Test
    fun theOpeningOctopusLooksAsThePictureDid() {
        val old = System.getenv("OCTO_OLD_OPENING")?.let(::File)?.takeIf { it.isFile }
        assumeTrue(old != null)
        val before = Bitmap.makeFromImage(Image.makeFromEncoded(old!!.readBytes()))
        val surface = Surface.makeRasterN32Premul(before.width, before.height)
        OctopusArt.drawOctopus(surface.canvas, before.width.toFloat(), OctopusArt.OpeningReach)
        val after = Bitmap.makeFromImage(surface.makeImageSnapshot())
        var total = 0L
        var worst = 0
        for (y in 0 until before.height) for (x in 0 until before.width) {
            val a = before.getColor(x, y)
            val b = after.getColor(x, y)
            for (shift in listOf(24, 16, 8, 0)) {
                val d = abs((a shr shift and 0xFF) - (b shr shift and 0xFF))
                total += d
                if (d > worst) worst = d
            }
        }
        val mean = total.toDouble() / (before.width * before.height * 4)
        println("opening vs old picture: mean difference $mean of 255, worst $worst")
        assertTrue("mean difference $mean", mean < 2.0)
        // With OCTO_SHOTS_DIR, the old picture scaled down as the window drew
        // it, and the vector drawn at that size: the opening (112) and About (56).
        val out = System.getenv("OCTO_SHOTS_DIR")?.let(::File) ?: return
        out.mkdirs()
        val picture = Image.makeFromEncoded(old.readBytes())
        for (side in listOf(112, 56)) {
            val scaled = Surface.makeRasterN32Premul(side, side).apply {
                canvas.clear(0xFF0C0C0D.toInt())
                canvas.drawImageRect(picture, org.jetbrains.skia.Rect.makeWH(picture.width.toFloat(), picture.height.toFloat()), org.jetbrains.skia.Rect.makeWH(side.toFloat(), side.toFloat()), org.jetbrains.skia.FilterMipmap(org.jetbrains.skia.FilterMode.LINEAR, org.jetbrains.skia.MipmapMode.LINEAR), null, true)
            }
            val drawn = Surface.makeRasterN32Premul(side, side).apply {
                canvas.clear(0xFF0C0C0D.toInt())
                OctopusArt.drawOctopus(canvas, side.toFloat(), OctopusArt.OpeningReach)
            }
            File(out, "octopus-before-$side.png").writeBytes(scaled.makeImageSnapshot().encodeToData(org.jetbrains.skia.EncodedImageFormat.PNG)!!.bytes)
            File(out, "octopus-after-$side.png").writeBytes(drawn.makeImageSnapshot().encodeToData(org.jetbrains.skia.EncodedImageFormat.PNG)!!.bytes)
        }
    }
}
