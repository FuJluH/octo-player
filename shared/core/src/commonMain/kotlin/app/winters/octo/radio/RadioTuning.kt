package app.winters.octo.radio

import app.winters.octo.discovery.LIBRARY_ONLY_SETTING

// How a listener tunes Octo's radio: how much of it is music from outside
// the library, how far it strays from the seeds, how soon an artist or an
// album comes back, and whether favorites come around more often. Each app
// keeps these in its own settings. The defaults play as radio always has,
// apart from where the outside songs land.
data class RadioTuning(
    val discovery: RadioDiscovery = RadioDiscovery.Balanced,
    val adventure: RadioAdventure = RadioAdventure.Balanced,
    val variety: RadioVariety = RadioVariety.Normal,
    val favorites: Boolean = false,
) {
    // How many songs to ask the server for: more when most of the radio is
    // to come from outside the library, so the share can be reached.
    val suggestions: Int get() = if (discovery.share > 0.5) 100 else 50
}

// The share of a radio kept for songs the library does not have, from the
// server's suggestions. Balanced is the share Octo's Your Radio keeps.
enum class RadioDiscovery(val share: Double, val label: String, val detail: String) {
    LibraryOnly(0.0, "Only my library", "Never a song from outside your library"),
    ALittle(0.15, "A little", "About 1 song in 7 from outside your library"),
    Balanced(0.35, "Balanced", "About 1 song in 3 from outside your library"),
    Lots(0.6, "Lots", "About 3 songs in 5 from outside your library"),
    MostlyNew(0.85, "Mostly new", "About 5 songs in 6 from outside your library"),
}

// How far down the best matches a pick may land, as a share of their total
// weight, and how many of the library's matches stay in the running.
enum class RadioAdventure(val reach: Double, val keep: Double, val label: String, val detail: String) {
    Focused(0.2, 0.5, "Focused", "Only the closest matches"),
    Balanced(0.5, 1.0, "Balanced", "Close matches, with some surprises"),
    Wander(1.0, 2.0, "Wander", "Deep cuts and further afield"),
}

// How far apart an album and an artist play, against the usual spacing,
// which grows with the library. Another version of the same song always
// waits the usual spacing.
enum class RadioVariety(val scale: Double, val label: String, val detail: String) {
    Tight(0.5, "Tight", "Artists and albums come back sooner"),
    Normal(1.0, "Normal", "Spaced to suit your library's size"),
    Wide(1.6, "Wide", "Artists and albums come back much later"),
}

// How the Discovery row shows: whether it can be chosen, the reading on its
// right, and the line under its title. With Library songs only on, no song
// from outside the library plays anywhere, radio included, so Discovery has
// no say; the line names that setting and `where` it is (the page or part of
// Settings that holds it in this app).
data class DiscoveryRowLook(val choosable: Boolean, val value: String, val helper: String)

fun discoveryRowLook(discovery: RadioDiscovery, libraryOnly: Boolean, where: String): DiscoveryRowLook =
    if (libraryOnly) {
        DiscoveryRowLook(
            choosable = false,
            value = RadioDiscovery.LibraryOnly.label,
            helper = "$LIBRARY_ONLY_SETTING is on in $where, so radio keeps to your library. Turn it off there to choose.",
        )
    } else {
        DiscoveryRowLook(choosable = true, value = discovery.label, helper = discovery.detail)
    }

// Radio mixed from your music, as Settings names it.
const val SONG_RADIO = "Song radio"

// What the Song radio part of Settings is, in a line.
const val SONG_RADIO_ABOUT = "Radio started from a song, album or artist, and Autoplay when the queue ends, mixed from your music."

// What the Live radio part of Settings is, in a line.
const val LIVE_RADIO_ABOUT = "Stations on the air: the ones your server keeps, and ones near you."
