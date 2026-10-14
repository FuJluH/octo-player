package app.winters.octo.player

import android.app.Activity
import android.content.Context
import android.content.ContextWrapper
import android.os.Build
import androidx.activity.compose.BackHandler
import androidx.annotation.DrawableRes
import androidx.compose.animation.AnimatedContent
import androidx.compose.animation.AnimatedContentTransitionScope
import androidx.compose.animation.ContentTransform
import androidx.compose.animation.EnterTransition
import androidx.compose.animation.SizeTransform
import androidx.compose.animation.AnimatedVisibility
import androidx.compose.animation.AnimatedVisibilityScope
import androidx.compose.animation.EnterExitState
import androidx.compose.animation.animateContentSize
import androidx.compose.animation.ExitTransition
import androidx.compose.animation.animateColorAsState
import androidx.compose.animation.core.VisibilityThreshold
import androidx.compose.animation.core.Animatable
import androidx.compose.animation.core.FastOutSlowInEasing
import androidx.compose.animation.core.snap
import androidx.compose.animation.core.animate
import androidx.compose.animation.core.animateFloatAsState
import androidx.compose.animation.core.animateInt
import androidx.compose.animation.core.spring
import androidx.compose.animation.core.tween
import androidx.compose.animation.fadeIn
import androidx.compose.animation.fadeOut
import androidx.compose.animation.scaleIn
import androidx.compose.animation.scaleOut
import androidx.compose.animation.slideInVertically
import androidx.compose.animation.togetherWith
import androidx.compose.foundation.background
import androidx.compose.foundation.basicMarquee
import androidx.compose.foundation.clickable
import androidx.compose.foundation.gestures.awaitEachGesture
import androidx.compose.foundation.gestures.awaitFirstDown
import androidx.compose.foundation.gestures.awaitVerticalTouchSlopOrCancellation
import androidx.compose.foundation.gestures.verticalDrag
import androidx.compose.foundation.interaction.MutableInteractionSource
import androidx.compose.foundation.interaction.collectIsPressedAsState
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.BoxWithConstraints
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.displayCutoutPadding
import androidx.compose.foundation.layout.fillMaxHeight
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.navigationBarsPadding
import androidx.compose.foundation.layout.offset
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.statusBarsPadding
import androidx.compose.foundation.layout.wrapContentHeight
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.Icon
import androidx.compose.material3.LocalContentColor
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.CompositionLocalProvider
import androidx.compose.runtime.DisposableEffect
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.derivedStateOf
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableFloatStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.rememberUpdatedState
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.alpha
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.graphicsLayer
import androidx.compose.ui.hapticfeedback.HapticFeedbackType
import androidx.compose.ui.input.pointer.pointerInput
import androidx.compose.ui.layout.Layout
import androidx.compose.ui.unit.Constraints
import androidx.compose.ui.input.pointer.positionChange
import androidx.compose.ui.input.pointer.util.VelocityTracker
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.platform.LocalHapticFeedback
import androidx.compose.ui.platform.LocalView
import androidx.compose.ui.res.painterResource
import androidx.compose.ui.semantics.CustomAccessibilityAction
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.semantics.clearAndSetSemantics
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.customActions
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.semantics.stateDescription
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.rememberTextMeasurer
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.IntOffset
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.min
import androidx.compose.ui.unit.sp
import androidx.core.view.WindowCompat
import androidx.hilt.lifecycle.viewmodel.compose.hiltViewModel
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import androidx.media3.common.Player
import app.winters.octo.ui.common.SongTitle
import app.winters.octo.catalog.isFind
import app.winters.octo.design.AccentFill
import app.winters.octo.design.GlassPopup
import app.winters.octo.design.PopupPager
import app.winters.octo.design.rememberPopupPages
import app.winters.octo.design.GlazeInset
import app.winters.octo.design.GlazeClearFilm
import app.winters.octo.design.GlowIcon
import app.winters.octo.design.Glaze
import app.winters.octo.design.IconAccent
import app.winters.octo.design.LineSlider
import app.winters.octo.design.rememberIconAccent
import app.winters.octo.design.OctoIcons
import app.winters.octo.design.OctoType
import app.winters.octo.design.elevation3
import app.winters.octo.playback.AudioQuality
import app.winters.octo.playback.NowPlaying
import app.winters.octo.playback.SleepState
import app.winters.octo.playback.sleepSummary
import app.winters.octo.playback.speedLabel
import app.winters.octo.player.immersive.CoverFadeMs
import app.winters.octo.player.immersive.PlayerBackground
import app.winters.octo.player.immersive.pausedBackgroundFps
import app.winters.octo.player.immersive.accentInk
import app.winters.octo.player.immersive.backgroundDolly
import app.winters.octo.player.immersive.isDarkInk
import app.winters.octo.player.immersive.mutedInk
import app.winters.octo.ui.common.Artwork
import app.winters.octo.ui.common.AxisDrag
import app.winters.octo.ui.common.SwipeSkip
import app.winters.octo.ui.common.detectAxisDrags
import app.winters.octo.ui.common.swipeSkip
import app.winters.octo.ui.common.AddToLibraryButton
import app.winters.octo.ui.common.LocalChoiceSheet
import app.winters.octo.ui.common.LocalHaze
import app.winters.octo.ui.common.LocalPressSpot
import app.winters.octo.ui.common.pressSpot
import app.winters.octo.ui.common.rememberOpenedBeside
import app.winters.octo.ui.common.RatingStars
import app.winters.octo.ui.menu.LocalSongMenu
import app.winters.octo.ui.menu.SongMenuContext
import app.winters.octo.ui.common.asClock
import app.winters.octo.ui.common.rememberSystemReduceMotion
import dev.chrisbanes.haze.HazeState
import dev.chrisbanes.haze.hazeSource
import dev.chrisbanes.haze.rememberHazeState
import kotlinx.coroutines.Job
import kotlinx.coroutines.delay
import kotlinx.coroutines.launch
import kotlin.math.abs

