package app.winters.octo.catalog

import java.math.RoundingMode
import java.text.DecimalFormat
import java.text.DecimalFormatSymbols
import java.text.Normalizer
import java.util.Locale
import java.util.regex.Pattern
import kotlin.math.abs
import kotlin.math.min

// What a comparison of two songs found.
enum class SongVerdict {
    // Another song, or another artist's song.
    Different,

    // The same song in another version: live against studio, a remix, a
    // sped-up upload, a different guest, or a length that is too far off.
    SameSongDifferentVersion,

    // The same recording.
    Same,
}

// A verdict, how sure it is (0 to 1), and why, in words a log or a person
// can read.
data class SongMatch(val verdict: SongVerdict, val confidence: Double, val reason: String) {
    val isSame: Boolean get() = verdict == SongVerdict.Same
}

// How one call site wants songs compared. The defaults are the strict
// reading.
data class SongMatchOptions(
    // How far apart two known lengths may be and still be one recording.
    // Null compares no lengths.
    val lengthToleranceSeconds: Int? = SongIdentity.LENGTH_TOLERANCE_SECONDS,
    // When on, a bracketed subtitle only one title carries ("Blue (Da Ba
    // Dee)" against "Blue") makes them different songs. Off, it only lowers
    // the confidence.
    val extrasMustAgree: Boolean = false,
    // Version markers this caller treats as the same recording, on top of
    // the ones that always are (remaster, explicit, original mix, album
    // version, mono, stereo).
    val alsoNeutral: Set<String> = emptySet(),
) {
    companion object {
        val Default = SongMatchOptions()

        // Lengths left out, for a caller that compares them its own way.
        val AnyLength = SongMatchOptions(lengthToleranceSeconds = null)
    }
}

// One side of a comparison. Seconds is the length when it is known. Isrcs
// are the codes a source gave the song, as it wrote them; anything that is
// not a valid ISRC is ignored.
data class SongRef(val title: String?, val artist: String?, val seconds: Double? = null, val isrcs: List<String?> = emptyList())

// One query to try against a search service, in the order queryVariants
// gives them. Artist is empty for the title-only query.
data class SongQuery(val title: String, val artist: String) {
    // The artist and the title as one free-text query.
    val text: String get() = if (artist.isEmpty()) title else "$artist $title"
}

// A title read into its parts.
// - raw: the title as given.
// - core: what is left once track numbers, a leading "Artist - ", brackets,
//   features and version tails are taken off: the title a person would say.
// - key: the core compared exactly: casefolded, accents and punctuation
//   ignored, with any part number ("Pt. 2") kept.
// - looseKey: the key again with stylized characters read as letters ($ as
//   s, 0 as o, 3 as e, @ as a, ! as i). An additional key, never a
//   replacement.
// - versions: every version marker found, canonical names, sorted.
// - remixers: keys of whoever a remix, mix, dub or edit is credited to.
// - featured: artists the title credits, "(feat. X)".
// - extras: keys of bracketed subtitles that are none of the above, "(Da Ba
//   Dee)".
// - artistFromTitle: the artist a title named in "Artist - Title" form.
// - keyed: the core with its part numbers, before keying: where numbers are
//   still apart.
data class SongTitle(
    val raw: String,
    val core: String,
    val key: String,
    val looseKey: String,
    val versions: List<String>,
    val remixers: List<String>,
    val featured: List<String>,
    val extras: List<String>,
    val artistFromTitle: String?,
    internal val keyed: String = core,
)

// An artist credit read into its parts.
// - display: the credit with channel suffixes, other-script aliases and
//   bracketed guests taken off.
// - names: the artists in it, split on every separator but never inside a
//   known name ("Tyler, The Creator") or before "the" ("Bob Marley & The
//   Wailers"). The first is the primary artist.
// - featured: guests credited in brackets, "Drake (feat. Rihanna)".
// - pieces: parts of a name kept whole only by the "the" rule, so "Bob
//   Marley" alone still matches "Bob Marley & The Wailers".
data class SongArtists(
    val raw: String,
    val display: String,
    val names: List<String>,
    val featured: List<String>,
    val pieces: List<String>,
) {
    val primary: String get() = names.firstOrNull() ?: display
    val isEmpty: Boolean get() = SongIdentity.key(display).isEmpty() && names.isEmpty()
}

// How two artist credits relate.
enum class ArtistAgreement {
    // Either side is empty.
    Unknown,

    // No artist in common.
    None,

    // They share an artist, but each names a guest the other does not.
    Conflict,

    // They share an artist only once stylized characters are read as
    // letters.
    Loose,

    // They share an artist.
    Agree,
}

// A song's keys for remembering it across sources: its primary artist, and
// its title with the version markers that make another recording.
data class SongKeys(val artist: String, val title: String) {
    val matchKey: String get() = "$artist|$title"
}

// One reading of song titles and artist credits for every place the app
// decides whether two songs are the same: merging the library's sources,
// finding a library song for one the server sent, following downloads, and
// the online lyrics. The server reads them the same way; the shared case
// file (song-identity-cases.json in the tests) is the contract both run.
//
// The rules, in the order a title is read:
//
// 1. Fold: Unicode NFKC (fullwidth "＄" and "﹩" become "$", "（" becomes
//    "("), curly quotes and dashes made plain, underscores made spaces,
//    Cyrillic and Greek lookalikes inside a Latin word read as Latin.
// 2. A track number in front ("01 - ", "01. ", "1-01 ") is dropped, and so
//    is a leading "Artist - " when it names the artist (or when no artist
//    was given at all).
// 3. Each bracket is read as a guest ("feat. X"), upload noise ("Official
//    Video"), a part number ("Pt. 2", kept in the key), one or more version
//    markers, or a subtitle.
// 4. A " - " tail that is a version or noise ("- Remastered 2011", "- Live
//    at Wembley") is read the same way, and so is a trailing "feat. X" and
//    a trailing "Remix" or "Sped Up".
// 5. The key is the rest, casefolded, accents stripped, and only letters,
//    digits and the marks some scripts need kept. A title of only symbols
//    or emoji keeps its symbols instead.
//
// Artist credits split on , & ; / 、 x × and with feat ft featuring vs, and
// the whole credit is kept as a candidate beside its parts, so "Simon &
// Garfunkel" and "Earth, Wind & Fire" match themselves however they are
// split. A small alias table covers renamed artists ("Ye" for Kanye West),
// and a bracketed alias in another script ("Ye (侃爷)") is ignored.
//
// Text is read one UTF-16 unit at a time wherever the server does, and the
// patterns spell out their spaces, digits and word edges, so the phone, the
// tests and the server all agree.
object SongIdentity {
    // How far apart two lengths may be and still be one recording.
    const val LENGTH_TOLERANCE_SECONDS = 3

    // Version markers that never make a different recording.
    val NeutralVersions: Set<String> = setOf("remaster", "explicit", "original", "album version", "single version", "mono", "stereo")

    // For telling duplicates apart: a subtitle only one title has ("Song
    // (Interlude)") is another title.
    val StrictTitles = SongMatchOptions(lengthToleranceSeconds = null, extrasMustAgree = true)

    // ---- folding ----------------------------------------------------------

