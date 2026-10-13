package app.winters.octo.ui.playlist

import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.flow.flowOn
import app.winters.octo.catalog.mosaicCovers
import app.winters.octo.covers.playlistGlyph
import app.winters.octo.livelists.LiveListSongs
import app.winters.octo.ui.common.phonePlaylistFooter
import app.winters.octo.ui.common.PlaylistArtwork
import android.net.Uri
import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.activity.result.contract.ActivityResultContracts
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.lazy.rememberLazyListState
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.unit.dp
import androidx.hilt.lifecycle.viewmodel.compose.hiltViewModel
import androidx.lifecycle.ViewModel
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import androidx.lifecycle.viewModelScope
import androidx.navigation3.runtime.NavKey
import app.winters.octo.catalog.PlaylistSummary
import app.winters.octo.livelists.LiveList
import app.winters.octo.livelists.LiveListStore
import app.winters.octo.playback.PlaylistStore
import app.winters.octo.playlists.PlaylistFiles
import app.winters.octo.sort.SortList
import app.winters.octo.sort.SortOrder
import app.winters.octo.sort.SortSettings
import app.winters.octo.sort.Sorted
import app.winters.octo.sort.sortPlaylists
import app.winters.octo.ui.common.BackButton
import app.winters.octo.ui.common.DetailTopGap
import app.winters.octo.ui.common.Refreshable
import app.winters.octo.ui.common.SortButton
import app.winters.octo.ui.common.TitleWithSort
import app.winters.octo.ui.common.TopOnNewOrder
import app.winters.octo.ui.common.screenPadding
import app.winters.octo.ui.common.songs
import app.winters.octo.ui.common.sortedRows
import app.winters.octo.ui.livelists.LiveListLine
import app.winters.octo.ui.livelists.NewLiveListLine
import app.winters.octo.ui.menu.CollectionTarget
import app.winters.octo.ui.menu.LocalSongMenu
import app.winters.octo.ui.nav.LiveListEditRoute
import app.winters.octo.ui.nav.LiveListRoute
import app.winters.octo.ui.nav.PlaylistRoute
import dagger.hilt.android.lifecycle.HiltViewModel
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.SharingStarted
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.combine
import kotlinx.coroutines.flow.stateIn
import kotlinx.coroutines.launch
import javax.inject.Inject
import android.util.Log
import app.winters.octo.discovery.Discovery
import app.winters.octo.discovery.Station
import app.winters.octo.home.answered
import app.winters.octo.lists.OctoListGroup
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.flow.collectLatest
import kotlinx.coroutines.withContext

@HiltViewModel
class PlaylistsViewModel @Inject constructor(
    store: PlaylistStore,
    private val files: PlaylistFiles,
    private val sorting: SortSettings,
    liveListStore: LiveListStore,
    liveSongs: LiveListSongs,
    private val discovery: Discovery,
    private val keptOcto: KeptOctoListsFiles,
) : ViewModel() {
    // The live lists, in the order they were made, above the playlists.
    val liveLists: StateFlow<List<LiveList>> =
        liveListStore.lists.stateIn(viewModelScope, SharingStarted.WhileSubscribed(5_000), emptyList())

    // The covers of each live list's first albums, by its id, for its picture.
    val liveCovers: StateFlow<Map<String, List<String>>> =
        combine(liveListStore.lists, liveSongs.library) { lists, library ->
            lists.associate { list -> list.id to mosaicCovers(library.pick(list.query).map { it.albumId to it.artwork }) }
        }.flowOn(Dispatchers.Default).stateIn(viewModelScope, SharingStarted.WhileSubscribed(5_000), emptyMap())

    // The playlists in the chosen order. There are few, so they sort here.
    val playlists: StateFlow<Sorted<PlaylistSummary>?> =
        combine(store.playlists, sorting.order(SortList.Playlists)) { list, order -> Sorted(sortPlaylists(list, order), order, null) }
            .stateIn(viewModelScope, SharingStarted.WhileSubscribed(5_000), null)

    // The lists an Octo server made for the listener, by group, as it last
    // gave them and then as it gives them now; none on any other server.
    private val _octoLists = MutableStateFlow<List<Pair<OctoListGroup, List<Station>>>>(emptyList())
    val octoLists: StateFlow<List<Pair<OctoListGroup, List<Station>>>> = _octoLists

    // How the last playlist file import went, shown until the page closes.
    private val _importState = MutableStateFlow<ImportState?>(null)
    val importState: StateFlow<ImportState?> = _importState

    init {
        // A playlist deleted on another device leaves the list, and one
        // made there comes in, without waiting for the next library copy.
        store.freshen()
        // A list found gone on its own page leaves this one too.
        viewModelScope.launch {
            discovery.gone.collect { id ->
                _octoLists.value = _octoLists.value.map { (group, lists) -> group to lists.filterNot { it.id == id } }.filter { it.second.isNotEmpty() }
            }
        }
        viewModelScope.launch {
            discovery.stationsFrom.collectLatest { server ->
                if (server == null) {
                    _octoLists.value = emptyList()
                    return@collectLatest
                }
                withContext(Dispatchers.IO) { keptOcto.store.read(server) }?.let { _octoLists.value = answered(_octoLists.value, it.read()) }
                try {
                    val got = withContext(Dispatchers.IO) { discovery.octoLists() }
                    _octoLists.value = answered(_octoLists.value, got)
                    withContext(Dispatchers.IO) { keptOcto.store.write(server, KeptOctoLists.of(got)) }
                } catch (e: CancellationException) {
                    throw e
                } catch (e: Exception) {
                    Log.w("Octo", "Octo lists failed to load: ${e.javaClass.simpleName}")
                }
            }
        }
    }

    fun setOrder(order: SortOrder) {
        viewModelScope.launch { sorting.set(SortList.Playlists, order) }
    }

    fun importFile(uri: Uri) {
        _importState.value = ImportState.Working
        viewModelScope.launch {
            _importState.value = files.import(uri)?.let(ImportState::Done) ?: ImportState.Failed
        }
    }
}

