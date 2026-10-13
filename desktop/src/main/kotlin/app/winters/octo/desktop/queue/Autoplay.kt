package app.winters.octo.desktop.queue

import app.winters.octo.desktop.library.LibraryIndex
import app.winters.octo.desktop.library.libraryOnlySongs
import app.winters.octo.desktop.player.DesktopPlayer
import app.winters.octo.desktop.player.PlayerState
import app.winters.octo.desktop.player.RepeatMode
import app.winters.octo.desktop.system.OPENED_FILE_PREFIX
import app.winters.octo.playback.AUTOPLAY_BATCH
import app.winters.octo.playback.QueueSource
import app.winters.octo.playback.autoplayPicks
import app.winters.octo.playback.isRadio
import app.winters.octo.radio.RadioDiscovery
import app.winters.octo.radio.RadioInput
import app.winters.octo.radio.RadioTuning
import app.winters.octo.radio.radioMix
import app.winters.octo.radio.radioSong
import app.winters.octo.subsonic.Song
import app.winters.octo.subsonic.SubsonicClient
import app.winters.octo.subsonic.SubsonicException
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Job
import kotlinx.coroutines.delay
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.combine
import kotlinx.coroutines.flow.distinctUntilChanged
import kotlinx.coroutines.launch
import kotlin.random.Random
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.flowOf

// Songs played this recently are not picked again, as on the phone.
private const val RECENT_PLAYS = 50

// How near the end of the last song the new songs go in: early enough for
// the server to answer and the engine to open the next one.
const val AUTOPLAY_LEAD_MS = 20_000L

// How often to look at how far into the last song the player is.
private const val WATCH_EVERY_MS = 1_000L

// This close to its end, a stopped song counts as played out.
private const val ENDED_MS = 1_000L

// Keeps music playing when the queue runs out, with the phone's rules:
// near the end of the last song, with repeat off and the setting on, it
// adds songs like it, marked as Autoplay's so the queue tells them from
// the listener's own. It tries once per song; turning the setting off, a
// pause, repeat or songs put in stand it down. `pick` finds the songs for
// a seed, leaving out the ids given.
class Autoplay(
    private val player: DesktopPlayer,
    private val enabled: StateFlow<Boolean>,
    private val scope: CoroutineScope,
    private val pick: suspend (seed: Song, exclude: Set<String>) -> List<Song>,
    private val leadMs: Long = AUTOPLAY_LEAD_MS,
    private val everyMs: Long = WATCH_EVERY_MS,
    // Whether something else keeps the songs to come going (a station), and
    // a flow that changes when that may have stopped being so.
    private val standsDown: (PlayerState) -> Boolean = { false },
    private val standsDownChanged: Flow<Int> = flowOf(0),
) {
    // The last song's watch, and the entry it is for.
    private var watch: Job? = null
    private var watching: Long? = null

    // The entry Autoplay last tried to add after.
    @Volatile private var doneFor: Long? = null

    fun start(): Job = scope.launch {
        combine(player.state, enabled, standsDownChanged) { state, on, _ -> lastSong(state, on) }
            .distinctUntilChanged()
            .collect { key -> check(key) }
    }

    // The entry to add after, when everything says so; else null.
    private fun lastSong(state: PlayerState, on: Boolean): Long? {
        val current = state.current ?: return null
        val due = on && state.playing && state.repeat == RepeatMode.Off && state.upcoming.isEmpty() &&
            !current.song.id.startsWith(OPENED_FILE_PREFIX) && !isRadio(current.song.id) && !standsDown(state)
        return current.key.takeIf { due }
    }

    private fun check(key: Long?) {
        if (key == null || key == doneFor) {
            watch?.cancel()
            watch = null
            watching = null
            return
        }
        if (watch?.isActive == true && watching == key) return
        watch?.cancel()
        watching = key
        watch = scope.launch { watchAndAdd(key) }
    }

    private suspend fun watchAndAdd(key: Long) {
        while ((leftMs() ?: Long.MAX_VALUE) > leadMs) delay(everyMs)
        val state = player.state.value
        val seed = state.current?.takeIf { it.key == key }?.song ?: return
        val queued = state.queue.map { it.song.id }.toSet()
        // Tried once for this song, whatever comes of it.
        doneFor = key
        // Apart from the watch, so the song ending meanwhile does not stop it.
        scope.launch {
            val songs = runCatching { pick(seed, queued + seed.id) }.getOrDefault(emptyList())
            if (songs.isEmpty()) return@launch
            // Only if the song is still the last one and the setting still on.
            val now = player.state.value
            if (!enabled.value || now.current?.key != key || now.upcoming.isNotEmpty()) return@launch
            // The song ended while the server answered: carry on.
            val ended = !now.playing && (leftMs() ?: Long.MAX_VALUE) < ENDED_MS
            player.addToQueue(songs, QueueSource.Autoplay)
            if (ended) player.state.value.upcoming.firstOrNull()?.let { player.skipTo(it.key) }
        }
    }

    // How long until the song playing ends, in real time at its speed, or
    // null while its length is unknown (a stream never ends by itself).
    private fun leftMs(): Long? {
        val state = player.state.value
        val length = state.durationMs.takeIf { it > 0 } ?: return null
        return ((length - player.positionMs()).coerceAtLeast(0) / state.speed.coerceAtLeast(0.1f)).toLong()
    }
}

