package app.winters.octo.player

import android.os.Build
import androidx.compose.animation.core.Animatable
import androidx.compose.animation.core.tween
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.gestures.detectTapGestures
import androidx.compose.foundation.gestures.detectVerticalDragGestures
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.BoxWithConstraints
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.DisposableEffect
import androidx.compose.runtime.IntState
import androidx.compose.runtime.MutableIntState
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.SideEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.key
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberUpdatedState
import androidx.compose.runtime.setValue
import androidx.compose.runtime.withFrameNanos
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clipToBounds
import androidx.compose.ui.draw.drawBehind
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.geometry.Rect
import androidx.compose.ui.geometry.Size
import androidx.compose.ui.graphics.BlendMode
import androidx.compose.ui.graphics.BlurEffect
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.CompositingStrategy
import androidx.compose.ui.graphics.Canvas as ComposeCanvas
import androidx.compose.ui.graphics.GraphicsLayerScope
import androidx.compose.ui.graphics.Paint
import androidx.compose.ui.graphics.RenderEffect
import androidx.compose.ui.graphics.Shadow
import androidx.compose.ui.graphics.TileMode
import androidx.compose.ui.graphics.TransformOrigin
import androidx.compose.ui.graphics.drawscope.CanvasDrawScope
import androidx.compose.ui.graphics.drawscope.DrawScope
import androidx.compose.ui.graphics.drawscope.drawIntoCanvas
import androidx.compose.ui.graphics.drawscope.withTransform
import androidx.compose.ui.graphics.graphicsLayer
import androidx.compose.ui.graphics.nativeCanvas
import androidx.compose.ui.input.pointer.pointerInput
import androidx.compose.ui.layout.Layout
import androidx.compose.ui.layout.layout
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.semantics.LiveRegionMode
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.liveRegion
import androidx.compose.ui.semantics.onClick
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.TextStyle
import androidx.compose.ui.text.drawText
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.rememberTextMeasurer
import androidx.compose.ui.unit.Constraints
import androidx.compose.ui.unit.LayoutDirection
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.lifecycle.Lifecycle
import androidx.lifecycle.compose.LocalLifecycleOwner
import androidx.lifecycle.repeatOnLifecycle
import app.winters.octo.lyrics.LookDial
import app.winters.octo.lyrics.Lyrics
import app.winters.octo.lyrics.LyricsLook
import app.winters.octo.lyrics.engine.ARC_DEPTH
import app.winters.octo.lyrics.engine.ARC_LIFT
import app.winters.octo.lyrics.engine.ARC_PERSPECTIVE
import app.winters.octo.lyrics.engine.ARC_YAW
import app.winters.octo.lyrics.engine.Emphasis
import app.winters.octo.lyrics.engine.LineState
import app.winters.octo.lyrics.engine.LineStatus
import app.winters.octo.lyrics.engine.LyricEngine
import app.winters.octo.lyrics.engine.LyricMapper
import app.winters.octo.lyrics.engine.MaskShape
import app.winters.octo.lyrics.engine.PRESSED_SCALE
import app.winters.octo.lyrics.engine.StillDots
import app.winters.octo.lyrics.engine.SyncLine
import app.winters.octo.lyrics.engine.SyncWord
import app.winters.octo.lyrics.engine.arcPose
import app.winters.octo.lyrics.engine.bobEm
import app.winters.octo.lyrics.engine.dotsPose
import app.winters.octo.lyrics.engine.emphasisFor
import app.winters.octo.lyrics.engine.fillProgress
import app.winters.octo.lyrics.engine.glyphPose
import app.winters.octo.lyrics.engine.liftEm
import app.winters.octo.lyrics.engine.maskLeft
import app.winters.octo.lyrics.engine.maskShape
import app.winters.octo.lyrics.engine.onScreen
import app.winters.octo.lyrics.heardAt
import app.winters.octo.lyrics.totalOffset
import app.winters.octo.playback.NowPlaying
import app.winters.octo.ui.common.asClock
import app.winters.octo.ui.common.rememberSystemReduceMotion
import kotlinx.coroutines.delay
import kotlinx.coroutines.flow.Flow
import kotlin.math.ceil
import kotlin.math.max
import kotlin.math.roundToLong
import app.winters.octo.lyrics.engine.liftOf

