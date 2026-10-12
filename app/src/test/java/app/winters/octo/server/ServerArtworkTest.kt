package app.winters.octo.server

import app.winters.octo.catalog.ArtworkRef
import app.winters.octo.catalog.DRAWN_COVER_VERSION
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNotEquals
import org.junit.Assert.assertTrue
import coil3.decode.DataSource
import coil3.decode.ImageSource
import coil3.fetch.SourceFetchResult
import okio.Buffer
import okio.FileSystem
import org.junit.Assert.assertArrayEquals
import org.junit.Assert.assertFalse
import org.junit.Test

class ServerArtworkTest {
    private val library = ArtworkRef.Server("server:music.example", "al-1")
    private val found = ArtworkRef.Server("server:music.example", "al-1", online = true)
    private val station = ArtworkRef.Server("server:music.example", "or3kZ9QpLmN2xY7wV1bC0a")
    private val day = 24L * 60 * 60 * 1000

    // 2026-09-29T12:00Z, on day 20725.
    private val noon = 1_790_683_200_000L

    @Test
    fun libraryCoversKeepTheKeysTheyWereCachedUnder() {
        // The same keys as before covers found online were kept apart, so
        // nothing already on the phone is fetched again.
        assertEquals("server-art:server:music.example|al-1", serverCoverKey(library))
        assertEquals("server-art:server:music.example|al-1|300", serverCoverDiskKey(library, 300))
    }

    @Test
    fun coversFoundOnlineStartAfreshUnderTheirVersion() {
        assertEquals("online-art:v$ONLINE_COVER_VERSION:server:music.example|al-1", serverCoverKey(found))
        assertEquals("online-art:v$ONLINE_COVER_VERSION:server:music.example|al-1|300", serverCoverDiskKey(found, 300))
        assertTrue(ONLINE_COVER_VERSION >= 2)
    }

    @Test
    fun theSameCoverIdOnlineAndInTheLibraryNeverShareACacheEntry() {
        assertNotEquals(serverCoverKey(library), serverCoverKey(found))
        for (px in listOf(150, 300, 600, 1200)) assertNotEquals(serverCoverDiskKey(library, px), serverCoverDiskKey(found, px))
    }

    @Test
    fun aStationsCoverIsKeptUnderItsVersionAndTheDay() {
        assertEquals("drawn-art:v$DRAWN_COVER_VERSION:20725:server:music.example|or3kZ9QpLmN2xY7wV1bC0a", serverCoverKey(station, noon))
        assertEquals("drawn-art:v$DRAWN_COVER_VERSION:20725:server:music.example|or3kZ9QpLmN2xY7wV1bC0a|300", serverCoverDiskKey(station, 300, noon))
    }

    @Test
    fun aStationsCoverIsAskedForAgainTheNextDay() {
        assertEquals(serverCoverKey(station, 20725 * day), serverCoverKey(station, 20726 * day - 1))
        assertNotEquals(serverCoverKey(station, 20725 * day), serverCoverKey(station, 20726 * day))
    }

    @Test
    fun aStationsCoverNeverUsesTheKeyItWasCachedUnderForever() {
        // What the phone kept a station's cover under before, for good.
        assertNotEquals("server-art:server:music.example|or3kZ9QpLmN2xY7wV1bC0a", serverCoverKey(station, noon))
    }

    @Test
    fun libraryAndOnlineCoversDoNotChangeWithTheDay() {
        assertEquals(serverCoverKey(library, 0), serverCoverKey(library, noon))
        assertEquals(serverCoverKey(found, 0), serverCoverKey(found, noon))
    }

    @Test
    fun aSmallAskReadsItsOwnSizeThenLargerCopiesFromTheDisk() {
        val song = ArtworkRef.Server("server:music.example", "mf-1")
        assertEquals(
            listOf(150, 300, 600, 1200).map { "server-art:server:music.example|mf-1|$it" },
            keptCoverKeys(song, 108),
        )
        assertEquals(listOf("server-art:server:music.example|mf-1|1200"), keptCoverKeys(song, 936))
    }

    @Test
    fun aKeptOnlyAskTakesSmallerCopiesLast() {
        val song = ArtworkRef.Server("server:music.example", "mf-1")
        assertEquals(
            listOf(1200, 600, 300, 150).map { "server-art:server:music.example|mf-1|$it" },
            keptCoverKeys(song, 936, anySize = true),
        )
    }

    @Test
    fun copiesOfAnOnlineCoverNeverAnswerForTheLibrarysOne() {
        assertTrue(keptCoverKeys(found, 150).none { it in keptCoverKeys(library, 150) })
    }

    private fun download(bytes: ByteArray) =
        SourceFetchResult(ImageSource(Buffer().write(bytes), FileSystem.SYSTEM), "image/jpeg", DataSource.NETWORK)

    @Test
    fun aRealCoverIsNotAStandInAndIsLeftWholeForTheDecoder() {
        val bytes = ByteArray(120_000) { (it % 251).toByte() }
        val result = download(bytes)
        assertFalse(isStandIn(result))
        assertArrayEquals(bytes, result.source.source().readByteArray())
    }

    @Test
    fun aCoverAsLongAsTheStandInIsReadThroughAndStillWhole() {
        val bytes = ByteArray(69_228) { 7 }
        val result = download(bytes)
        assertFalse(isStandIn(result))
        assertArrayEquals(bytes, result.source.source().readByteArray())
    }

    @Test
    fun aCoverWithAFallbackIsKeptUnderItsOwnKey() {
        val withFallback = library.copy(fallbackId = "mf-2")
        assertEquals(serverCoverKey(library), serverCoverKey(withFallback))
    }
}
