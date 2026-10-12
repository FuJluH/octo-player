package app.winters.octo.ui.menu

import app.winters.octo.ui.family.REMOVE_FROM_MY_LIBRARY
import app.winters.octo.ui.family.REQUEST_A_COPY
import app.winters.octo.ui.family.SAVED
import app.winters.octo.ui.family.SAVE
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.Icon
import androidx.compose.runtime.Composable
import androidx.compose.runtime.DisposableEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.produceState
import androidx.compose.runtime.remember
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.res.painterResource
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.selected
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.unit.dp
import androidx.hilt.lifecycle.viewmodel.compose.hiltViewModel
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import androidx.navigation3.runtime.NavKey
import app.winters.octo.catalog.TrackEntity
import app.winters.octo.catalog.isFind
import app.winters.octo.design.GlassPopup
import app.winters.octo.design.OctoColors
import app.winters.octo.design.OctoIcons
import app.winters.octo.design.PopupPager
import app.winters.octo.discovery.DownloadState
import app.winters.octo.health.DELETE_FROM_DISK
import app.winters.octo.offline.DownloadStatus
import app.winters.octo.offline.Reasons
import app.winters.octo.offline.reasons
import app.winters.octo.output.OutputChoice
import app.winters.octo.ui.common.Artwork
import app.winters.octo.ui.common.GlassMenuAction
import app.winters.octo.ui.common.GlassMenuBack
import app.winters.octo.ui.common.GlassMenuGroups
import app.winters.octo.ui.common.GlassMenuHeader
import app.winters.octo.ui.common.GlassMenuPage
import app.winters.octo.ui.common.GlassMenuSeparator
import app.winters.octo.ui.common.LocalHaze
import app.winters.octo.ui.common.SelectionBarHost
import app.winters.octo.ui.common.rememberOpenedBeside
import app.winters.octo.ui.nav.AlbumRoute
import app.winters.octo.ui.nav.ArtistRoute
import app.winters.octo.ui.nav.SoundRoute
import app.winters.octo.ui.output.OutputList
import app.winters.octo.ui.output.OutputsViewModel
import app.winters.octo.ui.playlist.PlaylistPickerPage
import app.winters.octo.ui.playlist.PlaylistSheetsViewModel
import app.winters.octo.ui.server.ShareLinkPage
import app.winters.octo.ui.server.ShareRequest
import app.winters.octo.ui.upgrade.FIND_HIGHER_QUALITY
import app.winters.octo.ui.upgrade.UpgradeAsk
import dev.chrisbanes.haze.HazeState

// The song menu, a glass card that floats beside the row held or the button
// tapped, over everything, the player included. Adding to a playlist,
// sharing, rating, the song's info and, from the player, the places to play
// open as its next pages, with a way back. `onOpen` goes to a page, and is
// expected to close the player if it is open. `backdrop` is what the card
// frosts: the player while it is open.
@Composable
fun SongMenuHost(
    state: SongMenuState,
    onOpen: (NavKey) -> Unit,
    backdrop: HazeState = LocalHaze.current,
    vm: SongMenuViewModel = hiltViewModel(),
    sheets: PlaylistSheetsViewModel = hiltViewModel(),
) {
    // Rows swipe and speak through these while the host is shown.
    DisposableEffect(state, vm) {
        state.quick = object : QuickSongActions {
            override fun playNext(trackId: String) = vm.playNextUndoable(trackId)
            override fun addToQueue(trackId: String) = vm.playLast(trackId)
        }
        onDispose { state.quick = null }
    }
    val phoneFiles = rememberPhoneFiles()
    // Over the bottom bar and under every menu, as the bar it stands in for.
    SelectionBarHost(state.selectionBar, phoneFiles)
    val open = state.trackId != null
    GlassPopup(
        visible = open,
        anchor = rememberOpenedBeside(open),
        onDismiss = state::close,
        backdrop = backdrop,
        title = "Song menu",
        onBack = state.pages::back,
    ) {
        val trackId = state.lastTrackId ?: return@GlassPopup
        val track by remember(trackId) { vm.track(trackId) }.collectAsStateWithLifecycle(null)
        val song = track ?: return@GlassPopup
        val sharing by vm.sharing.collectAsStateWithLifecycle()
        val shareId by produceState<String?>(null, trackId, sharing) { value = if (sharing) vm.shareId(trackId) else null }
        val back: () -> Unit = { state.pages.back() }
        PopupPager(state.pages) { page, _ ->
            when (page) {
                SongPage.Actions -> SongActionsPage(state, song, shareId, vm, phoneFiles, onOpen, sheets)
                SongPage.AddToPlaylist -> PlaylistPickerPage(listOf(trackId), onBack = back, onDone = state::close, vm = sheets)
                SongPage.AddToLastPlaylist -> {
                    val recent by sheets.recentIds.collectAsStateWithLifecycle()
                    PlaylistPickerPage(listOf(trackId), onBack = back, onDone = state::close, vm = sheets, start = recent.firstOrNull())
                }
                SongPage.Rate -> RatePage(song, vm, onBack = back)
                SongPage.Share -> shareId?.let { id ->
                    val request = remember(id, song.title) { ShareRequest(listOf(id), song.title) }
                    ShareLinkPage(request, onBack = back, onDone = state::close)
                }
                SongPage.Info -> SongInfoPage(trackId, onBack = back)
                SongPage.DeleteFromDisk -> {
                    val keepDays by vm.keepDays.collectAsStateWithLifecycle()
                    DiskDeleteQuestion(1, song.title, keepDays, onCancel = back) {
                        vm.deleteFromDisk(song)
                        state.close()
                    }
                }
                SongPage.Cast -> CastPage(onBack = back, onDone = state::close)
            }
        }
    }
    CollectionMenuHost(state.collections, onOpen, backdrop)
}

