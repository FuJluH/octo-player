package app.winters.octo.desktop.window

import app.winters.octo.desktop.settings.DesktopOs
import com.sun.jna.Library
import com.sun.jna.Memory
import com.sun.jna.Native
import com.sun.jna.Pointer
import com.sun.jna.ptr.IntByReference
import java.awt.Window
import javax.swing.JFrame

// Asks Windows 11 to round the corners of the app's frameless window, as it
// does for every framed one. Older Windows ignores the request.
fun roundWindowsCorners(window: Window) {
    runCatching {
        val dwm = Native.load("dwmapi", Dwm::class.java)
        val handle = Native.getWindowPointer(window) ?: return
        dwm.DwmSetWindowAttribute(handle, DWMWA_WINDOW_CORNER_PREFERENCE, IntByReference(DWMWCP_ROUND), 4)
    }
}

// On macOS the window keeps its own traffic lights, over a title bar made
// see-through so the app's glass runs to the top edge.
fun seeThroughMacTitleBar(window: JFrame) {
    window.rootPane.putClientProperty("apple.awt.fullWindowContent", true)
    window.rootPane.putClientProperty("apple.awt.transparentTitleBar", true)
    window.rootPane.putClientProperty("apple.awt.windowTitleVisible", false)
}

@Suppress("FunctionName")
private interface Dwm : Library {
    fun DwmSetWindowAttribute(window: Pointer, attribute: Int, value: IntByReference, size: Int): Int
}

private const val DWMWA_WINDOW_CORNER_PREFERENCE = 33
private const val DWMWCP_ROUND = 2

// Whether the system rounds a frameless window's corners itself, with its
// own edge and shadow: Windows 11 (build 22000 on) does once asked
// (roundWindowsCorners). Elsewhere a window with round corners is drawn
// see-through outside its rounded shape.
fun systemRoundsWindows(os: DesktopOs, build: () -> Int? = ::windowsBuild): Boolean =
    os == DesktopOs.Windows && (build() ?: 0) >= WINDOWS_11_BUILD

// The Windows build number, as the system itself has it (the version an
// app is told can be held back for older apps).
private fun windowsBuild(): Int? = runCatching {
    val info = Memory(OS_VERSION_INFO_BYTES).apply {
        clear()
        setInt(0, OS_VERSION_INFO_BYTES.toInt())
    }
    if (Native.load("ntdll", NtDll::class.java).RtlGetVersion(info) != 0) null else info.getInt(12)
}.getOrNull()

@Suppress("FunctionName")
private interface NtDll : Library {
    fun RtlGetVersion(info: Pointer): Int
}

// RTL_OSVERSIONINFOW: five 32-bit fields and 128 UTF-16 characters.
private const val OS_VERSION_INFO_BYTES = 276L
private const val WINDOWS_11_BUILD = 22_000
