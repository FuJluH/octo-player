package app.winters.octo.player

import androidx.compose.ui.text.TextLayoutResult
import androidx.compose.ui.text.TextMeasurer
import androidx.compose.ui.text.TextStyle
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.text.style.TextDirection
import androidx.compose.ui.unit.Constraints
import androidx.compose.ui.unit.Density
import androidx.compose.ui.unit.em
import androidx.compose.ui.unit.sp
import app.winters.octo.lyrics.engine.heldWords
import app.winters.octo.lyrics.engine.SyncLine
import java.text.BreakIterator
import kotlin.math.max

// The main line's size: the view's width over 20, kept within these.
private const val MIN_LINE_SP = 22f
private const val MAX_LINE_SP = 36f

// Everything else is sized from the main line's size (em).
private const val ROW_HEIGHT_EM = 1.2f
private const val LINE_PADDING_EM = 0.25f
private const val WORD_GAP_EM = 0.25f
private const val EXTRA_SIZE_EM = 0.5f
private const val EXTRA_LINE_HEIGHT = 1.3f
private const val EXTRA_GAP_EM = 0.1f
private const val BACKGROUND_SIZE_EM = 0.75f
private const val BACKGROUND_MIN_DP = 12f
private const val CREDIT_SIZE_EM = 0.4f
private const val CREDIT_MIN_DP = 13f

// An interlude closed, in dp.
private const val INTERLUDE_IDLE_DP = 10f

// A word as laid out: its text, where it is drawn, and the row it sits in.
internal class WordBox(
    val layout: TextLayoutResult,
    val x: Float,
    val top: Float,
    val width: Float,
    val rowTop: Float,
    val rowHeight: Float,
)

// One letter of a held word, drawn on its own so it can swell. `x` is from
// the word's left edge.
internal class GlyphBox(val layout: TextLayoutResult, val x: Float, val width: Float)

// A block of text drawn whole: a line timed by line, the credit, or a
// translation or romanization under a line.
internal class TextPiece(val layout: TextLayoutResult, val x: Float, val y: Float)

// One line as laid out, in pixels from its own top left.
internal class LineBox(
    val height: Float,
    // Its main text's size.
    val em: Float,
    val style: TextStyle,
    // Word by word, in the line's order; empty for a line drawn whole.
    val words: List<WordBox>,
    val block: TextPiece?,
    val extras: List<TextPiece>,
    // Where it grows from: the edge its text starts at.
    val pivotX: Float,
) {
    // Each held word's letters, while the line is near the focus, and which
    // of its words are held (see heldWords).
    var glyphs: Array<List<GlyphBox>?>? = null
    var held: BooleanArray? = null
}

// The sizes every line shares, worked out from the view's width.
internal class LyricsSpec(val width: Int, density: Density) {
    val em: Float
    val left: Float
    val right: Float
    val available: Float
    val style: TextStyle
    val backgroundSize: Float
    val creditSize: Float
    val interludeIdle: Float
    val interludeFull: Float
    private val pxPerSp = density.fontScale * density.density

    init {
        val widthDp = width / density.density
        // Large enough to read at arm's length: about 30 sp on a typical phone.
        val size = (widthDp / 13f).coerceIn(MIN_LINE_SP, MAX_LINE_SP)
        em = size * pxPerSp
        left = (width * 0.06f).coerceIn(24f * density.density, 48f * density.density)
        right = (width * 0.04f).coerceIn(16f * density.density, 56f * density.density)
        available = max(1f, width - left - right)
        style = TextStyle(fontSize = size.sp, fontWeight = FontWeight.ExtraBold)
        backgroundSize = max(BACKGROUND_SIZE_EM * em, BACKGROUND_MIN_DP * density.density)
        creditSize = max(CREDIT_SIZE_EM * em, CREDIT_MIN_DP * density.density)
        interludeIdle = INTERLUDE_IDLE_DP * density.density
        interludeFull = ROW_HEIGHT_EM * em + 2 * LINE_PADDING_EM * em
    }

    fun spOf(px: Float) = (px / pxPerSp).sp
}

// All the lines as laid out for one width.
internal class LyricsLayout(val spec: LyricsSpec, val lines: List<LineBox>) {
    val width: Int get() = spec.width

    // Heights for the engine; an interlude counts closed.
    fun baseHeights(): DoubleArray = DoubleArray(lines.size) { lines[it].height.toDouble() }

    // Splits a line's held words into letters, so they can swell one by one;
    // `fast` when fast singing blooms too.
    fun prepare(index: Int, line: SyncLine, measurer: TextMeasurer, fast: Boolean) {
        val box = lines[index]
        if (box.words.isEmpty()) return
        val held = heldWords(line.words, fast)
        box.held = held
        box.glyphs = Array(line.words.size) { j ->
            if (held[j]) letters(box.words[j], line.words[j].text, box.style, line.rtl, measurer) else null
        }
    }

    fun release(index: Int) {
        lines[index].glyphs = null
        lines[index].held = null
    }
}

