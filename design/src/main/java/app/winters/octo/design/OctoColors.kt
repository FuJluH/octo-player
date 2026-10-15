package app.winters.octo.design

import androidx.compose.runtime.mutableStateOf
import androidx.compose.ui.graphics.Color

// Mixes two colors channel by channel, the way a stylesheet does.
fun mix(from: Color, to: Color, amount: Float) = Color(
    red = from.red + (to.red - from.red) * amount,
    green = from.green + (to.green - from.green) * amount,
    blue = from.blue + (to.blue - from.blue) * amount,
)

// Octo's own accent, a blue gray: the default accent, and the color of the
// quieter words whatever accent is chosen.
val OctoAccent = Color(0xFF97B1B9)
private val OctoAccentHover = Color(0xFFADC4CC)

// The accent in use. Snapshot state, so whatever reads it while composing
// or drawing follows a new choice.
private val accentNow = mutableStateOf(OctoAccent)

// Whether the glass takes the accent too. Off, it keeps Octo's blue gray
// whatever accent is chosen.
private val glassTintNow = mutableStateOf(false)

// Winters' Glass, the palette the other apps share. Dark only.
object OctoColors {
    val Background = Color(0xFF0C0C0D)
    // A low-alpha wash that tints glass panels.
    val BackgroundSecondary = Color.White.copy(alpha = 0.03f)
    // The solid surface under cards and glazed controls.
    val BackgroundTertiary = Color(0xFF1A1A1B)

    // The accent chosen in Appearance: selected states, sliders, switches,
    // focus rings and filled buttons.
    val Accent: Color get() = accentNow.value

    // Makes `color` the accent everywhere. Only a change redraws anything.
    fun useAccent(color: Color) {
        if (accentNow.value != color) accentNow.value = color
    }

    // The color lit into the glass: the bar, glazed buttons, tabs and
    // sheets. The accent when the glass takes it, else Octo's blue gray.
    val GlassAccent: Color get() = if (glassTintNow.value) Accent else OctoAccent

    // Whether the glass takes the accent. Only a change redraws anything.
    fun tintGlass(on: Boolean) {
        if (glassTintNow.value != on) glassTintNow.value = on
    }

    // A raised surface for rows to read and change: the solid gray with a
    // touch of Octo's blue gray, a clear step up from the page.
    val SurfaceRaised = mix(Color(0xFF1A1A1B), OctoAccent, 0.06f)
    val AccentHover: Color get() = Accent.let { if (it == OctoAccent) OctoAccentHover else mix(it, Color.White, 0.22f) }
    val TextPrimary = Color.White
    // Words stay in Octo's blue gray whatever the accent, so a page reads
    // the same in every color.
    val TextSecondary = OctoAccent
    // The quietest words: four fifths of the blue gray, 5.8:1 on the page
    // and the glass, so they keep WCAG AA's 4.5:1 with room for the colors
    // behind the page. At 60% they measured 3.7:1.
    val TextMuted = OctoAccent.copy(alpha = 0.8f)
    val Error = Color(0xFFEF4444)

    // The accent's family, each derived from the accent the same way:

    // A standard button's resting fill: a tenth of the accent in a dark gray.
    val AccentTonal: Color get() = mix(Color(0xFF1E1E1E), Accent, 0.10f)

    // A selected list row: the accent 40% of the way out of black, so it is
    // still the darker pill, only lightly tinted, and white text reads on it.
    val AccentSelected: Color get() = mix(Color.Black, Accent, 0.40f)

    // The ring round a focused control.
    val FocusRing: Color get() = Accent.copy(alpha = 0.70f)

    // A menu row under the finger or the pointer: the selected row's tint,
    // half as strong, so it is quieter than the chosen one.
    val MenuPress: Color get() = AccentSelected.copy(alpha = 0.55f)

    // A destructive action's words: a soft red. Its icon stays white.
    val Destructive = Color(0xFFFF3B30).copy(alpha = 0.85f)

    // The signal colors, for the rare thing that needs one.
    val SignalRed = Color(0xFFFF3B30)
    val SignalOrange = Color(0xFFFF9500)
    val SignalYellow = Color(0xFFFFCC00)
    val SignalGreen = Color(0xFF28CD41)
    val SignalBlue = Color(0xFF007AFF)
}
