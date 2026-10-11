package app.winters.octo.discovery

import app.winters.octo.catalog.OnlineSongEntity
import app.winters.octo.subsonic.Acquisition
import kotlinx.coroutines.ExperimentalCoroutinesApi
import kotlinx.coroutines.async
import kotlinx.coroutines.test.TestScope
import kotlinx.coroutines.test.advanceTimeBy
import kotlinx.coroutines.test.runCurrent
import kotlinx.coroutines.test.runTest
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

private const val NOW = 1_000_000_000_000L

private fun find(id: String, title: String, artist: String = "Kavinsky", requestedAt: Long = NOW, adoptedId: String = "") = OnlineSongEntity(
    id = "find:$id", sourceId = "server:octo", nativeId = id, title = title, artist = artist, album = "OutRun",
    albumId = null, artistId = null, durationMs = 0, coverId = null, mimeType = null, bitrate = null, seenAt = NOW,
    requestedAt = requestedAt, adoptedId = adoptedId,
)

private fun entry(
    id: String,
    state: String,
    progress: Float? = null,
    title: String = "Nightcall",
    artist: String = "Kavinsky",
    error: String? = null,
    libraryId: String? = null,
    startedAt: String? = "2026-09-26T18:00:00Z",
) = Acquisition(id = id, artist = artist, title = title, state = state, progress = progress, error = error, libraryId = libraryId, startedAt = startedAt)

// Stands in for the server and the library.
private class FakeHost(vararg finds: OnlineSongEntity) : AcquisitionHost {
    val finds = finds.toMutableList()
    val calls = mutableListOf<String>()
    var asked = 0
    var answer: () -> List<Acquisition>? = { emptyList() }
    var library = mapOf<String, String>()
    var onSync: () -> Unit = {}

    override suspend fun waiting() = finds.filter { it.adoptedId.isEmpty() }

    override suspend fun acquisitions(): List<Acquisition>? {
        asked++
        return answer()
    }

    override suspend fun takeIn(libraryId: String): String? {
        calls += "take in $libraryId"
        return library[libraryId]
    }

    override suspend fun adopt(findId: String, trackId: String) {
        calls += "adopt $findId as $trackId"
        adoptNow(findId, trackId)
    }

    override suspend fun syncAndWait() {
        calls += "sync"
        onSync()
    }

    fun adoptNow(findId: String, trackId: String) {
        val at = finds.indexOfFirst { it.id == findId }
        finds[at] = finds[at].copy(adoptedId = trackId)
    }

    fun row(findId: String) = finds.first { it.id == findId }
}

@OptIn(ExperimentalCoroutinesApi::class)
class DownloadProgressTest {
    private fun TestScope.watchOf(host: FakeHost) = ProgressWatch(host) { NOW + testScheduler.currentTime }

    @Test
    fun serverStagesMapOntoWhatTheButtonShows() {
        assertEquals(DownloadPhase.Queued, phaseOf(entry("a", "queued")))
        assertEquals(DownloadPhase.Queued, phaseOf(entry("a", "searching")))
        assertEquals(DownloadPhase.Downloading(0.42f), phaseOf(entry("a", "downloading", 0.42f)))
        assertEquals(DownloadPhase.Downloading(null), phaseOf(entry("a", "downloading")))
        assertEquals(DownloadPhase.Adding, phaseOf(entry("a", "verifying")))
        assertEquals(DownloadPhase.Adding, phaseOf(entry("a", "importing")))
        // Finished on the server is still being added until the library has it.
        assertEquals(DownloadPhase.Adding, phaseOf(entry("a", "done")))
        assertEquals(DownloadPhase.Failed("No source had this song"), phaseOf(entry("a", "failed", error = "No source had this song")))
        assertEquals(DownloadPhase.Failed("the server did not say why"), phaseOf(entry("a", "failed", error = " ")))
        // A stage from a newer server waits like a queued one.
        assertEquals(DownloadPhase.Queued, phaseOf(entry("a", "teleporting")))
    }

