package app.winters.octo.desktop.sound

import androidx.compose.animation.core.animateFloatAsState
import androidx.compose.animation.core.tween
import androidx.compose.foundation.Canvas
import androidx.compose.foundation.gestures.awaitEachGesture
import androidx.compose.foundation.gestures.awaitFirstDown
import androidx.compose.foundation.layout.BoxWithConstraints
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberUpdatedState
import androidx.compose.runtime.setValue
import androidx.compose.ui.ExperimentalComposeUiApi
import androidx.compose.ui.Modifier
import androidx.compose.ui.geometry.CornerRadius
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.geometry.Size
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.Path
import androidx.compose.ui.graphics.StrokeCap
import androidx.compose.ui.graphics.StrokeJoin
import androidx.compose.ui.graphics.asSkiaPath
import androidx.compose.ui.graphics.drawscope.DrawScope
import androidx.compose.ui.graphics.drawscope.Stroke
import androidx.compose.ui.graphics.drawscope.drawIntoCanvas
import androidx.compose.ui.graphics.lerp
import androidx.compose.ui.graphics.skiaCanvas
import androidx.compose.ui.graphics.toArgb
import androidx.compose.ui.input.pointer.PointerEventType
import androidx.compose.ui.input.pointer.PointerIcon
import androidx.compose.ui.input.pointer.onPointerEvent
import androidx.compose.ui.input.pointer.pointerHoverIcon
import androidx.compose.ui.input.pointer.pointerInput
import androidx.compose.ui.input.pointer.positionChange
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.TextMeasurer
import androidx.compose.ui.text.drawText
import androidx.compose.ui.text.rememberTextMeasurer
import androidx.compose.ui.unit.Density
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import app.winters.octo.design.OctoColors
import app.winters.octo.design.OctoType
import app.winters.octo.sound.EqMode
import app.winters.octo.sound.GAIN_RANGE_DB
import app.winters.octo.sound.GraphicBands
import app.winters.octo.sound.ResponseCurve
import app.winters.octo.sound.SoundSettings
import app.winters.octo.ui.sound.MAX_HZ
import app.winters.octo.ui.sound.MIN_HZ
import app.winters.octo.ui.sound.cleanGain
import app.winters.octo.desktop.ui.LateClose
import app.winters.octo.ui.sound.readDb
import app.winters.octo.ui.sound.readHz
import app.winters.octo.ui.sound.shortHz
import app.winters.octo.ui.sound.withBandGain
import app.winters.octo.ui.sound.withFilter
import org.jetbrains.skia.FilterBlurMode
import org.jetbrains.skia.MaskFilter
import org.jetbrains.skia.PaintMode
import org.jetbrains.skia.PaintStrokeCap
import org.jetbrains.skia.PaintStrokeJoin
import kotlin.math.ln
import kotlin.math.pow
import kotlin.math.roundToInt
import kotlin.math.sign

// How many points the drawn curve has.
private const val CurvePoints = 256

private val PlotHeight = 240.dp
private val LabelBand = 22.dp
private val PadAcross = 12.dp
private val PadUpDown = 14.dp

// How near a node the pointer has to be to take hold of it.
private val HitRadius = 18.dp
private val NodeRadius = 5.5.dp
private val ActiveRadius = 8.dp

// How much one notch of the mouse wheel moves a node.
private const val WheelStepDb = 0.5f

// A second press this soon after the first, on the same node, puts it
// back to 0 dB.
private const val DoubleClickMs = 400L

// The curve and nodes when the equalizer is off.
private val Muted = Color(0xFF6B7075)

private val GridHz = listOf(100f, 1_000f, 10_000f)
private val EdgeLabelsHz = listOf(20f, 100f, 1_000f, 10_000f, 20_000f)

// Where frequencies and gains land on the plot, in pixels: frequency on a
// log scale across, gain from +12 dB at the top to -12 dB at the bottom.
internal class Plot(width: Float, height: Float, density: Density) {
    val left = with(density) { PadAcross.toPx() }
    val right = width - left
    val top = with(density) { PadUpDown.toPx() }
    val bottom = height - with(density) { (LabelBand + PadUpDown).toPx() }
    val pxPerDb = (bottom - top) / (2 * GAIN_RANGE_DB)

