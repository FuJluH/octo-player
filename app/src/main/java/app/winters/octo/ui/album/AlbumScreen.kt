package app.winters.octo.ui.album

import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.remember
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import androidx.hilt.lifecycle.viewmodel.compose.hiltViewModel
import androidx.lifecycle.ViewModel
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import androidx.lifecycle.viewModelScope
import androidx.navigation3.runtime.NavKey
import app.winters.octo.ambient.PageArtwork
import app.winters.octo.animated.AnimatedArts
import app.winters.octo.animated.LocalPlayerCovers
import app.winters.octo.animated.LoopVideo
import app.winters.octo.animated.rememberLoopPlay
import app.winters.octo.subsonic.AnimatedClip
import androidx.compose.foundation.layout.size
import androidx.compose.ui.draw.clip
import androidx.compose.ui.layout.ContentScale
import coil3.compose.AsyncImage
import app.winters.octo.catalog.AlbumEntity
import app.winters.octo.catalog.CatalogDao
import app.winters.octo.catalog.TrackEntity
import app.winters.octo.catalog.isFind
import app.winters.octo.discovery.ONLY_MY_SONGS
import app.winters.octo.player.PlayerSettings
import app.winters.octo.design.OctoColors
import app.winters.octo.design.OctoIcons
import app.winters.octo.design.OctoType
import app.winters.octo.design.artworkRim
import app.winters.octo.design.elevation3
import app.winters.octo.data.ServerDownloads
import app.winters.octo.discovery.Discovery
import app.winters.octo.discovery.TopSongsSource
import app.winters.octo.discovery.albumHighlight
import app.winters.octo.discovery.DownloadState
import app.winters.octo.discovery.Downloads
import app.winters.octo.discovery.wholeAlbum
import app.winters.octo.listening.FavouriteKind
import app.winters.octo.playback.PlaybackConnection
import app.winters.octo.ui.common.Artwork
import app.winters.octo.ui.common.BackButton
import app.winters.octo.ui.common.CHECK_SETTLE_MS
import app.winters.octo.ui.common.DetailTopGap
import app.winters.octo.ui.common.FavouriteHeart
import app.winters.octo.ui.common.LocalAdoptedFinds
import app.winters.octo.ui.common.Pickable
import app.winters.octo.ui.common.PlayRow
import app.winters.octo.ui.common.QuietAction
import app.winters.octo.ui.common.QuietActions
import app.winters.octo.ui.common.Refreshable
import app.winters.octo.ui.common.SelectableSongs
import app.winters.octo.ui.common.SongLead
import app.winters.octo.ui.common.SongRow
import app.winters.octo.ui.common.addMissingLabel
import app.winters.octo.ui.common.albumLibraryNote
import app.winters.octo.ui.common.asLength
import app.winters.octo.ui.common.isOutsideLibrary
import app.winters.octo.ui.common.screenPadding
import app.winters.octo.ui.common.songs
import app.winters.octo.ui.menu.SongMenuContext
import app.winters.octo.ui.nav.AlbumRoute
import app.winters.octo.ui.nav.ArtistRoute
import app.winters.octo.ui.nav.GenreRoute
import app.winters.octo.subsonic.SubsonicException
import dagger.assisted.Assisted
import dagger.assisted.AssistedFactory
import dagger.assisted.AssistedInject
import dagger.hilt.android.lifecycle.HiltViewModel
import kotlinx.coroutines.ExperimentalCoroutinesApi
import kotlinx.coroutines.delay
import kotlinx.coroutines.flow.SharingStarted
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.collectLatest
import kotlinx.coroutines.flow.combine
import kotlinx.coroutines.flow.distinctUntilChanged
import kotlinx.coroutines.flow.drop
import kotlinx.coroutines.flow.first
import kotlinx.coroutines.flow.flatMapLatest
import kotlinx.coroutines.flow.flowOf
import kotlinx.coroutines.flow.filter
import kotlinx.coroutines.flow.map
import kotlinx.coroutines.flow.mapLatest
import kotlinx.coroutines.flow.stateIn
import kotlinx.coroutines.launch

