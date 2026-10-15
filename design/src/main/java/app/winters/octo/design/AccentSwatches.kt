package app.winters.octo.design

import androidx.compose.foundation.Canvas
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.FlowRow
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.selection.selectable
import androidx.compose.foundation.selection.selectableGroup
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.Path
import androidx.compose.ui.graphics.StrokeCap
import androidx.compose.ui.graphics.StrokeJoin
import androidx.compose.ui.graphics.drawscope.Stroke
import androidx.compose.ui.input.pointer.PointerIcon
import androidx.compose.ui.input.pointer.pointerHoverIcon
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.unit.dp

// One accent to pick: its name, the colour it shows, or null for the one
// drawn as every accent round a circle ("From the album art"), and whether
// it is the one in use.
class AccentSwatch(val label: String, val color: Color?, val selected: Boolean)

// The accents as a wrapping row of colour circles. The one in use carries a
// dark check and a white ring round it; each is a radio button named for
// screen readers. `spectrum` paints the circle with no colour of its own,
// and `wrap` lets a desktop add a tooltip with the name.
@Composable
fun AccentSwatches(
    swatches: List<AccentSwatch>,
    onPick: (Int) -> Unit,
    modifier: Modifier = Modifier,
    spectrum: List<Color> = emptyList(),
    wrap: @Composable (label: String, content: @Composable () -> Unit) -> Unit = { _, content -> content() },
) {
    FlowRow(
        modifier.selectableGroup(),
        horizontalArrangement = Arrangement.spacedBy(2.dp),
        verticalArrangement = Arrangement.spacedBy(2.dp),
    ) {
        swatches.forEachIndexed { index, swatch ->
            wrap(swatch.label) { Swatch(swatch, spectrum) { onPick(index) } }
        }
    }
}

// The dark ink on an accent, the page's own colour.
private val SwatchInk = Color(0xFF0C0C0D)

@Composable
private fun Swatch(swatch: AccentSwatch, spectrum: List<Color>, onClick: () -> Unit) {
    Box(
        Modifier
            .size(48.dp)
            .clip(CircleShape)
            .pointerHoverIcon(PointerIcon.Hand)
            .selectable(selected = swatch.selected, role = Role.RadioButton, onClick = onClick)
            .semantics { contentDescription = swatch.label },
        contentAlignment = Alignment.Center,
    ) {
        Canvas(Modifier.size(42.dp)) {
            val radius = size.minDimension / 2
            if (swatch.selected) drawCircle(Color.White, radius = radius - 1.dp.toPx(), style = Stroke(2.dp.toPx()))
            val inner = radius - 5.dp.toPx()
            val color = swatch.color
            if (color != null) {
                drawCircle(color, radius = inner)
            } else if (spectrum.isNotEmpty()) {
                drawCircle(Brush.sweepGradient(spectrum + spectrum.first(), center), radius = inner)
            }
            if (swatch.selected) {
                val s = inner * 0.9f
                val check = Path().apply {
                    moveTo(center.x - s * 0.45f, center.y + s * 0.02f)
                    lineTo(center.x - s * 0.12f, center.y + s * 0.34f)
                    lineTo(center.x + s * 0.48f, center.y - s * 0.30f)
                }
                drawPath(check, SwatchInk, style = Stroke(2.5.dp.toPx(), cap = StrokeCap.Round, join = StrokeJoin.Round))
            }
        }
    }
}
