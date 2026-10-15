package app.winters.octo.desktop.system

import java.awt.AlphaComposite
import java.awt.RenderingHints
import java.awt.geom.RoundRectangle2D
import java.awt.image.BufferedImage
import java.io.ByteArrayOutputStream
import java.io.File
import java.nio.ByteBuffer
import java.nio.ByteOrder
import javax.imageio.ImageIO
import kotlin.math.ceil
import kotlin.math.floor

// The app's icon files, each size drawn from the vector (OctopusArt):
// a PNG for Linux and the window, an ICO for Windows and an ICNS for macOS.
// Each is the art in a rounded square, the way each system draws app icons.
//
// Run with ./gradlew :desktop:makeIcons; the files are kept in the
// repository, in desktop/icons.

// How much room is left around the rounded square, and how round it is,
// as shares of the icon's side.
data class IconShape(val margin: Float, val radius: Float)

// Windows and Linux: nearly the full square, softly rounded.
val FlatShape = IconShape(margin = 0.03f, radius = 0.20f)

// macOS: the rounded square on its standard grid (824 of 1024), with room
// for the shadow the Dock adds.
val MacShape = IconShape(margin = 100f / 1024f, radius = 0.225f * (824f / 1024f))

// The art scaled to `size`, inside a rounded square with clear corners.
fun roundedIcon(art: BufferedImage, size: Int, shape: IconShape): BufferedImage {
    val out = BufferedImage(size, size, BufferedImage.TYPE_INT_ARGB)
    val margin = size * shape.margin
    val side = size - margin * 2
    val g = out.createGraphics()
    try {
        g.setRenderingHint(RenderingHints.KEY_ANTIALIASING, RenderingHints.VALUE_ANTIALIAS_ON)
        g.setRenderingHint(RenderingHints.KEY_RENDERING, RenderingHints.VALUE_RENDER_QUALITY)
        g.setRenderingHint(RenderingHints.KEY_INTERPOLATION, RenderingHints.VALUE_INTERPOLATION_BICUBIC)
        // The mask first, then the art drawn only where the mask is. The art
        // covers every pixel the mask touches, or the mask's white shows
        // as a hairline on the right and bottom.
        g.color = java.awt.Color.WHITE
        g.fill(RoundRectangle2D.Float(margin, margin, side, side, size * shape.radius * 2, size * shape.radius * 2))
        g.composite = AlphaComposite.SrcIn
        val start = floor(margin).toInt()
        g.drawImage(scaled(art, (ceil(margin + side).toInt() - start).coerceAtLeast(1)), start, start, null)
    } finally {
        g.dispose()
    }
    return out
}

// Halves the picture step by step to the size, so small icons stay sharp.
private fun scaled(image: BufferedImage, size: Int): BufferedImage {
    var current = image
    while (current.width / 2 >= size) current = resize(current, current.width / 2)
    return if (current.width == size) current else resize(current, size)
}

private fun resize(image: BufferedImage, size: Int): BufferedImage {
    val out = BufferedImage(size, size, BufferedImage.TYPE_INT_ARGB)
    val g = out.createGraphics()
    g.setRenderingHint(RenderingHints.KEY_INTERPOLATION, RenderingHints.VALUE_INTERPOLATION_BICUBIC)
    g.setRenderingHint(RenderingHints.KEY_RENDERING, RenderingHints.VALUE_RENDER_QUALITY)
    g.drawImage(image, 0, 0, size, size, null)
    g.dispose()
    return out
}

fun pngBytes(image: BufferedImage): ByteArray = ByteArrayOutputStream().also { ImageIO.write(image, "png", it) }.toByteArray()

