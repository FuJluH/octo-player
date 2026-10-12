package app.winters.octo.server

import app.winters.octo.catalog.ArtworkRef
import app.winters.octo.catalog.StandInCovers
import app.winters.octo.catalog.drawnCoverStamp
import app.winters.octo.data.SessionRepository
import app.winters.octo.data.SessionState
import app.winters.octo.covers.AheadCoverBucket
import app.winters.octo.covers.CoverDownloads
import app.winters.octo.covers.CoverLanes
import app.winters.octo.covers.coverBucket
import app.winters.octo.covers.keptCoverOrder
import coil3.ImageLoader
import coil3.decode.DataSource
import coil3.decode.ImageSource
import coil3.fetch.FetchResult
import coil3.fetch.Fetcher
import coil3.fetch.SourceFetchResult
import coil3.key.Keyer
import coil3.request.Options
import coil3.size.pxOrElse
import coil3.toUri
import kotlinx.coroutines.flow.first
import java.io.IOException
import java.util.concurrent.ConcurrentHashMap

// The order cover downloads go to the server in, and the downloads under
// way, for the whole app. The player marks the covers it shows now and
// next as urgent (see CoversAhead).
object CoverTraffic {
    val lanes = CoverLanes()
    val downloads = CoverDownloads()
}

// Covers of things found online used to come with a mark the server drew in
// a corner. Octo now sends them clean to this app, so they are kept under
// keys of their own that start afresh, while library covers keep theirs.
// Raise this if the server ever changes how it draws them again. 3: the
// server sends them at full size, where it had sent soft 600 pixel ones.
const val ONLINE_COVER_VERSION = 3

// What a cover is remembered by, whatever address fetched it: its server
// and id. A cover Octo paints (a station's or a mix's) changes under the
// same id, so it is kept under its version and the day, and asked for
// again each day.
fun serverCoverKey(art: ArtworkRef.Server, nowMs: Long = System.currentTimeMillis()): String = when {
    art.online -> "online-art:v$ONLINE_COVER_VERSION:${art.sourceId}|${art.coverId}"
    art.drawn -> "drawn-art:${drawnCoverStamp(nowMs)}:${art.sourceId}|${art.coverId}"
    else -> "server-art:${art.sourceId}|${art.coverId}"
}

// What one downloaded size of a cover is kept on disk under.
fun serverCoverDiskKey(art: ArtworkRef.Server, px: Int, nowMs: Long = System.currentTimeMillis()): String = "${serverCoverKey(art, nowMs)}|$px"

// The disk keys of the copies of a cover that answer an ask at `px`, best
// first (see keptCoverOrder).
fun keptCoverKeys(art: ArtworkRef.Server, px: Int, anySize: Boolean = false, nowMs: Long = System.currentTimeMillis()): List<String> =
    keptCoverOrder(px, anySize).map { serverCoverDiskKey(art, it, nowMs) }

