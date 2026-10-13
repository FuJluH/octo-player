package app.winters.octo.desktop.library

import app.winters.octo.catalog.SongIdentity
import app.winters.octo.desktop.server.userMessage
import app.winters.octo.discovery.IsrcIndex
import app.winters.octo.discovery.TitleIndex
import app.winters.octo.discovery.knownLengthMs
import app.winters.octo.discovery.sameSong
import app.winters.octo.server.Arriving
import app.winters.octo.server.NewMusic
import app.winters.octo.server.asListed
import app.winters.octo.server.lastScanOf
import app.winters.octo.server.lookForNewMusic
import app.winters.octo.server.newMusicLookDue
import app.winters.octo.subsonic.Album
import app.winters.octo.subsonic.AlbumWithSongs
import app.winters.octo.subsonic.Artist
import app.winters.octo.subsonic.Library
import app.winters.octo.subsonic.Song
import app.winters.octo.subsonic.SubsonicClient
import app.winters.octo.subsonic.SubsonicException
import app.winters.octo.subsonic.readLibrary
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.Job
import kotlinx.coroutines.async
import kotlinx.coroutines.awaitAll
import kotlinx.coroutines.coroutineScope
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.launch
import kotlinx.coroutines.sync.Mutex
import kotlinx.coroutines.sync.withLock
import kotlinx.coroutines.withContext

// A genre, with how many songs and albums the library has in it.
data class GenreCount(val name: String, val songs: Int, val albums: Int)

// The whole library as the server lists it, read once after signing in and
// kept in memory, for the pages that show everything (Songs, Albums,
// Artists, Genres, History) and for telling library songs from songs a
// search found online.
class LibraryIndex(val songs: List<Song>, val albums: List<Album>, val artists: List<Artist>) {
    private val songIds = songs.mapTo(HashSet()) { it.id }
    private val albumIds = albums.mapTo(HashSet()) { it.id }
    private val artistIds = artists.mapTo(HashSet()) { it.id }
    private val byTitle = TitleIndex(songs, { it.title }, { it.artist.orEmpty() })
    private val byIsrc = IsrcIndex(songs) { it.isrc }

    // Whether the server marks any song as in a family member's own
    // library. One that marks none is one that never marks.
    val marksPersonal: Boolean by lazy { songs.any { it.octoPersonal } }

    // Every genre, with its counts, A to Z. A song's genres are its
    // OpenSubsonic list when it has one, else its single genre. Worked out
    // with the rest of the index, away from the window's thread.
    val genres: List<GenreCount> = run {
        val songCounts = HashMap<String, Int>()
        val albumSets = HashMap<String, HashSet<String>>()
        val names = HashMap<String, String>()
        songs.forEach { song ->
            genresOf(song).forEach { genre ->
                val key = genre.lowercase()
                names.putIfAbsent(key, genre)
                songCounts[key] = (songCounts[key] ?: 0) + 1
                song.albumId?.let { albumSets.getOrPut(key) { HashSet() } += it }
            }
        }
        sortedByName(songCounts.keys.map { GenreCount(names.getValue(it), songCounts.getValue(it), albumSets[it]?.size ?: 0) }) { it.name }
    }

    fun songsInGenre(name: String): List<Song> = songs.filter { song -> genresOf(song).any { it.equals(name, ignoreCase = true) } }

    fun albumsInGenre(name: String): List<Album> {
        val ids = songsInGenre(name).mapNotNullTo(HashSet()) { it.albumId }
        return albums.filter { it.id in ids }
    }

    fun hasAlbum(id: String) = id in albumIds

    // The library's album of an album found online with its very name and
    // artist (case, accents and punctuation aside), as the server judges
    // it; nothing when there is none. Octo leaves such an album out of a
    // search itself; this is for a server that does not yet.
    fun namesake(album: Album): Album? = byNameAndArtist[nameAndArtistKey(album)]

    private val byNameAndArtist: Map<String, Album> by lazy {
        albums.filter { SongIdentity.key(it.name).isNotEmpty() }.associateBy(::nameAndArtistKey)
    }

    private fun nameAndArtistKey(album: Album) = SongIdentity.key(album.name) + "|" + SongIdentity.key(album.artist)

