package app.winters.octo.ui.nav

import androidx.annotation.DrawableRes
import androidx.annotation.StringRes
import androidx.compose.animation.animateColorAsState
import androidx.compose.animation.core.animate
import androidx.compose.animation.core.animateDpAsState
import androidx.compose.animation.core.animateFloatAsState
import androidx.compose.animation.core.spring
import androidx.compose.foundation.clickable
import androidx.compose.foundation.interaction.MutableInteractionSource
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.BoxWithConstraints
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxHeight
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.navigationBarsPadding
import androidx.compose.foundation.layout.offset
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.layout.widthIn
import androidx.compose.foundation.layout.wrapContentWidth
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.material3.Icon
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableFloatStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.rememberUpdatedState
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.alpha
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.Shape
import androidx.compose.ui.graphics.graphicsLayer
import androidx.compose.ui.graphics.lerp
import androidx.compose.ui.hapticfeedback.HapticFeedbackType
import androidx.compose.ui.input.pointer.pointerInput
import androidx.compose.ui.platform.LocalHapticFeedback
import androidx.compose.ui.res.painterResource
import androidx.compose.ui.res.stringResource
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.semantics.stateDescription
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.IntOffset
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.lerp
import androidx.compose.ui.unit.sp
import app.winters.octo.ui.common.SongTitle
import app.winters.octo.R
import app.winters.octo.design.FloatingGlaze
import app.winters.octo.design.GlazeSelected
import app.winters.octo.design.GlazeTint
import app.winters.octo.design.OctoColors
import app.winters.octo.design.OctoIcons
import app.winters.octo.design.OctoType
import app.winters.octo.playback.NowPlaying
import app.winters.octo.player.LiveStopIcon
import app.winters.octo.player.fractionAt
import app.winters.octo.player.rememberPositionMs
import app.winters.octo.ui.common.Artwork
import app.winters.octo.ui.common.AxisDrag
import app.winters.octo.ui.common.SwipeSkip
import app.winters.octo.ui.common.detectAxisDrags
import app.winters.octo.ui.common.isOutsideLibrary
import app.winters.octo.ui.common.swipeSkip
import app.winters.octo.ui.common.swipeUp
import dev.chrisbanes.haze.HazeState
import kotlinx.coroutines.launch
import kotlin.math.abs

// A tab: its icon, the filled icon it shows while selected, and its name.
private class Tab(@DrawableRes val icon: Int, @DrawableRes val selectedIcon: Int, @StringRes val label: Int)

private val tabs = listOf(
    Tab(OctoIcons.Home, OctoIcons.HomeSelected, R.string.tab_home),
    Tab(OctoIcons.Search, OctoIcons.SearchSelected, R.string.tab_search),
    Tab(OctoIcons.Library, OctoIcons.LibrarySelected, R.string.tab_library),
    Tab(OctoIcons.Settings, OctoIcons.SettingsSelected, R.string.tab_settings),
)

val BarHeight = 56.dp

// The space between the bar and the bottom of the screen.
val BarBottomGap = 14.dp
private val TabIconSize = 23.dp
private val Gap = 10.dp

// How often a progress ring round a small artwork steps while playing.
const val RingStepMs = 1_000L

// What the bar's buttons do.
class BarActions(
    val onSelect: (Int) -> Unit,
    val onRoundButton: () -> Unit,
    val onShowTabs: () -> Unit,
    val onOpenPlayer: () -> Unit,
    val onPrevious: () -> Unit,
    val onPlayPause: () -> Unit,
    val onNext: () -> Unit,
)

