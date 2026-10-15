package app.winters.octo.desktop.system

import app.winters.octo.design.IconSource
import app.winters.octo.design.loadIcon
import org.jetbrains.skia.Bitmap
import org.jetbrains.skia.Canvas
import org.jetbrains.skia.ColorAlphaType
import org.jetbrains.skia.ColorType
import org.jetbrains.skia.ImageInfo
import org.jetbrains.skia.Paint
import org.jetbrains.skia.Path
import org.jetbrains.skia.RRect
import org.jetbrains.skia.PathFillMode
import org.jetbrains.skia.Surface

// The taskbar thumbnail's icons, drawn from the same icon files as the
// player bar's buttons, at the size Windows asks for. Dark on a light
// taskbar, white on a dark one.

// The icons' colour for the system's taskbar theme.
fun taskbarIconColour(lightTaskbar: Boolean): Int = if (lightTaskbar) 0xFF1F1F1F.toInt() else 0xFFFFFFFF.toInt()

// The four icons, previous, play, pause and next, one after another, each
// `size` by `size` pixels of blue, green, red and alpha, not premultiplied,
// rows top down: the form the system library takes. For a live station
// (`stop`) the pause icon is a stop square, the same as the player's.
fun taskbarIconPixels(size: Int, colour: Int, stop: Boolean = false): ByteArray {
    val previous = loadIcon("sym_fast_rewind")
    val play = loadIcon("sym_play_arrow")
    val pause = loadIcon("sym_pause")
    val next = loadIcon("sym_fast_forward")
    return drawn(size) { canvas, paint -> glyph(canvas, paint, previous, size) }
        .plus(drawn(size) { canvas, paint -> glyph(canvas, paint, play, size) })
        .plus(drawn(size) { canvas, paint -> if (stop) stopSquare(canvas, paint, size) else glyph(canvas, paint, pause, size) })
        .plus(drawn(size) { canvas, paint -> glyph(canvas, paint, next, size) })
        .also { tint(it, colour) }
}

private fun drawn(size: Int, draw: (Canvas, Paint) -> Unit): ByteArray {
    val surface = Surface.makeRaster(ImageInfo.makeN32Premul(size, size))
    val paint = Paint().apply {
        color = 0xFFFFFFFF.toInt()
        isAntiAlias = true
    }
    draw(surface.canvas, paint)
    val info = ImageInfo(size, size, ColorType.BGRA_8888, ColorAlphaType.UNPREMUL)
    val bitmap = Bitmap().apply { allocPixels(info) }
    surface.readPixels(bitmap, 0, 0)
    val pixels = bitmap.readPixels(info, size * 4, 0, 0) ?: ByteArray(size * size * 4)
    bitmap.close()
    surface.close()
    return pixels
}

// An icon file's paths, filling the square as its grid lays them out.
private fun glyph(canvas: Canvas, paint: Paint, icon: IconSource, size: Int) {
    val scale = size / icon.viewportWidth
    canvas.save()
    canvas.scale(scale, scale)
    icon.paths.forEach { part ->
        val path = Path.makeFromSVGString(part.data)
        if (part.evenOdd) path.fillMode = PathFillMode.EVEN_ODD
        canvas.drawPath(path, paint)
        path.close()
    }
    canvas.restore()
}

// A rounded square in the middle of the icon, as wide as the pause bars
// stand.
private fun stopSquare(canvas: Canvas, paint: Paint, size: Int) {
    val side = size * 0.56f
    val start = (size - side) / 2f
    canvas.drawRRect(RRect.makeXYWH(start, start, side, side, side * 0.16f), paint)
}

// Every pixel takes the colour, keeping its own coverage.
private fun tint(pixels: ByteArray, colour: Int) {
    val blue = (colour and 0xFF).toByte()
    val green = ((colour shr 8) and 0xFF).toByte()
    val red = ((colour shr 16) and 0xFF).toByte()
    for (i in pixels.indices step 4) {
        pixels[i] = blue
        pixels[i + 1] = green
        pixels[i + 2] = red
    }
}
