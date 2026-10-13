package app.winters.octo.server

import app.winters.octo.subsonic.Album
import app.winters.octo.subsonic.AlbumListType
import app.winters.octo.subsonic.AlbumWithSongs
import app.winters.octo.subsonic.ScanStatus
import app.winters.octo.subsonic.SearchResult
import app.winters.octo.subsonic.Song
import app.winters.octo.subsonic.SubsonicClient
import app.winters.octo.subsonic.SubsonicException

// Both apps keep a copy of the server's library and copy it whole only now
// and then. In between, music the server takes in is brought into the copy
// a little at a time: what a search turns up, and what a look at the
// server's newest albums finds.

// The least time between two looks at one server for new music.
const val NEW_MUSIC_LOOK_MS = 15 * 60 * 1000L

// How many of the server's newest albums one look reads.
const val NEWEST_ALBUMS_READ = 30

// The most albums taken in at once. A look that finds more copies the
// whole library again instead; a search takes in the first ones only.
const val ALBUMS_TAKEN_IN = 10

// Whether a look is due: none made yet, or the last one long enough ago.
// A clock that went backwards counts as due.
fun newMusicLookDue(lastLookAt: Long?, now: Long, every: Long = NEW_MUSIC_LOOK_MS): Boolean =
    lastLookAt == null || now < lastLookAt || now - lastLookAt >= every

// Whether the server may have read in new music since it last said it
// read its folders at `seen`. A server that does not say (no answer, or no
// time in it) may have. One reading its folders now is left until it is
// done.
fun scannedSince(seen: String?, status: ScanStatus?): Boolean = when {
    status == null -> true
    status.scanning -> false
    status.lastScan.isNullOrBlank() -> true
    else -> status.lastScan != seen
}

// What a look at the newest albums found.
sealed interface NewMusic {
    data object None : NewMusic

    // These albums are new to the copy, or hold another number of songs
    // than it has, as the newest list gives them.
    data class TakeIn(val albums: List<Album>) : NewMusic

    // Too much is new to take in album by album.
    data object CopyAll : NewMusic
}

// Sets the server's newest albums against the copy: `kept` holds the song
// count the copy has for each album it has, by the album's id. Albums the
// server marks as outside the library are not the library's.
fun newMusic(newest: List<Album>, kept: Map<String, Int>, most: Int = ALBUMS_TAKEN_IN): NewMusic {
    val changed = newest.asSequence()
        .filterNot { it.isExternal }
        .distinctBy { it.id }
        .filter { kept[it.id] != it.songCount }
        .toList()
    return when {
        changed.isEmpty() -> NewMusic.None
        changed.size > most -> NewMusic.CopyAll
        else -> NewMusic.TakeIn(changed)
    }
}

// One look's answer: what it found, and the time the server last read its
// folders, to set against the next look. `scan` stays as it was when the
// server did not say.
class NewMusicLook(val scan: String?, val found: NewMusic)

// Looks for music the server has that the copy lacks: first whether the
// server read its folders since `seen` (one small answer), and only then
// its newest albums (one more). `kept` gives the copy's song count of each
// album id asked about. Throws SubsonicException when the newest albums
// cannot be read.
suspend fun lookForNewMusic(
    client: SubsonicClient,
    seen: String?,
    kept: suspend (List<String>) -> Map<String, Int>,
): NewMusicLook {
    val status = try {
        client.scanStatus()
    } catch (e: SubsonicException) {
        null
    }
    if (!scannedSince(seen, status)) return NewMusicLook(seen, NewMusic.None)
    val newest = client.albumList(AlbumListType.NEWEST, NEWEST_ALBUMS_READ)
    val scan = status?.lastScan?.takeIf { it.isNotBlank() } ?: seen
    return NewMusicLook(scan, newMusic(newest, kept(newest.map { it.id })))
}

// The time the server last read its folders, for a copy about to be made,
// so the first look after it only reads on when the server read again.
// Null when the server does not say, or is reading now.
suspend fun lastScanOf(client: SubsonicClient): String? = try {
    client.scanStatus().takeIf { !it.scanning }?.lastScan?.takeIf { it.isNotBlank() }
} catch (e: SubsonicException) {
    null
}

// An album read with its songs, as the server's album lists would list it.
fun AlbumWithSongs.asListed() = Album(
    id = id,
    name = name,
    artist = artist,
    artistId = artistId,
    displayArtist = displayArtist,
    coverArt = coverArt,
    songCount = songCount,
    duration = duration,
    year = year,
    genre = genre,
    created = created,
    starred = starred,
    isCompilation = isCompilation,
    genres = genres,
    discTitles = discTitles,
    originalReleaseDate = originalReleaseDate,
    releaseDate = releaseDate,
    releaseTypes = releaseTypes,
)

// Songs and albums a server's answer gives as its library's (not marked as
// outside it) that the copy does not have yet: music the server took in
// since the copy was made.
class Arriving(val songs: List<Song>, val albums: List<Album>) {
    val isEmpty get() = songs.isEmpty() && albums.isEmpty()

    // The albums to take in, the albums named first and then those of the
    // songs, each once and at most `most` of them.
    fun albumIds(most: Int = ALBUMS_TAKEN_IN): List<String> =
        (albums.map { it.id } + songs.mapNotNull { song -> song.albumId?.takeIf(String::isNotEmpty) })
            .distinct()
            .take(most)

    companion object {
        val Nothing = Arriving(emptyList(), emptyList())
    }
}

// A server that also finds music online (`findsOnline`) marks what it found;
// an answer of its that marks nothing cannot be told apart, so nothing is
// taken from it. Any other server's answer is all its library.
fun arriving(
    sent: SearchResult,
    hasSong: (Song) -> Boolean,
    hasAlbum: (Album) -> Boolean,
    findsOnline: Boolean = false,
): Arriving {
    if (findsOnline && sent.song.none { it.isExternal } && sent.album.none { it.isExternal }) return Arriving.Nothing
    return Arriving(
        sent.song.filter { !it.isExternal && !hasSong(it) }.distinctBy { it.id },
        sent.album.filter { !it.isExternal && !hasAlbum(it) }.distinctBy { it.id },
    )
}