// The view fades in over this long once the lyrics are laid out.
private const val FADE_IN_MS = 450

// After a resize, the lines are laid out again once it has held this long.
private const val REMEASURE_AFTER_MS = 150L

// Laying the lines out takes at most this long a frame, so opening lyrics
// never stalls a frame.
private const val MEASURE_SLICE_NANOS = 4_000_000L

// Nothing moving and nothing playing: the loop looks again this often
// instead of every frame.
private const val RESTING_FRAME_MS = 32L

// The time stamp a long press shows stays this long.
private const val STAMP_SHOWN_MS = 1_500L

// Backing vocals, the credit, and translations sit quieter than the lead.
private const val BACKGROUND_ALPHA = 0.6f
private const val CREDIT_ALPHA = 0.75f
private const val EXTRA_ALPHA = 0.7f

// Dots across and apart, in em.
private const val DOT_EM = 0.34f
private const val DOT_GAP_EM = 0.22f

// The time stamp pill: a dark glass fill and a faint white edge.
private val StampFill = Color(0x52121214)
private val StampEdge = Color.White.copy(alpha = 0.16f)
private val StampStyle = TextStyle(fontSize = 11.52.sp, fontWeight = FontWeight.Bold, fontFeatureSettings = "tnum")

// The layer's camera works in 72nds of its distance unit.
private const val CAMERA_UNIT = 72f

