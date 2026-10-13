package app.winters.octo.liveradio

// A stream address as two stations are matched by, in both apps: http and
// https count as one, the host in any case, the path as it is, and no slash
// at the end. Other schemes keep theirs.
fun liveStreamKey(url: String): String {
    val text = url.trim()
    val scheme = text.substringBefore("://", "").lowercase()
    val rest = if (scheme.isEmpty()) text else text.substringAfter("://")
    val hostEnd = rest.indexOfFirst { it == '/' || it == '?' || it == '#' }.let { if (it < 0) rest.length else it }
    val host = rest.substring(0, hostEnd).lowercase()
    val path = rest.substring(hostEnd).trimEnd('/')
    val kind = if (scheme == "http" || scheme == "https" || scheme.isEmpty()) "" else "$scheme://"
    return kind + host + path
}

// What a "where" field asks for: a postal code, a city, its state, or a few
// of them together.
data class WhereParts(val code: String? = null, val name: String? = null, val state: String? = null)

// Reads a "where" field, for both apps. The words with a digit in them are
// the postal code ("55401", "SW1A 1AA"); the rest is the city, with its
// state after the first comma ("Austin, Texas"). So "Austin, TX 78701" is
// the code 78701 in Austin, TX, and "10001, NY" the code 10001 in NY. Null
// when there is neither a code nor a city.
fun parseWhere(text: String): WhereParts? {
    val words = text.trim().split(Regex("\\s+")).filter { it.isNotEmpty() }
    val code = words.filter { word -> word.any { it.isDigit() } }
        .map { it.trim(',', ';') }
        .filter { it.isNotEmpty() }
        .joinToString(" ")
        .uppercase()
        .ifEmpty { null }
    // A code's own commas stay, so "10001, NY" leaves ", NY": a state.
    val rest = words.joinToString(" ") { word -> if (word.any { it.isDigit() }) word.filter { it == ',' } else word }
    val name = rest.substringBefore(',').trim().ifEmpty { null }
    val state = rest.substringAfter(',', "").substringBefore(',').trim().ifEmpty { null }
    if (code == null && name == null) return null
    return WhereParts(code, name, state)
}
