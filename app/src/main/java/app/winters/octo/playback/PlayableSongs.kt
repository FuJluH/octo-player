package app.winters.octo.playback

import android.content.Context
import android.provider.MediaStore
import androidx.core.net.toUri
import androidx.media3.common.MediaItem
import app.winters.octo.catalog.CatalogDao
import app.winters.octo.catalog.OnlineDao
import app.winters.octo.catalog.OnlineSongEntity
import app.winters.octo.catalog.SourceDao
import app.winters.octo.catalog.SourceTrackEntity
import app.winters.octo.catalog.isFind
import app.winters.octo.discovery.asTrack
import app.winters.octo.offline.OfflineDownloads
import app.winters.octo.offline.OfflineSettings
import app.winters.octo.player.StreamPrefs
import dagger.hilt.android.qualifiers.ApplicationContext
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.flow.first
import kotlinx.coroutines.withContext
import java.io.File
import javax.inject.Inject
import javax.inject.Singleton

// The song a find plays as: the library song it became once downloaded,
// while the library has it, or else the find itself, streamed.
fun playsAs(find: OnlineSongEntity, library: Set<String>): String = find.adoptedId.takeIf { it in library } ?: find.id

// Where a list asked for starts once its songs are turned into playable
// ones (`played`, one for each asked, null for any gone): the song chosen,
// found by its place, since a find plays under its library song's id and a
// list may hold a song twice. The first song when the chosen one is gone.
fun chosenStart(played: List<Any?>, startIndex: Int): Int =
    if (played.getOrNull(startIndex) == null) 0 else played.take(startIndex).count { it != null }

// Turns song ids into songs the player can play. Each library song plays
// from one of its copies, chosen now by the settings and by what can play:
// the phone's file, or a stream from the server. A song found online
// streams from the server, or plays as the library song it became once
// downloaded.
@Singleton
class PlayableSongs @Inject constructor(
    @ApplicationContext private val context: Context,
    private val catalog: CatalogDao,
    private val sources: SourceDao,
    private val streams: Streams,
    private val online: OnlineDao,
    private val offline: OfflineDownloads,
    private val offlineSettings: OfflineSettings,
) {
    // In the order asked for, dropping any the app no longer knows.
    suspend fun items(ids: List<String>): List<MediaItem> = itemsEach(ids).filterNotNull()

    // One for each id asked for, in order: nothing for any the app no
    // longer knows, so a caller can tell which ones went.
    suspend fun itemsEach(ids: List<String>): List<MediaItem?> {
        val finds = ids.filter(::isFind).distinct().chunked(900).flatMap { online.byIds(it) }.associateBy { it.id }
        val adopted = finds.values.mapNotNull { it.adoptedId.ifEmpty { null } }
        val library = libraryItems(ids.filterNot { isFind(it) || isRadio(it) || isOpenedFile(it) } + adopted).associateBy { it.mediaId }
        val prefs = if (finds.isEmpty()) StreamPrefs() else streams.prefs()
        return ids.map { id ->
            // A radio station plays from the address in its id.
            if (isRadio(id)) return@map radioItem(id, streams.currentSourceId())
            // So does a file opened from another app, while Octo may read it.
            if (isOpenedFile(id)) return@map openedFileItem(context, id)
            val find = finds[id] ?: return@map library[id]
            library[playsAs(find, library.keys)] ?: findItem(find, prefs)
        }
    }

    // A find streams by no listed bitrate: the listed one is its preview's,
    // and the server may send a whole FLAC in its place, so a cap applies as
    // it does to a lossless song. The player goes by the bytes that come.
    private fun findItem(find: OnlineSongEntity, prefs: StreamPrefs): MediaItem =
        find.asTrack().toMediaItem(
            streams.uriFor(find.sourceId, find.nativeId, find.mimeType, null),
            streams.mimeTypeFor(find.mimeType, null, prefs),
            sniffed = true,
        )

    private suspend fun libraryItems(ids: List<String>): List<MediaItem> {
        if (ids.isEmpty()) return emptyList()
        val tracks = catalog.tracksByIds(ids.distinct())
        val copies = tracks.map { it.id }.distinct().chunked(900)
            .flatMap { sources.copiesOf(it) }
            .groupBy { it.mergedId }
        val onServer = copies.values.filter { group -> group.any { it.isServerCopy } }
        // Only ask about the server when some song is on one.
        val reachable = onServer.isNotEmpty() && streams.online() && streams.client() != null
        // Phone files that could be swapped for a stream, checked in case one is gone.
        val missing = if (reachable) missingPhoneFiles(onServer.flatten().filterNot { it.isServerCopy }) else emptySet()
        val prefs = streams.prefs()
        // Downloads play first, unless streaming on Wi-Fi is preferred and the phone is on it.
        val downloads = if (onServer.isEmpty()) emptyMap() else offline.playableCopies(onServer.map { it.first().mergedId })
        val streamInstead = downloads.isNotEmpty() && offlineSettings.prefs.first().streamOnWifi && streams.onWifi()
        return tracks.map { track ->
            val all = copies[track.id].orEmpty()
            val download = downloads[track.id]?.let { row ->
                val server = all.firstOrNull { it.sourceId == row.sourceId && it.nativeId == row.serverId } ?: all.firstOrNull { it.isServerCopy }
                server?.let { downloadedCopy(it, File(row.path).toUri().toString(), row.format, row.sizeBytes) }
            }
            val copy = chooseCopy(all, download, streamInstead, prefs.copies, reachable) { it.uri in missing }
            val loudness = storedLoudness(copy, all)
            val bpm = songBpm(copy, all)
            when {
                copy == null -> track.toMediaItem(track.uri, track.mimeType, loudness, bpm)
                copy.isServerCopy -> track.toMediaItem(streams.uriFor(copy), streams.mimeTypeFor(copy, prefs), loudness, bpm)
                else -> track.toMediaItem(copy.uri, copy.mimeType, loudness, bpm)
            }
        }
    }

    // The addresses of the phone files among these that are gone, asked of
    // the phone's media store in one go.
    private suspend fun missingPhoneFiles(copies: List<SourceTrackEntity>): Set<String> = withContext(Dispatchers.IO) {
        val uris = copies.mapNotNull { copy ->
            val uri = copy.uri ?: return@mapNotNull null
            uri.toUri().lastPathSegment?.toLongOrNull()?.let { it to uri }
        }.toMap()
        val present = HashSet<Long>()
        try {
            uris.keys.chunked(900).forEach { chunk ->
                context.contentResolver.query(
                    MediaStore.Audio.Media.EXTERNAL_CONTENT_URI,
                    arrayOf(MediaStore.Audio.Media._ID),
                    "${MediaStore.Audio.Media._ID} IN (${chunk.joinToString(",")})",
                    null,
                    null,
                )?.use { cursor -> while (cursor.moveToNext()) present += cursor.getLong(0) }
            }
        } catch (e: SecurityException) {
            // Without access to the phone's music, none of its files can play.
        }
        uris.filterKeys { it !in present }.values.toSet()
    }
}
