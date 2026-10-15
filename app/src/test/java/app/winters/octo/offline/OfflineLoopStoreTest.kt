package app.winters.octo.offline

import app.winters.octo.subsonic.AnimatedArt
import app.winters.octo.subsonic.AnimatedClip
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Rule
import org.junit.Test
import org.junit.rules.TemporaryFolder

// The loops of downloaded albums, kept on the phone beside their songs.
class OfflineLoopStoreTest {
    @get:Rule
    val folder = TemporaryFolder()

    private val square = AnimatedClip(video = "https://music.example.com/animated/t1/square.m3u8", poster = "https://music.example.com/animated/t1/square.jpg", color = "1b2a3a", width = 1080, height = 1080)
    private val tall = AnimatedClip(video = "https://music.example.com/animated/t1/tall.m3u8", width = 1080, height = 1440)
    private val album = LoopAlbum("server:one", "al-1")

    private fun store() = OfflineLoopStore(folder.root.resolve("loops"))

    @Test
    fun theArtIsKeptForUseWithNoConnection() {
        val store = store()
        assertNull(store.read(album))
        store.write(KeptLoops(album.sourceId, album.albumId, AnimatedArt(square, tall)))
        assertEquals(AnimatedArt(square, tall), store.read(album)?.art)
        // The same album on another server is another album.
        assertNull(store.read(LoopAlbum("server:two", "al-1")))
        // An album with none is kept as none, and has nothing more to fetch.
        val none = KeptLoops("server:one", "al-2", null)
        store.write(none)
        assertNull(store.read(none.album)?.art)
        assertTrue(store.complete(none))
        assertNull(store.local(none))
    }

    @Test
    fun theLoopsOnThePhonePlayInPlaceOfTheirAddresses() {
        val store = store()
        val kept = KeptLoops(album.sourceId, album.albumId, AnimatedArt(square, tall))
        store.write(kept)
        assertFalse(store.complete(kept))
        // Only the square loop is here so far: the tall one still streams.
        store.loopFile(album, SQUARE_LOOP).writeBytes(ByteArray(8))
        store.posterFile(album, SQUARE_LOOP).writeBytes(ByteArray(8))
        val local = store.local(kept)!!
        assertTrue(local.square!!.video.startsWith("file:"))
        assertTrue(local.square!!.poster!!.startsWith("file:"))
        assertEquals("1b2a3a", local.square!!.color)
        assertEquals(tall.video, local.tall!!.video)
        assertFalse(store.complete(kept))
        store.loopFile(album, TALL_LOOP).writeBytes(ByteArray(8))
        assertTrue(store.complete(kept))
    }

    @Test
    fun anAlbumNoLongerDownloadedLetsItsLoopsGo() {
        val store = store()
        val other = LoopAlbum("server:one", "al-9")
        for (each in listOf(album, other)) {
            store.write(KeptLoops(each.sourceId, each.albumId, AnimatedArt(square, tall)))
            store.loopFile(each, SQUARE_LOOP).writeBytes(ByteArray(8))
            store.posterFile(each, SQUARE_LOOP).writeBytes(ByteArray(8))
        }
        // A file from a fetch the app closed during, for an album not wanted.
        val stray = store.loopFile(LoopAlbum("server:one", "gone"), TALL_LOOP).apply { writeBytes(ByteArray(8)) }
        store.keepOnly(setOf(album))
        assertTrue(store.loopFile(album, SQUARE_LOOP).isFile)
        assertTrue(store.posterFile(album, SQUARE_LOOP).isFile)
        assertEquals(album, store.records().single().album)
        assertFalse(store.loopFile(other, SQUARE_LOOP).exists())
        assertFalse(store.posterFile(other, SQUARE_LOOP).exists())
        assertNull(store.read(other))
        assertFalse(stray.exists())
    }

    @Test
    fun anAlbumBeingFetchedKeepsItsFilesBeforeItHasARecord() {
        val store = store()
        val fetching = store.loopFile(album, SQUARE_LOOP).apply {
            parentFile!!.mkdirs()
            writeBytes(ByteArray(8))
        }
        store.keepOnly(setOf(album))
        assertTrue(fetching.isFile)
        store.drop(album)
        assertFalse(fetching.exists())
    }

    @Test
    fun onlyClipsWithAnAddressAreShapes() {
        assertEquals(listOf(SQUARE_LOOP, TALL_LOOP), shapes(AnimatedArt(square, tall)).map { it.first })
        assertEquals(listOf(TALL_LOOP), shapes(AnimatedArt(AnimatedClip(video = ""), tall)).map { it.first })
    }
}
