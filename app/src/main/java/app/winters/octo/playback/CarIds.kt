package app.winters.octo.playback

// Everything a car can browse to, and the id each is known by. A song keeps
// the list it was found in, so choosing it plays that list from that song.
sealed interface CarNode {
    data object Root : CarNode
    data object Recent : CarNode
    data object Playlists : CarNode
    data object Albums : CarNode
    data object Artists : CarNode
    data object Liked : CarNode
    data object MostPlayed : CarNode
    data class Album(val id: String) : CarNode
    data class Artist(val id: String) : CarNode
    data class Playlist(val id: String) : CarNode
    data class Song(val trackId: String, val list: CarNode?) : CarNode
}

private const val SONG = "song:"
private const val IN = "|in:"

fun carId(node: CarNode): String = when (node) {
    CarNode.Root -> "root"
    CarNode.Recent -> "tab:recent"
    CarNode.Playlists -> "tab:playlists"
    CarNode.Albums -> "tab:albums"
    CarNode.Artists -> "tab:artists"
    CarNode.Liked -> "liked"
    CarNode.MostPlayed -> "mostplayed"
    is CarNode.Album -> "album:${node.id}"
    is CarNode.Artist -> "artist:${node.id}"
    is CarNode.Playlist -> "playlist:${node.id}"
    is CarNode.Song -> SONG + node.trackId + (node.list?.let { IN + carId(it) } ?: "")
}

// Reads an id back. A plain song id, as the app itself sends, is not a car
// id, so this returns null for it.
fun parseCarId(id: String): CarNode? = when {
    id == "root" -> CarNode.Root
    id == "tab:recent" -> CarNode.Recent
    id == "tab:playlists" -> CarNode.Playlists
    id == "tab:albums" -> CarNode.Albums
    id == "tab:artists" -> CarNode.Artists
    id == "liked" -> CarNode.Liked
    id == "mostplayed" -> CarNode.MostPlayed
    id.startsWith("album:") -> CarNode.Album(id.removePrefix("album:"))
    id.startsWith("artist:") -> CarNode.Artist(id.removePrefix("artist:"))
    id.startsWith("playlist:") -> CarNode.Playlist(id.removePrefix("playlist:"))
    id.startsWith(SONG) -> {
        val rest = id.removePrefix(SONG)
        val cut = rest.indexOf(IN)
        if (cut < 0) {
            CarNode.Song(rest, null)
        } else {
            CarNode.Song(rest.substring(0, cut), parseCarId(rest.substring(cut + IN.length)))
        }
    }
    else -> null
}

// Where to start in a list of songs: at the chosen song, or the top if it
// is no longer there.
fun startIndex(trackIds: List<String>, chosen: String?): Int =
    chosen?.let { trackIds.indexOf(it) }?.takeIf { it >= 0 } ?: 0

// The server's library action playlists, named with a leading 🛠 (U+1F6E0).
// A song added to one is acted on, so a car, which only plays, leaves them out.
fun isToolPlaylist(name: String): Boolean = name.startsWith(String(Character.toChars(0x1F6E0)))
