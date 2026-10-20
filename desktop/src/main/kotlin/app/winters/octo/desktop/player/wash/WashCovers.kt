package app.winters.octo.desktop.player.wash

import app.winters.octo.player.immersive.relativeLuminance
import app.winters.octo.player.immersive.WashSize
import app.winters.octo.player.immersive.WashTuning
import app.winters.octo.player.immersive.applyColorMatrix
import app.winters.octo.player.immersive.capBrightness
import app.winters.octo.player.immersive.washColorMatrix
import app.winters.octo.player.immersive.WashRange
import app.winters.octo.player.immersive.washRange
import app.winters.octo.player.immersive.washPeak
import app.winters.octo.desktop.library.CoverArrivals
import app.winters.octo.desktop.library.coverPicture
import app.winters.octo.subsonic.SubsonicClient
import coil3.ImageLoader
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Deferred
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.async
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.first
import kotlinx.coroutines.flow.flow
import kotlinx.coroutines.withContext
import kotlinx.coroutines.withTimeoutOrNull
import okhttp3.OkHttpClient
import okhttp3.Request
import org.jetbrains.skia.Bitmap
import org.jetbrains.skia.Canvas
import org.jetbrains.skia.ColorAlphaType
import org.jetbrains.skia.ColorType
import org.jetbrains.skia.FilterMipmap
import org.jetbrains.skia.FilterMode
import org.jetbrains.skia.Image
import org.jetbrains.skia.ImageInfo
import org.jetbrains.skia.MipmapMode
import org.jetbrains.skia.Paint
import org.jetbrains.skia.Rect
import org.jetbrains.skia.Surface
import app.winters.octo.desktop.ui.LateClose

// A cover made ready for the background: the 512 square the wash draws
// from, the darkest and brightest patches of it (`washRange`), from which
// the words over it take their colour, its main colour as ARGB, which
// tints the app's glass while it plays, and the brightest the wash over it
// gets (`washPeak`), for words on the pages, and the brightest of the cover
// itself (`glowPeak`), for the glow, which draws the cover as it is.
class WashCover(
    val key: String,
    val square: Image,
    val range: WashRange,
    val main: Int = 0,
    val peak: Int = 0xFF000000.toInt(),
    val glowPeak: Int = peak,
) {
    // Closed once the covers let it go (see WashCovers), after the frame
    // that last drew it.
    @Volatile var closed = false
        private set

    // A copy of the square of its own, for drawing from after this cover is
    // let go; null once it is closed. On the window's thread, where it
    // closes.
    fun hold(): Image? {
        if (closed) return null
        val surface = Surface.makeRasterN32Premul(square.width, square.height)
        try {
            surface.canvas.drawImage(square, 0f, 0f)
            return surface.makeImageSnapshot()
        } finally {
            surface.close()
        }
    }

    // Closes the square after the next whole frame.
    fun retire() {
        LateClose.close {
            closed = true
            square.close()
        }
    }
}

// How long the wash waits before asking again for a cover the server did
// not send, each time; then it keeps the blend.
val WASH_RETRY_MS = listOf(3_000L, 8_000L, 20_000L, 60_000L, 120_000L)

// How long a cover the server did not send at once is waited for before
// the blend stands in: an outside song's often comes a moment later, as
// Octo finds it, and the wash went to the blend and straight on to it.
const val WASH_HOLD_MS = 1_500L

// The size covers are fetched at for the wash, which draws them at 512.
private const val WashFetchPx = 600

// The pixels of a 512 square, as ARGB, and back.
private val SquareInfo = ImageInfo(WashSize, WashSize, ColorType.BGRA_8888, ColorAlphaType.PREMUL)

