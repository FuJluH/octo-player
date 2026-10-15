package app.winters.octo.desktop.window

import app.winters.octo.desktop.settings.DesktopOs
import com.sun.jna.Library
import com.sun.jna.Native
import com.sun.jna.ptr.IntByReference
import org.jetbrains.skia.PixelGeometry
import org.jetbrains.skiko.SkiaLayer
import java.awt.Component
import java.awt.Container
import java.awt.Window

// How the screen's pixels are laid out for text smoothed in colour, as the
// system smooths its own: on Windows with ClearType on, red green blue
// across (or blue green red, as the listener set it in the ClearType
// tuner). Null where the system smooths text in grey (ClearType off, macOS,
// which has had no colour smoothing for years, and Linux, whose desktops
// say it each their own way), so Octo stays grey too.
fun systemTextPixels(os: DesktopOs, read: (Int) -> Int? = ::systemParameter): PixelGeometry? {
    if (os != DesktopOs.Windows) return null
    if (read(SPI_GETFONTSMOOTHING) != 1) return null
    if (read(SPI_GETFONTSMOOTHINGTYPE) != FE_FONTSMOOTHINGCLEARTYPE) return null
    return when (read(SPI_GETFONTSMOOTHINGORIENTATION)) {
        FE_FONTSMOOTHINGORIENTATIONBGR -> PixelGeometry.BGR_H
        else -> PixelGeometry.RGB_H
    }
}

// Tells a window's drawing surface how its screen's pixels are laid out, so
// text smoothed in colour is drawn in colour there. Compose makes the
// window's drawing layer without saying, and the layer keeps what it was
// made with, so it is set on the layer itself; the surfaces are made again
// from it when the window is first drawn or changes size. Done before the
// window is first shown, it applies from the first frame.
fun useTextPixels(window: Window, pixels: PixelGeometry?) {
    if (pixels == null) return
    runCatching {
        val layer = drawingLayer(window) ?: return
        if (layer.pixelGeometry == pixels) return
        val field = SkiaLayer::class.java.getDeclaredField("pixelGeometry")
        field.isAccessible = true
        field.set(layer, pixels)
    }
}

private fun drawingLayer(component: Component): SkiaLayer? {
    if (component is SkiaLayer) return component
    if (component is Container) component.components.forEach { child -> drawingLayer(child)?.let { return it } }
    return null
}

private fun systemParameter(action: Int): Int? = runCatching {
    val value = IntByReference()
    if (Native.load("user32", User32Parameters::class.java).SystemParametersInfoW(action, 0, value, 0)) value.value else null
}.getOrNull()

@Suppress("FunctionName")
private interface User32Parameters : Library {
    fun SystemParametersInfoW(action: Int, param: Int, value: IntByReference, winIni: Int): Boolean
}

private const val SPI_GETFONTSMOOTHING = 0x004A
private const val SPI_GETFONTSMOOTHINGTYPE = 0x200A
private const val SPI_GETFONTSMOOTHINGORIENTATION = 0x2012
private const val FE_FONTSMOOTHINGCLEARTYPE = 0x0002
private const val FE_FONTSMOOTHINGORIENTATIONBGR = 0x0000

// The layout this run's windows tell their surfaces, decided once at start.
@Volatile var appTextPixels: PixelGeometry? = null
