package app.winters.octo.desktop.search

import app.winters.octo.desktop.FakeServer
import app.winters.octo.desktop.library.LibraryIndex
import app.winters.octo.desktop.songJson
import app.winters.octo.discovery.albumShareLine
import app.winters.octo.subsonic.Acquisition
import app.winters.octo.subsonic.OCTO_ACQUISITIONS
import app.winters.octo.subsonic.Album
import app.winters.octo.subsonic.Artist
import app.winters.octo.subsonic.Playlist
import app.winters.octo.subsonic.SearchResult
import app.winters.octo.subsonic.Song
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.Job
import kotlinx.coroutines.cancel
import kotlinx.coroutines.delay
import kotlinx.coroutines.flow.first
import kotlinx.coroutines.runBlocking
import kotlinx.coroutines.withTimeout
import org.junit.After
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class SearchTest {
    private val server = FakeServer()

    @After fun stop() = server.close()

    private val library = LibraryIndex(
        songs = listOf(Song("lib1", "Karma Police", artist = "Radiohead", duration = 264)),
        albums = listOf(Album("alb1", "OK Computer")),
        artists = listOf(Artist("art1", "Radiohead")),
    )

    private val sent = SearchResult(
        artist = listOf(Artist("art1", "Radiohead"), Artist("ext-art", "Radiohead Tribute")),
        album = listOf(Album("alb1", "OK Computer"), Album("ext-alb", "Kid A Mnesia")),
        song = listOf(Song("lib1", "Karma Police", artist = "Radiohead"), Song("ext1", "Lift", artist = "Radiohead", duration = 250)),
    )

    // Brandon, 2026-10-04: some of his songs in search had checkmarks, some
    // did not, though all were his. Octo had sent an online copy of a song
    // he owns; it went among his songs, marked, so that one row had a "+"
    // and every other row a check. The library's songs are now only his.
    @Test
    fun anOnlineCopyOfALibrarySongIsTheLibrarysOwn() {
        val copy = Song("ext-kp", "Karma Police", artist = "Radiohead", duration = 264, isExternal = true)
        val withCopy = sent.copy(song = listOf(copy, Song("lib1", "Karma Police", artist = "Radiohead", duration = 264), Song("ext1", "Lift", artist = "Radiohead", duration = 250, isExternal = true)))
        val found = splitResults(withCopy, "radiohead", SearchFilter.All, emptyList(), library, outsideOn = true)
        assertEquals(listOf("lib1"), found.library.songs.map { it.id })
        assertFalse(found.library.songs.any { it.isExternal })
        assertEquals(listOf("ext1"), found.outside.songs.map { it.id })
        // Alone, it still stands for the library's song.
        val alone = splitResults(sent.copy(song = listOf(copy)), "radiohead", SearchFilter.All, emptyList(), library, outsideOn = true)
        assertEquals(listOf("lib1"), alone.library.songs.map { it.id })
    }

    @Test
    fun anOctoServerSplitsOutWhatIsNotInTheLibrary() {
        val found = splitResults(sent, "radiohead", SearchFilter.All, emptyList(), library, outsideOn = true)
        assertEquals(listOf("lib1"), found.library.songs.map { it.id })
        assertEquals(listOf("alb1"), found.library.albums.map { it.id })
        assertEquals(listOf("art1"), found.library.artists.map { it.id })
        assertEquals(listOf("ext1"), found.outside.songs.map { it.id })
        assertEquals(listOf("ext-alb"), found.outside.albums.map { it.id })
        assertEquals(listOf("ext-art"), found.outside.artists.map { it.id })
    }

    // Brandon, 2026-10-04: searching "drake" listed albums he owns under
    // "Not in your library": HABIBTI (all eleven songs are in his HABIBTI
    // (FOMO)), HABIBTI (FOMO) itself, and What A Time To Be Alive as if he
    // had none of it, though he has two of its songs.
    @Test
    fun albumsFoundOnlineGoWhereTheLibraryHoldsThem() {
        val fomo = Album("al-fomo", "HABIBTI (FOMO)", artist = "Drake", songCount = 15)
        val library = LibraryIndex(emptyList(), listOf(Album("al-take", "Take Care", artist = "Drake"), fomo), emptyList())
        val sent = SearchResult(
            album = listOf(
                Album("al-take", "Take Care", artist = "Drake"),
                // From a server that does not leave out the library's namesake.
                Album("e-fomo", "HABIBTI (FOMO)", artist = "Drake", songCount = 15, isExternal = true),
                Album("e-held", "HABIBTI", artist = "Drake", songCount = 11, isExternal = true, ownedCount = 11),
                Album("e-wattba", "What A Time To Be Alive", artist = "Drake", songCount = 11, isExternal = true, ownedCount = 2),
                Album("e-maid", "MAID OF HONOUR", artist = "Drake", songCount = 14, isExternal = true, ownedCount = 0),
                // Not counted: listed as before.
                Album("e-sss", "\$ome \$exy \$ongs 4 U", artist = "PARTYNEXTDOOR", songCount = 21, isExternal = true),
            ),
        )
        val found = splitResults(sent, "drake", SearchFilter.All, emptyList(), library, outsideOn = true)

        assertEquals(listOf("al-take", "al-fomo", "e-held"), found.library.albums.map { it.id })
        assertEquals(listOf("e-wattba"), found.outside.partAlbums.map { it.id })
        assertEquals("2 of 11 in your library", albumShareLine(found.outside.partAlbums.single()))
        assertEquals(listOf("e-maid", "e-sss"), found.outside.albums.map { it.id })
        assertFalse(found.outside.notInLibraryEmpty)

        // Only partly held albums: nothing goes under "Not in your library".
        val partOnly = splitResults(SearchResult(album = listOf(sent.album[3])), "drake", SearchFilter.All, emptyList(), library, outsideOn = true)
        assertTrue(partOnly.outside.notInLibraryEmpty)
        assertFalse(partOnly.outside.isEmpty)
        // And the Albums filter keeps them.
        assertEquals(listOf("e-wattba"), splitResults(sent, "drake", SearchFilter.Albums, emptyList(), library, outsideOn = true).outside.partAlbums.map { it.id })
    }

    // "Library songs only": what was found online is hidden, never merged
    // in among the library's.
    @Test
    fun libraryOnlyHidesWhatWasFoundOnline() {
        val found = splitResults(sent, "radiohead", SearchFilter.All, emptyList(), library, outsideOn = true, hideOutside = true)
        assertEquals(listOf("lib1"), found.library.songs.map { it.id })
        assertEquals(listOf("alb1"), found.library.albums.map { it.id })
        assertEquals(listOf("art1"), found.library.artists.map { it.id })
        assertTrue(found.outside.isEmpty)
        // Where they would otherwise count as the library's, marked finds go too.
        val marked = sent.copy(
            album = listOf(Album("alb1", "OK Computer"), Album("ext-alb", "Kid A Mnesia", isExternal = true)),
            song = listOf(Song("lib1", "Karma Police"), Song("ext1", "Lift", isExternal = true)),
        )
        val plain = splitResults(marked, "radiohead", SearchFilter.All, emptyList(), library, outsideOn = false, hideOutside = true)
        assertEquals(listOf("lib1"), plain.library.songs.map { it.id })
        assertEquals(listOf("alb1"), plain.library.albums.map { it.id })
        assertTrue(plain.outside.isEmpty)
    }

    // An answer that marks what it found online is taken at its word: a
    // song or album the server took in since the library was read is the
    // library's, never "not in your library", with or without "Library
    // songs only".
    @Test
    fun whatTheServerTookInSinceTheLibraryWasReadIsTheLibrarys() {
        val sent = SearchResult(
            album = listOf(Album("al-alac", "Octo ALAC test"), Album("ext-alb", "Kid A Mnesia", isExternal = true)),
            song = listOf(Song("s-new", "Nightcall (ALAC test)", artist = "Kavinsky", albumId = "al-alac"), Song("ext1", "Lift", artist = "Radiohead", isExternal = true)),
        )
        val found = splitResults(sent, "test", SearchFilter.All, emptyList(), library, outsideOn = true)
        assertEquals(listOf("s-new"), found.library.songs.map { it.id })
        assertEquals(listOf("al-alac"), found.library.albums.map { it.id })
        assertEquals(listOf("ext1"), found.outside.songs.map { it.id })
        assertEquals(listOf("ext-alb"), found.outside.albums.map { it.id })

        val hidden = splitResults(sent, "test", SearchFilter.All, emptyList(), library, outsideOn = true, hideOutside = true)
        assertEquals(listOf("s-new"), hidden.library.songs.map { it.id })
        assertTrue(hidden.outside.isEmpty)
    }

    // Songs the library had not read yet are taken in, and once in the
    // same answer lists them as the library's.
    @Test
    fun aSearchTakesInWhatTheLibraryLacks() = runBlocking {
        server.answer("search3", """"searchResult3":{"song":[${songJson("s-new", "Nightcall", albumId = "al-new")},${songJson("lib1", "Karma Police")}]}""")
        val scope = CoroutineScope(Dispatchers.Default + Job())
        var index = library
        val asked = mutableListOf<List<String>>()
        val model = SearchModel(server.connection(), { index }, { emptyList() }, scope) { arriving ->
            asked += arriving.songs.map { it.id }
            index = index.takingIn(arriving.songs, emptyList())
            true
        }
        model.type("nightcall")
        withTimeout(5_000) { while (asked.isEmpty()) delay(20) }
        assertEquals(listOf(listOf("s-new")), asked)
        val done = model.state as SearchState.Done
        assertEquals(listOf("s-new", "lib1"), done.found.library.songs.map { it.id })
        scope.cancel()
    }

    @Test
    fun anyOtherServerShowsEverythingAsTheLibrary() {
        val found = splitResults(sent, "radiohead", SearchFilter.All, emptyList(), library, outsideOn = false)
        assertEquals(2, found.library.songs.size)
        assertTrue(found.outside.isEmpty)
    }

    @Test
    fun beforeTheLibraryIsReadNothingIsCalledOutside() {
        val found = splitResults(sent, "radiohead", SearchFilter.All, emptyList(), index = null, outsideOn = true)
        assertTrue(found.outside.isEmpty)
        assertEquals(2, found.library.albums.size)
    }

    @Test
    fun aFilterShowsOnlyItsKind() {
        val found = splitResults(sent, "radiohead", SearchFilter.Albums, emptyList(), library, outsideOn = true)
        assertTrue(found.library.songs.isEmpty())
        assertTrue(found.outside.songs.isEmpty())
        assertEquals(listOf("ext-alb"), found.outside.albums.map { it.id })
    }

    @Test
    fun playlistsMatchByNameAccentsAndCaseIgnored() {
        val lists = listOf(Playlist("p1", "Café Radio"), Playlist("p2", "Gym"))
        val found = splitResults(SearchResult(), "cafe", SearchFilter.All, lists, library, outsideOn = false)
        assertEquals(listOf("p1"), found.library.playlists.map { it.id })
    }

    @Test
    fun moreThanFitsOffersSeeAll() {
        val many = SearchResult(album = (1..21).map { Album("a$it", "Album $it") })
        val found = splitResults(many, "album", SearchFilter.All, emptyList(), null, outsideOn = false)
        assertEquals(20, found.library.albums.size)
        assertTrue(found.library.moreAlbums)
        assertFalse(found.library.moreSongs)
    }

    @Test
    fun theSameCapsAsThePhone() {
        assertEquals(SearchCaps(10, 20, 50, 10), searchCaps(SearchFilter.All))
        assertEquals(1_000, searchCaps(SearchFilter.Songs).songs)
    }

    @Test
    fun typingWaitsForAPauseAndAsksOnce() = runBlocking {
        server.answer("search3", """"searchResult3":{"song":[${songJson("s1", "Lift")}]}""")
        val scope = CoroutineScope(Dispatchers.Default + Job())
        val model = SearchModel(server.connection(), { null }, { emptyList() }, scope)
        model.type("l")
        assertEquals(SearchState.Idle, model.state)
        model.type("li")
        model.type("lif")
        assertEquals(SearchState.Looking, model.state)
        withTimeout(5_000) { while (model.state !is SearchState.Done) delay(20) }
        val done = model.state as SearchState.Done
        assertEquals(listOf("s1"), done.found.library.songs.map { it.id })
        assertEquals(listOf("search3"), server.endpoints())
        val asked = server.calls.single().url
        assertEquals("lif", asked.queryParameter("query"))
        assertTrue("always more than Octo holds back for", asked.queryParameter("songCount")!!.toInt() > 12)
        scope.cancel()
    }
    // A search shows the library's results at once, from the library as last
    // read, while the server is asked for what it found online; the songs
    // found online join after them, and the library's rows keep their places.
    @Test
    fun theLibraryShowsAtOnceWhileTheServerLooks() = runBlocking {
        val gate = java.util.concurrent.CountDownLatch(1)
        server.answerBy("search3") {
            gate.await(5, java.util.concurrent.TimeUnit.SECONDS)
            server.ok(""""searchResult3":{"song":[${songJson("lib1", "Karma Police", artist = "Radiohead")},${songJson("ext1", "Lift", artist = "Radiohead").dropLast(1)},"isExternal":true}]}""")
        }
        val scope = CoroutineScope(Dispatchers.Default + Job())
        val model = SearchModel(server.connection(listOf("$OCTO_ACQUISITIONS:1")), { library }, { emptyList() }, scope)
        model.type("radiohead")
        val early = model.state as SearchState.Done
        assertEquals(listOf("lib1"), early.found.library.songs.map { it.id })
        assertEquals(OnlinePhase.Looking, early.online)
        gate.countDown()
        withTimeout(5_000) { while ((model.state as? SearchState.Done)?.online != OnlinePhase.Done) delay(20) }
        val done = model.state as SearchState.Done
        assertEquals(listOf("lib1"), done.found.library.songs.map { it.id })
        assertEquals(listOf("ext1"), done.found.outside.songs.map { it.id })
        scope.cancel()
    }

    // The server could not be asked: the library's results stay, and the
    // line under them says so, with Try again.
    @Test
    fun aFailedAskKeepsTheLibrarysResults() = runBlocking {
        server.fail("search3", 0, "Octo is restarting")
        val scope = CoroutineScope(Dispatchers.Default + Job())
        val model = SearchModel(server.connection(listOf("$OCTO_ACQUISITIONS:1")), { library }, { emptyList() }, scope)
        model.type("karma")
        withTimeout(5_000) { while ((model.state as? SearchState.Done)?.online == OnlinePhase.Looking) delay(20) }
        val done = model.state as SearchState.Done
        assertEquals(listOf("lib1"), done.found.library.songs.map { it.id })
        assertTrue(done.online is OnlinePhase.Failed)
        scope.cancel()
    }

    // "Library songs only": nothing is waited for online.
    @Test
    fun libraryOnlyWaitsForNothingOnline() {
        val scope = CoroutineScope(Dispatchers.Default + Job())
        val model = SearchModel(server.connection(listOf("$OCTO_ACQUISITIONS:1")), { library }, { emptyList() }, scope, libraryOnly = { true })
        model.type("karma")
        assertEquals(OnlinePhase.Done, (model.state as SearchState.Done).online)
        scope.cancel()
    }

    @Test
    fun theLibrarysOwnSearchMatchesEveryWordAnywhere() {
        val index = LibraryIndex(
            songs = listOf(
                Song("s1", "Numb", artist = "Linkin Park", album = "Meteora"),
                Song("s2", "Numb", artist = "U2", album = "Zooropa"),
                Song("s3", "Faint", artist = "Linkin Park", album = "Meteora"),
            ),
            albums = listOf(Album("a1", "Meteora", artist = "Linkin Park")),
            artists = listOf(Artist("r1", "Linkin Park")),
        )
        val found = localResults(index, "linkin numb", SearchFilter.All, emptyList())
        assertEquals(listOf("s1"), found.songs.map { it.id })
        assertEquals(listOf("s1", "s3"), localResults(index, "Linkin Park", SearchFilter.All, emptyList()).songs.map { it.id })
        assertEquals(listOf("a1"), localResults(index, "meteora", SearchFilter.All, emptyList()).albums.map { it.id })
        assertTrue(localResults(index, "meteora", SearchFilter.Songs, emptyList()).albums.isEmpty())
    }

    @Test
    fun theServersAnswerKeepsTheRowsShown() {
        assertEquals(listOf("b", "a", "c"), inShownOrder(listOf("b", "a"), listOf("a", "c", "b")) { it })
        assertEquals(listOf("a", "c"), inShownOrder(listOf("x", "a"), listOf("a", "c")) { it })
        assertEquals(listOf("a", "c"), inShownOrder(emptyList(), listOf("a", "c")) { it })
    }
}

