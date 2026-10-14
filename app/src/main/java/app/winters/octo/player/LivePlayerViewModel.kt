package app.winters.octo.player

import android.content.ClipData
import android.content.ClipboardManager
import android.content.Context
import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import app.winters.octo.catalog.CatalogDao
import app.winters.octo.catalog.TrackEntity
import app.winters.octo.catalog.searchKey
import app.winters.octo.data.userMessage
import app.winters.octo.discovery.Discovery
import app.winters.octo.discovery.Downloads
import app.winters.octo.liveradio.AddResult
import app.winters.octo.liveradio.HeartCandidate
import app.winters.octo.liveradio.KeptStations
import app.winters.octo.liveradio.LiveRadioStore
import app.winters.octo.liveradio.LiveStation
import app.winters.octo.liveradio.OnAir
import app.winters.octo.liveradio.ServerAdds
import app.winters.octo.liveradio.addResultLine
import app.winters.octo.liveradio.heartQuery
import app.winters.octo.playback.LikeStore
import app.winters.octo.playback.PlaybackConnection
import app.winters.octo.playback.radioDetailsOf
import app.winters.octo.playback.radioIsHls
import app.winters.octo.playback.radioOf
import app.winters.octo.server.ServerControls
import app.winters.octo.ui.common.Feedback
import app.winters.octo.ui.search.SearchAsks
import dagger.hilt.android.lifecycle.HiltViewModel
import dagger.hilt.android.qualifiers.ApplicationContext
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.flow.SharingStarted
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.distinctUntilChanged
import kotlinx.coroutines.flow.map
import kotlinx.coroutines.flow.stateIn
import kotlinx.coroutines.launch
import javax.inject.Inject