    // The text with its lookalikes made plain, case and accents untouched:
    // NFKC, curly quotes and dashes folded, underscores as spaces,
    // whitespace collapsed. What every other reading starts from, and what a
    // query is sent as.
    fun fold(value: String?): String {
        if (isBlank(value)) return ""
        // Plain ASCII has nothing to normalize and no lookalikes: only its
        // spacing, backticks and underscores change.
        if (value!!.all { it in ' '..'~' }) {
            val plain = value.replace('`', '\'').replace('_', ' ')
            return trimSpace(if ("  " in plain) Whitespace.replace(plain, " ") else plain)
        }
        val text = Normalizer.normalize(value.replace('\u00B4', '\''), Normalizer.Form.NFKC)
        val sb = StringBuilder(text.length)
        for (ch in text) {
            sb.append(
                when (ch) {
                    '\u2018', '\u2019', '\u201A', '\u201B', '\u2032', '`' -> '\''
                    '\u201C', '\u201D', '\u201E', '\u201F', '\u2033' -> '"'
                    '\u2010', '\u2011', '\u2012', '\u2013', '\u2014', '\u2015', '\u2212' -> '-'
                    '\u3010', '\u3016' -> '['
                    '\u3011', '\u3017' -> ']'
                    '\u3014' -> '('
                    '\u3015' -> ')'
                    '_' -> ' '
                    else -> if (isSpace(ch)) ' ' else ch
                },
            )
        }
        return trimSpace(Whitespace.replace(foldMixedScriptWords(sb.toString()), " "))
    }

    // The exact key: casefolded, accents stripped, "&" read as "and", and
    // only letters, digits and combining marks kept. Symbols only when there
    // is nothing else.
    fun key(value: String?): String {
        val lower = lowerFold(fold(value))
        if (lower.isEmpty()) return ""
        val sb = StringBuilder(lower.length)
        forEachCodePoint(lower) { point ->
            val type = Character.getType(point)
            if (Character.isLetterOrDigit(point) || type == NON_SPACING || type == SPACING_MARK) sb.appendCodePoint(point)
        }
        if (sb.isNotEmpty()) return sb.toString()
        // "!!!" or an emoji: nothing is a letter, so the symbols are the name.
        forEachCodePoint(lower) { point -> if (!isSpace(point)) sb.appendCodePoint(point) }
        return sb.toString()
    }

    // The key with stylized characters read as letters, so "$uicideboy$"
    // and "Suicideboys" agree. Only ever an additional key.
    fun looseKey(value: String?): String = key(foldStylized(fold(value)))

    // Stylized characters read as the letters they stand for: $ as s, @ as
    // a, 0 as o and 3 as e when they sit against a letter, ! as i between
    // two letters. "2003", "Blink-182" and "Help!" are left alone.
    fun foldStylized(value: String?): String {
        if (value.isNullOrEmpty()) return ""
        val sb = StringBuilder(value.length)
        for (i in value.indices) {
            val ch = value[i]
            val prev = if (i > 0) value[i - 1] else ' '
            val next = if (i + 1 < value.length) value[i + 1] else ' '
            val letterBeside = prev.isLetter() || next.isLetter()
            val digitBeside = isDigit(prev) || isDigit(next)
            val upper = if (next.isLetter()) isUpper(next) else isUpper(prev)
            val read = when {
                ch == '$' && letterBeside -> 's'
                ch == '@' && letterBeside -> 'a'
                ch == '!' && prev.isLetter() && next.isLetter() -> 'i'
                ch == '0' && letterBeside && !digitBeside -> 'o'
                ch == '3' && letterBeside && !digitBeside -> 'e'
                else -> null
            }
            sb.append(if (read != null) (if (upper) read.uppercaseChar() else read) else ch)
        }
        return sb.toString()
    }

    // The folded text lowercased and without accents, spacing and
    // punctuation kept: for matching words inside something that is not a
    // title, such as a file name.
    fun plain(value: String?): String = lowerFold(fold(value))

    // Cyrillic and Greek letters that look Latin, read as Latin inside a
    // word that also has Latin letters. A word wholly in Cyrillic or Greek
    // is left as it is.
    private val Homoglyphs: Map<Char, Char> = mapOf(
        'А' to 'A', 'В' to 'B', 'Е' to 'E', 'К' to 'K', 'М' to 'M', 'Н' to 'H', 'О' to 'O',
        'Р' to 'P', 'С' to 'C', 'Т' to 'T', 'Х' to 'X', 'І' to 'I', 'Ј' to 'J', 'Ѕ' to 'S',
        'а' to 'a', 'е' to 'e', 'о' to 'o', 'р' to 'p', 'с' to 'c', 'у' to 'y', 'х' to 'x',
        'і' to 'i', 'ј' to 'j', 'ѕ' to 's',
        'Α' to 'A', 'Β' to 'B', 'Ε' to 'E', 'Ζ' to 'Z', 'Η' to 'H', 'Ι' to 'I', 'Κ' to 'K',
        'Μ' to 'M', 'Ν' to 'N', 'Ο' to 'O', 'Ρ' to 'P', 'Τ' to 'T', 'Υ' to 'Y', 'Χ' to 'X',
        'ο' to 'o',
    )

    // Words are runs of letters and marks, read one UTF-16 unit at a time,
    // so a letter outside the basic plane ends a word as it does on the
    // server.
    private fun foldMixedScriptWords(text: String): String {
        val sb = StringBuilder(text.length)
        var i = 0
        while (i < text.length) {
            if (!isLetterOrMark(text[i])) {
                sb.append(text[i++])
                continue
            }
            var end = i
            while (end < text.length && isLetterOrMark(text[end])) end++
            val word = text.substring(i, end)
            val latin = word.any { it in 'A'..'Z' || it in 'a'..'z' }
            if (latin && word.any { it in Homoglyphs }) word.forEach { sb.append(Homoglyphs[it] ?: it) } else sb.append(word)
            i = end
        }
        return sb.toString()
    }

    // Lowercase, the letters that do not decompose spelled out, accents
    // stripped, "&" and a spaced "+" read as "and".
    private fun lowerFold(folded: String): String {
        if (folded.isEmpty()) return ""
        // Plain ASCII has no accents to strip.
        if (folded.all { it < '\u0080' }) return folded.lowercase().replace("&", " and ").replace(" + ", " and ")
        val lower = lowerInvariant(folded)
            .replace("ß", "ss").replace("æ", "ae").replace("œ", "oe").replace("ø", "o")
            .replace("đ", "d").replace("ð", "d").replace("ł", "l").replace("þ", "th").replace("ı", "i")
            .replace("&", " and ").replace(" + ", " and ")
        val decomposed = Normalizer.normalize(lower, Normalizer.Form.NFD)
        val sb = StringBuilder(decomposed.length)
        for (ch in decomposed) {
            // Only the Latin, Greek and Cyrillic accents. A kana's voicing
            // mark is a different letter, and stripping it would make two
            // Japanese titles one.
            if (ch in '\u0300'..'\u036F' || ch in '\u1AB0'..'\u1AFF' || ch in '\u1DC0'..'\u1DFF' || ch in '\uFE20'..'\uFE2F') continue
            sb.append(ch)
        }
        return Normalizer.normalize(sb, Normalizer.Form.NFC)
    }

    // ---- titles -----------------------------------------------------------

    // "01 - ", "01. ", "1-01 ", "2) " in front of a title, with a letter
    // after it. "1-800-273-8255" and "99 Problems" keep their numbers.
    private val TrackNumber = rx(
        """^(?:$D{1,2}-$D{1,3}$S+|$D{1,3}$S*[.)]$S*|$D{1,3}$S+-$S+)(?=[^\p{Nd}\t\n\u000B\f\r\u0085\p{Z}.])""",
    )

