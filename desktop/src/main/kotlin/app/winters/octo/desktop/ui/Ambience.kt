package app.winters.octo.desktop.ui

import app.winters.octo.desktop.system.OctopusArt
import app.winters.octo.design.motionScale
import androidx.compose.animation.core.animateFloatAsState
import androidx.compose.animation.core.tween
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.runtime.Composable
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.compositionLocalOf
import androidx.compose.runtime.getValue
import androidx.compose.runtime.produceState
import androidx.compose.runtime.staticCompositionLocalOf
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.alpha
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.lerp
import androidx.compose.ui.graphics.toArgb
import app.winters.octo.desktop.AppState
import app.winters.octo.desktop.player.wash.ImmersiveWash
import app.winters.octo.desktop.player.wash.WashCover
import app.winters.octo.desktop.player.wash.WashCovers
import app.winters.octo.desktop.settings.AmbienceMotion
import app.winters.octo.desktop.settings.WashPrefs
import app.winters.octo.design.LocalReduceMotion
import app.winters.octo.design.OctoColors
import app.winters.octo.player.immersive.CoverFadeMs
import app.winters.octo.player.immersive.FpsChoices
import app.winters.octo.player.immersive.WashTuning
import app.winters.octo.player.immersive.paceBpm
import app.winters.octo.player.immersive.readableAlpha
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import org.jetbrains.skia.Image

// Octo's own colour, the violet of its icon: the key colour while no song
// gives one.
val OctoKey = Color(0xFF9061FA)

// The colour the glass takes a hint of: the playing song's, or Octo's.
val LocalKeyColour = staticCompositionLocalOf { OctoKey }

// A colour made fit to tint with: the same hue, never too dark or grey to
// show on dark glass.
fun keyColour(argb: Int): Color {
    val hsv = FloatArray(3)
    java.awt.Color.RGBtoHSB(argb shr 16 and 0xFF, argb shr 8 and 0xFF, argb and 0xFF, hsv)
    // A cover with hardly any colour gives Octo's own.
    if (hsv[1] < 0.12f) return OctoKey
    val rgb = java.awt.Color.HSBtoRGB(hsv[0], hsv[1].coerceIn(0.35f, 0.8f), hsv[2].coerceIn(0.75f, 1f))
    return Color(rgb or (0xFF shl 24))
}

// The glass's rim with a fifth of the key colour in it.
fun keyRim(key: Color, alpha: Float = 0.12f): Color = lerp(Color.White, key, 0.2f).copy(alpha = alpha)

// Octo's icon (drawn from the vector at OCTO_ART_PX) made ready for the
// wash, once for the whole run.
internal object OctoArt {
    private const val OCTO_ART_PX = 512
    @Volatile private var made: WashCover? = null

    fun cover(tuning: WashTuning): WashCover {
        made?.takeIf { it.key == keyFor(tuning) }?.let { return it }
        val image = runCatching {
            OctopusArt.icon(OCTO_ART_PX, shape = null)
        }.getOrNull()
        return WashCovers.prepared(keyFor(tuning), image, tuning).also { made = it }
    }

    private fun keyFor(tuning: WashTuning) = "octo|${tuning.contrast}|${tuning.saturation}|${tuning.brightnessCap}"
}

// Octo's own colours as a slow wash, for when there is no cover to show:
// behind the sign-in, and very dim behind the pages while nothing plays.
// It is the full player's background seeded with the app's icon. With
// motion reduced, `moving` off, or the window minimised or in the tray, it
// holds still. `veil` is how much of the page colour lies over it.
@Composable
fun OctoAmbience(app: AppState, moving: Boolean, veil: Float, modifier: Modifier = Modifier) {
    val settings by app.settings.state.collectAsState()
    val wash = settings.appearance.wash
    val tuning = WashTuning(wash.contrast, wash.saturation / 100f, wash.brightnessCap / 100f)
    val cover by produceState<WashCover?>(null, tuning) { value = withContext(Dispatchers.Default) { OctoArt.cover(tuning) } }
    Box(modifier.fillMaxSize().background(OctoColors.Background)) {
        ImmersiveWash(
            cover,
            paceBpm(null, false),
            // Calm and cheap: a gentle pace at a modest frame rate.
            fpsLimit = minOf(wash.fps, 30),
            speed = 0.12f,
            moving = moving && !LocalReduceMotion.current && LocalWindowShown.current,
            dolly = { 1f },
        )
        Box(Modifier.fillMaxSize().alpha(veil).background(OctoColors.Background))
    }
}

// The key colour for a prepared cover.
fun WashCover.keyColour(): Color = if (main == 0) OctoKey else keyColour(main)

// Whether what reads it is on screen: the window not minimized and not
// hidden in the tray, and for the frame and its colours, not covered by
// the full player. What moves rests while it is not.
val LocalWindowShown = compositionLocalOf { true }

// Whether the window is drawn by the processor, without the graphics card
// (an old or virtual machine). A moving wash costs too much there, so it
// holds still.
val LocalSoftwareDrawing = compositionLocalOf { false }

