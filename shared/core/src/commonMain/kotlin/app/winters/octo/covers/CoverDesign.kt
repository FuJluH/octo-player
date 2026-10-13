package app.winters.octo.covers

import kotlin.math.max
import kotlin.math.min
import kotlin.math.roundToInt

// A playlist's cover: one of the painted backgrounds (chosen by the list's
// music), the colour-keeping veil where the words sit, and white words at
// the top left (its name large, a light line under it saying what it is)
// with a small line at the foot. The numbers are in cover-design.json
// (CoverBook), the backgrounds in backgrounds/backgrounds.json.

// What a cover is made from: whose it is (its id), the name, the light line
// under it ("Playlist", "Live list"), the small line at the foot ("12
// songs", "By sam"), and its music's colour. `coverTitle` is shorter words
// the server gives a list's cover in place of its name; `glyph`, when set,
// is drawn in place of every word.
data class CoverSpec(
    val id: String,
    val name: String,
    val line: String?,
    val footer: String?,
    val palette: CoverPalette,
    val coverTitle: String? = null,
    val glyph: CoverGlyph? = null,
)

enum class CoverAlign { Left, Right }

// Which words: the name, the line under it, or the foot line.
enum class CoverRole { Title, Line, Footer }

// Words on a cover: which, what, how they are set, the box they are set in,
// how they sit in it, their colour (white, perhaps partly see-through), and
// what they measured.
data class CoverWords(
    val role: CoverRole,
    val text: String,
    val type: CoverType,
    val left: Float,
    val top: Float,
    val width: Float,
    val align: CoverAlign,
    val ink: Int,
    val measured: Measured,
) {
    val height: Float get() = measured.height

    // Where the letters themselves are, as left, top, right, bottom.
    val inked: FloatArray
        get() {
            val w = measured.width.coerceAtMost(width)
            val x = if (align == CoverAlign.Left) left else left + width - w
            return floatArrayOf(x, top, x + w, top + measured.height)
        }
}

// A cover ready to paint: its side in pixels, its background and which way
// it is turned, its words or its glyph, and the veil's regions under them.
data class CoverPlan(
    val side: Int,
    val background: CoverBackground,
    val orientation: Int,
    val words: List<CoverWords>,
    val veil: List<VeilRegion>,
    val glyph: GlyphDrawing? = null,
)

private const val White = 0xFFFFFFFF.toInt()

// Everything about a cover `side` pixels square but its pixels: the words
// measured by the app's own text engine.
fun planCover(
    spec: CoverSpec,
    side: Int,
    setter: CoverTypesetter,
    book: CoverBook = CoverBook.Default,
    library: CoverBackgrounds = CoverBackgrounds.Default,
): CoverPlan {
    val background = chooseBackground(spec.id, spec.palette, library, book.background)
    val orientation = coverOrientation(spec.id, book.background)
    val numbers = book.glyphs
    if (spec.glyph != null && numbers != null) {
        val glyph = glyphDrawing(spec.glyph, side, numbers)
        return CoverPlan(side, background, orientation, emptyList(), listOf(glyphVeilRegion(glyph, numbers, book)), glyph)
    }
    val words = coverWords(spec, side, setter, book)
    return CoverPlan(side, background, orientation, words, veilRegions(words, side, book))
}

