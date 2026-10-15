package app.winters.octo.desktop.system

import androidx.compose.ui.geometry.Size
import androidx.compose.ui.graphics.drawscope.DrawScope
import androidx.compose.ui.graphics.drawscope.drawIntoCanvas
import androidx.compose.ui.graphics.nativeCanvas
import androidx.compose.ui.graphics.painter.Painter
import org.jetbrains.skia.Canvas
import org.jetbrains.skia.Color
import org.jetbrains.skia.Data
import org.jetbrains.skia.EncodedImageFormat
import org.jetbrains.skia.Color4f
import org.jetbrains.skia.FilterTileMode
import org.jetbrains.skia.Gradient
import org.jetbrains.skia.Image
import org.jetbrains.skia.Paint
import org.jetbrains.skia.Point
import org.jetbrains.skia.RRect
import org.jetbrains.skia.SamplingMode
import org.jetbrains.skia.Rect
import org.jetbrains.skia.Shader
import org.jetbrains.skia.Surface
import org.jetbrains.skia.svg.SVGDOM
import java.awt.image.BufferedImage
import java.io.ByteArrayInputStream
import javax.imageio.ImageIO
import kotlin.math.ceil
import kotlin.math.floor
import kotlin.math.max
import kotlin.math.roundToInt

// Octo's octopus and its icon, drawn from the one vector every icon comes
// from (tools/appicon/octopus.svg, bundled as /octo-octopus.svg), so each is
// sharp at any size and density. The icon is the octopus on its lavender
// tile, as tools/appicon/make_app_icon.py draws the square: a diagonal
// gradient, a soft white light in the middle, the octopus over it.
object OctopusArt {
    // The octopus's box, in the vector's own units.
    const val Width = 537f
    const val Height = 494f

    // How far the octopus's ink reaches from its box's centre, in the
    // vector's units: the measure the octopus is placed by everywhere (an
    // octopus "reaching a share of the side" has this distance be that
    // share of the side).
    const val Reach = 314.24f

    // The opening's and About's octopus: its ink reaches this share of
    // the square it is drawn in.
    const val OpeningReach = 0.48f

    // The icon's octopus on its tile.
    const val SquareReach = 0.44f

    private val SkyTop = Color.makeRGB(0xC9, 0xBE, 0xFF)
    private val SkyBottom = Color.makeRGB(0x9C, 0x8A, 0xF0)
    private const val GlowAlpha = 0.45f
    private const val GlowRadius = 0.50f

    // Read once; drawn from one thread at a time.
    private val dom: SVGDOM by lazy {
        val bytes = OctopusArt::class.java.getResourceAsStream("/octo-octopus.svg")!!.use { it.readBytes() }
        SVGDOM(Data.makeFromBytes(bytes)).apply { setContainerSize(Width, Height) }
    }

    // The octopus centred in the square from (0, 0) to `side`, its ink
    // reaching `share` of the side.
    fun drawOctopus(canvas: Canvas, side: Float, share: Float) {
        val scale = side * share / Reach
        canvas.save()
        canvas.translate(side / 2f, side / 2f)
        canvas.scale(scale, scale)
        canvas.translate(-Width / 2f, -Height / 2f)
        synchronized(dom) { dom.render(canvas) }
        canvas.restore()
    }

    // The tile and the octopus over it, filling the square from (0, 0) to `side`.
    fun drawSquare(canvas: Canvas, side: Float) {
        Paint().use { sky ->
            sky.shader = Shader.makeLinearGradient(Point(0f, 0f), Point(side, side), gradient(SkyTop, SkyBottom))
            canvas.drawRect(Rect.makeWH(side, side), sky)
        }
        Paint().use { glow ->
            val white = Color.makeARGB((GlowAlpha * 255).roundToInt(), 255, 255, 255)
            glow.shader = Shader.makeRadialGradient(Point(side / 2f, side / 2f), side * GlowRadius, gradient(white, Color.makeARGB(0, 255, 255, 255)))
            canvas.drawRect(Rect.makeWH(side, side), glow)
        }
        drawOctopus(canvas, side, SquareReach)
    }

