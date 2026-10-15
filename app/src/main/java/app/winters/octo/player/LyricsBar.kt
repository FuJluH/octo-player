package app.winters.octo.player

import androidx.annotation.DrawableRes
import androidx.compose.foundation.clickable
import androidx.compose.foundation.gestures.awaitEachGesture
import androidx.compose.foundation.gestures.awaitFirstDown
import androidx.compose.foundation.gestures.awaitHorizontalTouchSlopOrCancellation
import androidx.compose.foundation.gestures.horizontalDrag
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.material3.Icon
import androidx.compose.material3.LocalContentColor
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.MutableLongState
import androidx.compose.runtime.derivedStateOf
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberUpdatedState
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.input.pointer.pointerInput
import androidx.compose.ui.layout.boundsInWindow
import androidx.compose.ui.layout.onGloballyPositioned
import androidx.compose.ui.res.painterResource
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.clearAndSetSemantics
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.semantics.stateDescription
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.IntRect
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.roundToIntRect
import androidx.compose.ui.unit.sp
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import app.winters.octo.design.FloatingGlaze
import app.winters.octo.design.LocalGlassBackdrop
import app.winters.octo.design.GlowIcon
import app.winters.octo.design.OctoIcons
import app.winters.octo.design.OctoType
import app.winters.octo.playback.NowPlaying
import app.winters.octo.ui.common.Artwork
import app.winters.octo.ui.common.asClock
import app.winters.octo.ui.common.LocalHaze
import app.winters.octo.ui.common.isOutsideLibrary
import app.winters.octo.ui.nav.ProgressRing
import app.winters.octo.ui.nav.RingStepMs
import app.winters.octo.ui.nav.isPaused

// How tall the small player under the lyrics is, and the room kept below it.
val LyricsBarHeight = 64.dp
val LyricsBarGap = 12.dp

// A drag that starts this close to the bottom edge moves through the song.
private val ScrubEdge = 22.dp

// The small player in lyrics mode, one glass capsule like the app's bar:
// the round artwork, the song, back, play and next, the lyrics switch, lit (a tap
// leaves lyrics), and the lyrics menu. A thin ring round the artwork shows
// how far the song has played, as the bar's round button does; a drag
// along the bottom edge moves through the song, the ring following the
// finger. A tap on the song leaves lyrics too, and a screen reader finds
// Close player on it.
@Composable
fun LyricsBar(
    now: NowPlaying,
    model: PlayerViewModel,
    onChooseLyrics: () -> Unit,
    onClose: () -> Unit,
    modifier: Modifier = Modifier,
) {
    val ink = LocalContentColor.current
    // The ring round the artwork is short, so it steps once a second.
    val position = rememberPositionMs(now, model::positionMs, everyMs = RingStepMs)
    val duration by rememberUpdatedState(now.durationMs)
    // Where a drag along the edge has got to, while one is under way.
    var scrub by remember { mutableStateOf<Float?>(null) }
    var menuAnchor by remember { mutableStateOf<IntRect?>(null) }
    var menuOpen by remember { mutableStateOf(false) }
    val lyrics by model.lyrics.collectAsStateWithLifecycle()

    FloatingGlaze(
        LocalHaze.current,
        picture = LocalGlassBackdrop.current,
        modifier = modifier
            .fillMaxWidth()
            .height(LyricsBarHeight)
            .pointerInput(Unit) {
                val edge = ScrubEdge.toPx()
                val inset = (LyricsBarHeight / 2).toPx()
                fun at(x: Float) = ((x - inset) / (size.width - inset * 2).coerceAtLeast(1f)).coerceIn(0f, 1f)
                awaitEachGesture {
                    val down = awaitFirstDown(requireUnconsumed = false)
                    if (down.position.y < size.height - edge || duration <= 0) return@awaitEachGesture
                    // Only a sideways drag scrubs, so taps still reach the buttons.
                    val start = awaitHorizontalTouchSlopOrCancellation(down.id) { change, _ -> change.consume() }
                        ?: return@awaitEachGesture
                    scrub = at(start.position.x)
                    val finished = horizontalDrag(start.id) { change ->
                        scrub = at(change.position.x)
                        change.consume()
                    }
                    val landed = scrub
                    if (finished && landed != null) {
                        val target = (landed * duration).toLong()
                        position.longValue = target
                        model.seekTo(target)
                    }
                    scrub = null
                }
            },
    ) {
        Row(
            // The artwork sits 12dp in; its ring takes the room around it.
            Modifier.fillMaxSize().padding(start = 12.dp - RingRoom, end = 6.dp),
            verticalAlignment = Alignment.CenterVertically,
        ) {
            ArtWithRing(now, position, progress = { scrub ?: now.fractionAt(position.longValue) })
            Column(
                Modifier
                    .weight(1f)
                    .clickable(
                        interactionSource = null,
                        indication = null,
                        role = Role.Button,
                        onClickLabel = "Leave lyrics",
                        onClick = model::toggleLyrics,
                    )
                    .closesPlayer(onClose)
                    .padding(start = 10.dp - RingRoom, end = 10.dp, top = 8.dp, bottom = 8.dp),
            ) {
                Text(now.title.orEmpty(), style = OctoType.label, color = ink, maxLines = 1, overflow = TextOverflow.Ellipsis)
                Text(
                    now.artist.orEmpty(),
                    style = OctoType.caption.copy(fontSize = 11.sp),
                    color = ink.copy(alpha = 0.6f),
                    maxLines = 1,
                    overflow = TextOverflow.Ellipsis,
                )
            }
            BarButton(OctoIcons.Previous, "Previous", 24.dp, model::previous)
            BarButton(if (now.isPlaying) OctoIcons.Pause else OctoIcons.Play, if (now.isPlaying) "Pause" else "Play", 28.dp, model::togglePlayPause)
            BarButton(OctoIcons.Next, "Next", 24.dp, model::next)
            Box(
                Modifier
                    .size(40.dp)
                    .clickable(interactionSource = null, indication = null, role = Role.Button, onClick = model::toggleLyrics)
                    .semantics {
                        contentDescription = "Lyrics"
                        stateDescription = "Showing"
                    },
                contentAlignment = Alignment.Center,
            ) {
                GlowIcon(painterResource(OctoIcons.Lyrics), tint = ink, lit = true, modifier = Modifier.size(22.dp))
            }
            Box(
                Modifier
                    .size(40.dp)
                    .onGloballyPositioned { menuAnchor = it.boundsInWindow().roundToIntRect() }
                    .clickable(interactionSource = null, indication = null, role = Role.Button) { menuOpen = true }
                    .semantics { contentDescription = "Lyrics menu" },
                contentAlignment = Alignment.Center,
            ) {
                Icon(painterResource(OctoIcons.More), contentDescription = null, tint = ink.copy(alpha = 0.7f), modifier = Modifier.size(22.dp))
            }
        }
    }
    LyricsMenu(
        visible = menuOpen,
        anchor = menuAnchor,
        state = lyrics,
        trackId = now.trackId,
        onDismiss = { menuOpen = false },
        onChooseOther = onChooseLyrics,
    )
}

