package app.winters.octo.lists

import app.winters.octo.subsonic.Playlist

// The kinds of list an Octo server makes for its listener, in the order
// they are shown, each with its heading.
enum class OctoListGroup(val title: String) {
    ForYou("Made for you"),
    Stations("Radio"),
    Charts("Charts"),
    Years("Years"),
    Genres("Genres"),
    Artists("Artists"),
    Countries("Countries"),
    More("More from Octo"),
}

// The group of a list an Octo server made for `listener`, or null for any
// other list: the listener's own, someone else's, a smart playlist, and
// Liked Songs, which has a place of its own. A list with no owner counts as
// the listener's. The server says which kind a list is (`octoGroup`); an
// older one does not (`guess`), so its Made for you lists are known by
// `octoList`, and its other read-only lists by the shape of Octo's ids:
// stations by "or", decade mixes by their names, the rest as more from
// Octo. A server that marks its lists is never guessed at, since
// Navidrome's own ids can have the same shape. Only call it for a server
// that runs Octo.
fun octoListGroup(playlist: Playlist, listener: String, guess: Boolean = true): OctoListGroup? {
    val owner = playlist.owner.orEmpty()
    if (listener.isNotBlank() && owner.isNotBlank() && !owner.equals(listener, ignoreCase = true)) return null
    playlist.octoGroup?.let { return groupOf(it) }
    if (playlist.octoList == "liked") return null
    if (playlist.octoList != null) return OctoListGroup.ForYou
    if (!guess || !playlist.readonly || !isOctoListId(playlist.id)) return null
    return when {
        playlist.id.startsWith("or") -> OctoListGroup.Stations
        DECADE_MIX.matches(playlist.name) -> OctoListGroup.Years
        else -> OctoListGroup.More
    }
}

// The lists an Octo server made for `listener`, by group in the order the
// groups are shown, groups with none left out. Years show the decades,
// then the single years, each newest first; the others run by name.
fun octoListGroups(playlists: List<Playlist>, listener: String): List<Pair<OctoListGroup, List<Playlist>>> {
    val guess = playlists.none { it.octoGroup != null }
    val grouped = playlists.mapNotNull { list -> octoListGroup(list, listener, guess)?.let { it to list } }.groupBy({ it.first }, { it.second })
    return OctoListGroup.entries.mapNotNull { group ->
        val lists = grouped[group] ?: return@mapNotNull null
        group to when (group) {
            OctoListGroup.Years -> lists.sortedWith(
                compareBy<Playlist> { if (isDecade(it.name)) 0 else 1 }.thenByDescending { yearOf(it.name) }.thenBy { it.name.lowercase() },
            )
            // Made for you and charts keep the order the server gives.
            OctoListGroup.ForYou, OctoListGroup.Charts -> lists
            else -> lists.sortedBy { it.name.lowercase() }
        }
    }
}

private fun groupOf(word: String): OctoListGroup? = when (word) {
    "forYou" -> OctoListGroup.ForYou
    "station" -> OctoListGroup.Stations
    "chart" -> OctoListGroup.Charts
    "decade", "year" -> OctoListGroup.Years
    "genre" -> OctoListGroup.Genres
    "artist" -> OctoListGroup.Artists
    "country" -> OctoListGroup.Countries
    "liked" -> null
    else -> OctoListGroup.More
}

// Octo's own list ids: "og" or "or" and 20 base62 digits.
private fun isOctoListId(id: String): Boolean =
    id.length == 22 && (id.startsWith("og") || id.startsWith("or")) && id.all { it.isLetterOrDigit() && it.code < 128 }

private val DECADE_MIX = Regex("""^\d{4}s Mix$""")

// The year a list's name starts with ("1990s Mix", "1994 Mix"), or -1.
private fun yearOf(name: String): Int = name.takeWhile { it.isDigit() }.takeIf { it.length == 4 }?.toInt() ?: -1

private fun isDecade(name: String): Boolean = yearOf(name) >= 0 && name.getOrNull(4) == 's'

