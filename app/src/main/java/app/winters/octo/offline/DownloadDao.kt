package app.winters.octo.offline

import androidx.room.Dao
import androidx.room.Entity
import androidx.room.Index
import androidx.room.Insert
import androidx.room.OnConflictStrategy
import androidx.room.Query
import app.winters.octo.catalog.SourceTrackEntity
import kotlinx.coroutines.flow.Flow

// Where a download is.
enum class DownloadStatus { Queued, Downloading, Done, Failed }

// A server song kept on the phone as a real file, so it plays with no
// connection. It is held for one or more reasons (see Reasons); once none
// is left, the file goes. Keyed by the server's song, which never changes;
// `trackId` is the library song it is, kept up to date after each sync.
@Entity(tableName = "download", primaryKeys = ["sourceId", "serverId"], indices = [Index("trackId"), Index("state")])
data class DownloadEntity(
    val trackId: String,
    val sourceId: String,
    val serverId: String,
    // The finished file, or empty until there is one.
    val path: String,
    val sizeBytes: Long,
    // What the file is: the server's type, or MP3 when a smaller one was asked for.
    val format: String?,
    val state: DownloadStatus,
    // From 0 to 1 while it downloads.
    val progress: Float,
    val addedAt: Long,
    // Why it is kept: see Reasons.
    val reason: String,
    // The song's name, for the Downloads page and the file.
    val title: String,
    val artist: String,
    // The server's size for the file the download was made from, so a new
    // file under the same id is told apart. Downloads made before it was
    // noted have none until the first check after a sync.
    val fileSize: Long? = null,
)

// A finished download beside its server song as the last sync saw it.
data class DownloadedFile(
    val sourceId: String,
    val serverId: String,
    val format: String?,
    val sizeBytes: Long,
    val fileSize: Long?,
    val serverSize: Long?,
    val serverType: String?,
)

// A download with the reasons it is kept, split out.
val DownloadEntity.reasons: Set<String> get() = Reasons.parse(reason)

// A download as the Downloads page shows it: with its artwork and length.
data class DownloadRow(
    val trackId: String,
    val sourceId: String,
    val serverId: String,
    val title: String,
    val artist: String,
    val artwork: String?,
    val sizeBytes: Long,
    val state: DownloadStatus,
    val progress: Float,
    val reason: String,
    // When it was asked for, for ordering the list.
    val addedAt: Long = 0,
    // Whether the song is marked explicit, while the library has it.
    val explicit: Boolean? = null,
)

// A playlist song, for keeping playlists downloaded.
data class PlaylistMember(val playlistId: String, val trackId: String)

@Dao
interface DownloadDao {
    @Query("SELECT * FROM download")
    suspend fun all(): List<DownloadEntity>

    @Query("SELECT * FROM download")
    fun allFlow(): Flow<List<DownloadEntity>>

    @Query(
        """
        SELECT d.trackId, d.sourceId, d.serverId, d.title, d.artist, t.artwork, d.sizeBytes, d.state, d.progress, d.reason,
            d.addedAt, t.explicit
        FROM download d LEFT JOIN track t ON t.id = d.trackId
        ORDER BY CASE d.state WHEN 'Downloading' THEN 0 WHEN 'Queued' THEN 1 WHEN 'Failed' THEN 2 ELSE 3 END, d.addedAt DESC, d.title
        """,
    )
    fun rows(): Flow<List<DownloadRow>>

    // Finished downloads of these library songs.
    @Query("SELECT * FROM download WHERE state = 'Done' AND trackId IN (:trackIds)")
    suspend fun doneFor(trackIds: List<String>): List<DownloadEntity>

    @Query("SELECT * FROM download WHERE trackId = :trackId")
    suspend fun forTrack(trackId: String): List<DownloadEntity>

    // The oldest download from this server still waiting.
    @Query("SELECT * FROM download WHERE state = 'Queued' AND sourceId = :sourceId ORDER BY addedAt, title LIMIT 1")
    suspend fun nextQueued(sourceId: String): DownloadEntity?