// Synced lyrics that flow: the line being sung sits a little above the
// middle, the rest ripple into place around it on springs, each word fills
// with a soft sweep of light as it is sung, and long notes bloom letter by
// letter. One frame loop moves everything; the lines only read the result
// while they draw, so playing never composes anything.
@Composable
fun FlowingLyrics(
    lyrics: Lyrics,
    now: NowPlaying,
    positionMs: () -> Long,
    speed: () -> Float,
    timeEvents: Flow<Int>,
    offsetMs: Long,
    outputOffsetMs: Long,
    look: LyricsLook,
    reduceMotion: Boolean,
    onSeek: (Long) -> Unit,
    modifier: Modifier = Modifier,
    textColor: Color = Color.White,
) {
    val lines = remember(lyrics) { LyricMapper.map(lyrics) }
    if (lines.isEmpty()) return
    val engine = remember(lines) { LyricEngine(lines) }
    val phoneCalm = rememberSystemReduceMotion()
    val calm = reduceMotion || phoneCalm
    SideEffect {
        engine.look = look
        engine.reduceMotion = calm
    }
    val position by rememberUpdatedState(positionMs)
    val rate by rememberUpdatedState(speed)
    // The song's timing, and the output's, read afresh every frame: a new
    // output (earbuds put in) moves the words on the next one.
    val offset by rememberUpdatedState(offsetMs)
    val outputOffset by rememberUpdatedState(outputOffsetMs)
    val playing by rememberUpdatedState(now.isPlaying)
    val seek by rememberUpdatedState(onSeek)

    // The clock takes a fresh anchor whenever the player says the time
    // changed, and on play, pause and a new song.
    LaunchedEffect(engine, timeEvents) { timeEvents.collect { engine.clock.requestAnchor() } }
    LaunchedEffect(engine, now.isPlaying, now.trackId) { engine.clock.requestAnchor() }

    val density = LocalDensity.current
    val measurer = rememberTextMeasurer()
    val lifecycle = LocalLifecycleOwner.current.lifecycle
    var laidOut by remember(lines) { mutableStateOf<LyricsLayout?>(null) }
    val fade = remember(lines) { Animatable(0f) }
    var stamp by remember(lines) { mutableStateOf<Int?>(null) }
    var said by remember { mutableStateOf("") }

    BoxWithConstraints(modifier.fillMaxSize().clipToBounds()) {
        val width = constraints.maxWidth
        val height = constraints.maxHeight
        LaunchedEffect(lines, width, height, density) {
            if (laidOut != null) delay(REMEASURE_AFTER_MS)
            val spec = LyricsSpec(width, density)
            val boxes = ArrayList<LineBox>(lines.size)
            var slice = System.nanoTime()
            for (line in lines) {
                boxes += measureLine(line, spec, measurer)
                if (System.nanoTime() - slice > MEASURE_SLICE_NANOS) {
                    withFrameNanos { }
                    slice = System.nanoTime()
                }
            }
            val measured = LyricsLayout(spec, boxes)
            engine.setGeometry(measured.baseHeights(), spec.interludeIdle.toDouble(), spec.interludeFull.toDouble(), height.toDouble())
            laidOut = measured
            fade.animateTo(1f, tween(FADE_IN_MS))
        }
        val shown = laidOut ?: return@BoxWithConstraints
        // The lines' blurred copies, for these lines in this colour and look.
        val copies = remember(shown, textColor, calm, look, density.density) {
            if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) LyricCopies(density.density) else null
        }
        DisposableEffect(copies) { onDispose { copies?.close() } }
        val currentCopies by rememberUpdatedState(copies)
        val rests = remember(shown, textColor, calm, look) { LineRests() }
        val drawDensity by rememberUpdatedState(density)

        // The one frame loop. It stops while the app is in the background
        // and starts fresh when it comes back.
        LaunchedEffect(engine, shown) {
            lifecycle.repeatOnLifecycle(Lifecycle.State.STARTED) {
                engine.restart()
                while (true) {
                    withFrameNanos { nanos ->
                        engine.frame(
                            nanos,
                            position(),
                            playing,
                            rate().toDouble(),
                            offset,
                            outputOffset,
                            prepare = { shown.prepare(it, lines[it], measurer, look.bloomFast) },
                            release = shown::release,
                        )
                        rests.follow(engine, engine.shown.value, calm)
                        if (Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) {
                            currentCopies?.follow(
                                engine.states,
                                engine.shown.value,
                                nanos,
                                size = { index -> shown.width to lineNodeHeight(engine.states[index].line, shown.lines[index], shown) },
                                record = { index, canvas ->
                                    val st = engine.states[index]
                                    val area = Size(shown.width.toFloat(), lineNodeHeight(st.line, shown.lines[index], shown).toFloat())
                                    copyScope.draw(drawDensity, LayoutDirection.Ltr, ComposeCanvas(canvas), area) {
                                        drawLyricLine(engine, st, shown.lines[index], shown, textColor, calm)
                                    }
                                },
                            )
                        }
                    }
                    if (engine.settled) delay(RESTING_FRAME_MS)
                }
            }
        }
        LaunchedEffect(stamp) {
            if (stamp != null) {
                delay(STAMP_SHOWN_MS)
                stamp = null
            }
        }

        val tap: (Int) -> Unit = tap@{ index ->
            val line = lines[index]
            // A line faded right out is not there to tap.
            if (line.isCredit || engine.states[index].opacity < 0.05) return@tap
            // Played from where it is heard, with both timings, so the line
            // is just starting when the tap lands.
            val target = heardAt((line.start * 1000).roundToLong(), totalOffset(offset, outputOffset))
            engine.tapped(index, target / 1000.0)
            seek(target)
            said = "Playing from ${clockText(target)}"
        }

        Layout(
            content = {
                // Only the lines on screen or about to be are composed; the
                // set changes as lines come and go, not every frame.
                val range = engine.shown.value
                for (index in range) {
                    key(index) {
                        LineNode(engine, index, shown, copies, rests.line(index), textColor, calm, onTap = tap, onLongPress = { stamp = it })
                    }
                }
                stamp?.let { TimeStamp(engine, it, shown, totalOffset(offset, outputOffset)) }
                if (said.isNotEmpty()) {
                    Box(
                        Modifier.size(1.dp).semantics {
                            liveRegion = LiveRegionMode.Polite
                            contentDescription = said
                        },
                    )
                }
            },
            modifier = Modifier
                .fillMaxSize()
                .graphicsLayer { alpha = fade.value }
                .pointerInput(engine) {
                    detectVerticalDragGestures(
                        onDragStart = { engine.dragStart() },
                        onDragEnd = { engine.dragEnd() },
                        onDragCancel = { engine.dragEnd() },
                        onVerticalDrag = { change, dy ->
                            change.consume()
                            engine.dragBy(dy.toDouble())
                        },
                    )
                },
        ) { measurables, constraints ->
            // Every line sits at the top; its layer moves it into place.
            val free = Constraints(maxWidth = constraints.maxWidth)
            val placed = measurables.map { it.measure(free) }
            layout(constraints.maxWidth, constraints.maxHeight) {
                placed.forEach { it.place(0, 0) }
            }
        }
    }
}

