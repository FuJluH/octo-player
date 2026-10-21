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
import org.jetbrains.skia.Canvas
import org.jetbrains.skia.FilterMipmap
import org.jetbrains.skia.FilterMode
import org.jetbrains.skia.FilterTileMode
import org.jetbrains.skia.IRect
import org.jetbrains.skia.Image
import org.jetbrains.skia.ImageFilter
import org.jetbrains.skia.Matrix33
import org.jetbrains.skia.MipmapMode
import org.jetbrains.skia.Paint
import org.jetbrains.skia.Rect
import org.jetbrains.skia.RuntimeEffect
import org.jetbrains.skia.RuntimeShaderBuilder
import org.jetbrains.skia.SamplingMode
import org.jetbrains.skia.Shader
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
    // magnification, for the way in; `alpha` fades it in.
    fun draw(canvas: Canvas, width: Float, height: Float, motion: WashMotion, fade: Float, zoom: Float, alpha: Float): Boolean {
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

        // Steps 1 and 2, in the square's own pixels.
        val shader = composite.makeShader()
        val square = ImageFilter.makeShader(shader, false, squareBounds)
        val blurred = ImageFilter.makeBlur(spreadAcross, spreadDown, FilterTileMode.MIRROR, square, squareBounds)
        // Step 3: magnified 2b about its centre and turned in its own space,
        // stretched over the area.
        val magnify = 2f * b * zoom
        val place = Matrix33.makeTranslate(width / 2f, height / 2f)
            .makeConcat(Matrix33.makeScale(magnify * width / WashSize, magnify * height / WashSize))
            .makeConcat(turned(motion.turn))
            .makeConcat(Matrix33.makeTranslate(-WashSize / 2f, -WashSize / 2f))
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
        return true
    }

    override fun close() {
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