    @Test
    fun theLibraryHasTheLastWord() {
        val asked = find("a", "Nightcall")
        assertEquals(DownloadPhase.Queued, phaseFor(asked, null, NOW))
        assertEquals(DownloadPhase.Downloading(0.5f), phaseFor(asked, DownloadPhase.Downloading(0.5f), NOW))
        assertEquals(DownloadPhase.Done, phaseFor(asked.copy(adoptedId = "t1"), DownloadPhase.Adding, NOW))
        assertEquals(DownloadPhase.None, phaseFor(asked.copy(requestedAt = 0), DownloadPhase.Adding, NOW))
        // A download asked for a day ago that never came can be asked for again.
        assertEquals(DownloadPhase.None, phaseFor(asked, null, NOW + 25 * 60 * 60_000L))
    }

    @Test
    fun thePlainStateKeepsAFailureAskable() {
        assertEquals(DownloadState.None, DownloadPhase.None.state)
        assertEquals(DownloadState.Requested, DownloadPhase.Queued.state)
        assertEquals(DownloadState.Requested, DownloadPhase.Downloading(0.1f).state)
        assertEquals(DownloadState.Requested, DownloadPhase.Adding.state)
        assertEquals(DownloadState.Done, DownloadPhase.Done.state)
        assertEquals(DownloadState.None, DownloadPhase.Failed("x").state)
    }

    @Test
    fun pollCadence() {
        assertEquals(2_000L, pollDelayMs(downloadingOnScreen = true, foreground = true))
        assertEquals(5_000L, pollDelayMs(downloadingOnScreen = false, foreground = true))
        assertEquals(30_000L, pollDelayMs(downloadingOnScreen = true, foreground = false))
        assertEquals(30_000L, pollDelayMs(downloadingOnScreen = false, foreground = false))
    }

    @Test
    fun entriesAreFoundByIdThenByTitle() {
        val night = find("dz-1", "Nightcall")
        assertEquals("dz-1", acquisitionFor(night, listOf(entry("dz-9", "queued"), entry("dz-1", "queued", title = "Other")))?.id)
        // A song of an album asked for at once, listed under another id.
        assertEquals("album-7", acquisitionFor(night, listOf(entry("album-7", "downloading", title = "Nightcall (feat. Lovefoxxx)")))?.id)
        // Not a remix, and not another artist's song.
        assertNull(acquisitionFor(night, listOf(entry("x", "queued", title = "Nightcall (Breakbot Remix)"))))
        assertNull(acquisitionFor(night, listOf(entry("x", "queued", artist = "London Grammar"))))
        // The newest entry wins when a song was asked for twice.
        val twice = listOf(
            entry("dz-1", "failed", startedAt = "2026-09-26T17:00:00Z"),
            entry("dz-1", "queued", startedAt = "2026-09-26T18:00:00Z"),
        )
        assertEquals("queued", acquisitionFor(night, twice)?.state)
    }

    @Test
    fun progressNeverGoesBackwards() = runTest {
        val host = FakeHost(find("a", "Nightcall"))
        val answers = listOf(0.3f, 0.5f, 0.2f, null, 0.7f)
        host.answer = { listOf(entry("a", "downloading", answers[minOf(host.asked, answers.size) - 1])) }
        val watch = watchOf(host)
        val seen = mutableListOf<DownloadPhase?>()
        val run = backgroundScope.async { watch.run() }
        runCurrent()
        repeat(5) {
            seen += watch.live.value["find:a"]
            advanceTimeBy(POLL_MS)
            runCurrent()
        }
        assertEquals(listOf(0.3f, 0.5f, 0.5f, 0.5f, 0.7f).map { DownloadPhase.Downloading(it) }, seen)
        run.cancel()
    }

