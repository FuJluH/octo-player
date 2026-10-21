package app.winters.octo.desktop.lyrics

import androidx.compose.runtime.mutableStateOf
import androidx.compose.ui.geometry.Size
import androidx.compose.ui.graphics.BlurEffect
import androidx.compose.ui.graphics.RenderEffect
import androidx.compose.ui.graphics.TileMode
import androidx.compose.ui.graphics.asComposeCanvas
import androidx.compose.ui.graphics.drawscope.CanvasDrawScope
import androidx.compose.ui.graphics.drawscope.DrawScope
import androidx.compose.ui.graphics.skiaImageFilter
import androidx.compose.ui.unit.Density
import androidx.compose.ui.unit.LayoutDirection
import app.winters.octo.desktop.ui.LateClose
import app.winters.octo.lyrics.engine.LineState
import app.winters.octo.lyrics.engine.shownBlur
import org.jetbrains.skia.Canvas
import org.jetbrains.skia.FilterMipmap
import org.jetbrains.skia.FilterMode
import org.jetbrains.skia.Image
import org.jetbrains.skia.ImageFilter
import org.jetbrains.skia.MipmapMode
import org.jetbrains.skia.Paint
import org.jetbrains.skia.Picture
import org.jetbrains.skia.PictureRecorder
import org.jetbrains.skia.RTreeFactory
import org.jetbrains.skia.Rect
import org.jetbrains.skia.Surface
import java.util.concurrent.ConcurrentLinkedQueue
import java.util.concurrent.Executor
import java.util.concurrent.Executors
import kotlin.math.ceil
import kotlin.math.floor

// How long a line's drawing and blur must hold still before a blurred copy
// of it is made: through a change of focus the blur steps through several
// strengths in a few frames, and only the one it rests at is worth a copy.
private const val HOLD_NANOS = 100_000_000L

// Copies kept for one drawing of a line, at different strengths.
private const val COPIES_KEPT = 3

// The blur Compose draws a layer with, at `radius` pixels, one per size so
// moving lines reuse them.
private val blurs = HashMap<Float, RenderEffect>()

internal fun blurOf(radius: Float): RenderEffect = blurs.getOrPut(radius) { BlurEffect(radius, radius, TileMode.Decal) }

// A line's blur as drawn, in pixels.
internal fun blurPx(st: LineState, density: Float): Float = shownBlur(st.blur).toFloat() * density

// How far a blur of `radius` pixels spreads past what it blurs: three
// spreads of the Gaussian Compose makes from it, and a pixel to spare.
private fun blurReach(radius: Float): Float = 3f * (0.57735f * radius + 0.5f) + 1f

private val Smooth = FilterMipmap(FilterMode.LINEAR, MipmapMode.NONE)

// One line already blurred: its picture drawn into `image` through the blur
// a layer would apply, `left` and `top` being where the image's corner sits
// in the line's own space. A line that draws nothing has no image.
internal class BlurCopy(val image: Image?, val left: Float, val top: Float, val version: Int, val radius: Float) {
    fun draw(canvas: Canvas) {
        val image = image ?: return
        val width = image.width.toFloat()
        val height = image.height.toFloat()
        canvas.drawImageRect(image, 0f, 0f, width, height, left, top, left + width, top + height, Smooth, null, true)
    }
}