// The songs Autoplay adds after `seed`: Octo's radio for the seed and the
// listener's own recent songs (`anchors`), over the library and the
// server's songs like the seed (see radioMix), spaced on from the songs in
// `before`. When the radio finds nothing (a seed with no genre and no
// server answer), the old rules: the library's songs by the same artist,
// then in the same genre, else any from the library. Never one in
// `exclude` or played lately. With `libraryOnly`, the server's songs found
// online are left out.
suspend fun autoplaySongs(
    seed: Song,
    exclude: Set<String>,
    client: SubsonicClient?,
    index: LibraryIndex?,
    before: List<Song> = emptyList(),
    anchors: List<Song> = emptyList(),
    rating: (Song) -> Int = { it.userRating ?: 0 },
    tuning: RadioTuning = RadioTuning(),
    now: Long = System.currentTimeMillis(),
    random: Random = Random.Default,
    libraryOnly: Boolean = false,
): List<Song> {
    val recent = index?.history?.take(RECENT_PLAYS)?.map { it.id }.orEmpty()
    val skip = exclude + recent + seed.id
    val similar = try {
        libraryOnlySongs(client?.similarSongs(seed.id, tuning.suggestions).orEmpty(), index, libraryOnly)
    } catch (e: SubsonicException) {
        emptyList()
    }
    val known = HashMap<String, Song>()
    similar.forEach { known[it.id] = it }
    index?.songs?.forEach { known[it.id] = it }
    // The library's copy of a song the server suggested has no word of who suggested it.
    val suggestedBy = similar.mapNotNull { s -> s.octoSuggestedBy?.let { s.id to it } }.toMap()
    fun Song.withSource() = suggestedBy[id]?.let { copy(octoSuggestedBy = it) } ?: this
    val mixed = radioMix(
        RadioInput(
            seeds = (listOf(seed) + anchors).distinctBy { it.id }.map { it.radioSong(rating(it)) },
            library = index?.songs.orEmpty().map { it.radioSong(rating(it)) },
            suggested = similar.map { it.radioSong(rating(it)) },
            before = (before + seed).map { it.radioSong(rating(it)) },
            exclude = skip,
            now = now,
            tuning = tuning,
        ),
        AUTOPLAY_BATCH,
        random,
    )
    if (mixed.isNotEmpty()) return mixed.mapNotNull { known[it.id]?.withSource() }
    // Only my library keeps the server's songs from outside it out here too.
    val owned = index?.songs?.mapTo(HashSet()) { it.id }.orEmpty()
    val offered = similar.filter { tuning.discovery != RadioDiscovery.LibraryOnly || it.id in owned }
    val fromServer = autoplayPicks(offered.map { it.id }, emptyList(), emptyList(), skip)
    if (fromServer.isNotEmpty()) return fromServer.mapNotNull { known[it]?.withSource() }
    if (index == null) return emptyList()
    val artist = index.songs.filter { song ->
        if (seed.artistId != null) song.artistId == seed.artistId else song.artist != null && song.artist.equals(seed.artist, ignoreCase = true)
    }
    val genre = LibraryIndex.genresOf(seed).firstOrNull()?.let(index::songsInGenre).orEmpty()
    val picked = autoplayPicks(emptyList(), artist.map { it.id }.shuffled(), genre.map { it.id }.shuffled(), skip)
        .ifEmpty { autoplayPicks(emptyList(), emptyList(), index.songs.shuffled().take(500).map { it.id }, skip) }
    return picked.mapNotNull(known::get)
}
