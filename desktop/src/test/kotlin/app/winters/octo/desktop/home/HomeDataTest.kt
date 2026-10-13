package app.winters.octo.desktop.home

import app.winters.octo.desktop.FakeServer
import app.winters.octo.desktop.server.Connection
import app.winters.octo.desktop.settings.key
import app.winters.octo.home.DefaultHomeSections
import app.winters.octo.home.HomeSection
import app.winters.octo.home.HomeShelfStore
import app.winters.octo.home.toggleHomeSection
import app.winters.octo.subsonic.Album
import app.winters.octo.subsonic.Playlist
import app.winters.octo.subsonic.RadioStation
import app.winters.octo.subsonic.Song
import app.winters.octo.subsonic.SubsonicException
import app.winters.octo.subsonic.TopSong
import app.winters.octo.subsonic.TopSongs
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.runBlocking
import org.junit.After
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertSame
import org.junit.Assert.assertTrue
import org.junit.Assert.fail
import org.junit.Rule
import org.junit.Test
import org.junit.rules.TemporaryFolder
import app.winters.octo.lists.OctoListGroup

class HomeDataTest {
    private val server = FakeServer()

    @get:Rule val temp = TemporaryFolder()

    @After fun stop() = server.close()

    private fun albums(vararg ids: String) = """"albumList2":{"album":[${ids.joinToString(",") { """{"id":"$it","name":"$it"}""" }}]}"""

    @Test
    fun eachShelfComesFromItsOwnList() = runBlocking {
        server.answer("getAlbumList2", albums("a1", "a2"))
        val home = loadHome(server.connection())
        assertEquals(listOf("a1", "a2"), home.recentlyAdded.map { it.id })
        val types = server.calls.map { it.url.queryParameter("type") }.filterNotNull().toSet()
        assertEquals("no random shelf: Home shows only what the library says", setOf("newest", "recent", "frequent"), types)
        assertTrue("favorites come from the starred list", "getStarred2" in server.endpoints())
    }

    @Test
    fun onlyOctoFillsTheRadioShelf() = runBlocking {
        server.answer("getAlbumList2", albums("a1"))
        server.answer("getInternetRadioStations", """"internetRadioStations":{"internetRadioStation":[{"id":"st1","name":"Discover Weekly","coverArt":"st1"}]}""")
        val plain = loadHome(server.connection())
        assertEquals("a server without Octo's stations has none", emptyList<RadioStation>(), plain.stations)
        assertEquals("and a station with no stream is not live radio", emptyList<RadioStation>(), plain.live)
        val octo = loadHome(server.connection(listOf("octoAcquisitions:1")))
        assertEquals(listOf("Discover Weekly"), octo.stations!!.map { it.name })
    }

    // An internet radio station added to the server is a stream: it goes on
    // the Live radio shelf, from any server, and Octo's own stay on Radio.
    @Test
    fun anAddedRadioStationGoesOnTheLiveRadioShelf() = runBlocking {
        server.answer("getAlbumList2", albums("a1"))
        val stations = """"internetRadioStations":{"internetRadioStation":[{"id":"st1","name":"Discover Weekly","coverArt":"st1"},{"id":"r1","name":"City Radio","streamUrl":"https://radio.example.com/live.mp3","coverArt":"ra-r1"},{"id":"r2","name":"Town FM","streamUrl":"https://town.example.com/fm"}]}"""
        server.answer("getInternetRadioStations", stations)
        val octo = loadHome(server.connection(listOf("octoAcquisitions:1")))
        assertEquals(listOf("Discover Weekly"), octo.stations!!.map { it.name })
        assertEquals(listOf("City Radio", "Town FM"), octo.live!!.map { it.name })
        val plain = loadHome(server.connection())
        assertEquals(listOf("City Radio", "Town FM"), plain.live!!.map { it.name })
        assertEquals("the stations are read once for both shelves", 2, server.endpoints().count { it == "getInternetRadioStations" })
    }