    private val Bracket = rx("""$S*[\(\[\{]([^\(\)\[\]\{\}]*)[\)\]\}]""")

    // A bracket a truncated title never closed, "Song (feat. X".
    private val OpenBracket = rx("""$S+[\(\[]([^\(\)\[\]]*)$""")

    private val DashTail = rx("""$S+-$S+""")

    private val TrailingFeature = rx("""$S+(?:feat\.?|ft\.?|featuring)$S+(.+)$""", ignoreCase = true)

    // Version words that mean a version even without brackets at the end of
    // a title, "Mask Off Remix", "Heat Waves Sped Up". Not "live" or "edit":
    // too many titles end in them.
    private val TrailingVersion = rx(
        """$S+(re-?mix|rmx|sped$S*up|speed$S*up|slowed(?:$S*(?:\+|&|and|n)$S*reverb(?:ed)?)?|slowed$S+down|nightcore|instrumental|acapella|a$S*cappella|karaoke(?:$S+version)?|drumless|8d$S+audio)$""",
        ignoreCase = true,
    )

    private val FeatureLead = rx("""^(?:feat\.$S*|ft\.$S*|w/$S*|(?:feat|ft|featuring|with)$S+)(.+)$""", ignoreCase = true)

    private val PartNumber = rx("""^(?:(?:pt|part|vol|volume|chapter|ch|no|book)\.?$S*)?(?:$D{1,3}|[ivx]{1,4})$""", ignoreCase = true)

    private val Year = rx("""^(?:19|20)$D{2}$""")

    // A part number, "Pt. 2", "Part II", "Vol. 3", spelled one way so "Part
    // II" and "Pt. 2" agree.
    private val PartWord = rx("""$B(?:(pt|part)|(vol|volume)|(chapter|ch)|(book))\.?$S*($D{1,3}|[ivx]{1,4})$E""", ignoreCase = true)

    private val Romans = listOf("i", "ii", "iii", "iv", "v", "vi", "vii", "viii", "ix", "x")

    private fun partOf(match: MatchResult): String {
        val groups = match.groups
        val word = when {
            groups[1] != null -> "pt"
            groups[2] != null -> "vol"
            groups[3] != null -> "ch"
            else -> "book"
        }
        val number = lowerInvariant(match.groupValues[5])
        val roman = Romans.indexOf(number)
        return "$word ${if (roman >= 0) (roman + 1).toString() else number}"
    }

    // Words that only ever describe how something was uploaded, never which
    // recording it is. A bracket made only of these is dropped.
    private val UploadNoise = listOf(
        "official", "music", "video", "audio", "lyric", "lyrics", "visualizer", "visualiser",
        "hd", "hq", "uhd", "4k", "8k", "1080p", "720p", "480p", "mv", "m/v", "clip", "videoclip",
        "with", "full", "song", "only", "new", "premiere", "animated",
    )

    private val NeutralPhrase = rx(
        """^(?:from|taken from|as heard (?:in|on)|as featured in|as seen (?:in|on)|theme from|music from)$E""" +
            """|$B(?:soundtrack|ost|motion picture|original score)$E""" +
            """|^bonus(?:$S+tracks?)?(?:$S+(?:edition|version))?$|^(?:prod|produced)$E""" +
            // A release edition is the same recordings packaged again;
            // "Drumless Edition" is a marker below.
            """|^(?:(?:super$S+)?deluxe|expanded|(?:$D+(?:st|nd|rd|th)$S+)?anniversary|special|collector'?s|limited|tour|platinum)(?:$S+(?:edition|version))?$""" +
            """|^(?:copyright free|free download|out now|audio only|single|ep)$""",
        ignoreCase = true,
    )

    private class Marker(pattern: String, val name: String, val credited: Boolean = false, val generic: Boolean = false) {
        val pattern = rx(pattern, ignoreCase = true)
    }

    // Version markers, most specific first. Each match is taken out of the
    // text before the next is looked for, so "Extended Mix" is extended and
    // not also a mix.
    private val Markers = listOf(
        Marker("""${B}radio$S+(?:edit|version|mix|cut)$E""", "radio edit"),
        Marker("""${B}extended(?:$S+(?:mix|version|edit|cut))?$E""", "extended"),
        Marker("""${B}original$S+(?:mix|version)$E""", "original"),
        Marker("""$B(?:album|lp)$S+version$E""", "album version"),
        Marker("""${B}single$S+version$E""", "single version"),
        Marker("""$B(?:$D{4}$S+)?(?:digital(?:ly)?$S+)?re-?master(?:ed)?(?:$S+$D{4})?(?:$S+(?:version|edition))?$E""", "remaster"),
        Marker("""${B}live$E""", "live"),
        Marker("""${B}unplugged$E""", "unplugged"),
        Marker("""${B}acoustic(?:$S+version)?$E""", "acoustic"),
        Marker("""${B}instrumental(?:$S+version)?$E""", "instrumental"),
        Marker("""$B(?:a$S*cappella|acapella)$E""", "acapella"),
        Marker("""${B}demo(?:$S+version)?$E""", "demo"),
        Marker("""$B(?:sped$S*up|speed$S*up)$E""", "sped up"),
        Marker("""${B}slowed(?:$S+down)?$E""", "slowed"),
        Marker("""${B}reverb(?:ed)?$E""", "reverb"),
        Marker("""${B}nightcore$E""", "nightcore"),
        // Editions that change what is played, unlike a deluxe or
        // anniversary one (NeutralPhrase).
        Marker("""${B}drumless$E""", "drumless"),
        Marker("""${B}8d(?:$S+audio)?$E""", "8d"),
        Marker("""${B}piano(?:$S+(?:version|edition|arrangement))?$E""", "piano"),
        Marker("""$B(?:orchestral|symphonic)(?:$S+(?:version|edition|mix))?$E""", "orchestral"),
        Marker("""${B}lo-?fi(?:$S+(?:version|edit|mix))?$E""", "lofi"),
        Marker("""${B}bass$S*boost(?:ed)?$E""", "bass boosted"),
        // Two songs or more in one: never the song asked for. Ahead of
        // "mix", so a megamix is not a mix.
        Marker("""${B}mash(?:$S|-)?ups?$E""", "mashup"),
        Marker("""${B}medley$E""", "medley"),
        Marker("""${B}mega(?:$S|-)?mix$E""", "megamix"),
        Marker("""${B}blend$E""", "blend"),
        Marker("""^(.*?)$S*$B(?:re-?mix(?:ed)?|rmx)$E""", "remix", credited = true),
        Marker("""${B}vip(?:$S+mix)?$E""", "vip"),
        Marker("""${B}bootleg$E""", "bootleg"),
        Marker("""${B}rework(?:ed)?$E""", "rework"),
        Marker("""^(.*?)$S*${B}dub(?:$S+(?:mix|version))?$E""", "dub", credited = true),
        Marker("""$B(?:clean|censored)(?:$S+(?:version|edit))?$E""", "clean"),
        Marker("""$B(?:explicit|dirty)(?:$S+version)?$E""", "explicit"),
        Marker("""${B}mono(?:$S+(?:version|mix))?$E""", "mono"),
        Marker("""${B}stereo(?:$S+(?:version|mix))?$E""", "stereo"),
        Marker(
            """${B}karaoke(?:$S+version)?$E|${B}originally performed by$E|${B}in the style of$E|${B}made (?:popular|famous) by$E|${B}backing (?:version|track)$E""",
            "karaoke",
        ),
        Marker("""${B}cover(?:$S+version)?$E""", "cover"),
        Marker("""${B}reprise$E""", "reprise"),
        Marker("""${B}sessions?$E""", "session"),
        Marker("""^(.*?)$S*${B}mix$E""", "mix", credited = true, generic = true),
        Marker("""^(.*?)$S*${B}edit$E""", "edit", credited = true, generic = true),
        Marker("""${B}version$E""", "version", generic = true),
    )

