package app.winters.octo.theme

import app.winters.octo.covers.lchToArgb
import app.winters.octo.covers.toLch
import app.winters.octo.player.immersive.contrastRatio
import kotlinx.serialization.Serializable

// The accent colour both apps draw selected states, sliders, switches and
// filled buttons in. Every fixed one is a light shade at the same OKLCH
// lightness as Octo's own (about 0.76), so each reads at WCAG AA or better
// as words on the page and as the fill under the page's dark ink. `argb`
// is null for the one taken from the playing song's cover.
@Serializable
enum class AccentChoice(val label: String, val argb: Int?) {
    Octo("Octo", 0xFF97B1B9.toInt()),
    Sky("Sky", 0xFF73BAEA.toInt()),
    Iris("Iris", 0xFFA3A9F6.toInt()),
    Lilac("Lilac", 0xFFC79DE6.toInt()),
    Rose("Rose", 0xFFE496B4.toInt()),
    Coral("Coral", 0xFFEF9687.toInt()),
    Amber("Amber", 0xFFDAA75D.toInt()),
    Lime("Lime", 0xFFA0BE66.toInt()),
    Mint("Mint", 0xFF6FC5A1.toInt()),
    FromArt("From the album art", null),
}

// The fixed accents, in the order the pickers show them.
val FixedAccents: List<AccentChoice> = AccentChoice.entries.filter { it.argb != null }

// Octo's own accent, the default.
val OctoAccentArgb: Int = AccentChoice.Octo.argb!!

// The page colour and the raised surface the accent sits on, and the dark
// ink drawn on an accent fill.
const val AccentPageArgb: Int = 0xFF0C0C0D.toInt()
const val AccentSurfaceArgb: Int = 0xFF1A1A1B.toInt()

// The contrast every accent keeps against the page, the raised surface
// and the dark ink: WCAG AA for small text.
const val AccentContrast = 4.5

// One line under the picker saying what the choice does.
fun accentHelp(choice: AccentChoice): String = when (choice) {
    AccentChoice.FromArt -> "Follows the playing song's cover. Octo's own color while nothing plays or the cover is gray."
    AccentChoice.Octo -> "Octo's own blue gray for selections, sliders, switches and buttons."
    else -> "Selections, sliders, switches and buttons in ${choice.label.lowercase()}."
}

// A cover's colour made into an accent: the same hue, at the fixed
// accents' lightness and a chroma held between theirs, lightened further
// when the page would still read it under AA. Null for a cover with
// hardly any colour, which keeps Octo's own.
fun accentFromArt(argb: Int): Int? {
    val lch = toLch(argb)
    if (lch.c < MinArtChroma) return null
    val chroma = lch.c.coerceIn(0.07, 0.12)
    var lightness = 0.76
    var accent = lchToArgb(lightness, chroma, lch.h)
    while (!accentReads(accent) && lightness < 0.95) {
        lightness += 0.02
        accent = lchToArgb(lightness, chroma, lch.h)
    }
    return accent
}

// Below this chroma a cover is grey enough to keep Octo's own accent.
private const val MinArtChroma = 0.04

// Whether an accent reads on the page and the raised surface, and dark
// ink reads on it, each at AA.
fun accentReads(argb: Int): Boolean =
    contrastRatio(argb, AccentPageArgb) >= AccentContrast && contrastRatio(argb, AccentSurfaceArgb) >= AccentContrast

// The accent to draw now: a fixed one as it is, the cover's for From the
// album art (`art` is the playing cover's colour, null with none), or
// Octo's own when the cover gives none.
fun accentArgb(choice: AccentChoice, art: Int?): Int =
    choice.argb ?: art?.let(::accentFromArt) ?: OctoAccentArgb
