package app.winters.octo.desktop.offline

import app.winters.octo.desktop.FakeServer
import app.winters.octo.desktop.settings.SettingsStore
import app.winters.octo.subsonic.DeviceIdentity
import app.winters.octo.subsonic.HeaderScope
import app.winters.octo.subsonic.PURPOSE_HEADER
import app.winters.octo.subsonic.ServerHeaders
import app.winters.octo.subsonic.Song
import app.winters.octo.subsonic.origin
import app.winters.octo.ui.family.FamilyModel
import app.winters.octo.ui.family.OFFLINE_COPIES_OFF
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.cancel
import okhttp3.HttpUrl.Companion.toHttpUrl
import okhttp3.OkHttpClient
import org.junit.After
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Rule
import org.junit.Test
import org.junit.rules.TemporaryFolder
import java.io.File

// Songs kept on this computer: picked by hand, the Liked songs and chosen
// playlists, fetched as offline copies, played from the folder, let go
// when no longer wanted, and refused for a family account without offline
// copies.
class DesktopOfflineTest {
    @get:Rule val folder = TemporaryFolder()

    private val scope = CoroutineScope(SupervisorJob() + Dispatchers.Default)
    private val server = FakeServer()
    private val said = mutableListOf<String>()
    private var liked: List<Song> = emptyList()
    private var familyOn = false

    @After
    fun stop() {
        scope.cancel()
        server.close()
    }

    private fun song(id: String, title: String) = Song(id, title, album = "Album", artist = "Artist", track = 1, suffix = "flac")

    private fun offline(): DesktopOffline {
        val settings = SettingsStore(File(folder.root, "settings.json"))
        val connection = server.connection(if (familyOn) listOf("octoFamily:1") else emptyList())
        // The server's own addresses hear what the request is for.
        val http = OkHttpClient.Builder()
            .addNetworkInterceptor(ServerHeaders { HeaderScope(setOf(origin(server.address.toHttpUrl())), emptyMap(), DeviceIdentity("id", "Studio PC")) })
            .build()
        val family = FamilyModel({ connection.client }, { familyOn }, scope)
        return DesktopOffline(settings, http, scope, File(folder.root, "kept"), { connection }, { liked }, family, { said += it }).also { it.start() }
    }

    private fun until(what: String, check: () -> Boolean) {
        val end = System.currentTimeMillis() + 10_000
        while (!check() && System.currentTimeMillis() < end) Thread.sleep(20)
        assertTrue(what, check())
    }

    @Test
    fun aSongKeptByHandIsFetchedAsAnOfflineCopyAndPlaysFromHere() {
        server.file("stream", ByteArray(1000) { 7 })
        val offline = offline()
        val one = song("tr-1", "One")
        offline.keep(listOf(one), true)
        until("kept") { offline.localFile("tr-1") != null }
        val file = offline.localFile("tr-1")!!
        assertEquals(1000L, file.length())
        assertEquals("01 One.flac", file.name)
        assertTrue(offline.isKeptByHand("tr-1"))
        val fetched = server.calls.first { it.url.pathSegments.last() == "stream" }
        assertEquals("offline", fetched.headers[PURPOSE_HEADER])
        assertEquals("raw", fetched.url.queryParameter("format"))
        // The count is updated just after the file lands.
        until("counted") { offline.status.kept == 1 }
        assertEquals(1000L, offline.status.bytes)

        // Let go: the file goes too.
        offline.keep(listOf(one), false)
        until("let go") { offline.localFile("tr-1") == null }
        assertFalse(file.exists())
    }

    @Test
    fun aLowerDownloadQualityFetchesOpusThroughTheStreamParameters() {
        server.file("stream", ByteArray(100) { 3 })
        val offline = offline()
        offline.setDownloadQuality(app.winters.octo.subsonic.StreamQuality.Standard)
        offline.keep(listOf(song("tr-1", "One")), true)
        until("kept") { offline.localFile("tr-1") != null }
        assertEquals("01 One.opus", offline.localFile("tr-1")!!.name)
        val fetched = server.calls.first { it.url.pathSegments.last() == "stream" }
        assertEquals("opus", fetched.url.queryParameter("format"))
        assertEquals("160", fetched.url.queryParameter("maxBitRate"))
        assertEquals("offline", fetched.headers[PURPOSE_HEADER])
    }