    @Test
    fun asksOftenOnlyWhileADownloadIsOnScreen() = runTest {
        val host = FakeHost(find("a", "Nightcall"))
        host.answer = { listOf(entry("a", "downloading", 0.5f)) }
        val watch = watchOf(host)
        val run = backgroundScope.async { watch.run() }
        runCurrent()
        // Nothing on screen: every 5 seconds.
        host.asked = 0
        advanceTimeBy(10_000)
        runCurrent()
        assertEquals(2, host.asked)

        // On screen: every 2 seconds.
        val hide = watch.show("find:a")
        runCurrent()
        host.asked = 0
        advanceTimeBy(10_000)
        runCurrent()
        assertEquals(5, host.asked)

        // The app in the background: every 30 seconds, whatever is shown.
        watch.foreground = false
        advanceTimeBy(2_000)
        runCurrent()
        host.asked = 0
        advanceTimeBy(60_000)
        runCurrent()
        assertEquals(2, host.asked)

        // Coming back asks at once.
        host.asked = 0
        watch.foreground = true
        runCurrent()
        assertEquals(1, host.asked)
        hide()
        run.cancel()
    }

    @Test
    fun stopsWhenNothingIsLeftWaiting() = runTest {
        val host = FakeHost(find("a", "Nightcall"))
        host.answer = { listOf(entry("a", "queued")) }
        val watch = watchOf(host)
        val run = backgroundScope.async { watch.run() }
        advanceTimeBy(POLL_MS * 2)
        runCurrent()
        assertFalse(run.isCompleted)
        host.adoptNow("find:a", "t1")
        advanceTimeBy(POLL_MS)
        runCurrent()
        assertTrue(run.isCompleted)
        assertTrue(run.await())
        assertTrue(watch.live.value.isEmpty())
    }

    @Test
    fun aFinishedSongIsFetchedThenSyncedThenAdopted() = runTest {
        val host = FakeHost(find("a", "Roadgame"))
        host.answer = { listOf(entry("a", "done", title = "Roadgame", libraryId = "nd-77")) }
        host.library = mapOf("nd-77" to "server:octo:nd-77")
        val shown = mutableListOf<DownloadPhase>()
        // What the button shows at each step of bringing the song in.
        val watch = watchOf(host)
        host.onSync = { shown += phaseFor(host.row("find:a"), watch.live.value["find:a"], NOW) }
        val run = backgroundScope.async { watch.run() }
        runCurrent()
        advanceTimeBy(POLL_MS)
        runCurrent()

        assertEquals(listOf("take in nd-77", "adopt find:a as server:octo:nd-77", "sync"), host.calls)
        // Adopted before the full copy, so the check shows at once.
        assertEquals(listOf(DownloadPhase.Done), shown)
        assertTrue(run.isCompleted)
        assertEquals(DownloadPhase.Done, phaseFor(host.row("find:a"), watch.live.value["find:a"], NOW))
    }

    @Test
    fun aFinishedSongWithoutALibraryIdWaitsForTheSync() = runTest {
        val host = FakeHost(find("a", "Roadgame"))
        host.answer = { listOf(entry("a", "done", title = "Roadgame")) }
        val watch = watchOf(host)
        val before = mutableListOf<DownloadPhase>()
        host.onSync = {
            // Still being added while the library is copied: no check yet.
            before += phaseFor(host.row("find:a"), watch.live.value["find:a"], NOW)
            host.adoptNow("find:a", "t9")
        }
        val run = backgroundScope.async { watch.run() }
        runCurrent()
        advanceTimeBy(POLL_MS)
        runCurrent()
        assertEquals(listOf("sync"), host.calls)
        assertEquals(listOf(DownloadPhase.Adding), before)
        assertEquals(DownloadPhase.Done, phaseFor(host.row("find:a"), watch.live.value["find:a"], NOW))
        assertTrue(run.await())
    }

