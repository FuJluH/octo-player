package app.winters.octo.player

import android.graphics.Typeface
import androidx.compose.foundation.layout.Row
import androidx.compose.runtime.Composable
import androidx.compose.runtime.remember
import androidx.compose.runtime.staticCompositionLocalOf
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.SolidColor
import androidx.compose.ui.graphics.StrokeCap
import androidx.compose.ui.graphics.StrokeJoin
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.graphics.vector.PathParser
import androidx.compose.ui.layout.Layout
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.platform.LocalFontFamilyResolver
import androidx.compose.ui.text.TextStyle
import androidx.compose.ui.text.rememberTextMeasurer
import androidx.compose.ui.text.font.FontStyle
import androidx.compose.ui.text.font.FontSynthesis
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.Constraints
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.dp
import kotlin.math.max
import kotlin.math.roundToInt

// The full player's buttons beside the song's name (the heart, or the add
// or plus, and More): each a 48dp round target, the two side by side.
val TitleButtonSize = 48.dp

// How strongly the buttons' icons show: a step quieter than the name, as
// actions beside it rather than part of it.
const val TitleIconAlpha = 0.7f

// The weight of the player's secondary icons (the row of switches under the
// controls: a 22dp icon drawn with Phosphor's regular 16-of-256 stroke),
// which the buttons beside the name are drawn at too.
val SecondaryStroke: Dp = (22f * 16f / 256f).dp

// The buttons' icons, sized from the name's capital height: the heart
// stands about 1.15 times as tall, drawn with the secondary stroke; the
// dots and the plus are drawn on the same square with the same weight
// (the dots two strokes across, so the three weigh as much as the heart's line).
class TitleIcons(capHeight: Dp) {
    // The side of the square every icon is drawn on.
    val size: Dp = ((capHeight.value * HeightOverCap - SecondaryStroke.value) * 256f / HeartLineHeight).dp

    private val unitsPerDp = 256f / size.value
    private val strokeUnits = SecondaryStroke.value * unitsPerDp
    private val dotUnits = DotOverStroke * strokeUnits / 2f

    // Half of what each icon covers across.
    val heartHalf: Dp = ((HeartLineWidth + strokeUnits) / unitsPerDp / 2f).dp
    val dotsHalf: Dp = ((DotsApart + dotUnits) / unitsPerDp).dp

    // How far up the heart is drawn so the middle of what it covers sits on
    // the middle of its square, as the dots' does.
    val heartLift: Dp = (HeartDrop / unitsPerDp).dp

    val heart: ImageVector = line("title heart", HeartLine)
    val plus: ImageVector = line("title plus", PlusLine)
    val dots: ImageVector = ImageVector.Builder("title dots", size, size, 256f, 256f)
        .addPath(PathParser().parsePathString(dotsPath(dotUnits)).toNodes(), fill = SolidColor(Color.White))
        .build()

    private fun line(name: String, path: String): ImageVector = ImageVector.Builder(name, size, size, 256f, 256f)
        .addPath(
            PathParser().parsePathString(path).toNodes(),
            fill = null,
            stroke = SolidColor(Color.White),
            strokeLineWidth = strokeUnits,
            strokeLineCap = StrokeCap.Round,
            strokeLineJoin = StrokeJoin.Round,
        )
        .build()

    private companion object {
        const val HeightOverCap = 1.15f
        const val DotOverStroke = 2f

        // Phosphor's heart and plus as the lines its regular weight strokes,
        // on its 256 square: the heart spans 208 across and 176 down, its
        // middle 8 below the square's.
        const val HeartLine = "M128,224S24,168,24,102A54,54,0,0,1,78,48C100.59,48,119.94,60.31,128,80C136.06,60.31,155.41,48,178,48A54,54,0,0,1,232,102C232,168,128,224,128,224Z"
        const val HeartLineWidth = 208f
        const val HeartLineHeight = 176f
        const val HeartDrop = 8f
        const val PlusLine = "M40,128H216M128,40V216"

        // The dots' middles, 68 apart about the square's middle.
        const val DotsApart = 68f

        fun dotsPath(r: Float): String = listOf(60f, 128f, 196f).joinToString("") { x ->
            "M${x - r},128A$r,$r,0,1,0,${x + r},128A$r,$r,0,1,0,${x - r},128Z"
        }
    }
}

