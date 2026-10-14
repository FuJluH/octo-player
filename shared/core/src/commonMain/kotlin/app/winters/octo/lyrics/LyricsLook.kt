package app.winters.octo.lyrics

import kotlinx.serialization.Serializable

// How synced lyrics are shown.
@Serializable
enum class LyricsStyle(val label: String, val about: String) {
    Flowing("Flowing", "Lines ripple into place, words fill with light and long notes bloom."),
    Classic("Classic", "The line being sung grows and its words brighten in place."),
}

// One of the look's sliders: its percent range and where it starts.
enum class LookDial(val key: String, val range: IntRange, val default: Int) {
    Emphasis("lyrics_fx_emphasis", 0..200, 100),
    Glow("lyrics_fx_glow", 0..200, 100),
    Lift("lyrics_fx_lift", 0..200, 100),
    Speed("lyrics_fx_speed", 50..200, 100),
    InactiveScale("lyrics_fx_inactive_scale", 60..100, 80),
    Fade("lyrics_fx_fade", 0..200, 100),
    Cascade("lyrics_fx_cascade", 0..200, 100),
}

// How the flowing lyrics look, in percent where it is a slider.
@Serializable
data class LyricsLook(
    val style: LyricsStyle = LyricsStyle.Flowing,
    // How much long notes swell, spread and rise.
    val emphasis: Int = LookDial.Emphasis.default,
    // How strongly long notes glow.
    val glow: Int = LookDial.Glow.default,
    // How far sung words rise and bob.
    val lift: Int = LookDial.Lift.default,
    // How quickly lines move into place.
    val speed: Int = LookDial.Speed.default,
    // The size of the lines not being sung.
    val inactiveScale: Int = LookDial.InactiveScale.default,
    // How soft the edge of the word fill is.
    val fade: Int = LookDial.Fade.default,
    // How far apart the lines start moving when the focus moves.
    val cascade: Int = LookDial.Cascade.default,
    // Lines already sung stay faintly on screen.
    // Sung lines stay above the current one, dimmed, so the lyrics fill the
    // screen instead of starting halfway down.
    val keepCompleted: Boolean = true,
    // The lines bend around a drum.
    val arc: Boolean = false,
    // Fast singing blooms too: a word held long for its line swells and
    // glows, held words glow more and every sung word rises a little more.
    val bloomFast: Boolean = true,
) {
    fun percent(dial: LookDial): Int = when (dial) {
        LookDial.Emphasis -> emphasis
        LookDial.Glow -> glow
        LookDial.Lift -> lift
        LookDial.Speed -> speed
        LookDial.InactiveScale -> inactiveScale
        LookDial.Fade -> fade
        LookDial.Cascade -> cascade
    }

    fun with(dial: LookDial, percent: Int): LyricsLook {
        val value = percent.coerceIn(dial.range)
        return when (dial) {
            LookDial.Emphasis -> copy(emphasis = value)
            LookDial.Glow -> copy(glow = value)
            LookDial.Lift -> copy(lift = value)
            LookDial.Speed -> copy(speed = value)
            LookDial.InactiveScale -> copy(inactiveScale = value)
            LookDial.Fade -> copy(fade = value)
            LookDial.Cascade -> copy(cascade = value)
        }
    }

    // As fractions, for the drawing.
    fun fraction(dial: LookDial): Double = percent(dial).coerceIn(dial.range) / 100.0
}
