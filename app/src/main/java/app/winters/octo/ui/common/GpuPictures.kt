package app.winters.octo.ui.common

import android.graphics.Bitmap
import android.graphics.ColorSpace
import android.graphics.HardwareRenderer
import android.graphics.PixelFormat
import android.graphics.RecordingCanvas
import android.graphics.RenderNode
import android.hardware.HardwareBuffer
import android.media.Image
import android.media.ImageReader
import android.os.Build
import android.os.Handler
import android.os.Looper
import android.os.SystemClock
import androidx.annotation.RequiresApi

// Pictures drawn on the GPU away from the window. A RenderNode, with any
// blur or shader set on it, is drawn into a hardware bitmap, and the window
// then draws that bitmap as a plain picture.
//
// The window's renderer works out a node's RenderEffect again on every
// frame the window draws, whether or not anything under it changed (some
// phones keep no copy of the result). A blur that holds still, or one that
// changes less often than the window draws, costs that work only when it
// changes once it is a picture.

private val Srgb: ColorSpace by lazy { ColorSpace.get(ColorSpace.Named.SRGB) }

private const val PictureUsage = HardwareBuffer.USAGE_GPU_SAMPLED_IMAGE or HardwareBuffer.USAGE_GPU_COLOR_OUTPUT

// One picture after another, all one size, for something that changes
// over and over (a moving background). A new drawing is asked for with
// `draw`; it arrives on the main thread a moment later, as `latest`, and
// `onPicture` runs. Only one drawing is on its way at a time.
@RequiresApi(Build.VERSION_CODES.Q)
class GpuPictureStream(val width: Int, val height: Int) : AutoCloseable {
    private val reader = ImageReader.newInstance(width, height, PixelFormat.RGBA_8888, MaxImages, PictureUsage.toLong())
    private val root = RenderNode("gpu picture").apply { setPosition(0, 0, this@GpuPictureStream.width, this@GpuPictureStream.height) }
    private val renderer = HardwareRenderer().apply {
        isOpaque = false
        setContentRoot(root)
        setSurface(reader.surface)
    }

    // The images whose pictures may still be drawn: the one shown, and the
    // one before it, which a frame still on the GPU may be reading. Older
    // ones go back to the reader to be drawn into again.
    private val held = ArrayDeque<Image>()
    private var closed = false

    // A drawing asked for and not arrived yet, and since when.
    private var waiting = false
    private var askedAt = 0L

    // The newest picture, or null before the first arrives.
    var latest: Bitmap? = null
        private set

    // One bitmap for each of the reader's images, made the first time the
    // image comes round and reused after, so the window's renderer takes
    // each image up once rather than taking up a new bitmap every picture.
    // The images are only ever drawn into while no bitmap of theirs is
    // shown (`held`), so a bitmap reused shows its image's newest drawing.
    private val bitmaps = HashMap<Long, Bitmap>()

    var onPicture: (() -> Unit)? = null

    init {
        reader.setOnImageAvailableListener({ take(it) }, Handler(Looper.getMainLooper()))
    }

    // Asks for a new picture, drawn by `record` over the whole area. False,
    // and nothing drawn, while the last one is still on its way (unless it
    // is long overdue, as when the GPU dropped it).
    fun draw(record: (RecordingCanvas) -> Unit): Boolean {
        val now = SystemClock.uptimeMillis()
        if (closed || (waiting && now - askedAt < OverdueMs)) return false
        val canvas = root.beginRecording(width, height)
        try {
            record(canvas)
        } finally {
            root.endRecording()
        }
        waiting = true
        askedAt = now
        val result = renderer.createRenderRequest().setVsyncTime(System.nanoTime()).setWaitForPresent(false).syncAndDraw()
        if (result != HardwareRenderer.SYNC_OK) waiting = false
        return waiting
    }

