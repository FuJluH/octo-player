package app.winters.octo.liveradio

import app.winters.octo.catalog.CatalogDao
import app.winters.octo.catalog.TrackEntity
import app.winters.octo.catalog.searchKey
import app.winters.octo.discovery.Discovery
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.CompletableDeferred
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import javax.inject.Inject
import javax.inject.Singleton

// What a look for the song on air found: every song weighed, the songs
// themselves by id, and the one that is surely it (heartMatch), whose
// cover the live player shows. `complete` is false when Octo could not be
// asked, so a heart tap asks again.
data class SongLookup(
    val candidates: List<HeartCandidate> = emptyList(),
    val songs: Map<String, TrackEntity> = emptyMap(),
    val match: HeartCandidate? = null,
    val complete: Boolean = true,
) {
    // The matched song's cover, an artwork reference.
    val cover: String? get() = match?.let { songs[it.id]?.artwork }?.takeIf(String::isNotBlank)
}

// Looks up the songs stations have on air: once per song (by its artist
// and title), the answer kept for the next time it plays, and one look at
// a time for each song however often it is asked for.
class SongLookups(private val kept: Int = 64, private val search: suspend (OnAir) -> SongLookup) {
    private val answers = object : LinkedHashMap<String, SongLookup>(16, 0.75f, true) {
        override fun removeEldestEntry(eldest: MutableMap.MutableEntry<String, SongLookup>) = size > kept
    }
    private val running = HashMap<String, CompletableDeferred<SongLookup>>()

    // The answer kept for this song, if it was looked up.
    @Synchronized
    fun known(onAir: OnAir): SongLookup? = answers[keyOf(onAir)]

    // The answer for this song: kept, or looked up now. `again` looks up
    // one whose last look could not reach Octo.
    suspend fun look(onAir: OnAir, again: Boolean = false): SongLookup {
        if (!onAir.named) return SongLookup()
        val key = keyOf(onAir)
        val (waiting, mine) = synchronized(this) {
            answers[key]?.takeIf { it.complete || !again }?.let { return it }
            running[key]?.let { return@synchronized it to false }
            CompletableDeferred<SongLookup>().also { running[key] = it } to true
        }
        if (!mine) return waiting.await()
        try {
            val found = search(onAir)
            synchronized(this) { answers[key] = found }
            waiting.complete(found)
            return found
        } catch (e: Throwable) {
            waiting.completeExceptionally(e)
            throw e
        } finally {
            synchronized(this) { running.remove(key) }
        }
    }

    private fun keyOf(onAir: OnAir): String = searchKey(onAir.artist) + "\u0000" + searchKey(onAir.title)
}

// The songs on air, looked up through Octo: the library's songs with the
// title, and the server's search (search3) for the artist and title, from
// outside the library too. The heart and the cover share each answer.
@Singleton
class LiveLookup @Inject constructor(
    private val catalog: CatalogDao,
    private val discovery: Discovery,
) {
    private val lookups = SongLookups { air -> withContext(Dispatchers.IO) { search(air) } }

    fun known(onAir: OnAir): SongLookup? = lookups.known(onAir)

    suspend fun look(onAir: OnAir, again: Boolean = false): SongLookup = lookups.look(onAir, again)

    private suspend fun search(air: OnAir): SongLookup {
        val library = catalog.searchTracks(searchKey(air.title), LIBRARY_LOOK)
        var complete = true
        val outside = try {
            discovery.search(heartQuery(air))?.songs.orEmpty()
        } catch (e: CancellationException) {
            throw e
        } catch (e: Exception) {
            complete = false
            emptyList()
        }
        return songLookupOf(air, library, outside, complete)
    }

    private companion object {
        // How many library songs with the title are weighed.
        const val LIBRARY_LOOK = 40
    }
}

// The answer for the song on air from the library's songs and those found
// outside it.
fun songLookupOf(air: OnAir, library: List<TrackEntity>, outside: List<TrackEntity>, complete: Boolean = true): SongLookup {
    val candidates = library.map { HeartCandidate(it.id, it.title, it.artist, inLibrary = true) } +
        outside.map { HeartCandidate(it.id, it.title, it.artist, inLibrary = false) }
    val songs = (library + outside).associateBy { it.id }
    return SongLookup(candidates, songs, heartMatch(air, candidates), complete)
}
