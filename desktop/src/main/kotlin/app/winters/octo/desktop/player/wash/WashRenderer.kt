package app.winters.octo.desktop.player.wash

import app.winters.octo.player.immersive.BlurStepAcross
import app.winters.octo.player.immersive.BlurStepDown
import app.winters.octo.player.immersive.CompositeShader
import app.winters.octo.player.immersive.FinalGain
import app.winters.octo.player.immersive.FinalShader
import app.winters.octo.player.immersive.WashBlurBoost
import app.winters.octo.player.immersive.WashCopies
import app.winters.octo.player.immersive.WashMotion
import app.winters.octo.player.immersive.WashSize
import app.winters.octo.player.immersive.blurRadiusFor
import app.winters.octo.player.immersive.blurSigmaTexels
import app.winters.octo.player.immersive.copyPlacement
import app.winters.octo.desktop.ui.LateClose
import org.jetbrains.skia.Canvas
import org.jetbrains.skia.DirectContext
import org.jetbrains.skia.FilterMipmap
import org.jetbrains.skia.FilterMode
import org.jetbrains.skia.FilterTileMode
import org.jetbrains.skia.IRect
import org.jetbrains.skia.Image
import org.jetbrains.skia.ImageFilter
import org.jetbrains.skia.ImageInfo
import org.jetbrains.skia.Matrix33
import org.jetbrains.skia.MipmapMode
import org.jetbrains.skia.Paint
import org.jetbrains.skia.Rect
import org.jetbrains.skia.RuntimeEffect
import org.jetbrains.skia.RuntimeShaderBuilder
import org.jetbrains.skia.SamplingMode
import org.jetbrains.skia.Shader
import org.jetbrains.skia.Surface
import kotlin.math.cos
import kotlin.math.sin
import kotlin.random.Random

// The phone's moving background (player/immersive/WashRenderer.kt there),
// drawn with Skia on the desktop from the same shader text (WashShaders.kt
// in the shared core, which Skia's runtime effects read as they are), as
// one chain of image filters, the way the phone chains render nodes:
//  1. the eight-copy composite with its warp, over the 512 square,
//  2. that square blurred, its edges mirrored,
//  3. the square turned and magnified over the window (a matrix transform,
//     so steps 1 and 2 are worked out at the square's own 512 pixels
//     whatever the window's size), then brightened with a speck of noise
//     by the final shader.
// It all runs where the window draws, on the GPU; per frame the work here
// is setting a few numbers. A frame's shader and filters hold the numbers
// it was drawn with, so they are made for it and closed once it is drawn
// (what was drawn keeps its own hold on them); the paint and the covers'
// shaders are made once.
class WashRenderer : AutoCloseable {
    private val composite = RuntimeShaderBuilder(RuntimeEffect.makeForShader(CompositeShader))
    private val final = RuntimeShaderBuilder(RuntimeEffect.makeForShader(FinalShader))
    private val squareBounds = IRect.makeWH(WashSize, WashSize)
    private val placement = FloatArray(6 * WashCopies.size)
    private val smooth: SamplingMode = FilterMipmap(FilterMode.LINEAR, MipmapMode.NONE)
    private val paint = Paint()
    private var oldCover: Image? = null
    private var newCover: Image? = null
    private var oldShader: Shader? = null
    private var newShader: Shader? = null

    // The phone's platform blur radius turned into the spread Skia takes
    // (Android's blur treats a radius r as a spread of 0.57735 r + 0.5).
    private val spreadAcross = spread(BlurStepAcross)
    private val spreadDown = spread(BlurStepDown)

    init {
        composite.uniform("coverSize", WashSize.toFloat())
        composite.uniform("size", WashSize.toFloat())
        final.uniform("gain", FinalGain)
    }

    // The two covers the copies fade between: 512 squares that repeat at
    // their edges.
    // The builder keeps its own hold on the shaders it is given, so the
    // ones replaced close at once.
    fun setCovers(old: Image, new: Image) {
        if (old !== oldCover) {
            val shader = coverShader(old)
            composite.child("oldCover", shader)
            oldShader?.close()
            oldShader = shader
        }
        if (new !== newCover) {
            val shader = coverShader(new)
            composite.child("newCover", shader)
            newShader?.close()
            newShader = shader
        }
        oldCover = old
        newCover = new
    }

    // Draws one frame over a width x height area. `zoom` scales the final
    // magnification, for the way in; `alpha` fades it in. With the window's
    // graphics card context (`gpu`), steps 1 and 2 are drawn into squares
    // of the wash's own, made once and used again every frame, and step 3
    // samples the blurred square through the same placement; without one,
    // the three steps run as a chain of image filters, whose working
    // textures Skia makes for each frame (their sizes follow the zoom and
    // turn) and keeps as spares.
    fun draw(canvas: Canvas, width: Float, height: Float, motion: WashMotion, fade: Float, zoom: Float, alpha: Float, gpu: DirectContext? = null): Boolean {
        if (newCover == null || width <= 0f || height <= 0f) return false
        val b = motion.breathing
        WashCopies.forEachIndexed { i, copy -> copyPlacement(copy, motion.time, motion.rotation, b, placement, i * 6) }
        for (i in WashCopies.indices) {
            val at = i * 6
            composite.uniform("m$i", placement[at], placement[at + 1], placement[at + 2], placement[at + 3])
            composite.uniform("o$i", placement[at + 4], placement[at + 5])
        }
        composite.uniform("rotation", motion.rotation)
        composite.uniform("warp", motion.warpPhase)
        composite.uniform("fade", fade)
        final.uniform("seed", Random.nextFloat() * 64f)
        val magnify = 2f * b * zoom
        val place = Matrix33.makeTranslate(width / 2f, height / 2f)
            .makeConcat(Matrix33.makeScale(magnify * width / WashSize, magnify * height / WashSize))
            .makeConcat(turned(motion.turn))
            .makeConcat(Matrix33.makeTranslate(-WashSize / 2f, -WashSize / 2f))
        val squares = gpu?.let(::squaresFor)
        if (squares != null) {
            drawOnSquares(canvas, squares, width, height, place, alpha)
        } else {
            drawWithFilters(canvas, width, height, place, alpha)
        }
        return true
    }

