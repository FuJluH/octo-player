package app.winters.octo.desktop.library

import androidx.compose.ui.graphics.ImageBitmap
import androidx.compose.ui.graphics.asComposeImageBitmap
import androidx.compose.ui.graphics.asSkiaBitmap
import androidx.compose.ui.graphics.toComposeImageBitmap
import androidx.compose.ui.text.font.createFontFamilyResolver
import app.winters.octo.covers.CoverBackground
import app.winters.octo.covers.CoverBackgrounds
import app.winters.octo.covers.CoverGlyph
import app.winters.octo.covers.CoverPalette
import app.winters.octo.covers.CoverSpec
import app.winters.octo.covers.Swatch
import app.winters.octo.covers.coverArtKey
import app.winters.octo.covers.coverFileName
import app.winters.octo.covers.coverPalette
import app.winters.octo.covers.coverSwatches
import app.winters.octo.covers.quarterSwatches
import app.winters.octo.desktop.lruMap
import app.winters.octo.design.CoverFontFamily
import app.winters.octo.design.coverMeasurer
import app.winters.octo.design.designCover
import app.winters.octo.subsonic.SubsonicClient
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.sync.Semaphore
import kotlinx.coroutines.sync.withPermit
import kotlinx.coroutines.withContext
import okhttp3.OkHttpClient
import okhttp3.Request
import org.jetbrains.skia.Bitmap
import org.jetbrains.skia.Canvas
import org.jetbrains.skia.ColorAlphaType
import org.jetbrains.skia.ColorType
import org.jetbrains.skia.EncodedImageFormat
import org.jetbrains.skia.FilterMipmap
import org.jetbrains.skia.FilterMode
import org.jetbrains.skia.Image
import org.jetbrains.skia.ImageInfo
import org.jetbrains.skia.MipmapMode
import org.jetbrains.skia.Paint
import org.jetbrains.skia.Rect
import java.io.File

// What a designed cover is made from: the list's id, name, its light line
// and foot line, and the covers its colours come from, with `quarters` when
// the one picture is a server's four-cover square. `stamp` changes when the
// list does, so its colours are worked out again. `coverTitle` and `glyph`
// are as CoverSpec has them.
data class CoverOrder(
    val id: String,
    val name: String,
    val line: String?,
    val footer: String?,
    val sources: List<String>,
    val quarters: Boolean = false,
    val stamp: String? = null,
    val coverTitle: String? = null,
    val glyph: CoverGlyph? = null,
)

// Designed playlist covers: their colours, from the lists' first covers,
// and the pictures, drawn at the size shown. Both are kept in memory and,
// once `folder` is set, on disk, so a list's cover is drawn once.
class PlaylistArtStore(private val http: OkHttpClient) {
    // Where covers are kept between runs; none in tests.
    @Volatile var folder: File? = null

    // The lists' colours, the ones used last kept: a long run through the
    // library touches a great many lists, and each one's colours are small
    // but never thrown out on their own.
    private val palettes = lruMap<String, CoverPalette>(PalettesKept)
    private val pictures = object : LinkedHashMap<String, ImageBitmap>(64, 0.75f, true) {
        var bytes = 0L

        override fun removeEldestEntry(eldest: MutableMap.MutableEntry<String, ImageBitmap>): Boolean {
            if (bytes <= MemoryBytes) return false
            bytes -= eldest.value.width.toLong() * eldest.value.height * 4
            return true
        }
    }

    // One at a time: the text engine's font cache is not safe to fill from
    // two threads at once (two first draws crashed Skia registering the
    // fonts), and one thread also keeps a sidebar of playlists off every core.
    private val drawing = Semaphore(1)
    private val fonts by lazy { createFontFamilyResolver() }
    private var written = 0

    fun knownPalette(key: String): CoverPalette? = synchronized(palettes) { palettes[key] }

    fun known(key: String): ImageBitmap? = synchronized(pictures) { pictures[key] }