// The floating bar. It has two shapes: tabs on the left with a round
// now-playing button, or, once that button is tapped, the tabs folded into
// one circle and the button grown into a small player.
@Composable
fun BottomBar(
    haze: HazeState,
    selected: Int,
    now: NowPlaying,
    positionMs: () -> Long,
    playerShown: Boolean,
    actions: BarActions,
    artModifier: Modifier,
    artShape: Shape,
    modifier: Modifier = Modifier,
    // The glass's film, which can carry a trace of the song's colour.
    film: Color = GlazeTint,
    // The tabs carrying a small dot, by index, each with what it means.
    marks: Map<Int, String> = emptyMap(),
) {
    val grown by animateFloatAsState(if (playerShown) 1f else 0f, spring(0.75f, 200f), label = "bar shape")
    // The ring round the button is the only thing here that moves with the
    // song, a pixel or two a second, so it steps once a second, with the
    // glow behind the page.
    val position = rememberPositionMs(now, positionMs, everyMs = RingStepMs)
    val progress = { now.fractionAt(position.longValue) }
    val swipe = rememberBarSwipe(hasSong = now.trackId != null, actions)

    BoxWithConstraints(
        modifier
            .navigationBarsPadding()
            .padding(start = 20.dp, end = 20.dp, bottom = BarBottomGap)
            .widthIn(max = 520.dp)
            .fillMaxWidth()
            .height(BarHeight),
    ) {
        val fullTabs = maxWidth - BarHeight - Gap
        val tabsWidth = lerp(fullTabs, BarHeight, grown)
        TabBar(haze, selected, grown, playerShown, fullTabs, Modifier.width(tabsWidth), actions, film, marks)
        FloatingGlaze(
            haze,
            Modifier
                .offset(x = tabsWidth + Gap)
                .width(maxWidth - tabsWidth - Gap)
                .fillMaxHeight()
                .then(swipe.gestures),
            film = film,
        ) {
            if (grown < 1f) {
                Box(
                    Modifier
                        .size(BarHeight)
                        .then(swipe.follow)
                        .alpha(1f - grown.coerceIn(0f, 1f))
                        .clickable(
                            enabled = !playerShown,
                            interactionSource = remember { MutableInteractionSource() },
                            indication = null,
                            role = Role.Button,
                            onClickLabel = if (now.trackId != null) "Show the player controls" else null,
                            onClick = actions.onRoundButton,
                        )
                        .semantics {
                            contentDescription = nowPlayingWords(now)
                            nowPlayingState(now).takeIf(String::isNotEmpty)?.let { stateDescription = it }
                        },
                ) {
                    NowPlayingFace(now, progress)
                }
            }
            if (grown > 0f) {
                PlayerCapsule(
                    now,
                    progress,
                    width = fullTabs,
                    artModifier = artModifier,
                    artShape = artShape,
                    actions = actions,
                    modifier = Modifier.matchParentSize().clip(CircleShape).alpha(grown.coerceIn(0f, 1f)),
                    follow = swipe.follow,
                )
            }
        }
    }
}

// The glaze across the whole bar, with the selected tab marked by a darker
// pill that glides between tabs. Folded, it is one glazed circle showing the
// current tab, which unfolds the tabs again.
@Composable
private fun TabBar(
    haze: HazeState,
    selected: Int,
    folded: Float,
    isFolded: Boolean,
    fullWidth: Dp,
    modifier: Modifier,
    actions: BarActions,
    film: Color,
    marks: Map<Int, String>,
) {
    FloatingGlaze(
        haze,
        modifier
            .fillMaxHeight()
            .clickable(
                enabled = isFolded,
                interactionSource = remember { MutableInteractionSource() },
                indication = null,
                role = Role.Button,
                onClick = actions.onShowTabs,
            ),
        film = film,
    ) {
        val column = (fullWidth - 12.dp) / tabs.size
        val capsuleWidth = 62.dp
        val capsuleX by animateDpAsState(
            targetValue = 6.dp + column * selected + (column - capsuleWidth) / 2,
            animationSpec = spring(dampingRatio = 0.8f, stiffness = 350f),
            label = "tab capsule",
        )
        // Folding, the selected pill slides left and swells into the whole
        // circle while it fades, carrying the tab's icon, so the folded tab is
        // the same glazed button as the one at the other end of the bar.
        val glazeX = lerp(capsuleX, 0.dp, folded)
        // Narrows to the circle as it folds, so the icon it carries stays centred.
        val pillWidth = lerp(capsuleWidth, BarHeight, folded)
        Box(Modifier.matchParentSize().clip(CircleShape)) {
            if (folded < 1f) {
                GlazeSelected(
                    Modifier
                        .align(Alignment.CenterStart)
                        .offset { IntOffset(glazeX.roundToPx(), 0) }
                        .size(width = pillWidth, height = lerp(44.dp, BarHeight, folded))
                        .alpha(1f - folded.coerceIn(0f, 1f)),
                )
            }
            if (folded < 1f) {
                // Laid out at full width and clipped, so the tabs slide under
                // the folding edge instead of squeezing together.
                Row(
                    Modifier
                        .wrapContentWidth(Alignment.Start, unbounded = true)
                        .width(fullWidth)
                        .fillMaxHeight()
                        .padding(horizontal = 6.dp)
                        .alpha(1f - folded.coerceIn(0f, 1f)),
                ) {
                    tabs.forEachIndexed { index, tab ->
                        TabButton(
                            tab,
                            selected = index == selected,
                            // While folding, the selected icon rides the glaze instead.
                            // The spring overshoots a little past open (below 0), so
                            // "open" is anything at or under 0; testing for exactly 0
                            // hid both copies of the icon for that moment.
                            showIcon = folded <= 0f || index != selected,
                            enabled = !isFolded,
                            // On the tab in front, its page shows what waits instead.
                            mark = marks[index]?.takeIf { index != selected },
                            modifier = Modifier.weight(1f),
                        ) { actions.onSelect(index) }
                    }
                }
            }
            if (folded > 0f) {
                Icon(
                    painterResource(tabs[selected].selectedIcon),
                    contentDescription = "Show tabs",
                    // The selected tab's accent, turning white as it folds into
                    // a plain glaze circle like the round button.
                    tint = lerp(OctoColors.Accent, OctoColors.TextPrimary, folded.coerceIn(0f, 1f)),
                    modifier = Modifier
                        .align(Alignment.CenterStart)
                        .offset { IntOffset((glazeX + (pillWidth - TabIconSize) / 2).roundToPx(), 0) }
                        .size(TabIconSize),
                )
            }
        }
    }
}