// The full player. It opens over everything, with the artwork flying in
// from the bar, and closes on back or by pulling it down. A screen reader
// finds Close player as an action on the song's name, wherever it shows,
// and on the album's. Turned sideways, the artwork sits beside the controls.
// `backdrop` is what its glass frosts, given from outside so the menus that
// open over it can frost it too.
@Composable
fun AnimatedVisibilityScope.PlayerOverlay(
    artModifier: Modifier,
    onClose: () -> Unit,
    onOpenArtist: (String) -> Unit,
    onOpenAlbum: (String) -> Unit,
    backdrop: HazeState = rememberHazeState(),
    model: PlayerViewModel = hiltViewModel(),
) {
    val now by model.now.collectAsStateWithLifecycle()
    val colors by model.colors.collectAsStateWithLifecycle()
    val prefs by model.prefs.collectAsStateWithLifecycle()
    val base by animateColorAsState(colors.base, tween(600), label = "player base")
    val ink by animateColorAsState(colors.content, tween(CoverFadeMs.toInt()), label = "player ink")
    val dolly = backgroundDolly()
    val close by rememberUpdatedState(onClose)
    val scope = rememberCoroutineScope()
    // How far the player has been pulled down, in pixels.
    var pull by remember { mutableFloatStateOf(0f) }
    var showQueue by remember { mutableStateOf(false) }
    // The sleep timer and the speed share one glass card: speed opens from
    // the timer as its next page, or on its own from the speed mark.
    var showTime by remember { mutableStateOf(false) }
    val timePages = rememberPopupPages(TimePage.Sleep)
    var showLyricsChooser by remember { mutableStateOf(false) }

    BackHandler(onBack = onClose)
    LightOnDarkBars(darkIcons = colors.content.isDarkInk)
    // The display's fastest rate while things move, handed back on close.
    val phoneCalm = rememberSystemReduceMotion()
    val powerSave = rememberPowerSave()
    val refreshNeed = playerRefreshNeed(
        playing = now.isPlaying,
        calm = prefs.reduceMotion || phoneCalm,
        powerSave = powerSave,
        movingBackgroundFps = pausedBackgroundFps(prefs, Build.VERSION.SDK_INT),
    )
    RequestDisplayRate(refreshNeed)

    BoxWithConstraints(Modifier.fillMaxSize().displayRateModifier(refreshNeed)) {
        val cap = constraints.maxHeight * 0.45f
        val pulled = (pull / cap).coerceIn(0f, 1f)
        // Fully rounded a fifth of the way down.
        val corner = 28.dp * (pulled * 5f).coerceAtMost(1f)
        Box(
            Modifier
                .fillMaxSize()
                .pointerInput(Unit) {
                    // Let go past this, holding still, and the player closes.
                    val farEnough = cap * 0.5f
                    val fling = 1_200.dp.toPx()
                    // Any upward movement at release faster than this is a change
                    // of mind: the player settles back.
                    val backUp = 150.dp.toPx()
                    awaitEachGesture {
                        // A pull down from anywhere closes the player. The sliders
                        // keep their sideways drags: whichever way the finger
                        // clearly moves first wins, and only downward counts here.
                        val down = awaitFirstDown(requireUnconsumed = false)
                        val tracker = VelocityTracker()
                        tracker.addPosition(down.uptimeMillis, down.position)
                        val start = awaitVerticalTouchSlopOrCancellation(down.id) { change, over ->
                            if (over > 0f) {
                                change.consume()
                                pull = (over * 0.82f).coerceIn(0f, cap)
                            }
                        } ?: return@awaitEachGesture
                        verticalDrag(start.id) { change ->
                            tracker.addPosition(change.uptimeMillis, change.position)
                            // A little resistance, so the sheet feels weighted.
                            pull = (pull + change.positionChange().y * 0.82f).coerceIn(0f, cap)
                            change.consume()
                        }
                        // Nothing is decided until the finger lifts: a flick down
                        // closes, moving back up keeps it open, and otherwise it
                        // closes only if pulled well down.
                        val speed = tracker.calculateVelocity().y
                        val closing = speed > fling || (speed > -backUp && pull > farEnough)
                        if (closing) {
                            close()
                        } else {
                            scope.launch { animate(pull, 0f, animationSpec = spring(0.8f, 400f)) { value, _ -> pull = value } }
                        }
                    }
                }
                // After the gesture in this chain, so the finger is tracked on the
                // screen rather than on the moving player.
                .graphicsLayer {
                    translationY = pull
                    scaleX = 1f - 0.06f * pulled
                    scaleY = 1f - 0.06f * pulled
                    shape = RoundedCornerShape(corner)
                    clip = pull > 0f
                }
                .background(base),
        ) {
            // The background is what the player's glass frosts, the way the
            // bar frosts the page.
            Box(Modifier.fillMaxSize().hazeSource(backdrop)) {
                PlayerBackground(prefs, colors, now, dolly = { dolly.value })
            }
            // The words and icons take the colour the background asks for.
            CompositionLocalProvider(LocalHaze provides backdrop, LocalContentColor provides ink) {
                PlayerContent(
                    now,
                    model,
                    artModifier,
                    onClose,
                    onOpenArtist,
                    onOpenAlbum,
                    onOpenQueue = { showQueue = true },
                    onOpenSleep = {
                        timePages.reset(TimePage.Sleep)
                        showTime = true
                    },
                    onOpenSpeed = {
                        timePages.reset(TimePage.Speed)
                        showTime = true
                    },
                    onChooseLyrics = { showLyricsChooser = true },
                )
            }
        }
        QueueSheets(model, now.shuffle, visible = showQueue, onDismiss = { showQueue = false }, backdrop = backdrop)
        LyricsChooserPanel(
            visible = showLyricsChooser,
            now = now,
            model = model,
            backdrop = backdrop,
            onDismiss = { showLyricsChooser = false },
        )
        GlassPopup(
            visible = showTime,
            anchor = rememberOpenedBeside(showTime),
            onDismiss = { showTime = false },
            backdrop = backdrop,
            title = "Sleep timer and speed",
            onBack = timePages::back,
        ) {
            PopupPager(timePages) { page, canGoBack ->
                when (page) {
                    TimePage.Sleep -> SleepPage(model, onDone = { showTime = false }, onOpenSpeed = { timePages.open(TimePage.Speed) })
                    TimePage.Speed -> SpeedPage(onBack = if (canGoBack) ({ timePages.back() }) else null)
                }
            }
        }
    }
}

// The pages of the card for time: the sleep timer, and the speed.
private enum class TimePage { Sleep, Speed }