@HiltViewModel(assistedFactory = AlbumViewModel.Factory::class)
class AlbumViewModel @AssistedInject constructor(
    @Assisted private val id: String,
    dao: CatalogDao,
    private val playback: PlaybackConnection,
    private val discovery: Discovery,
    private val downloads: Downloads,
    private val topSongs: TopSongsSource,
    private val serverDownloads: ServerDownloads,
    player: PlayerSettings,
    animatedArts: AnimatedArts,
) : ViewModel() {
    val album: StateFlow<AlbumEntity?> =
        dao.album(id).stateIn(viewModelScope, SharingStarted.WhileSubscribed(5_000), null)

    // The album's songs in the library.
    val library: StateFlow<List<TrackEntity>> =
        dao.albumTracks(id).stateIn(viewModelScope, SharingStarted.WhileSubscribed(5_000), emptyList())

    // The album's square loop from its server, in place of its cover.
    @OptIn(ExperimentalCoroutinesApi::class)
    val loop: StateFlow<AnimatedClip?> = animatedArts.pageLoop(
        library.map { songs -> songs.map(TrackEntity::id) }
            .filter { it.isNotEmpty() }
            .distinctUntilChanged()
            .mapLatest { animatedArts.serverAlbumOf(it) },
    ).stateIn(viewModelScope, SharingStarted.WhileSubscribed(5_000), null)

    // The album as the server lists it, once asked: an Octo server lists the
    // songs the library lacks too. Empty until then, or when it cannot say.
    private val server = MutableStateFlow<List<TrackEntity>>(emptyList())

    // The album whole: the library's songs, and in their places the songs
    // found online, which play through the server and can be added.
    val whole: StateFlow<List<TrackEntity>> = combine(library, server, downloads.adoptions) { library, server, adoptions ->
        wholeAlbum(library, server, adoptions.orEmpty())
    }.stateIn(viewModelScope, SharingStarted.WhileSubscribed(5_000), emptyList())

    // Whether songs found online are left out everywhere, by the setting.
    val libraryOnly: StateFlow<Boolean> =
        player.prefs.map { it.libraryOnly }.stateIn(viewModelScope, SharingStarted.WhileSubscribed(5_000), false)

    // This page's own "Only my songs", for while it is open.
    private val onlyMine = MutableStateFlow(false)
    val ownOnly: StateFlow<Boolean> = onlyMine

    fun setOnlyMine(on: Boolean) {
        onlyMine.value = on
    }

    // The songs the page lists and plays: the album whole, or only the
    // library's songs when either switch says so. Play and shuffle count
    // in this list, so a row plays itself.
    val tracks: StateFlow<List<TrackEntity>> = combine(whole, libraryOnly, onlyMine) { all, everywhere, here ->
        albumSongsShown(all, everywhere || here)
    }.stateIn(viewModelScope, SharingStarted.WhileSubscribed(5_000), emptyList())

    // How each song asked for is getting on.
    val downloadStates: StateFlow<Map<String, DownloadState>> = downloads.states

    // The album's main song, starred as Apple Music does: the one first in
    // the artist's top songs on the server. None until known, or when no song
    // here is among them.
    @OptIn(ExperimentalCoroutinesApi::class)
    val highlight: StateFlow<String?> = album.map { it?.artist }.distinctUntilChanged()
        .flatMapLatest { artist -> if (artist == null) flowOf(emptyList()) else flowOf(topSongs.forArtist(artist)) }
        .combine(tracks) { ranked, tracks -> albumHighlight(tracks, ranked) }
        .stateIn(viewModelScope, SharingStarted.WhileSubscribed(5_000), null)

    init {
        // Asked once the library's songs are known, then again when a song
        // from here arrives in the library, once its check has landed.
        viewModelScope.launch {
            askServer(library.first { it.isNotEmpty() })
            downloads.arrived.drop(1).collectLatest {
                delay(CHECK_SETTLE_MS)
                if (server.value.any { isFind(it.id) }) askServer(library.value)
            }
        }
    }

    private suspend fun askServer(songs: List<TrackEntity>) {
        try {
            discovery.libraryAlbum(songs.map { it.id })?.let { server.value = it }
        } catch (e: SubsonicException) {
            // Offline or refused: the library's songs are the album for now.
        }
    }

    // Has the server add every song here it lacks and not yet asked for.
    fun addMissing() {
        val waiting = whole.value.filter { isFind(it.id) && downloads.state(it.id) == DownloadState.None }
        viewModelScope.launch { waiting.forEach { downloads.request(it) } }
    }

    // Whether the server keeps a downloads list the sheet can show.
    val canFollow: StateFlow<Boolean> = serverDownloads.supported

    // The server downloads sheet, on its list, to follow the songs on their way.
    fun showDownloads() {
        if (!serverDownloads.supported.value) return
        serverDownloads.showList()
        serverDownloads.open()
    }

    // The artist's other albums, for the foot of the page.
    @OptIn(ExperimentalCoroutinesApi::class)
    val moreByArtist: StateFlow<List<AlbumEntity>> = dao.album(id)
        .map { it?.artistId }
        .distinctUntilChanged()
        .flatMapLatest { artistId -> if (artistId == null) flowOf(emptyList()) else dao.artistAlbums(artistId) }
        .map { albums -> albums.filter { it.id != id } }
        .stateIn(viewModelScope, SharingStarted.WhileSubscribed(5_000), emptyList())

    // Plays the album from one of its songs.
    fun play(index: Int) = playback.playTracks(tracks.value.map { it.id }, index, source = album.value?.title)

    // Shuffles the album whole, songs found online too, when it has any.
    fun shuffle() {
        val all = tracks.value
        if (all.any { isFind(it.id) }) playback.playTracks(all.map { it.id }, shuffle = true, source = album.value?.title) else playback.playAlbum(id, shuffle = true)
    }

    @AssistedFactory
    interface Factory {
        fun create(id: String): AlbumViewModel
    }
}

