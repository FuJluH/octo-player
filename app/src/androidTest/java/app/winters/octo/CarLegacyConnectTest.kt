package app.winters.octo

import android.content.ComponentName
import android.media.browse.MediaBrowser
import androidx.test.ext.junit.runners.AndroidJUnit4
import androidx.test.platform.app.InstrumentationRegistry
import app.winters.octo.playback.OctoPlaybackService
import org.junit.After
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Before
import org.junit.Test
import org.junit.runner.RunWith
import java.util.concurrent.CountDownLatch
import java.util.concurrent.TimeUnit
import java.util.concurrent.atomic.AtomicReference

// Connects the way Android Auto does, through the platform's old media
// browser rather than Media3's: the service answers it while its own main
// thread waits. Needs no library, so it runs on a fresh phone or emulator.
@RunWith(AndroidJUnit4::class)
class CarLegacyConnectTest {
    private val instrumentation = InstrumentationRegistry.getInstrumentation()
    private val context = instrumentation.targetContext
    private val connected = CountDownLatch(1)
    private lateinit var browser: MediaBrowser

    @Before
    fun connect() {
        instrumentation.runOnMainSync {
            browser = MediaBrowser(
                context,
                ComponentName(context, OctoPlaybackService::class.java),
                object : MediaBrowser.ConnectionCallback() {
                    override fun onConnected() = connected.countDown()
                },
                null,
            )
            browser.connect()
        }
    }

    @After
    fun disconnect() {
        // A main thread that never answered would hold this up too.
        if (connected.count == 0L) instrumentation.runOnMainSync { browser.disconnect() }
    }

    @Test
    fun connectsAndListsTheTabs() {
        assertTrue("never connected", connected.await(5, TimeUnit.SECONDS))
        assertEquals("root", browser.root)
        val loaded = CountDownLatch(1)
        val children = AtomicReference<List<MediaBrowser.MediaItem>>()
        instrumentation.runOnMainSync {
            browser.subscribe(
                browser.root,
                object : MediaBrowser.SubscriptionCallback() {
                    override fun onChildrenLoaded(parentId: String, items: List<MediaBrowser.MediaItem>) {
                        children.set(items)
                        loaded.countDown()
                    }
                },
            )
        }
        assertTrue("no children", loaded.await(10, TimeUnit.SECONDS))
        val tabs = children.get().map { it.description.title.toString() }
        assertEquals(listOf("Recent", "Playlists", "Albums", "Artists"), tabs)
    }

    @Test
    fun aTabCanBeLookedUpById() {
        val item = lookUp("tab:albums")
        assertNotNull(item)
        assertEquals("Albums", item!!.description.title.toString())
        assertTrue(item.isBrowsable)
    }

    @Test
    fun anUnknownIdFindsNothing() {
        assertNull(lookUp("nothing:here"))
    }

    // The item a car gets for an id, or null when the service says there is none.
    private fun lookUp(id: String): MediaBrowser.MediaItem? {
        assertTrue("never connected", connected.await(5, TimeUnit.SECONDS))
        val loaded = CountDownLatch(1)
        val found = AtomicReference<MediaBrowser.MediaItem?>()
        instrumentation.runOnMainSync {
            browser.getItem(
                id,
                object : MediaBrowser.ItemCallback() {
                    override fun onItemLoaded(item: MediaBrowser.MediaItem?) {
                        found.set(item)
                        loaded.countDown()
                    }

                    override fun onError(mediaId: String) = loaded.countDown()
                },
            )
        }
        assertTrue("no answer", loaded.await(10, TimeUnit.SECONDS))
        return found.get()
    }
}
