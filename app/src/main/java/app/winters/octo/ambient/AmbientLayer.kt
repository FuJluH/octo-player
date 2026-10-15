package app.winters.octo.ambient

import android.graphics.RuntimeShader
import android.os.Build
import androidx.annotation.RequiresApi
import androidx.compose.animation.animateColorAsState
import androidx.compose.animation.core.animateFloatAsState
import androidx.compose.animation.core.tween
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.DisposableEffect
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.Stable
import androidx.compose.runtime.State
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableFloatStateOf
import androidx.compose.runtime.mutableStateMapOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.produceState
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.runtime.staticCompositionLocalOf
import androidx.compose.runtime.withFrameNanos
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.draw.drawBehind
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.ShaderBrush
import androidx.compose.ui.graphics.compositeOver
import androidx.compose.ui.graphics.drawscope.DrawScope
import androidx.compose.ui.graphics.graphicsLayer
import androidx.compose.ui.graphics.toArgb
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.hilt.lifecycle.viewmodel.compose.hiltViewModel
import androidx.lifecycle.Lifecycle
import androidx.lifecycle.ViewModel
import androidx.lifecycle.compose.LocalLifecycleOwner
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import androidx.lifecycle.repeatOnLifecycle
import androidx.lifecycle.viewModelScope
import androidx.navigation3.runtime.NavKey
import app.winters.octo.design.GlazeTint
import app.winters.octo.design.OctoColors
import app.winters.octo.design.OctoType
import app.winters.octo.playback.NowPlaying
import app.winters.octo.playback.PlaybackConnection
import app.winters.octo.player.ArtworkPalette
import app.winters.octo.player.MESH
import app.winters.octo.player.PlayerColors
import app.winters.octo.player.PlayerSettings
import app.winters.octo.ui.common.rememberSystemReduceMotion
import app.winters.octo.ui.common.delayToNextTick
import dagger.hilt.android.lifecycle.HiltViewModel
import kotlinx.coroutines.delay
import kotlinx.coroutines.flow.SharingStarted
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.distinctUntilChanged
import kotlinx.coroutines.flow.map
import kotlinx.coroutines.flow.stateIn
import kotlinx.coroutines.launch
import javax.inject.Inject

// How long one song's colours take to become the next's.
private const val CrossfadeMs = 800

// The glow drifts at a fifth of the player's pace. A field this faint and
// soft changes under any one pixel by about a level of brightness a second
// at the subtle strength (twice that at the rich one), so it redraws once a
// second, or twice when rich: a step that small never shows. It steps on
// whole seconds of the clock, with the bar's ring, so the two share frames.
private const val DriftSpeed = 0.2f

fun driftFrameMs(alpha: Float): Long = if (alpha > ambientAlpha(AmbientStrength.Subtle)) 500L else 1_000L

// Toward the bottom the glow fades to 60%, so the lists and the bar sit on
// the quietest part.
private val BottomFade = Brush.verticalGradient(
    0.35f to Color.Transparent,
    1f to OctoColors.Background.copy(alpha = 0.4f),
)

// The settings and colours the glow is made from.
@HiltViewModel
class AmbienceViewModel @Inject constructor(
    private val settings: PlayerSettings,
    private val palette: ArtworkPalette,
    playback: PlaybackConnection,
) : ViewModel() {
    // Null until read, so a glow that was turned off never flashes up.
    val prefs: StateFlow<AmbientPrefs?> = settings.prefs
        .map<_, AmbientPrefs?> { it.ambient }
        .distinctUntilChanged()
        .stateIn(viewModelScope, SharingStarted.WhileSubscribed(5_000), null)

    val now: StateFlow<NowPlaying> = playback.now

    // Octo's own Reduce motion, beside the phone's.
    val reduceMotion: StateFlow<Boolean> = settings.prefs
        .map { it.reduceMotion }
        .distinctUntilChanged()
        .stateIn(viewModelScope, SharingStarted.WhileSubscribed(5_000), false)

    // The same colours the full player uses, from the same cache.
    suspend fun colorsFor(artwork: String?): PlayerColors = palette.colorsFor(artwork)

    fun setStrength(strength: AmbientStrength) {
        viewModelScope.launch { settings.setAmbientStrength(strength) }
    }

    fun setArea(area: AmbientArea, on: Boolean) {
        viewModelScope.launch { settings.setAmbientArea(area, on) }
    }

    fun setBar(on: Boolean) {
        viewModelScope.launch { settings.setAmbientBar(on) }
    }

    fun setPageArtwork(on: Boolean) {
        viewModelScope.launch { settings.setAmbientPageArtwork(on) }
    }
}