// Back, play or next: a plain icon that answers a tap.
@Composable
private fun BarButton(@DrawableRes icon: Int, description: String, iconSize: Dp, onClick: () -> Unit) {
    Box(
        Modifier
            .size(40.dp)
            .clickable(interactionSource = null, indication = null, role = Role.Button, onClick = onClick)
            .semantics { contentDescription = description },
        contentAlignment = Alignment.Center,
    ) {
        Icon(painterResource(icon), contentDescription = null, tint = LocalContentColor.current, modifier = Modifier.size(iconSize))
    }
}

// The artwork, and the room between it and its ring.
private val ArtSize = 40.dp
private val RingRoom = 3.dp

// The song's artwork, round, with a ring round it for how far the song has
// played (`progress`, read while drawing): the bar's round button, full
// for a station, breathing while paused. A screen reader hears the song
// and how much of it has played.
@Composable
private fun ArtWithRing(now: NowPlaying, position: MutableLongState, progress: () -> Float) {
    val playedSeconds by remember { derivedStateOf { (position.longValue / 1000).toInt() } }
    val song = listOfNotNull(now.title?.takeIf(String::isNotBlank), now.artist?.takeIf(String::isNotBlank)).joinToString(", ")
    val played = playedWords(playedSeconds, (now.durationMs / 1000).toInt(), live = now.live != null)
    Box(
        Modifier
            .size(ArtSize + RingRoom * 2)
            .clearAndSetSemantics {
                if (song.isNotEmpty()) contentDescription = song
                if (played.isNotEmpty()) stateDescription = played
            },
        contentAlignment = Alignment.Center,
    ) {
        Artwork(now.artwork, ArtSize, shape = CircleShape, outside = isOutsideLibrary(now.trackId))
        if (now.trackId != null) {
            ProgressRing(progress, paused = isPaused(now), modifier = Modifier.matchParentSize(), whole = now.live != null)
        }
    }
}

// How much of the song has played, as a screen reader says it: "1:05 of
// 3:20 played". Nothing for a station or a song of no known length.
internal fun playedWords(playedSeconds: Int, lengthSeconds: Int, live: Boolean): String =
    if (live || lengthSeconds <= 0) "" else "${playedSeconds.coerceIn(0, lengthSeconds).asClock()} of ${lengthSeconds.asClock()} played"
