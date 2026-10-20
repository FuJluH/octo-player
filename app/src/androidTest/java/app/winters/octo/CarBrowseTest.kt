package app.winters.octo

import android.content.ComponentName
import android.graphics.BitmapFactory
import androidx.media3.common.MediaItem
import androidx.media3.session.LibraryResult
import androidx.media3.session.MediaBrowser
import androidx.media3.session.SessionToken
import androidx.test.ext.junit.runners.AndroidJUnit4
import androidx.test.platform.app.InstrumentationRegistry
import app.winters.octo.playback.ArtworkProvider
import app.winters.octo.playback.OctoPlaybackService
import com.google.common.util.concurrent.ListenableFuture
import org.junit.After
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertTrue
import org.junit.Before
import org.junit.Test
import org.junit.runner.RunWith
import java.util.concurrent.TimeUnit

// Browses the music the way a car does, through the playback service, on
// the phone and its real library. It never plays anything, so the queue on
// the phone is left alone.
@RunWith(AndroidJUnit4::class)
class CarBrowseTest {
    private val instrumentation = InstrumentationRegistry.getInstrumentation()
    private val context = instrumentation.targetContext
    private lateinit var browser: MediaBrowser

    @Before
    fun connect() {
        val token = SessionToken(context, ComponentName(context, OctoPlaybackService::class.java))
        lateinit var pending: ListenableFuture<MediaBrowser>
        instrumentation.runOnMainSync { pending = MediaBrowser.Builder(context, token).buildAsync() }
        browser = pending.get(10, TimeUnit.SECONDS)
    }

    @After
    fun disconnect() {
        instrumentation.runOnMainSync { browser.release() }
    }

    // Runs a browser call on the main thread and waits for its answer.
    private fun <T> ask(call: MediaBrowser.() -> ListenableFuture<LibraryResult<T>>): T {
        lateinit var pending: ListenableFuture<LibraryResult<T>>
        instrumentation.runOnMainSync { pending = browser.call() }
        val result = pending.get(20, TimeUnit.SECONDS)
        assertEquals(LibraryResult.RESULT_SUCCESS, result.resultCode)
        return result.value!!
    }

    private fun children(parentId: String, pageSize: Int = 50): List<MediaItem> =
        ask { getChildren(parentId, 0, pageSize, null) }

    @Test
    fun theRootHasTheFourTabs() {
        val root = ask { getLibraryRoot(null) }
        val tabs = children(root.mediaId).map { it.mediaMetadata.title.toString() }
        assertEquals(listOf("Recent", "Playlists", "Albums", "Artists"), tabs)
    }

    @Test
    fun albumsAreCoversThatOpenToTheirSongs() {
        val albums = children("tab:albums", pageSize = 5)
        assertEquals(5, albums.size)
        val album = albums.first()
        assertTrue(album.mediaMetadata.isBrowsable == true && album.mediaMetadata.isPlayable == true)
        val songs = children(album.mediaId)
        assertTrue(songs.isNotEmpty())
        // A song remembers its album, so choosing it plays the album from there.
        assertTrue(songs.all { it.mediaId.startsWith("song:") && it.mediaId.endsWith("|in:" + album.mediaId) })
    }

    @Test
    fun anAlbumAndItsSongCanBeLookedUpById() {
        val album = children("tab:albums", pageSize = 1).single()
        assertEquals(album.mediaMetadata.title, ask { getItem(album.mediaId) }.mediaMetadata.title)
        val song = children(album.mediaId).first()
        val found = ask { getItem(song.mediaId) }
        assertEquals(song.mediaId, found.mediaId)
        assertEquals(song.mediaMetadata.title, found.mediaMetadata.title)
    }

    @Test
    fun anArtistOpensToTheirAlbums() {
        val artist = children("tab:artists", pageSize = 1).single()
        val albums = children(artist.mediaId)
        assertTrue(albums.isNotEmpty() && albums.all { it.mediaId.startsWith("album:") })
    }

    @Test
    fun coversAreServedAsSmallPictures() {
        val album = children("tab:albums", pageSize = 40).first { it.mediaMetadata.artworkUri != null }
        val uri = album.mediaMetadata.artworkUri!!
        assertEquals(ArtworkProvider.AUTHORITY, uri.authority)
        val bitmap = context.contentResolver.openInputStream(uri)!!.use(BitmapFactory::decodeStream)
        assertNotNull(bitmap)
        assertTrue(bitmap.width in 1..512 && bitmap.height in 1..512)
    }

    @Test
    fun searchFindsMusic() {
        lateinit var pending: ListenableFuture<LibraryResult<Void>>
        instrumentation.runOnMainSync { pending = browser.search("love", null) }
        assertEquals(LibraryResult.RESULT_SUCCESS, pending.get(20, TimeUnit.SECONDS).resultCode)
        val found: List<MediaItem> = ask { getSearchResult("love", 0, 50, null) }
        assertTrue(found.isNotEmpty())
    }
}