@Composable
private fun AnimatedVisibilityScope.PlayerContent(
    now: NowPlaying,
    model: PlayerViewModel,
    artModifier: Modifier,
    onClose: () -> Unit,
    onOpenArtist: (String) -> Unit,
    onOpenAlbum: (String) -> Unit,
    onOpenQueue: () -> Unit,
    onOpenSleep: () -> Unit,
    onOpenSpeed: () -> Unit,
    onChooseLyrics: () -> Unit,
) {
    val lyricsWanted by model.lyricsOpen.collectAsStateWithLifecycle()
    // A live station has no lyrics to show.
    val lyricsOpen = lyricsWanted && now.live == null
    val prefs by model.prefs.collectAsStateWithLifecycle()
    val calm = prefs.reduceMotion || rememberSystemReduceMotion()
    // The player's own scope, so the controls still rise in as the player
    // opens wherever they are placed.
    val player = this
    val header: @Composable () -> Unit = { TopLine(now, model, onClose, onOpenAlbum) }
    val controls: @Composable (Boolean) -> Unit = { roomy ->
        with(player) { Controls(now, model, lyricsOpen, onClose, onOpenArtist, onOpenQueue, onOpenSleep, onOpenSpeed, roomy) }
    }
    val lyricsBar: @Composable () -> Unit = { LyricsBar(now, model, onChooseLyrics, onClose, Modifier.bleed(LyricsBarBleed)) }
    BoxWithConstraints(
        Modifier
            .fillMaxSize()
            .statusBarsPadding()
            .navigationBarsPadding()
            .displayCutoutPadding(),
    ) {
        val roomy = maxHeight >= 360.dp
        if (maxWidth > maxHeight) {
            // Turned sideways: the artwork on the left, everything else on
            // the right. A short screen drops the volume line; the phone's
            // own buttons still set it. In lyrics mode the lyrics take the
            // right side, over the small player, and the artwork stays.
            Row(
                Modifier.fillMaxSize().padding(horizontal = 24.dp),
                horizontalArrangement = Arrangement.spacedBy(32.dp),
                verticalAlignment = Alignment.CenterVertically,
            ) {
                ArtStage(
                    now,
                    model,
                    folded = false,
                    calm = calm,
                    maxSide = 420.dp,
                    modifier = Modifier.weight(1f).fillMaxHeight().padding(vertical = 12.dp),
                    artModifier = artModifier,
                )
                AnimatedContent(
                    targetState = lyricsOpen,
                    transitionSpec = { lyricsFold(calm, resize = false) },
                    modifier = Modifier.weight(1f).fillMaxHeight(),
                    label = "player side",
                ) { open ->
                    if (open) {
                        Column(Modifier.fillMaxSize()) {
                            header()
                            val lyrics by model.lyrics.collectAsStateWithLifecycle()
                            LyricsPane(lyrics, now, model::positionMs, model::seekTo, Modifier.weight(1f).fillMaxWidth().padding(vertical = 4.dp))
                            Box(Modifier.padding(bottom = 8.dp)) { lyricsBar() }
                        }
                    } else {
                        Column(Modifier.fillMaxSize(), verticalArrangement = Arrangement.Center) {
                            header()
                            controls(roomy)
                        }
                    }
                }
            }
        } else {
            // Upright: in lyrics mode the artwork, the song, the controls,
            // the volume and the switches fold away, and the lyrics fill
            // everything from under the top line to just above the small
            // player that takes the controls' place.
            // The artwork and the blocks keep their places either way, so
            // closing lyrics mode brings them back where they were.
            Box(Modifier.fillMaxSize().padding(horizontal = 24.dp)) {
                val shown by animateFloatAsState(
                    if (lyricsOpen) 0f else 1f,
                    if (calm) snap() else tween(if (lyricsOpen) 160 else 240, delayMillis = if (lyricsOpen) 0 else 120),
                    label = "controls shown",
                )
                with(player) {
                    UprightPlayer(
                        now, model, calm, folded = lyricsOpen, shown = { shown },
                        header = header, artModifier = artModifier,
                        onClose = onClose, onOpenArtist = onOpenArtist, onOpenQueue = onOpenQueue, onOpenSleep = onOpenSleep, onOpenSpeed = onOpenSpeed,
                    )
                }
                AnimatedVisibility(
                    visible = lyricsOpen,
                    enter = if (calm) EnterTransition.None else fadeIn(tween(240, delayMillis = 120)),
                    exit = if (calm) ExitTransition.None else fadeOut(tween(160)),
                    modifier = Modifier.align(Alignment.BottomCenter).fillMaxWidth().padding(bottom = LyricsBarGap),
                ) { lyricsBar() }
                // Laid out at their full size from the start, so the lines
                // settle where they belong while the rest folds away.
                LyricsLayer(
                    now,
                    model,
                    lyricsOpen,
                    calm,
                    Modifier.fillMaxSize().padding(top = TopLineHeight, bottom = LyricsBarHeight + LyricsBarGap),
                )
            }
        }
    }
}

// The small player reaches past the player's side margins, nearer the
// screen's edges, to give the song's name more room.
private val LyricsBarBleed = 12.dp

// The line across the top holds only the album's name, so it stays low
// and leaves the room to the artwork.
private val TopLineHeight = 40.dp

// How long the controls take to fold away as lyrics mode opens.
private const val LYRICS_FOLD_MS = 360

// Lyrics mode coming or going: the old controls fade out quickly, the new
// ones fade in once they have mostly gone, and, upright, the space they
// take eases to its new height. With reduced motion it all changes at once.
private fun AnimatedContentTransitionScope<Boolean>.lyricsFold(calm: Boolean, resize: Boolean): ContentTransform {
    if (calm) return (EnterTransition.None togetherWith ExitTransition.None).using(SizeTransform(clip = false) { _, _ -> snap() })
    val change = fadeIn(tween(240, delayMillis = 120)) togetherWith fadeOut(tween(160))
    return change.using(
        SizeTransform(clip = false) { _, _ -> if (resize) tween(LYRICS_FOLD_MS, easing = FastOutSlowInEasing) else snap() },
    )
}

// The lyrics over the upright player, fading in as the rest folds away.
@Composable
private fun LyricsLayer(now: NowPlaying, model: PlayerViewModel, open: Boolean, calm: Boolean, modifier: Modifier = Modifier) {
    val lyrics by model.lyrics.collectAsStateWithLifecycle()
    val shown by animateFloatAsState(
        if (open) 1f else 0f,
        if (calm) snap() else tween(LYRICS_FOLD_MS, delayMillis = if (open) 120 else 0),
        label = "lyrics shown",
    )
    if (shown > 0f) {
        LyricsPane(
            lyrics,
            now,
            model::positionMs,
            model::seekTo,
            modifier.padding(vertical = 8.dp).graphicsLayer { alpha = shown },
            // Out to the screen's margins, past the player's side padding.
            edgeBleed = 24.dp,
        )
    }
}

