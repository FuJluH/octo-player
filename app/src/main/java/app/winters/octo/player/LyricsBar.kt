package app.winters.octo.player

import androidx.annotation.DrawableRes
import androidx.compose.foundation.Canvas
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
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.Icon
import androidx.compose.material3.LocalContentColor
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberUpdatedState
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.graphics.StrokeCap
import androidx.compose.ui.input.pointer.pointerInput
import androidx.compose.ui.layout.boundsInWindow
import androidx.compose.ui.layout.onGloballyPositioned
import androidx.compose.ui.res.painterResource
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.semantics.stateDescription
import androidx.compose.ui.platform.LocalWindowInfo
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.IntRect
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.roundToIntRect
import androidx.compose.ui.unit.sp
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import app.winters.octo.design.FloatingGlaze
import app.winters.octo.design.GlowIcon
import app.winters.octo.design.OctoIcons
import app.winters.octo.design.OctoType
import app.winters.octo.playback.NowPlaying
import app.winters.octo.ui.common.Artwork
import app.winters.octo.ui.common.LocalHaze
import app.winters.octo.ui.common.isOutsideLibrary

// How tall the small player under the lyrics is, and the room kept below it.
val LyricsBarHeight = 64.dp
val LyricsBarGap = 12.dp

// A drag that starts this close to the bottom edge moves through the song.
private val ScrubEdge = 22.dp

// The small player in lyrics mode, one glass capsule like the app's bar:
// the artwork, the song, back, play and next, the lyrics switch, lit (a tap
// leaves lyrics), and the lyrics menu. A thin line along the bottom edge
// shows how far the song has played; a drag along that edge moves through
// it. A tap on the song leaves lyrics too, and a screen reader finds Close
// player on it.
@Composable
fun LyricsBar(
    now: NowPlaying,
    model: PlayerViewModel,
    onChooseLyrics: () -> Unit,
    onClose: () -> Unit,
    modifier: Modifier = Modifier,
) {
    val ink = LocalContentColor.current
    // The line along the edge is never wider than the window.
    val position = rememberPositionMs(now, model::positionMs, lengthPx = LocalWindowInfo.current.containerSize.width.toFloat())
    val duration by rememberUpdatedState(now.durationMs)
    // Where a drag along the edge has got to, while one is under way.
    var scrub by remember { mutableStateOf<Float?>(null) }
    var menuAnchor by remember { mutableStateOf<IntRect?>(null) }
    var menuOpen by remember { mutableStateOf(false) }
    val lyrics by model.lyrics.collectAsStateWithLifecycle()

    FloatingGlaze(
        LocalHaze.current,
        modifier
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
            Modifier.fillMaxSize().padding(start = 12.dp, end = 6.dp),
            verticalAlignment = Alignment.CenterVertically,
        ) {
            Artwork(now.artwork, 40.dp, shape = RoundedCornerShape(10.dp), outside = isOutsideLibrary(now.trackId))
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
                    .padding(horizontal = 10.dp, vertical = 8.dp),
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
        // The song's progress along the straight part of the bottom edge,
        // brighter and thicker while it is dragged.
        Canvas(
            Modifier
                .align(Alignment.BottomCenter)
                .padding(start = LyricsBarHeight / 2, end = LyricsBarHeight / 2, bottom = 4.dp)
                .fillMaxWidth()
                .height(3.dp),
        ) {
            val dragging = scrub != null
            val fraction = scrub ?: now.fractionAt(position.longValue)
            val weight = if (dragging) size.height else size.height * 2 / 3
            val y = size.height - weight / 2
            drawLine(ink.copy(alpha = 0.18f), Offset(0f, y), Offset(size.width, y), strokeWidth = weight, cap = StrokeCap.Round)
            if (fraction > 0f) {
                drawLine(
                    ink.copy(alpha = if (dragging) 0.95f else 0.7f),
                    Offset(0f, y),
                    Offset(size.width * fraction, y),
                    strokeWidth = weight,
                    cap = StrokeCap.Round,
                )
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
