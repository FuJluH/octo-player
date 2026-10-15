package app.winters.octo.desktop.system

import app.winters.octo.desktop.settings.AppSettings
import app.winters.octo.desktop.settings.SettingsStore
import app.winters.octo.desktop.settings.WindowSpot
import app.winters.octo.desktop.window.ScreenArea
import org.junit.Assert.assertArrayEquals
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Rule
import org.junit.Test
import org.junit.rules.TemporaryFolder
import java.awt.image.BufferedImage
import java.io.ByteArrayInputStream
import java.io.File
import java.nio.ByteBuffer
import java.nio.ByteOrder
import javax.imageio.ImageIO

// The settings, the icon files and where the mini player opens.
class SystemFilesTest {
    @get:Rule val folder = TemporaryFolder()

    @Test
    fun systemSettingsSurviveARestart() {
        val file = File(folder.root, "settings.json")
        val prefs = SystemPrefs(closeToTray = true, nowPlayingNotices = true, miniPlayerOpen = true, miniPlayer = WindowSpot(10f, 20f, 400f, 130f))
        SettingsStore(file).update { it.copy(system = prefs) }
        assertEquals(prefs, SettingsStore(file).current.system)
    }

    @Test
    fun systemSettingsDefaultToOff() {
        val defaults = AppSettings().system
        assertFalse(defaults.closeToTray)
        assertFalse(defaults.nowPlayingNotices)
        assertFalse(defaults.miniPlayerOpen)
        val file = File(folder.root, "settings.json")
        file.writeText("""{"sidePanel":"queue"}""")
        assertEquals("a file from before these settings still reads", SystemPrefs(), SettingsStore(file).current.system)
    }

    private val screens = listOf(ScreenArea(0f, 0f, 1920f, 1040f), ScreenArea(1920f, 0f, 1280f, 1024f))

    @Test
    fun theMiniPlayerFirstOpensInTheBottomRightCorner() {
        assertEquals(WindowSpot(1920f - MINI_WIDTH - 24f, 1040f - MINI_HEIGHT - 24f, MINI_WIDTH, MINI_HEIGHT), placeMiniPlayer(null, screens))
    }

    @Test
    fun theMiniPlayerReturnsWhereItWas() {
        val spot = WindowSpot(2000f, 100f, 420f, 140f)
        assertEquals(spot, placeMiniPlayer(spot, screens))
    }

    @Test
    fun aMiniPlayerOffEveryScreenComesBack() {
        val gone = WindowSpot(5000f, 5000f, 420f, 140f)
        val placed = placeMiniPlayer(gone, screens)
        assertEquals(1920f - 420f - 24f, placed.x)
        assertEquals(420f, placed.width)
        val halfOff = placeMiniPlayer(WindowSpot(1800f, 950f, 380f, 124f), screens.take(1))
        assertEquals("pulled inside the screen", 1920f - 380f, halfOff.x)
        assertEquals(1040f - 124f, halfOff.y)
    }

    @Test
    fun theMiniPlayerKeepsToItsSizes() {
        val huge = placeMiniPlayer(WindowSpot(0f, 0f, 3000f, 3000f), screens)
        assertEquals(MINI_MAX_WIDTH, huge.width)
        assertEquals(MINI_MAX_HEIGHT, huge.height)
        val tiny = placeMiniPlayer(WindowSpot(0f, 0f, 10f, 10f), screens)
        assertEquals(MINI_MIN_WIDTH, tiny.width)
        assertEquals(MINI_MIN_HEIGHT, tiny.height)
    }

    private val art = BufferedImage(64, 64, BufferedImage.TYPE_INT_ARGB).apply {
        val g = createGraphics()
        g.color = java.awt.Color(0x6A, 0x4C, 0xFF)
        g.fillRect(0, 0, 64, 64)
        g.dispose()
    }

    @Test
    fun roundedIconsHaveClearCornersAndAFullMiddle() {
        val icon = roundedIcon(art, 128, FlatShape)
        assertEquals(128, icon.width)
        assertEquals("a clear corner", 0, icon.getRGB(1, 1) ushr 24)
        assertEquals("an opaque middle", 0xFF, icon.getRGB(64, 64) ushr 24)
        val mac = roundedIcon(art, 128, MacShape)
        assertEquals("room around the macOS icon", 0, mac.getRGB(8, 64) ushr 24)
    }

    // The mask sits at fractional pixels; the art once stopped a pixel short
    // of it, leaving a white line down the right and along the bottom.
    @Test
    fun roundedIconsHaveNoWhiteEdge() {
        for (size in IcoSizes + listOf(512)) {
            for (shape in listOf(FlatShape, MacShape)) {
                val icon = roundedIcon(art, size, shape)
                for (i in 0 until size) {
                    for ((x, y) in listOf(size - 1 - i to size / 2, size / 2 to size - 1 - i, i to size / 2)) {
                        val rgb = icon.getRGB(x, y)
                        if (rgb ushr 24 == 0) continue
                        assertTrue("no white at $x,$y of $size", (rgb shr 8 and 0xFF) < 0x80)
                    }
                }
            }
        }
    }