// The line across the top: the album's name, which opens the album like
// the artist does, closing the player on the way. Cast and Sound are in the
// song's menu.
@Composable
private fun TopLine(
    now: NowPlaying,
    model: PlayerViewModel,
    onClose: () -> Unit,
    onOpenAlbum: (String) -> Unit,
) {
    Box(
        Modifier.fillMaxWidth().height(TopLineHeight),
        contentAlignment = Alignment.Center,
    ) {
        val album by model.albumLabel.collectAsStateWithLifecycle()
        album?.let {
            // The name shows only for an album in the library, so there is
            // always a page to open.
            val albumId = now.albumId?.takeIf { id -> id.isNotEmpty() && now.trackId?.let(::isFind) != true }
            Text(
                it,
                style = OctoType.caption,
                color = mutedInk,
                maxLines = 1,
                overflow = TextOverflow.Ellipsis,
                textAlign = TextAlign.Center,
                modifier = Modifier
                    .padding(horizontal = 16.dp)
                    .clickable(
                        enabled = albumId != null,
                        interactionSource = null,
                        indication = null,
                        role = Role.Button,
                        onClickLabel = "Open album",
                    ) { albumId?.let(onOpenAlbum) }
                    .closesPlayer(onClose)
                    .padding(vertical = 8.dp),
            )
        }
    }
}

// The artwork. Upright, it folds away under the lyrics in lyrics mode, but
// stays laid out there, so it can still fly back to the bar when the player
// closes. Swiping the artwork sideways skips: it follows the finger a
// little way, and a tick marks the point past which letting go skips.
@Composable
private fun AnimatedVisibilityScope.ArtStage(
    now: NowPlaying,
    model: PlayerViewModel,
    folded: Boolean,
    calm: Boolean,
    maxSide: Dp,
    modifier: Modifier,
    artModifier: Modifier,
) {
    val fold by animateFloatAsState(if (folded) 1f else 0f, if (calm) snap() else tween(300), label = "art folded")
    val scope = rememberCoroutineScope()
    val haptics = LocalHapticFeedback.current
    // How far the artwork has been swiped, in pixels.
    var swipe by remember { mutableFloatStateOf(0f) }
    val liveLineupNow by rememberUpdatedState(now.live?.lineup)
    BoxWithConstraints(modifier, contentAlignment = Alignment.Center) {
        val side = min(maxSide, min(maxWidth, maxHeight))
        val width = constraints.maxWidth.toFloat()
        Box(
            Modifier
                .pointerInput(folded, width) {
                    if (folded) return@pointerInput
                    val distance = 88.dp.toPx()
                    val fling = 900.dp.toPx()
                    var armed = false
                    // A new swipe takes over from one still settling.
                    var settling: Job? = null
                    detectAxisDrags(
                        horizontal = AxisDrag(
                            onMove = { offset ->
                                settling?.cancel()
                                // Held back, so it reads as a nudge rather than a page turn.
                                swipe = offset * 0.55f
                                val past = abs(offset) >= distance
                                if (past != armed) {
                                    armed = past
                                    if (past) haptics.performHapticFeedback(HapticFeedbackType.GestureThresholdActivate)
                                }
                            },
                            onEnd = { offset, velocity ->
                                // A station at an end of its lineup has no
                                // station that way to swipe to.
                                val lineup = liveLineupNow
                                val skip = swipeSkip(offset, velocity, distance, fling).let {
                                    when {
                                        lineup == null -> it
                                        it == SwipeSkip.Next && !lineup.hasNext -> SwipeSkip.Stay
                                        it == SwipeSkip.Previous && !lineup.hasPrevious -> SwipeSkip.Stay
                                        else -> it
                                    }
                                }
                                if (skip != SwipeSkip.Stay && !armed) haptics.performHapticFeedback(HapticFeedbackType.GestureThresholdActivate)
                                armed = false
                                settling = scope.launch { settleSwipe(skip, width, { swipe }, { swipe = it }, model::next, model::previous) }
                            },
                        ),
                    )
                }
                // After the gesture in this chain, so the finger is tracked on
                // the screen rather than on the moving artwork.
                .graphicsLayer {
                    translationX = swipe
                    alpha = (1f - fold) * (1f - 0.5f * (abs(swipe) / (width * 0.5f)).coerceAtMost(1f))
                    scaleX = 1f - 0.08f * fold
                    scaleY = 1f - 0.08f * fold
                },
        ) {
            PlayerArt(now.artwork, side, now.isPlaying, artModifier)
        }
    }
}

// Finishes a swipe of the artwork. A skip carries it on out the way it was
// going, changes the song, and brings the new one in from the other side;
// otherwise it springs back.
private suspend fun settleSwipe(
    skip: SwipeSkip,
    width: Float,
    current: () -> Float,
    set: (Float) -> Unit,
    onNext: () -> Unit,
    onPrevious: () -> Unit,
) {
    if (skip == SwipeSkip.Stay) {
        animate(current(), 0f, animationSpec = spring(0.8f, 400f)) { value, _ -> set(value) }
        return
    }
    val way = if (skip == SwipeSkip.Next) -1f else 1f
    animate(current(), way * width * 0.5f, animationSpec = tween(120)) { value, _ -> set(value) }
    if (skip == SwipeSkip.Next) onNext() else onPrevious()
    animate(-way * width * 0.2f, 0f, animationSpec = spring(0.8f, 300f)) { value, _ -> set(value) }
}

// Everything under the artwork: the song, the progress line, the controls,
// the volume and the row of switches, as the sideways player stacks them.
// They rise into place a moment after the player opens. `roomy` is off
// only on a short sideways screen.
@Composable
private fun AnimatedVisibilityScope.Controls(
    now: NowPlaying,
    model: PlayerViewModel,
    lyricsOpen: Boolean,
    onClose: () -> Unit,
    onOpenArtist: (String) -> Unit,
    onOpenQueue: () -> Unit,
    onOpenSleep: () -> Unit,
    onOpenSpeed: () -> Unit,
    roomy: Boolean,
) {
    val gap = if (roomy) 12.dp else 4.dp
    Column(Modifier.then(risesIn())) {
        TitleRow(now, model, onClose, onOpenArtist)
        Spacer(Modifier.height(BarGap))
        BarBlock(now, model, onOpenSpeed)
        Spacer(Modifier.height(gap))
        Transport(now, model)
        if (roomy) {
            Spacer(Modifier.height(8.dp))
            Volume(model)
        }
        Spacer(Modifier.height(gap))
        SwitchRow(now, model, lyricsOpen, onOpenQueue, onOpenSleep)
        Spacer(Modifier.height(gap))
    }
}