// The artwork each open album or artist page shows, by its route, so the
// glow behind the page on top can follow it.
@Stable
class PageArtworks {
    internal val artworks = mutableStateMapOf<NavKey, String>()

    fun artworkFor(route: NavKey?): String? = route?.let { artworks[it] }
}

val LocalPageArtworks = staticCompositionLocalOf<PageArtworks?> { null }

// Called by an album or artist page with its own cover, for the glow.
@Composable
fun PageArtwork(route: NavKey, artwork: String?) {
    val pages = LocalPageArtworks.current ?: return
    DisposableEffect(pages, route, artwork) {
        if (artwork != null) pages.artworks[route] = artwork
        onDispose {
            if (pages.artworks[route] == artwork) pages.artworks.remove(route)
        }
    }
}

// The glow behind every page: the artwork's colours, faint and dark, above
// the plain background and under the page. It drifts only while music plays,
// the app is in view and nothing covers it (awake), and never when the
// phone's animations are off.
@Composable
fun AmbientBackdrop(
    route: NavKey?,
    now: NowPlaying,
    pages: PageArtworks,
    awake: Boolean,
    vm: AmbienceViewModel = hiltViewModel(),
) {
    val prefs by vm.prefs.collectAsStateWithLifecycle()
    val source = ambientSource(prefs, route, pages.artworkFor(route), now.trackId != null, now.artwork)
    // Kept through a turn to none, so the old colours fade out as they are.
    val colors by produceState<PlayerColors?>(null, source) {
        when (source) {
            AmbientSource.None -> Unit
            is AmbientSource.Playing -> value = vm.colorsFor(source.artwork)
            is AmbientSource.Page -> value = vm.colorsFor(source.artwork)
        }
    }
    val strength = if (source == AmbientSource.None) 0f else ambientAlpha(prefs?.strength ?: AmbientStrength.Off)
    val appCalm by vm.reduceMotion.collectAsStateWithLifecycle()
    val reduceMotion = rememberSystemReduceMotion() || appCalm
    AmbientField(colors, strength, moving = awake && now.isPlaying && !reduceMotion)
}

// The film for the floating bar's glass: the plain one, or with a trace of
// the song's main colour when the bar is chosen to glow.
@Composable
fun rememberBarFilm(now: NowPlaying, vm: AmbienceViewModel = hiltViewModel()): State<Color> {
    val prefs by vm.prefs.collectAsStateWithLifecycle()
    val strength = prefs?.takeIf { it.tintsBar && now.trackId != null }?.strength
    val colors by produceState<PlayerColors?>(null, now.artwork, strength) {
        value = if (strength == null) null else vm.colorsFor(now.artwork)
    }
    val target = colors?.let { c -> strength?.let { barFilm(c.mesh[0], it) } } ?: GlazeTint
    return animateColorAsState(target, tween(CrossfadeMs), label = "bar film")
}

// A trace of a colour over the glass's usual dim film.
fun barFilm(color: Color, strength: AmbientStrength): Color =
    Color(ambientColor(color.toArgb())).copy(alpha = barTintAlpha(strength)).compositeOver(GlazeTint)

