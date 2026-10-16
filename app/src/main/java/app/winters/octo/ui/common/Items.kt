package app.winters.octo.ui.common

import androidx.compose.animation.AnimatedContent
import androidx.compose.animation.core.tween
import androidx.compose.animation.fadeIn
import androidx.compose.animation.fadeOut
import androidx.compose.animation.togetherWith
import androidx.compose.foundation.LocalIndication
import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.combinedClickable
import androidx.compose.foundation.interaction.MutableInteractionSource
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.Icon
import androidx.compose.material3.SwipeToDismissBox
import androidx.compose.material3.SwipeToDismissBoxValue
import androidx.compose.material3.Text
import androidx.compose.material3.rememberSwipeToDismissBoxState
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.composed
import androidx.compose.ui.draw.alpha
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.graphicsLayer
import androidx.compose.ui.hapticfeedback.HapticFeedback
import androidx.compose.ui.hapticfeedback.HapticFeedbackType
import androidx.compose.ui.platform.LocalHapticFeedback
import androidx.compose.ui.res.painterResource
import androidx.compose.ui.semantics.CustomAccessibilityAction
import androidx.compose.ui.semantics.customActions
import androidx.compose.ui.semantics.selected
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.dp
import app.winters.octo.catalog.AlbumEntity
import app.winters.octo.catalog.ArtistEntity
import app.winters.octo.catalog.TrackEntity
import app.winters.octo.catalog.isFind
import app.winters.octo.design.NowPlayingBars
import app.winters.octo.design.OctoColors
import app.winters.octo.design.OctoIcons
import app.winters.octo.design.OctoType
import app.winters.octo.design.SelectedRow
import app.winters.octo.design.rememberPressSqueeze
import app.winters.octo.discovery.OnlineAlbum
import app.winters.octo.discovery.OnlineArtist
import app.winters.octo.discovery.albumShareLine
import app.winters.octo.discovery.shownLengthMs
import app.winters.octo.ui.menu.CollectionTarget
import app.winters.octo.ui.menu.LocalSongMenu
import app.winters.octo.ui.menu.SongMenuContext
import kotlinx.coroutines.launch

// What TalkBack says a long press does on any card or row with a menu.
private const val MoreOptions = "More options"

private val RowShape = RoundedCornerShape(12.dp)

// How far song, artist and playlist rows sit from the screen's sides, and a
// picked row's pill closer still, so lists run near the edges.
val ListRowSide = 12.dp
val ListRowPickInset = 4.dp

// Opens the menu on a long press, with a little buzz, floating beside
// what was held. Held down, it gives a little and springs back.
private fun Modifier.pressOrHold(haptics: HapticFeedback, spot: PressSpot, onClick: () -> Unit, onLongClick: (() -> Unit)?): Modifier = composed {
    val interaction = remember { MutableInteractionSource() }
    val squeeze by rememberPressSqueeze(interaction)
    val indication = LocalIndication.current
    val squeezed = Modifier.graphicsLayer {
        scaleX = squeeze
        scaleY = squeeze
    }
    if (onLongClick == null) return@composed squeezed.clickable(interactionSource = interaction, indication = indication, onClick = onClick)
    squeezed.pressSpot(spot).combinedClickable(
        interactionSource = interaction,
        indication = indication,
        onClick = onClick,
        onLongClickLabel = MoreOptions,
        onLongClick = {
            haptics.performHapticFeedback(HapticFeedbackType.LongPress)
            onLongClick()
        },
    )
}

// An album as a picture with its name and artist under it. No card
// outline: the picture carries the edge. A long press opens its menu.
@Composable
fun AlbumCard(album: AlbumEntity, onClick: () -> Unit, modifier: Modifier = Modifier, width: Dp? = 150.dp) {
    val menus = LocalSongMenu.current.collections
    AlbumCard(album.artwork, album.title, album.artist, onClick, { menus.open(CollectionTarget.Album(album.id)) }, modifier, width, outside = false, note = null)
}

// An album on the server, not in the library, drawn the same way with the
// not-in-library mark on its cover, and, when the library holds some of
// its songs, how many.
@Composable
fun AlbumCard(album: OnlineAlbum, onClick: () -> Unit, modifier: Modifier = Modifier, width: Dp? = 150.dp) =
    AlbumCard(album.artwork, album.title, album.artist, onClick, null, modifier, width, outside = true, note = albumShareLine(album.ownedCount, album.songCount))