    fun hasArtist(id: String) = id in artistIds

    fun hasSong(id: String) = id in songIds

    // The index with music the server took in since it was read: `albums`
    // as the server lists them now and `songs`, each in place of the one
    // with its id or added. What the server marks as outside the library is
    // left out. An album's artist the index lacks is added, as the albums
    // name it. The same index when nothing is new.
    fun takingIn(songs: List<Song>, albums: List<Album>): LibraryIndex {
        val newSongs = LinkedHashMap<String, Song>()
        songs.filterNot { it.isExternal }.forEach { newSongs[it.id] = it }
        val newAlbums = LinkedHashMap<String, Album>()
        albums.filterNot { it.isExternal }.forEach { newAlbums[it.id] = it }
        if (newSongs.isEmpty() && newAlbums.isEmpty()) return this
        val artistsAdded = newAlbums.values
            .filter { !it.artistId.isNullOrEmpty() && it.artistId !in artistIds }
            .groupBy { it.artistId!! }
            .map { (id, owned) -> Artist(id, owned.first().artist, albumCount = owned.size) }
        return LibraryIndex(
            this.songs.filterNot { it.id in newSongs } + newSongs.values,
            this.albums.map { newAlbums[it.id] ?: it } + newAlbums.values.filterNot { it.id in albumIds },
            this.artists + artistsAdded,
        )
    }

    // Whether a song a server sent is in the library: the same id, or the
    // same song by the same artist (a find the server has since downloaded
    // under a new id), or a song with the same ISRC under another title. The
    // same rules the phone app uses.
    fun holds(song: Song): Boolean {
        if (song.id in songIds) return true
        val length = knownLengthMs(song)
        val candidates = byTitle.candidates(song.title, song.artist.orEmpty()) + byIsrc.candidates(song.isrc)
        return candidates.any { sameSong(song.title, song.artist.orEmpty(), length, it.title, it.artist.orEmpty(), knownLengthMs(it), song.isrc, it.isrc) }
    }

    // The library's own copy of a song it holds, by the same rules; nothing
    // when it does not hold it.
    fun copyOf(song: Song): Song? {
        if (song.id in songIds) return songs.firstOrNull { it.id == song.id }
        val length = knownLengthMs(song)
        val candidates = byTitle.candidates(song.title, song.artist.orEmpty()) + byIsrc.candidates(song.isrc)
        return candidates.firstOrNull { sameSong(song.title, song.artist.orEmpty(), length, it.title, it.artist.orEmpty(), knownLengthMs(it), song.isrc, it.isrc) }
    }

    // Songs that have been played, most recently first.
    val history: List<Song> = recentlyPlayed(songs)

    companion object {
        fun of(library: Library) = LibraryIndex(library.songs, library.albums, library.artists)

        fun genresOf(song: Song): List<String> =
            song.genres.ifEmpty { listOfNotNull(song.genre?.trim()?.takeIf(String::isNotEmpty)) }
    }
}

sealed interface LibraryState {
    data object Idle : LibraryState
    data object Loading : LibraryState
    class Ready(val index: LibraryIndex) : LibraryState
    class Failed(val message: String) : LibraryState
}