// The upright player: the album line, the artwork a little under it, and
// the song's blocks under that, the height shared between them by
// playerRhythm. Each block rises into place as the player opens. In lyrics
// mode (`folded`) the artwork folds away and the blocks fade to `shown`
// and take no touches, staying laid out where they were.
@Composable
private fun AnimatedVisibilityScope.UprightPlayer(
    now: NowPlaying,
    model: PlayerViewModel,
    calm: Boolean,
    folded: Boolean,
    shown: () -> Float,
    header: @Composable () -> Unit,
    artModifier: Modifier,
    onClose: () -> Unit,
    onOpenArtist: (String) -> Unit,
    onOpenQueue: () -> Unit,
    onOpenSleep: () -> Unit,
    onOpenSpeed: () -> Unit,
) {
    val look = risesIn()
        .graphicsLayer { alpha = shown() }
        .then(if (folded) Modifier.clearAndSetSemantics { }.pointerInput(Unit) { swallowTouches() } else Modifier)
    RhythmColumn(Modifier.fillMaxSize()) {
        header()
        ArtStage(now, model, folded = folded, calm = calm, maxSide = Dp.Infinity, modifier = Modifier, artModifier = artModifier)
        Box(look) { TitleRow(now, model, onClose, onOpenArtist) }
        Box(look) { BarBlock(now, model, onOpenSpeed) }
        Box(look) { Transport(now, model) }
        Box(look) { Volume(model) }
        Box(look) { SwitchRow(now, model, false, onOpenQueue, onOpenSleep) }
    }
}

// Takes every touch before what is under it can, for controls put away.
private suspend fun androidx.compose.ui.input.pointer.PointerInputScope.swallowTouches() {
    awaitPointerEventScope {
        while (true) awaitPointerEvent(androidx.compose.ui.input.pointer.PointerEventPass.Initial).changes.forEach { it.consume() }
    }
}

// Lays out the upright player's seven parts (the album line, the artwork,
// then the five blocks under it) by playerRhythm: each block at its own
// height, the artwork square, and the gaps as the rhythm shares them. A
// volume line the rhythm leaves out is not placed.
@Composable
private fun RhythmColumn(modifier: Modifier, content: @Composable () -> Unit) {
    Layout(content, modifier) { measurables, constraints ->
        val width = constraints.maxWidth
        val height = constraints.maxHeight
        val loose = Constraints(minWidth = 0, maxWidth = width, minHeight = 0, maxHeight = Constraints.Infinity)
        val header = measurables[0].measure(loose)
        val blocks = measurables.drop(2).map { it.measure(loose) }
        val rhythm = playerRhythm(
            height = height.toDp().value,
            width = width.toDp().value,
            header = header.height.toDp().value,
            blocks = blocks.map { it.height.toDp().value },
            volumeAt = RHYTHM_VOLUME_AT,
        )
        val side = rhythm.art.dp.roundToPx()
        val art = measurables[1].measure(Constraints.fixed(side, side))
        val shown = blocks.filterIndexed { i, _ -> rhythm.volume || i != RHYTHM_VOLUME_AT }
        layout(width, height) {
            var y = 0
            header.placeRelative((width - header.width) / 2, y)
            y += header.height + rhythm.gaps[0].dp.roundToPx()
            art.placeRelative((width - side) / 2, y)
            y += side
            shown.forEachIndexed { i, block ->
                y += rhythm.gaps[i + 1].dp.roundToPx()
                block.placeRelative((width - block.width) / 2, y)
                y += block.height
            }
        }
    }
}

// Where the volume line is among the blocks under the artwork.
private const val RHYTHM_VOLUME_AT = 3

// The room between the song's name and its bar, sideways.
private val BarGap = 10.dp

// The rise and fade the controls come in with as the player opens.
@Composable
private fun AnimatedVisibilityScope.risesIn(): Modifier {
    val density = LocalDensity.current
    return Modifier.animateEnterExit(
        enter = slideInVertically(spring(0.68f, 400f, IntOffset.VisibilityThreshold)) {
            with(density) { 28.dp.roundToPx() }
        } + fadeIn(tween(380, delayMillis = 80)),
        exit = ExitTransition.None,
    )
}

// The song's name and artist with its buttons, and a line for its rating
// kept the same height whether it has one or not (and for a station), so
// the player's blocks keep their places from song to song.
@Composable
private fun TitleRow(now: NowPlaying, model: PlayerViewModel, onClose: () -> Unit, onOpenArtist: (String) -> Unit) {
    Column(Modifier.fillMaxWidth()) {
        val live = now.live
        val liveModel: LivePlayerViewModel? = if (live != null) hiltViewModel() else null
        // A station's heart and menu sit on the title's own line, centered
        // on it, their touch room reaching past it.
        val measurer = rememberTextMeasurer()
        val titleLine = with(LocalDensity.current) { remember(measurer, this) { measurer.measure("Ag", TitleStyle).size.height.toDp() } }
        Row(verticalAlignment = if (live != null) Alignment.Top else Alignment.CenterVertically) {
            Box(Modifier.weight(1f)) { TitleBlock(now, onOpenArtist, onClose) }
            if (live != null && liveModel != null) {
                Row(Modifier.height(titleLine).wrapContentHeight(unbounded = true), verticalAlignment = Alignment.CenterVertically) {
                    LiveSongButtons(live, liveModel, calm = model.prefs.collectAsStateWithLifecycle().value.reduceMotion || rememberSystemReduceMotion())
                }
            } else {
                SongButtons(now, model)
            }
        }
        Box(Modifier.padding(top = 2.dp).height(RatingLine)) {
            if (live == null) {
                // The song's rating, only once it has one.
                val rating by model.rating.collectAsStateWithLifecycle()
                RatingStars(rating, size = 12.dp)
            }
        }
    }
}

private val RatingLine = 12.dp