    @Test
    fun aSongTheLibraryHasNotTakenInIsTriedAFewTimesThenLeft() = runTest {
        val host = FakeHost(find("a", "Roadgame"))
        host.answer = { listOf(entry("a", "done", title = "Roadgame")) }
        val watch = watchOf(host)
        val run = backgroundScope.async { watch.run() }
        advanceTimeBy(ARRIVAL_RETRY_MS * (ARRIVAL_TRIES + 2))
        runCurrent()
        assertEquals(List(ARRIVAL_TRIES) { "sync" }, host.calls)
        assertTrue(run.isCompleted)
        // In the server's library: shown as in the library, not as on its way.
        assertEquals(DownloadPhase.Done, watch.live.value["find:a"])
        assertEquals(DownloadPhase.Done, phaseFor(host.row("find:a"), watch.live.value["find:a"], NOW, watch.listedSince.value))
    }

    @Test
    fun aServerThatCannotSayFallsBackAtOnce() = runTest {
        val host = FakeHost(find("a", "Nightcall"))
        host.answer = { null }
        val watch = watchOf(host)
        assertFalse(watch.run())
        assertEquals(1, host.asked)
        assertTrue(host.calls.isEmpty())
    }

    @Test
    fun anUnreachableServerIsAskedAgainLater() = runTest {
        val host = FakeHost(find("a", "Nightcall"))
        var down = true
        host.answer = { if (down) throw java.io.IOException("away") else listOf(entry("a", "downloading", 0.2f)) }
        val watch = watchOf(host)
        val run = backgroundScope.async { watch.run() }
        runCurrent()
        assertFalse(run.isCompleted)
        down = false
        advanceTimeBy(POLL_MS)
        runCurrent()
        assertEquals(DownloadPhase.Downloading(0.2f), watch.live.value["find:a"])
        run.cancel()
    }

    @Test
    fun aFailureIsShownAndAskingAgainStartsAfresh() = runTest {
        val host = FakeHost(find("a", "Nightcall"))
        val old = entry("a", "failed", error = "No source had this song", startedAt = "2026-09-26T17:00:00Z")
        var list = listOf(old)
        host.answer = { list }
        val watch = watchOf(host)
        // Only a failure left: nothing to wait for.
        assertTrue(watch.run())
        assertEquals(DownloadPhase.Failed("No source had this song"), watch.live.value["find:a"])

        // Asked again: the old failure the server still lists is passed over.
        watch.retry("find:a")
        assertNull(watch.live.value["find:a"])
        val run = backgroundScope.async { watch.run() }
        runCurrent()
        assertEquals(null, watch.live.value["find:a"])
        list = listOf(old, entry("a", "searching", startedAt = "2026-09-26T17:05:00Z"))
        advanceTimeBy(POLL_MS)
        runCurrent()
        assertEquals(DownloadPhase.Queued, watch.live.value["find:a"])
        run.cancel()
    }

    // ---------------------------------------------------------------------------
    // The same rule as the downloads pill

    @Test
    fun aDownloadTheServersListDoesNotShowIsNotQueued() {
        val asked = find("a", "Nightcall")
        val later = NOW + 1_000
        assertEquals("No list since the ask", DownloadPhase.Queued, phaseFor(asked, null, later, listedSince = NOW - 1))
        assertEquals("A list asked for after the ask, without it", DownloadPhase.None, phaseFor(asked, null, later, listedSince = NOW + 500))
        assertEquals("No list coming back, within two minutes", DownloadPhase.Queued, phaseFor(asked, null, NOW + 60_000))
        assertEquals("No list coming back, after two minutes", DownloadPhase.None, phaseFor(asked, null, NOW + 2 * 60_000))
        assertEquals("The reporter's: an hour on, after a restart", DownloadPhase.None, phaseFor(asked, null, NOW + 60 * 60_000))
        assertEquals("The server's news still wins", DownloadPhase.Downloading(0.3f), phaseFor(asked, DownloadPhase.Downloading(0.3f), later, listedSince = NOW + 500))
        assertEquals("Landed", DownloadPhase.Done, phaseFor(asked.copy(adoptedId = "t1"), null, later, listedSince = NOW + 500))
    }