// One line: its layer moves, scales, fades and blurs it from the engine's
// numbers, and its drawing fills its words. Both read only the line's own
// counters, so a line that did not change is left alone. A line resting at
// a blur draws a copy already blurred (LyricCopies) and its layer adds
// none; otherwise it draws itself and its layer blurs it.
@Composable
private fun LineNode(
    engine: LyricEngine,
    index: Int,
    shown: LyricsLayout,
    copies: LyricCopies?,
    rest: IntState,
    color: Color,
    calm: Boolean,
    onTap: (Int) -> Unit,
    onLongPress: (Int) -> Unit,
) {
    val st = engine.states[index]
    val line = st.line
    val box = shown.lines[index]
    val nodeHeight = lineNodeHeight(line, box, shown)
    val copy = remember(copies, index) { copies?.line(index)?.copy }
    val tap by rememberUpdatedState(onTap)
    val hold by rememberUpdatedState(onLongPress)
    val stampLabel = remember(line) { "Play from ${clockText((line.start * 1000).roundToLong())}" }
    Box(
        Modifier
            .layout { measurable, _ ->
                val placeable = measurable.measure(Constraints.fixed(shown.width, nodeHeight))
                layout(shown.width, nodeHeight) { placeable.place(0, 0) }
            }
            .graphicsLayer { placeLine(engine, st, box, shown, copy?.value) }
            .semantics {
                contentDescription = describe(line)
                if (!line.isCredit) {
                    onClick(label = stampLabel) {
                        tap(index)
                        true
                    }
                }
            }
            .then(
                if (line.isCredit) {
                    Modifier
                } else {
                    Modifier.pointerInput(index) {
                        detectTapGestures(
                            onPress = {
                                engine.press(index, true)
                                tryAwaitRelease()
                                engine.press(index, false)
                            },
                            onTap = { tap(index) },
                            onLongPress = { hold(index) },
                        )
                    }
                },
            )
            // A line sung word by word draws what holds still here, again only
            // when that changes (`rest`), and its moving words in the layer
            // below, every frame they move.
            .drawBehind {
                val words = box.words.isNotEmpty()
                if (words) rest.intValue else st.drawVersion.intValue
                val blurred = copy?.value
                if (blurred != null) {
                    drawIntoCanvas { blurred.draw(it.nativeCanvas) }
                } else {
                    drawLyricLine(engine, st, box, shown, color, calm, if (words) WordPass.Resting else WordPass.All)
                }
            },
    ) {
        if (box.words.isNotEmpty()) {
            Spacer(
                Modifier
                    .matchParentSize()
                    .graphicsLayer()
                    .drawBehind {
                        st.drawVersion.intValue
                        if (copy?.value == null) drawLyricLine(engine, st, box, shown, color, calm, WordPass.Moving)
                    },
            )
        }
    }
}

// A line's height as laid out: an interlude's has room for its dots open.
private fun lineNodeHeight(line: SyncLine, box: LineBox, shown: LyricsLayout): Int =
    ceil(if (line.isInterlude) shown.spec.interludeFull else box.height).toInt()

// Draws lines for their copies, away from the window.
private val copyScope = CanvasDrawScope()

// What a line reads as, aloud.
private fun describe(line: SyncLine): String = when {
    line.isInterlude -> "Instrumental"
    else -> listOfNotNull(line.text, line.translation).joinToString(". ")
}

// Blur effects by size, so moving lines reuse them.
private val blurs = HashMap<Float, RenderEffect>()

private fun blurOf(radius: Float): RenderEffect = blurs.getOrPut(radius) { BlurEffect(radius, radius, TileMode.Decal) }