    // Steps 1 and 2 into the wash's own squares, then step 3 as one rect.
    private fun drawOnSquares(canvas: Canvas, squares: Squares, width: Float, height: Float, place: Matrix33, alpha: Float) {
        val shader = composite.makeShader()
        squarePaint.shader = shader
        squares.composite.canvas.drawRect(squareRect, squarePaint)
        squarePaint.shader = null
        shader.close()
        val raw = squares.composite.makeImageSnapshot()
        val target = squares.nextBlurred()
        target.canvas.drawImage(raw, 0f, 0f, blurPaint)
        raw.close()
        val blurred = target.makeImageSnapshot()
        val wash = blurred.makeShader(FilterTileMode.DECAL, FilterTileMode.DECAL, smooth, place)
        final.child("wash", wash)
        val washed = final.makeShader()
        try {
            paint.shader = washed
            paint.alpha = (alpha.coerceIn(0f, 1f) * 255).toInt()
            canvas.drawRect(Rect.makeWH(width, height), paint)
        } finally {
            paint.shader = null
            washed.close()
            wash.close()
            // The frame drawn keeps its own hold on the blurred square.
            LateClose.close(blurred)
        }
    }

    private fun drawWithFilters(canvas: Canvas, width: Float, height: Float, place: Matrix33, alpha: Float) {
        // Steps 1 and 2, in the square's own pixels.
        val shader = composite.makeShader()
        val square = ImageFilter.makeShader(shader, false, squareBounds)
        val blurred = ImageFilter.makeBlur(spreadAcross, spreadDown, FilterTileMode.MIRROR, square, squareBounds)
        // Step 3: magnified 2b about its centre and turned in its own space,
        // stretched over the area.
        val placed = ImageFilter.makeMatrixTransform(place, smooth, blurred)
        val washed = ImageFilter.makeRuntimeShader(final, "wash", placed)
        try {
            paint.imageFilter = washed
            paint.alpha = (alpha.coerceIn(0f, 1f) * 255).toInt()
            canvas.saveLayer(Rect.makeWH(width, height), paint)
            canvas.restore()
        } finally {
            paint.imageFilter = null
            washed.close()
            placed.close()
            blurred.close()
            square.close()
            shader.close()
        }
    }

    // The squares steps 1 and 2 are drawn into on the graphics card: the
    // composite, and three for the blur taken in turn, so a frame never
    // draws into the square a frame still on screen shows.
    private class Squares(val context: DirectContext, val composite: Surface, val blurred: List<Surface>) : AutoCloseable {
        private var next = 0

        fun nextBlurred(): Surface = blurred[next].also { next = (next + 1) % blurred.size }

        override fun close() {
            composite.close()
            blurred.forEach(Surface::close)
        }
    }

    private var squares: Squares? = null

    // The squares for this context: made the first time, and again when
    // the window draws with another (after the graphics card was reset).
    private fun squaresFor(context: DirectContext): Squares? {
        squares?.let { if (it.context === context) return it }
        squares?.let(LateClose::close)
        squares = null
        val info = ImageInfo.makeN32Premul(WashSize, WashSize)
        val made = runCatching {
            val composite = Surface.makeRenderTarget(context, false, info)
            val blurred = List(3) { Surface.makeRenderTarget(context, false, info) }
            Squares(context, composite, blurred)
        }.getOrNull() ?: return null
        squares = made
        return made
    }

    private val squareRect = Rect.makeWH(WashSize.toFloat(), WashSize.toFloat())
    private val squarePaint = Paint()

    // The blur of step 2, with its edges mirrored, made once.
    private val blurFilter = ImageFilter.makeBlur(spreadAcross, spreadDown, FilterTileMode.MIRROR, null, squareBounds)
    private val blurPaint = Paint().apply { imageFilter = blurFilter }

    override fun close() {
        squares?.close()
        squares = null
        squarePaint.close()
        blurPaint.close()
        blurFilter.close()
        oldShader?.close()
        newShader?.close()
        oldShader = null
        newShader = null
        paint.close()
        composite.close()
        final.close()
    }

    // A turn by `radians`, built by hand: this Skia's Matrix33.makeRotate
    // does not take degrees as its name says (90 turns by about 5157
    // radians), and passing it the turn in degrees spun the picture some
    // 3,300 times too fast, a strobe rather than a drift.
    internal fun turned(radians: Float): Matrix33 {
        val c = cos(radians)
        val s = sin(radians)
        return Matrix33(c, -s, 0f, s, c, 0f, 0f, 0f, 1f)
    }

    private fun coverShader(image: Image): Shader = image.makeShader(FilterTileMode.REPEAT, FilterTileMode.REPEAT, SamplingMode.LINEAR)

    private fun spread(step: Float): Float = 0.57735f * blurRadiusFor(blurSigmaTexels(step)) * WashBlurBoost + 0.5f
}