// Lays out one line.
internal fun measureLine(line: SyncLine, spec: LyricsSpec, measurer: TextMeasurer): LineBox {
    val pivot = if (line.alignRight) spec.left + spec.available else spec.left
    if (line.isInterlude) {
        return LineBox(spec.interludeIdle, spec.em, spec.style, emptyList(), null, emptyList(), pivot)
    }
    val em = when {
        line.isBackground -> spec.backgroundSize
        line.isCredit -> spec.creditSize
        else -> spec.em
    }
    val style = spec.style.copy(
        fontSize = spec.spOf(em),
        fontWeight = if (line.isCredit) FontWeight.SemiBold else FontWeight.ExtraBold,
    )
    val padding = LINE_PADDING_EM * em
    // Right and left as the eye sees them: an Arabic or Hebrew line is right
    // to left, where End would mean the left edge.
    val align = if (line.alignRight) TextAlign.Right else TextAlign.Left
    val direction = if (line.rtl) TextDirection.Rtl else TextDirection.Ltr
    val whole = Constraints(minWidth = spec.available.toInt(), maxWidth = spec.available.toInt())

    var bottom: Float
    var words = emptyList<WordBox>()
    var block: TextPiece? = null
    if (line.isLineTimed || line.isCredit || line.words.isEmpty()) {
        val layout = measurer.measure(
            line.text,
            style.copy(lineHeight = ROW_HEIGHT_EM.em, textAlign = align, textDirection = direction),
            constraints = whole,
        )
        block = TextPiece(layout, spec.left, padding)
        bottom = padding + layout.size.height
    } else {
        words = flowWords(line, style, em, padding, spec, measurer)
        bottom = (words.maxOfOrNull { it.rowTop + it.rowHeight } ?: padding)
    }

    val extras = mutableListOf<TextPiece>()
    val extraStyle = spec.style.copy(
        fontSize = spec.spOf(EXTRA_SIZE_EM * em),
        fontWeight = FontWeight.SemiBold,
        lineHeight = EXTRA_LINE_HEIGHT.em,
        textAlign = align,
    )
    listOfNotNull(line.romanization, line.translation).forEach { text ->
        bottom += EXTRA_GAP_EM * em
        val layout = measurer.measure(text, extraStyle, constraints = whole)
        extras += TextPiece(layout, spec.left, bottom)
        bottom += layout.size.height
    }
    return LineBox(bottom + padding, em, style, words, block, extras, pivot)
}

// Word by word: syllables of one word sit flush, a quarter em follows each
// whole word, and whole words wrap to the next row. Right-to-left lines
// run from the right; right-aligned lines sit against the right edge.
private fun flowWords(line: SyncLine, style: TextStyle, em: Float, padding: Float, spec: LyricsSpec, measurer: TextMeasurer): List<WordBox> {
    val measured = line.words.map { measurer.measure(it.text, style, softWrap = false, maxLines = 1) }
    val gap = WORD_GAP_EM * em
    val rowHeight = ROW_HEIGHT_EM * em

    // Words into groups (one sung word each), groups into rows.
    val groups = mutableListOf<IntRange>()
    var from = 0
    line.words.forEachIndexed { index, word ->
        if (word.trailingSpace || index == line.words.lastIndex) {
            groups += from..index
            from = index + 1
        }
    }
    val rows = mutableListOf<MutableList<IntRange>>()
    var used = 0f
    groups.forEach { group ->
        val width = group.sumOf { measured[it].size.width.toDouble() }.toFloat()
        val row = rows.lastOrNull()
        if (row == null || (row.isNotEmpty() && used + width > spec.available)) {
            rows += mutableListOf(group)
            used = width + gap
        } else {
            row += group
            used += width + gap
        }
    }

    val boxes = arrayOfNulls<WordBox>(line.words.size)
    rows.forEachIndexed { r, row ->
        val rowTop = padding + r * rowHeight
        val rowWidth = row.sumOf { group -> group.sumOf { measured[it].size.width.toDouble() } }.toFloat() + gap * (row.size - 1)
        val start = if (line.alignRight) spec.left + spec.available - rowWidth else spec.left
        var along = 0f
        row.forEach { group ->
            group.forEach { index ->
                val layout = measured[index]
                val width = layout.size.width.toFloat()
                val x = if (line.rtl) start + rowWidth - along - width else start + along
                boxes[index] = WordBox(layout, x, rowTop + (rowHeight - layout.size.height) / 2, width, rowTop, rowHeight)
                along += width
            }
            along += gap
        }
    }
    return boxes.map { requireNotNull(it) }
}

// A held word's letters (a letter being what reads as one character, so
// accents stay on their letters), spaces left out. Right-to-left words stay
// whole, since their letters join and would break apart if drawn singly.
private fun letters(word: WordBox, text: String, style: TextStyle, rtl: Boolean, measurer: TextMeasurer): List<GlyphBox> {
    if (rtl) return listOf(GlyphBox(word.layout, 0f, word.width))
    val breaks = BreakIterator.getCharacterInstance()
    breaks.setText(text)
    val glyphs = mutableListOf<GlyphBox>()
    var start = breaks.first()
    var end = breaks.next()
    while (end != BreakIterator.DONE) {
        val piece = text.substring(start, end)
        if (piece.isNotBlank()) {
            val layout = measurer.measure(piece, style, softWrap = false, maxLines = 1)
            val x = word.layout.getBoundingBox(start).left
            glyphs += GlyphBox(layout, x, layout.size.width.toFloat())
        }
        start = end
        end = breaks.next()
    }
    return glyphs
}