// Where the words go.
fun coverWords(spec: CoverSpec, side: Int, setter: CoverTypesetter, book: CoverBook = CoverBook.Default): List<CoverWords> {
    val layout = book.layout
    val s = side.toFloat()
    val shown = coverTitle(spec.name, spec.line, spec.coverTitle)
    val rtl = isRightToLeft(shown.title)
    val align = if (rtl) CoverAlign.Right else CoverAlign.Left
    val name = shown.title
    // A small cover is its artwork alone: at a list's row size the name
    // is beside it anyway.
    if (side < layout.tinyBelowPx) return emptyList()
    val margin = (s * layout.margin).roundToInt().toFloat()
    val width = s - 2 * margin
    val out = mutableListOf<CoverWords>()
    var foot: CoverWords? = null

    // The foot line first, so the name knows how far down it may go.
    var floor = s - margin
    val footerText = spec.footer?.trim()?.takeIf { it.isNotEmpty() && side >= layout.footer.showFromPx }
    if (footerText != null) {
        val f = layout.footer
        val look = CoverType(0f, f.weight, f.tracking, coverLineHeight(coverScript(footerText), f.lineHeight), 1)
        val size = max(f.minPx, s * f.size)
        val fit = fitCoverText(footerText, width, s * 0.2f, 1, f.minPx, size, look, setter)
        val top = s - s * f.bottom - fit.measured.height
        foot = CoverWords(CoverRole.Footer, footerText, fit.type, margin, top, width, align, alpha(White, f.opacity), fit.measured)
        floor = top - s * 0.04f
    }
    if (name.isEmpty()) return listOfNotNull(foot)

    val t = layout.title
    val top = s * t.top
    val lineText = shown.line?.takeIf { side >= layout.line.showFromPx }
    val lineRoom = if (lineText == null) 0f else max(s * t.wrapSize, t.wrapMinPx) * layout.line.shareOfTitle * layout.line.lineHeight
    val room = floor - top - lineRoom
    val look = CoverType(0f, t.weight, t.tracking, coverLineHeight(coverScript(name), t.lineHeight), 1)
    val minPx = max(t.minPx, s * t.minSize)
    val oneLineLeast = max(minPx, max(s * t.oneLineDownTo, t.oneLineMinPx))
    val wrapMost = max(minPx, max(s * t.wrapSize, min(t.wrapMinPx, s * t.size)))
    val title = (if (oneLineLeast <= s * t.size) fitOrNull(name, width, room, 1, oneLineLeast, s * t.size, look, setter) else null)
        ?: fitCoverText(name, width, room, t.maxLines, minPx, wrapMost, look, setter)
    out += CoverWords(CoverRole.Title, name, title.type, margin, top, width, align, White, title.measured)

    if (lineText != null) {
        val l = layout.line
        val lineTop = top + title.measured.height
        val most = max(l.minPx, title.type.sizePx * l.shareOfTitle)
        val lineLook = CoverType(0f, l.weight, l.tracking, coverLineHeight(coverScript(lineText), l.lineHeight), 1)
        val fit = fitCoverText(lineText, width, s, 1, min(l.minPx, most), most, lineLook, setter)
        if (lineTop + fit.measured.height <= floor) out += CoverWords(CoverRole.Line, lineText, fit.type, margin, lineTop, width, align, White, fit.measured)
    }
    return out + listOfNotNull(foot)
}

// The words a cover sets large and the light line under them. A name
// ending in a word that says what the list is (Mix, Radio, Chart) is set
// as two lines, "Discovery" over "Mix", "Bad Bunny" over "Station",
// whatever kind of list it is; "Your Radio" and the like stay whole. A
// `coverTitle` from the server is set as it is. Otherwise the name is set
// whole over `line`, unless the name already says what it is.
data class CoverTitle(val title: String, val line: String?)

fun coverTitle(name: String, line: String?, coverTitle: String? = null): CoverTitle {
    val shown = name.trim()
    var title = coverTitle?.trim()?.takeIf { it.isNotEmpty() } ?: shown
    var said = line?.trim()?.takeIf { it.isNotEmpty() }
    if (title == shown) {
        for ((suffix, word) in KindSuffixes) {
            if (!shown.endsWith(suffix, ignoreCase = true)) continue
            val head = shown.dropLast(suffix.length).trim()
            if (head.length > 1 && Possessives.none { it.equals(head, ignoreCase = true) }) {
                title = head
                said = word
                break
            }
        }
    }
    return CoverTitle(title, said.takeIf { title.isNotEmpty() && !nameSaysWhatItIs(title) })
}

// Name endings that say what a list is, and the word the light line uses
// for each. "New" and "Trending" are not among them: "Something New" is a
// name, not a kind.
private val KindSuffixes = listOf(" Radio" to STATION_COVER_LINE, " Chart" to CHART_COVER_LINE, " Mix" to MIX_COVER_LINE)

// Names that keep their kind word: "Your Radio" stays "Your Radio".
private val Possessives = listOf("Your", "My", "Our")

// Whether a name already ends with the word the second line would add ("Road
// Trip Playlist", "Your Radio"), so the cover leaves that line out, as the
// server's covers do. Only a whole last word counts: "Mixtape" does not.
fun nameSaysWhatItIs(name: String): Boolean {
    val last = name.trim().split(Regex("""[^\p{L}\p{N}]+""")).lastOrNull { it.isNotEmpty() } ?: return false
    return last.lowercase() in KindWords
}

private val KindWords = setOf("mix", "mixes", "radio", "radios", "station", "stations", "playlist", "playlists")

// The colour with this opacity.
internal fun alpha(argb: Int, a: Float): Int = ((a.coerceIn(0f, 1f) * 255).roundToInt() shl 24) or (argb and 0xFFFFFF)