    @Test
    fun icoFilesListEachPicture() {
        val pictures = listOf(16, 256).map { it to pngBytes(roundedIcon(art, it, FlatShape)) }
        val bytes = icoBytes(pictures)
        val head = ByteBuffer.wrap(bytes).order(ByteOrder.LITTLE_ENDIAN)
        assertEquals(0, head.getShort(0).toInt())
        assertEquals("an icon, not a cursor", 1, head.getShort(2).toInt())
        assertEquals(2, head.getShort(4).toInt())
        assertEquals(16, bytes[6].toInt())
        assertEquals("256 is written as 0", 0, bytes[6 + 16].toInt())
        val offset = head.getInt(6 + 12)
        val size = head.getInt(6 + 8)
        val first = bytes.copyOfRange(offset, offset + size)
        assertArrayEquals(pictures[0].second, first)
        assertEquals(16, ImageIO.read(ByteArrayInputStream(first)).width)
    }

    @Test
    fun icnsFilesCarryTheirLengthAndTypes() {
        val png = pngBytes(roundedIcon(art, 32, MacShape))
        val bytes = icnsBytes(listOf("icp5" to png, "ic11" to png))
        val head = ByteBuffer.wrap(bytes).order(ByteOrder.BIG_ENDIAN)
        assertEquals("icns", String(bytes, 0, 4, Charsets.US_ASCII))
        assertEquals(bytes.size, head.getInt(4))
        assertEquals("icp5", String(bytes, 8, 4, Charsets.US_ASCII))
        assertEquals(8 + png.size, head.getInt(12))
        assertEquals("ic11", String(bytes, 8 + 8 + png.size, 4, Charsets.US_ASCII))
    }

    @Test
    fun theIconFilesAreWritten() {
        val out = folder.newFolder("icons")
        writeIconFiles(out)
        listOf("octo.png", "octo.ico", "octo.icns").forEach { assertTrue(it, File(out, it).length() > 0) }
        assertEquals(512, ImageIO.read(File(out, "octo.png")).width)
    }

    @Test
    fun theIcoHoldsEverySizeEachDrawnOnItsOwn() {
        val out = folder.newFolder("ico")
        writeIconFiles(out)
        val bytes = File(out, "octo.ico").readBytes()
        val head = ByteBuffer.wrap(bytes).order(ByteOrder.LITTLE_ENDIAN)
        val count = head.getShort(4).toInt()
        assertEquals(IcoSizes.size, count)
        val seen = mutableListOf<Int>()
        for (i in 0 until count) {
            val at = 6 + i * 16
            val side = (bytes[at].toInt() and 0xFF).let { if (it == 0) 256 else it }
            val length = head.getInt(at + 8)
            val offset = head.getInt(at + 12)
            val entry = bytes.copyOfRange(offset, offset + length)
            val png = entry[0] == 0x89.toByte() && entry[1] == 'P'.code.toByte()
            // The 256 is a PNG; every smaller one is a 32-bit bitmap of its own size.
            if (side >= 256) {
                assertTrue("256 is a PNG", png)
            } else {
                assertTrue("$side is a bitmap", !png)
                val info = ByteBuffer.wrap(entry).order(ByteOrder.LITTLE_ENDIAN)
                assertEquals(40, info.getInt(0))
                assertEquals(side, info.getInt(4))
                assertEquals(side * 2, info.getInt(8))
                assertEquals(32, info.getShort(14).toInt())
            }
            seen += side
        }
        assertEquals(IcoSizes, seen)
        // Each size is its own drawing: the 16 is not the 32 halved.
        val sixteen = OctopusArt.iconImage(16)
        val halved = java.awt.image.BufferedImage(16, 16, java.awt.image.BufferedImage.TYPE_INT_ARGB).also {
            val g = it.createGraphics()
            g.setRenderingHint(java.awt.RenderingHints.KEY_INTERPOLATION, java.awt.RenderingHints.VALUE_INTERPOLATION_BILINEAR)
            g.drawImage(OctopusArt.iconImage(32), 0, 0, 16, 16, null)
            g.dispose()
        }
        assertTrue((0 until 16).any { x -> (0 until 16).any { y -> sixteen.getRGB(x, y) != halved.getRGB(x, y) } })
    }

    @Test
    fun onlyPicturesCountAsCovers() {
        assertTrue(looksLikeImage(byteArrayOf(0xFF.toByte(), 0xD8.toByte(), 0xFF.toByte())))
        assertTrue(looksLikeImage(pngBytes(art)))
        assertFalse(looksLikeImage("<html>not found</html>".toByteArray()))
        assertFalse(looksLikeImage(ByteArray(0)))
    }
}