// The song at the top, then its actions in their groups.
@Composable
private fun SongActionsPage(
    state: SongMenuState,
    song: TrackEntity,
    shareId: String?,
    vm: SongMenuViewModel,
    phoneFiles: PhoneFileActions,
    onOpen: (NavKey) -> Unit,
    sheets: PlaylistSheetsViewModel,
) {
    val trackId = song.id
    // The playlist added to last, while it is still there.
    val playlists by sheets.playlists.collectAsStateWithLifecycle()
    val recent by sheets.recentIds.collectAsStateWithLifecycle()
    val last = recent.firstOrNull()?.let { id -> playlists.firstOrNull { it.id == id } }
    val context = state.lastContext
    val liked by vm.liked.collectAsStateWithLifecycle()
    val downloads by vm.downloadStates.collectAsStateWithLifecycle()
    val kept by vm.kept.collectAsStateWithLifecycle()
    val radio by vm.radio.collectAsStateWithLifecycle()
    val canUpgrade by vm.canUpgrade.collectAsStateWithLifecycle()
    val canFindSongs by vm.canFindSongs.collectAsStateWithLifecycle()
    val upgradable by produceState(emptyList<UpgradeAsk>(), trackId, canUpgrade) { value = if (canUpgrade) vm.upgradable(trackId) else emptyList() }
    val canRemove by vm.canRemove.collectAsStateWithLifecycle()
    val onDisk by produceState(false, trackId, canRemove) { value = canRemove && vm.deletable(trackId) }
    val removesFromMine = vm.family.removesFromMine
    val inMine by produceState(false, trackId, removesFromMine) { value = removesFromMine && vm.removableFromMine(trackId) }
    val isLiked = trackId in liked
    val keptRow = kept[trackId]
    val byHand = keptRow?.reasons?.contains(Reasons.MANUAL) == true
    val place = menuPlace(context, song.albumId, song.artistId)
    val phone = song.onPhone && !isFind(trackId)
    val actions = songActions(
        isFind(trackId),
        radio,
        share = shareId != null,
        offline = !song.onPhone || keptRow != null,
        place = place,
        phone = phone,
        lastPlaylist = last != null,
        upgrade = upgradable.isNotEmpty(),
        findSongs = canFindSongs,
        disk = onDisk,
        requestCopy = vm.family.outside.offersRequest,
        removeFromMine = inMine,
    )
    // A family member whose songs are saved rather than added.
    val saves = vm.family.outside.addLabel != null

    GlassMenuPage(
        header = {
            SongHeader(song)
            GlassMenuSeparator()
        },
    ) {
        GlassMenuGroups(songMenuGroups(actions)) { action ->
            when (action) {
                SongAction.PlayNext -> GlassMenuAction(OctoIcons.PlayNext, "Play next", onClick = {
                    vm.playNext(trackId)
                    state.close()
                })
                SongAction.AddToQueue -> GlassMenuAction(OctoIcons.AddToQueue, "Add to queue", onClick = {
                    vm.playLast(trackId)
                    state.close()
                })
                SongAction.StartRadio -> GlassMenuAction(OctoIcons.Radio, "Start radio", onClick = {
                    state.close()
                    vm.startRadio(song)
                })
                SongAction.Download -> if (saves) {
                    val saved = vm.family.isSaved(trackId)
                    GlassMenuAction(if (saved) OctoIcons.Liked else OctoIcons.Like, if (saved) "Remove from $SAVED" else SAVE, onClick = {
                        state.close()
                        vm.family.toggleSaved(trackId, song.title)
                    })
                } else {
                    val download = downloads[trackId] ?: DownloadState.None
                    val icon = when (download) {
                        DownloadState.None, DownloadState.Requested -> OctoIcons.AddToLibrary
                        DownloadState.Done -> OctoIcons.Check
                    }
                    GlassMenuAction(icon, downloadLabel(download), enabled = download == DownloadState.None, onClick = { vm.download(song) })
                }
                SongAction.RequestCopy -> GlassMenuAction(OctoIcons.Download, REQUEST_A_COPY, opensPage = true, onClick = {
                    state.close()
                    vm.family.ask(trackId, song.title)
                })
                SongAction.RemoveFromMyLibrary -> GlassMenuAction(OctoIcons.RemoveFromPlaylist, REMOVE_FROM_MY_LIBRARY, destructive = true, onClick = {
                    state.close()
                    vm.removeFromMyLibrary(song)
                })
                SongAction.AddToLastPlaylist -> GlassMenuAction(
                    OctoIcons.AddToPlaylist,
                    "Add to last playlist: ${last?.name.orEmpty()}",
                    onClick = { state.pages.open(SongPage.AddToLastPlaylist) },
                )
                SongAction.AddToPlaylist -> GlassMenuAction(
                    OctoIcons.AddToPlaylist,
                    "Add to playlist",
                    opensPage = true,
                    onClick = { state.pages.open(SongPage.AddToPlaylist) },
                )
                SongAction.RemoveFromPlaylist -> GlassMenuAction(OctoIcons.RemoveFromPlaylist, "Remove from this playlist", onClick = {
                    state.close()
                    val playlistId = context.playlistId
                    val itemId = context.playlistItemId
                    if (playlistId != null && itemId != null) vm.removeFromPlaylist(playlistId, itemId)
                })
                SongAction.Select -> GlassMenuAction(OctoIcons.Select, "Select", onClick = {
                    state.close()
                    context.selectKey?.let { key -> context.selection?.start(key) }
                })
                SongAction.KeepOffline -> {
                    val status = keptRow?.state
                    val icon = when (status) {
                        DownloadStatus.Queued, DownloadStatus.Downloading -> OctoIcons.Downloading
                        DownloadStatus.Done -> OctoIcons.Downloaded
                        null, DownloadStatus.Failed -> OctoIcons.Download
                    }
                    GlassMenuAction(icon, keepOfflineLabel(status, byHand), enabled = keepOfflineEnabled(status, byHand), onClick = {
                        when (status) {
                            null -> vm.keepOffline(trackId)
                            DownloadStatus.Failed -> vm.retryOffline(trackId)
                            else -> vm.removeOffline(trackId)
                        }
                    })
                }
                SongAction.FindFlac -> GlassMenuAction(OctoIcons.Lossless, FIND_HIGHER_QUALITY, onClick = {
                    state.close()
                    vm.findFlac(upgradable)
                })
                SongAction.ShareFile -> GlassMenuAction(OctoIcons.ShareFile, "Share file", onClick = {
                    state.close()
                    phoneFiles.share(listOf(trackId))
                })
                SongAction.Share -> GlassMenuAction(OctoIcons.Share, "Share link", opensPage = true, onClick = { state.pages.open(SongPage.Share) })
                SongAction.Like -> GlassMenuAction(
                    if (isLiked) OctoIcons.Liked else OctoIcons.Like,
                    if (isLiked) "Remove from Liked songs" else "Add to Liked songs",
                    onClick = { vm.toggleLike(trackId) },
                )
                SongAction.Rate -> GlassMenuAction(
                    if (song.rating > 0) OctoIcons.StarFilled else OctoIcons.Star,
                    "Rate",
                    detail = starsLabel(song.rating),
                    opensPage = true,
                    onClick = { state.pages.open(SongPage.Rate) },
                )
                SongAction.GoToAlbum -> GlassMenuAction(OctoIcons.Album, "Go to album", onClick = {
                    state.close()
                    onOpen(AlbumRoute(song.albumId))
                })
                SongAction.GoToArtist -> GlassMenuAction(OctoIcons.Artist, "Go to artist", onClick = {
                    state.close()
                    onOpen(ArtistRoute(song.artistId))
                })
                SongAction.SetAsSound -> GlassMenuAction(OctoIcons.Ringtone, "Set as ringtone", onClick = {
                    state.close()
                    phoneFiles.setSound(trackId)
                })
                SongAction.DeleteFromPhone -> GlassMenuAction(OctoIcons.Delete, "Delete from phone", destructive = true, onClick = {
                    state.close()
                    phoneFiles.delete(listOf(trackId))
                })
                SongAction.DeleteFromDisk -> GlassMenuAction(OctoIcons.Delete, DELETE_FROM_DISK, destructive = true, opensPage = true, onClick = {
                    state.pages.open(SongPage.DeleteFromDisk)
                })
                SongAction.Info -> GlassMenuAction(OctoIcons.Info, "Song info", opensPage = true, onClick = { state.pages.open(SongPage.Info) })
                SongAction.FindSongs -> GlassMenuAction(OctoIcons.Search, app.winters.octo.ui.downloads.FIND_SONGS, onClick = {
                    state.close()
                    vm.findSongs(trackId, song.title)
                })
                SongAction.Cast -> CastAction(onClick = { state.pages.open(SongPage.Cast) })
                SongAction.Sound -> {
                    val equalizerOn by vm.equalizerOn.collectAsStateWithLifecycle()
                    GlassMenuAction(OctoIcons.Sound, "Sound", detail = soundDetail(equalizerOn), onClick = {
                        state.close()
                        onOpen(SoundRoute)
                    })
                }
            }
        }
    }
}