    fun x(hz: Float) = left + ln(hz / MIN_HZ) / ln(MAX_HZ / MIN_HZ) * (right - left)
    fun hz(x: Float) = MIN_HZ * (MAX_HZ / MIN_HZ).pow(((x - left) / (right - left)).coerceIn(0f, 1f))
    fun y(db: Float) = top + (GAIN_RANGE_DB - db.coerceIn(-GAIN_RANGE_DB, GAIN_RANGE_DB)) * pxPerDb
}

// A handle on the curve: where it is, and the gain it sets.
internal data class Node(val hz: Float, val gainDb: Float)

internal fun nodesOf(settings: SoundSettings): List<Node> = when (settings.mode) {
    EqMode.Graphic -> GraphicBands.zip(settings.graphicGains) { hz, gain -> Node(hz, gain) }
    EqMode.Parametric -> settings.filters.map { Node(it.frequency, it.gainDb) }
}

// The same edit to a node, whichever kind of curve it is on. The equalizer
// comes on too, so the change is heard.
internal fun moveNode(settings: SoundSettings, index: Int, hz: Float?, gainDb: Float): SoundSettings {
    val moved = when (settings.mode) {
        EqMode.Graphic -> withBandGain(settings, index, gainDb)
        EqMode.Parametric -> {
            val filter = settings.filters.getOrNull(index) ?: return settings
            withFilter(settings, index, filter.copy(frequency = hz ?: filter.frequency, gainDb = gainDb))
        }
    }
    return moved.copy(eqEnabled = true)
}

private fun pointsOf(settings: SoundSettings, plot: Plot): List<Offset> {
    val filters = settings.copy(eqEnabled = true).activeFilters()
    return nodesOf(settings).map { Offset(plot.x(it.hz), plot.y(ResponseCurve.gainDb(filters, it.hz))) }
}

// The node nearest the pointer, if one is close enough. The chosen node
// wins a tie, so stacked filters can still be told apart.
private fun nodeAt(points: List<Offset>, at: Offset, reach: Float, preferred: Int?): Int? {
    if (preferred != null && preferred in points.indices && (points[preferred] - at).getDistance() <= reach) return preferred
    return points.indices.map { it to (points[it] - at).getDistance() }.filter { it.second <= reach }.minByOrNull { it.second }?.first
}