    @Test
    fun withBothRadioShelvesHiddenTheServerIsNotAsked() = runBlocking {
        server.answer("getAlbumList2", albums("a1"))
        val home = loadHome(server.connection(listOf("octoAcquisitions:1")), stations = false, live = false)
        assertFalse("getInternetRadioStations" in server.endpoints())
        assertNull(home.stations)
        assertNull(home.live)
    }

    // A station Octo has since made anew is taken off the shelf at once,
    // and the shelves are read again.
    @Test
    fun aStationTheServerNoLongerHasLeavesTheShelf() {
        server.answer("getAlbumList2", albums("a1"))
        server.answer("getInternetRadioStations", """"internetRadioStations":{"internetRadioStation":[{"id":"st1","name":"Discover Weekly","coverArt":"st1"},{"id":"st2","name":"Chill","coverArt":"st2"}]}""")
        val store = HomeStore(server.connection(listOf("octoAcquisitions:1")), CoroutineScope(Dispatchers.Unconfined))
        store.refresh()
        waitFor { store.shelves.stations.size == 2 }
        server.answer("getInternetRadioStations", """"internetRadioStations":{"internetRadioStation":[{"id":"st2","name":"Chill","coverArt":"st2"},{"id":"st3","name":"Morning","coverArt":"st3"}]}""")
        store.stationGone("st1")
        assertFalse(store.shelves.stations.any { it.id == "st1" })
        waitFor { store.shelves.stations.map { it.id } == listOf("st2", "st3") }
    }

    private fun waitFor(what: () -> Boolean) {
        val until = System.currentTimeMillis() + 5_000
        while (!what() && System.currentTimeMillis() < until) Thread.sleep(20)
        assertTrue("waited too long", what())
    }

    @Test
    fun oneBrokenShelfDoesNotBreakThePage() = runBlocking {
        server.answer("getAlbumList2", albums("a1"))
        server.fail("getInternetRadioStations", 0, "busy")
        val home = loadHome(server.connection(listOf("octoLyrics:1")))
        assertNull("stations that did not come are not an empty answer", home.stations)
        assertFalse(home.isEmpty)
    }

    // Home's server shelves, kept per account

    private val octo = listOf("octoAcquisitions:1")
    private val kept = KeptShelves(
        stations = listOf(RadioStation("st1", "Morning", coverArt = "st1"), RadioStation("st2", "Chill", coverArt = "st2")),
        madeForYou = listOf(Playlist("og-new", "New Releases", octoList = "newReleases", songCount = 40)),
        chart = TopSongs(source = "apple", chart = "overall", entry = listOf(TopSong(1, song = Song("s1", "First")))),
    )

    private fun shelfStore() = HomeShelfStore(temp.root, KeptShelves.serializer())

    private fun stationsAnswer(vararg stations: Pair<String, String>) {
        server.answer(
            "getInternetRadioStations",
            """"internetRadioStations":{"internetRadioStation":[${stations.joinToString(",") { (id, name) -> """{"id":"$id","name":"$name","coverArt":"$id"}""" }}]}""",
        )
    }

    @Test
    fun theShelvesTheServerGaveLastTimeShowAtOnce() {
        val connection = server.connection(octo)
        shelfStore().write(connection.server.key, kept)
        val store = HomeStore(connection, CoroutineScope(Dispatchers.Unconfined), kept = shelfStore())
        assertEquals("before anything is asked", kept, store.shelves)
    }

    @Test
    fun anotherAccountStartsWithItsOwnShelves() {
        val first = server.connection(octo)
        shelfStore().write(first.server.key, kept)
        val other = Connection(first.client, first.server.copy(id = "another-account"))
        val store = HomeStore(other, CoroutineScope(Dispatchers.Unconfined), kept = shelfStore())
        assertEquals(KeptShelves(), store.shelves)
    }

