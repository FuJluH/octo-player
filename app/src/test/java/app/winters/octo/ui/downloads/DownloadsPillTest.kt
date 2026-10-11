package app.winters.octo.ui.downloads

import app.winters.octo.catalog.OnlineSongEntity
import app.winters.octo.discovery.DownloadPhase
import app.winters.octo.discovery.askedSongs
import app.winters.octo.subsonic.Acquisition
import org.junit.Assert.assertEquals
import org.junit.Test

// The pill shows only while songs are on their way, says the step the one
// furthest along is on, and opens the downloads from anywhere.
class DownloadsPillTest {
    private fun find(id: String, requestedAt: Long = 1_000, adoptedId: String = "", sourceId: String = "server:octo") = OnlineSongEntity(
        id = "find:$id", sourceId = sourceId, nativeId = id, title = "Nightcall", artist = "Kavinsky", album = "OutRun",
        albumId = null, artistId = null, durationMs = 0, coverId = null, mimeType = null, bitrate = null, seenAt = 0,
        requestedAt = requestedAt, adoptedId = adoptedId,
    )

    @Test
    fun onlySongsAskedForOnThisServerThatHaveNotLandedAreAsked() {
        val rows = listOf(
            find("a", requestedAt = 5_000),
            find("b", adoptedId = "nd-7"),
            find("c", sourceId = "server:other"),
            find("d", requestedAt = 0),
        )
        assertEquals(listOf(AskedSong("a", 5_000)), askedSongs(rows, "server:octo"))
        assertEquals("Signed out: nothing", emptyList<AskedSong>(), askedSongs(rows, null))
    }

    @Test
    fun aSongThatLandedLeavesThePill_EvenBeforeAnyListComesBack() {
        val now = 10_000L
        val landed = askedSongs(listOf(find("a", requestedAt = now - 1_000, adoptedId = "nd-7")), "server:octo")
        assertEquals(0, pillCount(emptyList(), landed, null, now))
    }

    @Test
    fun theReportersPill_AnOldAskWithAnEmptyDrawer_IsGone() {
        val now = 100 * 60_000L
        val asked = askedSongs(listOf(find("a", requestedAt = now - 60 * 60_000L)), "server:octo")
        assertEquals("After a list came back", 0, pillCount(emptyList(), asked, now - 3_000, now))
        assertEquals("Straight after a restart, before any list", 0, pillCount(emptyList(), asked, null, now))
    }

    @Test
    fun theWordsCountTheSongs() {
        assertEquals("1 downloading", comingText(1))
        assertEquals("3 downloading", comingText(3))
    }

    @Test
    fun theRingFollowsTheServersStep() {
        fun row(state: String, progress: Float? = null) =
            rowOf(Acquisition(id = "a", title = "Da Funk", artist = "Daft Punk", state = state, progress = progress, key = "s:a", kind = "download"))
        assertEquals(DownloadPhase.Queued, ringPhase(row("queued")))
        assertEquals(DownloadPhase.Queued, ringPhase(row("searching")))
        assertEquals(DownloadPhase.Downloading(0.4f), ringPhase(row("downloading", 0.4f)))
        assertEquals(DownloadPhase.Adding, ringPhase(row("verifying")))
        assertEquals(DownloadPhase.Adding, ringPhase(row("importing")))
    }
}