@Composable
private fun TabButton(
    tab: Tab,
    selected: Boolean,
    showIcon: Boolean,
    enabled: Boolean,
    mark: String?,
    modifier: Modifier,
    onClick: () -> Unit,
) {
    val tint by animateColorAsState(
        // White by default so every tab reads clearly; the selected one takes
        // the accent, set in its darker pill.
        if (selected) OctoColors.Accent else OctoColors.TextPrimary,
        label = "tab tint",
    )
    Box(
        modifier
            .fillMaxHeight()
            .clickable(
                enabled = enabled,
                interactionSource = remember { MutableInteractionSource() },
                indication = null,
                onClick = onClick,
            ),
        contentAlignment = Alignment.Center,
    ) {
        val label = stringResource(tab.label)
        Box(Modifier.size(TabIconSize).alpha(if (showIcon) 1f else 0f)) {
            Icon(
                painterResource(if (selected) tab.selectedIcon else tab.icon),
                contentDescription = if (mark != null) "$label, $mark" else label,
                tint = tint,
                modifier = Modifier.matchParentSize(),
            )
            // A small dot on the icon's corner while something waits there.
            if (mark != null) {
                Box(
                    Modifier
                        .align(Alignment.TopEnd)
                        .offset(x = 3.dp, y = (-2).dp)
                        .size(7.dp)
                        .background(OctoColors.Accent, CircleShape),
                )
            }
        }
    }
}

// The small player: artwork with its progress ring (breathing while
// paused), the song, and back, play and next. Tapping anywhere else opens the full player; so does a
// swipe up, and a swipe sideways skips.
@Composable
private fun PlayerCapsule(
    now: NowPlaying,
    progress: () -> Float,
    width: Dp,
    artModifier: Modifier,
    artShape: Shape,
    actions: BarActions,
    modifier: Modifier,
    follow: Modifier,
) {
    Box(
        modifier.clickable(
            interactionSource = remember { MutableInteractionSource() },
            indication = null,
            role = Role.Button,
            onClickLabel = "Open player",
            onClick = actions.onOpenPlayer,
        ),
    ) {
        Row(
            Modifier
                .wrapContentWidth(Alignment.Start, unbounded = true)
                .width(width)
                .fillMaxHeight()
                .then(follow)
                .padding(start = 6.dp, end = 4.dp),
            verticalAlignment = Alignment.CenterVertically,
        ) {
            Box(Modifier.size(44.dp), contentAlignment = Alignment.Center) {
                Artwork(now.artwork, 36.dp, artModifier, shape = artShape, outside = isOutsideLibrary(now.trackId))
                ProgressRing(progress, paused = isPaused(now), modifier = Modifier.matchParentSize().padding(1.dp), whole = now.live != null)
            }
            Column(Modifier.weight(1f).padding(horizontal = 10.dp)) {
                SongTitle(
                    now.title.orEmpty(),
                    explicit = now.explicit,
                    style = OctoType.label,
                    color = OctoColors.TextPrimary,
                )
                Text(
                    now.artist.orEmpty(),
                    style = OctoType.caption.copy(fontSize = 11.sp),
                    color = OctoColors.TextMuted,
                    maxLines = 1,
                    overflow = TextOverflow.Ellipsis,
                )
            }
            val live = now.live
            if (live == null) {
                CapsuleButton(OctoIcons.Previous, "Previous", actions.onPrevious)
                CapsuleButton(if (now.isPlaying) OctoIcons.Pause else OctoIcons.Play, if (now.isPlaying) "Pause" else "Play", actions.onPlayPause)
                CapsuleButton(OctoIcons.Next, "Next", actions.onNext)
            } else {
                // A station stops rather than pauses; Back and Next change
                // station, while there is more than one to change to.
                val lineup = live.lineup
                if (lineup.shows) CapsuleButton(OctoIcons.Previous, "Previous station", actions.onPrevious, enabled = lineup.hasPrevious)
                CapsuleButton(if (now.playWhenReady) LiveStopIcon else OctoIcons.Play, if (now.playWhenReady) "Stop" else "Play", actions.onPlayPause)
                if (lineup.shows) CapsuleButton(OctoIcons.Next, "Next station", actions.onNext, enabled = lineup.hasNext)
            }
        }
    }
}

