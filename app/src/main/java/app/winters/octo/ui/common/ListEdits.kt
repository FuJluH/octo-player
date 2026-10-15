package app.winters.octo.ui.common

import androidx.compose.ui.graphics.Color
import androidx.compose.foundation.Canvas
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.material3.Icon
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.graphics.Shape
import androidx.compose.ui.graphics.StrokeCap
import androidx.compose.ui.res.painterResource
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.unit.dp
import app.winters.octo.design.OctoColors
import app.winters.octo.design.OctoIcons
import app.winters.octo.design.OctoType

// What is behind a row as it is swiped away.
private val RemoveFill = OctoColors.Error.copy(alpha = 0.25f)

// Two short lines, the grip a row is dragged by.
@Composable
fun DragHandle(modifier: Modifier) {
    Box(
        modifier.size(40.dp).semantics { contentDescription = "Reorder" },
        contentAlignment = Alignment.Center,
    ) {
        Canvas(Modifier.size(width = 18.dp, height = 8.dp)) {
            val stroke = 2.dp.toPx()
            listOf(stroke / 2, size.height - stroke / 2).forEach { y ->
                drawLine(OctoColors.TextMuted, Offset(0f, y), Offset(size.width, y), stroke, StrokeCap.Round)
            }
        }
    }
}

// What is behind a song as it is swiped right, to play it next.
private val PlayNextFill: Color get() = OctoColors.Accent.copy(alpha = 0.22f)

// Shown behind a row being swiped right: a wash of the accent, and what the
// swipe does at the start.
@Composable
fun PlayNextBackground(active: Boolean, shape: Shape) {
    if (!active) return
    Row(
        Modifier.fillMaxSize().background(PlayNextFill, shape).padding(horizontal = 24.dp),
        verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.spacedBy(10.dp),
    ) {
        Icon(painterResource(OctoIcons.PlayNext), contentDescription = null, tint = OctoColors.TextPrimary, modifier = Modifier.size(22.dp))
        Text("Play next", style = OctoType.bodySmall, color = OctoColors.TextPrimary)
    }
}

// Shown behind a row being swiped left: a wash of red and a bin at the end.
@Composable
fun RemoveBackground(active: Boolean, shape: Shape) {
    if (!active) return
    Box(
        Modifier.fillMaxSize().background(RemoveFill, shape).padding(horizontal = 24.dp),
        contentAlignment = Alignment.CenterEnd,
    ) {
        Icon(painterResource(OctoIcons.Delete), contentDescription = "Remove", tint = OctoColors.TextPrimary, modifier = Modifier.size(22.dp))
    }
}