class FetchesTest {
    private val server = FakeServer()

    @After fun stop() = server.close()

    @Test
    fun theServersWordsBecomeTheButtonsPhases() {
        assertEquals(FetchPhase.Queued, phaseOf(Acquisition(state = "searching")))
        assertEquals(FetchPhase.Downloading(0.5f), phaseOf(Acquisition(state = "downloading", progress = 0.5f)))
        assertEquals(FetchPhase.Adding, phaseOf(Acquisition(state = "importing")))
        assertEquals(FetchPhase.Done, phaseOf(Acquisition(state = "done")))
        assertEquals(FetchPhase.Failed("no source"), phaseOf(Acquisition(state = "failed", error = "no source")))
        assertEquals(FetchPhase.Queued, phaseOf(Acquisition(state = "something new")))
    }

    @Test
    fun askingStarsTheSongAndFollowsItToTheLibrary() = runBlocking {
        server.answer("star")
        server.answer("getAcquisitions", """"acquisitions":{"acquisition":[{"id":"ext1","state":"downloading","progress":0.4,"startedAt":"2026-09-27T10:00:00Z"}]}""")
        var arrived = 0
        val scope = CoroutineScope(Dispatchers.Default + Job())
        val fetches = Fetches(server.client(), scope, onArrived = { arrived++ }, pollMs = 50)
        fetches.request("ext1")
        assertEquals(FetchPhase.Queued, fetches.phase("ext1"))
        withTimeout(5_000) { fetches.phases.first { it["ext1"] is FetchPhase.Downloading } }
        assertEquals(FetchPhase.Downloading(0.4f), fetches.phase("ext1"))
        assertEquals("ext1", server.calls.first { it.url.pathSegments.last() == "star" }.url.queryParameter("id"))
        server.answer("getAcquisitions", """"acquisitions":{"acquisition":[{"id":"ext1","state":"done","startedAt":"2026-09-27T10:00:00Z"}]}""")
        withTimeout(5_000) { fetches.phases.first { it["ext1"] == FetchPhase.Done } }
        assertEquals(1, arrived)
        scope.cancel()
    }