// What the live player does beyond playing: the heart for the song on air,
// and the station's menu (keep it, add it to the server, find or copy the
// song).
@HiltViewModel
class LivePlayerViewModel @Inject constructor(
    @ApplicationContext private val context: Context,
    playback: PlaybackConnection,
    private val catalog: CatalogDao,
    private val discovery: Discovery,
    private val downloads: Downloads,
    private val likes: LikeStore,
    private val store: LiveRadioStore,
    private val controls: ServerControls,
    private val feedback: Feedback,
    private val searches: SearchAsks,
) : ViewModel() {
    // Songs found outside the library for the last heart, by id, so the
    // one starred can be downloaded.
    private val outside = HashMap<String, TrackEntity>()

    private val heart = LiveHeart(
        find = { query, air -> candidates(query, air) },
        star = { song ->
            if (song.inLibrary) {
                if (!likes.isLiked(song.id)) likes.toggle(song.id)
                true
            } else {
                outside[song.id]?.let { downloads.request(it) } == true
            }
        },
        unstar = { song ->
            if (song.inLibrary && likes.isLiked(song.id)) likes.toggle(song.id)
            song.inLibrary
        },
    )

    val heartState: StateFlow<LiveHeartState> = heart.state

    init {
        viewModelScope.launch {
            playback.now.map { it.live?.shown?.onAir ?: OnAir.Nothing }.distinctUntilChanged().collect(heart::onAir)
        }
    }

    // The library's songs with the title on air, and the server's songs
    // from outside the library for the whole search.
    private suspend fun candidates(query: String, air: OnAir): List<HeartCandidate> {
        val library = catalog.searchTracks(searchKey(air.title), LIBRARY_LOOK).map { HeartCandidate(it.id, it.title, it.artist, inLibrary = true) }
        val found = try {
            discovery.search(query)?.songs.orEmpty()
        } catch (e: CancellationException) {
            throw e
        } catch (e: Exception) {
            emptyList()
        }
        outside.clear()
        found.forEach { outside[it.id] = it }
        return library + found.map { HeartCandidate(it.id, it.title, it.artist, inLibrary = false) }
    }

    fun tapHeart() {
        viewModelScope.launch {
            when (val outcome = heart.tap()) {
                is HeartOutcome.Starred -> feedback.done(if (outcome.song.inLibrary) "Added to Liked songs" else "Adding ${outcome.song.title} to your library")
                is HeartOutcome.NoMatch -> feedback.show(noMatchLine(heart.state.value.onAir), "Search", onAction = { searches.ask(outcome.query) })
                HeartOutcome.Failed -> feedback.show("Could not heart this song")
                HeartOutcome.Unstarred, HeartOutcome.Ignored -> Unit
            }
        }
    }

    // ---- The station's menu ----

    val kept: StateFlow<KeptStations> = store.kept.stateIn(viewModelScope, SharingStarted.WhileSubscribed(5_000), KeptStations())

    val admin: StateFlow<Boolean> = controls.admin

    // The server's stations' streams, read once the menu is first opened by an admin.
    private var serverStreams: Set<String>? = null

    private val adds = ServerAdds(
        admin = { controls.admin.value },
        streams = { serverStreams.orEmpty() },
        add = { station -> controls.addStation(station.streamUrl, station.name, radioHomepage) },
        why = { it.userMessage() },
    )

    // The home page of the station last added, for the server.
    private var radioHomepage: String? = null

    // Reads the server's stations, for an admin, so one already there is
    // not offered again.
    fun menuOpened() {
        if (!controls.admin.value || serverStreams != null) return
        viewModelScope.launch {
            serverStreams = runCatching { controls.stations().map { it.streamUrl }.filter(String::isNotBlank).toSet() }.getOrNull()
        }
    }

    // Whether the menu offers adding the station `id` to the server.
    fun addable(id: String): Boolean = liveStationOf(id)?.let(adds::offers) == true

    fun keep(id: String) {
        val station = liveStationOf(id)?.takeIf { it.uuid.isNotBlank() } ?: return
        viewModelScope.launch {
            store.keep(station)
            feedback.done("Kept ${station.name} on Live radio")
        }
    }

    fun remove(id: String) {
        val station = liveStationOf(id)?.takeIf { it.uuid.isNotBlank() } ?: return
        viewModelScope.launch {
            store.drop(station.uuid)
            feedback.undoable("Removed ${station.name}") { viewModelScope.launch { store.keep(station) } }
        }
    }

    fun addToServer(id: String) {
        val station = liveStationOf(id) ?: return
        radioHomepage = radioDetailsOf(id).homepage.ifBlank { null }
        viewModelScope.launch {
            val result = adds.addToServer(station)
            val line = addResultLine(result, station.name)
            if (result == AddResult.Added) {
                serverStreams = serverStreams.orEmpty() + station.streamUrl
                feedback.done(line)
            } else {
                feedback.show(line)
            }
        }
    }

    // Search, with the song on air.
    fun findSong(onAir: OnAir) = searches.ask(heartQuery(onAir))

    fun copySong(onAir: OnAir) {
        val words = copiedSongName(onAir)
        if (words.isBlank()) return
        context.getSystemService(ClipboardManager::class.java)?.setPrimaryClip(ClipData.newPlainText("Song", words))
        feedback.done("Copied $words")
    }

    private companion object {
        // How many library songs with the title are weighed.
        const val LIBRARY_LOOK = 40
    }
}

// The Radio Browser station a queue id carries, as the live radio list
// keeps it; null for an id that is not a station.
fun liveStationOf(id: String): LiveStation? {
    val (stream, name) = radioOf(id) ?: return null
    val details = radioDetailsOf(id)
    return LiveStation(
        uuid = details.uuid,
        name = name.ifBlank { stream },
        streamUrl = stream,
        favicon = details.logo,
        codec = details.codec,
        bitrate = details.bitrate,
        hls = radioIsHls(id),
        country = details.country,
        countryCode = details.countryCode,
        state = details.state,
        tags = details.tags,
    )
}