// Reads the library from the server, once, and again on request. The
// reading, the passes that drop repeats and the index are all done away
// from the window's thread (a big library takes over a second); only the
// finished index is handed back to the state the pages read. In between,
// music the server takes in is added to the index: what a search finds
// (takeIn), and what a look at the server's newest albums finds (look).
// Both need `client`.
class LibraryStore(
    private val read: suspend () -> Library,
    private val scope: CoroutineScope,
    private val client: SubsonicClient? = null,
    // A clock that only goes forward, in milliseconds.
    private val clock: () -> Long = { System.nanoTime() / 1_000_000 },
) {
    constructor(client: SubsonicClient, scope: CoroutineScope) : this({ client.readLibrary() }, scope, client)

    private val _state = MutableStateFlow<LibraryState>(LibraryState.Idle)
    val state: StateFlow<LibraryState> = _state
    private var job: Job? = null

    // One take-in or look at a time.
    private val takeInLock = Mutex()

    // When the server last read its folders, as it said before the last
    // read or look, and when the last look (or read) was.
    @Volatile private var seenScan: String? = null

    @Volatile private var lookedAt: Long? = null

    val index: LibraryIndex? get() = (state.value as? LibraryState.Ready)?.index

    fun load() {
        if (job?.isActive == true) return
        val previous = index
        if (previous == null) _state.value = LibraryState.Loading
        job = scope.launch {
            _state.value = try {
                val (scan, fresh) = withContext(Dispatchers.Default) {
                    // Asked before the read, so a look afterwards reads on
                    // only once the server has read its folders again.
                    val scan = client?.let { lastScanOf(it) }
                    scan to LibraryIndex.of(read())
                }
                seenScan = scan
                lookedAt = clock()
                LibraryState.Ready(fresh)
            } catch (e: SubsonicException) {
                // A failed refresh keeps what was read before.
                previous?.let { LibraryState.Ready(it) } ?: LibraryState.Failed(e.userMessage())
            }
        }
    }

    // Takes in music a search found that the index lacks (see Arriving):
    // the albums it names and those of its songs, read as the server has
    // them now, and the songs. It goes on to the end even when the one
    // asking stops waiting. A read running brings it all, so that is waited
    // for instead. Answers whether the index has any of it now.
    suspend fun takeIn(arriving: Arriving): Boolean {
        val client = client ?: return false
        if (arriving.isEmpty) return false
        return scope.async {
            takeInLock.withLock {
                job?.join()
                withContext(Dispatchers.Default) {
                    val read = readAlbums(client, arriving.albumIds())
                    putIn(read.flatMap { it.song } + arriving.songs, arriving.albums + read.map { it.asListed() })
                }
                val index = index ?: return@withLock false
                arriving.songs.any { index.hasSong(it.id) } || arriving.albums.any { index.hasAlbum(it.id) }
            }
        }.await()
    }

    // Looks for music the server took in since the library was read (see
    // lookForNewMusic), at most once a NEW_MUSIC_LOOK_MS: new albums, and
    // albums with songs added, are taken in; too many at once reads the
    // whole library again. Never while a read runs.
    fun look() {
        val client = client ?: return
        if (job?.isActive == true || index == null) return
        val now = clock()
        if (!newMusicLookDue(lookedAt, now)) return
        lookedAt = now
        scope.launch {
            takeInLock.withLock {
                val found = withContext(Dispatchers.Default) {
                    val index = index ?: return@withContext null
                    val look = try {
                        lookForNewMusic(client, seenScan) { ids ->
                            val asked = ids.toHashSet()
                            index.albums.filter { it.id in asked }.associate { it.id to it.songCount }
                        }
                    } catch (e: SubsonicException) {
                        return@withContext null
                    }
                    val found = look.found
                    var allIn = true
                    if (found is NewMusic.TakeIn) {
                        val read = readAlbums(client, found.albums.map { it.id })
                        // Each album read as the list gave it, so the next
                        // look sees the same count; one not read is left for
                        // the next look, which then reads on whatever the
                        // scan says.
                        val listed = found.albums.associateBy { it.id }
                        putIn(read.flatMap { it.song }, read.map { listed[it.id] ?: it.asListed() })
                        allIn = read.size == found.albums.size
                    }
                    if (found != NewMusic.CopyAll && allIn) seenScan = look.scan
                    found
                }
                if (found == NewMusic.CopyAll) load()
            }
        }
    }

    // Puts songs and albums into the index the pages read, unless a read
    // replaced it meanwhile.
    private fun putIn(songs: List<Song>, albums: List<Album>) {
        val now = state.value as? LibraryState.Ready ?: return
        val next = now.index.takingIn(songs, albums)
        if (next !== now.index) _state.compareAndSet(now, LibraryState.Ready(next))
    }

    // Albums read with their songs; one the server cannot give is skipped.
    private suspend fun readAlbums(client: SubsonicClient, ids: List<String>): List<AlbumWithSongs> = coroutineScope {
        ids.distinct().map { id ->
            async {
                try {
                    client.album(id)
                } catch (e: SubsonicException) {
                    null
                }
            }
        }.awaitAll().filterNotNull()
    }
}
