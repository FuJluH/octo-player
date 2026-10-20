package app.winters.octo.catalog

import androidx.room.Dao
import androidx.room.Insert
import androidx.room.Query
import androidx.room.RawQuery
import androidx.room.RoomRawQuery
import androidx.room.Transaction
import androidx.room.Upsert
import kotlinx.coroutines.flow.Flow

@Dao
interface CatalogDao {
    @Query("SELECT * FROM album ORDER BY addedAt DESC LIMIT :limit")
    fun recentAlbums(limit: Int): Flow<List<AlbumEntity>>

    @Query("SELECT * FROM album ORDER BY RANDOM() LIMIT :limit")
    suspend fun randomAlbums(limit: Int): List<AlbumEntity>

    @Query("SELECT * FROM artist ORDER BY RANDOM() LIMIT :limit")
    suspend fun randomArtists(limit: Int): List<ArtistEntity>

    @Query("SELECT * FROM track ORDER BY sortKey")
    fun tracks(): Flow<List<TrackEntity>>

    @Query("SELECT * FROM album ORDER BY sortKey")
    fun albums(): Flow<List<AlbumEntity>>

    @Query("SELECT * FROM artist ORDER BY sortKey")
    fun artists(): Flow<List<ArtistEntity>>

    // Lists in the order the listener chose. The queries are built in
    // sort/SortQueries.kt from fixed pieces only. A query that reads likes
    // also watches them, so the others do not run again on every like.

    @RawQuery(observedEntities = [TrackEntity::class, AlbumEntity::class, ArtistEntity::class])
    fun sortedTracks(query: RoomRawQuery): Flow<List<SortedTrack>>

    // Every song in one genre, for picking songs to keep playing.
    @Query("SELECT id FROM track WHERE genre = :name COLLATE NOCASE")
    suspend fun genreTrackIds(name: String): List<String>

    @RawQuery(observedEntities = [TrackEntity::class, AlbumEntity::class, ArtistEntity::class, LikedTrackEntity::class])
    fun sortedTracksWithLikes(query: RoomRawQuery): Flow<List<SortedTrack>>

    @RawQuery(observedEntities = [AlbumEntity::class, ArtistEntity::class])
    fun sortedAlbums(query: RoomRawQuery): Flow<List<SortedAlbum>>

    @RawQuery(observedEntities = [ArtistEntity::class, TrackEntity::class])
    fun sortedArtists(query: RoomRawQuery): Flow<List<SortedArtist>>

    @Query("SELECT * FROM album WHERE id = :id")
    fun album(id: String): Flow<AlbumEntity?>

    @Query("SELECT * FROM track WHERE id = :id")
    fun trackFlow(id: String): Flow<TrackEntity?>

    @Query("SELECT * FROM track WHERE id = :id")
    suspend fun track(id: String): TrackEntity?

    @Query("SELECT * FROM track WHERE id IN (:ids)")
    suspend fun tracksByIdsUnordered(ids: List<String>): List<TrackEntity>

    @Query("SELECT id FROM track WHERE albumId = :albumId ORDER BY albumOrder")
    suspend fun albumTrackIds(albumId: String): List<String>

    @Query("SELECT id FROM track ORDER BY sortKey")
    suspend fun allTrackIds(): List<String>

    @Query("SELECT * FROM track WHERE albumId = :albumId ORDER BY albumOrder")
    fun albumTracks(albumId: String): Flow<List<TrackEntity>>

    @Query("SELECT * FROM artist WHERE id = :id")
    fun artist(id: String): Flow<ArtistEntity?>

    // An artist's songs, album by album, newest album first, each in its
    // own order.
    @Query(
        """
        SELECT t.* FROM track t LEFT JOIN album a ON a.id = t.albumId
        WHERE t.artistId = :artistId
        ORDER BY COALESCE(a.year, 0) DESC, a.sortKey, t.albumId, t.albumOrder
        """,
    )
    fun artistTracks(artistId: String): Flow<List<TrackEntity>>

    // Every song's album and artist, album by album in the same order, for
    // playing whole lists of albums or artists.
    @Query(
        """
        SELECT t.id AS id, t.albumId AS albumId, t.artistId AS artistId
        FROM track t LEFT JOIN album a ON a.id = t.albumId
        ORDER BY COALESCE(a.year, 0) DESC, a.sortKey, t.albumId, t.albumOrder
        """,
    )
    suspend fun trackPlaces(): List<TrackPlace>

