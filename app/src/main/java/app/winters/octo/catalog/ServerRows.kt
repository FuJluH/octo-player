package app.winters.octo.catalog

import androidx.room.Embedded

// A server song that is in the library, and the library song it is.
data class ServerLink(val serverId: String, val trackId: String)

// A server album the library has, and how many songs the server listed in it.
data class ServerAlbumCount(val serverId: String, val songCount: Int)

// A server's copy of a library song: its id on the server, and when the
// server last saw it played.
data class ServerCopy(
    val trackId: String,
    val serverId: String,
    val lastPlayedAt: Long? = null,
)

// A song still in the library, with the play record one of its server
// copies has.
data class ServerPlayedTrack(
    @Embedded val track: TrackEntity,
    val serverId: String,
    val serverPlays: Int,
    val serverLastPlayedAt: Long?,
)

// A server's copy of a library song and the listener's rating of it there,
// 0 for none.
data class RatingCopy(val trackId: String, val serverId: String, val rating: Int)