// The lines above the playlists, in order.
enum class PlaylistsLead(val key: String) {
    New("new"),
    NewLive("new-live"),
    Import("import"),
    ImportNote("import-note"),
}

// The lead lines to show: making a playlist or a live list, importing, then
// how the last import went while there is one. Liked songs is not here;
// hearted songs live on the Favourites page.
fun playlistsLead(importNote: Boolean): List<PlaylistsLead> =
    PlaylistsLead.entries.filter { it != PlaylistsLead.ImportNote || importNote }

// Every playlist: ways to make or import one, then the listener's own and
// the server's in the chosen order, the one changed last at the top to
// begin with, then the lists Octo made, by kind.
@Composable
fun PlaylistsScreen(onOpen: (NavKey) -> Unit, onBack: () -> Unit, vm: PlaylistsViewModel = hiltViewModel()) {
    val playlists by vm.playlists.collectAsStateWithLifecycle()
    val importState by vm.importState.collectAsStateWithLifecycle()
    val liveLists by vm.liveLists.collectAsStateWithLifecycle()
    val liveCovers by vm.liveCovers.collectAsStateWithLifecycle()
    val octoLists by vm.octoLists.collectAsStateWithLifecycle()
    val sheets = LocalPlaylistSheets.current
    val menus = LocalSongMenu.current.collections
    val pickFile = rememberLauncherForActivityResult(ActivityResultContracts.OpenDocument()) { uri -> uri?.let(vm::importFile) }

    val state = rememberLazyListState()
    playlists?.let { TopOnNewOrder(it.order, state) }

    Refreshable {
        LazyColumn(Modifier.fillMaxSize(), state = state, contentPadding = screenPadding(extraTop = DetailTopGap)) {
            item(key = "title") {
                TitleWithSort("Playlists") {
                    playlists?.let { sorted -> SortButton(SortList.Playlists, sorted.order, vm::setOrder) }
                }
            }
            playlistsLead(importNote = importState != null).forEach { lead ->
                item(key = lead.key) {
                    when (lead) {
                        PlaylistsLead.New -> NewPlaylistLine { sheets.show(PlaylistSheet.Create()) }
                        PlaylistsLead.NewLive -> NewLiveListLine { onOpen(LiveListEditRoute()) }
                        PlaylistsLead.Import -> ImportPlaylistLine { pickFile.launch(PlaylistFileTypes) }
                        PlaylistsLead.ImportNote -> importState?.let { ImportNote(it) }
                    }
                }
            }
            items(liveLists, key = { "live:${it.id}" }) { list ->
                LiveListLine(list, liveCovers[list.id].orEmpty(), onClick = { onOpen(LiveListRoute(list.id)) }, onLongClick = { sheets.show(PlaylistSheet.LiveOptions(list.id, list.name)) })
            }
            sortedRows(playlists?.items.orEmpty(), key = { it.id }) { playlist ->
                PlaylistLine(
                    playlist.name,
                    songs(playlist.songCount),
                    onClick = { onOpen(PlaylistRoute(playlist.id)) },
                    onServer = playlist.onServer,
                    onLongClick = { menus.open(CollectionTarget.Playlist(playlist.id)) },
                ) {
                    PlaylistArtwork(playlist.id, playlist.name, playlist.covers, 56.dp, footer = phonePlaylistFooter(playlist.songCount), glyph = playlistGlyph(playlist.octoNotice, null)) {
                        PlaylistCover(playlist.covers, 56.dp)
                    }
                }
            }
            octoListRows(octoLists, onOpen)
        }
        BackButton(onBack)
    }
}
