package app.winters.octo.ui.search

// How a search lists what the library has and what the server found online,
// the same on the phone and the desktop: each kind is one list, the
// library's best few first and the finds right after them, so the finds are
// never under a long run of library songs.

// How many library songs "All" shows before the songs found online, and how
// many of those it shows; "See all" lists every one of both. Three keeps the
// line about looking online above a phone's tab bar under a row of artists.
const val LIBRARY_SONGS_SHOWN = 3
const val ONLINE_SONGS_SHOWN = 4

// How many waiting rows stand in for the songs found online while the
// server looks: as many as "All" shows, so the finds take their places and
// nothing below moves.
const val WAITING_ROWS = ONLINE_SONGS_SHOWN

// Where looking online stands, for the line between the library's songs
// and the songs found online.
enum class OutsideLook {
    // Not looking: "Library songs only", or no server that finds music.
    Off,

    // Asked, no answer yet.
    Looking,

    // Found songs, listed under the library's.
    Found,

    // Asked and found no songs.
    NoneFound,

    // The server could not be asked.
    Failed,
}

// What the line says for each state; none when there is nothing to look
// for. Over the finds it stays, quietly, where it said it was looking.
const val SEARCHING_OUTSIDE = "Searching outside your library…"
const val FOUND_OUTSIDE = "Not in your library"
const val OUTSIDE_FAILED = "Couldn't search outside your library"

// `kind` names what was looked for in the plural: songs, albums, artists.
fun noneOutsideText(query: String, kind: String = "songs"): String = "No $kind outside your library for \"${query.trim()}\""

fun outsideLine(look: OutsideLook, query: String, kind: String = "songs"): String? = when (look) {
    OutsideLook.Looking -> SEARCHING_OUTSIDE
    OutsideLook.NoneFound -> noneOutsideText(query, kind)
    OutsideLook.Failed -> OUTSIDE_FAILED
    OutsideLook.Found -> FOUND_OUTSIDE
    OutsideLook.Off -> null
}

// The state from what is known: whether finds are wanted at all, whether
// the answer is still coming, whether asking failed, and how many songs
// came back.
fun outsideLook(wanted: Boolean, looking: Boolean, failed: Boolean, songs: Int): OutsideLook = when {
    !wanted -> OutsideLook.Off
    looking -> OutsideLook.Looking
    failed -> OutsideLook.Failed
    songs > 0 -> OutsideLook.Found
    else -> OutsideLook.NoneFound
}

// Whether "All" has more songs than it shows, of either kind.
fun moreSongsThanShown(library: Int, online: Int): Boolean =
    library > LIBRARY_SONGS_SHOWN || online > ONLINE_SONGS_SHOWN

// Whether a kind's list is shown at all in "All": it has library results,
// or the line between them has something to say. A search that found no
// songs anywhere still says so under Songs while the library has some
// other kind of result.
fun songsShown(library: Int, look: OutsideLook): Boolean = library > 0 || look != OutsideLook.Off