    @Test
    fun aSongAskedWithItsAlbumWaitsForTheAlbum() {
        val asked = find("a", "Nightcall")
        assertEquals(DownloadPhase.Queued, phaseFor(asked, null, NOW + 10 * 60_000, listedSince = NOW + 9 * 60_000, album = true))
        assertEquals(DownloadPhase.None, phaseFor(asked, null, NOW + 30 * 60_000, listedSince = NOW + 29 * 60_000, album = true))
    }

    @Test
    fun aServerThatListsNothingKeepsItsDownloadsQueuedUntilGivenUp() {
        val asked = find("a", "Nightcall")
        assertEquals(DownloadPhase.Queued, phaseFor(asked, null, NOW + 3 * 60 * 60_000, lists = false))
        assertEquals(DownloadPhase.None, phaseFor(asked, null, NOW + 25 * 60 * 60_000, lists = false))
    }

    @Test
    fun songsAskedForWithTheirAlbumShareItsTime() {
        val one = find("a", "Nightcall").copy(albumId = "al-1")
        val two = find("b", "Roadgame").copy(albumId = "al-1")
        val alone = find("c", "Testarossa").copy(albumId = "al-1", requestedAt = NOW + 5)
        val other = find("d", "Odd Look").copy(albumId = "al-2")
        assertEquals(setOf("find:a", "find:b"), askedWithAlbum(listOf(one, two, alone, other)))
        assertEquals(listOf(true, true, false, false), askedSongs(listOf(one, two, alone, other), "server:octo").map { it.album })
    }

    @Test
    fun anotherServersListSaysNothingOfThisServersFinds() {
        val here = find("a", "Nightcall")
        val there = find("b", "Roadgame").copy(sourceId = "server:other")
        val inputs = PhaseInputs(listOf(here, there), emptyMap(), listedSince = NOW + 500, lists = true, sourceId = "server:octo")
        val phases = phasesOf(inputs, NOW + 1_000)
        assertEquals(DownloadPhase.None, phases["find:a"])
        assertEquals("Still within two minutes of its ask", DownloadPhase.Queued, phases["find:b"])
        assertEquals(2 * 60_000L - 1_000, recheckMs(inputs, NOW + 1_000))
        assertNull(recheckMs(PhaseInputs(listOf(here), emptyMap(), NOW + 500, true, "server:octo"), NOW + 1_000))
    }

    @Test
    fun theWatchSaysWhenItsNewestListWasAskedFor_AndAForgottenDownloadLeaves() = runTest {
        val host = FakeHost(find("a", "Nightcall"))
        var list = listOf(entry("a", "downloading", 0.4f))
        host.answer = { list }
        val watch = watchOf(host)
        assertNull(watch.listedSince.value)
        val run = backgroundScope.async { watch.run() }
        runCurrent()
        assertEquals(NOW, watch.listedSince.value)
        assertEquals(DownloadPhase.Downloading(0.4f), phaseFor(host.row("find:a"), watch.live.value["find:a"], NOW, watch.listedSince.value))

        // The server restarted and forgot it.
        list = emptyList()
        advanceTimeBy(POLL_MS)
        runCurrent()
        val now = NOW + testScheduler.currentTime
        assertNull(watch.live.value["find:a"])
        assertEquals(DownloadPhase.None, phaseFor(host.row("find:a"), null, now, watch.listedSince.value))
        run.cancel()
    }

    @Test
    fun aSongTheServerNeverTookShowsAddAfterTheFirstList() = runTest {
        val host = FakeHost(find("a", "Nightcall", requestedAt = NOW - 1))
        val watch = watchOf(host)
        val run = backgroundScope.async { watch.run() }
        runCurrent()
        assertEquals(DownloadPhase.None, phaseFor(host.row("find:a"), watch.live.value["find:a"], NOW, watch.listedSince.value))
        run.cancel()
    }
}
