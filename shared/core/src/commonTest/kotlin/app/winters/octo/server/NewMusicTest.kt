package app.winters.octo.server

import app.winters.octo.subsonic.Album
import app.winters.octo.subsonic.AlbumWithSongs
import app.winters.octo.subsonic.Credentials
import app.winters.octo.subsonic.ScanStatus
import app.winters.octo.subsonic.SearchResult
import app.winters.octo.subsonic.Song
import app.winters.octo.subsonic.SubsonicClient
import kotlinx.coroutines.test.runTest
import mockwebserver3.Dispatcher
import mockwebserver3.MockResponse
import mockwebserver3.MockWebServer
import mockwebserver3.RecordedRequest
import okhttp3.HttpUrl
import okhttp3.OkHttpClient
import org.junit.After
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Before
import org.junit.Test
import java.util.concurrent.CopyOnWriteArrayList

// Music the server took in since the library was copied: when to look for
// it, what counts as new, and what a search turns up of it. Always against
// a local stand-in server.
class NewMusicTest {
    private val server = MockWebServer()
    private val asked = CopyOnWriteArrayList<String>()
    private val urls = CopyOnWriteArrayList<HttpUrl>()
    private val answers = HashMap<String, String>()

    @Before
    fun start() {
        server.dispatcher = object : Dispatcher() {
            override fun dispatch(request: RecordedRequest): MockResponse {
                val endpoint = request.url.pathSegments.last()
                asked += endpoint
                urls += request.url
                val payload = answers[endpoint]
                    ?: return MockResponse.Builder().body(wrap(""""status":"failed","error":{"code":70,"message":"not found"}""")).build()
                return MockResponse.Builder().body(wrap(""""status":"ok",$payload""")).build()
            }
        }
        server.start()
    }

    @After
    fun stop() = server.close()

    private fun wrap(inner: String) = """{"subsonic-response":{"version":"1.16.1",$inner}}"""

    private fun client() = SubsonicClient(server.url("/"), Credentials("winters", "secret"), OkHttpClient())

    private fun scan(lastScan: String, scanning: Boolean = false) {
        answers["getScanStatus"] = """"scanStatus":{"scanning":$scanning,"count":120,"lastScan":"$lastScan"}"""
    }

    private fun newest(vararg albums: String) {
        answers["getAlbumList2"] = """"albumList2":{"album":[${albums.joinToString(",")}]}"""
    }

    private fun albumJson(id: String, songs: Int, external: Boolean = false) =
        """{"id":"$id","name":"Album $id","artist":"Kavinsky","songCount":$songs,"isExternal":$external}"""

    @Test
    fun aLookIsDueOncePerQuarterHour() {
        assertTrue(newMusicLookDue(null, 1_000))
        assertFalse(newMusicLookDue(1_000, 1_000 + NEW_MUSIC_LOOK_MS - 1))
        assertTrue(newMusicLookDue(1_000, 1_000 + NEW_MUSIC_LOOK_MS))
        // A clock that went backwards (another boot) looks again.
        assertTrue(newMusicLookDue(5_000, 1_000))
    }

    @Test
    fun onlyANewReadOfTheFoldersIsWorthReadingOn() {
        val read = ScanStatus(scanning = false, count = 9, lastScan = "2026-10-13T02:10:00Z")
        assertFalse(scannedSince("2026-10-13T02:10:00Z", read))
        assertTrue(scannedSince("2026-10-12T22:00:00Z", read))
        assertTrue("never seen", scannedSince(null, read))
        // Still reading: looked at again once it is done.
        assertFalse(scannedSince("2026-10-12T22:00:00Z", read.copy(scanning = true)))
        // A server that does not say might have new music.
        assertTrue(scannedSince("2026-10-12T22:00:00Z", null))
        assertTrue(scannedSince("2026-10-12T22:00:00Z", read.copy(lastScan = null)))
    }

    @Test
    fun newAndGrownAlbumsAreTakenInAndTooManyCopyEverything() {
        val kept = mapOf("a1" to 10, "a2" to 3)
        assertEquals(NewMusic.None, newMusic(listOf(Album("a1", songCount = 10), Album("a2", songCount = 3)), kept))
        val found = newMusic(
            listOf(
                Album("new", songCount = 2),
                Album("a2", songCount = 4),
                Album("a1", songCount = 10),
                // Found online, not the library's.
                Album("outside", songCount = 12, isExternal = true),
            ),
            kept,
        )
        assertEquals(listOf("new", "a2"), (found as NewMusic.TakeIn).albums.map { it.id })
        val many = (1..ALBUMS_TAKEN_IN + 1).map { Album("n$it", songCount = 1) }
        assertEquals(NewMusic.CopyAll, newMusic(many, kept))
        assertTrue(newMusic(many.take(ALBUMS_TAKEN_IN), kept) is NewMusic.TakeIn)
    }