    @Query("SELECT * FROM album WHERE artistId = :artistId ORDER BY year DESC, sortKey")
    fun artistAlbums(artistId: String): Flow<List<AlbumEntity>>

    // Genres by name, leaving out songs with none. Each source already keeps
    // one spelling per genre; case is ignored here too so sources agree.
    @Query(
        "SELECT genre AS name, COUNT(*) AS songCount, MIN(artwork) AS artwork FROM track WHERE genre != '' " +
            "GROUP BY genre COLLATE NOCASE ORDER BY genre COLLATE NOCASE",
    )
    fun genres(): Flow<List<GenreSummary>>

    @Query(
        "SELECT * FROM album WHERE id IN (SELECT albumId FROM track WHERE genre = :name COLLATE NOCASE) " +
            "ORDER BY sortKey",
    )
    fun genreAlbums(name: String): Flow<List<AlbumEntity>>

    @Query("SELECT * FROM artist WHERE searchKey LIKE '%' || :q || '%' ORDER BY sortKey LIMIT :limit")
    suspend fun searchArtists(q: String, limit: Int): List<ArtistEntity>

    @Query("SELECT * FROM album WHERE searchKey LIKE '%' || :q || '%' ORDER BY sortKey LIMIT :limit")
    suspend fun searchAlbums(q: String, limit: Int): List<AlbumEntity>

    // Exact title, album and artist lookups, for telling whether something
    // the server found is already in the library.
    @Query("SELECT * FROM track WHERE searchKey IN (:keys)")
    suspend fun tracksWithKeys(keys: List<String>): List<TrackEntity>

    @Query("SELECT * FROM album WHERE searchKey IN (:keys)")
    suspend fun albumsWithKeys(keys: List<String>): List<AlbumEntity>

    @Query("SELECT * FROM artist WHERE searchKey IN (:keys)")
    suspend fun artistsWithKeys(keys: List<String>): List<ArtistEntity>

    // Songs whose title holds the words, then those whose artist does (an
    // artist's name matched as typed, accents and all), each by title.
    @Query(
        "SELECT * FROM track WHERE searchKey LIKE '%' || :q || '%' OR lower(artist) LIKE '%' || :q || '%' " +
            "ORDER BY searchKey LIKE '%' || :q || '%' DESC, sortKey LIMIT :limit",
    )
    suspend fun searchTracks(q: String, limit: Int): List<TrackEntity>

    @Query("SELECT COUNT(*) FROM track WHERE sourceId = :sourceId")
    fun trackCount(sourceId: String): Flow<Int>

    // Every song in the library, from the phone and the server together.
    @Query("SELECT COUNT(*) FROM track")
    fun libraryTrackCount(): Flow<Int>

    @Query("DELETE FROM track")
    suspend fun deleteTracks()

    @Query("DELETE FROM album")
    suspend fun deleteAlbums()

    @Query("DELETE FROM artist")
    suspend fun deleteArtists()

    @Insert
    suspend fun insertTracks(rows: List<TrackEntity>)

    @Insert
    suspend fun insertAlbums(rows: List<AlbumEntity>)

    @Insert
    suspend fun insertArtists(rows: List<ArtistEntity>)

    @Query("SELECT * FROM file_tags")
    suspend fun fileTags(): List<FileTagsEntity>

    @Upsert
    suspend fun upsertFileTags(rows: List<FileTagsEntity>)

    @Query("DELETE FROM file_tags WHERE mediaId IN (:ids)")
    suspend fun deleteFileTags(ids: List<Long>)

    // Swaps in the whole merged library at once, so screens never see a
    // half-written one.
    @Transaction
    suspend fun replaceAll(tracks: List<TrackEntity>, albums: List<AlbumEntity>, artists: List<ArtistEntity>) {
        deleteTracks()
        deleteAlbums()
        deleteArtists()
        artists.chunked(500).forEach { insertArtists(it) }
        albums.chunked(500).forEach { insertAlbums(it) }
        tracks.chunked(500).forEach { insertTracks(it) }
    }
}
