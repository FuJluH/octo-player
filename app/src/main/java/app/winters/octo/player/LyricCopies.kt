package app.winters.octo.player

import android.graphics.Canvas
import android.graphics.Picture
import android.graphics.RenderEffect
import android.graphics.RenderNode
import android.graphics.Shader
import android.os.Build
import androidx.annotation.RequiresApi
import androidx.compose.runtime.mutableStateOf
import app.winters.octo.lyrics.engine.LineState
import app.winters.octo.lyrics.engine.shownBlur
import app.winters.octo.ui.common.GpuPicture
import app.winters.octo.ui.common.GpuPictureMaker
import kotlin.math.ceil

// How long a line's drawing and blur must hold still before a blurred copy
// of it is made: through a change of focus the blur steps through several
// strengths in a few frames, and only the one it rests at is worth a copy.
private const val HOLD_NANOS = 100_000_000L

// A line's blur as drawn, in pixels.
internal fun blurPx(st: LineState, density: Float): Float = shownBlur(st.blur).toFloat() * density

// How far a blur of `radius` pixels spreads past what it blurs: three
// spreads of the Gaussian the platform makes from it, and a pixel to spare.
internal fun blurReach(radius: Float): Float = 3f * (0.57735f * radius + 0.5f) + 1f

// One line already blurred: its drawing, cut to its own area, drawn through
// the blur its layer would apply. `left` and `top` are where the picture's
// corner sits in the line's own space.
internal class BlurCopy(val picture: GpuPicture, val left: Float, val top: Float, val version: Int, val radius: Float) {
    fun draw(canvas: Canvas) {
        canvas.drawBitmap(picture.bitmap, left, top, null)
    }
}

// The flowing lines' blurred copies. A line drawn from the same drawing,
// at the same blur, for a moment is from then on shown from a copy already
// blurred to that strength, made on the GPU away from the window, so a
// frame costs the window one picture for the line instead of a blur worked
// out again (the window's renderer keeps no blurred result between frames
// on some phones). A line whose drawing or blur is changing draws itself,
// blurred as its layer draws, as before. Used on the main thread.
@RequiresApi(Build.VERSION_CODES.S)
internal class LyricCopies(private val density: Float) : AutoCloseable {
    private val maker = GpuPictureMaker()
    private val lines = HashMap<Int, LineCopy>()
    private var closed = false

    fun line(index: Int): LineCopy = lines.getOrPut(index) { LineCopy() }

    // Once a frame, after the engine has moved: sets each shown line's copy
    // for the drawing and blur it has now (or none, to draw itself), and
    // asks for copies of lines that have held still long enough. `record`
    // draws a line's drawing, `width` by `height`, into a picture. Lines no
    // longer shown are let go.
    fun follow(states: List<LineState>, shown: IntRange, nanos: Long, size: (Int) -> Pair<Int, Int>, record: (Int, Canvas) -> Unit) {
        if (closed) return
        if (lines.keys.any { it !in shown }) {
            lines.keys.filter { it !in shown }.forEach { lines.remove(it)?.letGo() }
        }
        for (index in shown) {
            val st = states.getOrNull(index) ?: continue
            val line = line(index)
            val radius = blurPx(st, density)
            val version = st.drawVersion.intValue
            if (!line.follow(version, radius, nanos)) continue
            val (width, height) = size(index)
            if (width <= 0 || height <= 0) continue
            val drawing = Picture()
            record(index, drawing.beginRecording(width, height))
            drawing.endRecording()
            makeCopy(line, drawing, width, height, version, radius)
        }
    }

    // Blurs `drawing` as a `width` x `height` layer with a blur of `radius`
    // would: what it draws is cut to the layer, then blurred, the blur
    // spreading past the layer's edges.
    private fun makeCopy(line: LineCopy, drawing: Picture, width: Int, height: Int, version: Int, radius: Float) {
        val reach = ceil(blurReach(radius))
        val copyWidth = width + 2 * reach.toInt()
        val copyHeight = height + 2 * reach.toInt()
        val node = RenderNode("lyric copy").apply {
            setPosition(0, 0, copyWidth, copyHeight)
            setRenderEffect(RenderEffect.createBlurEffect(radius, radius, Shader.TileMode.DECAL))
            val canvas = beginRecording(copyWidth, copyHeight)
            canvas.translate(reach, reach)
            canvas.clipRect(0f, 0f, width.toFloat(), height.toFloat())
            canvas.drawPicture(drawing)
            endRecording()
        }
        val ticket = line.startMaking()
        maker.make(copyWidth, copyHeight, record = { it.drawRenderNode(node) }) { picture ->
            node.discardDisplayList()
            if (picture == null) {
                line.made(ticket, null)
                return@make
            }
            if (closed || !line.made(ticket, BlurCopy(picture, -reach, -reach, version, radius))) picture.release()
        }
    }

    override fun close() {
        if (closed) return
        closed = true
        lines.values.forEach { it.letGo() }
        lines.clear()
        maker.close()
    }

    // A line's copy and the one it shows.
    internal class LineCopy {
        // The copy the line shows instead of drawing itself, or null to draw.
        val copy = mutableStateOf<BlurCopy?>(null)

        // The latest copy made, for the drawing and blur it was made at.
        private var ready: BlurCopy? = null

        // Since when its drawing and blur have held.
        private var heldVersion = -1
        private var heldRadius = -1f
        private var heldSince = 0L

        // The copy being made, by ticket; a newer ticket makes it stale.
        private var ticket = 0
        private var making = false

        // Sets the copy to show for this frame; true when one should be made
        // now.
        fun follow(version: Int, radius: Float, nanos: Long): Boolean {
            if (version != heldVersion || radius != heldRadius) {
                heldVersion = version
                heldRadius = radius
                heldSince = nanos
            }
            val made = ready
            if (made != null && made.version != version) {
                // A new drawing: the copy, and any on its way, are of the old.
                drop()
            }
            val show = ready?.takeIf { radius > 0f && it.radius == radius }
            if (copy.value !== show) copy.value = show
            return show == null && radius > 0f && !making && nanos - heldSince >= HOLD_NANOS
        }

        fun startMaking(): Int {
            making = true
            return ++ticket
        }

        // What was made for `ticket`; false when it came too late to keep.
        fun made(ticket: Int, copy: BlurCopy?): Boolean {
            if (ticket != this.ticket) return false
            making = false
            if (copy == null || copy.version != heldVersion) return false
            // The old copy's bitmap stays drawable after its release, for a
            // frame that still shows it: nothing draws into it again.
            ready?.picture?.release()
            ready = copy
            return true
        }

        fun letGo() {
            drop()
            heldVersion = -1
        }

        private fun drop() {
            ticket++
            making = false
            copy.value = null
            ready?.picture?.release()
            ready = null
        }
    }
}
