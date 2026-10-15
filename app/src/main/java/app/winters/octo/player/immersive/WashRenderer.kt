package app.winters.octo.player.immersive

import android.graphics.Bitmap
import android.graphics.BitmapShader
import android.graphics.Canvas
import android.graphics.Matrix
import android.graphics.Paint
import android.graphics.RenderEffect
import android.graphics.RenderNode
import android.graphics.RuntimeShader
import android.graphics.Shader
import android.os.Build
import androidx.annotation.RequiresApi
import app.winters.octo.ui.common.GpuPictureStream
import kotlin.random.Random

// Draws the moving background, one frame at a time, in three steps:
//  1. the composite with its warp, into a 512 square,
//  2. that square blurred, by a blur set on it once,
//  3. the square turned and magnified over the screen, then brightened
//     with a speck of noise by the final shader.
// Everything runs on the GPU; per frame the work on this side is setting a
// few numbers and re-recording two one-line drawings.
//
// Steps 1 and 2, and the turning and magnifying of step 3, go into a
// picture a quarter of the screen's size, drawn away from the window
// (`renderPicture`), only when the wash moves. The window draws that
// picture stretched over the screen through the final shader
// (`drawPicture`), a plain drawing with no blur to work out again on each
// of the window's frames. The wash is so blurred that a quarter size
// loses nothing: its finest detail spans dozens of screen pixels.
@RequiresApi(Build.VERSION_CODES.TIRAMISU)
class WashRenderer {
    private val composite = RuntimeShader(CompositeShader)
    private val final = RuntimeShader(FinalShader)
    private val paint = Paint().apply { shader = composite }
    private val square = RenderNode("wash square").apply {
        setPosition(0, 0, WashSize, WashSize)
        setRenderEffect(
            RenderEffect.createBlurEffect(
                blurRadiusFor(blurSigmaTexels(BlurStepAcross)) * WashBlurBoost,
                blurRadiusFor(blurSigmaTexels(BlurStepDown)) * WashBlurBoost,
                Shader.TileMode.MIRROR,
            ),
        )
    }
    private val screen = RenderNode("wash screen")
    private val placement = FloatArray(6 * WashCopies.size)
    private val matrix = Matrix()
    private var oldCover: Bitmap? = null
    private var newCover: Bitmap? = null

    // The picture drawn over the window, the zoom it was made at, and the
    // zoom of the one on its way.
    private val finalPaint = Paint().apply { shader = final }
    private val pictureMatrix = Matrix()
    private var shownPicture: Bitmap? = null
    private var pictureShader: BitmapShader? = null
    private val pictureShaders = HashMap<Bitmap, BitmapShader>()
    private var pictureZoom = 1f
    private var pendingZoom = 1f

    init {
        composite.setFloatUniform("coverSize", WashSize.toFloat())
        composite.setFloatUniform("size", WashSize.toFloat())
        final.setFloatUniform("gain", FinalGain)
    }

    // The two covers the copies fade between. Both are 512 squares that
    // repeat at their edges.
    fun setCovers(old: Bitmap, new: Bitmap) {
        if (old !== oldCover) composite.setInputShader("oldCover", coverShader(old))
        if (new !== newCover) composite.setInputShader("newCover", coverShader(new))
        oldCover = old
        newCover = new
    }

    // Draws one frame over a width x height screen. `zoom` scales the final
    // magnification, for the way in and out. The window's own way, for
    // when a picture cannot be made.
    fun draw(canvas: Canvas, width: Int, height: Int, motion: WashMotion, fade: Float, zoom: Float, alpha: Float): Boolean {
        if (newCover == null || width <= 0 || height <= 0 || !canvas.isHardwareAccelerated) return false

        recordSquare(motion, fade)
        val b = motion.breathing

        // Step 3: the square stretched over the screen, magnified 2b about
        // its centre and turned in its own space, then the final shader.
        if (screen.width != width || screen.height != height) screen.setPosition(0, 0, width, height)
        val magnify = 2f * b * zoom
        matrix.reset()
        matrix.postTranslate(-WashSize / 2f, -WashSize / 2f)
        matrix.postRotate(Math.toDegrees(motion.turn.toDouble()).toFloat())
        matrix.postScale(magnify * width / WashSize, magnify * height / WashSize)
        matrix.postTranslate(width / 2f, height / 2f)
        val screenCanvas = screen.beginRecording()
        screenCanvas.concat(matrix)
        screenCanvas.drawRenderNode(square)
        screen.endRecording()
        final.setFloatUniform("seed", Random.nextFloat() * 64f)
        screen.setRenderEffect(RenderEffect.createRuntimeShaderEffect(final, "wash"))
        screen.setAlpha(alpha)
        canvas.drawRenderNode(screen)
        return true
    }