    private fun take(reader: ImageReader) {
        val image = runCatching { reader.acquireNextImage() }.getOrNull() ?: return
        waiting = false
        if (closed) {
            image.close()
            return
        }
        val bitmap = image.hardwareBuffer?.use { buffer ->
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
                bitmaps[buffer.id] ?: Bitmap.wrapHardwareBuffer(buffer, Srgb)?.also { bitmaps[buffer.id] = it }
            } else {
                Bitmap.wrapHardwareBuffer(buffer, Srgb)
            }
        }
        if (bitmap == null) {
            image.close()
            return
        }
        held.addLast(image)
        while (held.size > HeldImages) held.removeFirst().close()
        latest = bitmap
        onPicture?.invoke()
    }

    override fun close() {
        if (closed) return
        closed = true
        onPicture = null
        renderer.destroy()
        root.discardDisplayList()
        held.forEach { it.close() }
        held.clear()
        latest = null
        bitmaps.clear()
        reader.close()
    }

    private companion object {
        // Two held, one being drawn into, and one to spare, so the drawing
        // never waits for a free image.
        const val HeldImages = 2
        const val MaxImages = 4
        const val OverdueMs = 250L
    }
}

// One finished picture: its bitmap, and the reader it came from, which
// `release` lets go. Nothing draws into the bitmap again, so it stays
// drawable for whatever still holds it.
class GpuPicture internal constructor(val bitmap: Bitmap, private val image: Image, private val reader: ImageReader) {
    private var released = false

    fun release() {
        if (released) return
        released = true
        image.close()
        reader.close()
    }
}

// Pictures made one at a time, each its own size, for things drawn once and
// then shown for a while (a blurred line of lyrics). Each request is drawn
// in turn; its picture comes back on the main thread through `done`, or
// null when it could not be made or the maker was closed first.
@RequiresApi(Build.VERSION_CODES.Q)
class GpuPictureMaker : AutoCloseable {
    private class Request(val width: Int, val height: Int, val record: (RecordingCanvas) -> Unit, val done: (GpuPicture?) -> Unit)

    private val root = RenderNode("gpu picture")
    private val renderer = HardwareRenderer().apply {
        isOpaque = false
        setContentRoot(root)
    }
    private val queue = ArrayDeque<Request>()
    private val main = Handler(Looper.getMainLooper())
    private var current: Pair<Request, ImageReader>? = null
    private var closed = false

    // Asks for a picture `width` by `height`, drawn by `record`.
    fun make(width: Int, height: Int, record: (RecordingCanvas) -> Unit, done: (GpuPicture?) -> Unit) {
        if (closed || width <= 0 || height <= 0) {
            done(null)
            return
        }
        queue.addLast(Request(width, height, record, done))
        if (current == null) next()
    }

    private fun next() {
        val request = queue.removeFirstOrNull() ?: return
        val reader = runCatching {
            ImageReader.newInstance(request.width, request.height, PixelFormat.RGBA_8888, 1, PictureUsage.toLong())
        }.getOrNull()
        if (reader == null) {
            request.done(null)
            next()
            return
        }
        current = request to reader
        reader.setOnImageAvailableListener({ take(request, it) }, main)
        root.setPosition(0, 0, request.width, request.height)
        val canvas = root.beginRecording(request.width, request.height)
        try {
            request.record(canvas)
        } finally {
            root.endRecording()
        }
        renderer.setSurface(reader.surface)
        val result = renderer.createRenderRequest().setVsyncTime(System.nanoTime()).setWaitForPresent(false).syncAndDraw()
        if (result != HardwareRenderer.SYNC_OK) finish(request, reader, null)
    }

    private fun take(request: Request, reader: ImageReader) {
        if (current?.first !== request) return
        val image = runCatching { reader.acquireNextImage() }.getOrNull()
        val bitmap = image?.hardwareBuffer?.use { Bitmap.wrapHardwareBuffer(it, Srgb) }
        val picture = if (image != null && bitmap != null) GpuPicture(bitmap, image, reader) else null
        if (picture == null) image?.close()
        finish(request, reader, picture)
    }

    private fun finish(request: Request, reader: ImageReader, picture: GpuPicture?) {
        current = null
        renderer.setSurface(null)
        reader.setOnImageAvailableListener(null, null)
        if (picture == null) reader.close()
        if (closed) {
            picture?.release()
            request.done(null)
            return
        }
        request.done(picture)
        next()
    }

    override fun close() {
        if (closed) return
        closed = true
        current?.let { (request, reader) ->
            current = null
            reader.close()
            request.done(null)
        }
        while (queue.isNotEmpty()) queue.removeFirst().done(null)
        renderer.destroy()
        root.discardDisplayList()
    }
}