// Draws a cover from the signed-in server. Its address is signed afresh for
// each download, so the download is cached under what the picture is, never
// under the address. A cover the server has none for answers "not found";
// the picture then fails and the artwork keeps its empty tile.
//
// A server may instead answer with a stand-in picture of its own (Navidrome's
// blue record), which would be cached as the cover for good. That answer is
// let go, from the disk too, and the cover's fallback is drawn in its place:
// for a library song, the cover of its album's first song. With no fallback
// the picture fails, so the app's own empty tile shows.
//
// A copy already on the disk at the size asked for, or a larger one, which
// the decoder shrinks, answers without the server. A request that may only
// use kept copies (no network) takes a smaller one too. Downloads wait for
// their turn in CoverTraffic's lanes, and an ask waits for a download of
// the same cover at its size or larger already under way. The covers the
// player shows now and next are downloaded at the largest size, so every
// place that shows them shares one download.
class ServerArtworkFetcher(
    private val sessions: SessionRepository,
    private val art: ArtworkRef.Server,
    private val options: Options,
    private val imageLoader: ImageLoader,
) : Fetcher {
    override suspend fun fetch(): FetchResult? {
        // Covers asked for while the app is still opening wait for the sign-in.
        val state = sessions.state.first { it !is SessionState.Loading }
        val session = (state as? SessionState.SignedIn)?.session ?: return null
        val client = session.client
        if (session.sourceId != art.sourceId) return null
        // With no size given, a middling one.
        val wanted = maxOf(options.size.width.pxOrElse { 0 }, options.size.height.pxOrElse { 0 }).takeIf { it > 0 } ?: 600
        val px = coverBucket(wanted)
        val keptOnly = !options.networkCachePolicy.readEnabled
        suspend fun download(cover: ArtworkRef.Server, size: Int): FetchResult? {
            val key = serverCoverDiskKey(cover, size)
            if (key in standIns) return null
            val url = client.coverArtUrl(cover.coverId, size).toString().toUri()
            val (fetcher, _) = imageLoader.components.newFetcher(url, options.copy(diskCacheKey = key), imageLoader) ?: return null
            return fetcher.fetch()?.let { checked(it, key) }
        }
        suspend fun picture(cover: ArtworkRef.Server): FetchResult? {
            val name = serverCoverKey(cover)
            val size = if (CoverTraffic.lanes.isUrgent(name)) AheadCoverBucket else px
            return CoverTraffic.downloads.get(
                name,
                size,
                kept = { kept(cover, px, anySize = keptOnly) },
                download = { if (keptOnly) null else CoverTraffic.lanes.pass(name) { download(cover, size) } },
            )
        }
        picture(art)?.let { return it }
        val fallback = art.fallbackId?.let { ArtworkRef.Server(art.sourceId, it, art.online) }
        return fallback?.let { picture(it) } ?: throw NoCover(art.coverId)
    }

    // A copy of `cover` on the disk that answers an ask at `px`, best first
    // (see keptCoverOrder), or null.
    private fun kept(cover: ArtworkRef.Server, px: Int, anySize: Boolean): FetchResult? {
        if (!options.diskCachePolicy.readEnabled) return null
        val disk = imageLoader.diskCache ?: return null
        for (key in keptCoverKeys(cover, px, anySize)) {
            val snapshot = disk.openSnapshot(key) ?: continue
            val result = SourceFetchResult(ImageSource(snapshot.data, disk.fileSystem, key, snapshot, null), null, DataSource.DISK)
            checked(result, key)?.let { return it }
        }
        return null
    }

    // The result, unless it is the server's stand-in, which is let go, from
    // the disk too.
    private fun checked(result: FetchResult, key: String): FetchResult? {
        if (!isStandIn(result)) return result
        (result as? SourceFetchResult)?.source?.close()
        imageLoader.diskCache?.remove(key)
        standIns += key
        return null
    }

    class Factory(private val sessions: SessionRepository) : Fetcher.Factory<ArtworkRef.Server> {
        override fun create(data: ArtworkRef.Server, options: Options, imageLoader: ImageLoader): Fetcher =
            ServerArtworkFetcher(sessions, data, options, imageLoader)
    }

    private companion object {
        // Covers at a size the server answered with its stand-in while the
        // app has been running, so they are not asked for again and again.
        // Forgotten when the app closes, by when the server may have the
        // picture.
        val standIns: MutableSet<String> = ConcurrentHashMap.newKeySet()
    }
}

// The server had no picture to give for a cover, only its stand-in.
class NoCover(coverId: String) : IOException("No cover for $coverId")

// Whether a download is the server's stand-in for a cover it could not give.
// Only a picture exactly as long as a known stand-in is read through, ahead
// of the decoder, which still reads it all.
internal fun isStandIn(result: FetchResult): Boolean {
    val source = (result as? SourceFetchResult)?.source ?: return false
    // A cover read from the disk cache says its length without being read.
    source.fileOrNull()?.let { file ->
        val length = source.fileSystem.metadataOrNull(file)?.size
        if (length != null && !StandInCovers.mayBe(length)) return false
    }
    val ahead = source.source().peek()
    if (ahead.request(StandInCovers.longest + 1L)) return false
    val bytes = ahead.readByteArray()
    return StandInCovers.mayBe(bytes.size.toLong()) && StandInCovers.isStandIn(bytes)
}

// A cover is remembered by its server and id, whatever address fetched it,
// and a painted one by the day too.
class ServerArtworkKeyer : Keyer<ArtworkRef.Server> {
    override fun key(data: ArtworkRef.Server, options: Options) = serverCoverKey(data)
}