    // Words in front of a mix that name its kind, not who made it.
    private val NotACredit = setOf("", "the", "official", "club", "dance", "house", "main", "short", "long", "full", "new", "a")

    private enum class Kind { Noise, Feature, Part, Version, Extra }

    private class Reading(val kind: Kind, val versions: List<String>, val credits: List<String>, val names: List<String>)

    // What one bracket or " - " tail says.
    private fun read(inner: String): Reading {
        val text = trimSpace(inner).trim { it == '-' || it == ':' || it == ',' || it == ' ' }
        val versions = ArrayList<String>()
        val credits = ArrayList<String>()
        if (text.isEmpty()) return Reading(Kind.Noise, versions, credits, emptyList())

        val words = text.split(' ', '-').filter { it.isNotEmpty() }
        if (words.all { word -> UploadNoise.any { it.equals(word, ignoreCase = true) } }) {
            return Reading(Kind.Noise, versions, credits, emptyList())
        }

        FeatureLead.find(text)?.let { feature ->
            return Reading(Kind.Feature, versions, credits, splitNames(feature.groupValues[1]).names)
        }

        if (PartNumber.containsMatchIn(text)) return Reading(Kind.Part, versions, credits, emptyList())
        if (NeutralPhrase.containsMatchIn(text) || Year.containsMatchIn(text)) return Reading(Kind.Noise, versions, credits, emptyList())

        var rest = text
        for (marker in Markers) {
            if (marker.generic && versions.isNotEmpty()) continue
            val match = marker.pattern.find(rest) ?: continue
            if (marker.name !in versions) versions += marker.name
            if (marker.credited) {
                val credit = key(match.groupValues[1])
                if (credit !in NotACredit) credits += credit
            }
            rest = rest.substring(0, match.range.first) + " " + rest.substring(match.range.last + 1)
        }
        return if (versions.isNotEmpty()) Reading(Kind.Version, versions, credits, emptyList()) else Reading(Kind.Extra, versions, credits, emptyList())
    }

    // A title read into its core, its key, its version markers and its
    // guests. The artist, when given, lets a leading "Artist - " be
    // recognised; an artist given as empty means the song has none, and then
    // any "X - Y" title is read as artist X and title Y. Null reads the
    // title alone.
    fun parseTitle(title: String?, artist: String? = null): SongTitle {
        val raw = title ?: ""
        var text = fold(raw)
        val versions = ArrayList<String>()
        val remixers = ArrayList<String>()
        val featured = ArrayList<String>()
        val extras = ArrayList<String>()
        val parts = ArrayList<String>()
        var artistFromTitle: String? = null

        fun take(reading: Reading, original: String) {
            when (reading.kind) {
                Kind.Feature -> featured += reading.names
                Kind.Part -> parts += trimSpace(original)
                Kind.Version -> {
                    for (version in reading.versions) if (version !in versions) versions += version
                    remixers += reading.credits
                }
                Kind.Extra -> extras += key(original)
                Kind.Noise -> Unit
            }
        }

        TrackNumber.find(text)?.let { numbered ->
            val after = text.substring(numbered.value.length)
            if (after.any { it.isLetter() }) text = after
        }

        // "Artist - Title": the artist named in front, or any name at all
        // when no artist was given.
        val dash = DashTail.find(text)
        if (dash != null && dash.range.first > 0) {
            val left = text.substring(0, dash.range.first)
            val right = text.substring(dash.range.last + 1)
            val tail = read(right)
            val namesArtist = !isBlank(artist) && namesArtist(left, artist!!)
            val noArtist = artist != null && isBlank(artist) && tail.kind == Kind.Extra && key(right).isNotEmpty()
            if ((namesArtist && key(right).isNotEmpty()) || noArtist) {
                artistFromTitle = trimSpace(left)
                text = right
            }
        }

        for (guard in 0 until 12) {
            val match = Bracket.find(text) ?: break
            val inner = match.groupValues[1]
            val rest = trimSpace(text.substring(0, match.range.first) + " " + text.substring(match.range.last + 1))
            // A title that is nothing but a bracket, "(Exchange)", is the
            // words inside it.
            if (key(rest).isEmpty() && read(inner).kind.let { it == Kind.Extra || it == Kind.Noise }) {
                text = inner
                break
            }
            take(read(inner), inner)
            text = rest
        }
        OpenBracket.find(text)?.let { open ->
            take(read(open.groupValues[1]), open.groupValues[1])
            text = text.substring(0, open.range.first)
        }

        // " - Live at Wembley", " - Remastered 2011": only a tail that says
        // what kind of recording this is. "Pt. 2 - The Return" keeps its tail.
        for (guard in 0 until 4) {
            val last = DashTail.findAll(text).lastOrNull() ?: break
            if (last.range.first == 0) break
            val tail = text.substring(last.range.last + 1)
            val reading = read(tail)
            if (reading.kind != Kind.Version && reading.kind != Kind.Noise && reading.kind != Kind.Feature) break
            take(reading, tail)
            text = text.substring(0, last.range.first)
        }

        TrailingFeature.find(text)?.let { trailing ->
            if (trailing.range.first > 0) {
                featured += splitNames(trailing.groupValues[1]).names
                text = text.substring(0, trailing.range.first)
            }
        }

        for (guard in 0 until 3) {
            val trailing = TrailingVersion.find(text) ?: break
            if (trailing.range.first == 0) break
            take(read(trailing.groupValues[1]), trailing.groupValues[1])
            text = text.substring(0, trailing.range.first)
        }

        var core = trimSpace(trimSpace(Whitespace.replace(text, " ")).trimEnd { it == '-' || it == ':' || it == ',' || it == '/' || it == ' ' })
        if (key(core).isEmpty()) {
            // Nothing is left but brackets or symbols: the whole title is the
            // name.
            val bare = fold(raw).replace("(", " ").replace(")", " ").replace("[", " ").replace("]", " ")
            core = trimSpace(Whitespace.replace(bare, " "))
            extras.clear()
        }
        val keyed = PartWord.replace(if (parts.isNotEmpty()) "$core ${parts.joinToString(" ")}" else core, ::partOf)

        versions.sort()
        return SongTitle(
            raw = raw,
            core = core,
            key = key(keyed),
            looseKey = looseKey(keyed),
            versions = versions,
            remixers = remixers.filter { it.isNotEmpty() }.distinct(),
            featured = featured.filter { key(it).isNotEmpty() }.distinct(),
            extras = extras.filter { it.isNotEmpty() }.distinct(),
            artistFromTitle = artistFromTitle,
            keyed = keyed,
        )
    }

    // The markers of a title that make it a different recording, for this
    // caller.
    fun distinctVersions(title: SongTitle, options: SongMatchOptions? = null): Set<String> =
        title.versions.filterTo(HashSet()) { it !in NeutralVersions && options?.alsoNeutral?.contains(it) != true }