// The progress line with its times, or for a station the live bar, in the
// same room.
@Composable
private fun BarBlock(now: NowPlaying, model: PlayerViewModel, onOpenSpeed: () -> Unit) {
    Column(Modifier.fillMaxWidth()) {
        val live = now.live
        if (live == null) {
            Progress(now, model, onOpenSpeed)
        } else {
            val prefs by model.prefs.collectAsStateWithLifecycle()
            LiveBar(live, calm = prefs.reduceMotion || rememberSystemReduceMotion())
        }
    }
}

// The row of switches under the controls. A station has no lyrics,
// shuffle or repeat: its queue button lists the stations being surfed, and
// the sleep timer stays.
@Composable
private fun SwitchRow(now: NowPlaying, model: PlayerViewModel, lyricsOpen: Boolean, onOpenQueue: () -> Unit, onOpenSleep: () -> Unit) {
    val live = now.live
    Row(
        Modifier.fillMaxWidth(),
        horizontalArrangement = Arrangement.spacedBy(20.dp, Alignment.CenterHorizontally),
    ) {
        if (live != null) {
            if (live.lineup.shows) {
                val sheet = LocalChoiceSheet.current
                ActionButton(
                    icon = OctoIcons.Queue,
                    description = "Stations",
                    on = false,
                    onClick = { sheet.show(stationList(live.lineup, model::playAt)) },
                )
            }
            SleepCircle(model, onClick = onOpenSleep)
        } else {
            ActionButton(
                icon = OctoIcons.Lyrics,
                description = "Lyrics",
                on = lyricsOpen,
                state = if (lyricsOpen) "Showing" else "Hidden",
                onClick = model::toggleLyrics,
            )
            ActionButton(
                icon = OctoIcons.Queue,
                description = "Up next",
                on = false,
                onClick = onOpenQueue,
            )
            SleepCircle(model, onClick = onOpenSleep)
            ActionButton(
                icon = OctoIcons.Shuffle,
                description = "Shuffle",
                on = now.shuffle,
                onClick = model::toggleShuffle,
            )
            ActionButton(
                icon = if (now.repeatMode == Player.REPEAT_MODE_ONE) OctoIcons.RepeatOne else OctoIcons.Repeat,
                description = "Repeat",
                on = now.repeatMode != Player.REPEAT_MODE_OFF,
                state = when (now.repeatMode) {
                    Player.REPEAT_MODE_ALL -> "All songs"
                    Player.REPEAT_MODE_ONE -> "This song"
                    else -> "Off"
                },
                onClick = model::cycleRepeat,
            )
        }
    }
}

// How round the card's corners are, as a percentage of its side.
const val PlayerArtCorner = 3

// The artwork card. Its corners round from a circle, as it leaves the bar,
// to a soft square as it lands. It sits full size while music plays and
// settles back smaller when paused.
@Composable
private fun AnimatedVisibilityScope.PlayerArt(ref: String?, side: Dp, playing: Boolean, artModifier: Modifier) {
    val corner by transition.animateInt(label = "art corners") {
        if (it == EnterExitState.Visible) PlayerArtCorner else 50
    }
    val scale by animateFloatAsState(
        if (playing) 1f else 0.84f,
        spring(dampingRatio = 0.6f, stiffness = 300f),
        label = "art size",
    )
    val shape = RoundedCornerShape(percent = corner)
    Box(artModifier.size(side), contentAlignment = Alignment.Center) {
        Box(
            Modifier
                .graphicsLayer {
                    scaleX = scale
                    scaleY = scale
                }
                .elevation3(shape),
        ) {
            Artwork(ref, side, shape = shape, keptFirst = true)
        }
    }
}

// The song's name and artist. The name also carries Close player for a
// screen reader.
@Composable
private fun TitleBlock(now: NowPlaying, onOpenArtist: (String) -> Unit, onClose: () -> Unit) {
    AnimatedContent(
        targetState = now,
        contentKey = { it.trackId },
        transitionSpec = { fadeIn(tween(250)) togetherWith fadeOut(tween(150)) },
        label = "song title",
    ) { song ->
        Column(Modifier.fillMaxWidth()) {
            // A long title scrolls; the "E" stays put after it.
            SongTitle(
                song.title.orEmpty(),
                explicit = song.explicit,
                style = TitleStyle,
                color = LocalContentColor.current,
                markColor = accentInk,
                titleModifier = Modifier.basicMarquee().closesPlayer(onClose),
                overflow = TextOverflow.Clip,
            )
            Text(
                song.artist.orEmpty(),
                style = OctoType.body,
                color = accentInk,
                maxLines = 1,
                overflow = TextOverflow.Ellipsis,
                // A song found online has no artist in the library to open.
                modifier = Modifier.clickable(
                    enabled = !song.artistId.isNullOrEmpty(),
                    interactionSource = null,
                    indication = null,
                    role = Role.Button,
                ) { song.artistId?.takeIf { it.isNotEmpty() }?.let(onOpenArtist) },
            )
        }
    }
}

// Beside the song: a heart for Liked songs, glowing while it is in them,
// or the add button for a song not in the library, and the song's menu.
@Composable
private fun SongButtons(now: NowPlaying, model: PlayerViewModel) {
    val menu = LocalSongMenu.current
    if (now.trackId != null && isFind(now.trackId)) {
        val find by model.find.collectAsStateWithLifecycle()
        // Held back until the find for this song has loaded, not the last one.
        find?.takeIf { it.id == now.trackId }?.let { AddToLibraryButton(it, size = 44.dp, iconSize = 24.dp) }
            ?: Spacer(Modifier.size(44.dp))
    } else {
        LikeButton(model)
    }
    Box(
        Modifier
            .size(44.dp)
            // The song's menu floats beside this button.
            .pressSpot(LocalPressSpot.current)
            .clickable(interactionSource = null, indication = null, role = Role.Button) {
                now.trackId?.let { menu.open(it, SongMenuContext(fromPlayer = true)) }
            }
            .semantics { contentDescription = "More" },
        contentAlignment = Alignment.Center,
    ) {
        Icon(painterResource(OctoIcons.More), contentDescription = null, tint = LocalContentColor.current.copy(alpha = 0.6f), modifier = Modifier.size(24.dp))
    }
}

@Composable
private fun LikeButton(model: PlayerViewModel) {
    val liked by model.liked.collectAsStateWithLifecycle()
    // The heart beats once as a song is liked.
    val pulse = rememberIconAccent(IconAccent.Pulse)
    Box(
        Modifier
            .size(44.dp)
            .clickable(interactionSource = null, indication = null, role = Role.Button) {
                if (!liked) pulse.play()
                model.toggleLike()
            }
            .semantics {
                contentDescription = "Like"
                stateDescription = if (liked) "In Liked songs" else "Not in Liked songs"
            },
        contentAlignment = Alignment.Center,
    ) {
        GlowIcon(
            painterResource(if (liked) OctoIcons.Liked else OctoIcons.Like),
            tint = if (liked) LocalContentColor.current else LocalContentColor.current.copy(alpha = 0.6f),
            lit = liked,
            modifier = Modifier.size(24.dp),
            accent = pulse,
        )
    }
}