// The equalizer's live response, as on the phone: a white line with a soft
// glow and a glass tint under it while the equalizer is on, grey while off.
// Drag a node up or down to set its gain; in parametric mode left and right
// set its frequency too. The mouse wheel over a node nudges it half a
// decibel; a double click puts it back to 0 dB.
@OptIn(ExperimentalComposeUiApi::class)
@Composable
fun EqCurve(
    settings: SoundSettings,
    selected: Int,
    onSelect: (Int) -> Unit,
    onPreview: ((SoundSettings) -> SoundSettings) -> Unit,
    onSettle: () -> Unit,
    modifier: Modifier = Modifier,
    plotHeight: Dp = PlotHeight,
) {
    val measurer = rememberTextMeasurer()
    val latest by rememberUpdatedState(settings)
    val chosen by rememberUpdatedState(selected)
    val select by rememberUpdatedState(onSelect)
    val preview by rememberUpdatedState(onPreview)
    val settle by rememberUpdatedState(onSettle)
    var held by remember { mutableStateOf<Int?>(null) }
    var hovered by remember { mutableStateOf<Int?>(null) }
    val clicks = remember { LastClick() }

    val filters = remember(settings) { settings.copy(eqEnabled = true).activeFilters() }
    val curve = remember(filters) { ResponseCurve.curve(filters, CurvePoints) }
    val nodes = nodesOf(settings)
    val nodeDb = remember(filters, nodes) { nodes.map { ResponseCurve.gainDb(filters, it.hz) } }
    val parametric = settings.mode == EqMode.Parametric
    val lit by animateFloatAsState(if (settings.eqEnabled) 1f else 0f, tween(250), label = "curve light")
    val line = lerp(Muted, Color.White, lit)

    BoxWithConstraints(modifier.fillMaxWidth().height(plotHeight + LabelBand)) {
        val density = androidx.compose.ui.platform.LocalDensity.current
        val plot = Plot(constraints.maxWidth.toFloat(), constraints.maxHeight.toFloat(), density)
        val points = nodes.mapIndexed { i, node -> Offset(plot.x(node.hz), plot.y(nodeDb[i])) }
        val active = held ?: hovered ?: if (parametric) selected else null
        Canvas(
            Modifier
                .fillMaxSize()
                .semantics { contentDescription = "Equalizer curve" }
                .pointerHoverIcon(if (hovered != null) PointerIcon.Hand else PointerIcon.Default)
                .onPointerEvent(PointerEventType.Move) { event ->
                    val at = event.changes.first().position
                    hovered = nodeAt(pointsOf(latest, Plot(size.width.toFloat(), size.height.toFloat(), this)), at, HitRadius.toPx(), chosen)
                }
                .onPointerEvent(PointerEventType.Exit) { hovered = null }
                .onPointerEvent(PointerEventType.Scroll) { event ->
                    val change = event.changes.first()
                    val index = nodeAt(pointsOf(latest, Plot(size.width.toFloat(), size.height.toFloat(), this)), change.position, HitRadius.toPx(), chosen)
                        ?: return@onPointerEvent
                    val node = nodesOf(latest)[index]
                    val step = -sign(change.scrollDelta.y) * WheelStepDb
                    preview { moveNode(it, index, null, cleanGain(node.gainDb + step)) }
                    settle()
                    change.consume()
                }
                .pointerInput(Unit) {
                    awaitEachGesture {
                        val down = awaitFirstDown()
                        val start = latest
                        val area = Plot(size.width.toFloat(), size.height.toFloat(), this)
                        val free = start.mode == EqMode.Parametric
                        val index = nodeAt(pointsOf(start, area), down.position, HitRadius.toPx(), if (free) chosen else null)
                            ?: return@awaitEachGesture
                        if (free) select(index)
                        if (clicks.twice(index)) {
                            preview { moveNode(it, index, null, 0f) }
                            settle()
                            return@awaitEachGesture
                        }
                        val node = nodesOf(start)[index]
                        held = index
                        down.consume()
                        // Settled however the drag ends, even when the page
                        // closes under it, so no half-made change is left.
                        try {
                            while (true) {
                                val event = awaitPointerEvent()
                                val change = event.changes.firstOrNull { it.id == down.id } ?: break
                                if (!change.pressed) break
                                if (change.positionChange() != Offset.Zero) {
                                    val gain = cleanGain(node.gainDb - (change.position.y - down.position.y) / area.pxPerDb)
                                    val hz = if (free) area.hz(area.x(node.hz) + change.position.x - down.position.x).roundToInt().toFloat() else null
                                    preview { moveNode(it, index, hz, gain) }
                                    change.consume()
                                }
                            }
                        } finally {
                            held = null
                            settle()
                        }
                    }
                },
        ) {
            grid(plot)
            curve(plot, curve, line, lit)
            points.forEachIndexed { i, point -> node(point, line, lit, big = i == active) }
            labels(plot, measurer, if (parametric) EdgeLabelsHz else GraphicBands)
            (held ?: hovered)?.let { i ->
                val node = nodes.getOrNull(i) ?: return@let
                reading(measurer, "${readHz(node.hz)}   ${readDb(node.gainDb)}", points[i])
            }
        }
    }
}

// Remembers the last press, to tell a double click.
private class LastClick {
    var at = 0L
    var index = -1

    fun twice(i: Int): Boolean {
        val now = System.currentTimeMillis()
        val again = i == index && now - at < DoubleClickMs
        at = if (again) 0L else now
        index = i
        return again
    }
}

// Faint lines at 100 Hz, 1 kHz and 10 kHz, and a clearer one at 0 dB.
private fun DrawScope.grid(plot: Plot) {
    GridHz.forEach { hz ->
        val x = plot.x(hz)
        drawLine(Color.White.copy(alpha = 0.06f), Offset(x, plot.top), Offset(x, plot.bottom), 1f)
    }
    val zero = plot.y(0f)
    drawLine(Color.White.copy(alpha = 0.14f), Offset(plot.left, zero), Offset(plot.right, zero), 1f)
}

