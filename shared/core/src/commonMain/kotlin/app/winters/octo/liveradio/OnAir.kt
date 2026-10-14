package app.winters.octo.liveradio

// What a live station has on air, read from its ICY metadata: the song and
// its artist, the song's artwork, or, while it names no song (between
// songs, an ad, the station's own spot), nothing but maybe a tagline such
// as "LA's #1 Hit Music Station". Every app reads a stream's titles with
// these rules.
data class OnAir(
    val title: String = "",
    val artist: String = "",
    val artwork: String = "",
    val tagline: String = "",
) {
    // Whether the station names a song now.
    val named: Boolean get() = title.isNotEmpty()

    companion object {
        val Nothing = OnAir()
    }
}

// The fields of one ICY metadata block, `StreamTitle='...';StreamUrl='...';`,
// by name. A value ends at the quote that closes it, the one before the
// next `;Key='` or the end of the block, so a quote inside a name stays in
// it ("LA's #1", "I DON'T WANNA MISS A THING").
fun icyFields(block: String): Map<String, String> {
    val text = block.trimEnd('\u0000')
    val fields = LinkedHashMap<String, String>()
    var at = 0
    while (at < text.length) {
        val eq = text.indexOf("='", at)
        if (eq < 0) break
        val key = text.substring(at, eq).trim().trimStart(';').trim()
        val start = eq + 2
        val end = icyValueEnd(text, start)
        if (key.isNotEmpty() && key.all { it.isLetterOrDigit() || it == '_' || it == '-' }) {
            fields.putIfAbsent(key, text.substring(start, end))
        }
        at = (end + 1).coerceAtMost(text.length)
        if (at < text.length && text[at] == ';') at++
    }
    return fields
}

// Where a value that starts at `start` ends: at a `';` that the next key or
// the end of the block follows, else at a quote that ends the block, else at
// the end.
private fun icyValueEnd(text: String, start: Int): Int {
    var search = start
    while (true) {
        val close = text.indexOf("';", search)
        if (close < 0) break
        val after = close + 2
        if (after >= text.length || NextKey.matchesAt(text, after) || text.substring(after).isBlank()) return close
        search = close + 1
    }
    val end = text.trimEnd().length
    return if (end - 1 >= start && text[end - 1] == '\'') end - 1 else text.length
}

private val NextKey = Regex("""\s*[A-Za-z][A-Za-z0-9_-]*='""")

// What a station has on air from the title its stream sends (the
// StreamTitle value) and the address it sends with it (StreamUrl, or
// StreamArtwork), for a station called `station`.
//
// - "Artist - Title" splits at the first " - "; a title with no dash is a
//   title alone; "- Advertisement" is a title alone too.
// - iHeart's `Artist - text="Title" song_spot="M" amgArtworkURL="..." ...`
//   shows only the artist and the text (or `title="..."` and
//   `artist="..."`), with the artwork; a song_spot other than "M" is not a
//   song, and what it says that is not the station's name is its tagline.
// - Nothing is named by an empty title, one with no letter or digit, the
//   station's own name, a playout cart code ("GWMR0446000") or an ad
//   ("Advertisement").
// - The address is the artwork when it is an image (Radio Paradise's covers,
//   SomaFM's logos).
fun onAir(streamTitle: String?, streamUrl: String? = null, station: String = ""): OnAir {
    val raw = squash(streamTitle.orEmpty()).take(TITLE_MAX)
    if (raw.isEmpty()) return OnAir.Nothing
    val pairs = KeyValue.findAll(raw).toList()
    val stationKey = plainKey(station)
    if (pairs.isNotEmpty()) {
        val keys = pairs.associate { it.groupValues[1].lowercase() to squash(it.groupValues[2]) }
        val lead = squash(raw.substring(0, pairs.first().range.first)).trimEnd('-', ' ').trim()
        val title = keys["text"]?.takeIf(String::isNotEmpty) ?: keys["title"].orEmpty()
        val artist = keys["artist"]?.takeIf(String::isNotEmpty) ?: lead
        val spot = keys["song_spot"]?.trim().orEmpty()
        val music = spot.isEmpty() || spot.equals("M", ignoreCase = true)
        val artwork = (keys["amgartworkurl"]?.takeIf(::isWebAddress)?.let(::sharperArtwork))
            ?: keys["artworkurl"]?.takeIf(::isWebAddress)
            ?: streamUrl?.trim()?.takeIf(::isImageAddress).orEmpty()
        if (!music || namesNothing(title, artist, stationKey)) {
            return OnAir(tagline = taglineOf(listOf(artist, title), stationKey))
        }
        return OnAir(title, artist, artwork)
    }
    val (artist, title) = splitArtist(raw)
    if (namesNothing(title, artist, stationKey)) return OnAir.Nothing
    return OnAir(title, artist, streamUrl?.trim()?.takeIf(::isImageAddress).orEmpty())
}

