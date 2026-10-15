package app.winters.octo.animated

import app.winters.octo.subsonic.AnimatedClip
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.suspendCancellableCoroutine
import kotlinx.coroutines.withContext
import okhttp3.Call
import okhttp3.Callback
import okhttp3.HttpUrl
import okhttp3.HttpUrl.Companion.toHttpUrlOrNull
import okhttp3.OkHttpClient
import okhttp3.Request
import okhttp3.Response
import java.io.File
import java.io.IOException
import java.security.MessageDigest
import kotlin.coroutines.resumeWithException

// The longest playlist read, and the largest loop file kept. Apple's
// playlists are a few KB and their loops a few MB.
private const val PLAYLIST_LIMIT = 512 * 1024L
private const val LOOP_FILE_LIMIT = 64L * 1024 * 1024

// Finds and fetches loop files: the version of a clip that suits a space
// on screen, as the one file it is kept in. `http` must carry the
// server's own headers (a proxy's access token), as a relayed clip's
// addresses lead to the server.
class LoopFetcher(private val http: OkHttpClient) {
    // The file of the clip's version that suits a space `width` by
    // `height` pixels in a format the device plays, or null when the clip
    // offers none or cannot be read just now.
    suspend fun locate(clip: AnimatedClip, width: Int, height: Int, codecs: Set<LoopCodec> = setOf(LoopCodec.Avc)): LoopFile? {
        val variant = pick(clip, width, height, codecs)?.url ?: return null
        return text(variant)?.let { parseLoopFile(it, variant) }
    }

    // The version of the clip that suits a space `width` by `height` pixels
    // in a format the device plays, as its own playlist: a player given it
    // has that one version only, so it never starts small and steps up.
    // Null when the clip offers none or cannot be read just now.
    suspend fun pick(clip: AnimatedClip, width: Int, height: Int, codecs: Set<LoopCodec> = setOf(LoopCodec.Avc)): LoopVariant? {
        val master = clip.video.toHttpUrlOrNull() ?: return null
        val ladder = text(master)?.let { parseLoopLadder(it, master) } ?: return null
        // A playlist with no versions is itself a version's playlist.
        if (ladder.isEmpty()) return LoopVariant(master, 0L, clip.width, clip.height, "")
        return pickLoopVariant(ladder, width, height, codecs)
    }

    // Puts the loop's file at `target` unless it is there already: through
    // a ".part" file beside it, so a half-fetched file is never taken for a
    // whole one. True when the file is there.
    suspend fun fetch(file: LoopFile, target: File): Boolean = fetchTo(file.url, target, LOOP_FILE_LIMIT)

    // Puts a clip's still at `target` unless it is there already.
    suspend fun fetchPoster(clip: AnimatedClip, target: File): Boolean {
        val url = clip.poster?.toHttpUrlOrNull() ?: return false
        return fetchTo(url, target, 16L * 1024 * 1024)
    }

    private suspend fun fetchTo(url: HttpUrl, target: File, limit: Long): Boolean {
        if (target.isFile && target.length() > 0) return true
        val response = runCatching { http.newCall(Request.Builder().url(url).build()).awaitResponse() }.getOrNull() ?: return false
        return withContext(Dispatchers.IO) {
            response.use {
                if (!it.isSuccessful) return@withContext false
                val length = it.body.contentLength()
                if (length > limit) return@withContext false
                target.parentFile?.mkdirs()
                val part = File(target.path + ".part")
                val whole = runCatching {
                    part.outputStream().use { out ->
                        val read = it.body.byteStream().copyTo(out)
                        read > 0 && read <= limit && (length < 0 || read == length)
                    }
                }.getOrDefault(false)
                if (!whole) {
                    part.delete()
                    return@withContext false
                }
                if (target.exists()) target.delete()
                part.renameTo(target).also { moved -> if (!moved) part.delete() }
            }
        }
    }

    private suspend fun text(url: HttpUrl): String? {
        val response = runCatching { http.newCall(Request.Builder().url(url).build()).awaitResponse() }.getOrNull() ?: return null
        return withContext(Dispatchers.IO) {
            response.use {
                if (!it.isSuccessful || it.body.contentLength() > PLAYLIST_LIMIT) null
                else runCatching { it.body.string() }.getOrNull()?.takeIf { body -> body.startsWith("#EXTM3U") }
            }
        }
    }
}

// Loop files kept on disk under `dir`, named by their address. Used as a
// cache: `trim` drops the least lately used past `maxBytes`.
class LoopShelf(val dir: File, private val maxBytes: Long) {
    fun fileFor(url: HttpUrl): File = File(dir, "${hashOf(url.toString())}.mp4")

    // Marks a file as just used, so trimming keeps it longest.
    fun touch(file: File) {
        if (file.isFile) file.setLastModified(System.currentTimeMillis())
    }

    // Drops the least lately used files until the shelf fits, never one in
    // `keep` (the loops on screen).
    fun trim(keep: Set<File> = emptySet()) {
        val files = dir.listFiles { f -> f.isFile && f.name.endsWith(".mp4") }?.sortedBy(File::lastModified) ?: return
        var total = files.sumOf(File::length)
        for (file in files) {
            if (total <= maxBytes) break
            if (file in keep) continue
            val size = file.length()
            if (file.delete()) total -= size
        }
        dir.listFiles { f -> f.name.endsWith(".part") && System.currentTimeMillis() - f.lastModified() > 3_600_000 }?.forEach(File::delete)
    }
}

// Where a downloaded album's loops are kept, beside its songs: one file
// per shape, and the shape's still.
fun offlineLoopFile(dir: File, albumId: String, shape: String): File = File(dir, "${hashOf(albumId)}-$shape.mp4")

fun offlineLoopPoster(dir: File, albumId: String, shape: String): File = File(dir, "${hashOf(albumId)}-$shape.jpg")

// What is kept of a downloaded album's animated art beside its loops (the
// art as the server gave it), so it is known with no connection too.
fun offlineLoopRecord(dir: File, albumId: String): File = File(dir, "${hashOf(albumId)}.json")

// What the name of every file kept for a downloaded album's loops starts with.
fun offlineLoopStem(albumId: String): String = hashOf(albumId)

internal fun hashOf(text: String): String =
    MessageDigest.getInstance("SHA-256").digest(text.toByteArray()).take(16).joinToString("") { "%02x".format(it) }

private suspend fun Call.awaitResponse(): Response = suspendCancellableCoroutine { cont ->
    cont.invokeOnCancellation { cancel() }
    enqueue(object : Callback {
        override fun onFailure(call: Call, e: IOException) = cont.resumeWithException(e)

        override fun onResponse(call: Call, response: Response) = cont.resume(response) { _, value, _ -> value.close() }
    })
}
