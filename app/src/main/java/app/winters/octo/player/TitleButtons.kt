package app.winters.octo.player

import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Row
import androidx.compose.runtime.Composable
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.drawWithContent
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.geometry.Size
import androidx.compose.ui.graphics.BlendMode
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.CompositingStrategy
import androidx.compose.ui.graphics.graphicsLayer
import androidx.compose.ui.layout.AlignmentLine
import androidx.compose.ui.layout.FirstBaseline
import androidx.compose.ui.layout.LastBaseline
import androidx.compose.ui.layout.Layout
import androidx.compose.ui.unit.Constraints
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.TextUnit
import androidx.compose.ui.unit.dp
import kotlin.math.max
import kotlin.math.roundToInt

// The full player's buttons beside the song's name (the heart, or the add
// or plus, and More): each a 48dp round target, the two side by side.
val TitleButtonSize = 48.dp

// The heart's icon, and More's three dots drawn a little larger, so the
// two read as the same size: the dots span 17dp of their 26, the heart 21
// of its 24.
val TitleIconSize = 24.dp
val TitleMoreIconSize = 26.dp

// Half the width each icon actually covers.
private val HeartHalfSpan = 10.5.dp
private val DotsHalfSpan = 8.5.dp

// The room between the song's name and the heart, and how long the name's
// end fades out over.
private val TitleToButtons = 8.dp
private val TitleFade = 24.dp

// The space between the heart and the dots as drawn; the dots sit that far
// from the screen's edge too, so the two are evenly spaced.
val TitleButtonsGap: Dp = TitleButtonSize - HeartHalfSpan - DotsHalfSpan

// The song's name and artist (`title`) with its buttons, which sit on the
// middle of the two lines (of the one line with no artist, `oneLine`): the
// same place for a song and a station, so switching never moves them. The
// row's right edge is `sideMargin` in from the screen's. The name and
// artist fade out just before the heart rather than running under it.
// `titleSize` and `artistSize` are the two lines' text sizes.
@Composable
fun TitleWithButtons(
    oneLine: Boolean,
    titleSize: TextUnit,
    artistSize: TextUnit,
    sideMargin: Dp,
    modifier: Modifier = Modifier,
    title: @Composable () -> Unit,
    buttons: @Composable () -> Unit,
) {
    Layout(
        content = {
            Box(Modifier.endFade(TitleFade)) { title() }
            Row { buttons() }
        },
        modifier = modifier,
    ) { measurables, constraints ->
        val width = constraints.maxWidth
        val buttons = measurables[1].measure(Constraints())
        val place = titleButtonsPlace(
            rowWidth = width.toFloat(),
            sideMargin = sideMargin.toPx(),
            buttonSize = TitleButtonSize.toPx(),
            heartHalf = HeartHalfSpan.toPx(),
            dotsHalf = DotsHalfSpan.toPx(),
            nameGap = TitleToButtons.toPx(),
        )
        val buttonsLeft = (place.buttonsRight - buttons.width).roundToInt()
        val titleWidth = place.titleWidth.roundToInt().coerceIn(0, width)
        val name = measurables[0].measure(constraints.copy(minWidth = 0, maxWidth = titleWidth))
        val center = buttonsCenter(
            first = name[FirstBaseline].takeIf { it != AlignmentLine.Unspecified }?.toFloat(),
            last = name[LastBaseline].takeIf { it != AlignmentLine.Unspecified }?.toFloat(),
            oneLine = oneLine,
            titlePx = titleSize.toPx(),
            artistPx = artistSize.toPx(),
            height = name.height.toFloat(),
        )
        val buttonsTop = (center - buttons.height / 2f).roundToInt()
        // One short line: the buttons may reach past it, so the row grows to
        // hold them.
        val lift = max(0, -buttonsTop)
        val height = max(name.height + lift, buttonsTop + lift + buttons.height)
        layout(width, height) {
            name.place(0, lift)
            buttons.place(buttonsLeft, buttonsTop + lift)
        }
    }
}

// Where the buttons and the name go across a row `rowWidth` wide whose
// right edge is `sideMargin` in from the screen's: the dots end the gap
// between the icons in from the screen's edge, the buttons' targets side by
// side, and the name ends `nameGap` before the heart as drawn.
internal class TitleButtonsPlace(val buttonsRight: Float, val titleWidth: Float)

internal fun titleButtonsPlace(rowWidth: Float, sideMargin: Float, buttonSize: Float, heartHalf: Float, dotsHalf: Float, nameGap: Float): TitleButtonsPlace {
    val gap = buttonSize - heartHalf - dotsHalf
    val dotsRight = rowWidth + sideMargin - gap
    val buttonsRight = dotsRight + (buttonSize / 2 - dotsHalf)
    val heartLeft = buttonsRight - 2 * buttonSize + (buttonSize / 2 - heartHalf)
    return TitleButtonsPlace(buttonsRight, (heartLeft - nameGap).coerceAtLeast(0f))
}

// The height the buttons' middle sits at: half way between the middles of
// the name's line and the artist's, or the name's own with one line. A
// line's middle is a third of its text size above its baseline (the middle
// of its capitals and lowercase alike). With no baselines, the middle.
internal fun buttonsCenter(first: Float?, last: Float?, oneLine: Boolean, titlePx: Float, artistPx: Float, height: Float): Float {
    if (first == null) return height / 2
    val titleMiddle = first - LineMiddle * titlePx
    if (oneLine || last == null || last <= first) return titleMiddle
    val artistMiddle = last - LineMiddle * artistPx
    return (titleMiddle + artistMiddle) / 2
}

private const val LineMiddle = 0.35f

// Fades what it draws out over its last `length` on the right.
private fun Modifier.endFade(length: Dp): Modifier = this
    .graphicsLayer { compositingStrategy = CompositingStrategy.Offscreen }
    .drawWithContent {
        drawContent()
        val fade = length.toPx().coerceAtMost(size.width)
        if (fade <= 0f) return@drawWithContent
        val start = size.width - fade
        drawRect(
            Brush.horizontalGradient(0f to Color.Black, 1f to Color.Transparent, startX = start, endX = size.width),
            topLeft = Offset(start, 0f),
            size = Size(fade, size.height),
            blendMode = BlendMode.DstIn,
        )
    }
