package app.winters.octo.ui.online

import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.itemsIndexed
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.unit.dp
import androidx.hilt.lifecycle.viewmodel.compose.hiltViewModel
import androidx.lifecycle.ViewModel
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import androidx.lifecycle.viewModelScope
import androidx.navigation3.runtime.NavKey
import app.winters.octo.ambient.PageArtwork
import app.winters.octo.catalog.isFind
import app.winters.octo.design.OctoColors
import app.winters.octo.design.OctoIcons
import app.winters.octo.design.OctoType
import app.winters.octo.discovery.Discovery
import app.winters.octo.discovery.DownloadState
import app.winters.octo.discovery.Downloads
import app.winters.octo.discovery.OnlineAlbumPage
import app.winters.octo.discovery.TopSongsSource
import app.winters.octo.discovery.albumHighlight
import app.winters.octo.playback.PlaybackConnection
import app.winters.octo.ui.album.AlbumHeader
import app.winters.octo.ui.common.BackButton
import app.winters.octo.ui.common.CHECK_SETTLE_MS
import app.winters.octo.ui.common.DetailTopGap
import app.winters.octo.ui.common.LoadState
import app.winters.octo.ui.common.LoadStateContent
import app.winters.octo.ui.common.LocalAdoptedFinds
import app.winters.octo.ui.common.QuietAction
import app.winters.octo.ui.common.QuietActions
import app.winters.octo.ui.common.SongLead
import app.winters.octo.ui.common.SongRow
import app.winters.octo.ui.common.albumLibraryNote
import app.winters.octo.ui.common.asLength
import app.winters.octo.ui.common.isOutsideLibrary
import app.winters.octo.ui.common.screenPadding
import app.winters.octo.ui.common.songs
import app.winters.octo.ui.nav.OnlineAlbumRoute
import app.winters.octo.ui.nav.OnlineArtistRoute
import dagger.assisted.Assisted
import dagger.assisted.AssistedFactory
import dagger.assisted.AssistedInject
import dagger.hilt.android.lifecycle.HiltViewModel
import kotlinx.coroutines.delay
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.SharingStarted
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.flow.collectLatest
import kotlinx.coroutines.flow.combine
import kotlinx.coroutines.flow.distinctUntilChanged
import kotlinx.coroutines.flow.drop
import kotlinx.coroutines.flow.flowOf
import kotlinx.coroutines.flow.map
import app.winters.octo.animated.AnimatedArts
import app.winters.octo.subsonic.AnimatedClip
import kotlinx.coroutines.flow.stateIn
import kotlinx.coroutines.launch

@HiltViewModel(assistedFactory = OnlineAlbumViewModel.Factory::class)
class OnlineAlbumViewModel @AssistedInject constructor(
    @Assisted private val id: String,
    private val discovery: Discovery,
    private val downloads: Downloads,
    private val playback: PlaybackConnection,
    private val topSongs: TopSongsSource,
    animatedArts: AnimatedArts,
) : ViewModel() {
    // The album's square loop, in place of its cover.
    val loop: StateFlow<AnimatedClip?> = animatedArts.pageLoop(flowOf(id))
        .stateIn(viewModelScope, SharingStarted.WhileSubscribed(5_000), null)

    private val _page = MutableStateFlow<LoadState<OnlineAlbumPage>>(LoadState.Loading)
    val page: StateFlow<LoadState<OnlineAlbumPage>> = _page.asStateFlow()

    // Set once the album is asked for here, cleared if the server says no.
    private val asked = MutableStateFlow(false)

    // Whether the album is on its way: asked for here, or every song from it
    // that is not in the library already asked for.
    val downloading: StateFlow<Boolean> = combine(_page, asked, downloads.states) { page, asked, states ->
        val finds = (page as? LoadState.Ready)?.data?.songs.orEmpty().filter { isFind(it.id) }
        asked || (finds.isNotEmpty() && finds.all { (states[it.id] ?: DownloadState.None) != DownloadState.None })
    }.stateIn(viewModelScope, SharingStarted.WhileSubscribed(5_000), false)

    init {
        reload()
        // A song from here that joins the library turns into a library song
        // on the page, once its check has landed.
        viewModelScope.launch {
            downloads.arrived.drop(1).collectLatest {
                delay(CHECK_SETTLE_MS)
                val songs = (_page.value as? LoadState.Ready)?.data?.songs.orEmpty()
                if (songs.any { isFind(it.id) && downloads.state(it.id) == DownloadState.Done }) refresh()
            }
        }
    }

    // The album's main song, starred as Apple Music does: the one first in
    // the artist's top songs on the server. None until known, or when no song
    // here is among them.
    val highlight: StateFlow<String?> = _page
        .map { (it as? LoadState.Ready)?.data }
        .distinctUntilChanged()
        .map { found -> found?.let { albumHighlight(it.songs, topSongs.forArtist(it.album.artist)) } }
        .stateIn(viewModelScope, SharingStarted.WhileSubscribed(5_000), null)

    fun reload() {
        _page.value = LoadState.Loading
        viewModelScope.launch { _page.value = loadOnline { discovery.album(id) } }
    }

    // Asks the server again, keeping the page as it is if it cannot answer.
    private suspend fun refresh() {
        val fresh = loadOnline { discovery.album(id) }
        if (fresh is LoadState.Ready) _page.value = fresh
    }

    // Plays the album from one of its songs.
    fun play(index: Int) = playback.playTracks(ids(), index)

    fun shuffle() = playback.playTracks(ids(), shuffle = true)

    // Has the server download the whole album into the library.
    fun download() {
        val found = (page.value as? LoadState.Ready)?.data ?: return
        asked.value = true
        viewModelScope.launch {
            if (!downloads.requestAlbum(id, found.songs, found.album.title)) asked.value = false
        }
    }

    private fun ids() = (page.value as? LoadState.Ready)?.data?.songs.orEmpty().map { it.id }

    @AssistedFactory
    interface Factory {
        fun create(id: String): OnlineAlbumViewModel
    }
}