    // Version markers the candidate carries that the request does not ("Song
    // (Live)" for "Song"), empty when it adds none. One-directional, for a
    // request whose title may be more specific than its match's.
    fun addedVersions(requested: String?, candidate: String?, options: SongMatchOptions? = null): Set<String> {
        val want = distinctVersions(parseTitle(requested), options)
        return distinctVersions(parseTitle(candidate), options).filterTo(HashSet()) { it !in want }
    }

    // The title without its guest credits, as a person would write it.
    fun stripFeatures(title: String?): String {
        var text = trimSpace(title ?: "")
        text = Bracket.replace(text) { match ->
            val inner = match.groupValues[1]
            if (read(fold(inner)).kind == Kind.Feature) return@replace ""
            // "(Radio Edit - feat. Pharrell Williams)": the credit goes, the
            // version stays.
            val credit = InnerFeature.find(inner)
            if (credit == null || credit.range.first == 0) return@replace match.value
            val kept = trimSpace(inner.substring(0, credit.range.first)).trimEnd('-', '–', ',', ';', '/', ' ')
            if (kept.isEmpty()) "" else match.value.replace(inner, kept)
        }
        TrailingFeature.find(text)?.let { trailing ->
            if (trailing.range.first > 0) {
                // "Song feat. X (Radio Edit)": the credit goes, a bracket
                // after it stays.
                val rest = text.substring(trailing.range.first)
                val bracket = rest.indexOfAny(charArrayOf('(', '['))
                text = text.substring(0, trailing.range.first) + (if (bracket > 0) " " + rest.substring(bracket) else "")
            }
        }
        // "Song - Radio Edit - feat. X" leaves the dash that led to the credit.
        text = trimSpace(text).trimEnd('-', '–', ',', ' ')
        return trimSpace(Whitespace.replace(text, " "))
    }

    // A guest credit run on after a version inside one bracket, "Radio Edit
    // - feat. X".
    private val InnerFeature = rx("""$S*(?:[-–,;/]$S*)?$B(?:feat\.?|ft\.?|featuring)$S+.+$""", ignoreCase = true)

    // ---- artists ----------------------------------------------------------

    // Names that contain a separator and are still one artist. Keys.
    private val KnownNames = setOf(
        "simonandgarfunkel", "earthwindandfire", "tylerthecreator", "acdc", "crosbystillsandnash",
        "crosbystillsnashandyoung", "emersonlakeandpalmer", "bloodsweatandtears", "peterpaulandmary",
        "hallandoates", "darylhallandjohnoates", "mumfordandsons", "ofmonstersandmen", "belleandsebastian",
        "chaseandstatus", "nicoandvinz", "macklemoreandryanlewis", "samanddave", "peachesandherb",
        "brooksanddunn", "bigandrich", "danandshay", "mattandkim", "sheandhim", "ironandwine",
        "angusandjuliastone", "yearsandyears", "coheedandcambria", "chloexhalle", "aura", "axwellingrosso",
        "aboveandbeyond", "alyandfila", "gabrielanddresden", "dimitrivegasandlikemike", "sonnyandcher",
        "captainandtennille", "ikeandtinaturner", "teganandsara", "ashfordandsimpson",
        "shovelsandrope", "florenceandthemachine",
    )

    // Other names an artist goes by, as keys, to one canonical key. Small on
    // purpose: renames and stage names that sources really do disagree on.
    private val Aliases = mapOf(
        "ye" to "kanyewest", "kanye" to "kanyewest",
        "2pac" to "2pac", "tupac" to "2pac", "tupacshakur" to "2pac", "makaveli" to "2pac",
        "diddy" to "diddy", "pdiddy" to "diddy", "puffdaddy" to "diddy", "seancombs" to "diddy",
        "snooplion" to "snoopdogg", "snoopdoggydogg" to "snoopdogg",
        "yasiinbey" to "mosdef",
        "biggie" to "notoriousbig", "biggiesmalls" to "notoriousbig", "thenotoriousbig" to "notoriousbig",
        "donaldglover" to "childishgambino",
        "princeandthenewpowergeneration" to "prince", "theartistformerlyknownasprince" to "prince",
    )

    private val ArtistSeparator = rx(
        """$S*(?:,|;|/|、|×|&|$S\+$S|$S[•·]$S|${S}x$S(?!(?:feat|ft|featuring|with|and|x)$E|[&,;/])|$S(?:and|with|feat\.?|ft\.?|featuring|vs\.?|pres\.|presents)$S)$S*""",
        ignoreCase = true,
    )

    // " - Topic" and "VEVO" are channel names. The server reads the letter
    // before "VEVO" with case ignored, so either case counts there.
    private val ChannelSuffix = rx("""(?:$S+-$S+topic|(?<=[\p{Lu}\p{Ll}\p{Lt}])vevo|$S+vevo)$""", ignoreCase = true)

    private val HasLatin = rx("[A-Za-z]")

    private fun isJoiner(separator: String): Boolean {
        val s = lowerInvariant(trimSpace(separator))
        return s == "&" || s == "and" || s == "+"
    }

    private class Split(val names: List<String>, val pieces: List<String>)

    private class Part(val start: Int, val end: Int, val before: String)

    // A credit split into its artists, keeping known names and "X & the Y"
    // whole.
    private fun splitNames(credit: String): Split {
        val text = trimSpace(credit)
        if (text.isEmpty()) return Split(emptyList(), emptyList())
        if (key(text) in KnownNames) return Split(listOf(text), emptyList())

        val parts = ArrayList<Part>()
        var at = 0
        var before = ""
        for (separator in ArtistSeparator.findAll(text)) {
            val index = separator.range.first
            if (index > at) parts += Part(at, index, before)
            before = separator.value
            at = index + separator.value.length
        }
        if (at < text.length) parts += Part(at, text.length, before)
        if (parts.isEmpty()) return Split(listOf(text), emptyList())

        val names = ArrayList<String>()
        val starts = ArrayList<Int>()
        val pieces = ArrayList<String>()
        var i = 0
        while (i < parts.size) {
            // The longest run of parts that is a known name, "Tyler, The
            // Creator".
            var end = i
            for (j in parts.size - 1 downTo i + 1) {
                if (key(text.substring(parts[i].start, parts[j].end)) in KnownNames) {
                    end = j
                    break
                }
            }
            val name = trimSpace(text.substring(parts[i].start, parts[end].end))

            // "Bob Marley & The Wailers": a "the" after "&" or "and" belongs
            // to the name before.
            if (end == i && names.isNotEmpty() && isJoiner(parts[i].before) && name.startsWith("the ", ignoreCase = true)) {
                pieces += names.last()
                pieces += name
                names[names.lastIndex] = trimSpace(text.substring(starts.last(), parts[i].end))
                i++
                continue
            }
            names += name
            starts += parts[i].start
            i = end + 1
        }
        return Split(names.filter { key(it).isNotEmpty() }, pieces.filter { key(it).isNotEmpty() })
    }

    // An artist credit read into its artists.
    fun parseArtists(artist: String?): SongArtists {
        val raw = artist ?: ""
        var text = trimSpace(ChannelSuffix.replace(fold(raw), ""))
        val featured = ArrayList<String>()
        // Every bracket goes: "(feat. X)" is a guest, "Ye (侃爷)" the same
        // artist in another script, and "Nirvana (US)" a disambiguation.
        text = Bracket.replace(text) { match ->
            FeatureLead.find(trimSpace(match.groupValues[1]))?.let { featured += splitNames(it.groupValues[1]).names }
            " "
        }
        text = trimSpace(Whitespace.replace(text, " "))
        if (key(text).isEmpty()) text = trimSpace(Whitespace.replace(fold(raw), " "))

        // "Drake feat. Rihanna" names its guest after the separator; the
        // names list keeps it.
        val split = splitNames(text)
        return SongArtists(raw, text, split.names, featured, split.pieces)
    }