@Composable
private fun CapsuleButton(@DrawableRes icon: Int, description: String, onClick: () -> Unit, enabled: Boolean = true) {
    Box(
        Modifier
            .size(36.dp)
            .clickable(
                interactionSource = remember { MutableInteractionSource() },
                indication = null,
                enabled = enabled,
                role = Role.Button,
                onClick = onClick,
            )
            .semantics { contentDescription = description },
        contentAlignment = Alignment.Center,
    ) {
        Icon(
            painterResource(icon),
            contentDescription = null,
            tint = if (enabled) OctoColors.TextPrimary else OctoColors.TextPrimary.copy(alpha = 0.3f),
            modifier = Modifier.size(28.dp),
        )
    }
}

// Swipes on the round button and the small player: sideways skips (left to
// the next song, right to the one before), and up opens the full player.
// Taps still go to the buttons. `gestures` goes on the glass, which stays
// put; `follow` goes on what is inside it, which leans a little with the
// finger.
private class BarSwipe(val gestures: Modifier, val follow: Modifier)

@Composable
private fun rememberBarSwipe(hasSong: Boolean, actions: BarActions): BarSwipe {
    val scope = rememberCoroutineScope()
    val haptics = LocalHapticFeedback.current
    val current by rememberUpdatedState(actions)
    // How far the finger has gone, sideways and up, in pixels.
    var sideways by remember { mutableFloatStateOf(0f) }
    var up by remember { mutableFloatStateOf(0f) }
    val follow = Modifier.graphicsLayer {
        translationX = sideways * 0.3f
        translationY = up * 0.3f
    }
    if (!hasSong) return BarSwipe(Modifier, follow)
    val gestures = Modifier.pointerInput(Unit) {
        val skipAt = 56.dp.toPx()
        val openAt = 28.dp.toPx()
        val fling = 700.dp.toPx()
        var armed = false
        // A tick when the finger passes the point where letting go acts.
        fun mark(past: Boolean) {
            if (past != armed) {
                armed = past
                if (past) haptics.performHapticFeedback(HapticFeedbackType.GestureThresholdActivate)
            }
        }
        fun settle(set: (Float) -> Unit, from: Float) {
            armed = false
            scope.launch { animate(from, 0f, animationSpec = spring(0.8f, 400f)) { value, _ -> set(value) } }
        }
        detectAxisDrags(
            horizontal = AxisDrag(
                onMove = { offset ->
                    sideways = offset
                    mark(abs(offset) >= skipAt)
                },
                onEnd = { offset, velocity ->
                    when (swipeSkip(offset, velocity, skipAt, fling)) {
                        SwipeSkip.Next -> current.onNext()
                        SwipeSkip.Previous -> current.onPrevious()
                        SwipeSkip.Stay -> Unit
                    }
                    settle({ sideways = it }, sideways)
                },
            ),
            vertical = AxisDrag(
                onMove = { offset ->
                    up = offset.coerceAtMost(0f)
                    mark(offset <= -openAt)
                },
                onEnd = { offset, velocity ->
                    if (swipeUp(offset, velocity, openAt, fling)) {
                        armed = false
                        up = 0f
                        current.onOpenPlayer()
                    } else {
                        settle({ up = it }, up)
                    }
                },
            ),
        )
    }
    return BarSwipe(gestures, follow)
}
