package app.winters.octo.ui.online

import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.itemsIndexed
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.ui.Modifier
import androidx.hilt.lifecycle.viewmodel.compose.hiltViewModel
import androidx.lifecycle.ViewModel
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import androidx.lifecycle.viewModelScope
import androidx.navigation3.runtime.NavKey
import app.winters.octo.ambient.PageArtwork
import app.winters.octo.catalog.TrackEntity
import app.winters.octo.catalog.isFind
import app.winters.octo.discovery.Discovery
import app.winters.octo.discovery.DownloadState
import app.winters.octo.discovery.Downloads
import app.winters.octo.playback.PlaybackConnection
import app.winters.octo.subsonic.SubsonicException
import app.winters.octo.ui.album.AlbumHeader
import app.winters.octo.ui.common.BackButton
import app.winters.octo.ui.common.CHECK_SETTLE_MS
import app.winters.octo.ui.common.DetailTopGap
import app.winters.octo.ui.common.LoadState
import app.winters.octo.ui.common.LoadStateContent
import app.winters.octo.ui.common.load
import app.winters.octo.ui.common.SongLead
import app.winters.octo.ui.common.SongRow
import app.winters.octo.ui.common.asLength
import app.winters.octo.ui.common.screenPadding
import app.winters.octo.ui.common.songs
import app.winters.octo.ui.home.stationGoneLine
import app.winters.octo.ui.nav.ServerListRoute
import dagger.assisted.Assisted
import dagger.assisted.AssistedFactory
import dagger.assisted.AssistedInject
import dagger.hilt.android.lifecycle.HiltViewModel
import kotlinx.coroutines.delay
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.flow.collectLatest
import kotlinx.coroutines.flow.drop
import kotlinx.coroutines.launch

@HiltViewModel(assistedFactory = ServerListViewModel.Factory::class)
class ServerListViewModel @AssistedInject constructor(
    @Assisted private val route: ServerListRoute,
    private val discovery: Discovery,
    private val downloads: Downloads,
    private val playback: PlaybackConnection,
) : ViewModel() {
    private val _page = MutableStateFlow<LoadState<List<TrackEntity>>>(LoadState.Loading)
    val page: StateFlow<LoadState<List<TrackEntity>>> = _page.asStateFlow()

    init {
        reload()
        // A song from here that joins the library turns into a library song
        // in the list, once its check has landed.
        viewModelScope.launch {
            downloads.arrived.drop(1).collectLatest {
                delay(CHECK_SETTLE_MS)
                val songs = (_page.value as? LoadState.Ready)?.data.orEmpty()
                if (songs.any { isFind(it.id) && downloads.state(it.id) == DownloadState.Done }) refresh()
            }
        }
    }

    fun reload() {
        _page.value = LoadState.Loading
        viewModelScope.launch { _page.value = read() }
    }

    // Asks the server again, keeping the list as it is if it cannot answer.
    private suspend fun refresh() {
        val fresh = read()
        if (fresh is LoadState.Ready) _page.value = fresh
    }

    // The songs the list has lined up. A list the server has made anew since
    // it was shown is gone, and Home is told so it can take it off.
    private suspend fun read(): LoadState<List<TrackEntity>> {
        var gone = false
        val state = load {
            try {
                discovery.stationSongs(route.id)
            } catch (e: SubsonicException.NotFound) {
                gone = true
                emptyList()
            }
        }
        if (!gone) return state
        discovery.listGone(route.id)
        return LoadState.Failed(stationGoneLine(route.name))
    }

    // Plays the songs shown, from one of them, the queue named after the
    // list. A station keeps going past them.
    fun play(index: Int) = if (route.radio) {
        playback.playStation(ids(), index, route.id, route.name)
    } else {
        playback.playTracks(ids(), index, source = route.name)
    }

    fun shuffle() = if (route.radio) {
        playback.playStation(ids(), 0, route.id, route.name, shuffle = true)
    } else {
        playback.playTracks(ids(), shuffle = true, source = route.name)
    }

    private fun ids() = (page.value as? LoadState.Ready)?.data.orEmpty().map { it.id }

    @AssistedFactory
    interface Factory {
        fun create(route: ServerListRoute): ServerListViewModel
    }
}

// A list the server makes, such as a station or a Made for you list: its
// songs, which play from any of them. A station shows the songs it has lined
// up and keeps going once played. Nothing in it can be edited here.
@Composable
fun ServerListScreen(
    route: ServerListRoute,
    onBack: () -> Unit,
    vm: ServerListViewModel = hiltViewModel<ServerListViewModel, ServerListViewModel.Factory> { it.create(route) },
) {
    val page by vm.page.collectAsStateWithLifecycle()

    Box(Modifier.fillMaxSize()) {
        PageArtwork(route, route.artwork)
        LoadStateContent(page, onRetry = vm::reload) { songs ->
            // The length only adds up when every song's length is known.
            val length = songs.takeIf { list -> list.isNotEmpty() && list.all { it.durationMs > 0 } }
                ?.let { list -> (list.sumOf { it.durationMs } / 1000).toInt().asLength() }
            LazyColumn(Modifier.fillMaxSize(), contentPadding = screenPadding(extraTop = DetailTopGap)) {
                item(key = "header") {
                    AlbumHeader(
                        artwork = route.artwork,
                        title = route.name,
                        artist = "Octo",
                        details = listOfNotNull(songs(songs.size), length).joinToString(" • "),
                        onArtist = null,
                        onPlay = { vm.play(0) },
                        onShuffle = vm::shuffle,
                    )
                }
                val mixed = songs.any { isFind(it.id) }
                itemsIndexed(songs, key = { index, track -> "$index:${track.id}" }) { index, track ->
                    SongRow(track, SongLead.Artwork, ownership = mixed) { vm.play(index) }
                }
            }
        }
        BackButton(onBack)
    }
}