// Prepares covers for the background off the main thread, as the phone
// does: cropped to the middle square and brought to 512, then contrast and
// saturation through the colour matrix and the brightness cap, pixel by
// pixel, with the shared maths. The last few are kept, so going back a
// song is instant. A cover the server did not send is not kept: the soft
// blend stands in for it, and it is asked for again (see follow). With an
// image loader from `images`, covers come through it, sharing its caches
// and its downloads with every other place that shows them; without, they
// are downloaded here.
class WashCovers(
    private val http: OkHttpClient,
    private val retryMs: List<Long> = WASH_RETRY_MS,
    private val holdMs: Long = WASH_HOLD_MS,
    private val images: () -> ImageLoader? = { null },
) {
    // Whoever draws a kept cover draws from a hold of their own, so the one
    // let go here closes.
    private val kept = object : LinkedHashMap<String, WashCover>(8, 0.75f, true) {
        override fun removeEldestEntry(eldest: MutableMap.MutableEntry<String, WashCover>?): Boolean {
            if (size <= 4) return false
            eldest?.value?.retire()
            return true
        }
    }

    // One fetch per cover at a time, however many places draw it.
    private val work = CoroutineScope(SupervisorJob() + Dispatchers.IO)
    private val fetching = HashMap<String, Deferred<Made>>()

    // A cover made ready, and whether it is the real one: false while the
    // server has not sent it, and the blend stands in.
    private class Made(val cover: WashCover, val real: Boolean)

    suspend fun prepare(client: SubsonicClient?, coverId: String?, tuning: WashTuning): WashCover = make(client, coverId, tuning).cover

    // The cover made ready, and again once it can be had when the server
    // did not send it: after a while, a few times, and at once when the
    // same cover comes in anywhere on screen. One that did not come at
    // once is waited for a moment before the blend is sent, so the cover
    // before stays meanwhile.
    fun follow(client: SubsonicClient?, coverId: String?, tuning: WashTuning): Flow<WashCover> = flow {
        var made = make(client, coverId, tuning)
        if (!made.real && holdMs > 0) {
            withTimeoutOrNull(holdMs) { CoverArrivals.arrived.first { it == coverId } }
            made = make(client, coverId, tuning)
        }
        emit(made.cover)
        for (wait in retryMs) {
            if (made.real) return@flow
            withTimeoutOrNull(wait) { CoverArrivals.arrived.first { it == coverId } }
            made = make(client, coverId, tuning)
            if (made.real) emit(made.cover)
        }
    }

    private suspend fun make(client: SubsonicClient?, coverId: String?, tuning: WashTuning): Made {
        val key = "${client?.primaryUrl?.host}|$coverId|${tuning.contrast}|${tuning.saturation}|${tuning.brightnessCap}"
        synchronized(kept) { kept[key] }?.let { return Made(it, true) }
        val job = synchronized(fetching) { fetching.getOrPut(key) { work.async { fetch(key, client, coverId, tuning) } } }
        return try {
            job.await()
        } finally {
            synchronized(fetching) { if (fetching[key] === job) fetching.remove(key) }
        }
    }

    private suspend fun fetch(key: String, client: SubsonicClient?, coverId: String?, tuning: WashTuning): Made {
        val loader = images()
        val image = when {
            client == null || coverId == null -> null
            loader != null -> runCatching { coverPicture(loader, client, coverId, WashFetchPx) }.getOrNull()
            else -> runCatching {
                http.newCall(Request.Builder().url(client.coverArtUrl(coverId, WashFetchPx)).build()).execute().use { r ->
                    if (r.isSuccessful) r.body.bytes() else null
                }
            }.getOrNull()?.let { runCatching { Image.makeFromEncoded(it) }.getOrNull() }
        }
        // With no cover to ask for, the blend is the answer, and is kept.
        val real = image != null || client == null || coverId == null
        // The blend standing in for a cover not sent yet is the same for
        // every cover, so one is made for each tuning and kept.
        if (!real) return Made(standIn(tuning), false)
        val cover = try {
            withContext(Dispatchers.Default) { prepared(key, image, tuning) }
        } finally {
            image?.close()
        }
        synchronized(kept) { kept.put(key, cover)?.takeIf { it !== cover }?.retire() }
        return Made(cover, true)
    }

    private val standIns = HashMap<String, WashCover>()

    private suspend fun standIn(tuning: WashTuning): WashCover {
        val key = "blend|${tuning.contrast}|${tuning.saturation}|${tuning.brightnessCap}"
        synchronized(standIns) { standIns[key] }?.let { return it }
        val made = withContext(Dispatchers.Default) { prepared(key, null, tuning) }
        return synchronized(standIns) {
            standIns[key] ?: made.also {
                // A tuning changed in Settings leaves the one before.
                standIns.values.forEach(WashCover::retire)
                standIns.clear()
                standIns[key] = it
            }
        }.also { if (it !== made) made.square.close() }
    }

    companion object {
        // A cover image through every step; with none, a soft dark blend.
        fun prepared(key: String, source: Image?, tuning: WashTuning): WashCover {
            val bytes = if (source == null) {
                ByteArray(WashSize * WashSize * 4)
            } else {
                val bitmap = Bitmap()
                val canvas: Canvas
                val paint = Paint()
                try {
                    bitmap.allocPixels(SquareInfo)
                    canvas = Canvas(bitmap)
                    val side = minOf(source.width, source.height).toFloat()
                    val crop = Rect.makeXYWH((source.width - side) / 2f, (source.height - side) / 2f, side, side)
                    canvas.drawImageRect(
                        source,
                        crop,
                        Rect.makeWH(WashSize.toFloat(), WashSize.toFloat()),
                        FilterMipmap(FilterMode.LINEAR, MipmapMode.LINEAR),
                        paint,
                        true,
                    )
                    canvas.close()
                    bitmap.readPixels(SquareInfo, WashSize * 4, 0, 0) ?: ByteArray(WashSize * WashSize * 4)
                } finally {
                    paint.close()
                    bitmap.close()
                }
            }
            val pixels = if (source == null) {
                blend()
            } else {
                IntArray(WashSize * WashSize) { i ->
                    val o = i * 4
                    // BGRA in memory.
                    (0xFF shl 24) or ((bytes[o + 2].toInt() and 0xFF) shl 16) or ((bytes[o + 1].toInt() and 0xFF) shl 8) or (bytes[o].toInt() and 0xFF)
                }
            }
            val dominant = dominantColour(pixels)
            // Before the wash's own tuning: the glow shows the cover untouched.
            val raw = if (source == null) 0xFF000000.toInt() else brightest(pixels)
            val matrix = washColorMatrix(tuning)
            for (i in pixels.indices) pixels[i] = capBrightness(applyColorMatrix(pixels[i], matrix), tuning.brightnessCap)
            for (i in pixels.indices) {
                val p = pixels[i]
                val o = i * 4
                bytes[o] = (p and 0xFF).toByte()
                bytes[o + 1] = (p shr 8 and 0xFF).toByte()
                bytes[o + 2] = (p shr 16 and 0xFF).toByte()
                bytes[o + 3] = 0xFF.toByte()
            }
            // The image keeps the bitmap's pixels; the bitmap itself goes.
            val out = Bitmap()
            val square = try {
                out.allocPixels(SquareInfo)
                out.installPixels(SquareInfo, bytes, WashSize * 4)
                out.setImmutable()
                Image.makeFromBitmap(out)
            } finally {
                out.close()
            }
            return WashCover(key, square, washRange(pixels, WashSize), dominant, washPeak(pixels), raw)
        }

        // The cover's brightest colour, leaving out the brightest fiftieth
        // (a few specks), as `washPeak` finds the wash's.
        fun brightest(pixels: IntArray, step: Int = 7): Int {
            val picked = IntArray((pixels.size + step - 1) / step) { pixels[it * step] }
            return picked.sortedBy { relativeLuminance(it) }[((picked.size - 1) * 0.98f).toInt()]
        }

        // For music without a cover: three quiet colours, blended corner to
        // corner.
        private fun blend(): IntArray {
            val stops = intArrayOf(0xFF2A2F45.toInt(), 0xFF3C2533.toInt(), 0xFF1C3A3A.toInt())
            fun mix(a: Int, b: Int, t: Float): Int {
                fun ch(shift: Int) = ((a shr shift and 0xFF) + ((b shr shift and 0xFF) - (a shr shift and 0xFF)) * t).toInt()
                return (0xFF shl 24) or (ch(16) shl 16) or (ch(8) shl 8) or ch(0)
            }
            return IntArray(WashSize * WashSize) { i ->
                val t = ((i % WashSize) + (i / WashSize)) / (2f * (WashSize - 1))
                if (t < 0.5f) mix(stops[0], stops[1], t * 2) else mix(stops[1], stops[2], t * 2 - 1)
            }
        }

        // The cover's main colour, as a palette's dominant swatch picks it
        // (shared with the playlist covers).
        fun dominantColour(pixels: IntArray): Int = app.winters.octo.covers.dominantColour(pixels)
    }
}