    @Test
    fun likedSongsAndAPlaylistAreKeptWhileChosen() {
        server.file("stream", ByteArray(10) { 1 })
        liked = listOf(song("tr-1", "Liked").copy(starred = "2026-10-01T00:00:00Z"), song("tr-2", "Not liked"))
        server.answer("getPlaylist", """"playlist":{"id":"p1","name":"Road trip","entry":[${app.winters.octo.desktop.songJson("tr-9", "Trip song")}]}""")
        val offline = offline()
        offline.keepLiked(true)
        offline.keepPlaylist("p1", true)
        until("both kept") { offline.localFile("tr-1") != null && offline.localFile("tr-9") != null }
        assertNull(offline.localFile("tr-2"))
        assertTrue(offline.isPlaylistKept("p1"))
        offline.keepPlaylist("p1", false)
        until("playlist let go") { offline.localFile("tr-9") == null }
        assertTrue(offline.localFile("tr-1") != null)
    }

    @Test
    fun aFamilyAccountWithoutOfflineCopiesGetsNoneButKeepsWhatItHas() {
        familyOn = true
        server.answer("getFamily", """"family":{"me":{"username":"winters","role":"Listener","managed":true,"abilities":{"offlineCopies":false}}}""", type = "octo")
        server.answer("getFamilyDevices", """"familyDevices":{"device":[]}""", type = "octo")
        server.file("stream", ByteArray(10) { 1 })
        val offline = offline()
        offline.keep(listOf(song("tr-1", "One")), true)
        until("refused") { OFFLINE_COPIES_OFF in said }
        assertNull(offline.localFile("tr-1"))
        assertTrue(server.calls.none { it.url.pathSegments.last() == "stream" })
        assertEquals(1, offline.status.waiting)
    }

    @Test
    fun aKeptFileOfASwappedServerFileIsFetchedAgain() {
        server.file("stream", ByteArray(1000) { 7 })
        liked = listOf(song("tr-1", "One").copy(size = 1000))
        val offline = offline()
        offline.keep(liked, true)
        until("kept") { offline.localFile("tr-1") != null }
        assertEquals(1000L, offline.files.single().fileSize)
        // The server swaps the song's file for another under the same id.
        server.file("stream", ByteArray(800) { 9 })
        liked = listOf(song("tr-1", "One").copy(size = 800))
        offline.poke()
        until("fetched again") { offline.localFile("tr-1")?.length() == 800L }
        assertEquals(800L, offline.files.single().fileSize)
        assertEquals(2, server.calls.count { it.url.pathSegments.last() == "stream" })
    }

    @Test
    fun aFileKeptBeforeSizesWereNotedIsCheckedByItsOwnSize() {
        server.file("stream", ByteArray(1000) { 7 })
        liked = listOf(song("tr-1", "One").copy(size = 1000))
        val first = offline()
        first.keep(liked, true)
        until("kept") { first.localFile("tr-1") != null }
        // As an older list of kept files has it: no size noted.
        val index = File(first.folder, DesktopOffline.INDEX)
        until("listed") { index.isFile && "fileSize" in index.readText() }
        index.writeText(index.readText().replace(Regex(",\\s*\"fileSize\":\\s*\\d+"), ""))
        val again = offline()
        until("noted") { again.files.singleOrNull()?.fileSize == 1000L }
        assertTrue(again.localFile("tr-1") != null)
        assertEquals(1, server.calls.count { it.url.pathSegments.last() == "stream" })
    }

    @Test
    fun aKeptFileIsTheFileAsItIsWhenItHasTheSongsType() {
        assertTrue(keptAsIs("server/Artist/Album/01 One.flac", "flac"))
        assertTrue(keptAsIs("server/Artist/Album/01 One.FLAC", "flac"))
        assertFalse(keptAsIs("server/Artist/Album/01 One.opus", "flac"))
        // Smaller copies are Opus too, so an Opus file never says.
        assertFalse(keptAsIs("server/Artist/Album/01 One.opus", "opus"))
        assertFalse(keptAsIs("server/Artist/Album/01 One", null))
    }

    @Test
    fun keptSongsAreFoundAgainAfterARestart() {
        server.file("stream", ByteArray(10) { 1 })
        val first = offline()
        first.keep(listOf(song("tr-1", "One")), true)
        until("kept") { first.localFile("tr-1") != null }
        val again = offline()
        until("read back") { again.localFile("tr-1") != null }
    }
}