@Composable
private fun AlbumCard(
    artwork: String?,
    title: String,
    artist: String,
    onClick: () -> Unit,
    onLongClick: (() -> Unit)?,
    modifier: Modifier,
    width: Dp?,
    outside: Boolean,
    note: String?,
) {
    Column(
        (if (width != null) modifier.width(width) else modifier.fillMaxWidth())
            .pressOrHold(LocalHapticFeedback.current, LocalPressSpot.current, onClick, onLongClick),
    ) {
        ArtworkFill(artwork, outside = outside)
        Spacer(Modifier.height(8.dp))
        Text(
            title,
            style = OctoType.bodySmall.copy(fontWeight = FontWeight.SemiBold),
            color = OctoColors.TextPrimary,
            maxLines = 1,
            overflow = TextOverflow.Ellipsis,
        )
        Text(
            artist,
            style = OctoType.caption,
            color = OctoColors.TextMuted,
            maxLines = 1,
            overflow = TextOverflow.Ellipsis,
        )
        if (note != null) {
            Text(
                note,
                style = OctoType.caption,
                color = OctoColors.TextMuted,
                maxLines = 1,
                overflow = TextOverflow.Ellipsis,
            )
        }
    }
}

// A song as a picture with its title and artist under it, for rows of
// songs. A tap plays; a long press opens the song's menu. A song found
// online carries the not-in-library mark on its picture, and nothing more
// by its artist.
@Composable
fun SongCard(track: TrackEntity, onClick: () -> Unit) {
    val menu = LocalSongMenu.current
    Column(
        Modifier
            .width(150.dp)
            .alpha(if (LocalOfflineMarks.current.isOutOfReach(track)) OutOfReachAlpha else 1f)
            .pressOrHold(LocalHapticFeedback.current, LocalPressSpot.current, onClick) { menu.open(track.id) },
    ) {
        ArtworkFill(track.artwork, outside = isOutsideLibrary(track.id))
        Spacer(Modifier.height(8.dp))
        SongTitle(
            track.title,
            explicit = track.explicit == true,
            style = OctoType.bodySmall.copy(fontWeight = FontWeight.SemiBold),
            color = OctoColors.TextPrimary,
        )
        Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(4.dp)) {
            Text(
                track.artist,
                style = OctoType.caption,
                color = OctoColors.TextMuted,
                maxLines = 1,
                overflow = TextOverflow.Ellipsis,
                modifier = Modifier.weight(1f, fill = false),
            )
            SourceMark(track)
        }
    }
}

// Marks a song that is not on the phone, so it streams from the server,
// or anything else that lives on the server.
@Composable
internal fun CloudMark(description: String = "Streams from your server") {
    Icon(
        painterResource(OctoIcons.Cloud),
        contentDescription = description,
        tint = OctoColors.TextMuted,
        modifier = Modifier.size(14.dp),
    )
}

// What sits at the start of a song row.
sealed interface SongLead {
    data object Artwork : SongLead
    data class Number(val track: Int?) : SongLead

    // A place in a ranking, then the artwork.
    data class Ranked(val rank: Int) : SongLead
}

// The album a row names. A song found online often has its own title for
// an album, which says nothing new, so that is left off.
fun rowAlbum(track: TrackEntity): String =
    track.album.takeUnless { isFind(track.id) && it.trim().equals(track.title.trim(), ignoreCase = true) }.orEmpty()

// "Artist • Album" under a song's title.
fun songSubtitle(track: TrackEntity): String =
    listOf(track.artist, rowAlbum(track)).filter { it.isNotEmpty() }.joinToString(" • ")

// How wide the add button is in a row, and its plus.
private val AddButtonSize = 40.dp
private val AddIconSize = 22.dp

// The column just after a song's number, in a list mixing library songs
// with songs found online: a lit check for a song in the library, the add
// button for one that is not, which turns into the check once it is in.
private val OwnershipWidth = 32.dp

@Composable
private fun OwnershipMark(track: TrackEntity) {
    Box(Modifier.width(OwnershipWidth), contentAlignment = Alignment.Center) {
        if (isOutsideLibrary(track.id)) {
            AddToLibraryButton(track, size = OwnershipWidth, iconSize = 20.dp)
        } else {
            Icon(
                painterResource(OctoIcons.Check),
                contentDescription = "In your library",
                tint = OctoColors.Accent,
                modifier = Modifier.size(20.dp),
            )
        }
    }
}