    @Test
    fun anEqualAnswerLeavesTheShelvesAlone() {
        val connection = server.connection(octo)
        shelfStore().write(connection.server.key, kept)
        server.answer("getAlbumList2", albums("a1"))
        stationsAnswer("st1" to "Morning", "st2" to "Chill")
        val store = HomeStore(connection, CoroutineScope(Dispatchers.Unconfined), kept = shelfStore())
        val shown = store.shelves
        store.refresh()
        waitFor { store.data != null }
        store.playlistsAnswered(listOf(Playlist("mine"), Playlist("og-new", "New Releases", octoList = "newReleases", songCount = 40)))
        store.chartAnswered(TopSongs(source = "apple", chart = "overall", entry = listOf(TopSong(1, song = Song("s1", "First")))))
        assertSame("the same shelves, not an equal copy", shown, store.shelves)
    }

    @Test
    fun aChangedAnswerReplacesItsShelfAndIsKept() {
        val connection = server.connection(octo)
        shelfStore().write(connection.server.key, kept)
        server.answer("getAlbumList2", albums("a1"))
        stationsAnswer("st2" to "Chill", "st3" to "Evening")
        val store = HomeStore(connection, CoroutineScope(Dispatchers.Unconfined), kept = shelfStore())
        val madeForYou = store.shelves.madeForYou
        store.refresh()
        waitFor { store.shelves.stations.map { it.id } == listOf("st2", "st3") }
        assertSame("a shelf whose answer did not change stays as it was", madeForYou, store.shelves.madeForYou)
        waitFor { shelfStore().read(connection.server.key)?.stations?.map { it.id } == listOf("st2", "st3") }
    }

    @Test
    fun aFailedLoadKeepsWhatIsShown() {
        val connection = server.connection(octo)
        shelfStore().write(connection.server.key, kept)
        server.answer("getAlbumList2", albums("a1"))
        server.fail("getInternetRadioStations", 0, "busy")
        val store = HomeStore(connection, CoroutineScope(Dispatchers.Unconfined), kept = shelfStore())
        store.refresh()
        waitFor { store.data != null }
        assertEquals(kept.stations, store.shelves.stations)
    }

    @Test
    fun aServerWithoutChartsOrListsShowsNone() {
        val connection = server.connection(octo)
        shelfStore().write(connection.server.key, kept)
        val store = HomeStore(connection, CoroutineScope(Dispatchers.Unconfined), kept = shelfStore())
        store.chartAnswered(null)
        store.playlistsAnswered(listOf(Playlist("mine")))
        assertNull(store.shelves.chart)
        assertTrue(store.shelves.madeForYou.isEmpty())
        waitFor { shelfStore().read(connection.server.key)?.let { it.chart == null && it.madeForYou.isEmpty() } == true }
    }

    @Test
    fun hiddenStationsAreNotAskedForUntilShownAgain() {
        server.answer("getAlbumList2", albums("a1"))
        stationsAnswer("st1" to "Morning")
        var sections = toggleHomeSection(toggleHomeSection(DefaultHomeSections, HomeSection.Stations, shown = false), HomeSection.InternetRadio, shown = false)
        val store = HomeStore(server.connection(octo), CoroutineScope(Dispatchers.Unconfined), sections = { sections })
        store.refresh()
        waitFor { store.data != null }
        assertFalse("getInternetRadioStations" in server.endpoints())
        assertNull("not asked is not an empty answer", store.data!!.stations)
        sections = DefaultHomeSections
        store.sectionsChanged()
        waitFor { store.shelves.stations.map { it.id } == listOf("st1") }
    }

    @Test
    fun theLiveStreamsAreKeptForNextTime() {
        val connection = server.connection()
        server.answer("getAlbumList2", albums("a1"))
        server.answer("getInternetRadioStations", """"internetRadioStations":{"internetRadioStation":[{"id":"r1","name":"City Radio","streamUrl":"https://radio.example.com/live.mp3"}]}""")
        val store = HomeStore(connection, CoroutineScope(Dispatchers.Unconfined), kept = shelfStore())
        store.refresh()
        waitFor { store.shelves.live.map { it.id } == listOf("r1") }
        waitFor { shelfStore().read(connection.server.key)?.live?.map { it.id } == listOf("r1") }
        val again = HomeStore(connection, CoroutineScope(Dispatchers.Unconfined), kept = shelfStore())
        assertEquals("before anything is asked", listOf("City Radio"), again.shelves.live.map { it.name })
    }