// The flowing lines' drawings, kept between frames. A line drawn from the
// same drawing, at the same blur, for a moment is from then on shown from a
// copy of its picture already blurred to that strength, made off the
// window's thread, so a frame costs the window one image for the line
// instead of a blur worked out again. A line whose drawing or blur is
// changing draws itself, blurred as its layer draws, as before. Used on the
// window's thread, apart from the copies the worker makes.
internal class LinePictures(
    private val density: Float,
    private val worker: Executor = BlurWorker,
) : AutoCloseable {
    private val lines = HashMap<Int, LinePicture>()
    private val made = ConcurrentLinkedQueue<Made>()
    private val recorder = PictureRecorder()
    private val bounds = RTreeFactory()
    private val scope = CanvasDrawScope()

    @Volatile
    private var closed = false

    // What the worker made for a line's ticket: a copy, or nothing when it
    // was no longer wanted by the time its turn came.
    private class Made(val line: LinePicture, val ticket: Int, val copy: BlurCopy?)

    // Pictures out with the worker, which close once back if they were
    // replaced meanwhile.
    private val lent = Lent()

    fun line(index: Int): LinePicture = lines.getOrPut(index) { LinePicture(lent) }

    // Once a frame, after the engine has moved: takes in the copies made
    // since the last frame, sets each shown line's copy for the blur it has
    // now (or none, to draw itself), and asks for copies of lines that have
    // held still long enough. Lines no longer shown are let go.
    fun follow(states: List<LineState>, shown: IntRange, nanos: Long) {
        while (true) {
            val done = made.poll() ?: break
            if (!done.line.take(done.ticket, done.copy)) done.copy?.image?.close()
        }
        if (lines.keys.any { it !in shown }) {
            val gone = lines.keys.filter { it !in shown }
            gone.forEach { lines.remove(it)?.letGo() }
        }
        for (index in shown) {
            val st = states.getOrNull(index) ?: continue
            val line = lines[index] ?: continue
            val radius = blurPx(st, density)
            val version = st.drawVersion.intValue
            val (picture, ticket) = line.follow(version, radius, nanos) ?: continue
            val filter = blurOf(radius).skiaImageFilter
            lent.lend(picture)
            worker.execute {
                try {
                    val copy = if (closed || !line.stillWants(ticket)) null else blurredCopy(picture, filter, radius, version)
                    if (closed) copy?.image?.close() else made.add(Made(line, ticket, copy))
                } finally {
                    lent.back(picture)
                }
            }
        }
    }

    // The line's drawing, recorded from `draw` over a `size` area and kept
    // as its latest picture, of `version`.
    fun record(line: LinePicture, version: Int, size: Size, density: Density, direction: LayoutDirection, draw: DrawScope.() -> Unit): Picture {
        // Room past the line on every side, for letters that lift or glow.
        val room = size.height
        val canvas = recorder.beginRecording(Rect.makeLTRB(-room, -room, size.width + room, size.height + room), bounds)
        scope.draw(density, direction, canvas.asComposeCanvas(), size, draw)
        val picture = recorder.finishRecordingAsPicture()
        line.drew(picture, version)
        return picture
    }

    override fun close() {
        closed = true
        lines.values.forEach { it.letGo() }
        lines.clear()
        while (true) {
            val done = made.poll() ?: break
            done.copy?.image?.close()
        }
        LateClose.close(recorder)
        LateClose.close(bounds)
    }

    // Pictures the worker is blurring: one replaced while it is out closes
    // when it comes back, and any other after the next whole frame (the
    // frame drawn keeps its own hold on it).
    internal class Lent {
        private val out = java.util.IdentityHashMap<Picture, Int>()
        private val replaced = java.util.Collections.newSetFromMap(java.util.IdentityHashMap<Picture, Boolean>())

        fun lend(picture: Picture) = synchronized(this) { out[picture] = (out[picture] ?: 0) + 1 }

        fun back(picture: Picture) {
            val close = synchronized(this) {
                val left = (out[picture] ?: 1) - 1
                if (left > 0) out[picture] = left else out.remove(picture)
                left <= 0 && replaced.remove(picture)
            }
            if (close) LateClose.close(picture)
        }

        fun retire(picture: Picture) {
            val now = synchronized(this) {
                if (picture in out) {
                    replaced.add(picture)
                    false
                } else {
                    true
                }
            }
            if (now) LateClose.close(picture)
        }
    }

    // A line's latest picture, its copies and the one it shows.
    internal class LinePicture(private val lent: Lent = Lent()) {
        // The copy the line shows instead of drawing itself, or null to draw.
        val copy = mutableStateOf<BlurCopy?>(null)

        private var picture: Picture? = null
        private var pictureVersion = -1
        private val copies = LinkedHashMap<Float, BlurCopy>()

        // Since when its drawing and blur have held.
        private var heldVersion = -1
        private var heldRadius = -1f
        private var heldSince = 0L

        // The copy being made, by ticket; a newer ticket makes it stale. The
        // worker reads it to skip work no longer wanted.
        @Volatile
        private var ticket = 0
        private var making = false

        fun drew(picture: Picture, version: Int) {
            if (version != pictureVersion) dropCopies()
            this.picture?.takeIf { it !== picture }?.let(lent::retire)
            this.picture = picture
            pictureVersion = version
        }

        // Sets the copy to show for this frame, and gives a picture to blur
        // (with its ticket) when one should be made now.
        fun follow(version: Int, radius: Float, nanos: Long): Pair<Picture, Int>? {
            if (version != heldVersion || radius != heldRadius) {
                heldVersion = version
                heldRadius = radius
                heldSince = nanos
            }
            if (version != pictureVersion) dropCopies()
            val ready = if (radius > 0f && version == pictureVersion) copies[radius] else null
            if (copy.value !== ready) copy.value = ready
            val source = picture
            if (ready != null || radius <= 0f || source == null || version != pictureVersion || making || nanos - heldSince < HOLD_NANOS) return null
            making = true
            return source to ticket
        }

        fun stillWants(ticket: Int): Boolean = ticket == this.ticket

        // What was made for `ticket`; false when it came too late to keep.
        fun take(ticket: Int, made: BlurCopy?): Boolean {
            if (ticket != this.ticket) return false
            making = false
            if (made == null || made.version != pictureVersion) return false
            copies.remove(made.radius)?.image?.close()
            copies[made.radius] = made
            while (copies.size > COPIES_KEPT) {
                val oldest = copies.keys.first()
                if (copies[oldest] === copy.value) break
                copies.remove(oldest)?.image?.close()
            }
            return true
        }

        fun letGo() {
            dropCopies()
            picture?.let(lent::retire)
            picture = null
            pictureVersion = -1
        }

        private fun dropCopies() {
            ticket++
            making = false
            if (copy.value != null) copy.value = null
            copies.values.forEach { it.image?.close() }
            copies.clear()
        }
    }

    companion object {
        // One thread for every lyrics view, below the window's in priority.
        private val BlurWorker: Executor by lazy {
            Executors.newSingleThreadExecutor { task ->
                Thread(task, "Octo lyrics blur").apply {
                    isDaemon = true
                    priority = Thread.NORM_PRIORITY - 1
                }
            }
        }
    }
}

// `picture` blurred as a layer with `filter` would draw it, cut to what it
// covers and the blur's reach.
internal fun blurredCopy(picture: Picture, filter: ImageFilter, radius: Float, version: Int): BlurCopy {
    val drawn = picture.cullRect
    if (drawn.isEmpty) return BlurCopy(null, 0f, 0f, version, radius)
    val reach = blurReach(radius)
    val left = floor(drawn.left - reach)
    val top = floor(drawn.top - reach)
    val width = (ceil(drawn.right + reach) - left).toInt()
    val height = (ceil(drawn.bottom + reach) - top).toInt()
    val surface = Surface.makeRasterN32Premul(width, height)
    val blur = Paint().apply { imageFilter = filter }
    try {
        val canvas = surface.canvas
        canvas.translate(-left, -top)
        canvas.saveLayer(null, blur)
        canvas.drawPicture(picture)
        canvas.restore()
        return BlurCopy(surface.makeImageSnapshot(), left, top, version, radius)
    } finally {
        blur.close()
        surface.close()
    }
}