// A song line; tapping it plays it. `subtitle` is the line under the title,
// for the song the row shows. `trailing` goes after the length, such as a
// drag handle. `menuContext` says what page the row is on, for its menu. In
// a list that picks songs, `selectKey` is the row's key; a tap then picks it
// instead. A swipe right puts it next in the queue, on lists where a swipe
// does nothing else (`swipeToPlayNext`).
// A song found online that is not in the library carries a small plus on
// its artwork. In a list that offers adding (`offerAdd`), it gets the add
// button at the end instead, and the row says it once. A library song in
// such a list keeps that space empty, so the lengths line up, unless the
// list's library songs end at their length (`librarySpace` false).
// Once a find is in the library, its row becomes the library song's row in
// place: after the check has its moment when that happens in view, or
// straight away when it already had. The swipe and the menu are then the
// library song's, and so is what plays. With `ownership`, every row has a
// mark just after its number instead: a check for a library song, the add
// button for a find (an album with songs found online).
@Composable
fun SongRow(
    track: TrackEntity,
    lead: SongLead = SongLead.Artwork,
    subtitle: (TrackEntity) -> String? = ::songSubtitle,
    trailing: (@Composable () -> Unit)? = null,
    menuContext: SongMenuContext = SongMenuContext(),
    selectKey: String = track.id,
    swipeToPlayNext: Boolean = true,
    offerAdd: Boolean = false,
    librarySpace: Boolean = offerAdd,
    ownership: Boolean = false,
    highlight: Boolean = false,
    onClick: (() -> Unit)? = null,
) {
    val swap = if (isFind(track.id)) rememberFindSwap(track.id, offerAdd, LocalReduceMotion.current) else null
    // The song the row is for now: the library song once a find has become it.
    val song = swap?.library ?: track
    val nowId = LocalNowPlayingId.current.trackId
    val isNow = nowId == track.id || nowId == song.id
    val face: @Composable (TrackEntity) -> Unit = { shown ->
        SongFace(shown, lead, subtitle(shown), trailing, offerAdd, librarySpace, selectKey, isNow, ownership, highlight)
    }
    if (swipeToPlayNext) {
        val menu = LocalSongMenu.current
        // No swiping while the list is picking songs.
        val selecting = LocalSongSelection.current?.active == true
        PlayNextSwipe(enabled = !selecting, onSwiped = { menu.quick?.playNext(song.id) }) {
            SongLine(song, swap, menuContext, selectKey, onClick, face)
        }
    } else {
        SongLine(song, swap, menuContext, selectKey, onClick, face)
    }
}

// The row around a song: a tap plays it, a long press opens its menu. For a
// find, what it shows fades into the library song it became, in the same
// place and at the same height, so nothing around it moves.
@Composable
private fun SongLine(
    song: TrackEntity,
    swap: FindSwap?,
    menuContext: SongMenuContext,
    selectKey: String,
    onClick: (() -> Unit)?,
    face: @Composable (TrackEntity) -> Unit,
) {
    val menu = LocalSongMenu.current
    val haptics = LocalHapticFeedback.current
    val selection = LocalSongSelection.current
    val selecting = selection?.active == true
    val picked = selection?.isPicked(selectKey) == true
    val interaction = remember { MutableInteractionSource() }
    val squeeze by rememberPressSqueeze(interaction)
    Box(
        Modifier.graphicsLayer {
            // Held down, the row gives a little and springs back.
            scaleX = squeeze
            scaleY = squeeze
        },
    ) {
        // A picked song sits in the selected row's pill: the darker pill,
        // lightly tinted with the accent.
        if (picked) SelectedRow(Modifier.matchParentSize().padding(horizontal = ListRowPickInset, vertical = 2.dp), RowShape)
        Box(
            Modifier
                .fillMaxWidth()
                // A tap plays, or picks while the list is picking; a long
                // press opens the song's menu.
                .pressSpot(LocalPressSpot.current)
                .combinedClickable(
                    interactionSource = interaction,
                    indication = LocalIndication.current,
                    onClick = { if (selecting) selection.toggle(selectKey) else onClick?.invoke() },
                    onLongClickLabel = MoreOptions,
                    onLongClick = {
                        haptics.performHapticFeedback(HapticFeedbackType.LongPress)
                        menu.open(song.id, menuContext.copy(selection = selection, selectKey = selectKey))
                    },
                )
                .semantics {
                    if (selecting) selected = picked
                    customActions = listOf(
                        // Like the swipe it stands in for, it says so, with an Undo.
                        CustomAccessibilityAction("Play next") {
                            menu.quick?.playNext(song.id)
                            true
                        },
                        CustomAccessibilityAction("Add to queue") {
                            menu.quick?.addToQueue(song.id)
                            true
                        },
                    )
                }
                // At least a row tall; taller when large text needs it.
                .heightIn(min = 56.dp)
                .padding(horizontal = ListRowSide, vertical = 4.dp)
                // With no connection, a song that cannot play is drawn faint.
                .alpha(if (LocalOfflineMarks.current.isOutOfReach(song)) OutOfReachAlpha else 1f),
            contentAlignment = Alignment.CenterStart,
        ) {
            if (swap == null) {
                face(song)
            } else {
                // The find and its check hold still; only the turn into the
                // library song fades.
                AnimatedContent(
                    targetState = song,
                    transitionSpec = { fadeIn(tween(swap.fadeMs)) togetherWith fadeOut(tween(swap.fadeMs)) using null },
                    label = "find to library song",
                    contentKey = { it.id },
                ) { shown -> face(shown) }
            }
        }
    }
}