    @Query("SELECT * FROM download WHERE sourceId = :sourceId AND serverId = :serverId")
    suspend fun get(sourceId: String, serverId: String): DownloadEntity?

    @Insert(onConflict = OnConflictStrategy.REPLACE)
    suspend fun upsert(rows: List<DownloadEntity>)

    @Query("UPDATE download SET reason = :reason WHERE sourceId = :sourceId AND serverId = :serverId")
    suspend fun setReason(sourceId: String, serverId: String, reason: String)

    @Query("UPDATE download SET state = :state, progress = :progress WHERE sourceId = :sourceId AND serverId = :serverId")
    suspend fun setState(sourceId: String, serverId: String, state: DownloadStatus, progress: Float)

    @Query(
        """
        UPDATE download SET state = 'Done', progress = 1, path = :path, sizeBytes = :size, format = :format, fileSize = :fileSize
        WHERE sourceId = :sourceId AND serverId = :serverId
        """,
    )
    suspend fun finish(sourceId: String, serverId: String, path: String, size: Long, format: String?, fileSize: Long?)

    // The finished downloads from this server, each with its server song.
    @Query(
        """
        SELECT d.sourceId, d.serverId, d.format, d.sizeBytes, d.fileSize, s.sizeBytes AS serverSize, s.mimeType AS serverType
        FROM download d JOIN source_track s ON s.sourceId = d.sourceId AND s.nativeId = d.serverId
        WHERE d.state = 'Done' AND d.sourceId = :sourceId
        """,
    )
    suspend fun doneFiles(sourceId: String): List<DownloadedFile>

    @Query("UPDATE download SET fileSize = :fileSize WHERE sourceId = :sourceId AND serverId = :serverId")
    suspend fun noteFileSize(sourceId: String, serverId: String, fileSize: Long)

    // A download cut short when the app last closed waits again.
    @Query("UPDATE download SET state = 'Queued', progress = 0 WHERE state = 'Downloading'")
    suspend fun requeueInterrupted()

    @Query("DELETE FROM download WHERE sourceId = :sourceId AND serverId = :serverId")
    suspend fun delete(sourceId: String, serverId: String)

    // After the library is rebuilt: each download follows its server song to
    // the library song it is now part of.
    @Query(
        """
        UPDATE download SET trackId = COALESCE((
            SELECT CASE WHEN s.mergedId = '' THEN s.id ELSE s.mergedId END FROM source_track s
            WHERE s.sourceId = download.sourceId AND s.nativeId = download.serverId LIMIT 1
        ), trackId)
        """,
    )
    suspend fun relink()

    // Liked songs, by library id.
    @Query("SELECT trackId FROM liked_track")
    fun likedIds(): Flow<List<String>>

    // The songs of these playlists.
    @Query("SELECT playlistId, trackId FROM playlist_item WHERE playlistId IN (:playlistIds)")
    fun playlistMembers(playlistIds: List<String>): Flow<List<PlaylistMember>>

    // The songs of one playlist, library songs only.
    @Query("SELECT i.trackId FROM playlist_item i JOIN track t ON t.id = i.trackId WHERE i.playlistId = :playlistId ORDER BY i.position")
    suspend fun playlistTrackIds(playlistId: String): List<String>

    // The server copies of these library songs.
    @Query("SELECT * FROM source_track WHERE mergedId IN (:trackIds) AND sourceId LIKE 'server:%'")
    suspend fun serverCopies(trackIds: List<String>): List<SourceTrackEntity>

    // One server song, as the last sync saw it.
    @Query("SELECT * FROM source_track WHERE sourceId = :sourceId AND nativeId = :serverId LIMIT 1")
    suspend fun serverCopy(sourceId: String, serverId: String): SourceTrackEntity?

    // Which of these library songs can be downloaded: on a server and not on the phone.
    @Query(
        """
        SELECT DISTINCT t.id FROM track t JOIN source_track s ON s.mergedId = t.id
        WHERE t.onPhone = 0 AND s.sourceId LIKE 'server:%' AND t.id IN (:trackIds)
        """,
    )
    suspend fun downloadable(trackIds: List<String>): List<String>
}