// A line's place, size, opacity and blur for this frame. A line drawn from
// a blurred copy is not blurred again, and its opacity goes on the copy
// itself, so nothing cuts the blur off at the line's edges.
private fun GraphicsLayerScope.placeLine(engine: LyricEngine, st: LineState, box: LineBox, shown: LyricsLayout, copy: BlurCopy?) {
    st.layerVersion.intValue
    val look = engine.look
    val inactive = look.fraction(LookDial.InactiveScale).toFloat()
    var scale = inactive + (1f - inactive) * st.grown.value().toFloat()
    scale *= 1f - (1f - PRESSED_SCALE.toFloat()) * st.press.toFloat()
    val y = st.y.value() + engine.scrollOffset
    translationY = y.toFloat()
    alpha = st.opacity.toFloat().coerceIn(0f, 1f)
    val blur = blurPx(st, density)
    renderEffect = if (blur > 0f && copy == null && Build.VERSION.SDK_INT >= Build.VERSION_CODES.S) blurOf(blur) else null
    compositingStrategy = if (copy != null) CompositingStrategy.ModulateAlpha else CompositingStrategy.Auto
    transformOrigin = TransformOrigin(if (shown.width > 0) box.pivotX / shown.width else 0f, 0.5f)
    if (look.arc && onScreen(y, st.height, engine.viewHeight)) {
        val pose = arcPose(
            centre = y + st.height / 2,
            viewHeight = engine.viewHeight,
            side = if (st.line.alignRight) -1 else 1,
            depth = ARC_DEPTH * density,
            lift = ARC_LIFT * density,
            yaw = ARC_YAW,
            perspective = ARC_PERSPECTIVE * density,
        )
        translationX = pose.translationX.toFloat()
        rotationY = Math.toDegrees(pose.rotationY).toFloat()
        cameraDistance = (ARC_PERSPECTIVE * density).toFloat() / CAMERA_UNIT
        scale *= pose.scale.toFloat()
    } else {
        translationX = 0f
        rotationY = 0f
    }
    scaleX = scale
    scaleY = scale
}

// Draws a line: its dots, its words with their fill, lift and bloom, or its
// text whole, then any translation or romanization under it.
// `pass` draws all of it, only what holds still now (`Resting`), or only
// the words moving now (`Moving`).
private fun DrawScope.drawLyricLine(engine: LyricEngine, st: LineState, box: LineBox, shown: LyricsLayout, color: Color, calm: Boolean, pass: WordPass = WordPass.All) {
    val line = st.line
    if (line.isInterlude) {
        if (pass != WordPass.Moving) drawDots(engine, st, shown, color, calm)
        return
    }
    val pair = st.brightness()
    val voice = if (line.isBackground) BACKGROUND_ALPHA else 1f
    if (pass != WordPass.Moving) {
        box.block?.let { piece ->
            val alpha = if (line.isCredit) CREDIT_ALPHA else pair.bright.toFloat() * voice
            drawText(piece.layout, color, Offset(piece.x, piece.y), alpha)
        }
    }
    if (box.words.isNotEmpty()) drawWords(engine, st, box, color, calm, pair.bright.toFloat() * voice, pair.dark.toFloat() * voice, pass)
    if (pass != WordPass.Moving) box.extras.forEach { drawText(it.layout, color, Offset(it.x, it.y), EXTRA_ALPHA) }
}

// Which of a line's words a drawing takes.
internal enum class WordPass { All, Resting, Moving }

// Whether a word's drawing changes with the time around `t`: from just
// before its fill reaches it (and its letters start to bob) until its rise,
// bloom and bob have settled, about 2.2 lengths after it starts.
internal fun wordMoves(t: Double, word: SyncWord): Boolean {
    val length = word.end - word.start
    val until = max(word.start + max(1.0, length), word.start + 2.2 * length)
    return t >= word.start - WORD_MOTION_LEAD_S && t <= until
}

private const val WORD_MOTION_LEAD_S = 0.5