    // The list's colours: kept, or worked out from its covers. With no
    // covers to be had (none, or the server did not answer) the list's own,
    // not kept, so they are asked for again next time.
    suspend fun palette(client: SubsonicClient?, order: CoverOrder, key: String): CoverPalette {
        knownPalette(key)?.let { return it }
        val file = folder?.let { File(File(it, "palettes"), coverFileName(key, "txt")) }
        val stored = withContext(Dispatchers.IO) { file?.takeIf(File::isFile)?.let { runCatching { it.readText() }.getOrNull() } }
        stored?.let { text -> readPalette(text)?.let { return remember(key, it) } }
        if (client == null || order.sources.isEmpty()) return coverPalette(emptyList(), order.id)
        val pictures = withContext(Dispatchers.IO) { order.sources.map { fetchPixels(client, it) } }
        if (pictures.any { it == null }) return coverPalette(emptyList(), order.id)
        val swatches: List<List<Swatch>> = withContext(Dispatchers.Default) {
            if (order.quarters && pictures.size == 1) quarterSwatches(pictures[0]!!, SampleSize) else pictures.map { coverSwatches(it!!) }
        }
        val palette = coverPalette(swatches, order.id)
        if (file != null) withContext(Dispatchers.IO) { runCatching { file.parentFile.mkdirs(); file.writeText(writePalette(palette)) } }
        return remember(key, palette)
    }

    private fun remember(key: String, palette: CoverPalette) = palette.also { synchronized(palettes) { palettes[key] = it } }

    // The cover drawn `side` pixels square: kept, or drawn now off the
    // window's thread.
    suspend fun art(spec: CoverSpec, side: Int): ImageBitmap {
        val key = coverArtKey(spec, side)
        known(key)?.let { return it }
        val file = folder?.let { File(File(it, "art"), coverFileName(key, "png")) }
        val stored = withContext(Dispatchers.IO) {
            file?.takeIf(File::isFile)?.let { runCatching { Image.makeFromEncoded(it.readBytes()).use { it.toComposeImageBitmap() } }.getOrNull() }
        }
        if (stored != null) return keep(key, stored)
        val drawn = drawing.withPermit {
            withContext(Dispatchers.Default) { designCover(spec, side, coverMeasurer(fonts), CoverFontFamily, ::backgroundPixels, ::pictureOf) }
        }
        if (file != null) withContext(Dispatchers.IO) { save(file, drawn) }
        return keep(key, drawn)
    }

    // The library's backgrounds as pixels, the last few kept: a sidebar of
    // lists often shares one.
    private val backgrounds = object : LinkedHashMap<String, Pair<IntArray, Int>>(8, 0.75f, true) {
        override fun removeEldestEntry(eldest: MutableMap.MutableEntry<String, Pair<IntArray, Int>>) = size > 4
    }

    private fun backgroundPixels(background: CoverBackground): Pair<IntArray, Int> = synchronized(backgrounds) {
        backgrounds.getOrPut(background.file) { decodePixels(CoverBackgrounds.bytes(background.file)) }
    }

    private fun keep(key: String, image: ImageBitmap): ImageBitmap = synchronized(pictures) {
        // Only the difference is counted: the same cover drawn at a bigger
        // size replaces the one kept, and the tally that lets the map know
        // its own weight has to follow it.
        val replaced = pictures.put(key, image)
        pictures.bytes += image.width.toLong() * image.height * 4 - (replaced?.let { it.width.toLong() * it.height * 4 } ?: 0L)
        image
    }

    private fun save(file: File, image: ImageBitmap) {
        runCatching {
            file.parentFile.mkdirs()
            val png = Image.makeFromBitmap(image.asSkiaBitmap()).use { it.encodeToData(EncodedImageFormat.PNG) }?.bytes ?: return
            val temp = File(file.parentFile, file.name + ".tmp")
            temp.writeBytes(png)
            if (!temp.renameTo(file)) temp.delete()
        }
        if (++written % TrimEvery == 0) trim(file.parentFile)
    }

    // Keeps the folder under its budget, the oldest pictures going first.
    private fun trim(folder: File) {
        val files = folder.listFiles { f -> f.isFile && f.name.endsWith(".png") }?.sortedBy { it.lastModified() } ?: return
        var total = files.sumOf { it.length() }
        for (f in files) {
            if (total <= DiskBytes) break
            total -= f.length()
            f.delete()
        }
    }

    private fun fetchPixels(client: SubsonicClient, coverId: String): IntArray? = runCatching {
        http.newCall(Request.Builder().url(client.coverArtUrl(coverId, 150)).build()).execute().use { response ->
            if (!response.isSuccessful) return null
            coverPixels(response.body.bytes())
        }
    }.getOrNull()

