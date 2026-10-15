package app.winters.octo.catalog

import java.util.regex.Pattern

// Which versions of a song its album says it is, read from where
// SongIdentity does not look: a plainly named track on "Let's Get Lost
// Remixes", "Too Close (Radio Edit) - Single" or "Club Hits (Extended
// Mixes)". Read word for word as the server reads an album, so the two
// agree on what a version is.
object VersionVariant {
    private const val S = SongIdentity.S
    private const val W = SongIdentity.W
    private const val B = "(?<!$W)"
    private const val E = "(?!$W)"

    // Case is ignored for every letter, as the server ignores it.
    private fun rxi(pattern: String): Regex =
        Pattern.compile(pattern, Pattern.UNIX_LINES or Pattern.CASE_INSENSITIVE or Pattern.UNICODE_CASE).toRegex()

    // Words that name a version wherever they stand, bracketed or not,
    // under SongIdentity's own names so the two readings can be compared.
    // Only words no album, artist or label is likely to be called: no bare
    // "clean" (Clean Bandit) or "acoustic" (Acoustic Soul); a bracket still
    // reads those.
    private val Words: List<Pair<Regex, String>> = listOf(
        rxi("${B}radio$S+(?:edit|version|mix|cut)s?$E") to "radio edit",
        rxi("${B}extended$E(?!$S+(?:edition|play)$E)") to "extended",
        rxi("$B(?:re-?mix(?:es|ed)?|rmx)$E") to "remix",
        rxi("$B(?:sped|speed)$S*up$E") to "sped up",
        rxi("${B}slowed$E") to "slowed",
        rxi("${B}nightcore$E") to "nightcore",
        rxi("${B}instrumentals?$E") to "instrumental",
        rxi("$B(?:a$S*cappellas?|acapellas?)$E") to "acapella",
        rxi("${B}karaoke$E") to "karaoke",
        rxi("${B}drumless$E") to "drumless",
        rxi("${B}mash(?:$S|-)?ups?$E") to "mashup",
        rxi("${B}medley$E") to "medley",
        rxi("${B}mega(?:$S|-)?mix$E") to "megamix",
        rxi("${B}8d$S+audio$E") to "8d",
        rxi("$B(?:dj|continuous|non-?stop)$S+mix(?:es)?$E|${B}mixed$S+by$E") to "dj mix",
    )

    // What an album's brackets can say that is no version of the songs on
    // it: a generic "(Japanese Version)" or "(Mix)", a label called
    // Reprise, a "[+cover]" scan, a VIP pack, and the live words.
    private val NotFromAnAlbum = setOf("mix", "edit", "version", "reprise", "cover", "vip", "live", "unplugged", "bootleg")

    // An album edition, not a version of its songs.
    private val Edition = rxi("${B}extended$S+(?:edition|play)$E")

    // The words in a text, in the list's order.
    private fun wordsIn(text: String?): List<String> {
        if (text == null || SongIdentity.isBlank(text)) return emptyList()
        return Words.filter { (pattern, _) -> pattern.containsMatchIn(text) }.map { it.second }
    }

    // A title's versions that make it a different recording, as
    // SongIdentity reads them.
    private fun distinct(title: String): Set<String> = SongIdentity.distinctVersions(SongIdentity.parseTitle(title))

    // The versions a title and an album ask for.
    fun requested(title: String?, album: String?): Set<String> {
        val wanted = LinkedHashSet<String>()
        for (text in listOfNotNull(title, album)) {
            if (SongIdentity.isBlank(text)) continue
            wanted += distinct(text)
            wanted += wordsIn(text)
        }
        return wanted
    }

    // A letter or a number in one UTF-16 code unit: half of a surrogate
    // pair is neither.
    private fun letterOrNumber(ch: Char): Boolean = Character.isLetter(ch) || when (Character.getType(ch)) {
        Character.DECIMAL_DIGIT_NUMBER.toInt(), Character.LETTER_NUMBER.toInt(), Character.OTHER_NUMBER.toInt() -> true
        else -> false
    }

    // Whether a match from `start` to `end` stands alone: no letter or
    // number right before or after it.
    private fun standsAlone(text: String, start: Int, end: Int): Boolean =
        !(start > 0 && letterOrNumber(text[start - 1])) && !(end < text.length && letterOrNumber(text[end]))

    // Every match of the pattern that stands alone, left to right and never
    // overlapping: a start where the bounds fail is tried again one
    // character on.
    private fun aloneMatches(pattern: Regex, text: String): List<IntRange> {
        val found = ArrayList<IntRange>()
        var at = 0
        while (at <= text.length) {
            val candidate = pattern.find(text, at) ?: break
            val start = candidate.range.first
            val end = candidate.range.last + 1
            if (end > start && standsAlone(text, start, end)) {
                found += start until end
                at = end
            } else {
                at = start + if (start < text.length) Character.charCount(text.codePointAt(start)) else 1
            }
        }
        return found
    }

    // The text with the artist's own name taken out, so a band called Live,
    // or an album named after its artist, is never read as a version.
    fun withoutArtist(text: String, artist: String?): String {
        if (artist == null || SongIdentity.isBlank(artist)) return text
        if (text.isEmpty()) return text
        val names = ArrayList(SongIdentity.parseArtists(artist).names)
        names += SongIdentity.trimSpace(artist)
        names.retainAll { SongIdentity.trimSpace(it).length > 1 }
        // Longest first, names of one length in their order.
        names.sortByDescending { it.length }
        var result = text
        for (name in names) {
            val found = aloneMatches(rxi(Pattern.quote(SongIdentity.trimSpace(name))), result)
            if (found.isEmpty()) continue
            val replaced = StringBuilder(result.length)
            var last = 0
            for (range in found) {
                replaced.append(result, last, range.first).append(' ')
                last = range.last + 1
            }
            replaced.append(result, last, result.length)
            result = replaced.toString()
        }
        return result
    }

    // The versions an album's name says its songs are, live words left out.
    fun inFolder(folder: String, artist: String?): Set<String> {
        val text = Edition.replace(withoutArtist(folder, artist), " ")
        val found = distinct(text).filterTo(LinkedHashSet()) { it !in NotFromAnAlbum }
        found += wordsIn(text)
        return found
    }
}