private fun DrawScope.drawWords(engine: LyricEngine, st: LineState, box: LineBox, color: Color, calm: Boolean, bright: Float, dark: Float, pass: WordPass) {
    val line = st.line
    val look = engine.look
    val t = engine.lyricTime
    // Sung long ago: drawn bright and risen, with nothing left to move.
    val cold = st.status == LineStatus.Passed && !st.live
    val lift = if (calm) 0.0 else look.fraction(LookDial.Lift)
    val letters = if (calm || !st.live) null else box.glyphs
    val lastGroup = line.words.dropLast(1).indexOfLast { it.trailingSpace } + 1
    line.words.forEachIndexed { j, word ->
        if (pass != WordPass.All && !cold && wordMoves(t, word) != (pass == WordPass.Moving)) return@forEachIndexed
        if (pass == WordPass.Moving && cold) return@forEachIndexed
        val wb = box.words[j]
        val rise = when {
            lift == 0.0 -> 0.0
            cold -> -liftOf(line.isBackground, look.bloomFast) * lift
            else -> liftEm(t, word.start, word.end, line.isBackground, lift, look.bloomFast)
        } * box.em
        val shape = maskShape(wb.width.toDouble(), wb.rowHeight.toDouble(), look.fraction(LookDial.Fade))
        val progress = if (cold) 1.0 else fillProgress(t, word.start, word.end, shape.edge)
        val glyphs = letters?.getOrNull(j)
        val bloom = glyphs?.let {
            emphasisFor(
                word.end - word.start, it.size, j >= lastGroup, look.fraction(LookDial.Emphasis), look.fraction(LookDial.Glow),
                fast = look.bloomFast, held = box.held?.getOrNull(j) ?: true,
            )
        }
        val paint: DrawScope.(Float) -> Unit = { alpha -> paintWord(wb, glyphs, bloom, word, t, rise.toFloat(), box.em, lift, line.isBackground, color, alpha) }
        when {
            progress <= 0.0 -> paint(dark)
            progress >= 1.0 -> paint(bright)
            else -> fillWord(wb, box.em, progress, shape, line.rtl, bright, dark, paint)
        }
    }
}

// A word part sung: drawn in full into its own layer, then an alpha mask
// slid across it keeps the sung side bright and the rest dark.
private fun DrawScope.fillWord(
    wb: WordBox,
    em: Float,
    progress: Double,
    shape: MaskShape,
    rtl: Boolean,
    bright: Float,
    dark: Float,
    paint: DrawScope.(Float) -> Unit,
) {
    if (wb.width <= 0f) return
    val margin = 0.5f * em
    val area = Rect(wb.x - margin, wb.rowTop - margin, wb.x + wb.width + margin, wb.rowTop + wb.rowHeight + margin)
    val left = maskLeft(progress, wb.x.toDouble(), wb.width.toDouble(), shape, rtl).toFloat()
    val right = left + (shape.size * wb.width).toFloat()
    val lit = Color.Black.copy(alpha = bright)
    val unlit = Color.Black.copy(alpha = dark)
    val near = shape.brightStop.toFloat()
    val far = shape.darkStop.toFloat()
    val mask = if (rtl) {
        Brush.horizontalGradient(0f to unlit, near to unlit, far to lit, 1f to lit, startX = left, endX = right)
    } else {
        Brush.horizontalGradient(0f to lit, near to lit, far to unlit, 1f to unlit, startX = left, endX = right)
    }
    val canvas = drawContext.canvas
    canvas.saveLayer(area, Paint())
    paint(1f)
    drawRect(mask, topLeft = area.topLeft, size = area.size, blendMode = BlendMode.DstIn)
    canvas.restore()
}

