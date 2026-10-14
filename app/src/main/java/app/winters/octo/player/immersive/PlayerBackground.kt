package app.winters.octo.player.immersive

import android.os.Build
import android.os.SystemClock
import androidx.compose.animation.Crossfade
import androidx.compose.animation.animateColorAsState
import androidx.compose.animation.core.animateFloatAsState
import androidx.compose.animation.core.tween
import androidx.compose.foundation.Image
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.remember
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.alpha
import androidx.compose.ui.draw.blur
import androidx.compose.ui.draw.BlurredEdgeTreatment
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.asImageBitmap
import androidx.compose.ui.graphics.graphicsLayer
import androidx.compose.ui.graphics.toArgb
import androidx.compose.ui.layout.ContentScale
import androidx.compose.ui.unit.dp
import androidx.hilt.lifecycle.viewmodel.compose.hiltViewModel
import androidx.lifecycle.ViewModel
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import androidx.lifecycle.viewModelScope
import app.winters.octo.ui.common.rememberSystemReduceMotion
import app.winters.octo.catalog.ArtworkRef
import app.winters.octo.catalog.SourceDao
import app.winters.octo.catalog.songDetails
import app.winters.octo.playback.NowPlaying
import app.winters.octo.playback.PlaybackConnection
import app.winters.octo.playback.isWebPicture
import app.winters.octo.playback.stationArtOf
import app.winters.octo.player.ArtworkPalette
import app.winters.octo.player.LiveBackgroundSupported
import app.winters.octo.player.MeshBackground
import app.winters.octo.player.PlayerColors
import app.winters.octo.player.PlayerPrefs
import app.winters.octo.player.PlayerSettings
import app.winters.octo.ui.common.artworkRequest
import coil3.compose.AsyncImage
import coil3.compose.LocalPlatformContext
import dagger.hilt.android.lifecycle.HiltViewModel
import kotlinx.coroutines.ExperimentalCoroutinesApi
import kotlinx.coroutines.flow.SharingStarted
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.combine
import kotlinx.coroutines.flow.distinctUntilChanged
import kotlinx.coroutines.flow.filterNotNull
import kotlinx.coroutines.flow.map
import kotlinx.coroutines.flow.mapLatest
import kotlinx.coroutines.flow.stateIn
import javax.inject.Inject

// What the background needs beyond the player's colours: the song's
// tempo and its prepared cover. Both are only worked out while a
// background that uses them is showing.
@OptIn(ExperimentalCoroutinesApi::class)
@HiltViewModel
class BackgroundViewModel @Inject constructor(
    playback: PlaybackConnection,
    settings: PlayerSettings,
    palette: ArtworkPalette,
    sources: SourceDao,
    artwork: WashArtwork,
) : ViewModel() {
    // The song's beats a minute, from its files' tags or its server, when
    // any copy has one.
    val bpm: StateFlow<Int?> = playback.now
        .map { it.trackId }
        .distinctUntilChanged()
        .mapLatest { id -> id?.let { songDetails(sources.copies(it)).bpm } }
        .stateIn(viewModelScope, SharingStarted.WhileSubscribed(5_000), null)

    // The song's cover made ready, following the artwork (not the song, so
    // an album plays through without a fade) and the adjustments.
    val cover: StateFlow<WashCover?> = combine(
        playback.now.map { it.artwork }.distinctUntilChanged(),
        settings.prefs.map { it.background.tuning }.distinctUntilChanged(),
    ) { ref, tuning -> ref to tuning }
        .mapLatest { (ref, tuning) -> runCatching { artwork.prepare(ref, palette.colorsFor(ref), tuning) }.getOrNull() }
        .filterNotNull()
        .stateIn(viewModelScope, SharingStarted.WhileSubscribed(5_000), null)
}

// The background mode actually drawn on this phone: the moving wash needs
// Android 13, so older phones show the still artwork in its place.
fun drawnMode(mode: BackgroundMode, sdk: Int): BackgroundMode =
    if (mode == BackgroundMode.Default && sdk < Build.VERSION_CODES.TIRAMISU) BackgroundMode.Artwork else mode

// The frame limit of the background while it moves even with the music
// paused (the live wash), or null when it is still or moves only while
// music plays.
fun pausedBackgroundFps(prefs: PlayerPrefs, sdk: Int): Int? =
    if (prefs.liveBackground && drawnMode(prefs.background.mode, sdk) == BackgroundMode.Default) prefs.background.fps else null