@Composable
private fun Progress(now: NowPlaying, model: PlayerViewModel, onOpenSpeed: () -> Unit) {
    val prefs by model.prefs.collectAsStateWithLifecycle()
    val position = rememberPositionMs(now, model::positionMs)
    val duration = now.durationMs.coerceAtLeast(0)
    // The line moves every frame, but the times only change once a second,
    // so only they recompose, and only then.
    val playedSeconds by remember(duration) {
        derivedStateOf { (position.longValue.coerceIn(0, duration) / 1000).toInt() }
    }
    val times = OctoType.caption.copy(fontFeatureSettings = "tnum")
    LineSlider(
        fraction = { now.fractionAt(position.longValue) },
        onSeek = { fraction ->
            val target = (fraction * now.durationMs).toLong()
            position.longValue = target
            model.seekTo(target)
        },
        color = LocalContentColor.current,
        trackColor = LocalContentColor.current.copy(alpha = 0.24f),
    )
    Box(Modifier.fillMaxWidth().heightIn(min = TimesRoom).offset(y = (-8).dp)) {
        Text(playedSeconds.asClock(), style = times, color = mutedInk, modifier = Modifier.align(Alignment.CenterStart))
        Row(
            Modifier.align(Alignment.Center),
            horizontalArrangement = Arrangement.spacedBy(8.dp),
            verticalAlignment = Alignment.CenterVertically,
        ) {
            now.quality?.let { QualityBadge(it, Modifier) }
            // The speed, only while it is not normal. A tap opens its sheet.
            if (prefs.speed != 1f) SpeedMark(prefs.speed, onOpenSpeed)
        }
        Text(
            "-" + ((duration / 1000).toInt() - playedSeconds).coerceAtLeast(0).asClock(),
            style = times,
            color = mutedInk,
            modifier = Modifier.align(Alignment.CenterEnd),
        )
    }
}

// What kind of file is playing, as a small glazed label: a waveform mark
// and "LOSSLESS" or "HI-RES" for lossless files, or just the format, like
// "OPUS". A tap shows everything, like "FLAC · 24-bit · 48 kHz", for a few
// seconds.
@Composable
private fun QualityBadge(quality: AudioQuality, modifier: Modifier) {
    var open by remember(quality) { mutableStateOf(false) }
    LaunchedEffect(open) {
        if (open) {
            delay(4_000)
            open = false
        }
    }
    Glaze(
        modifier
            .height(24.dp)
            .clickable(interactionSource = null, indication = null, role = Role.Button) { open = !open }
            .clearAndSetSemantics { contentDescription = "${quality.label}, ${quality.full}" },
        backdrop = LocalHaze.current,
        film = GlazeClearFilm,
    ) {
        Row(
            Modifier.animateContentSize(spring(0.8f, 400f)).padding(horizontal = 10.dp),
            verticalAlignment = Alignment.CenterVertically,
        ) {
            if (quality.lossless) {
                Icon(
                    painterResource(OctoIcons.Lossless),
                    contentDescription = null,
                    tint = LocalContentColor.current,
                    modifier = Modifier.padding(end = 5.dp).size(13.dp),
                )
            }
            Text(
                if (open) quality.full else quality.label.uppercase(),
                style = if (open) BadgeDetail else BadgeLabel,
                color = LocalContentColor.current,
                maxLines = 1,
            )
        }
    }
}

// A small "1.25x" beside the quality label while music plays at another speed.
@Composable
private fun SpeedMark(speed: Float, onClick: () -> Unit) {
    Text(
        speedLabel(speed),
        style = BadgeLabel.copy(fontFeatureSettings = "tnum", letterSpacing = 0.sp),
        color = LocalContentColor.current,
        maxLines = 1,
        modifier = Modifier
            .clickable(interactionSource = null, indication = null, role = Role.Button, onClick = onClick)
            .padding(horizontal = 4.dp, vertical = 4.dp)
            .semantics { contentDescription = "Playback speed ${speedLabel(speed)}" },
    )
}

private val BadgeLabel = OctoType.caption.copy(fontSize = 10.5.sp, fontWeight = FontWeight.SemiBold, letterSpacing = 1.sp)
private val BadgeDetail = OctoType.caption.copy(fontSize = 11.sp)

@Composable
private fun Transport(now: NowPlaying, model: PlayerViewModel) {
    Row(
        Modifier.fillMaxWidth(),
        horizontalArrangement = Arrangement.SpaceEvenly,
        verticalAlignment = Alignment.CenterVertically,
    ) {
        val live = now.live
        if (live != null) {
            // A station stops and plays again live; Back and Next change
            // station, while there are others in its list, up to its ends.
            val lineup = live.lineup
            if (lineup.shows) {
                TransportButton(OctoIcons.Previous, "Previous station", 44.dp, model::previous, nudge = (-8).dp, enabled = lineup.hasPrevious)
            }
            TransportButton(
                if (now.playWhenReady) LiveStopIcon else OctoIcons.Play,
                if (now.playWhenReady) "Stop" else "Play",
                56.dp,
                model::togglePlayPause,
            )
            if (lineup.shows) {
                TransportButton(OctoIcons.Next, "Next station", 44.dp, model::next, nudge = 8.dp, enabled = lineup.hasNext)
            }
        } else {
            TransportButton(OctoIcons.Previous, "Previous", 44.dp, model::previous, nudge = (-8).dp)
            TransportButton(
                if (now.isPlaying) OctoIcons.Pause else OctoIcons.Play,
                if (now.isPlaying) "Pause" else "Play",
                56.dp,
                model::togglePlayPause,
            )
            TransportButton(OctoIcons.Next, "Next", 44.dp, model::next, nudge = 8.dp)
        }
    }
}