// A word at one brightness: whole, or letter by letter while it blooms.
private fun DrawScope.paintWord(
    wb: WordBox,
    glyphs: List<GlyphBox>?,
    bloom: Emphasis?,
    word: SyncWord,
    t: Double,
    rise: Float,
    em: Float,
    lift: Double,
    background: Boolean,
    color: Color,
    alpha: Float,
) {
    if (glyphs == null || bloom == null) {
        drawText(wb.layout, color, Offset(wb.x, wb.top + rise), alpha)
        return
    }
    glyphs.forEachIndexed { k, glyph ->
        val pose = glyphPose(t, word.start, bloom, k, glyphs.size)
        val bob = bobEm(t, word.start, bloom, k, lift, background) * em
        val x = wb.x + glyph.x + (pose.dxEm * em).toFloat()
        val y = wb.top + rise + (pose.dyEm * em + bob).toFloat()
        val radius = (bloom.glowRadiusEm * em).toFloat()
        val glow = if (pose.glowAlpha > 0.01 && radius > 0.5f) {
            Shadow(Color.White.copy(alpha = pose.glowAlpha.toFloat().coerceAtMost(1f)), Offset.Zero, radius)
        } else {
            null
        }
        val scale = pose.scale.toFloat()
        withTransform({
            translate(x, y)
            scale(scale, scale, pivot = Offset(glyph.width / 2f, glyph.layout.size.height / 2f))
        }) {
            drawText(glyph.layout, color, Offset.Zero, alpha, glow)
        }
    }
}

// The three dots of an interlude, centred in its current height.
private fun DrawScope.drawDots(engine: LyricEngine, st: LineState, shown: LyricsLayout, color: Color, calm: Boolean) {
    if (st.status != LineStatus.Active) return
    val line = st.line
    val spec = shown.spec
    val pose = if (calm) StillDots else dotsPose(engine.lyricTime - line.start, line.end - line.start, st.grownIn)
    val dot = DOT_EM * spec.em
    val gap = DOT_GAP_EM * spec.em
    val across = 3 * dot + 2 * gap
    val startX = if (line.alignRight) spec.left + spec.available - across else spec.left
    val middle = (st.height / 2).toFloat()
    repeat(3) { k ->
        drawCircle(
            color = color,
            radius = dot / 2 * pose.scale.toFloat(),
            center = Offset(startX + dot / 2 + k * (dot + gap), middle),
            alpha = (pose.opacity * pose.lights[k]).toFloat().coerceIn(0f, 1f),
        )
    }
}

// The time a long-pressed line starts, in a small pill just above it.
@Composable
private fun TimeStamp(engine: LyricEngine, index: Int, shown: LyricsLayout, offsetMs: Long) {
    val st = engine.states[index]
    val text = remember(index, offsetMs) { clockText(heardAt((st.line.start * 1000).roundToLong(), offsetMs)) }
    Text(
        text,
        style = StampStyle,
        color = Color.White,
        modifier = Modifier
            .graphicsLayer {
                st.layerVersion.intValue
                val top = st.y.value() + engine.scrollOffset
                translationY = (top - size.height - 4.dp.toPx()).toFloat()
                translationX = if (st.line.alignRight) shown.spec.left + shown.spec.available - size.width else shown.spec.left
            }
            .background(StampFill, CircleShape)
            .border(0.5.dp, StampEdge, CircleShape)
            .padding(horizontal = 8.dp, vertical = 3.dp),
    )
}

// A time as the player shows it, like 1:05.
private fun clockText(ms: Long): String = (ms / 1000).coerceAtLeast(0).toInt().asClock()

// What each word-by-word line draws while holding still: a count that goes
// up whenever that changes, for the line's resting drawing to read. It
// changes when a word starts or stops moving, and with the line's
// brightness, its word animation being got ready or let go, and its being
// sung long ago.
private class LineRests {
    private val counts = HashMap<Int, MutableIntState>()
    private val keys = HashMap<Int, Long>()

    fun line(index: Int): IntState = counts.getOrPut(index) { mutableIntStateOf(0) }

    fun follow(engine: LyricEngine, shown: IntRange, calm: Boolean) {
        val t = engine.lyricTime
        for (index in shown) {
            val st = engine.states.getOrNull(index) ?: continue
            val words = st.line.words
            if (words.isEmpty() || st.line.isLineTimed || st.line.isInterlude) continue
            var key = st.brightness().hashCode().toLong()
            key = key * 31 + (if (st.live) 1 else 0) + (if (st.status == LineStatus.Passed) 2 else 0) + (if (calm) 4 else 0)
            key = key * 31 + engine.look.hashCode()
            for (j in words.indices) if (wordMoves(t, words[j])) key = key * 31 + j + 1
            if (keys[index] != key) {
                keys[index] = key
                (counts.getOrPut(index) { mutableIntStateOf(0) }).intValue++
            }
        }
    }
}
