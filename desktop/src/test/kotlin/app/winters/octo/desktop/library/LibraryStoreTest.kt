package app.winters.octo.desktop.library

import app.winters.octo.desktop.FakeServer
import app.winters.octo.desktop.songJson
import app.winters.octo.server.ALBUMS_TAKEN_IN
import app.winters.octo.server.Arriving
import app.winters.octo.server.NEW_MUSIC_LOOK_MS
import app.winters.octo.subsonic.Album
import app.winters.octo.subsonic.Artist
import app.winters.octo.subsonic.Library
import app.winters.octo.subsonic.Song
import app.winters.octo.subsonic.SubsonicException
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.asCoroutineDispatcher
import kotlinx.coroutines.cancel
import kotlinx.coroutines.flow.first
import kotlinx.coroutines.runBlocking
import kotlinx.coroutines.withTimeout
import org.junit.After
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertSame
import org.junit.Assert.assertTrue
import org.junit.Test
import java.util.concurrent.ConcurrentHashMap
import java.util.concurrent.Executors

class LibraryStoreTest {
    // A stand-in for the window's thread: one thread, with a name to look for.
    private val windowThread = Executors.newSingleThreadExecutor { Thread(it, WINDOW) }
    private val window = windowThread.asCoroutineDispatcher()
    private val job = SupervisorJob()
    private val scope = CoroutineScope(window + job)

    @After
    fun stop() {
        scope.cancel()
        window.close()
    }

    private val songs = listOf(
        Song("s1", "Blue Monday", artist = "New Order", albumId = "a1", genre = "Synth-pop", played = "2026-09-01T10:00:00Z"),
        Song("s2", "Atmosphere", artist = "Joy Division", albumId = "a2", genre = "Post-punk"),
    )

    // Waits for every load started so far to finish.
    private fun settle() = runBlocking { withTimeout(10_000) { job.children.forEach { it.join() } } }

    private fun ready(store: LibraryStore): LibraryIndex = runBlocking {
        withTimeout(10_000) { (store.state.first { it is LibraryState.Ready } as LibraryState.Ready).index }
    }

    @Test
    fun theLibraryIsReadAndIndexedAwayFromTheWindowsThread() {
        val threads = ConcurrentHashMap.newKeySet<String>()
        // A song list that notes every thread that reads it.
        val watched = object : AbstractList<Song>() {
            override val size get() = songs.size

            override fun get(index: Int): Song {
                threads += Thread.currentThread().name
                return songs[index]
            }
        }
        val store = LibraryStore({
            threads += Thread.currentThread().name
            Library(watched, emptyList(), emptyList())
        }, scope)
        store.load()
        val index = ready(store)
        assertEquals(listOf("s1"), index.history.map { it.id })
        assertEquals(2, index.genres.size)
        assertTrue(threads.isNotEmpty())
        assertFalse("nothing on the window's thread: $threads", WINDOW in threads)
        assertTrue("all on the shared worker threads: $threads", threads.all { it.startsWith("DefaultDispatcher-worker") })
    }

    @Test
    fun aFailedRefreshKeepsWhatWasReadBefore() {
        var reads = 0
        val store = LibraryStore({
            if (++reads > 1) throw SubsonicException.NotFound("gone")
            Library(songs, emptyList(), emptyList())
        }, scope)
        store.load()
        val first = ready(store)
        settle()
        store.load()
        settle()
        assertEquals(2, reads)
        assertSame(first, store.index)
    }

    @Test
    fun aFailedFirstReadSaysSo() {
        val store = LibraryStore({ throw SubsonicException.NotFound("gone") }, scope)
        store.load()
        settle()
        assertTrue(store.state.value is LibraryState.Failed)
    }

    @Test
    fun takingInPutsNewMusicInPlace() {
        val index = LibraryIndex(songs, listOf(Album("a1", "Power, Corruption & Lies", artist = "New Order", artistId = "ar1", songCount = 1)), listOf(Artist("ar1", "New Order")))
        assertSame(index, index.takingIn(emptyList(), emptyList()))
        assertSame("found online is not the library's", index, index.takingIn(listOf(Song("e1", "Lift", isExternal = true)), emptyList()))
        val next = index.takingIn(
            listOf(Song("s3", "Age of Consent", albumId = "a1"), Song("s4", "Nightcall", albumId = "a9")),
            listOf(Album("a1", "Power, Corruption & Lies", artist = "New Order", artistId = "ar1", songCount = 2), Album("a9", "Nightcall", artist = "Kavinsky", artistId = "ar9", songCount = 1)),
        )
        assertTrue(next.hasSong("s3") && next.hasSong("s4") && next.hasSong("s1"))
        assertEquals(listOf("a1", "a9"), next.albums.map { it.id })
        assertEquals(2, next.albums.first().songCount)
        assertEquals(listOf("ar1", "ar9"), next.artists.map { it.id })
        assertTrue(next.hasArtist("ar9"))
    }