// A Windows icon file holding pictures (PNG, or its own bitmaps), one per size (Windows Vista and
// later read PNG inside ICO). Sizes up to 256.
fun icoBytes(pictures: List<Pair<Int, ByteArray>>): ByteArray {
    val header = 6 + 16 * pictures.size
    val out = ByteBuffer.allocate(header + pictures.sumOf { it.second.size }).order(ByteOrder.LITTLE_ENDIAN)
    out.putShort(0).putShort(1).putShort(pictures.size.toShort())
    var offset = header
    for ((size, png) in pictures) {
        require(size in 1..256) { "an icon picture is at most 256 wide" }
        // 256 is written as 0.
        out.put((size % 256).toByte()).put((size % 256).toByte())
        out.put(0).put(0)
        out.putShort(1).putShort(32)
        out.putInt(png.size).putInt(offset)
        offset += png.size
    }
    pictures.forEach { out.put(it.second) }
    return out.array()
}

// A macOS icon file: its type and length, then each picture under the
// four-letter type for its size, as PNG.
fun icnsBytes(pictures: List<Pair<String, ByteArray>>): ByteArray {
    val total = 8 + pictures.sumOf { 8 + it.second.size }
    val out = ByteBuffer.allocate(total).order(ByteOrder.BIG_ENDIAN)
    out.put("icns".toByteArray(Charsets.US_ASCII)).putInt(total)
    for ((type, png) in pictures) {
        require(type.length == 4)
        out.put(type.toByteArray(Charsets.US_ASCII)).putInt(8 + png.size).put(png)
    }
    return out.array()
}

// The macOS picture types, by the pixel size each holds.
val IcnsTypes = listOf(
    "icp4" to 16, "icp5" to 32, "icp6" to 64, "ic07" to 128, "ic08" to 256, "ic09" to 512,
    // The same at twice the density: 16@2x, 32@2x, 128@2x, 256@2x.
    "ic11" to 32, "ic12" to 64, "ic13" to 256, "ic14" to 512,
)

// Every size the ICO holds: each size Windows draws an app's icon at, from
// 100% to 400% scaling (the window's own list, WindowIconSizes).
val IcoSizes = WindowIconSizes

// A picture as a Windows icon's own bitmap entry: 32-bit colour with alpha,
// bottom row first, the height doubled for the (empty) mask that follows,
// which Windows reads for every picture under 256.
fun icoBitmap(image: BufferedImage): ByteArray {
    val w = image.width
    val h = image.height
    val maskRow = ((w + 31) / 32) * 4
    val out = ByteBuffer.allocate(40 + w * h * 4 + maskRow * h).order(ByteOrder.LITTLE_ENDIAN)
    out.putInt(40).putInt(w).putInt(h * 2).putShort(1).putShort(32).putInt(0).putInt(w * h * 4 + maskRow * h).putInt(0).putInt(0).putInt(0).putInt(0)
    for (y in h - 1 downTo 0) for (x in 0 until w) {
        val argb = image.getRGB(x, y)
        out.put((argb and 0xFF).toByte()).put((argb shr 8 and 0xFF).toByte()).put((argb shr 16 and 0xFF).toByte()).put((argb ushr 24).toByte())
    }
    repeat(maskRow * h) { out.put(0) }
    return out.array()
}

// Writes octo.png (Linux and the installers' file types), octo.ico (Windows:
// the installer, shortcuts, the taskbar and Start) and octo.icns (macOS)
// into `folder`, each size drawn on its own from the vector: the 256 in the
// ICO as PNG, the smaller ones as its own bitmaps.
fun writeIconFiles(folder: File) {
    folder.mkdirs()
    File(folder, "octo.png").writeBytes(OctopusArt.iconPng(512, FlatShape))
    File(folder, "octo.ico").writeBytes(
        icoBytes(IcoSizes.map { size -> size to if (size >= 256) OctopusArt.iconPng(size, FlatShape) else icoBitmap(OctopusArt.iconImage(size, FlatShape)) }),
    )
    val mac = IcnsTypes.map { it.second }.distinct().associateWith { OctopusArt.iconPng(it, MacShape) }
    File(folder, "octo.icns").writeBytes(icnsBytes(IcnsTypes.map { (type, size) -> type to mac.getValue(size) }))
}

// ./gradlew :desktop:makeIcons runs this with the folder to write.
fun main(args: Array<String>) {
    writeIconFiles(File(args[0]))
    println("Icons written to ${File(args[0]).absolutePath}")
}
