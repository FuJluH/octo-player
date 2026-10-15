package app.winters.octo.desktop.pages

import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.runtime.Composable
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import app.winters.octo.design.AccentSwatch
import app.winters.octo.design.AccentSwatches
import app.winters.octo.design.DesktopType
import app.winters.octo.design.OctoColors
import app.winters.octo.design.OctoTooltip
import app.winters.octo.design.Space
import app.winters.octo.design.Txt
import app.winters.octo.theme.AccentChoice
import app.winters.octo.theme.FixedAccents
import app.winters.octo.theme.accentHelp

// The accent picker: a circle for each accent and one for the playing
// cover's, the chosen one checked and ringed, each named on hover, and a
// line naming the chosen one and saying what it colours.
@Composable
internal fun AccentRow(chosen: AccentChoice, onPick: (AccentChoice) -> Unit) {
    Column(Modifier.fillMaxWidth().padding(horizontal = RowInset, vertical = Space.L)) {
        Txt(ACCENT_COLOR, DesktopType.body, OctoColors.TextPrimary)
        AccentSwatches(
            swatches = AccentChoice.entries.map { choice -> AccentSwatch(choice.label, choice.argb?.let(::Color), selected = choice == chosen) },
            onPick = { onPick(AccentChoice.entries[it]) },
            spectrum = FixedAccents.drop(1).map { Color(it.argb!!) },
            modifier = Modifier.fillMaxWidth().padding(top = Space.S),
            wrap = { label, content -> OctoTooltip(label) { content() } },
        )
        Txt("${chosen.label}: ${accentHelp(chosen)}", DesktopType.meta, OctoColors.TextMuted, Modifier.padding(top = Space.Xs), maxLines = 3)
    }
}

const val ACCENT_COLOR = "Accent color"
