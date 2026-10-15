package app.winters.octo.ui.common

import androidx.compose.animation.core.Animatable
import androidx.compose.animation.core.LinearEasing
import androidx.compose.animation.core.tween
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.composed
import androidx.compose.ui.draw.drawWithContent
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.geometry.Size
import androidx.compose.ui.graphics.BlendMode
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.CompositingStrategy
import androidx.compose.ui.graphics.drawscope.DrawScope
import androidx.compose.ui.graphics.drawscope.translate
import androidx.compose.ui.graphics.graphicsLayer
import androidx.compose.ui.layout.layout
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.unit.Constraints
import androidx.compose.ui.unit.Dp
import androidx.compose.ui.unit.dp
import kotlinx.coroutines.delay
import kotlinx.coroutines.launch
import kotlin.math.max
import kotlin.math.min
import kotlin.math.roundToInt

// A single line too long for its room. It fades out softly at its right
// edge; with `scroll` it also scrolls through, a few times, as a marquee
// does, fading softly at its left edge only while it is moving, so at rest
// its first letter sits crisp at the start. `key` starts it over (the
// song). The fades are masks on the line's own layer, so they work over
// any background, and a scroll only moves an inner layer: nothing is drawn
// again while it moves. A line that fits is drawn as it is.
fun Modifier.fadingMarquee(key: Any?, scroll: Boolean, fade: Dp = MarqueeFade): Modifier = composed {
    var room by remember { mutableIntStateOf(0) }
    var content by remember { mutableIntStateOf(0) }
    val offset = remember { Animatable(0f) }
    val leftFade = remember { Animatable(0f) }
    val velocity = with(LocalDensity.current) { MarqueeVelocity.toPx() }
    val overflow = content > room && room > 0
    val gap = room * MarqueeSpacing

    LaunchedEffect(key, overflow, content, room, scroll) {
        offset.snapTo(0f)
        leftFade.snapTo(0f)
        if (!overflow || !scroll) return@LaunchedEffect
        val distance = content + gap
        repeat(MarqueeIterations) {
            delay(MarqueeDelayMs)
            launch { leftFade.animateTo(1f, tween(FadeInMs)) }
            offset.animateTo(distance, tween((distance / velocity * 1000).roundToInt(), easing = LinearEasing))
            // The copy behind now sits where the line began: back to the start
            // without a jump, then still.
            offset.snapTo(0f)
            leftFade.animateTo(0f, tween(FadeInMs))
        }
    }

    this
        // The line's room: its own layer, cut to the room, with the fades.
        .graphicsLayer {
            compositingStrategy = CompositingStrategy.Offscreen
            clip = true
        }
        .drawWithContent {
            drawContent()
            if (overflow) fadeEdges(fade.toPx(), leftFade.value)
        }
        // The line at its full length inside it, moved by its own layer.
        .layout { measurable, constraints ->
            val placeable = measurable.measure(constraints.copy(minWidth = 0, maxWidth = Constraints.Infinity))
            val width = min(placeable.width, constraints.maxWidth).coerceAtLeast(constraints.minWidth)
            room = width
            content = placeable.width
            layout(width, placeable.height) { placeable.place(0, 0) }
        }
        .graphicsLayer { translationX = -offset.value }
        .drawWithContent {
            drawContent()
            if (overflow && scroll) translate(left = content + gap) { this@drawWithContent.drawContent() }
        }
}

// Masks the right edge out over `length`, eased, and the left edge as much
// as `left` (0 to 1) of the same.
private fun DrawScope.fadeEdges(length: Float, left: Float) {
    val fade = min(length, size.width / 2)
    if (fade <= 0f) return
    drawRect(
        Brush.horizontalGradient(*EasedOut, startX = size.width - fade, endX = size.width),
        topLeft = Offset(size.width - fade, 0f),
        size = Size(fade, size.height),
        blendMode = BlendMode.DstIn,
    )
    if (left > 0f) {
        val stops = Array(EasedOut.size) { i ->
            val (at, color) = EasedOut[EasedOut.lastIndex - i]
            1f - at to Color.Black.copy(alpha = 1f - left * (1f - color.alpha))
        }
        drawRect(
            Brush.horizontalGradient(*stops, startX = 0f, endX = fade),
            topLeft = Offset.Zero,
            size = Size(fade, size.height),
            blendMode = BlendMode.DstIn,
        )
    }
}

// From fully shown to gone, along a smooth curve rather than a straight
// ramp, so the fade has no visible start.
private val EasedOut: Array<Pair<Float, Color>> = Array(9) { i ->
    val t = i / 8f
    val eased = t * t * (3f - 2f * t)
    t to Color.Black.copy(alpha = max(0f, 1f - eased))
}

// How long the fades are, how fast a line scrolls, how long it rests
// before each pass, the room after it before it comes round again (a
// share of the line's room), and how many passes.
val MarqueeFade = 28.dp
private val MarqueeVelocity = 30.dp
private const val MarqueeDelayMs = 1_200L
private const val MarqueeSpacing = 1f / 3f
private const val MarqueeIterations = 3
private const val FadeInMs = 250