    // Draws one frame of a width x height screen into `pictures`, a little
    // past the screen's edges (`PictureOverscan`) so a picture made at one
    // `zoom` still covers the screen drawn at a slightly smaller one. False
    // when nothing was asked for (no cover yet, or the last picture still
    // on its way).
    fun renderPicture(pictures: GpuPictureStream, width: Int, height: Int, motion: WashMotion, fade: Float, zoom: Float): Boolean {
        if (newCover == null || width <= 0 || height <= 0) return false
        val asked = pictures.draw { canvas ->
            recordSquare(motion, fade)
            val magnify = 2f * motion.breathing * zoom
            matrix.reset()
            matrix.postTranslate(-WashSize / 2f, -WashSize / 2f)
            matrix.postRotate(Math.toDegrees(motion.turn.toDouble()).toFloat())
            matrix.postScale(magnify * width / WashSize, magnify * height / WashSize)
            // From the screen, about its centre, into the picture.
            matrix.postScale(pictures.width / (width * PictureOverscan), pictures.height / (height * PictureOverscan))
            matrix.postTranslate(pictures.width / 2f, pictures.height / 2f)
            canvas.concat(matrix)
            canvas.drawRenderNode(square)
        }
        if (asked) pendingZoom = zoom
        return asked
    }

    // Takes the picture that arrived last, made at the zoom asked for with it.
    fun pictureArrived(pictures: GpuPictureStream) {
        val bitmap = pictures.latest ?: return
        if (bitmap === shownPicture) return
        shownPicture = bitmap
        pictureZoom = pendingZoom
        // The stream hands its few bitmaps round again; each keeps its shader.
        pictureShader = pictureShaders.getOrPut(bitmap) {
            BitmapShader(bitmap, Shader.TileMode.CLAMP, Shader.TileMode.CLAMP).apply { filterMode = BitmapShader.FILTER_MODE_LINEAR }
        }
        final.setFloatUniform("seed", Random.nextFloat() * 64f)
    }

    // Draws the last picture stretched over a width x height screen through
    // the final shader, scaled about the centre from the zoom it was made at
    // to `zoom`. False before the first picture.
    fun drawPicture(canvas: Canvas, width: Int, height: Int, zoom: Float, alpha: Float): Boolean {
        val bitmap = shownPicture ?: return false
        val shader = pictureShader ?: return false
        if (width <= 0 || height <= 0) return false
        val k = if (pictureZoom > 0f) zoom / pictureZoom else 1f
        pictureMatrix.reset()
        pictureMatrix.postTranslate(-bitmap.width / 2f, -bitmap.height / 2f)
        pictureMatrix.postScale(width * PictureOverscan / bitmap.width * k, height * PictureOverscan / bitmap.height * k)
        pictureMatrix.postTranslate(width / 2f, height / 2f)
        shader.setLocalMatrix(pictureMatrix)
        final.setInputShader("wash", shader)
        finalPaint.alpha = (alpha.coerceIn(0f, 1f) * 255).toInt()
        canvas.drawRect(0f, 0f, width.toFloat(), height.toFloat(), finalPaint)
        return true
    }

    // Steps 1 and 2: the composite, into the blurred square.
    private fun recordSquare(motion: WashMotion, fade: Float) {
        val b = motion.breathing
        WashCopies.forEachIndexed { i, copy -> copyPlacement(copy, motion.time, motion.rotation, b, placement, i * 6) }
        for (i in WashCopies.indices) {
            val at = i * 6
            composite.setFloatUniform("m$i", placement[at], placement[at + 1], placement[at + 2], placement[at + 3])
            composite.setFloatUniform("o$i", placement[at + 4], placement[at + 5])
        }
        composite.setFloatUniform("rotation", motion.rotation)
        composite.setFloatUniform("warp", motion.warpPhase)
        composite.setFloatUniform("fade", fade)
        val squareCanvas = square.beginRecording()
        squareCanvas.drawRect(0f, 0f, WashSize.toFloat(), WashSize.toFloat(), paint)
        square.endRecording()
    }

    // Lets go of the drawings' memory once the background is gone.
    fun release() {
        square.discardDisplayList()
        screen.discardDisplayList()
        shownPicture = null
        pictureShader = null
        pictureShaders.clear()
    }

    private fun coverShader(bitmap: Bitmap) = BitmapShader(bitmap, Shader.TileMode.REPEAT, Shader.TileMode.REPEAT).apply {
        filterMode = BitmapShader.FILTER_MODE_LINEAR
    }
}

// How far past the screen's edges the wash's picture reaches, as a share of
// the screen, and how many times smaller than the screen it is made.
const val PictureOverscan = 1.1f
const val PictureScaleDown = 4
