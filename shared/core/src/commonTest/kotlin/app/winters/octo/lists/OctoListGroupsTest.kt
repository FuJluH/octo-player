package app.winters.octo.lists

import app.winters.octo.home.HomeSection
import app.winters.octo.home.MixShelves
import app.winters.octo.home.mixGroup
import app.winters.octo.subsonic.Playlist
import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertNull

class OctoListGroupsTest {
    private val me = "ana"

    private fun octo(id: String, name: String, group: String? = null, list: String? = null, owner: String = me) =
        Playlist(id, name, owner = owner, readonly = true, octoGroup = group, octoList = list)

    // 22 characters, as Octo's ids are.
    private fun id(prefix: String, n: Int) = prefix + n.toString().padStart(20, '0')

    @Test
    fun theServerSaysWhichKindEachListIs() {
        val lists = listOf(
            octo(id("og", 1), "Pop Mix", "genre"),
            octo(id("og", 2), "1990s Mix", "decade"),
            octo(id("og", 3), "1994 Mix", "year"),
            octo(id("og", 4), "Spain Mix", "country"),
            octo(id("og", 5), "Drake Mix", "artist"),
            octo(id("og", 6), "Top Pop", "chart"),
            octo(id("og", 7), "New Releases", "forYou", "newReleases"),
            octo(id("or", 8), "Your Radio", "station"),
            octo(id("og", 9), "Something new", "lyrics"),
        )
        assertEquals(
            listOf(
                OctoListGroup.Genres, OctoListGroup.Years, OctoListGroup.Years, OctoListGroup.Countries, OctoListGroup.Artists,
                OctoListGroup.Charts, OctoListGroup.ForYou, OctoListGroup.Stations, OctoListGroup.More,
            ),
            lists.map { octoListGroup(it, me) },
        )
    }

    @Test
    fun likedSongsHasAPlaceOfItsOwn() {
        assertNull(octoListGroup(octo(id("og", 1), "Liked Songs", "liked", "liked"), me))
        assertNull(octoListGroup(octo(id("og", 1), "Liked Songs", list = "liked"), me))
    }

    @Test
    fun anOlderServerIsReadFromWhatItSends() {
        assertEquals(OctoListGroup.ForYou, octoListGroup(octo(id("og", 1), "Deep Cuts", list = "deepCuts"), me))
        assertEquals(OctoListGroup.Stations, octoListGroup(octo(id("or", 2), "Your Radio"), me))
        assertEquals(OctoListGroup.Years, octoListGroup(octo(id("og", 3), "2010s Mix"), me))
        assertEquals(OctoListGroup.More, octoListGroup(octo(id("og", 4), "Spain Mix"), me))
    }

    @Test
    fun otherPeoplesListsAndSmartPlaylistsAreNotOctos() {
        // Navidrome marks both read-only too.
        assertNull(octoListGroup(octo(id("og", 1), "Pop Mix", "genre", owner = "ben"), me))
        assertNull(octoListGroup(Playlist("5f3c-smart", "Top rated", owner = me, readonly = true), me))
        assertNull(octoListGroup(Playlist("5f3c-mine", "Road trip", owner = me), me))
        assertNull(octoListGroup(octo("og-short", "Pop Mix"), me))
    }

    @Test
    fun aListWithNoOwnerCountsAsTheListeners() {
        assertEquals(OctoListGroup.Genres, octoListGroup(octo(id("og", 1), "Pop Mix", "genre", owner = ""), me))
    }

    @Test
    fun theListenersOwnPlaylistIsNeverTakenForOctosByItsId() {
        // Navidrome's own ids can have the shape of Octo's.
        val mine = Playlist(id("og", 7), "Road trip", owner = me)
        assertNull(octoListGroup(mine, me))
        // A server that marks its lists is never guessed at.
        val unmarked = octo(id("og", 8), "Rock Mix")
        val marked = octo(id("og", 9), "Pop Mix", "genre")
        assertEquals(listOf(OctoListGroup.Genres), octoListGroups(listOf(marked, unmarked, mine), me).map { it.first })
        assertEquals(listOf("Pop Mix"), octoListGroups(listOf(marked, unmarked, mine), me).single().second.map { it.name })
    }

    @Test
    fun groupsComeInTheirOrderAndYearsRunNewestFirst() {
        val lists = listOf(
            octo(id("og", 1), "Rock Mix", "genre"),
            octo(id("og", 2), "1994 Mix", "year"),
            octo(id("og", 3), "2010s Mix", "decade"),
            octo(id("og", 4), "Funk Mix", "genre"),
            octo(id("og", 5), "2019 Mix", "year"),
            octo(id("og", 6), "1990s Mix", "decade"),
        )
        val groups = octoListGroups(lists, me)
        assertEquals(listOf(OctoListGroup.Years, OctoListGroup.Genres), groups.map { it.first })
        assertEquals(listOf("2010s Mix", "1990s Mix", "2019 Mix", "1994 Mix"), groups[0].second.map { it.name })
        assertEquals(listOf("Funk Mix", "Rock Mix"), groups[1].second.map { it.name })
    }

    @Test
    fun eachShelfOfMixesShowsItsGroup() {
        assertEquals(
            listOf(HomeSection.YearMixes, HomeSection.GenreMixes, HomeSection.ArtistMixes, HomeSection.CountryMixes),
            MixShelves,
        )
        assertEquals(OctoListGroup.Countries, HomeSection.CountryMixes.mixGroup)
        assertNull(HomeSection.Stations.mixGroup)
    }
}