    // The icon `size` pixels square: the square art in a rounded square
    // with clear corners, or the bare square with `shape` null. The art is
    // drawn from the vector several times larger and halved step by step with a
    // sharp cubic filter, which keeps a small icon's thin arms crisp, and
    // the rounded outline is cut at the icon's own size. At small sizes the
    // outline's edges sit on whole pixels, so it stays crisp at 100% scaling.
    fun icon(size: Int, shape: IconShape? = FlatShape): Image {
        val surface = Surface.makeRasterN32Premul(size, size)
        val canvas = surface.canvas
        canvas.clear(Color.TRANSPARENT)
        if (shape == null) {
            art(size).use { canvas.drawImage(it, 0f, 0f) }
        } else {
            val margin = size * shape.margin
            val start = if (size <= SnapBelow) floor(margin + 0.5f) else margin
            val side = size - start * 2
            val radius = size * shape.radius
            canvas.save()
            canvas.clipRRect(RRect.makeXYWH(start, start, side, side, radius), true)
            art(ceil(side).toInt()).use { canvas.drawImageRect(it, Rect.makeWH(it.width.toFloat(), it.height.toFloat()), Rect.makeXYWH(start, start, side, side), SamplingMode.LINEAR, null, true) }
            canvas.restore()
        }
        return surface.makeImageSnapshot()
    }

    // The square art `side` pixels across, drawn at a power of two times
    // that (at least four times, and at least ArtDrawnAt pixels) and halved
    // step by step, as the icon was always made from its large square.
    private fun art(side: Int): Image {
        var steps = 2
        while (side shl steps < ArtDrawnAt && steps < MaxHalvings) steps++
        val drawn = side shl steps
        var image = Surface.makeRasterN32Premul(drawn, drawn).run {
            canvas.clear(Color.TRANSPARENT)
            drawSquare(canvas, drawn.toFloat())
            makeImageSnapshot()
        }
        repeat(steps) {
            val half = image.width / 2
            val next = Surface.makeRasterN32Premul(half, half).run {
                canvas.drawImageRect(image, Rect.makeWH(image.width.toFloat(), image.height.toFloat()), Rect.makeWH(half.toFloat(), half.toFloat()), SamplingMode.CATMULL_ROM, null, true)
                makeImageSnapshot()
            }
            image.close()
            image = next
        }
        return image
    }

    fun iconPng(size: Int, shape: IconShape? = FlatShape): ByteArray = icon(size, shape).encodeToData(EncodedImageFormat.PNG)!!.bytes

    fun iconImage(size: Int, shape: IconShape? = FlatShape): BufferedImage = ImageIO.read(ByteArrayInputStream(iconPng(size, shape)))

    // The window's icons, one drawn for each size Windows may ask for (the
    // title bar, Alt+Tab and the taskbar, at every scaling), so none is a
    // smaller copy of a bigger one.
    fun windowIcons(shape: IconShape? = null): List<BufferedImage> = WindowIconSizes.map { iconImage(it, shape) }

    // At and below this size, the icon's outline sits on whole pixels.
    private const val SnapBelow = 32

    private const val ArtDrawnAt = 256
    private const val MaxHalvings = 4
}

// Every size Windows draws an app's icon at, from 100% to 400% scaling.
val WindowIconSizes = listOf(16, 20, 24, 30, 32, 36, 40, 48, 60, 64, 72, 80, 96, 128, 256)

// The octopus as a picture for Compose, drawn from the vector at whatever
// size it is laid out at: centred, its ink reaching `share` of the
// smaller side.
class OctopusPainter(private val share: Float = OctopusArt.OpeningReach) : Painter() {
    override val intrinsicSize: Size = Size.Unspecified

    override fun DrawScope.onDraw() {
        val side = minOf(size.width, size.height)
        drawIntoCanvas { canvas ->
            val native = canvas.nativeCanvas
            native.save()
            native.translate((size.width - side) / 2f, (size.height - side) / 2f)
            OctopusArt.drawOctopus(native, side, share)
            native.restore()
        }
    }
}

// The icon for Compose (the tray), drawn from the vector at the size it is
// asked for, so the tray's small icon is drawn at its own size.
class OctoIconPainter(private val shape: IconShape? = FlatShape) : Painter() {
    override val intrinsicSize: Size = Size.Unspecified

    override fun DrawScope.onDraw() {
        val side = max(1, minOf(size.width, size.height).roundToInt())
        drawIntoCanvas { canvas ->
            OctopusArt.icon(side, shape).use { canvas.nativeCanvas.drawImage(it, (size.width - side) / 2f, (size.height - side) / 2f) }
        }
    }
}

// Two colours blended evenly from the start to the end, held past them.
private fun gradient(from: Int, to: Int): Gradient =
    Gradient(Gradient.Colors(arrayOf(Color4f(from), Color4f(to)), null, FilterTileMode.CLAMP))
