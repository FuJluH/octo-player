package app.winters.octo.desktop.animated

import app.winters.octo.animated.LoopFetcher
import app.winters.octo.animated.offlineLoopFile
import app.winters.octo.animated.offlineLoopPoster
import app.winters.octo.offline.fileSafe
import app.winters.octo.subsonic.AnimatedArt
import app.winters.octo.subsonic.AnimatedArtAnswer
import kotlinx.serialization.json.Json
import okhttp3.OkHttpClient
import java.io.File
import java.util.concurrent.ConcurrentHashMap

// The size a downloaded album's loops are kept for: the square for a
// large cover, the tall one for a tall window.
private const val KeptSquarePx = 960
private const val KeptTallWidth = 810
private const val KeptTallHeight = 1080

// The folder beside a server's kept songs that holds their albums' loops.
const val KEPT_LOOPS = ".animated"

// What a kept answer says when the album has no animated art.
private val NoArt = AnimatedArt()

// The animated art of downloaded albums, kept beside their songs: the
// server's answer, and each loop and its still, so they play without a
// connection. They go with the album's last kept song.
class KeptLoops(
    http: OkHttpClient,
    // The offline folder now (the listener can move it).
    private val folder: () -> File,
) {
    private val fetcher = LoopFetcher(http)
    private val json = Json { ignoreUnknownKeys = true }

    // Answers read from the disk, by folder and album.
    private val answers = ConcurrentHashMap<String, AnimatedArt>()

    private fun dir(server: String): File = File(folder(), "${fileSafe(server)}${File.separator}$KEPT_LOOPS")

    private fun answerFile(dir: File, albumId: String): File = File(dir, offlineLoopFile(dir, albumId, "art").nameWithoutExtension + ".json")

    // The kept answer for an album, if it has art; null when nothing is
    // kept or it has none.
    fun art(server: String?, albumId: String): AnimatedArt? {
        server ?: return null
        val file = answerFile(dir(server), albumId)
        answers[file.path]?.let { return it.takeUnless(AnimatedArt::isEmpty) }
        if (!file.isFile) return null
        val read = runCatching { json.decodeFromString(AnimatedArt.serializer(), file.readText()) }.getOrNull() ?: return null
        answers[file.path] = read
        return read.takeUnless(AnimatedArt::isEmpty)
    }

    fun loop(server: String?, albumId: String, shape: LoopShape): File? =
        server?.let { offlineLoopFile(dir(it), albumId, shape.key).takeIf { f -> f.isFile && f.length() > 0 } }

    fun poster(server: String?, albumId: String, shape: LoopShape): File? =
        server?.let { offlineLoopPoster(dir(it), albumId, shape.key).takeIf { f -> f.isFile && f.length() > 0 } }

    // Keeps the loops of these albums from `server`, asking about each
    // album not asked yet, and lets go of every other album's. An album the
    // server could not answer for now is asked again next time.
    suspend fun keep(server: String, albums: Set<String>, ask: (suspend (String) -> AnimatedArtAnswer)?) {
        val dir = dir(server)
        val wanted = albums.mapTo(HashSet()) { prefix(dir, it) }
        dir.listFiles()?.forEach { file ->
            if (file.name.substringBefore('-') !in wanted) {
                answers.remove(file.path)
                file.delete()
            }
        }
        if (ask == null) return
        for (album in albums) {
            val answerFile = answerFile(dir, album)
            val art = if (answerFile.isFile) {
                art(server, album)
            } else {
                when (val answer = runCatching { ask(album) }.getOrDefault(AnimatedArtAnswer.NotNow)) {
                    is AnimatedArtAnswer.Found -> answer.art.also { write(answerFile, it) }
                    AnimatedArtAnswer.None -> null.also { write(answerFile, NoArt) }
                    // Off, or not now: asked again at the next look.
                    AnimatedArtAnswer.Off -> return
                    AnimatedArtAnswer.NotNow -> continue
                }
            } ?: continue
            for (shape in LoopShape.entries) {
                val clip = art.clip(shape) ?: continue
                val (w, h) = if (shape == LoopShape.Square) KeptSquarePx to KeptSquarePx else KeptTallWidth to KeptTallHeight
                val target = offlineLoopFile(dir, album, shape.key)
                if (!target.isFile) fetcher.locate(clip, w, h)?.let { fetcher.fetch(it, target) }
                val still = offlineLoopPoster(dir, album, shape.key)
                if (!still.isFile) fetcher.fetchPoster(clip, still)
            }
        }
    }

    // Lets go of every kept loop of `server`.
    fun removeAll(server: String) {
        val dir = dir(server)
        dir.listFiles()?.forEach { answers.remove(it.path) }
        dir.deleteRecursively()
    }

    private fun write(file: File, art: AnimatedArt) {
        runCatching {
            file.parentFile?.mkdirs()
            val part = File(file.path + ".part")
            part.writeText(json.encodeToString(AnimatedArt.serializer(), art))
            if (file.exists()) file.delete()
            part.renameTo(file)
            answers[file.path] = art
        }
    }

    private fun prefix(dir: File, albumId: String): String = offlineLoopFile(dir, albumId, "x").name.substringBefore('-')
}