    @Test
    fun anUnchangedServerIsAskedOneSmallQuestion() = runTest {
        scan("2026-10-13T02:10:00Z")
        newest(albumJson("al-new", 2))
        val look = lookForNewMusic(client(), "2026-10-13T02:10:00Z") { emptyMap() }
        assertEquals(NewMusic.None, look.found)
        assertEquals("2026-10-13T02:10:00Z", look.scan)
        assertEquals(listOf("getScanStatus"), asked)
    }

    @Test
    fun aNewReadOfTheFoldersFindsTheNewAlbum() = runTest {
        scan("2026-10-13T02:10:00Z")
        newest(albumJson("al-new", 2), albumJson("al-old", 11), albumJson("al-online", 9, external = true))
        var counted = emptyList<String>()
        val look = lookForNewMusic(client(), "2026-10-12T22:00:00Z") { ids ->
            counted = ids
            mapOf("al-old" to 11)
        }
        assertEquals(listOf("al-new"), (look.found as NewMusic.TakeIn).albums.map { it.id })
        assertEquals("2026-10-13T02:10:00Z", look.scan)
        assertEquals(listOf("al-new", "al-old", "al-online"), counted)
        assertEquals(listOf("getScanStatus", "getAlbumList2"), asked)
        val list = urls[1]
        assertEquals("newest", list.queryParameter("type"))
        assertEquals("$NEWEST_ALBUMS_READ", list.queryParameter("size"))
    }

    @Test
    fun aServerThatDoesNotSayIsLookedAtAnyway() = runTest {
        newest(albumJson("al-new", 2))
        val look = lookForNewMusic(client(), "2026-10-12T22:00:00Z") { emptyMap() }
        assertTrue(look.found is NewMusic.TakeIn)
        // What was seen stays, to set against the next answer.
        assertEquals("2026-10-12T22:00:00Z", look.scan)
    }

    @Test
    fun aServerReadingItsFoldersIsLeftUntilItIsDone() = runTest {
        scan("2026-10-13T02:10:00Z", scanning = true)
        val look = lookForNewMusic(client(), "2026-10-12T22:00:00Z") { emptyMap() }
        assertEquals(NewMusic.None, look.found)
        assertEquals("2026-10-12T22:00:00Z", look.scan)
        assertEquals(listOf("getScanStatus"), asked)
        assertEquals(null, lastScanOf(client()))
    }

    @Test
    fun aSearchTurnsUpTheServersOwnMusicTheCopyLacks() {
        val sent = SearchResult(
            album = listOf(Album("al-alac", "Octo ALAC test"), Album("al-kept", "Nightcall"), Album("e-al", "Outrun", isExternal = true)),
            song = listOf(
                Song("s-new", "Nightcall (ALAC test)", albumId = "al-alac"),
                Song("s-new2", "Angel Grove (ALAC test)", albumId = "al-alac"),
                Song("s-kept", "Nightcall", albumId = "al-kept"),
                Song("e-1", "Nightcall", isExternal = true),
                Song("s-new", "Nightcall (ALAC test)", albumId = "al-alac"),
            ),
        )
        val found = arriving(sent, { it.id == "s-kept" }, { it.id == "al-kept" })
        assertEquals(listOf("s-new", "s-new2"), found.songs.map { it.id })
        assertEquals(listOf("al-alac"), found.albums.map { it.id })
        assertEquals(listOf("al-alac"), found.albumIds())
        assertTrue(arriving(sent, { true }, { true }).isEmpty)
        // A server that finds music online marked some of this answer, so
        // the rest is its library.
        assertEquals(listOf("s-new", "s-new2"), arriving(sent, { it.id == "s-kept" }, { true }, findsOnline = true).songs.map { it.id })
        // An answer of its that marks nothing cannot be told apart.
        val unmarked = SearchResult(song = listOf(Song("s-new", "Nightcall (ALAC test)", albumId = "al-alac")))
        assertTrue(arriving(unmarked, { false }, { false }, findsOnline = true).isEmpty)
        assertEquals(listOf("s-new"), arriving(unmarked, { false }, { false }).songs.map { it.id })
    }

    @Test
    fun theAlbumsTakenInAreCapped() {
        val songs = (1..ALBUMS_TAKEN_IN + 3).map { Song("s$it", "Song $it", albumId = "al$it") }
        val found = Arriving(songs + Song("loose", "No album"), listOf(Album("named")))
        assertEquals(ALBUMS_TAKEN_IN, found.albumIds().size)
        assertEquals("named", found.albumIds().first())
    }

    @Test
    fun anAlbumReadWholeKeepsWhatTheListWouldSay() {
        val read = AlbumWithSongs("al1", "Nightcall", "Kavinsky", artistId = "ar1", songCount = 2, created = "2026-10-13T02:10:00Z", song = listOf(Song("s1", "Nightcall")))
        val listed = read.asListed()
        assertEquals("al1", listed.id)
        assertEquals(2, listed.songCount)
        assertEquals("2026-10-13T02:10:00Z", listed.created)
        assertEquals("ar1", listed.artistId)
    }
}