// Where the music plays: the Cast mark lights up and the device is named
// under it while casting. It leads on to the list of places to play.
@Composable
private fun CastAction(onClick: () -> Unit, outputs: OutputsViewModel = hiltViewModel()) {
    val current by outputs.current.collectAsStateWithLifecycle()
    GlassMenuAction(
        if (current is OutputChoice.Phone) OctoIcons.Cast else OctoIcons.CastConnected,
        "Cast",
        detail = castDetail(current),
        opensPage = true,
        onClick = onClick,
    )
}

// The places music can play, as the menu's next page. Choosing one closes
// the menu.
@Composable
private fun CastPage(onBack: () -> Unit, onDone: () -> Unit) {
    GlassMenuPage(header = { GlassMenuBack("Play on", onBack) }) {
        OutputList(onDone = onDone)
    }
}

// "3 stars", or nothing for a song not rated yet.
private fun starsLabel(rating: Int): String? = when {
    rating <= 0 -> null
    rating == 1 -> "1 star"
    else -> "$rating stars"
}

// The song a menu is about: small artwork, its title and artist.
@Composable
internal fun SongHeader(song: TrackEntity) {
    GlassMenuHeader(song.title, song.artist) { Artwork(song.artwork, 40.dp, shape = RoundedCornerShape(6.dp)) }
}