// The phone's media volume, quiet on the left and loud on the right. It
// follows the volume buttons too.
@Composable
private fun Volume(model: PlayerViewModel) {
    val volume by model.volume.collectAsStateWithLifecycle()
    Row(Modifier.fillMaxWidth(), verticalAlignment = Alignment.CenterVertically) {
        Icon(painterResource(OctoIcons.VolumeDown), contentDescription = null, tint = mutedInk, modifier = Modifier.size(20.dp))
        LineSlider(
            fraction = { volume },
            onSeek = model::setVolume,
            live = true,
            modifier = Modifier
                .weight(1f)
                .padding(horizontal = 10.dp)
                .semantics { contentDescription = "Volume" },
            color = LocalContentColor.current.copy(alpha = 0.85f),
            trackColor = LocalContentColor.current.copy(alpha = 0.24f),
        )
        Icon(painterResource(OctoIcons.VolumeUp), contentDescription = null, tint = mutedInk, modifier = Modifier.size(20.dp))
    }
}

// A play control that answers the finger: it gives a little under a press
// and springs back, back and next nudge the way they go, and play and pause
// pop from one to the other.
@Composable
private fun TransportButton(
    @DrawableRes icon: Int,
    description: String,
    iconSize: Dp,
    onClick: () -> Unit,
    nudge: Dp = 0.dp,
    enabled: Boolean = true,
) {
    val interaction = remember { MutableInteractionSource() }
    val pressed by interaction.collectIsPressedAsState()
    val press by animateFloatAsState(if (pressed) 0.82f else 1f, spring(0.45f, 600f), label = "press")
    val shift = remember { Animatable(0f) }
    val scope = rememberCoroutineScope()
    Box(
        Modifier
            .size(72.dp)
            .alpha(if (enabled) 1f else 0.3f)
            .clickable(interactionSource = interaction, indication = null, enabled = enabled, role = Role.Button) {
                onClick()
                if (nudge != 0.dp) {
                    scope.launch {
                        shift.animateTo(1f, tween(90))
                        shift.animateTo(0f, spring(0.5f, 400f))
                    }
                }
            }
            .semantics { contentDescription = description },
        contentAlignment = Alignment.Center,
    ) {
        AnimatedContent(
            targetState = icon,
            transitionSpec = {
                (fadeIn(tween(150)) + scaleIn(tween(150), initialScale = 0.6f)) togetherWith
                    (fadeOut(tween(100)) + scaleOut(tween(100), targetScale = 0.6f))
            },
            label = "transport icon",
        ) { shown ->
            Icon(
                painterResource(shown),
                contentDescription = null,
                tint = LocalContentColor.current,
                modifier = Modifier
                    .size(iconSize)
                    .graphicsLayer {
                        scaleX = press
                        scaleY = press
                        translationX = shift.value * nudge.toPx()
                    },
            )
        }
    }
}

// What a screen reader offers to close the player with. There is no close
// button: the player closes on back and by pulling it down, and this action
// sits on the song's name, the album's and the small player's song.
internal const val CLOSE_PLAYER = "Close player"

internal fun closePlayerActions(onClose: () -> Unit): List<CustomAccessibilityAction> =
    listOf(
        CustomAccessibilityAction(CLOSE_PLAYER) {
            onClose()
            true
        },
    )

internal fun Modifier.closesPlayer(onClose: () -> Unit): Modifier = semantics { customActions = closePlayerActions(onClose) }

// One of the buttons under the controls: a plain icon, bright white and
// glowing while its setting is on and dimmed while off, the way the
// progress line glows where it has played.
@Composable
private fun ActionButton(
    @DrawableRes icon: Int,
    description: String,
    on: Boolean,
    onClick: () -> Unit,
    state: String? = null,
) {
    Box(
        Modifier
            .size(44.dp)
            .clickable(interactionSource = null, indication = null, role = Role.Button, onClick = onClick)
            .semantics {
                contentDescription = description
                stateDescription = state ?: if (on) "On" else "Off"
            },
        contentAlignment = Alignment.Center,
    ) {
        GlowIcon(
            painterResource(icon),
            tint = if (on) LocalContentColor.current else LocalContentColor.current.copy(alpha = 0.45f),
            lit = on,
            modifier = Modifier.size(22.dp),
        )
    }
}

@Composable
private fun SleepCircle(model: PlayerViewModel, onClick: () -> Unit) {
    val sleep by model.sleep.collectAsStateWithLifecycle()
    val minutes = (sleep as? SleepState.Counting)?.let { ((it.remainingMs + 59_999) / 60_000).toInt() }
    Box {
        ActionButton(
            icon = OctoIcons.SleepTimer,
            description = "Sleep timer",
            on = sleep != SleepState.Off,
            state = when {
                minutes != null -> "$minutes min left"
                else -> sleepSummary(sleep)
            },
            onClick = onClick,
        )
        if (minutes != null) {
            GlazeInset(
                fill = AccentFill,
                shape = CircleShape,
                modifier = Modifier
                    .align(Alignment.TopEnd)
                    .offset(x = 6.dp, y = (-4).dp)
                    .height(18.dp)
                    .clearAndSetSemantics { },
            ) {
                Text(
                    "$minutes",
                    style = OctoType.caption.copy(fontSize = 10.sp, fontWeight = FontWeight.SemiBold, fontFeatureSettings = "tnum"),
                    color = Color.White,
                    modifier = Modifier.padding(horizontal = 6.dp),
                )
            }
        }
    }
}

// Light status and navigation icons while the player is open (dark ones
// over a light background), whatever the rest of the app uses, put back
// as they were when it closes.
@Composable
private fun LightOnDarkBars(darkIcons: Boolean) {
    val view = LocalView.current
    DisposableEffect(view) {
        val window = view.context.findActivity()?.window ?: return@DisposableEffect onDispose { }
        val bars = WindowCompat.getInsetsController(window, view)
        val status = bars.isAppearanceLightStatusBars
        val navigation = bars.isAppearanceLightNavigationBars
        onDispose {
            bars.isAppearanceLightStatusBars = status
            bars.isAppearanceLightNavigationBars = navigation
        }
    }
    LaunchedEffect(view, darkIcons) {
        val window = view.context.findActivity()?.window ?: return@LaunchedEffect
        val bars = WindowCompat.getInsetsController(window, view)
        bars.isAppearanceLightStatusBars = darkIcons
        bars.isAppearanceLightNavigationBars = darkIcons
    }
}

private tailrec fun Context.findActivity(): Activity? = when (this) {
    is Activity -> this
    is ContextWrapper -> baseContext.findActivity()
    else -> null
}

// The song's name in the player.
private val TitleStyle = OctoType.title.copy(fontWeight = FontWeight.Bold)