private val glowPaint = org.jetbrains.skia.Paint().apply {
    isAntiAlias = true
    mode = PaintMode.STROKE
    strokeCap = PaintStrokeCap.ROUND
    strokeJoin = PaintStrokeJoin.ROUND
}

private fun DrawScope.curve(plot: Plot, gains: List<Float>, color: Color, lit: Float) {
    if (gains.isEmpty()) return
    val path = Path()
    val step = (plot.right - plot.left) / (gains.size - 1)
    gains.forEachIndexed { i, db ->
        val x = plot.left + step * i
        val y = plot.y(db)
        if (i == 0) path.moveTo(x, y) else path.lineTo(x, y)
    }
    // The glass tint under the line.
    val fill = Path().apply {
        addPath(path)
        lineTo(plot.right, plot.bottom)
        lineTo(plot.left, plot.bottom)
        close()
    }
    drawPath(fill, Brush.verticalGradient(listOf(color.copy(alpha = 0.05f + 0.09f * lit), color.copy(alpha = 0.01f)), startY = plot.top, endY = plot.bottom))
    val stroke = 2.dp.toPx()
    // The glow, only while the equalizer is on: three soft passes, as the
    // progress line has.
    if (lit > 0f) {
        drawIntoCanvas { canvas ->
            for (spread in floatArrayOf(2.5f, 1f, 0.3f)) {
                glowPaint.color = Color.White.copy(alpha = 0.4f * lit / 3f).toArgb()
                glowPaint.strokeWidth = stroke
                glowPaint.maskFilter = MaskFilter.makeBlur(FilterBlurMode.NORMAL, 6f * spread)
                canvas.skiaCanvas.drawPath(path.asSkiaPath(), glowPaint)
            }
        }
    }
    drawPath(path, color, style = Stroke(stroke, cap = StrokeCap.Round, join = StrokeJoin.Round))
    // Both paths are handed to LateClose: the curve is made again on every
    // frame the page animates, and what a frame draws keeps its own hold on
    // them until that frame is through. Leaving them for the collector is
    // what grew the app over a long listen.
    LateClose.close(fill.asSkiaPath())
    LateClose.close(path.asSkiaPath())
}

private fun DrawScope.node(at: Offset, color: Color, lit: Float, big: Boolean) {
    val radius = (if (big) ActiveRadius else NodeRadius).toPx()
    if (big && lit > 0f) drawCircle(Color.White.copy(alpha = 0.18f * lit), radius * 2f, at)
    // A dark edge so a node stands out against the line through it.
    drawCircle(Color.Black.copy(alpha = 0.45f), radius + 1.5f, at)
    drawCircle(color, radius, at)
}

private fun DrawScope.labels(plot: Plot, measurer: TextMeasurer, frequencies: List<Float>) {
    val style = OctoType.caption.copy(fontSize = 10.sp, color = OctoColors.TextMuted, fontFeatureSettings = "tnum")
    val y = plot.bottom + PadUpDown.toPx() + 4.dp.toPx()
    frequencies.forEach { hz ->
        val text = measurer.measure(shortHz(hz), style)
        val x = (plot.x(hz) - text.size.width / 2f).coerceIn(0f, size.width - text.size.width)
        drawText(text, topLeft = Offset(x, y))
    }
}

// A node's value in a small dark pill above it, or below it near the top.
private fun DrawScope.reading(measurer: TextMeasurer, text: String, at: Offset) {
    val style = OctoType.caption.copy(fontSize = 11.sp, color = Color.White, fontFeatureSettings = "tnum")
    val measured = measurer.measure(text, style)
    val padX = 8.dp.toPx()
    val padY = 3.dp.toPx()
    val width = measured.size.width + padX * 2
    val height = measured.size.height + padY * 2
    val gap = 16.dp.toPx()
    val above = at.y - gap - height
    val top = if (above >= 0f) above else at.y + gap
    val left = (at.x - width / 2).coerceIn(0f, size.width - width)
    drawRoundRect(Color.Black.copy(alpha = 0.72f), Offset(left, top), Size(width, height), CornerRadius(height / 2))
    drawText(measured, topLeft = Offset(left + padX, top + padY))
}
