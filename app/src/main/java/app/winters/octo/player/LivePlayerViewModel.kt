package app.winters.octo.player

import android.content.ClipData
import android.content.ClipboardManager
import android.content.Context
import android.util.Log
import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import app.winters.octo.data.userMessage
import app.winters.octo.discovery.DownloadPhase
import app.winters.octo.discovery.Downloads
import app.winters.octo.liveradio.AddResult
import app.winters.octo.liveradio.KeptStations
import app.winters.octo.liveradio.LiveLookup
import app.winters.octo.liveradio.LiveSongButton
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
import kotlinx.coroutines.flow.collectLatest
import kotlinx.coroutines.flow.combine
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
    private val lookup: LiveLookup,
    private val downloads: Downloads,
    private val likes: LikeStore,
    private val store: LiveRadioStore,
    private val controls: ServerControls,
    private val feedback: Feedback,
    private val searches: SearchAsks,
) : ViewModel() {
    // The song button weighs the same look the cover came from: kept per
    // song, so Octo is asked again only when that look could not reach it.
    private val song = LiveSong(
        look = { air, again -> lookup.look(air, again) },
        like = { id, on -> if (likes.isLiked(id) != on) likes.toggle(id) },
        add = { track -> downloads.request(track) },
        search = searches::ask,
    )

    private val library: StateFlow<LibraryNow> = combine(likes.liked, downloads.phases, downloads.adoptions) { liked, phases, adoptions ->
        LibraryNow(liked, phases, adoptions.orEmpty())
    }.stateIn(viewModelScope, SharingStarted.Eagerly, LibraryNow())

    // The button for the song on air: the heart, the plus that adds it or
    // searches for it, or none.
    val songButton: StateFlow<LiveSongButton> = combine(song.state, library, song::button)
        .stateIn(viewModelScope, SharingStarted.WhileSubscribed(5_000), LiveSongButton.None)

    // How the outside song asked for from the plus is coming along, for its
    // ring: Queued until the server's own word on it comes.
    val songPhase: StateFlow<DownloadPhase> = combine(song.state, library) { state, now ->
        val id = state.lookup?.match?.id ?: return@combine DownloadPhase.None
        now.phases[id] ?: if (id in state.requested) DownloadPhase.Queued else DownloadPhase.None
    }.stateIn(viewModelScope, SharingStarted.WhileSubscribed(5_000), DownloadPhase.None)

    init {
        // Each new song is looked up as it comes on, before any tap.
        viewModelScope.launch {
            playback.now.map { it.live?.shown?.onAir ?: OnAir.Nothing }.distinctUntilChanged().collectLatest { air ->
                song.onAir(air)
                try {
                    song.lookUp()
                } catch (e: CancellationException) {
                    throw e
                } catch (e: Exception) {
                    Log.w("Octo", "song on air not looked up: ${e.javaClass.simpleName}")
                }
            }
        }
    }

    fun tapSong() {
        viewModelScope.launch {
            val outcome = try {
                song.tap { library.value }
            } catch (e: CancellationException) {
                throw e
            } catch (e: Exception) {
                SongTap.Failed
            }
            when (outcome) {
                is SongTap.Hearted -> feedback.done("Added to Liked songs")
                is SongTap.Adding -> feedback.done("Adding ${outcome.song.title} to your library")
                SongTap.Failed -> feedback.show("Could not add this song")
                is SongTap.Unhearted, is SongTap.Searched, SongTap.Ignored -> Unit
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