// A strip in Settings showing the glow at a strength, with the song on now
// written over it the way a page's text sits on it.
@Composable
fun AmbientPreview(strength: AmbientStrength, modifier: Modifier = Modifier, vm: AmbienceViewModel = hiltViewModel()) {
    val now by vm.now.collectAsStateWithLifecycle()
    val colors by produceState<PlayerColors?>(null, now.artwork) { value = vm.colorsFor(now.artwork) }
    Box(
        modifier
            .fillMaxWidth()
            .height(72.dp)
            .clip(RoundedCornerShape(14.dp))
            .background(OctoColors.Background),
    ) {
        AmbientField(colors, ambientAlpha(strength), moving = false)
        Column(Modifier.align(Alignment.CenterStart).padding(horizontal = 16.dp)) {
            Text(
                now.title ?: "Nothing playing",
                style = OctoType.bodySmall,
                color = OctoColors.TextPrimary,
                maxLines = 1,
                overflow = TextOverflow.Ellipsis,
            )
            Text(
                if (now.title != null) now.artist.orEmpty() else "The glow takes its colors from the song on now.",
                style = OctoType.caption,
                color = OctoColors.TextSecondary,
                maxLines = 1,
                overflow = TextOverflow.Ellipsis,
            )
        }
    }
}

// The colour field itself, in a layer of its own: new frames redraw only
// this layer, and only its drawing reads the moving values, so the page over
// it is never recomposed or redrawn for it.
@Composable
private fun AmbientField(colors: PlayerColors?, strength: Float, moving: Boolean, modifier: Modifier = Modifier) {
    val target = remember(colors) { (colors ?: PlayerColors.Quiet).mesh.map { Color(ambientColor(it.toArgb())) } }
    val c0 = animateColorAsState(target[0], tween(CrossfadeMs), label = "ambient 0")
    val c1 = animateColorAsState(target[1], tween(CrossfadeMs), label = "ambient 1")
    val c2 = animateColorAsState(target[2], tween(CrossfadeMs), label = "ambient 2")
    val c3 = animateColorAsState(target[3], tween(CrossfadeMs), label = "ambient 3")
    val glow = animateFloatAsState(if (colors == null) 0f else strength, tween(CrossfadeMs), label = "ambient glow")
    val painter = remember { fieldPainter() }

    val time = remember { mutableFloatStateOf(0f) }
    if (moving && strength > 0f && painter.moves) {
        val lifecycle = LocalLifecycleOwner.current.lifecycle
        val stepMs = driftFrameMs(strength)
        LaunchedEffect(lifecycle, stepMs) {
            lifecycle.repeatOnLifecycle(Lifecycle.State.STARTED) {
                var last = withFrameNanos { it }
                while (true) {
                    delayToNextTick(stepMs)
                    withFrameNanos { now ->
                        time.floatValue += (now - last) / 1_000_000_000f * DriftSpeed
                        last = now
                    }
                }
            }
        }
    }

    Spacer(
        modifier
            .fillMaxSize()
            .graphicsLayer { }
            .drawBehind {
                val alpha = glow.value
                if (alpha <= 0.002f) return@drawBehind
                with(painter) { paint(c0.value, c1.value, c2.value, c3.value, time.floatValue, alpha) }
                drawRect(BottomFade)
            },
    )
}

// Draws the four colours as a field.
private interface FieldPainter {
    val moves: Boolean
    fun DrawScope.paint(c0: Color, c1: Color, c2: Color, c3: Color, time: Float, alpha: Float)
}

private fun fieldPainter(): FieldPainter =
    if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU) MeshPainter() else GradientPainter()

// The full player's moving mesh, on phones that can draw it.
@RequiresApi(Build.VERSION_CODES.TIRAMISU)
private class MeshPainter : FieldPainter {
    private val shader = RuntimeShader(MESH)
    private val brush = ShaderBrush(shader)
    override val moves = true

    override fun DrawScope.paint(c0: Color, c1: Color, c2: Color, c3: Color, time: Float, alpha: Float) {
        shader.setFloatUniform("size", size.width, size.height)
        shader.setFloatUniform("time", time)
        shader.setColorUniform("c0", c0.toArgb())
        shader.setColorUniform("c1", c1.toArgb())
        shader.setColorUniform("c2", c2.toArgb())
        shader.setColorUniform("c3", c3.toArgb())
        drawRect(brush, alpha = alpha)
    }
}

// A still diagonal blend of the same colours, for older phones.
private class GradientPainter : FieldPainter {
    override val moves = false

    override fun DrawScope.paint(c0: Color, c1: Color, c2: Color, c3: Color, time: Float, alpha: Float) {
        drawRect(Brush.linearGradient(listOf(c0, c1, c2, c3)), alpha = alpha)
    }
}
