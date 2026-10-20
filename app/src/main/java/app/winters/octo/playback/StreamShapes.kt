package app.winters.octo.playback

import android.net.Uri
import androidx.annotation.OptIn
import androidx.media3.common.util.UnstableApi
import androidx.media3.datasource.DataSource
import androidx.media3.datasource.DataSpec
import java.io.IOException
import java.util.Locale

// What a server answered a song's stream with: its type and the whole
// file's length, each when it said. A server can send a song as another
// file than it listed (a whole FLAC for a listed preview), so what is held
// or saved of one file is never continued with another's bytes.
data class StreamShape(val type: String?, val total: Long?) {
    // Whether two answers are of different files: both name a type and the
    // types differ, or both give a whole length and the lengths differ.
    // What one leaves out is no difference.
    fun differsFrom(other: StreamShape): Boolean {
        val a = plainType(type)
        val b = plainType(other.type)
        if (a != null && b != null && a != b) return true
        val x = total?.takeIf { it > 0 }
        val y = other.total?.takeIf { it > 0 }
        return x != null && y != null && x != y
    }
}

// A type without its parameters, or none for plain bytes, which name no file.
internal fun plainType(type: String?): String? =
    type?.substringBefore(';')?.trim()?.lowercase(Locale.ROOT)?.takeIf { it.isNotEmpty() && it != "application/octet-stream" }

// The shape of an answer from its headers: a part names the whole length
// after the slash of its Content-Range; an answer without one is the whole
// file, so its length is the whole.
fun streamShapeOf(headers: Map<String, List<String>>): StreamShape {
    fun header(name: String) = headers.entries.firstOrNull { it.key.equals(name, ignoreCase = true) }?.value?.firstOrNull()
    val range = header("Content-Range")
    val total = if (range != null) {
        range.substringAfterLast('/').trim().toLongOrNull()
    } else {
        header("Content-Length")?.trim()?.toLongOrNull()
    }
    return StreamShape(plainType(header("Content-Type")), total?.takeIf { it > 0 })
}

// What the saved copies know of the file each was saved from.
interface StreamShapes {
    fun shape(key: String): StreamShape?

    fun note(key: String, shape: StreamShape)

    // Lets a saved copy go, all of it.
    fun drop(key: String)
}

// The server began sending another file for a song than the one being read.
class StreamChanged : IOException("the server sent another file for this song")

// Checks every answer for a server song against the first one this reader
// had and the one its saved copy was made from. Another file lets the saved
// copy go and fails the load at once, so the song is opened again from its
// start instead of carrying on with the other file's bytes.
@OptIn(UnstableApi::class)
class ShapeGuardDataSource(
    private val upstream: DataSource,
    private val isStream: (Uri) -> Boolean,
    private val shapes: StreamShapes?,
) : DataSource by upstream {
    private var seen: StreamShape? = null

    override fun open(dataSpec: DataSpec): Long {
        val length = upstream.open(dataSpec)
        if (!isStream(dataSpec.uri)) return length
        val now = streamShapeOf(upstream.responseHeaders)
        val key = dataSpec.key
        val before = seen ?: key?.let { shapes?.shape(it) }
        if (before != null && before.differsFrom(now)) {
            upstream.close()
            seen = null
            key?.let { shapes?.drop(it) }
            throw StreamChanged()
        }
        seen = StreamShape(before?.type ?: now.type, before?.total ?: now.total)
        if (key != null) shapes?.note(key, now)
        return length
    }

    class Factory(private val upstream: DataSource.Factory, private val isStream: (Uri) -> Boolean, private val shapes: StreamShapes?) :
        DataSource.Factory {
        override fun createDataSource(): DataSource = ShapeGuardDataSource(upstream.createDataSource(), isStream, shapes)
    }
}

// Whether a failure came from the server sending another file for a song.
fun streamChangedIn(error: Throwable): Boolean = generateSequence(error) { it.cause }.take(16).any { it is StreamChanged }