// The full player's background, by the chosen mode. `dolly` is read only
// while drawing, for the way in and out.
@Composable
fun PlayerBackground(
    prefs: PlayerPrefs,
    colors: PlayerColors,
    now: NowPlaying,
    dolly: () -> Float,
    vm: BackgroundViewModel = hiltViewModel(),
) {
    val background = prefs.background
    // Dimmed over the base as far as the words need (`PlayerColors.show`).
    val show by animateFloatAsState(colors.show, tween(CoverFadeMs.toInt(), easing = EaseInOutCubicCurve), label = "background show")
    Box(Modifier.fillMaxSize().graphicsLayer { alpha = show }) { DrawnBackground(prefs, colors, now, dolly, vm) }
}

// The background itself, by the mode this phone draws.
@Composable
private fun DrawnBackground(prefs: PlayerPrefs, colors: PlayerColors, now: NowPlaying, dolly: () -> Float, vm: BackgroundViewModel) {
    val background = prefs.background
    when (drawnMode(background.mode, Build.VERSION.SDK_INT)) {
        BackgroundMode.Default -> {
            val cover by vm.cover.collectAsStateWithLifecycle()
            val bpm by vm.bpm.collectAsStateWithLifecycle()
            val still = !prefs.liveBackground || prefs.reduceMotion || rememberSystemReduceMotion()
            ImmersiveWash(cover, paceBpm(bpm, background.useBpm), background.fps, background.speed / 100f, moving = !still, dolly = dolly)
        }
        BackgroundMode.Artwork -> {
            val cover by vm.cover.collectAsStateWithLifecycle()
            StillArtwork(cover, dolly)
        }
        BackgroundMode.Colour -> ColourFill(colors, background)
        BackgroundMode.Classic -> {
            if (prefs.liveBackground && LiveBackgroundSupported) {
                MeshBackground(colors, now.isPlaying)
            } else {
                ClassicArtwork(now.artwork)
            }
        }
    }
}

// The prepared cover, blurred and still. Covers fade into each other the
// way the wash's do.
@Composable
fun StillArtwork(cover: WashCover?, dolly: () -> Float) {
    val timing = remember { CoverFade() }
    val fadeMs = remember(cover) { if (cover == null) 0L else timing.start(SystemClock.uptimeMillis()) }
    Crossfade(cover, animationSpec = tween(fadeMs.toInt(), easing = EaseInOutCubicCurve), label = "still artwork") { shown ->
        if (shown != null) {
            val blurred = shown.stillBlurred
            Image(
                (blurred ?: shown.square).asImageBitmap(),
                contentDescription = null,
                contentScale = ContentScale.Crop,
                modifier = Modifier
                    .fillMaxSize()
                    // A little oversized, so the way in never shows an edge.
                    .graphicsLayer {
                        val scale = StillOverscan * dollyScale(dolly())
                        scaleX = scale
                        scaleY = scale
                    }
                    .then(if (blurred == null) Modifier.blur(StillBlur, BlurredEdgeTreatment.Rectangle) else Modifier),
            )
        }
    }
}

private const val StillOverscan = 1.12f
private val StillBlur = 80.dp

// A flat fill of the artwork's main colour, adjusted like the covers.
@Composable
private fun ColourFill(colors: PlayerColors, background: BackgroundPrefs) {
    val target = colors.dominant?.let { Color(prepareColor(it.toArgb(), background.tuning)) } ?: colors.base
    val fill by animateColorAsState(target, tween(CoverFadeMs.toInt(), easing = EaseInOutCubicCurve), label = "colour fill")
    Box(Modifier.fillMaxSize().background(fill))
}

// The song's own artwork, blurred into a wash of its colours: the classic
// background when it is not moving or the phone cannot draw the mesh. A
// live station washes in its song's artwork, else its logo.
@Composable
private fun ClassicArtwork(ref: String?) {
    val context = LocalPlatformContext.current
    val model = remember(ref) {
        ArtworkRef.decode(ref)?.let { artworkRequest(context, it) }
            ?: stationArtOf(ref)?.let { art ->
                art.pictures.firstOrNull()?.let { picture ->
                    ArtworkRef.decode(picture)?.let { artworkRequest(context, it) } ?: picture.takeIf(::isWebPicture)
                }
            }
    }
    if (model != null) {
        AsyncImage(
            model = model,
            contentDescription = null,
            contentScale = ContentScale.Crop,
            modifier = Modifier.fillMaxSize().blur(80.dp).alpha(0.6f),
        )
    }
}