    @Test
    fun homeKeepsOnlyTheChartSongsItsRowShows() {
        val top = TopSongs(source = "apple", chart = "overall", entry = (1..50).map { TopSong(it, song = Song("s$it", "Song $it")) } + TopSong(51))
        assertEquals((1..10).map { "s$it" }, homeChart(top).entry.map { it.song!!.id })
    }

    @Test
    fun whenNothingAnswersThePageSaysSo() = runBlocking {
        server.fail("getAlbumList2", 0, "down")
        try {
            loadHome(server.connection())
            fail("an empty Home was shown for a server that answered nothing")
        } catch (e: SubsonicException) {
            assertTrue(e.message!!.contains("down"))
        }
    }

    @Test
    fun favouritesShowTheNewestFavouriteFirst() {
        val albums = listOf(Album("old", starred = "2024-01-01T00:00:00Z"), Album("new", starred = "2026-09-01T00:00:00Z"), Album("undated", starred = "yes"))
        assertEquals(listOf("new", "old", "undated"), newestFavourites(albums).map { it.id })
    }

    @Test
    fun pinnedPlaylistsComeFirstInTheOrderTheyWerePinned() {
        val playlists = listOf(Playlist("a"), Playlist("b"), Playlist("c"), Playlist("d"))
        assertEquals(listOf("c", "a", "b", "d"), pinnedFirst(playlists, listOf("c", "a", "gone")).map { it.id })
    }

    // Made for you has its own shelf, in kind order, and is not shown again
    // among the listener's own playlists.
    @Test
    fun madeForYouListsHaveTheirOwnShelf() {
        val playlists = listOf(
            Playlist("mine"),
            Playlist("og-deep", octoList = "deepCuts"),
            Playlist("og-new", octoList = "newReleases"),
            Playlist("og-later", octoList = "aKindFromANewerServer"),
            Playlist("og-re", octoList = "rediscover"),
            Playlist("og-liked", octoList = "liked"),
        )
        assertEquals(listOf("og-liked", "og-new", "og-re", "og-deep", "og-later"), madeForYou(playlists).map { it.id })
        assertEquals(listOf("mine"), yourPlaylists(playlists).map { it.id })
        assertTrue("a server without the lists marks none", madeForYou(listOf(Playlist("a"), Playlist("b"))).isEmpty())
    }

    // On Octo, its mixes and stations leave "Your playlists" for their own
    // shelves; someone else's and a smart playlist stay, read-only or not.
    @Test
    fun octosOwnListsAreNotTheListenersPlaylists() {
        val pop = Playlist("og00000000000000000001", "Pop Mix", owner = "ana", readonly = true, octoGroup = "genre")
        val decade = Playlist("og00000000000000000002", "1990s Mix", owner = "ana", readonly = true, octoGroup = "decade")
        val station = Playlist("or00000000000000000003", "Your Radio", owner = "ana", readonly = true, octoGroup = "station")
        val shared = Playlist("5f3c1", "Road trip", owner = "ben", readonly = true)
        val smart = Playlist("5f3c2", "Top rated", owner = "ana", readonly = true)
        val all = listOf(Playlist("mine", owner = "ana"), pop, decade, station, shared, smart)
        assertEquals(listOf("mine", "5f3c1", "5f3c2"), yourPlaylists(all, "ana", isOcto = true).map { it.id })
        assertEquals(all.map { it.id }, yourPlaylists(all, "ana", isOcto = false).map { it.id })
        val groups = octoLists(all, "ana", isOcto = true).toMap()
        assertEquals(listOf("Pop Mix"), groups[OctoListGroup.Genres]?.map { it.name })
        assertEquals(listOf("1990s Mix"), groups[OctoListGroup.Years]?.map { it.name })
        assertEquals(listOf("Your Radio"), groups[OctoListGroup.Stations]?.map { it.name })
        assertTrue(octoLists(all, "ana", isOcto = false).isEmpty())
    }
}