    // A search found songs the server took in since the library was read:
    // their albums are read and join the index the pages read.
    @Test
    fun aSearchTakesInWhatTheLibraryLacks() = FakeServer().use { server ->
        server.answer("getAlbum", """"album":{"id":"al-new","name":"Octo ALAC test","artist":"Kavinsky","artistId":"ar9","songCount":2,"song":[${songJson("s-new", "Nightcall", albumId = "al-new")},${songJson("s-new2", "Angel Grove", albumId = "al-new")}]}""")
        val store = LibraryStore({ Library(songs, emptyList(), emptyList()) }, scope, server.client())
        store.load()
        ready(store)
        val found = Arriving(listOf(Song("s-new", "Nightcall", albumId = "al-new")), emptyList())
        assertTrue(runBlocking { withTimeout(10_000) { store.takeIn(found) } })
        val index = store.index!!
        assertTrue(index.hasSong("s-new") && index.hasSong("s-new2") && index.hasAlbum("al-new"))
        // Nothing new: nothing asked.
        assertFalse(runBlocking { store.takeIn(Arriving.Nothing) })
    }

    @Test
    fun aLookTakesInNewAlbumsOnlyWhenTheServerReadItsFolders() = FakeServer().use { server ->
        var now = 0L
        server.answer("getScanStatus", """"scanStatus":{"scanning":false,"count":3,"lastScan":"2026-10-13T02:00:00Z"}""")
        val store = LibraryStore({ Library(songs, listOf(Album("a1", songCount = 1)), emptyList()) }, scope, server.client(), clock = { now })
        store.load()
        ready(store)
        settle()

        // The server has not read its folders since: one small question.
        now += NEW_MUSIC_LOOK_MS
        store.look()
        settle()
        assertEquals(listOf("getScanStatus", "getScanStatus"), server.endpoints())

        // Within the quarter hour: nothing asked at all.
        server.calls.clear()
        server.answer("getScanStatus", """"scanStatus":{"scanning":false,"count":5,"lastScan":"2026-10-13T02:10:00Z"}""")
        store.look()
        settle()
        assertTrue(server.calls.isEmpty())

        // It read them again: the newest albums show one new, taken in.
        server.answer("getAlbumList2", """"albumList2":{"album":[{"id":"al-new","name":"Octo ALAC test","songCount":1},{"id":"a1","songCount":1}]}""")
        server.answer("getAlbum", """"album":{"id":"al-new","name":"Octo ALAC test","songCount":1,"song":[${songJson("s-new", "Nightcall", albumId = "al-new")}]}""")
        now += NEW_MUSIC_LOOK_MS
        store.look()
        settle()
        assertEquals(listOf("getScanStatus", "getAlbumList2", "getAlbum"), server.endpoints())
        assertTrue(store.index!!.hasSong("s-new"))
        assertTrue(store.index!!.hasAlbum("al-new"))

        // And the next look starts from that reading.
        server.calls.clear()
        now += NEW_MUSIC_LOOK_MS
        store.look()
        settle()
        assertEquals(listOf("getScanStatus"), server.endpoints())
    }

    @Test
    fun tooMuchNewMusicReadsTheWholeLibraryAgain() = FakeServer().use { server ->
        var reads = 0
        var now = 0L
        val many = (1..ALBUMS_TAKEN_IN + 1).joinToString(",") { """{"id":"n$it","songCount":1}""" }
        server.answer("getAlbumList2", """"albumList2":{"album":[$many]}""")
        val store = LibraryStore({
            reads++
            Library(songs, emptyList(), emptyList())
        }, scope, server.client(), clock = { now })
        store.load()
        ready(store)
        settle()
        now += NEW_MUSIC_LOOK_MS
        store.look()
        settle()
        // The read it starts is one more to wait for.
        settle()
        assertEquals(2, reads)
        assertFalse(server.endpoints().contains("getAlbum"))
    }

    private companion object {
        const val WINDOW = "window"
    }
}