// Five stars for rating a song. A tap sets the rating; tapping the star it
// already has takes it off. The page stays, so the stars show what was chosen.
@Composable
private fun RatePage(song: TrackEntity, vm: SongMenuViewModel, onBack: () -> Unit) {
    GlassMenuPage(header = { GlassMenuBack("Rate", onBack) }) {
        SongHeader(song)
        Row(
            Modifier.fillMaxWidth().padding(horizontal = 8.dp),
            horizontalArrangement = Arrangement.spacedBy(2.dp, Alignment.CenterHorizontally),
        ) {
            for (star in 1..5) {
                val lit = star <= song.rating
                Box(
                    Modifier
                        .size(48.dp)
                        .clickable(interactionSource = null, indication = null, role = Role.Button) {
                            vm.rate(song.id, nextRating(song.rating, star))
                        }
                        .semantics {
                            contentDescription = if (star == 1) "1 star" else "$star stars"
                            selected = star == song.rating
                        },
                    contentAlignment = Alignment.Center,
                ) {
                    Icon(
                        painterResource(if (lit) OctoIcons.StarFilled else OctoIcons.Star),
                        contentDescription = null,
                        tint = if (lit) Color.White else OctoColors.TextMuted,
                        modifier = Modifier.size(30.dp),
                    )
                }
            }
        }
        Spacer(Modifier.height(10.dp))
    }
}

// The rating a tap on a star gives: that many stars, or none when the song
// already has exactly that many.
fun nextRating(current: Int, tapped: Int): Int = if (tapped == current) 0 else tapped