// An album on the server that is not in the library. Songs the library has
// play as usual; the rest can be downloaded one by one or all at once.
@Composable
fun OnlineAlbumScreen(
    id: String,
    onOpen: (NavKey) -> Unit,
    onBack: () -> Unit,
    vm: OnlineAlbumViewModel = hiltViewModel<OnlineAlbumViewModel, OnlineAlbumViewModel.Factory> { it.create(id) },
) {
    val page by vm.page.collectAsStateWithLifecycle()
    val downloading by vm.downloading.collectAsStateWithLifecycle()
    val highlight by vm.highlight.collectAsStateWithLifecycle()

    Box(Modifier.fillMaxSize()) {
        LoadStateContent(page, onRetry = vm::reload) { found ->
            val album = found.album
            PageArtwork(OnlineAlbumRoute(id), album.artwork)
            // The length only adds up when every song's length is known.
            val length = found.songs.takeIf { songs -> songs.isNotEmpty() && songs.all { it.durationMs > 0 } }
                ?.let { songs -> (songs.sumOf { it.durationMs } / 1000).toInt().asLength() }
            LazyColumn(Modifier.fillMaxSize(), contentPadding = screenPadding(extraTop = DetailTopGap)) {
                item(key = "header") {
                    val loop by vm.loop.collectAsStateWithLifecycle()
                    AlbumHeader(
                        artwork = album.artwork,
                        loop = loop,
                        title = album.title,
                        artist = album.artist,
                        details = listOfNotNull(album.year?.toString(), songs(album.songCount), length).joinToString(" • "),
                        onArtist = album.artistId?.takeIf { it.isNotEmpty() }?.let { artistId -> { onOpen(OnlineArtistRoute(artistId)) } },
                        onPlay = { vm.play(0) },
                        onShuffle = vm::shuffle,
                        // The cover stays clean. The plus adds the album to the
                        // library; for an album partly there, a note says how
                        // much of it is.
                        more = if (found.songs.any { isFind(it.id) }) {
                            {
                                val adopted = LocalAdoptedFinds.current
                                val note = albumLibraryNote(found.songs.size, found.songs.count { isOutsideLibrary(it.id, adopted) })
                                QuietActions {
                                    QuietAction(
                                        OctoIcons.AddToLibrary,
                                        if (downloading) "Adding" else "Add to your library",
                                        onClick = vm::download,
                                        enabled = !downloading,
                                    )
                                    if (note != null) {
                                        Spacer(Modifier.weight(1f))
                                        Text(
                                            note,
                                            style = OctoType.caption,
                                            color = OctoColors.TextMuted,
                                            maxLines = 1,
                                            modifier = Modifier.padding(horizontal = 10.dp),
                                        )
                                    }
                                }
                            }
                        } else {
                            null
                        },
                    )
                }
                // Songs found online have no track numbers, so every song is
                // numbered by where it sits on the album. As on a library
                // album, whether each song is in the library is said beside
                // its number, so the rows run to the edge of the screen and
                // no space is kept empty at their end.
                val mixed = found.songs.any { isFind(it.id) }
                itemsIndexed(found.songs, key = { _, track -> track.id }) { index, track ->
                    // Only say who is singing when it is not the album's artist.
                    SongRow(
                        track,
                        SongLead.Number(index + 1),
                        subtitle = { it.artist.takeIf { artist -> artist != album.artist } },
                        ownership = mixed,
                        highlight = track.id == highlight,
                    ) { vm.play(index) }
                }
            }
        }
        BackButton(onBack)
    }
}
