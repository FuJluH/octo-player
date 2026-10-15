package app.winters.octo.desktop.window

import app.winters.octo.desktop.settings.DesktopOs
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class SystemLookTest {
    @Test
    fun windows11RoundsFramelessWindowsItself() {
        assertTrue(systemRoundsWindows(DesktopOs.Windows) { 22_000 })
        assertTrue(systemRoundsWindows(DesktopOs.Windows) { 26_300 })
    }

    @Test
    fun windows10AndOthersAreDrawnSeeThroughInstead() {
        assertFalse(systemRoundsWindows(DesktopOs.Windows) { 19_045 })
        assertFalse(systemRoundsWindows(DesktopOs.Windows) { null })
        assertFalse(systemRoundsWindows(DesktopOs.Mac) { 26_300 })
        assertFalse(systemRoundsWindows(DesktopOs.Linux) { 26_300 })
    }
}
