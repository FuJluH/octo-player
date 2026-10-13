package app.winters.octo.home

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class HomeSectionsTest {
    private val defaultIds = "pinned,recentlyPlayed,madeForYou,stations,recentlyAdded,mostPlayed,favoriteAlbums,charts,artists," +
        "somethingDifferent,notPlayedLately,neverFinished,neverPlayed"

    private fun ids(entries: List<HomeSectionEntry>) = entries.map { (if (it.shown) "" else "-") + it.section.id }

    @Test
    fun theDefaultOrder() {
        assertEquals(defaultIds, encodeHomeSections(DefaultHomeSections))
        assertTrue(DefaultHomeSections.all { it.shown })
        assertEquals("home_sections", HOME_SECTIONS_KEY)
    }

    @Test
    fun nothingStoredIsTheDefault() {
        assertEquals(DefaultHomeSections, homeSectionOrder(null))
        assertEquals(DefaultHomeSections, homeSectionOrder(""))
        assertEquals(DefaultHomeSections, homeSectionOrder(" , ,"))
    }

    @Test
    fun aStoredOrderReadsBackTheSame() {
        val stored = "charts,-pinned,neverPlayed,recentlyPlayed,madeForYou,stations,recentlyAdded,mostPlayed,favoriteAlbums,artists," +
            "-somethingDifferent,notPlayedLately,neverFinished"
        val entries = homeSectionOrder(stored)
        assertEquals(stored, encodeHomeSections(entries))
        assertEquals(HomeSectionEntry(HomeSection.Charts), entries.first())
        assertEquals(HomeSectionEntry(HomeSection.Pinned, shown = false), entries[1])
    }

    @Test
    fun unknownIdsAreLeftOutAndRepeatsCountOnce() {
        val entries = homeSectionOrder("radio,-charts,pinned,charts, -nope ,recentlyPlayed")
        val stored = setOf(HomeSection.Charts, HomeSection.Pinned, HomeSection.RecentlyPlayed)
        assertEquals(listOf("-charts", "pinned", "recentlyPlayed"), ids(entries.filter { it.section in stored }))
        assertEquals(HomeSection.entries.size, entries.size)
    }

    @Test
    fun spacesAroundIdsDoNotMatter() {
        val entries = homeSectionOrder(" charts , - pinned ")
        assertEquals(listOf("charts", "-pinned"), ids(entries.filter { it.section == HomeSection.Charts || it.section == HomeSection.Pinned }))
    }

    @Test
    fun aMissingSectionGoesInAfterTheOneBeforeItByDefault() {
        // "stations" is missing; "madeForYou" comes before it by default.
        val entries = homeSectionOrder(
            "madeForYou,pinned,recentlyPlayed,recentlyAdded,mostPlayed,favoriteAlbums,charts,artists," +
                "somethingDifferent,notPlayedLately,neverFinished,neverPlayed",
        )
        assertEquals(listOf("madeForYou", "stations", "pinned", "recentlyPlayed"), ids(entries).take(4))
        assertTrue(entries.first { it.section == HomeSection.Stations }.shown)
    }

    @Test
    fun missingSectionsInARowKeepTheirDefaultOrder() {
        val entries = homeSectionOrder("-recentlyPlayed,neverPlayed")
        assertEquals(
            listOf(
                "pinned", "-recentlyPlayed", "madeForYou", "stations", "recentlyAdded", "mostPlayed", "favoriteAlbums",
                "charts", "artists", "somethingDifferent", "notPlayedLately", "neverFinished", "neverPlayed",
            ),
            ids(entries),
        )
    }

    @Test
    fun aMissingFirstSectionGoesFirst() {
        // "pinned" has nothing before it by default; "artists" and the rest follow "charts".
        val entries = homeSectionOrder("charts,recentlyPlayed")
        assertEquals(
            listOf(
                "pinned", "charts", "artists", "somethingDifferent", "notPlayedLately", "neverFinished", "neverPlayed",
                "recentlyPlayed", "madeForYou", "stations", "recentlyAdded", "mostPlayed", "favoriteAlbums",
            ),
            ids(entries),
        )
    }

    @Test
    fun aMissingSectionFollowsTheNearestEarlierOneThere() {
        // Neither "favoriteAlbums" nor "mostPlayed" is stored, so "charts" goes after "recentlyAdded".
        val entries = homeSectionOrder("recentlyAdded,pinned,artists")
        assertEquals(listOf("recentlyAdded", "mostPlayed", "favoriteAlbums", "charts", "pinned", "recentlyPlayed"), ids(entries).take(6))
        assertEquals(HomeSection.entries.size, entries.size)
    }

    @Test
    fun hiddenIsWrittenWithALeadingDash() {
        val entries = toggleHomeSection(DefaultHomeSections, HomeSection.Charts, shown = false)
        assertEquals(defaultIds.replace("charts", "-charts"), encodeHomeSections(entries))
        assertEquals(DefaultHomeSections, toggleHomeSection(entries, HomeSection.Charts, shown = true))
        assertFalse(entries.shows(HomeSection.Charts))
        assertTrue(entries.shows(HomeSection.Stations))
    }

    @Test
    fun movingAsAListDragReportsIt() {
        // Drag "charts" (7) to the top.
        var entries = moveHomeSections(DefaultHomeSections, listOf(7), 0)
        assertEquals(listOf("charts", "pinned", "recentlyPlayed"), ids(entries).take(3))
        // Drag "pinned" (now 1) down below "stations" (now 4): it lands before offset 5.
        entries = moveHomeSections(entries, listOf(1), 5)
        assertEquals(listOf("charts", "recentlyPlayed", "madeForYou", "stations", "pinned"), ids(entries).take(5))
        // To the very end.
        entries = moveHomeSections(entries, listOf(0), entries.size)
        assertEquals("charts", ids(entries).last())
        assertEquals(HomeSection.entries.size, entries.size)
    }

    @Test
    fun movingToAPlaceInTheNewOrder() {
        val entries = moveHomeSection(DefaultHomeSections, HomeSection.Pinned, 3)
        assertEquals(listOf("recentlyPlayed", "madeForYou", "stations", "pinned", "recentlyAdded"), ids(entries).take(5))
        assertEquals(DefaultHomeSections, moveHomeSection(entries, HomeSection.Pinned, 0))
    }

    @Test
    fun movingInAListOfSomeShelvesKeepsTheOthersInPlace() {
        val listed = DefaultHomeSections.map { it.section } - setOf(HomeSection.Pinned, HomeSection.Artists, HomeSection.SomethingDifferent)
        // Down: "recentlyPlayed" (0 of the list) onto "stations" (2) goes just after it.
        val down = moveListedHomeSection(DefaultHomeSections, listed, 0, 2)
        assertEquals(listOf("pinned", "madeForYou", "stations", "recentlyPlayed", "recentlyAdded"), ids(down).take(5))
        // Up: "notPlayedLately" (7 of the list) onto "charts" (6) goes just before it, "artists" staying after "charts".
        val up = moveListedHomeSection(DefaultHomeSections, listed, 7, 6)
        assertEquals(listOf("favoriteAlbums", "notPlayedLately", "charts", "artists", "somethingDifferent", "neverFinished"), ids(up).subList(6, 12))
        assertEquals(DefaultHomeSections, moveListedHomeSection(DefaultHomeSections, listed, 3, 3))
        assertEquals(DefaultHomeSections, moveListedHomeSection(DefaultHomeSections, listed, 40, 0))
    }

    @Test
    fun movingKeepsWhetherItShows() {
        val hidden = toggleHomeSection(DefaultHomeSections, HomeSection.Artists, shown = false)
        val moved = moveHomeSection(hidden, HomeSection.Artists, 0)
        assertEquals(HomeSectionEntry(HomeSection.Artists, shown = false), moved.first())
        assertEquals(HomeSectionEntry(HomeSection.Artists, shown = false), moveHomeSection(moved, HomeSection.Artists, 99).last())
    }

    @Test
    fun movingNothingChangesNothing() {
        assertEquals(DefaultHomeSections, moveHomeSections(DefaultHomeSections, emptyList(), 3))
        assertEquals(DefaultHomeSections, moveHomeSections(DefaultHomeSections, listOf(40), 0))
        assertEquals(DefaultHomeSections, moveHomeSections(DefaultHomeSections, listOf(2), 2))
        assertEquals(DefaultHomeSections, moveHomeSections(DefaultHomeSections, listOf(2), 3))
    }

    @Test
    fun resetIsTheDefaultOrderAllShown() {
        assertEquals(DefaultHomeSections, resetHomeSections())
    }

    @Test
    fun eachSectionHasHomesName() {
        assertEquals("Not played in 6 months", HomeSection.NotPlayedLately.title)
        assertEquals("Albums you never finished", HomeSection.NeverFinished.title)
        assertEquals("Unplayed albums", HomeSection.NeverPlayed.title)
        assertEquals("Something different", HomeSection.SomethingDifferent.title)
        assertEquals(HomeSection.entries.size, HomeSection.entries.map { it.title }.toSet().size)
    }

    @Test
    fun theSummarySaysWhatChanged() {
        assertEquals("Every section, in the usual order", homeSectionsSummary(DefaultHomeSections))
        val hidden = toggleHomeSection(DefaultHomeSections, HomeSection.Charts, shown = false)
        assertEquals("1 hidden", homeSectionsSummary(hidden))
        val moved = moveHomeSection(DefaultHomeSections, HomeSection.Charts, 0)
        assertEquals("Every section, in your order", homeSectionsSummary(moved))
        val both = toggleHomeSection(toggleHomeSection(moved, HomeSection.Pinned, shown = false), HomeSection.Artists, shown = false)
        assertEquals("2 hidden, in your order", homeSectionsSummary(both))
    }
}
