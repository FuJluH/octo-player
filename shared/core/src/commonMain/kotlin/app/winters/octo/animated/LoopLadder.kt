package app.winters.octo.animated

import okhttp3.HttpUrl

// The highest bit rate picked among same-size versions of a loop. Above it
// the file grows (a 24 s loop at 6 Mbit/s is about 18 MB) with no gain a
// cover can show.
const val LOOP_MAX_BANDWIDTH = 6_000_000L

// The video formats a loop comes in.
enum class LoopCodec { Avc, Hevc }

// One version of a loop that an HLS playlist offers.
data class LoopVariant(
    val url: HttpUrl,
    val bandwidth: Long,
    val width: Int,
    val height: Int,
    val codecs: String,
) {
    val codec: LoopCodec?
        get() = when {
            codecs.startsWith("avc1") || codecs.startsWith("avc3") -> LoopCodec.Avc
            codecs.startsWith("hvc1") || codecs.startsWith("hev1") -> LoopCodec.Hevc
            else -> null
        }
}

// The versions an HLS playlist offers (its EXT-X-STREAM-INF lines; the
// still-frame lists are skipped), with whole addresses.
fun parseLoopLadder(playlist: String, playlistUrl: HttpUrl): List<LoopVariant> {
    val lines = playlist.lineSequence().map(String::trim).toList()
    val found = mutableListOf<LoopVariant>()
    for ((index, line) in lines.withIndex()) {
        if (!line.startsWith("#EXT-X-STREAM-INF:")) continue
        val uri = lines.drop(index + 1).firstOrNull { it.isNotEmpty() && !it.startsWith("#") } ?: continue
        val attributes = hlsAttributes(line.substringAfter(':'))
        val url = playlistUrl.resolve(uri) ?: continue
        val (width, height) = attributes["RESOLUTION"]?.split('x')?.mapNotNull(String::toIntOrNull)
            ?.takeIf { it.size == 2 }?.let { it[0] to it[1] } ?: (0 to 0)
        found += LoopVariant(
            url = url,
            bandwidth = attributes["BANDWIDTH"]?.toLongOrNull() ?: 0L,
            width = width,
            height = height,
            codecs = attributes["CODECS"].orEmpty(),
        )
    }
    return found
}

// The version to show in a space `width` by `height` pixels, scaled to
// cover it: the smallest one in a format the device plays that needs no
// enlarging (else the largest), and of those the same-size one with the
// highest bit rate up to LOOP_MAX_BANDWIDTH (else the lowest).
fun pickLoopVariant(
    variants: List<LoopVariant>,
    width: Int,
    height: Int,
    codecs: Set<LoopCodec> = setOf(LoopCodec.Avc),
): LoopVariant? {
    val playable = variants.filter { it.codec in codecs && it.width > 0 && it.height > 0 }
    if (playable.isEmpty()) return null
    val wantW = width.coerceAtLeast(1).toDouble()
    val wantH = height.coerceAtLeast(1).toDouble()
    fun enlarges(v: LoopVariant) = maxOf(wantW / v.width, wantH / v.height) > 1.0
    val area = { v: LoopVariant -> v.width.toLong() * v.height }
    val size = playable.filterNot(::enlarges).minByOrNull(area) ?: playable.maxBy(area)
    val sameSize = playable.filter { it.width == size.width && it.height == size.height }
    return sameSize.filter { it.bandwidth <= LOOP_MAX_BANDWIDTH }.maxByOrNull { it.bandwidth }
        ?: sameSize.minBy { it.bandwidth }
}

// A loop version kept in one file, as Apple's are: the playlist's map and
// every part name the same file, so the whole file is the whole loop.
data class LoopFile(val url: HttpUrl, val seconds: Double)

// The one file a version's playlist reads its parts from, or null when the
// parts come from more than one file.
fun parseLoopFile(playlist: String, playlistUrl: HttpUrl): LoopFile? {
    val files = mutableSetOf<String>()
    var seconds = 0.0
    for (raw in playlist.lineSequence()) {
        val line = raw.trim()
        when {
            line.isEmpty() -> Unit
            line.startsWith("#EXT-X-MAP:") -> hlsAttributes(line.substringAfter(':'))["URI"]?.let { files += it }
            line.startsWith("#EXTINF:") -> seconds += line.substringAfter(':').substringBefore(',').trim().toDoubleOrNull() ?: 0.0
            line.startsWith("#") -> Unit
            else -> files += line
        }
    }
    val only = files.singleOrNull() ?: return null
    val url = playlistUrl.resolve(only) ?: return null
    return LoopFile(url, seconds)
}

// An HLS tag's attributes, NAME=value or NAME="value, with commas".
internal fun hlsAttributes(text: String): Map<String, String> {
    val found = mutableMapOf<String, String>()
    var at = 0
    while (at < text.length) {
        val eq = text.indexOf('=', at).takeIf { it >= 0 } ?: break
        val name = text.substring(at, eq).trim().trimStart(',').trim()
        val end: Int
        val value: String
        if (eq + 1 < text.length && text[eq + 1] == '"') {
            val close = text.indexOf('"', eq + 2).takeIf { it >= 0 } ?: text.length
            value = text.substring(eq + 2, close)
            end = close + 1
        } else {
            val comma = text.indexOf(',', eq + 1).takeIf { it >= 0 } ?: text.length
            value = text.substring(eq + 1, comma)
            end = comma
        }
        found[name] = value
        at = end + 1
    }
    return found
}