// What a song row shows: its artwork or number, title and subtitle, marks
// and length, and what goes at its end.
@Composable
private fun SongFace(
    track: TrackEntity,
    lead: SongLead,
    subtitle: String?,
    trailing: (@Composable () -> Unit)?,
    offerAdd: Boolean,
    librarySpace: Boolean,
    selectKey: String,
    isNow: Boolean,
    ownership: Boolean = false,
    highlight: Boolean = false,
) {
    val sign = rowAddSign(track.id, LocalAdoptedFinds.current, offerAdd)
    val end: (@Composable () -> Unit)? = when (rowEnd(sign, librarySpace, hasTrailing = trailing != null)) {
        RowEnd.AddButton -> ({ AddToLibraryButton(track, size = AddButtonSize, iconSize = AddIconSize) })
        RowEnd.AddSpace -> ({ Spacer(Modifier.width(AddButtonSize)) })
        RowEnd.Trailing -> trailing
    }
    val picked = LocalSongSelection.current?.isPicked(selectKey) == true
    val playing = LocalNowPlayingId.current.playing
    Row(
        Modifier.fillMaxWidth(),
        verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.spacedBy(12.dp),
    ) {
        val artwork: @Composable () -> Unit = {
            Box(contentAlignment = Alignment.Center) {
                Artwork(track.artwork, 44.dp, shape = RoundedCornerShape(6.dp), outside = sign == AddSign.Mark)
                when {
                    picked -> LeadMark { PickedMark() }
                    isNow -> LeadMark { NowPlayingBars(playing, Modifier.size(16.dp)) }
                }
            }
        }
        when (lead) {
            SongLead.Artwork -> artwork()
            is SongLead.Ranked -> Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(10.dp)) {
                Text(
                    lead.rank.toString(),
                    style = OctoType.caption,
                    color = OctoColors.TextMuted,
                    textAlign = TextAlign.End,
                    modifier = Modifier.width(20.dp),
                )
                artwork()
            }
            is SongLead.Number -> Box(Modifier.width(28.dp), contentAlignment = Alignment.CenterEnd) {
                when {
                    picked -> PickedMark()
                    isNow -> NowPlayingBars(playing, Modifier.size(14.dp))
                    else -> Text(
                        lead.track?.toString() ?: "",
                        style = OctoType.caption,
                        color = OctoColors.TextMuted,
                        textAlign = TextAlign.End,
                    )
                }
            }
        }
        if (ownership) OwnershipMark(track)
        Column(Modifier.weight(1f)) {
            SongTitle(
                track.title,
                explicit = track.explicit == true,
                style = OctoType.bodySmall,
                color = OctoColors.TextPrimary,
                leading = if (highlight) {
                    {
                        // The album's main song, starred as Apple Music marks it.
                        Icon(
                            painterResource(OctoIcons.StarFilled),
                            contentDescription = "Most popular",
                            tint = OctoColors.Accent,
                            modifier = Modifier.padding(end = 6.dp).size(14.dp),
                        )
                    }
                } else {
                    null
                },
            )
            if (!subtitle.isNullOrEmpty()) {
                Text(subtitle, style = OctoType.caption, color = OctoColors.TextMuted, maxLines = 1, overflow = TextOverflow.Ellipsis)
            }
        }
        Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(6.dp)) {
            // A song found online has no mark here: its artwork or add
            // button says it. Its length may only be learned by playing it.
            SourceMark(track)
            LengthSlot(shownLengthMs(track.durationMs, LocalLearnedLengths.current[track.id]))
        }
        end?.invoke()
    }
}

// Shaded over a row's artwork, so a mark on it reads.
private val LeadShade = Color.Black.copy(alpha = 0.5f)

@Composable
private fun LeadMark(mark: @Composable () -> Unit) {
    Box(Modifier.size(44.dp).background(LeadShade, RoundedCornerShape(6.dp)), contentAlignment = Alignment.Center) { mark() }
}