private val CoverShape = RoundedCornerShape(10.dp)
private val CoverSide = 240.dp

@Composable
fun AlbumScreen(
    id: String,
    onOpen: (NavKey) -> Unit,
    onBack: () -> Unit,
    vm: AlbumViewModel = hiltViewModel<AlbumViewModel, AlbumViewModel.Factory> { it.create(id) },
) {
    val album by vm.album.collectAsStateWithLifecycle()
    val tracks by vm.tracks.collectAsStateWithLifecycle()
    val whole by vm.whole.collectAsStateWithLifecycle()
    val libraryOnly by vm.libraryOnly.collectAsStateWithLifecycle()
    val ownOnly by vm.ownOnly.collectAsStateWithLifecycle()
    val library by vm.library.collectAsStateWithLifecycle()
    val states by vm.downloadStates.collectAsStateWithLifecycle()
    // Whether the album lists songs found online, so every row says which
    // songs are in the library; `missing` whether it has any, shown or not.
    val mixed = tracks.any { isFind(it.id) }
    val missing = whole.any { isFind(it.id) }
    val moreByArtist by vm.moreByArtist.collectAsStateWithLifecycle()
    val highlight by vm.highlight.collectAsStateWithLifecycle()
    val loop by vm.loop.collectAsStateWithLifecycle()
    PageArtwork(AlbumRoute(id), album?.artwork)

    val pickable = remember(tracks) { tracks.map { Pickable(it.id, it) } }
    // Its songs' menus leave out the way back to this page.
    val menuContext = remember(id) { SongMenuContext(albumId = id) }

    Refreshable {
        SelectableSongs(pickable) {
            LazyColumn(Modifier.fillMaxSize(), contentPadding = screenPadding(extraTop = DetailTopGap)) {
                album?.let { a ->
                    item(key = "header") {
                        AlbumHeader(
                            artwork = a.artwork,
                            loop = loop,
                            title = a.title,
                            artist = a.artist,
                            details = listOfNotNull(
                                a.year?.toString(),
                                songs(if (mixed) tracks.size else a.songCount),
                                (if (mixed) (tracks.sumOf { it.durationMs } / 1000).toInt() else (a.durationMs / 1000).toInt()).asLength(),
                            ).joinToString(" • "),
                            onArtist = { onOpen(ArtistRoute(a.artistId)) },
                            onPlay = { vm.play(0) },
                            onShuffle = vm::shuffle,
                            // Favourites: the heart beside the buttons.
                            heart = { FavouriteHeart(FavouriteKind.Album, id) },
                            more = {
                                QuietActions {
                                    AlbumShareButton(id, a.title)
                                    AlbumDownloadButton(library)
                                }
                                val canFollow by vm.canFollow.collectAsStateWithLifecycle()
                                if (missing) {
                                    MissingSongs(
                                        whole,
                                        states,
                                        vm::addMissing,
                                        if (canFollow) vm::showDownloads else null,
                                        // The setting already leaves them out; the toggle is for this album alone.
                                        onlyMine = if (libraryOnly) null else ownOnly,
                                        onOnlyMine = { vm.setOnlyMine(!ownOnly) },
                                    )
                                }
                            },
                        )
                    }
                }
                // The genre and the songs' average rating, when known.
                val genre = albumGenre(library)
                val average = averageRating(library)
                if (album != null && (genre != null || average != null)) {
                    item(key = "about") { AlbumAbout(genre, average) { onOpen(GenreRoute(it)) } }
                }
                val discs = tracks.groupBy { it.discNo ?: 1 }
                discs.forEach { (disc, onDisc) ->
                    if (discs.size > 1) {
                        item(key = "disc:$disc") {
                            Text(
                                "Disc $disc",
                                style = OctoType.caption.copy(fontWeight = FontWeight.Bold),
                                color = OctoColors.TextMuted,
                                modifier = Modifier.padding(start = 20.dp, top = 16.dp, bottom = 4.dp),
                            )
                        }
                    }
                    items(onDisc, key = { it.id }) { track ->
                        // Only say who is singing when it is not the album's artist.
                        // In an album mixing in songs found online, each row
                        // says after its number whether the song is in the
                        // library, as the desktop's album does.
                        SongRow(
                            track,
                            SongLead.Number(track.trackNo),
                            subtitle = { it.artist.takeIf { artist -> artist != album?.artist } },
                            menuContext = menuContext,
                            ownership = mixed,
                            highlight = track.id == highlight,
                        ) { vm.play(tracks.indexOf(track)) }
                    }
                }
                album?.let { a ->
                    if (moreByArtist.isNotEmpty()) {
                        item(key = "more-by-artist") { MoreByArtist(a.artist, moreByArtist, onOpen) }
                    }
                }
            }
        }
        BackButton(onBack)
    }
}