// The most of the immersive wash that shows behind the pages, by the
// strength setting: from a third to nine tenths.
fun immersiveOpacity(strength: Float): Float = 0.3f + 0.6f * strength.coerceIn(0f, 1f)

// How much of Octo's own colours show while nothing plays: what the glow
// shows of them, a fifth to a half.
fun quietOpacity(strength: Float): Float = 0.2f + 0.3f * strength.coerceIn(0f, 1f)

// The contrast the pages' quieter words (the accent colour, used for
// subtitles and details) keep over the wash's brightest part, the usual
// minimum for reading. The quietest words (TextMuted) are kept readable
// by the page's own shade (PageShade.kt), so the colours stay rich.
const val PageContrast = 4.5

// How much of this cover's wash shows behind the pages: as much as the
// strength asks, less when the cover is bright enough to wash out the
// words. The page's words stay light, so a bright cover shows fainter.
fun WashCover.pageOpacity(strength: Float): Float =
    readableAlpha(peak, OctoColors.Background.toArgb(), OctoColors.TextSecondary.toArgb(), PageContrast, immersiveOpacity(strength))

// How much of the glow shows: a little more than a tenth up to a half, by
// the strength.
fun glowOpacity(strength: Float): Float = 0.12f + 0.38f * strength.coerceIn(0f, 1f)

// How fast the immersive colours drift behind the pages, as a share of the
// full pace, or null when they hold still. Gentle is half the full
// player's own speed; Full is its speed.
fun ambienceSpeed(motion: AmbienceMotion, wash: WashPrefs): Float? = when (motion) {
    AmbienceMotion.Still -> null
    AmbienceMotion.Gentle -> wash.speed / 200f
    AmbienceMotion.Full -> wash.speed / 100f
}

// Whether the immersive colours move now: only while music plays, the
// window is on screen and the full player (which has its own) is shut;
// never when held still, with motion reduced, or without a graphics card.
fun ambienceMoves(motion: AmbienceMotion, playing: Boolean, shown: Boolean, software: Boolean, fullPlayer: Boolean, reduced: Boolean): Boolean =
    motion != AmbienceMotion.Still && playing && shown && !software && !fullPlayer && !reduced

// The frame rate behind the pages: the lowest of the phone's choices, 30,
// or the full player's own when that is lower. The frame's glass blurs
// this layer again every frame, and at a drift this slow more frames show
// nothing new.
fun ambienceFps(wash: WashPrefs): Int = minOf(wash.fps, FpsChoices.first())

// The full player's moving wash behind the whole window: the playing
// song's cover, as the full player draws it and from the same prepared
// copy, dimmed behind the pages so their words stay readable. With nothing
// playing, Octo's own colours stand in, still. It moves only while music
// plays, the window is on screen and the full player is shut (it has its
// own), and never with motion reduced or without a graphics card.
@Composable
fun ImmersiveAmbience(app: AppState, modifier: Modifier = Modifier) {
    val settings by app.settings.state.collectAsState()
    val look = settings.appearance
    val wash = look.wash
    val tuning = WashTuning(wash.contrast, wash.saturation / 100f, wash.brightnessCap / 100f)
    val state by app.player.state.collectAsState()
    val song = state.current?.song
    val connection = app.connection
    val cover by produceState<WashCover?>(null, song?.coverArt, song == null, connection, tuning) {
        if (song == null || connection == null) {
            value = withContext(Dispatchers.Default) { OctoArt.cover(tuning) }
        } else {
            app.washCovers.follow(connection.client, song.coverArt, tuning).collect { value = it }
        }
    }
    val moving = ambienceMoves(
        look.ambienceMotion,
        playing = song != null && state.playing,
        shown = LocalWindowShown.current,
        software = LocalSoftwareDrawing.current,
        fullPlayer = app.fullPlayer,
        reduced = LocalReduceMotion.current,
    )
    ImmersiveBackdrop(cover, look.glowStrength, paceBpm(song?.bpm, wash.useBpm), ambienceFps(wash), ambienceSpeed(look.ambienceMotion, wash) ?: 0f, moving, modifier, quiet = song == null)
}

// The wash behind the pages over the page colour, as much of it showing as
// the strength asks and the cover allows (`pageOpacity`), easing between
// covers. `quiet` (nothing playing, Octo's own colours) keeps it as dim as
// the glow keeps them.
@Composable
internal fun ImmersiveBackdrop(
    cover: WashCover?,
    strength: Float,
    bpm: Float,
    fps: Int,
    speed: Float,
    moving: Boolean,
    modifier: Modifier = Modifier,
    quiet: Boolean = false,
) {
    val most = cover?.pageOpacity(strength) ?: 0f
    val target = if (quiet) minOf(most, quietOpacity(strength)) else most
    val opacity by animateFloatAsState(target, tween(motionScale().ms(CoverFadeMs.toInt())), label = "ambience")
    Box(modifier.fillMaxSize().background(OctoColors.Background)) {
        ImmersiveWash(cover, bpm, fps, speed, moving, dolly = { 1f }, opacity = { opacity })
    }
}