val LocalTitleIcons = staticCompositionLocalOf<TitleIcons?> { null }

// Where a line of `style` has its baseline, in pixels from its top.
@Composable
fun rememberBaselinePx(style: TextStyle): Float {
    val measurer = rememberTextMeasurer()
    return remember(measurer, style) { measurer.measure("Ag", style, maxLines = 1).firstBaseline }
}

// The height of a capital letter in `style`, in pixels, from its font.
@Composable
fun rememberCapHeightPx(style: TextStyle): Float {
    val resolver = LocalFontFamilyResolver.current
    val density = LocalDensity.current
    return remember(resolver, density, style) {
        val typeface = resolver.resolve(
            style.fontFamily,
            style.fontWeight ?: FontWeight.Normal,
            style.fontStyle ?: FontStyle.Normal,
            style.fontSynthesis ?: FontSynthesis.All,
        ).value as? Typeface
        val paint = android.graphics.Paint().apply {
            this.typeface = typeface
            textSize = with(density) { style.fontSize.toPx() }
        }
        val bounds = android.graphics.Rect()
        paint.getTextBounds("H", 0, 1, bounds)
        (-bounds.top).toFloat()
    }
}

// The song's name and artist (`title`) with its buttons, which sit on the
// middle of the name's capitals: `capHeight` tall, standing on
// `titleBaseline`, both in pixels from the top of the name's line. Both
// come from the name's font rather than from the laid out name, so the
// buttons stay put whatever the name is doing (scrolling, fading in a new
// song, or a short one). The same place for a song and a station, so
// switching never moves them. The row's right edge is `sideMargin` in from
// the screen's. The name and artist end at the heart's target, fading out
// before it.
@Composable
fun TitleWithButtons(
    capHeight: Float,
    titleBaseline: Float,
    icons: TitleIcons,
    sideMargin: Dp,
    modifier: Modifier = Modifier,
    title: @Composable () -> Unit,
    buttons: @Composable () -> Unit,
) {
    Layout(
        content = {
            title()
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
            heartHalf = icons.heartHalf.toPx(),
            dotsHalf = icons.dotsHalf.toPx(),
        )
        val buttonsLeft = (place.buttonsRight - buttons.width).roundToInt()
        val name = measurables[0].measure(constraints.copy(minWidth = 0, maxWidth = place.titleWidth.roundToInt().coerceIn(0, width)))
        val center = capMiddle(titleBaseline, capHeight)
        val buttonsTop = (center - buttons.height / 2f).roundToInt()
        // The buttons may reach past the name's lines, so the row grows to
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
// between the icons in from the screen's edge, the two targets side by
// side, and the name up to the heart's target.
internal class TitleButtonsPlace(val buttonsRight: Float, val titleWidth: Float)

internal fun titleButtonsPlace(rowWidth: Float, sideMargin: Float, buttonSize: Float, heartHalf: Float, dotsHalf: Float): TitleButtonsPlace {
    val gap = buttonSize - heartHalf - dotsHalf
    val dotsRight = rowWidth + sideMargin - gap
    val buttonsRight = dotsRight + (buttonSize / 2 - dotsHalf)
    return TitleButtonsPlace(buttonsRight, (buttonsRight - 2 * buttonSize).coerceAtLeast(0f))
}

// The middle of `capHeight` capitals standing on `baseline`.
internal fun capMiddle(baseline: Float, capHeight: Float): Float = baseline - capHeight / 2