@Composable
private fun PickedMark() {
    Icon(painterResource(OctoIcons.Select), contentDescription = null, tint = OctoColors.TextPrimary, modifier = Modifier.size(22.dp))
}

// A swipe right puts the song next: the row springs back once it has, with
// "Play next" showing behind it on the way.
@Composable
private fun PlayNextSwipe(enabled: Boolean, onSwiped: () -> Unit, content: @Composable () -> Unit) {
    val swipe = rememberSwipeToDismissBoxState()
    val scope = rememberCoroutineScope()
    val haptics = LocalHapticFeedback.current
    SwipeToDismissBox(
        state = swipe,
        enableDismissFromEndToStart = false,
        gesturesEnabled = enabled,
        onDismiss = {
            haptics.performHapticFeedback(HapticFeedbackType.Confirm)
            onSwiped()
            scope.launch { swipe.reset() }
        },
        backgroundContent = { PlayNextBackground(swipe.dismissDirection == SwipeToDismissBoxValue.StartToEnd, RowShape) },
    ) {
        // Solid under the row while it moves, so it hides what it passes
        // over; clear at rest, so the page's glow shows.
        val swiping = swipe.dismissDirection == SwipeToDismissBoxValue.StartToEnd
        Box(Modifier.background(if (swiping) OctoColors.Background else Color.Transparent, RowShape)) { content() }
    }
}

// An artist line: round picture, name, album count. A long press opens the
// artist's menu.
@Composable
fun ArtistRow(artist: ArtistEntity, onClick: () -> Unit) {
    val menus = LocalSongMenu.current.collections
    ArtistRow(artist.artwork, artist.name, artist.albumCount, onClick, { menus.open(CollectionTarget.Artist(artist.id)) }, outside = false)
}

// An artist on the server the library lacks, drawn the same way, with the
// not-in-library mark; the album count only when the server knows it.
@Composable
fun ArtistRow(artist: OnlineArtist, onClick: () -> Unit) =
    ArtistRow(artist.artwork, artist.name, artist.albumCount.takeIf { it > 0 }, onClick, null, outside = true)

@Composable
private fun ArtistRow(artwork: String?, name: String, albumCount: Int?, onClick: () -> Unit, onLongClick: (() -> Unit)?, outside: Boolean) {
    Row(
        Modifier
            .fillMaxWidth()
            .pressOrHold(LocalHapticFeedback.current, LocalPressSpot.current, onClick, onLongClick)
            // At least a row tall; taller when large text needs it.
            .heightIn(min = 64.dp)
            .padding(horizontal = ListRowSide, vertical = 4.dp),
        verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.spacedBy(12.dp),
    ) {
        Artwork(artwork, 48.dp, shape = CircleShape, outside = outside)
        Column(Modifier.weight(1f)) {
            Text(name, style = OctoType.bodySmall, color = OctoColors.TextPrimary, maxLines = 1, overflow = TextOverflow.Ellipsis)
            if (albumCount != null) Text(albums(albumCount), style = OctoType.caption, color = OctoColors.TextMuted)
        }
    }
}

// An artist as a round picture with the name under it, for rows. A long
// press opens the artist's menu.
@Composable
fun ArtistCircle(artist: ArtistEntity, onClick: () -> Unit) {
    val menus = LocalSongMenu.current.collections
    ArtistCircle(artist.artwork, artist.name, onClick, { menus.open(CollectionTarget.Artist(artist.id)) }, outside = false)
}

// An artist on the server, drawn the same way. Not in the library unless
// said otherwise (`outside`), so with the not-in-library mark.
@Composable
fun ArtistCircle(artist: OnlineArtist, outside: Boolean = true, onClick: () -> Unit) =
    ArtistCircle(artist.artwork, artist.name, onClick, null, outside = outside)

@Composable
private fun ArtistCircle(artwork: String?, name: String, onClick: () -> Unit, onLongClick: (() -> Unit)?, outside: Boolean) {
    Column(
        Modifier.width(96.dp).pressOrHold(LocalHapticFeedback.current, LocalPressSpot.current, onClick, onLongClick),
        horizontalAlignment = Alignment.CenterHorizontally,
    ) {
        Artwork(artwork, 96.dp, shape = CircleShape, outside = outside)
        Spacer(Modifier.height(8.dp))
        Text(
            name,
            style = OctoType.caption,
            color = OctoColors.TextPrimary,
            maxLines = 1,
            overflow = TextOverflow.Ellipsis,
            textAlign = TextAlign.Center,
        )
    }
}
