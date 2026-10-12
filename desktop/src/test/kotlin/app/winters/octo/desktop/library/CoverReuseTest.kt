package app.winters.octo.desktop.library

import app.winters.octo.desktop.FakeServer
import app.winters.octo.desktop.player.PlayerState
import app.winters.octo.desktop.player.QueueEntry
import app.winters.octo.desktop.player.RepeatMode
import app.winters.octo.subsonic.Song
import coil3.ImageLoader
import coil3.PlatformContext
import coil3.decode.DataSource
import coil3.request.CachePolicy
import coil3.request.SuccessResult
import kotlinx.coroutines.async
import kotlinx.coroutines.awaitAll
import kotlinx.coroutines.runBlocking
import okhttp3.OkHttpClient
import org.jetbrains.skia.EncodedImageFormat
import org.jetbrains.skia.Surface
import org.junit.After
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Rule
import org.junit.Test
import org.junit.rules.TemporaryFolder
import java.util.concurrent.CopyOnWriteArrayList

// A cover is fetched once and every smaller size is drawn from that copy;
// the covers the player shows are fetched at the largest size, once.
class CoverReuseTest {
    @get:Rule val folder = TemporaryFolder()

    private fun square(px: Int): ByteArray = Surface.makeRasterN32Premul(px, px).run {
        canvas.clear(0xFF2060D0.toInt())
        makeImageSnapshot().encodeToData(EncodedImageFormat.PNG)!!.bytes
    }

    @After
    fun calm() = CoverTraffic.lanes.setUrgent(emptyList())

    // A server whose covers come at the size asked for, noting each size
    // asked for, slowly enough that asks made together overlap.
    private fun covers(test: (FakeServer, ImageLoader, MutableList<Int>) -> Unit) {
        val asked = CopyOnWriteArrayList<Int>()
        FakeServer().use { server ->
            server.fileBy("getCoverArt") { request ->
                val size = request.url.queryParameter("size")!!.toInt()
                asked += size
                Thread.sleep(150)
                square(size)
            }
            test(server, coverLoader(PlatformContext.INSTANCE, OkHttpClient(), folder.newFolder()), asked)
        }
    }

    private fun ImageLoader.load(server: FakeServer, id: String, bucket: Int, keptOnly: Boolean = false) = runBlocking {
        val request = coverRequest(PlatformContext.INSTANCE, server.client(), id, bucket)
            .size(bucket)
            .apply { if (keptOnly) networkCachePolicy(CachePolicy.DISABLED) }
            .build()
        execute(request)
    }

    @Test
    fun aSmallerSizeIsDrawnFromALargerCopyWithoutTheServer() = covers { server, loader, asked ->
        assertTrue(loader.load(server, "mf-1", 1200) is SuccessResult)
        val small = loader.load(server, "mf-1", 150)
        assertTrue(small is SuccessResult)
        assertEquals(DataSource.DISK, (small as SuccessResult).dataSource)
        assertEquals(150, small.image.width)
        assertEquals(listOf(1200), asked)
    }

    @Test
    fun aLargerSizeIsStillFetchedSharp() = covers { server, loader, asked ->
        loader.load(server, "mf-1", 150)
        val large = loader.load(server, "mf-1", 1200) as SuccessResult
        assertEquals(1200, large.image.width)
        assertEquals(listOf(150, 1200), asked)
    }

    @Test
    fun aRequestThatMayOnlyUseKeptCopiesTakesASmallerOne() = covers { server, loader, asked ->
        loader.load(server, "mf-1", 300)
        val kept = loader.load(server, "mf-1", 1200, keptOnly = true)
        assertTrue(kept is SuccessResult)
        assertEquals(300, (kept as SuccessResult).image.width)
        assertEquals(listOf(300), asked)
    }

    @Test
    fun theCoverOfThePlayingSongIsFetchedOnceAtTheLargestSizeForEveryPlace() = covers { server, loader, asked ->
        CoverTraffic.lanes.setUrgent(listOf("mf-on"))
        val results = runBlocking {
            // The bar, the background, the full player and the system's
            // player ask at once.
            listOf(150, 600, 1200, 600).map { bucket -> async(kotlinx.coroutines.Dispatchers.IO) { loader.load(server, "mf-on", bucket) } }.awaitAll()
        }
        assertTrue(results.all { it is SuccessResult })
        assertEquals(listOf(1200), asked)
    }

    @Test
    fun aCoverNotUrgentIsFetchedAtItsOwnSize() = covers { server, loader, asked ->
        loader.load(server, "al-row", 150)
        assertEquals(listOf(150), asked)
    }

    // ---- The songs whose covers are fetched ahead ----

    private fun entry(key: Long, cover: String) = QueueEntry(key, Song(id = "s$key", title = "Song $key", coverArt = cover))

    @Test
    fun theSongOnAndTheNextTwoInPlayOrderAreFetchedAhead() {
        // Shuffled: the play order is what the player gives as played and
        // upcoming.
        val state = PlayerState(
            played = listOf(entry(4, "mf-4")),
            current = entry(2, "mf-2"),
            upcoming = listOf(entry(5, "mf-5"), entry(1, "mf-1"), entry(3, "mf-3")),
            shuffle = true,
        )
        assertEquals(listOf("mf-2", "mf-5", "mf-1"), coversAhead(state))
    }

    @Test
    fun withRepeatAllTheStartOfThePlayOrderFollowsTheEnd() {
        val state = PlayerState(
            played = listOf(entry(1, "mf-1"), entry(2, "mf-2")),
            current = entry(3, "mf-3"),
            upcoming = listOf(entry(4, "mf-4")),
            repeat = RepeatMode.All,
        )
        assertEquals(listOf("mf-3", "mf-4", "mf-1"), coversAhead(state))
        assertEquals(listOf("mf-3", "mf-4"), coversAhead(state.copy(repeat = RepeatMode.Off)))
        // Repeat one: a skip still moves on to the next song.
        assertEquals(listOf("mf-3", "mf-4"), coversAhead(state.copy(repeat = RepeatMode.One)))
    }

    @Test
    fun songsSharingACoverAskForItOnce() {
        val state = PlayerState(current = entry(1, "al-1"), upcoming = listOf(entry(2, "al-1"), entry(3, "al-2")))
        assertEquals(listOf("al-1", "al-2"), coversAhead(state))
    }

    @Test
    fun withNothingOnThereIsNothingToFetch() {
        assertEquals(emptyList<String>(), coversAhead(PlayerState()))
    }
}
