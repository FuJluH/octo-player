package app.winters.octo.offline

import android.content.Context
import android.os.Environment
import app.winters.octo.animated.offlineLoopFile
import app.winters.octo.animated.offlineLoopPoster
import app.winters.octo.animated.offlineLoopRecord
import app.winters.octo.animated.offlineLoopStem
import app.winters.octo.subsonic.AnimatedArt
import app.winters.octo.subsonic.AnimatedClip
import kotlinx.serialization.Serializable
import kotlinx.serialization.json.Json
import java.io.File

// The two shapes an album's loops come in, as their files are named.
const val SQUARE_LOOP = "square"
const val TALL_LOOP = "tall"

// An album of a server whose loops are kept on the phone.
data class LoopAlbum(val sourceId: String, val albumId: String) {
    // One name across servers, as the files are named by it.
    val key: String get() = "$sourceId|$albumId"
}

// What is kept of a downloaded album's animated art: the art as the server
// gave it (null when it has none, so it is not asked about again).
@Serializable
data class KeptLoops(val sourceId: String, val albumId: String, val art: AnimatedArt? = null) {
    val album: LoopAlbum get() = LoopAlbum(sourceId, albumId)
}

private val RecordJson = Json {
    ignoreUnknownKeys = true
    explicitNulls = false
}

// The loops of downloaded albums, kept beside their songs: per album a
// record of its art, and for each shape its loop file and still. Plain
// files, so the art and the loops are there with no connection.
class OfflineLoopStore(val dir: File) {
    fun read(album: LoopAlbum): KeptLoops? =
        runCatching { RecordJson.decodeFromString(KeptLoops.serializer(), offlineLoopRecord(dir, album.key).readText()) }.getOrNull()

    fun write(kept: KeptLoops) {
        dir.mkdirs()
        val target = offlineLoopRecord(dir, kept.album.key)
        val part = File(target.path + ".part")
        part.writeText(RecordJson.encodeToString(KeptLoops.serializer(), kept))
        if (!part.renameTo(target)) {
            target.delete()
            part.renameTo(target)
        }
    }

    // Every album with a record.
    fun records(): List<KeptLoops> =
        dir.listFiles { f -> f.isFile && f.name.endsWith(".json") }.orEmpty().mapNotNull { file ->
            runCatching { RecordJson.decodeFromString(KeptLoops.serializer(), file.readText()) }.getOrNull()
        }

    fun loopFile(album: LoopAlbum, shape: String): File = offlineLoopFile(dir, album.key, shape)

    fun posterFile(album: LoopAlbum, shape: String): File = offlineLoopPoster(dir, album.key, shape)

    // Whether every loop the album has is on the phone. An album with no
    // art has nothing more to fetch.
    fun complete(kept: KeptLoops): Boolean {
        val art = kept.art ?: return true
        return shapes(art).all { (shape, _) -> loopFile(kept.album, shape).isFile }
    }

    // The album's art as it plays from the phone: each loop and still kept
    // here in place of its address, the rest as the server gave it.
    fun local(kept: KeptLoops): AnimatedArt? {
        val art = kept.art ?: return null
        fun AnimatedClip.here(shape: String): AnimatedClip {
            val loop = loopFile(kept.album, shape).takeIf(File::isFile)
            val still = posterFile(kept.album, shape).takeIf(File::isFile)
            return copy(
                video = loop?.toURI()?.toString() ?: video,
                poster = still?.toURI()?.toString() ?: poster,
            )
        }
        return AnimatedArt(art.square?.here(SQUARE_LOOP), art.tall?.here(TALL_LOOP))
    }

    // Lets go of everything kept for an album.
    fun drop(album: LoopAlbum) {
        val stem = offlineLoopStem(album.key)
        dir.listFiles { f -> f.name.startsWith(stem) }?.forEach(File::delete)
    }

    // Lets go of every album not in `wanted`, and of any file no record
    // owns (one left by a fetch the app closed during).
    fun keepOnly(wanted: Set<LoopAlbum>) {
        val kept = records()
        kept.filter { it.album !in wanted }.forEach { drop(it.album) }
        val owned = kept.filter { it.album in wanted }.map { offlineLoopStem(it.album.key) }.toSet()
        val fetching = wanted.map { offlineLoopStem(it.key) }.toSet()
        dir.listFiles()?.forEach { file ->
            val stem = file.name.substringBefore('-').substringBefore('.')
            if (stem !in owned && stem !in fetching) file.delete()
        }
    }
}

// The shapes an album's art has, with their clips.
fun shapes(art: AnimatedArt): List<Pair<String, AnimatedClip>> =
    listOfNotNull(
        art.square?.takeIf { it.video.isNotBlank() }?.let { SQUARE_LOOP to it },
        art.tall?.takeIf { it.video.isNotBlank() }?.let { TALL_LOOP to it },
    )

// Where downloaded albums' loops are kept: beside the downloaded songs, in
// app storage on the phone's music drive, or inside the app without one.
fun offlineLoopsDir(context: Context): File {
    val base = context.getExternalFilesDir(Environment.DIRECTORY_MUSIC) ?: File(context.filesDir, "music")
    return File(File(base, "Octo"), ".loops")
}