    // The artist a credit names first, as written: "Beyoncé" for "Beyoncé
    // feat. Jay-Z", "Tyler, The Creator" for itself.
    fun primaryArtist(artist: String?): String = parseArtists(artist).primary

    // Every key a name can be matched by: itself, without a leading "the",
    // and its alias.
    private fun keysOf(name: String, loose: Boolean): List<String> {
        val key = if (loose) looseKey(name) else key(name)
        if (key.isEmpty()) return emptyList()
        val keys = arrayListOf(key)
        val trimmed = fold(name)
        if (trimmed.startsWith("the ", ignoreCase = true)) {
            val bare = if (loose) looseKey(trimmed.substring(4)) else key(trimmed.substring(4))
            if (bare.isNotEmpty()) keys += bare
        }
        Aliases[key]?.let { keys += it }
        return keys
    }

    private fun keys(names: List<String>, loose: Boolean): Set<String> = names.flatMapTo(HashSet()) { keysOf(it, loose) }

    private class Credit(val artists: SongArtists) {
        val all: List<String> get() = artists.names + artists.featured + artists.pieces + artists.display
        val primary: List<String> get() = listOf(artists.primary, artists.display)
        val named: List<String> get() = artists.names + artists.featured
    }

    // How two credits relate. `bCredits`, when a source lists its artists
    // one by one, is used instead of splitting `b`.
    fun compareArtists(a: String?, b: String?, bCredits: List<String>? = null): ArtistAgreement =
        compareArtists(parseArtists(a), withCredits(parseArtists(b), bCredits))

    private fun withCredits(artists: SongArtists, credits: List<String>?): SongArtists {
        val listed = credits?.map { trimSpace(it) }?.filter { key(it).isNotEmpty() }
        if (listed.isNullOrEmpty()) return artists
        val names = listed.map { parseArtists(it).display }
        return artists.copy(
            display = if (artists.isEmpty) names.joinToString(" & ") else artists.display,
            names = names + artists.names.filter { name -> names.none { key(it) == key(name) } },
        )
    }

    fun compareArtists(a: SongArtists, b: SongArtists): ArtistAgreement {
        if (a.isEmpty || b.isEmpty) return ArtistAgreement.Unknown
        val left = Credit(a)
        val right = Credit(b)

        var found: ArtistAgreement? = null
        for (loose in listOf(false, true)) {
            val allLeft = keys(left.all, loose)
            val allRight = keys(right.all, loose)
            if (keys(left.primary, loose).any { it in allRight } || keys(right.primary, loose).any { it in allLeft }) {
                found = if (loose) ArtistAgreement.Loose else ArtistAgreement.Agree
                break
            }
        }
        if (found == null) return ArtistAgreement.None

        // "Bizarrap, Duki" against "Bizarrap & Rauw Alejandro": one artist in
        // common, and each names a guest the other does not. A name in
        // another script is not counted, since it may be one of the Latin
        // names written its own way. Nor is a name that holds, or is held
        // in, one on the other side: "feat 2 Chainz B.O.B" never had a
        // separator to split on.
        val leftKeys = left.named.filter { HasLatin.containsMatchIn(it) }.map { keys(listOf(it), true) }
        val rightKeys = right.named.filter { HasLatin.containsMatchIn(it) }.map { keys(listOf(it), true) }
        val onlyLeft = leftKeys.any { !credited(it, right) }
        val onlyRight = rightKeys.any { !credited(it, left) }
        return if (onlyLeft && onlyRight) ArtistAgreement.Conflict else found
    }

    // Whether a name is credited on the other side: one of its keys is one
    // there, or holds or is held in one of the other side's names (never its
    // whole credit, which holds every name).
    private fun credited(keys: Set<String>, other: Credit): Boolean {
        val all = keys(other.all, true)
        if (keys.any { it in all }) return true
        val named = keys(other.named + other.artists.pieces, true)
        return keys.any { key ->
            named.any { name -> min(key.length, name.length) >= 3 && (key.contains(name) || name.contains(key)) }
        }
    }

    // The two credits share an artist and do not disagree about the guests.
    fun artistsAgree(a: String?, b: String?, bCredits: List<String>? = null): Boolean =
        compareArtists(a, b, bCredits).let { it == ArtistAgreement.Agree || it == ArtistAgreement.Loose }

    // Whether a name is the artist, in any of the forms a credit is matched
    // by.
    private fun namesArtist(name: String, artist: String): Boolean {
        val candidate = listOf(parseArtists(name).display)
        val credit = Credit(parseArtists(artist))
        val exact = keys(credit.all, false)
        val loose = keys(credit.all, true)
        return keys(candidate, false).any { it in exact } || keys(candidate, true).any { it in loose }
    }

    // ---- ISRCs ------------------------------------------------------------

    // Two letters of country, three of registrant, two digits of year, five
    // of designation.
    private val IsrcShape = Regex("^[A-Z]{2}[A-Z0-9]{3}[0-9]{7}$")

    // An ISRC in its one spelling, or null when the value is not one.
    // Sources write "USRC17607839", "US-RC1-76-07839", "us rc1 76 07839" and
    // with dots, and all of those are one code. Anything that is still not
    // twelve characters of the right shape once the separators are gone
    // counts as no code at all.
    fun normalizeIsrc(value: String?): String? {
        if (isBlank(value)) return null
        val text = Normalizer.normalize(value!!, Normalizer.Form.NFKC)
        val sb = StringBuilder(12)
        for (ch in text) {
            if (ch == '-' || ch == '.' || isSpace(ch)) continue
            // Each character raised on its own, as the server does, and a
            // dotless i left as it is.
            sb.append(if (ch == '\u0131') ch else Character.toUpperCase(ch))
        }
        val isrc = sb.toString()
        return if (IsrcShape.matches(isrc)) isrc else null
    }

    // Every valid ISRC among the values, in its one spelling.
    fun isrcs(values: Iterable<String?>?): Set<String> = values?.mapNotNullTo(HashSet(), ::normalizeIsrc) ?: emptySet()

    // Both sides carry a valid ISRC and at least one is on both.
    fun sharesIsrc(a: Iterable<String?>?, b: Iterable<String?>?): Boolean {
        val left = isrcs(a)
        return left.isNotEmpty() && isrcs(b).any { it in left }
    }

    // ---- comparing --------------------------------------------------------

    private enum class TitleAgreement { None, Exact, Loose, Numbers }

    private fun compareKeys(a: SongTitle, b: SongTitle): TitleAgreement {
        if (a.key.isEmpty() || b.key.isEmpty()) return TitleAgreement.None
        if (a.key == b.key) return TitleAgreement.Exact
        if (a.looseKey == b.looseKey) return TitleAgreement.Loose

        // Numbers compare as sets: "Vol. 53" is "Vol. 53/66", but "Shotta
        // Flow" is never "Shotta Flow 4".
        val lettersA = a.key.filter { it.isLetter() }
        val lettersB = b.key.filter { it.isLetter() }
        if (lettersA.isEmpty() || lettersA != lettersB) return TitleAgreement.None
        val numbersA = numbersIn(a.keyed)
        val numbersB = numbersIn(b.keyed)
        if (numbersA.isEmpty() || numbersB.isEmpty()) return TitleAgreement.None
        return if (numbersB.containsAll(numbersA) || numbersA.containsAll(numbersB)) TitleAgreement.Numbers else TitleAgreement.None
    }

