package app.winters.octo.desktop.nav

import androidx.compose.runtime.Stable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateMapOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue
import app.winters.octo.livelists.DefaultLiveListSort
import app.winters.octo.query.LibraryQuery
import app.winters.octo.desktop.home.AlbumShelf

// Every page the main area can show.
sealed interface Page {
    data object Home : Page
    data object Search : Page
    data object Songs : Page
    data object Albums : Page
    data object Artists : Page
    data object Genres : Page
    data object Folders : Page
    data object Favourites : Page
    data object History : Page
    data object RecentlyAdded : Page
    data object LibraryHealth : Page
    // Import, on an Octo server: lists from other services, files and links.
    data object Imports : Page
    // The charts and new songs, on an Octo server that has them.
    data object Charts : Page
    // Family: the account's abilities, requests and devices, on an Octo server with it on.
    data object Family : Page
    // Live radio near you: stations from the radio catalog around a place.
    data object LiveRadio : Page
    data object Settings : Page
    data object Sound : Page
    data class Album(val id: String) : Page
    data class Artist(val id: String, val name: String = "") : Page
    data class Genre(val name: String) : Page
    // `trail` is the folders above it, from the top, when it was opened
    // from one of them; `focus` a song to show in it ("Show in folder").
    data class Folder(val id: String, val name: String, val trail: List<FolderStep> = emptyList(), val focus: String? = null) : Page
    data class Playlist(val id: String) : Page
    // Every album on one of Home's shelves.
    data class Shelf(val shelf: AlbumShelf) : Page
    // A live list: songs picked by rules, kept on this computer; opened
    // straight into its editor with `editing`.
    data class LiveList(val id: String, val editing: Boolean = false) : Page
    // A live list being made, from these rules (a page's filters, or none).
    data class NewLiveList(val query: LibraryQuery = LibraryQuery(sort = DefaultLiveListSort), val name: String = "") : Page
}

// One folder on the way down to another, for the breadcrumbs.
data class FolderStep(val id: String, val name: String)

// The sidebar's items. Settings sits at the bottom; playlists are listed
// under their own heading.
sealed interface SidebarItem {
    data class Top(val page: Page) : SidebarItem
    data class PlaylistItem(val id: String) : SidebarItem
    data class LiveListItem(val id: String) : SidebarItem
}

// The item a top-level page lights up in the sidebar, or null for a page
// that is not in it (an album, an artist), which keeps the item of the page
// it was opened from.
fun sidebarItemOf(page: Page): SidebarItem? = when (page) {
    Page.Home, Page.Search, Page.Songs, Page.Albums, Page.Artists, Page.Genres, Page.Folders,
    Page.Favourites, Page.History, Page.RecentlyAdded, Page.LibraryHealth, Page.Imports, Page.Charts, Page.Family, Page.LiveRadio, Page.Settings, Page.Sound,
    -> SidebarItem.Top(page)
    is Page.Playlist -> SidebarItem.PlaylistItem(page.id)
    is Page.Album, is Page.Artist, is Page.Genre, is Page.Folder -> null
    is Page.Shelf -> null
    is Page.LiveList -> SidebarItem.LiveListItem(page.id)
    is Page.NewLiveList -> null
}

// One visit to a page. The id is its own, so the same page visited twice
// keeps two scroll positions; `item` is what the sidebar shows lit.
data class Visit(val id: Long, val page: Page, val item: SidebarItem?)

private val NoFilter = LibraryQuery()

// Where a list was scrolled to: the first row showing and how far into it.
data class ScrollSpot(val index: Int = 0, val offset: Int = 0)

// Back and forward through the pages, as a browser does: going somewhere
// new drops what was ahead. Each visit remembers how far it was scrolled.
@Stable
class Navigator(start: Page = Page.Home, private val limit: Int = 100) {
    private var nextId = 1L
    private val visits = ArrayList<Visit>()
    private var at by mutableStateOf(0)
    // Scrolls by visit and by which list on the page, since a page can
    // have two (a list and a grid).
    private val scrolls = HashMap<Pair<Long, String>, ScrollSpot>()
    private val tabs = HashMap<Long, String>()

    // Each visit's filters on its list, so Back returns to the list as it
    // was filtered. Only while the app runs; nothing is saved.
    private val filters = mutableStateMapOf<Long, LibraryQuery>()

    // Bumped on every move, so the screen redraws.
    private var moves by mutableStateOf(0)

    init {
        visits += visit(start, null)
    }

    val current: Visit get() = moves.let { visits[at] }

    val canGoBack: Boolean get() = moves.let { at > 0 }

    val canGoForward: Boolean get() = moves.let { at < visits.lastIndex }

    // What the sidebar lights up now.
    val sidebarItem: SidebarItem? get() = current.item

    fun go(page: Page) {
        if (page == current.page) return
        // Anything ahead is dropped, with its scroll positions.
        while (visits.lastIndex > at) forget(visits.removeAt(visits.lastIndex))
        visits += visit(page, current.item)
        // A very long history forgets its oldest pages.
        while (visits.size > limit) forget(visits.removeAt(0))
        at = visits.lastIndex
        moves++
    }

    // Shows `page` in place of the one on screen, so Back skips what it
    // replaced: a live list once made, in place of its editor.
    fun replace(page: Page) {
        val old = visits[at]
        forget(old)
        visits[at] = visit(page, old.item)
        moves++
    }

    fun back(): Boolean {
        if (!canGoBack) return false
        at--
        moves++
        return true
    }

    fun forward(): Boolean {
        if (!canGoForward) return false
        at++
        moves++
        return true
    }

    // Forgets every page and scroll and starts again at `page`, for a
    // different account.
    fun startOver(page: Page = Page.Home) {
        visits.clear()
        scrolls.clear()
        tabs.clear()
        filters.clear()
        visits += visit(page, null)
        at = 0
        moves++
    }

    fun scrollOf(visit: Visit, list: String = ""): ScrollSpot = scrolls[visit.id to list] ?: ScrollSpot()

    fun keepScroll(visit: Visit, spot: ScrollSpot, list: String = "") {
        if (visits.any { it.id == visit.id }) scrolls[visit.id to list] = spot
    }

    // The tab a visit was left on, for pages with tabs.
    fun tabOf(visit: Visit): String? = tabs[visit.id]

    fun keepTab(visit: Visit, tab: String) {
        if (visits.any { it.id == visit.id }) tabs[visit.id] = tab
    }

    // The filters a visit's list is under; none at first.
    fun filterOf(visit: Visit): LibraryQuery = filters[visit.id] ?: NoFilter

    fun keepFilter(visit: Visit, query: LibraryQuery) {
        if (visits.none { it.id == visit.id }) return
        if (query == NoFilter) filters.remove(visit.id) else filters[visit.id] = query
    }

    private fun forget(visit: Visit) {
        scrolls.keys.removeAll { it.first == visit.id }
        tabs.remove(visit.id)
        filters.remove(visit.id)
    }

    // A page opened from another keeps that page's sidebar item lit, unless
    // it is in the sidebar itself.
    private fun visit(page: Page, from: SidebarItem?) = Visit(nextId++, page, sidebarItemOf(page) ?: from)

    // How many pages back and forward there are, for tests.
    val depth: Pair<Int, Int> get() = at to visits.lastIndex - at
}