// The artwork address in a block's StreamUrl or StreamArtwork, for onAir.
fun icyArtworkField(fields: Map<String, String>): String? =
    listOfNotNull(fields["StreamArtwork"], fields["StreamUrl"]).map(String::trim).firstOrNull { it.isNotEmpty() }

// iHeart's artwork asked for at the size the player draws: its catalog
// addresses say `ops=fit(200,200)`, which is blurry on a phone, and it
// serves any fit up to the original. Other addresses stay as they are.
fun sharperArtwork(url: String): String {
    val host = url.substringAfter("://", "").substringBefore('/').substringBefore(':').lowercase()
    if (host != "iheart.com" && !host.endsWith(".iheart.com")) return url
    return IHeartFit.replace(url) { match ->
        val size = match.groupValues[1].toIntOrNull() ?: return@replace match.value
        if (size >= ARTWORK_SIZE) match.value else "fit($ARTWORK_SIZE,$ARTWORK_SIZE)"
    }
}

private val IHeartFit = Regex("""fit\((\d+),\s*\d+\)""")

// The longest side asked of a station's artwork, in pixels.
const val ARTWORK_SIZE = 600

// "Artist - Title" at its first " - ", or a title alone.
private fun splitArtist(text: String): Pair<String, String> {
    val bare = text.trim()
    if (bare.startsWith("-")) return "" to bare.trimStart('-', ' ')
    val dash = bare.indexOf(" - ")
    if (dash < 0) return "" to bare
    return bare.substring(0, dash).trim() to bare.substring(dash + 3).trim().trimStart('-', ' ')
}

private fun namesNothing(title: String, artist: String, stationKey: String): Boolean {
    if (title.none { it.isLetterOrDigit() }) return true
    val titleKey = plainKey(title)
    if (stationKey.isNotEmpty() && artist.isEmpty() && titleKey == stationKey) return true
    if (stationKey.isNotEmpty() && plainKey("$artist $title") == stationKey) return true
    if (artist.isEmpty() && (titleKey in Ads || CartCode.matches(title))) return true
    return false
}

private fun taglineOf(parts: List<String>, stationKey: String): String =
    parts.firstOrNull { part -> part.any { it.isLetterOrDigit() } && plainKey(part) != stationKey && !CartCode.matches(part) }.orEmpty()

// Letters and digits only, in lower case, for comparing names.
private fun plainKey(text: String): String =
    text.lowercase().filter { it.isLetterOrDigit() || it == ' ' }.split(' ').filter(String::isNotEmpty).joinToString(" ")

private fun squash(text: String): String = text.trim().replace(Spaces, " ")

private fun isWebAddress(text: String): Boolean = text.startsWith("https://", ignoreCase = true) || text.startsWith("http://", ignoreCase = true)

private fun isImageAddress(text: String): Boolean {
    if (!isWebAddress(text)) return false
    val path = text.substringBefore('?').substringBefore('#').lowercase()
    return ImageEndings.any(path::endsWith)
}

private val Spaces = Regex("""\s+""")

// key="value" pairs, as iHeart puts them after the artist.
private val KeyValue = Regex("""([A-Za-z][A-Za-z0-9_]*)="([^"]*)"""")

// One word of capitals and digits with both in it: a playout system's cart
// number, sent where a title would be.
private val CartCode = Regex("""^(?=.*\d)(?=.*[A-Z])[A-Z0-9_]{6,}$""")

private val Ads = setOf("advertisement", "advert", "advertising", "commercial", "commercials", "ad break", "spot break", "adbreak")

private val ImageEndings = listOf(".jpg", ".jpeg", ".png", ".webp", ".gif")

private const val TITLE_MAX = 1_000