    // Runs of decimal digits, one UTF-16 unit at a time.
    private fun numbersIn(text: String): Set<String> {
        val numbers = HashSet<String>()
        var i = 0
        while (i < text.length) {
            if (!isDigit(text[i])) {
                i++
                continue
            }
            var end = i
            while (end < text.length && isDigit(text[end])) end++
            numbers += text.substring(i, end)
            i = end
        }
        return numbers
    }

    private val CreditedVersions = setOf("remix", "mix", "dub", "edit")

    // Whether two titles are one song, and one version of it. Artists are
    // not looked at.
    fun sameTitle(a: String?, b: String?, options: SongMatchOptions = SongMatchOptions.Default): SongMatch =
        compareTitles(parseTitle(a), parseTitle(b), options)

    private fun compareTitles(a: SongTitle, b: SongTitle, options: SongMatchOptions): SongMatch {
        val agreement = compareKeys(a, b)
        if (agreement == TitleAgreement.None) {
            return SongMatch(
                SongVerdict.Different,
                0.95,
                if (a.key.isEmpty() || b.key.isEmpty()) "a title is empty" else "different titles ('${a.core}' and '${b.core}')",
            )
        }

        var confidence = 1.0
        val reasons = ArrayList<String>()
        if (agreement == TitleAgreement.Loose) {
            confidence -= 0.15
            reasons += "the same title once stylized characters are read as letters"
        }
        if (agreement == TitleAgreement.Numbers) {
            confidence -= 0.1
            reasons += "the same title with numbers that overlap"
        }

        val versionsA = distinctVersions(a, options)
        val versionsB = distinctVersions(b, options)
        if (versionsA != versionsB) {
            return SongMatch(SongVerdict.SameSongDifferentVersion, 0.9, "a different version (${describe(versionsA)} against ${describe(versionsB)})")
        }

        if (versionsA.any { it in CreditedVersions }) {
            if (a.remixers.isNotEmpty() && b.remixers.isNotEmpty() && a.remixers.none { it in b.remixers }) {
                return SongMatch(SongVerdict.SameSongDifferentVersion, 0.85, "remixes by different people")
            }
            if (a.remixers.isNotEmpty() != b.remixers.isNotEmpty()) {
                confidence -= 0.05
                reasons += "only one says who made the remix"
            }
        }

        if (a.extras.isNotEmpty() && b.extras.isNotEmpty() && a.extras.none { it in b.extras }) {
            return SongMatch(SongVerdict.Different, 0.7, "different subtitles")
        }
        if (a.extras.isNotEmpty() != b.extras.isNotEmpty()) {
            if (options.extrasMustAgree) return SongMatch(SongVerdict.Different, 0.7, "only one title has a subtitle")
            confidence -= 0.1
            reasons += "only one title has a subtitle"
        }

        return SongMatch(SongVerdict.Same, round2(confidence), if (reasons.isEmpty()) "the same title" else reasons.joinToString("; "))
    }

    private fun describe(versions: Set<String>): String = if (versions.isEmpty()) "the original" else versions.sorted().joinToString(" + ")

    // Whether two songs are the same recording. Both artists must be known:
    // a title alone is not an identity.
    fun same(a: SongRef, b: SongRef, options: SongMatchOptions = SongMatchOptions.Default): SongMatch {
        // First, and above the text: a romanised title and the same title in
        // its own script share no letter, and one ISRC still says they are
        // one recording. Different ISRCs fall through to the text, since a
        // re-release can carry a new code for the same audio.
        if (sharesIsrc(a.isrcs, b.isrcs)) return SongMatch(SongVerdict.Same, 1.0, "same ISRC")

        val titleA = parseTitle(a.title, a.artist ?: "")
        val titleB = parseTitle(b.title, b.artist ?: "")
        val title = compareTitles(titleA, titleB, options)
        if (title.verdict == SongVerdict.Different) return title

        val artistA = creditOf(a.artist, titleA)
        val artistB = creditOf(b.artist, titleB)
        val artist = compareArtists(artistA, artistB)
        when (artist) {
            ArtistAgreement.Unknown -> return SongMatch(SongVerdict.Different, 0.6, "no artist to compare")
            ArtistAgreement.None -> return SongMatch(SongVerdict.Different, 0.9, "different artists ('${artistA.display}' and '${artistB.display}')")
            else -> Unit
        }
        if (title.verdict == SongVerdict.SameSongDifferentVersion) return title
        if (artist == ArtistAgreement.Conflict) return SongMatch(SongVerdict.SameSongDifferentVersion, 0.75, "different guest artists")

        var confidence = title.confidence
        val reasons = ArrayList<String>()
        if (title.reason != "the same title") reasons += title.reason
        if (artist == ArtistAgreement.Loose) {
            confidence -= 0.1
            reasons += "the same artist once stylized characters are read as letters"
        }

        val tolerance = options.lengthToleranceSeconds
        if (tolerance != null) {
            val secondsA = a.seconds
            val secondsB = b.seconds
            if (secondsA != null && secondsA > 0 && secondsB != null && secondsB > 0) {
                val apart = abs(secondsA - secondsB)
                if (apart > tolerance) return SongMatch(SongVerdict.SameSongDifferentVersion, 0.8, "lengths differ by ${oneDecimal(apart)} s")
            } else {
                confidence -= 0.05
                reasons += "a length is unknown"
            }
        }

        return SongMatch(SongVerdict.Same, round2(confidence.coerceIn(0.0, 1.0)), if (reasons.isEmpty()) "the same song" else reasons.joinToString("; "))
    }

    fun same(aTitle: String?, aArtist: String?, bTitle: String?, bArtist: String?, options: SongMatchOptions = SongMatchOptions.Default): SongMatch =
        same(SongRef(aTitle, aArtist), SongRef(bTitle, bArtist), options)

    // The artist credit of one side, with the guests its title names, and
    // the artist an "Artist - Title" title gave when the credit itself is
    // empty.
    private fun creditOf(artist: String?, title: SongTitle): SongArtists {
        val credit = parseArtists(if (isBlank(artist)) title.artistFromTitle else artist)
        if (title.featured.isEmpty()) return credit
        return credit.copy(featured = credit.featured + title.featured)
    }

    // Within the tolerance, or unknown on either side.
    fun lengthFits(want: Int?, got: Double?, tolerance: Int = LENGTH_TOLERANCE_SECONDS): Boolean =
        want == null || want <= 0 || got == null || got <= 0 || abs(got - want) <= tolerance

    // A key for "this song in this version", for deduplicating and for
    // remembering songs across sources: the primary artist and the title
    // keys, and the version markers that make a different recording. "Drake
    // feat. Rihanna - Too Good" and "Drake - Too Good (feat. Rihanna)" share
    // one; "Song (Live)" has its own.
    fun matchKey(artist: String?, title: String?): String = songKeys(artist, title).matchKey

    // The two halves of matchKey, worked out once.
    fun songKeys(artist: String?, title: String?): SongKeys {
        val parsed = parseTitle(title, artist ?: "")
        val credit = parseArtists(if (isBlank(artist)) parsed.artistFromTitle else artist)
        val primary = key(credit.primary)
        return SongKeys(Aliases[primary] ?: primary, versionedKey(parsed))
    }

