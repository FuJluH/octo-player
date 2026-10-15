package app.winters.octo.player.immersive

import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.toArgb
import app.winters.octo.player.PlayerColors
import app.winters.octo.player.TitleIconAlpha
import kotlinx.serialization.Serializable

// What fills the full player behind the lyrics and controls.
enum class BackgroundMode {
    // The artwork torn into drifting copies, warped and blurred into a
    // slow wash of its colours.
    Default,

    // The artwork, blurred and still.
    Artwork,

    // A flat fill of the artwork's main colour.
    Colour,

    // The earlier moving mesh of four colours.
    Classic,
}

// The background's settings. The brightness cap, saturation and drift speed
// are percentages, the contrast a factor, and the frame rate a limit.
@Serializable
data class BackgroundPrefs(
    val mode: BackgroundMode = BackgroundMode.Default,
    val brightnessCap: Int = 50,
    val saturation: Int = 180,
    val contrast: Float = 1.3f,
    val useBpm: Boolean = true,
    // The frame rate the background once offered as a setting. It always
    // draws at WashMaxFps now; the value is still read from settings and
    // backups made before, and otherwise left alone.
    val fps: Int = 60,
    // How fast it drifts, as a share of the full pace. Low by default, so it
    // reads as a slow ambience rather than an animation.
    val speed: Int = 25,
) {
    // Held to the ranges the settings offer, for values read back.
    fun sane(): BackgroundPrefs = copy(
        brightnessCap = brightnessCap.coerceIn(BrightnessCapRange),
        saturation = saturation.coerceIn(SaturationRange),
        contrast = contrast.coerceIn(ContrastRange),
        fps = fps.takeIf { it in FpsChoices } ?: 60,
        speed = speed.coerceIn(SpeedRange),
    )

    val tuning: WashTuning get() = WashTuning(contrast, saturation / 100f, brightnessCap / 100f)

    // Whether the background is drawn from the prepared cover, so the
    // adjustments and the light or dark words apply.
    val prepared: Boolean get() = mode != BackgroundMode.Classic
}

// The ranges and frame rates offered are in shared core (WashReading.kt).

// The darkest and brightest the background drawn in `mode` gets: the
// prepared cover's range (`cover`, from WashArtwork), brightened or dimmed
// as the wash's last pass leaves it; the adjusted main colour for a flat
// fill; the mesh's four colours for the classic one (at 60% over the base
// when it cannot move, as the blurred artwork then shows). Null while the
// cover is still being made.
fun drawnRange(mode: BackgroundMode, colors: PlayerColors, prefs: BackgroundPrefs, cover: WashRange?, live: Boolean): WashRange? = when (mode) {
    BackgroundMode.Default -> cover?.scaled(FinalGain)
    BackgroundMode.Artwork -> cover
    BackgroundMode.Colour -> WashRange.of(colors.dominant?.let { prepareColor(it.toArgb(), prefs.tuning) } ?: colors.base.toArgb())
    BackgroundMode.Classic -> {
        val mesh = colors.mesh.map { it.toArgb() }
        if (live) WashRange.of(*mesh.toIntArray()) else WashRange.of(*mesh.map { overlay(it, 0.6f, colors.base.toArgb()) }.toIntArray())
    }
}

// The player's colours with the words' colour decided from what is drawn
// behind them (`drawnRange`), and the background dimmed as far as they
// need. Until the cover is ready, white words over the background as it is.
//
// The quieter icons are as strong as reading over the background's worst
// part needs: its brightest under white words, its darkest under dark ones.
fun PlayerColors.over(range: WashRange?): PlayerColors {
    val ink = range?.let { inkOver(it, base.toArgb()) } ?: WashInk(dark = false, show = 1f)
    val content = if (ink.dark) DarkInk else Color.White
    val under = when {
        range == null -> base.toArgb()
        ink.dark -> range.low
        else -> overlay(range.high, ink.show, base.toArgb())
    }
    return copy(content = content, show = ink.show, quiet = quietAlpha(under, content.toArgb(), TitleIconAlpha))
}
