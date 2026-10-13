package app.winters.octo.catalog

import androidx.room.ColumnInfo
import androidx.room.Embedded
import androidx.room.Entity
import androidx.room.Index
import androidx.room.PrimaryKey
import kotlinx.serialization.Serializable

// Ids are "<source>:<native id>", so one catalog can hold every source.

@Entity(
    tableName = "track",
    indices = [Index("albumId"), Index("artistId"), Index("sourceId"), Index("sortKey"), Index("searchKey"), Index("relinkKey")],
)
// Serializable too, so Home can keep the chart songs it showed.
@Serializable
data class TrackEntity(
    @PrimaryKey val id: String,
    val sourceId: String,
    val nativeId: String,
    val title: String,
    val searchKey: String,
    val sortKey: String,
    val artist: String,
    val artistId: String,
    val album: String,
    val albumId: String,
    val trackNo: Int?,
    val discNo: Int?,
    val year: Int?,
    val durationMs: Long,
    val addedAt: Long,
    val mimeType: String?,
    val sizeBytes: Long?,
    val artwork: String?,
    // Where the audio is: a content:// address for phone files.
    val uri: String?,
    // Position within its album, worked out once when the catalog is built.
    @ColumnInfo(defaultValue = "0") val albumOrder: Int = 0,
    // Who, what and how long: finds this song again if its id changes.
    @ColumnInfo(defaultValue = "") val relinkKey: String = "",
    // The song's main genre, or empty when it has none.
    @ColumnInfo(defaultValue = "") val genre: String = "",
    // Whether a copy is on the phone. A song only on a server streams.
    @ColumnInfo(defaultValue = "1") val onPhone: Boolean = true,
    // The listener's rating, 1 to 5 stars, or 0 for none: the server's when
    // it has one, otherwise the one made on the phone.
    @ColumnInfo(defaultValue = "0") val rating: Int = 0,
    // True when a copy is marked explicit, false when marked clean, null
    // when nothing says. Rows show the "E" only for true.
    val explicit: Boolean? = null,
)

@Entity(
    tableName = "album",
    indices = [Index("artistId"), Index("sourceId"), Index("sortKey"), Index("searchKey"), Index("addedAt")],
)
data class AlbumEntity(
    @PrimaryKey val id: String,
    val sourceId: String,
    val nativeId: String,
    val title: String,
    val searchKey: String,
    val sortKey: String,
    val artist: String,
    val artistId: String,
    val year: Int?,
    val songCount: Int,
    val durationMs: Long,
    val addedAt: Long,
    val artwork: String?,
    // What kind of release it is, one word a line ("Album", "EP", "Live"),
    // as an OpenSubsonic server tags it; empty when nothing says.
    @ColumnInfo(defaultValue = "") val releaseTypes: String = "",
)

@Entity(tableName = "artist", indices = [Index("sourceId"), Index("sortKey"), Index("searchKey")])
data class ArtistEntity(
    @PrimaryKey val id: String,
    val sourceId: String,
    val name: String,
    val searchKey: String,
    val sortKey: String,
    val albumCount: Int,
    val songCount: Int,
    val artwork: String?,
)

// Tags read from one file on the phone, kept so a rescan only re-reads
// files that changed. Stale when the file's modified time or size moves.
@Entity(tableName = "file_tags")
data class FileTagsEntity(
    @PrimaryKey val mediaId: Long,
    val modifiedAt: Long,
    val size: Long,
    // False when the file could not be read; the phone's own tags are used then.
    val readOk: Boolean,
    val title: String?,
    val artist: String?,
    val albumArtist: String?,
    val album: String?,
    val trackNo: Int?,
    val discNo: Int?,
    val year: Int?,
    val compilation: Boolean,
    val mbAlbumId: String?,
    // Every genre the file names, one per line, main one first.
    @ColumnInfo(defaultValue = "") val genres: String = "",
    // Which way of reading tags wrote this row; rows from an older one are
    // read again, so what it adds reaches files already seen.
    @ColumnInfo(defaultValue = "0") val tagsVersion: Int = 0,
    // The rest of what the file says, as FileTags has it. Lists are one
    // value per line.
    val originalYear: Int? = null,
    @ColumnInfo(defaultValue = "") val artists: String = "",
    val composer: String? = null,
    val bpm: Int? = null,
    val comment: String? = null,
    val explicit: Boolean? = null,
    val discTitle: String? = null,
    val mbRecordingId: String? = null,
    val mbReleaseGroupId: String? = null,
    @ColumnInfo(defaultValue = "") val mbArtistIds: String = "",
    val sortTitle: String? = null,
    val sortAlbum: String? = null,
    val sortAlbumArtist: String? = null,
    val trackGain: Float? = null,
    val albumGain: Float? = null,
    val trackPeak: Float? = null,
    val albumPeak: Float? = null,
)

// A genre on the Genres page: its name, how many songs, and a cover from
// one of its albums.
data class GenreSummary(val name: String, val songCount: Int, val artwork: String?)

// A row of a list in a chosen order, with the name it files under when the
// order is by name (null otherwise).
data class SortedTrack(@Embedded val track: TrackEntity, val heading: String?)

data class SortedAlbum(@Embedded val album: AlbumEntity, val heading: String?)

data class SortedArtist(@Embedded val artist: ArtistEntity, val heading: String?)
