package app.winters.octo.home

// One of Home's shelves, by the id it is stored under, with its name as
// Home shows it. The entries are in the default order.
enum class HomeSection(val id: String, val title: String) {
    Pinned("pinned", "Pinned"),
    RecentlyPlayed("recentlyPlayed", "Recently played"),
    MadeForYou("madeForYou", "Made for you"),
    Stations("stations", "Stations"),
    RecentlyAdded("recentlyAdded", "Recently added"),
    MostPlayed("mostPlayed", "Most played"),
    FavoriteAlbums("favoriteAlbums", "Favorite albums"),
    Charts("charts", "Charts"),
    Artists("artists", "Artists"),
    SomethingDifferent("somethingDifferent", "Something different"),
    NotPlayedLately("notPlayedLately", "Not played in 6 months"),
    NeverFinished("neverFinished", "Albums you never finished"),
    NeverPlayed("neverPlayed", "Unplayed albums"),
    ;

    companion object {
        fun ofId(id: String): HomeSection? = entries.firstOrNull { it.id == id }
    }
}

// A shelf in its place on Home, and whether it shows.
data class HomeSectionEntry(val section: HomeSection, val shown: Boolean = true)

// The settings key Home's order and hidden shelves are kept under.
const val HOME_SECTIONS_KEY = "home_sections"

// Every shelf in the default order, all shown.
val DefaultHomeSections: List<HomeSectionEntry> = HomeSection.entries.map { HomeSectionEntry(it) }

// The words of the page that orders and hides the shelves.
const val HOME_SECTIONS_TITLE = "Home sections"
const val HOME_SECTIONS_NOTE = "Drag a section by its handle to move it. A hidden section keeps its place here, ready to show again."
const val RESET_HOME_SECTIONS = "Reset to default order"
const val RESET_HOME_SECTIONS_ASK = "Reset Home sections?"
const val RESET_HOME_SECTIONS_DETAIL = "Every section goes back to its usual place and shows again."
const val EDIT_HOME = "Edit Home"

// Home's shelves from the stored string: ids separated by commas, in order,
// a hidden one led by "-". Unknown ids are passed over and an id written
// twice counts once, where it first stands. A shelf the string leaves out
// goes in shown, just after the shelf before it in the default order (first
// of all when none of those is there). Nothing stored is the default.
fun homeSectionOrder(stored: String?): List<HomeSectionEntry> {
    val entries = mutableListOf<HomeSectionEntry>()
    for (piece in stored.orEmpty().split(',')) {
        var id = piece.trim()
        if (id.isEmpty()) continue
        val hidden = id.startsWith("-")
        if (hidden) id = id.drop(1).trim()
        val section = HomeSection.ofId(id) ?: continue
        if (entries.any { it.section == section }) continue
        entries += HomeSectionEntry(section, shown = !hidden)
    }
    val all = HomeSection.entries
    all.forEachIndexed { index, section ->
        if (entries.any { it.section == section }) return@forEachIndexed
        val before = all.subList(0, index).asReversed().firstNotNullOfOrNull { earlier ->
            entries.indexOfFirst { it.section == earlier }.takeIf { it >= 0 }
        }
        entries.add(before?.plus(1) ?: 0, HomeSectionEntry(section))
    }
    return entries
}

// The string Home's shelves are stored as: every id in order, a hidden one
// led by "-".
fun encodeHomeSections(entries: List<HomeSectionEntry>): String =
    entries.joinToString(",") { (if (it.shown) "" else "-") + it.section.id }

// The shelves with the ones at `offsets` moved to stand before
// `destination`, which counts places in the list before the move.
fun moveHomeSections(entries: List<HomeSectionEntry>, offsets: Collection<Int>, destination: Int): List<HomeSectionEntry> {
    val valid = offsets.filter { it in entries.indices }.toSortedSet()
    if (valid.isEmpty()) return entries
    val moving = valid.map { entries[it] }
    val rest = mutableListOf<HomeSectionEntry>()
    var place = 0
    entries.forEachIndexed { index, entry ->
        if (index in valid) return@forEachIndexed
        if (index < destination) place++
        rest += entry
    }
    rest.addAll(place.coerceIn(0, rest.size), moving)
    return rest
}

// The shelves with one moved to stand at `index` of the new order.
fun moveHomeSection(entries: List<HomeSectionEntry>, section: HomeSection, index: Int): List<HomeSectionEntry> {
    val from = entries.indexOfFirst { it.section == section }
    if (from < 0) return entries
    val next = entries.toMutableList()
    val entry = next.removeAt(from)
    next.add(index.coerceIn(0, next.size), entry)
    return next
}

// The shelves with one moved, by a drag in a list that names only some of
// them (`listed`, an app's own shelves): from place `from` of that list to
// place `to`, just before or after the shelf it lands on there. The ones
// not listed keep their places among the rest.
fun moveListedHomeSection(entries: List<HomeSectionEntry>, listed: Collection<HomeSection>, from: Int, to: Int): List<HomeSectionEntry> {
    val shown = entries.filter { it.section in listed }
    val moving = shown.getOrNull(from)?.section ?: return entries
    val target = shown.getOrNull(to.coerceIn(0, shown.lastIndex))?.section ?: return entries
    if (moving == target) return entries
    val rest = entries.filter { it.section != moving }
    val at = rest.indexOfFirst { it.section == target }
    return moveHomeSection(entries, moving, if (to > from) at + 1 else at)
}

// The shelves with one shown or hidden, in its place.
fun toggleHomeSection(entries: List<HomeSectionEntry>, section: HomeSection, shown: Boolean): List<HomeSectionEntry> =
    entries.map { if (it.section == section) HomeSectionEntry(section, shown) else it }

// Every shelf back in the default order, and shown.
fun resetHomeSections(): List<HomeSectionEntry> = DefaultHomeSections

// Whether a shelf is drawn on Home.
fun List<HomeSectionEntry>.shows(section: HomeSection): Boolean = firstOrNull { it.section == section }?.shown ?: true

// The line under "Home sections" in Settings: how many shelves are hidden,
// and whether the order was changed.
fun homeSectionsSummary(entries: List<HomeSectionEntry>): String {
    val hidden = entries.count { !it.shown }
    val moved = entries.map { it.section } != HomeSection.entries
    return when {
        hidden == 0 && !moved -> "Every section, in the usual order"
        hidden == 0 -> "Every section, in your order"
        moved -> "$hidden hidden, in your order"
        else -> "$hidden hidden"
    }
}
