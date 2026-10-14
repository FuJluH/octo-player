package app.winters.octo.player

import app.winters.octo.liveradio.HeartCandidate
import app.winters.octo.liveradio.OnAir
import app.winters.octo.liveradio.heartMatch
import app.winters.octo.liveradio.heartQuery
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.flow.update

// The heart in the live player, for the song on air: whether it is
// starred, and whether it is being looked for now.
data class LiveHeartState(val onAir: OnAir = OnAir.Nothing, val starred: HeartCandidate? = null, val working: Boolean = false) {
    // Hidden while the station names no song.
    val shown: Boolean get() = onAir.named
}

// What a tap on the live heart came to.
sealed interface HeartOutcome {
    // The song is starred: the library's copy, or one from outside it that
    // the server downloads.
    data class Starred(val song: HeartCandidate) : HeartOutcome

    // The star was taken off again.
    data object Unstarred : HeartOutcome

    // No search result is surely the song on air; `query` searches for it.
    data class NoMatch(val query: String) : HeartOutcome

    // The star could not be set.
    data object Failed : HeartOutcome

    // Nothing to do: no song is named, or a tap is still on its way.
    data object Ignored : HeartOutcome
}

// Hearts the song a station has on air: it searches for it (`find`, the
// library and outside it), stars the one result that is surely it
// (heartMatch) with `star`, and never another. A new song on air starts
// it afresh, unstarred.
class LiveHeart(
    private val find: suspend (query: String, onAir: OnAir) -> List<HeartCandidate>,
    private val star: suspend (HeartCandidate) -> Boolean,
    private val unstar: suspend (HeartCandidate) -> Boolean,
) {
    private val _state = MutableStateFlow(LiveHeartState())
    val state: StateFlow<LiveHeartState> = _state.asStateFlow()

    // The station names something new.
    fun onAir(onAir: OnAir) {
        if (!same(onAir, _state.value.onAir)) _state.value = LiveHeartState(onAir)
    }

    suspend fun tap(): HeartOutcome {
        val now = _state.value
        val air = now.onAir
        if (!air.named || now.working) return HeartOutcome.Ignored
        now.starred?.let { song ->
            if (!unstar(song)) return HeartOutcome.Failed
            _state.update { if (same(it.onAir, air)) it.copy(starred = null) else it }
            return HeartOutcome.Unstarred
        }
        _state.update { it.copy(working = true) }
        try {
            val query = heartQuery(air)
            val match = heartMatch(air, find(query, air)) ?: return HeartOutcome.NoMatch(query)
            if (!star(match)) return HeartOutcome.Failed
            _state.update { if (same(it.onAir, air)) it.copy(starred = match) else it }
            return HeartOutcome.Starred(match)
        } finally {
            _state.update { if (same(it.onAir, air)) it.copy(working = false) else it }
        }
    }

    private fun same(a: OnAir, b: OnAir): Boolean = a.title == b.title && a.artist == b.artist
}

// What a screen reader calls the live heart: "Heart Petal by Ariana Grande".
fun liveHeartLabel(onAir: OnAir): String =
    if (onAir.artist.isBlank()) "Heart ${onAir.title}" else "Heart ${onAir.title} by ${onAir.artist}"

// The short line shown when no result is surely the song on air.
fun noMatchLine(onAir: OnAir): String = "Could not find ${onAir.title} in Octo for sure"

// The song's name as copied: "Ariana Grande - Petal".
fun copiedSongName(onAir: OnAir): String = listOf(onAir.artist, onAir.title).filter(String::isNotBlank).joinToString(" - ")