// Under an album that has only some of its songs in the library: how many
// are in, and the plus that adds the rest (each one not asked for yet).
// Once they are all on their way, it opens the downloads sheet instead.
// "Only my songs" (`onlyMine`, when offered) hides the rest on this page.
@Composable
private fun MissingSongs(
    tracks: List<TrackEntity>,
    states: Map<String, DownloadState>,
    onAdd: () -> Unit,
    onFollow: (() -> Unit)?,
    onlyMine: Boolean? = null,
    onOnlyMine: () -> Unit = {},
) {
    val adopted = LocalAdoptedFinds.current
    val outside = tracks.count { isOutsideLibrary(it.id, adopted) }
    val askable = tracks.count { isFind(it.id) && (states[it.id] ?: DownloadState.None) == DownloadState.None }
    val note = albumLibraryNote(tracks.size, outside)
    val coming = tracks.count { isFind(it.id) && states[it.id] == DownloadState.Requested }
    val follows = askable == 0 && coming > 0 && onFollow != null
    QuietActions {
        QuietAction(
            OctoIcons.AddToLibrary,
            if (askable > 0) addMissingLabel(askable) else if (follows) "Adding, show downloads" else "Adding",
            onClick = { if (follows) onFollow?.invoke() else onAdd() },
            enabled = askable > 0 || follows,
        )
        if (onlyMine != null) QuietAction(OctoIcons.Library, ONLY_MY_SONGS, onOnlyMine, checked = onlyMine)
        if (note != null) {
            Text(
                note,
                style = OctoType.caption,
                color = OctoColors.TextMuted,
                maxLines = 1,
                overflow = TextOverflow.Ellipsis,
                textAlign = TextAlign.End,
                modifier = Modifier.weight(1f).padding(horizontal = 10.dp),
            )
        }
    }
}

// The top of an album page: cover, title and artist, then a quiet line with
// the details on the left and the heart on the right, and Play and Shuffle
// under it. The artist opens only when there is somewhere to go. `heart`
// sits on the details line and `more` under the buttons, for quieter actions.
// An album with animated art plays its square `loop` in place of the cover
// while the page is in front.
@Composable
fun AlbumHeader(
    artwork: String?,
    title: String,
    artist: String,
    details: String,
    onArtist: (() -> Unit)?,
    onPlay: () -> Unit,
    onShuffle: () -> Unit,
    heart: (@Composable () -> Unit)? = null,
    more: (@Composable () -> Unit)? = null,
    loop: AnimatedClip? = null,
) {
    Column(Modifier.fillMaxWidth().padding(bottom = 12.dp)) {
        Column(
            Modifier.fillMaxWidth().padding(horizontal = 20.dp),
            horizontalAlignment = Alignment.CenterHorizontally,
        ) {
            val play = rememberLoopPlay(inView = !LocalPlayerCovers.current)
            Box {
                LoopVideo(loop, play, Modifier.elevation3(CoverShape).size(CoverSide).clip(CoverShape)) {
                    Artwork(artwork, CoverSide, shape = CoverShape, rim = loop == null)
                    loop?.poster?.let { poster ->
                        AsyncImage(model = poster, contentDescription = null, contentScale = ContentScale.Crop, modifier = Modifier.size(CoverSide))
                    }
                }
                // One rim over the still and the loop alike.
                if (loop != null) Box(Modifier.size(CoverSide).artworkRim(CoverShape))
            }
            Spacer(Modifier.height(20.dp))
            Text(title, style = OctoType.title, color = OctoColors.TextPrimary, textAlign = TextAlign.Center)
            Text(
                artist,
                style = OctoType.body,
                color = if (onArtist != null) OctoColors.Accent else OctoColors.TextSecondary,
                modifier = Modifier
                    .padding(top = 4.dp)
                    .then(if (onArtist != null) Modifier.clickable(onClick = onArtist) else Modifier),
            )
            PlayRow(details, onPlay, onShuffle, Modifier.padding(top = 14.dp)) { heart?.invoke() }
        }
        more?.invoke()
    }
}
