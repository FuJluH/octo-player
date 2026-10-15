package app.winters.octo.animated

import android.view.SurfaceHolder
import android.view.SurfaceView
import androidx.annotation.OptIn
import androidx.compose.animation.core.Animatable
import androidx.compose.animation.core.tween
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.BoxWithConstraints
import androidx.compose.runtime.Composable
import androidx.compose.runtime.DisposableEffect
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.key
import androidx.compose.runtime.mutableFloatStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberUpdatedState
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clipToBounds
import androidx.compose.ui.graphics.graphicsLayer
import androidx.compose.ui.layout.layout
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.unit.Constraints
import androidx.compose.ui.viewinterop.AndroidView
import androidx.media3.common.PlaybackException
import androidx.media3.common.Player
import androidx.media3.common.VideoSize
import androidx.media3.common.util.UnstableApi
import app.winters.octo.subsonic.AnimatedClip
import dagger.hilt.EntryPoint
import dagger.hilt.InstallIn
import dagger.hilt.android.EntryPointAccessors
import dagger.hilt.components.SingletonComponent
import kotlinx.coroutines.delay
import kotlin.math.roundToInt

// How long a loop held out of sight keeps its player: past this it lets the
// player go, and the still shows until it is seen again.
private const val HOLD_KEEP_MS = 20_000L

// How long the space a loop fills is left to settle before its version is
// picked.
private const val SIZE_SETTLE_MS = 120L

@EntryPoint
@InstallIn(SingletonComponent::class)
interface LoopPlayersEntry {
    fun loopPlayers(): LoopPlayers
}

// A loop of animated art filling its space, scaled to cover it (cut at the
// sides, never bars): the still (`still`, the poster or the cover) shows
// first, and the loop fades in over it only once its first frame is drawn,
// so there is never a black frame. Held, it stops on the frame it was on;
// with `play` StillOnly, or with no clip, only the still shows and no
// player is made. A new clip fades back to the still over the old loop's
// last frame before its own loop comes in.
@Composable
fun LoopVideo(
    clip: AnimatedClip?,
    play: LoopPlay,
    modifier: Modifier = Modifier,
    still: @Composable () -> Unit,
) {
    // Let go of after a while out of sight.
    var letGo by remember(clip) { mutableStateOf(false) }
    LaunchedEffect(clip, play) {
        if (play == LoopPlay.Hold) {
            delay(HOLD_KEEP_MS)
            letGo = true
        } else {
            letGo = false
        }
    }
    val wanted = clip?.takeIf { play != LoopPlay.StillOnly && !letGo }
    // The clip the player is for, which follows `wanted` once the still is
    // back over the old one.
    var playing by remember { mutableStateOf<AnimatedClip?>(null) }
    var drawn by remember { mutableStateOf(false) }
    val shown = remember { Animatable(0f) }
    val seen by rememberUpdatedState(play == LoopPlay.Play)
    LaunchedEffect(wanted) {
        if (playing == wanted) return@LaunchedEffect
        if (shown.value > 0f) {
            if (seen) shown.animateTo(0f, tween(LOOP_FADE_MS)) else shown.snapTo(0f)
        }
        drawn = false
        playing = wanted
    }
    LaunchedEffect(drawn, play) {
        when {
            !drawn -> shown.snapTo(0f)
            play == LoopPlay.Play -> shown.animateTo(1f, tween(LOOP_FADE_MS))
        }
    }
    BoxWithConstraints(modifier.clipToBounds()) {
        val width = constraints.maxWidth
        val height = constraints.maxHeight
        playing?.let { loop ->
            key(loop) { LoopSurface(loop, width, height, play, onDrawn = { drawn = it }) }
        }
        Box(Modifier.matchParentSize().graphicsLayer { alpha = 1f - shown.value }) { still() }
    }
}

// The loop's player and the surface it draws on, sized to cover the space.
// `onDrawn` hears true once a frame is on the surface, and false when the
// surface goes (the app put away, say) until a frame is drawn again.
@OptIn(UnstableApi::class)
@Composable
private fun LoopSurface(clip: AnimatedClip, width: Int, height: Int, play: LoopPlay, onDrawn: (Boolean) -> Unit) {
    val context = LocalContext.current
    val players = remember(context) { EntryPointAccessors.fromApplication(context.applicationContext, LoopPlayersEntry::class.java).loopPlayers() }
    val player = remember(clip) { players.create() }
    val drawn by rememberUpdatedState(onDrawn)
    var aspect by remember(clip) { mutableFloatStateOf(if (clip.width > 0 && clip.height > 0) clip.width.toFloat() / clip.height else 1f) }
    DisposableEffect(player) {
        val listener = object : Player.Listener {
            override fun onRenderedFirstFrame() = drawn(true)

            override fun onVideoSizeChanged(videoSize: VideoSize) {
                if (videoSize.width > 0 && videoSize.height > 0) {
                    aspect = videoSize.width * videoSize.pixelWidthHeightRatio / videoSize.height
                }
            }

            // A loop that cannot play leaves the still showing.
            override fun onPlayerError(error: PlaybackException) = drawn(false)
        }
        player.addListener(listener)
        onDispose {
            player.removeListener(listener)
            player.release()
            drawn(false)
        }
    }
    // The version is picked once, for the size the space settles at (it
    // may still be growing as the player opens).
    val space by rememberUpdatedState(width to height)
    LaunchedEffect(player) {
        delay(SIZE_SETTLE_MS)
        val (w, h) = space
        if (w <= 0 || h <= 0) return@LaunchedEffect
        val source = players.sourceFor(clip, w, h) ?: return@LaunchedEffect
        player.setMediaSource(source)
        player.prepare()
    }
    LaunchedEffect(player, play) { player.playWhenReady = play == LoopPlay.Play }
    // A surface of its own: the loop's frames go straight to the screen,
    // with no frame of the app's window drawn for them. Its hole in the
    // window follows the clip above it, so rounded corners hold.
    AndroidView(
        factory = { viewContext ->
            SurfaceView(viewContext).also { view ->
                view.holder.addCallback(object : SurfaceHolder.Callback {
                    override fun surfaceCreated(holder: SurfaceHolder) = Unit
                    override fun surfaceChanged(holder: SurfaceHolder, format: Int, width: Int, height: Int) = Unit
                    override fun surfaceDestroyed(holder: SurfaceHolder) = drawn(false)
                })
                player.setVideoSurfaceView(view)
            }
        },
        modifier = Modifier.covering(aspect),
        onRelease = { view -> player.clearVideoSurfaceView(view) },
    )
}

// Measured to cover the space at `aspect` (width over height), centered,
// reaching past the space's edges on one side when the shapes differ.
private fun Modifier.covering(aspect: Float): Modifier = layout { measurable, constraints ->
    val width = constraints.maxWidth
    val height = constraints.maxHeight
    val (w, h) = coverSize(width, height, aspect)
    val placeable = measurable.measure(Constraints.fixed(w, h))
    layout(width, height) { placeable.place((width - w) / 2, (height - h) / 2) }
}

// The size, at `aspect`, that covers `width` by `height` with the least
// cut away.
internal fun coverSize(width: Int, height: Int, aspect: Float): Pair<Int, Int> {
    if (width <= 0 || height <= 0 || aspect <= 0f) return width to height
    return if (width.toFloat() / height > aspect) {
        width to (width / aspect).roundToInt()
    } else {
        (height * aspect).roundToInt() to height
    }
}