    // A clock that moves on a little each time it is read, so a list asked
    // for after the ask is always later than it.
    private fun ticking(): () -> Long {
        val t = java.util.concurrent.atomic.AtomicLong(1_000_000)
        return { t.addAndGet(10) }
    }

    @Test
    fun aSongTheServerNeverListsIsNotLeftQueued() = runBlocking {
        server.answer("star")
        server.answer("getAcquisitions", """"acquisitions":{"acquisition":[]}""")
        val scope = CoroutineScope(Dispatchers.Default + Job())
        val fetches = Fetches(server.client(), scope, pollMs = 50, clock = ticking())
        fetches.request("ext1")
        withTimeout(5_000) { fetches.phases.first { it["ext1"] == FetchPhase.None } }
        scope.cancel()
    }

    @Test
    fun aSongTheServerForgetsIsNotLeftDownloading() = runBlocking {
        server.answer("star")
        server.answer("getAcquisitions", """"acquisitions":{"acquisition":[{"id":"ext1","state":"downloading","progress":0.4,"startedAt":"2026-09-27T10:00:00Z"}]}""")
        val scope = CoroutineScope(Dispatchers.Default + Job())
        val fetches = Fetches(server.client(), scope, pollMs = 50, clock = ticking())
        fetches.request("ext1")
        withTimeout(5_000) { fetches.phases.first { it["ext1"] is FetchPhase.Downloading } }
        // The server restarted and its list is empty.
        server.answer("getAcquisitions", """"acquisitions":{"acquisition":[]}""")
        withTimeout(5_000) { fetches.phases.first { it["ext1"] == FetchPhase.None } }
        scope.cancel()
    }

    @Test
    fun withNoListComingBack_ASongJustAskedStaysQueued() = runBlocking {
        server.answer("star")
        val scope = CoroutineScope(Dispatchers.Default + Job())
        val fetches = Fetches(server.client(), scope, pollMs = 50, clock = ticking())
        fetches.request("ext1")
        withTimeout(5_000) { while (server.calls.count { it.url.pathSegments.last() == "getAcquisitions" } < 3) kotlinx.coroutines.delay(20) }
        assertEquals(FetchPhase.Queued, fetches.phase("ext1"))
        scope.cancel()
    }
}