    // The title part of matchKey, for songs already known to share an
    // artist, such as the tracks of one album.
    fun titleKey(title: String?): String = versionedKey(parseTitle(title))

    private fun versionedKey(parsed: SongTitle): String {
        val versions = distinctVersions(parsed).sorted()
        return if (versions.isEmpty()) parsed.key else "${parsed.key}|${versions.joinToString("+")}"
    }

    // Every key two titles can agree on, for finding the songs worth
    // comparing before comparing them: the key's letters (the key itself
    // when it has none) and the loose key. Two titles `same` reads as one
    // song always share one.
    fun titleLookupKeys(title: String?, artist: String?): Set<String> {
        val parsed = parseTitle(title, artist ?: "")
        if (parsed.key.isEmpty()) return emptySet()
        val letters = parsed.key.filter { it.isLetter() }
        return setOf(letters.ifEmpty { parsed.key }, parsed.looseKey)
    }

    // Whether two names are one artist, whole: case, accents, a leading
    // "The", stylized characters and the alias table ignored, but never
    // split, so "Bob Marley" is not "Bob Marley & The Wailers". For an artist
    // page, where a credit's guests do not belong.
    fun sameArtistName(a: String?, b: String?): Boolean {
        val left = listOf(parseArtists(a).display)
        val right = listOf(parseArtists(b).display)
        if (key(left[0]).isEmpty() || key(right[0]).isEmpty()) return false
        return keys(left, false).any { it in keys(right, false) } || keys(left, true).any { it in keys(right, true) }
    }

    // ---- searching --------------------------------------------------------

    // The queries to try against a search service, in order, stopping at
    // the first that finds the song:
    //
    // 1. the title and artist as given;
    // 2. the title without brackets, guests or version tails, and the credit
    //    without aliases;
    // 3. the same with stylized characters read as letters ("suicideboys
    //    suicide");
    // 4. the primary artist only;
    // 5. the title alone, as a last resort.
    //
    // A variant that reads the same as an earlier one is left out, so a
    // plain "Drake - Landed" has two. Whatever a variant finds must still
    // pass `same` against the song as asked: a looser query never means a
    // looser match.
    fun queryVariants(title: String?, artist: String?): List<SongQuery> {
        val variants = ArrayList<SongQuery>()
        fun add(t: String, a: String) {
            val queryTitle = trimSpace(Whitespace.replace(t, " "))
            val queryArtist = trimSpace(Whitespace.replace(a, " "))
            if (key(queryTitle).isEmpty()) return
            val seen = variants.any {
                fold(it.title).equals(fold(queryTitle), ignoreCase = true) && fold(it.artist).equals(fold(queryArtist), ignoreCase = true)
            }
            if (!seen) variants += SongQuery(queryTitle, queryArtist)
        }

        val parsed = parseTitle(title, artist ?: "")
        val credit = parseArtists(if (isBlank(artist)) parsed.artistFromTitle else artist)
        var cleanTitle = parsed.core
        val parts = Bracket.findAll(fold(title)).map { trimSpace(it.groupValues[1]) }.filter { PartNumber.containsMatchIn(it) }.toList()
        if (parts.isNotEmpty()) cleanTitle = "$cleanTitle ${parts.joinToString(" ")}"

        add(trimSpace(title ?: ""), trimSpace(artist ?: ""))
        add(cleanTitle, credit.display)
        add(foldStylized(cleanTitle), foldStylized(credit.display))
        add(cleanTitle, credit.primary)
        add(cleanTitle, "")
        return variants
    }

    // ---- reading text the way the server does -----------------------------

    // Patterns spell out what the server's engine means by a space, a digit
    // and the edge of a word, since the phone's engine and the JVM's read
    // the short forms differently.
    internal const val S = """[\t\n\u000B\f\r\u0085\p{Z}]"""
    private const val D = """\p{Nd}"""
    internal const val W = """[\p{L}\p{Mn}\p{Nd}\p{Pc}\u200C\u200D]"""
    private const val B = """(?<!$W)"""
    private const val E = """(?!$W)"""

    private val Whitespace = rx("$S+")

    // Case is ignored for ASCII letters only (every pattern is ASCII, and
    // the text is folded first), and only "\n" ends a line, as on the server.
    private fun rx(pattern: String, ignoreCase: Boolean = false): Regex =
        Pattern.compile(pattern, Pattern.UNIX_LINES or (if (ignoreCase) Pattern.CASE_INSENSITIVE else 0)).toRegex()

    private val NON_SPACING = Character.NON_SPACING_MARK.toInt()
    private val SPACING_MARK = Character.COMBINING_SPACING_MARK.toInt()

    // The server's white space: the Unicode separators, and tab to carriage
    // return and the next-line control. Not the other control characters.
    private fun isSpace(point: Int): Boolean = point in 0x09..0x0D || point == 0x85 || when (Character.getType(point)) {
        Character.SPACE_SEPARATOR.toInt(), Character.LINE_SEPARATOR.toInt(), Character.PARAGRAPH_SEPARATOR.toInt() -> true
        else -> false
    }

    private fun isSpace(ch: Char): Boolean = isSpace(ch.code)

    internal fun isBlank(value: String?): Boolean = value == null || value.all(::isSpace)

    internal fun trimSpace(value: String): String = value.trim(::isSpace)

    private fun isDigit(ch: Char): Boolean = Character.getType(ch) == Character.DECIMAL_DIGIT_NUMBER.toInt()

    private fun isUpper(ch: Char): Boolean = Character.getType(ch) == Character.UPPERCASE_LETTER.toInt()

    private fun isLetterOrMark(ch: Char): Boolean = when (Character.getType(ch)) {
        Character.UPPERCASE_LETTER.toInt(), Character.LOWERCASE_LETTER.toInt(), Character.TITLECASE_LETTER.toInt(),
        Character.MODIFIER_LETTER.toInt(), Character.OTHER_LETTER.toInt(),
        Character.NON_SPACING_MARK.toInt(), Character.ENCLOSING_MARK.toInt(), Character.COMBINING_SPACING_MARK.toInt(),
        -> true
        else -> false
    }

    // Each character lowered on its own, as the server does: no final sigma,
    // and a dotted capital I is left as it is.
    private fun lowerInvariant(text: String): String {
        val sb = StringBuilder(text.length)
        forEachCodePoint(text) { point -> sb.appendCodePoint(if (point == 0x130) point else Character.toLowerCase(point)) }
        return sb.toString()
    }

    // Code points in order, a lone surrogate read as the replacement
    // character.
    private inline fun forEachCodePoint(text: String, action: (Int) -> Unit) {
        var i = 0
        while (i < text.length) {
            val ch = text[i]
            if (Character.isHighSurrogate(ch) && i + 1 < text.length && Character.isLowSurrogate(text[i + 1])) {
                action(Character.toCodePoint(ch, text[i + 1]))
                i += 2
            } else {
                action(if (Character.isSurrogate(ch)) 0xFFFD else ch.code)
                i++
            }
        }
    }

    // Rounded to two places, halves to even, as the server rounds.
    private fun round2(value: Double): Double = Math.rint(value * 100) / 100

    private fun oneDecimal(value: Double): String =
        DecimalFormat("0.#", DecimalFormatSymbols(Locale.ROOT)).apply { roundingMode = RoundingMode.HALF_UP }.format(value)
}
