package app.winters.octo.desktop.window

import app.winters.octo.desktop.settings.DesktopOs
import org.jetbrains.skia.PixelGeometry
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Test

class TextSmoothingTest {
    // What Windows answers for font smoothing, its kind and its order.
    private fun windows(on: Int, type: Int, orientation: Int): (Int) -> Int? = { action ->
        when (action) {
            0x004A -> on
            0x200A -> type
            0x2012 -> orientation
            else -> null
        }
    }

    @Test
    fun clearTypeAcrossInRedGreenBlueSmoothsInColour() {
        assertEquals(PixelGeometry.RGB_H, systemTextPixels(DesktopOs.Windows, windows(1, 2, 1)))
    }

    @Test
    fun clearTypeTunedToBlueGreenRedFollowsIt() {
        assertEquals(PixelGeometry.BGR_H, systemTextPixels(DesktopOs.Windows, windows(1, 2, 0)))
    }

    @Test
    fun greySmoothingOrNoneStaysGrey() {
        assertNull(systemTextPixels(DesktopOs.Windows, windows(1, 1, 1)))
        assertNull(systemTextPixels(DesktopOs.Windows, windows(0, 2, 1)))
        assertNull(systemTextPixels(DesktopOs.Windows) { null })
    }

    @Test
    fun macAndLinuxStayGrey() {
        assertNull(systemTextPixels(DesktopOs.Mac, windows(1, 2, 1)))
        assertNull(systemTextPixels(DesktopOs.Linux, windows(1, 2, 1)))
    }
}
