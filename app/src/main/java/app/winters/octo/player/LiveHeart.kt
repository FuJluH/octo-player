package app.winters.octo.player

import app.winters.octo.catalog.TrackEntity
import app.winters.octo.discovery.DownloadPhase
import app.winters.octo.liveradio.LiveSongButton
import app.winters.octo.liveradio.OnAir
import app.winters.octo.liveradio.SongLookup
import app.winters.octo.liveradio.heartQuery
import app.winters.octo.liveradio.liveSongButton
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.flow.update

// The song on air as the live player's song button knows it: the lookup
// for it (null while Octo is still being asked), and the outside songs
// asked for from this button.
data class LiveSongState(
    val onAir: OnAir = OnAir.Nothing,
    val lookup: SongLookup? = null,
    val requested: Set<String> = emptySet(),
)

// What the library says about the song: the library's liked songs, how
// each outside song asked for is coming along, and the library song each
// arrived one became.
data class LibraryNow(
    val liked: Set<String> = emptySet(),
    val phases: Map<String, DownloadPhase> = emptyMap(),
    val adoptions: Map<String, String> = emptyMap(),
)

// What a tap on the song button came to.
sealed interface SongTap {
    data class Hearted(val songId: String) : SongTap
    data class Unhearted(val songId: String) : SongTap
    // An outside song asked for: Octo downloads it into the library.
    data class Adding(val song: TrackEntity) : SongTap
    data class Searched(val query: String) : SongTap
    data object Failed : SongTap
    data object Ignored : SongTap
}

// The live player's button for the song on air. Each new song is looked up
// as it comes on (`look`, the same strict match the cover uses), so the
// button is known before any tap:
// - a song in the library: the heart, filled once liked;
// - a song outside it: a plus that has Octo download it, showing it on its
//   way, then the filled heart once it is in the library;
// - no song Octo is sure of: a plus that searches for it, never starring
//   anything;
// - no song named: no button.
// A tap while the look is still under way waits for its answer.
class LiveSong(
    private val look: suspend (OnAir, Boolean) -> SongLookup,
    private val like: suspend (songId: String, on: Boolean) -> Unit,
    private val add: suspend (TrackEntity) -> Boolean,
    private val search: (String) -> Unit,
) {
    private val _state = MutableStateFlow(LiveSongState())
    val state: StateFlow<LiveSongState> = _state.asStateFlow()

    // The station names something new.
    fun onAir(onAir: OnAir) {
        if (!same(onAir, _state.value.onAir)) _state.value = LiveSongState(onAir)
    }

    // Looks up the song on now, once; `again` asks Octo again after a look
    // that could not reach it.
    suspend fun lookUp(again: Boolean = false): SongLookup? {
        val air = _state.value.onAir
        if (!air.named) return null
        val found = look(air, again)
        _state.update { if (same(it.onAir, air)) it.copy(lookup = found) else it }
        return found
    }

    fun button(state: LiveSongState, library: LibraryNow): LiveSongButton {
        val match = state.lookup?.match
        val adopted = match?.let { library.adoptions[it.id] }
        val phase = match?.let { library.phases[it.id] } ?: DownloadPhase.None
        val asked = match != null && (match.id in state.requested || phase != DownloadPhase.None)
        val inLibrary = adopted != null || phase == DownloadPhase.Done
        val starred = when {
            match == null -> false
            match.inLibrary -> match.id in library.liked
            // Arrived: liked there, or asked for from here, which stars it.
            adopted != null -> adopted in library.liked || match.id in state.requested
            else -> asked
        }
        val adding = asked && !inLibrary && phase !is DownloadPhase.Failed
        return liveSongButton(state.onAir, match, state.lookup != null, starred, inLibrary, adding)
    }

    suspend fun tap(library: () -> LibraryNow): SongTap {
        val air = _state.value.onAir
        if (!air.named) return SongTap.Ignored
        val known = _state.value.lookup
        val found = when {
            known == null -> lookUp()
            !known.complete -> lookUp(again = true)
            else -> known
        } ?: return SongTap.Ignored
        val state = _state.value
        if (!same(state.onAir, air)) return SongTap.Ignored
        val now = library()
        val match = found.match
        return when (val button = button(state, now)) {
            LiveSongButton.None -> SongTap.Ignored
            LiveSongButton.Search -> heartQuery(air).let { query ->
                search(query)
                SongTap.Searched(query)
            }
            is LiveSongButton.Heart -> {
                val song = match ?: return SongTap.Failed
                val id = (if (song.inLibrary) song.id else now.adoptions[song.id]) ?: return SongTap.Failed
                like(id, !button.starred)
                if (button.starred) _state.update { it.copy(requested = it.requested - song.id) }
                if (button.starred) SongTap.Unhearted(id) else SongTap.Hearted(id)
            }
            is LiveSongButton.Add -> {
                if (button.adding || match == null) return SongTap.Ignored
                val song = found.songs[match.id] ?: return SongTap.Failed
                if (!add(song)) return SongTap.Failed
                _state.update { if (same(it.onAir, air)) it.copy(requested = it.requested + match.id) else it }
                SongTap.Adding(song)
            }
        }
    }

    private fun same(a: OnAir, b: OnAir): Boolean = a.title == b.title && a.artist == b.artist
}

// The song's name as copied: "Ariana Grande - Petal".
fun copiedSongName(onAir: OnAir): String = listOf(onAir.artist, onAir.title).filter(String::isNotBlank).joinToString(" - ")