    companion object {
        private const val MemoryBytes = 64L * 1024 * 1024
        private const val DiskBytes = 96L * 1024 * 1024
        private const val TrimEvery = 40

        // How many lists' colours are remembered at once.
        private const val PalettesKept = 512

        // Covers are looked at this small: plenty for their colours.
        const val SampleSize = 64

        fun writePalette(palette: CoverPalette): String = palette.key + if (palette.fromMusic) " music" else " own"

        fun readPalette(text: String): CoverPalette? {
            val (key, from) = text.trim().split(' ').takeIf { it.size == 2 } ?: return null
            return CoverPalette.fromKey(key, fromMusic = from == "music")
        }

        // A picture (the backgrounds are WebP, which Skia reads) at its own
        // size, as ARGB pixels and its side.
        fun decodePixels(bytes: ByteArray): Pair<IntArray, Int> {
            val image = Image.makeFromEncoded(bytes)
            try {
                val side = image.width
                val info = ImageInfo(side, image.height, ColorType.BGRA_8888, ColorAlphaType.PREMUL)
                val bitmap = Bitmap()
                try {
                    bitmap.allocPixels(info)
                    Canvas(bitmap).use { it.drawImage(image, 0f, 0f) }
                    val raw = bitmap.readPixels(info, side * 4, 0, 0)!!
                    return IntArray(side * image.height) { i ->
                        val o = i * 4
                        (0xFF shl 24) or ((raw[o + 2].toInt() and 0xFF) shl 16) or ((raw[o + 1].toInt() and 0xFF) shl 8) or (raw[o].toInt() and 0xFF)
                    } to side
                } finally {
                    bitmap.close()
                }
            } finally {
                // The pixels come out as an IntArray, so nothing here outlives
                // the call: a sidebar of lists re-decodes a background every
                // time one falls out of the four kept.
                image.close()
            }
        }

        // ARGB pixels, `side` square, as a picture.
        fun pictureOf(pixels: IntArray, side: Int): ImageBitmap {
            val info = ImageInfo(side, side, ColorType.BGRA_8888, ColorAlphaType.PREMUL)
            val bytes = ByteArray(side * side * 4)
            for (i in pixels.indices) {
                val p = pixels[i]
                val o = i * 4
                bytes[o] = (p and 0xFF).toByte()
                bytes[o + 1] = (p shr 8 and 0xFF).toByte()
                bytes[o + 2] = (p shr 16 and 0xFF).toByte()
                bytes[o + 3] = 0xFF.toByte()
            }
            val bitmap = Bitmap()
            bitmap.allocPixels(info)
            bitmap.installPixels(info, bytes, side * 4)
            bitmap.setImmutable()
            return bitmap.asComposeImageBitmap()
        }

        // A picture's pixels at 64 square, as ARGB.
        fun coverPixels(bytes: ByteArray): IntArray? {
            val source = runCatching { Image.makeFromEncoded(bytes) }.getOrNull() ?: return null
            try {
                val info = ImageInfo(SampleSize, SampleSize, ColorType.BGRA_8888, ColorAlphaType.PREMUL)
                val bitmap = Bitmap()
                val paint = Paint()
                try {
                    bitmap.allocPixels(info)
                    Canvas(bitmap).use { canvas ->
                        canvas.drawImageRect(
                            source,
                            Rect.makeWH(source.width.toFloat(), source.height.toFloat()),
                            Rect.makeWH(SampleSize.toFloat(), SampleSize.toFloat()),
                            FilterMipmap(FilterMode.LINEAR, MipmapMode.LINEAR),
                            paint,
                            true,
                        )
                    }
                    val raw = bitmap.readPixels(info, SampleSize * 4, 0, 0) ?: return null
                    return IntArray(SampleSize * SampleSize) { i ->
                        val o = i * 4
                        (0xFF shl 24) or ((raw[o + 2].toInt() and 0xFF) shl 16) or ((raw[o + 1].toInt() and 0xFF) shl 8) or (raw[o].toInt() and 0xFF)
                    }
                } finally {
                    paint.close()
                    bitmap.close()
                }
            } finally {
                source.close()
            }
        }
    }
}
