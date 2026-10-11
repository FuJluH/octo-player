package app.winters.octo.ui.downloads

import app.winters.octo.subsonic.Acquisition
import app.winters.octo.subsonic.AcquisitionEvent
import app.winters.octo.subsonic.FoundCandidate
import app.winters.octo.subsonic.FoundSong
import app.winters.octo.subsonic.FoundSongs
import app.winters.octo.subsonic.LIBRARY_ACTION_RESTORE
import app.winters.octo.subsonic.PickCompare
import app.winters.octo.subsonic.PickSide
import app.winters.octo.subsonic.PickResult
import app.winters.octo.subsonic.SubsonicException
import app.winters.octo.subsonic.Upgrade
import java.time.Instant
import java.time.ZoneOffset
import java.util.Locale
import kotlinx.coroutines.ExperimentalCoroutinesApi
import kotlinx.coroutines.test.StandardTestDispatcher
import kotlinx.coroutines.test.TestScope
import kotlinx.coroutines.test.advanceTimeBy
import kotlinx.coroutines.test.runCurrent
import kotlinx.coroutines.test.runTest
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

@OptIn(ExperimentalCoroutinesApi::class)
class DownloadsTest {
    private val now = Instant.parse("2026-10-04T18:00:00Z").toEpochMilli()

    private fun download(
        key: String,
        state: String,
        startedAt: String = "2026-10-04T17:59:00Z",
        updatedAt: String = startedAt,
        kind: String? = "download",
        progress: Float? = null,
        note: String? = null,
        error: String? = null,
        ahead: Int? = null,
    ) = Acquisition(
        id = key.substringAfter(':'), artist = "Air", title = "Song $key", state = state, progress = progress, source = "Soulseek",
        startedAt = startedAt, updatedAt = updatedAt, error = error, note = note, ahead = ahead, key = key, kind = kind,
    )

    private fun upgrade(id: String, state: String, acquisition: String? = null, detail: String? = null, updatedAt: String = "2026-10-04T17:58:00Z") =
        Upgrade(id = id, title = "Up $id", artist = "Air", state = state, detail = detail, updatedAt = updatedAt, acquisition = acquisition)

    @Test
    fun eachStageReadsAsOneLine() {
        assertEquals("Waiting, 3 ahead", statusOf(download("s:a", "queued", ahead = 3)))
        assertEquals("Waiting its turn", statusOf(download("s:a", "queued")))
        assertEquals("Soulseek couldn't get it, trying YouTube", statusOf(download("s:a", "searching", note = "Soulseek couldn't get it, trying YouTube.")))
        assertEquals("Looking on Soulseek", statusOf(download("s:a", "searching")))
        assertEquals("Downloading from Soulseek, 42%", statusOf(download("s:a", "downloading", progress = 0.42f)))
        assertEquals("Checking the file", statusOf(download("s:a", "verifying")))
        assertEquals("Adding to your library", statusOf(download("s:a", "importing")))
        assertEquals("In your library", statusOf(download("s:a", "done")))
        assertEquals("No source had this song", statusOf(download("s:a", "failed", error = "No source had this song.")))
    }

    @Test
    fun runningRowsComeFirst_ThenTheNewestFinished() {
        val rows = drawerRows(
            listOf(
                download("s:old", "done", startedAt = "2026-10-04T17:00:00Z", updatedAt = "2026-10-04T17:05:00Z"),
                download("s:run", "downloading", progress = 0.5f),
                download("s:new", "failed", startedAt = "2026-10-04T17:30:00Z", updatedAt = "2026-10-04T17:40:00Z"),
            ),
            emptyList(),
            now,
        )
        assertEquals(listOf("s:run", "s:new", "s:old"), rows.map { it.key })
        assertEquals(0.5f, rows[0].fraction!!, 0f)
        assertEquals(1, runningCount(rows))
        assertEquals(0.5f, overallFraction(rows)!!, 0f)
    }

    @Test
    fun anUpgradeJoinsItsDownload_AndItsVerdictIsTheLastWord() {
        val rows = drawerRows(
            listOf(download("s:x", "done", kind = "upgrade")),
            listOf(upgrade("nd-1", "upgraded", acquisition = "s:x", detail = "Now FLAC 16-bit 44.1 kHz, 31.0 MB, was MP3 220 kbps.")),
            now,
        )
        val row = rows.single()
        assertEquals(RowKind.Upgrade, row.kind)
        assertEquals(RowPhase.Done, row.phase)
        assertEquals("Now FLAC 16-bit 44.1 kHz, 31.0 MB, was MP3 220 kbps", row.status)
        assertEquals("nd-1", row.findId)
        assertEquals("s:x", row.logKey)
    }

    @Test
    fun aDownloadedUpgradeIsStillCheckedBeforeItCountsAsDone() {
        val row = drawerRows(listOf(download("s:x", "done", kind = "upgrade")), listOf(upgrade("nd-1", "working", acquisition = "s:x")), now).single()
        assertEquals(RowPhase.Checking, row.phase)
        assertFalse(row.finished)
    }

    @Test
    fun anUpgradeWithoutADownloadIsARowOfItsOwn_AndAnOldFinishedOneLeaves() {
        val rows = drawerRows(
            emptyList(),
            listOf(
                upgrade("nd-1", "waiting"),
                upgrade("nd-2", "notFound", updatedAt = "2026-10-04T17:00:00Z"),
                upgrade("nd-3", "upgraded", updatedAt = "2026-10-03T10:00:00.1234567Z"),
            ),
            now,
        )
        assertEquals(listOf("upgrade:nd-1", "upgrade:nd-2"), rows.map { it.key })
        assertEquals("Waiting for Soulseek", rows[0].status)
        assertEquals("No higher quality copy found", rows[1].status)
        assertNull(rows[0].logKey)
    }

    @Test
    fun aClearedRowStaysHidden() {
        val rows = drawerRows(listOf(download("s:a", "done")), listOf(upgrade("nd-2", "notFound")), now, hidden = setOf("upgrade:nd-2", "s:a"))
        assertTrue(rows.isEmpty())
    }

    @Test
    fun aCopyReadsBestFactFirst() {
        val copy = FoundCandidate(
            source = "Soulseek", peer = "peer1", file = "03 - Da Funk.flac", title = "Da Funk", format = "flac",
            quality = "FLAC 16-bit 44.1 kHz", size = 31_000_000, length = 330, freeSlot = true, speed = 1_500_000, rank = 1,
        )
        assertEquals(listOf("FLAC 16-bit 44.1 kHz", "29.6 MB", "5:30", "Soulseek", "peer1", "Free to send now", "1.4 MB/s"), candidateFacts(copy, Locale.US))
        assertEquals("Da Funk", candidateTitle(copy))
        assertEquals("Octo's first choice", candidateVerdict(copy))
        assertEquals("Octo's choice 3", candidateVerdict(copy.copy(rank = 3)))
        assertEquals("From a live album", candidateVerdict(copy.copy(rank = null, note = "From a live album.")))
        assertTrue(isLosslessCopy(copy))
        assertTrue(isLosslessCopy(copy.copy(format = "FLAC 24bit")))
        assertFalse(isLosslessCopy(copy.copy(format = "MP3-320")))
        assertEquals(listOf("MP3", "3 in queue"), candidateFacts(FoundCandidate(source = "", format = "mp3", queueLength = 3), Locale.US))
    }

    @Test
    fun theSummaryCountsWhatRunsAndWhatFinished() {
        val rows = drawerRows(listOf(download("s:a", "done"), download("s:b", "searching"), download("s:c", "failed")), emptyList(), now)
        assertEquals("1 on the way, 2 finished", drawerSummary(rows))
        assertEquals("", drawerSummary(emptyList()))
        assertEquals("Your copy: MP3 220 kbps, 6.7 MB", ownedCopyText("MP3 220 kbps", 7_000_000, Locale.US))
        assertNull(ownedCopyText(null, null))
    }

    @Test
    fun logLinesShowTheClockTime() {
        assertEquals("18:04:31", logTime("2026-10-04T18:04:31Z", ZoneOffset.UTC))
        assertEquals("", logTime(null))
        assertEquals("", logTime("not a time"))
    }

    // ---------------------------------------------------------------------------

    private class FakeDownloads : DownloadsSource {
        var list = listOf<Acquisition>()
        var calls = 0
        val cleared = mutableListOf<String?>()
        var fail = false

        override suspend fun acquisitions(): List<Acquisition> {
            calls++
            if (fail) throw SubsonicException.Server(0, "down")
            return list
        }

        override suspend fun upgrades(): List<Upgrade> = emptyList()

        override suspend fun clear(key: String?) {
            cleared += key
            list = list.filter { !(it.stage.name == "Done" && (key == null || it.key == key)) }
        }
    }

    @Test
    fun theDrawerIsAskedOftenWhileOpenOrBusy_AndSeldomOtherwise() = runTest {
        val source = FakeDownloads().apply { list = listOf(download("s:a", "done")) }
        val scope = TestScope(StandardTestDispatcher(testScheduler))
        val watch = DownloadsWatch(source, scope, clock = { now })
        watch.start()
        scope.runCurrent()
        assertEquals(1, source.calls)
        assertTrue(watch.loaded.value)

        scope.advanceTimeBy(DOWNLOADS_OPEN_POLL_MS + 1)
        assertEquals("Idle and closed: not asked again yet", 1, source.calls)

        watch.open = true
        scope.runCurrent()
        assertEquals(2, source.calls)
        scope.advanceTimeBy(DOWNLOADS_OPEN_POLL_MS + 1)
        assertEquals(3, source.calls)

        // A moment without the server keeps the rows.
        source.fail = true
        scope.advanceTimeBy(DOWNLOADS_OPEN_POLL_MS + 1)
        assertEquals(1, watch.rows.value.size)
        watch.stop()
    }

    @Test
    fun clearingHidesAtOnceAndAsksTheServer() = runTest {
        val source = FakeDownloads().apply { list = listOf(download("s:a", "done"), download("s:b", "downloading")) }
        val scope = TestScope(StandardTestDispatcher(testScheduler))
        val watch = DownloadsWatch(source, scope, clock = { now })
        watch.poll()
        watch.clear()
        assertEquals(listOf("s:b"), watch.rows.value.map { it.key })
        assertEquals(listOf<String?>(null), source.cleared)

        watch.poll()
        watch.clear("s:b")
        assertEquals("A running row is never cleared", listOf("s:b"), watch.rows.value.map { it.key })
    }

    @Test
    fun aFinishedLogIsAskedForAMinuteMore_ThenNoLonger() = runTest {
        var loads = 0
        var state = "downloading"
        val scope = TestScope(StandardTestDispatcher(testScheduler))
        val watch = DownloadLogWatch({ key -> loads++; download(key, state).copy(updatedAt = "2026-10-04T17:59:59Z") }, scope, clock = { now })
        watch.follow("s:a")
        scope.advanceTimeBy(LOG_POLL_MS * 3 + 1)
        assertEquals(4, loads)

        state = "done"
        scope.advanceTimeBy(LOG_FINISHED_GRACE_MS + LOG_POLL_MS * 3)
        val afterGrace = loads
        assertTrue("Still asked a while for the lyrics line", afterGrace > 4 + LOG_FINISHED_GRACE_MS / LOG_POLL_MS - 2)
        scope.advanceTimeBy(LOG_FINISHED_GRACE_MS * 10)
        assertEquals("Asked no more once it settled", afterGrace, loads)
        assertFalse(watch.following)
        assertEquals("done", watch.row.value!!.state)
    }

    @Test
    fun aLogThatFinishedLongAgoIsReadOnce() = runTest {
        var loads = 0
        val scope = TestScope(StandardTestDispatcher(testScheduler))
        val watch = DownloadLogWatch({ key -> loads++; download(key, "failed").copy(updatedAt = "2026-10-04T15:00:00Z") }, scope, clock = { now })
        watch.follow("s:a")
        scope.advanceTimeBy(LOG_POLL_MS * 20)
        assertEquals(1, loads)
        assertFalse(watch.following)
    }

    @Test
    fun aLogWaitsWhileTheAppIsBehind() = runTest {
        var loads = 0
        val scope = TestScope(StandardTestDispatcher(testScheduler))
        val watch = DownloadLogWatch({ key -> loads++; download(key, "downloading") }, scope, clock = { now })
        watch.follow("s:a")
        scope.runCurrent()
        assertEquals(1, loads)

        watch.foreground = false
        scope.advanceTimeBy(LOG_POLL_MS * 100)
        assertEquals("Not asked while behind", 1, loads)

        watch.foreground = true
        scope.runCurrent()
        assertEquals(2, loads)
        watch.close()
    }

    // A Find songs source whose search finishes on the second look, and
    // which notes each pick it is sent.
    private class FakeFind : FindSource {
        var asks = 0
        var searches = 0
        val picks = mutableListOf<Pair<String, FoundCandidate>>()

        // What each pick sent as `anyway`, null when it was left out.
        val anyways = mutableListOf<Boolean?>()
        var answer: suspend () -> PickResult = { PickResult("queued", "Getting it.", "soulseek:x") }

        // The library's copy of the song, when the search is for one.
        var libraryId: String? = null

        override suspend fun start(id: String): FoundSongs {
            searches++
            asks = 0
            return FoundSongs(id = "f$searches", state = "searching", candidate = listOf(copy))
        }

        override suspend fun get(search: String): FoundSongs {
            asks++
            return FoundSongs(
                id = search,
                state = if (asks < 2) "searching" else "done",
                song = FoundSong(title = "Holocene", libraryId = libraryId),
                candidate = listOf(copy, FoundCandidate(source = "Lidarr", index = 1, id = "c2")),
            )
        }

        override suspend fun pick(search: String, copy: FoundCandidate, anyway: Boolean?): PickResult {
            picks += search to copy
            anyways += anyway
            return answer()
        }

        companion object {
            val copy = FoundCandidate(source = "Soulseek", index = 0, id = "c1")
        }
    }

    @Test
    fun aFindSearchIsFollowedUntilItEnds_ThenPicked() = runTest {
        val source = FakeFind()
        val scope = TestScope(StandardTestDispatcher(testScheduler))
        val watch = FindSongsWatch(source, scope)
        watch.search("nd-1")
        scope.runCurrent()
        assertTrue(watch.found.value!!.searching)
        scope.advanceTimeBy(FIND_POLL_MS * 3)
        assertEquals("done", watch.found.value!!.state)
        assertEquals(2, source.asks)

        val picked = watch.pick("f1", FakeFind.copy)
        assertTrue(picked.queued)
        assertEquals("soulseek:x", watch.picked.value!!.key)
        assertEquals(listOf("f1" to FakeFind.copy), source.picks)
    }

    // A search that has finished, ready to pick from.
    private fun TestScope.doneWatch(source: FakeFind, asksFirst: Boolean): FindSongsWatch {
        val scope = TestScope(StandardTestDispatcher(testScheduler))
        val watch = FindSongsWatch(source, scope)
        watch.asksFirst = asksFirst
        watch.search("nd-1")
        scope.advanceTimeBy(FIND_POLL_MS * 3)
        assertEquals("done", watch.found.value!!.state)
        return watch
    }

    private val question = "This copy is MP3 320 and yours is FLAC, so it sounds worse. Replace yours anyway?"

    @Test
    fun anOlderServerIsNeverSentAnyway() = runTest {
        val source = FakeFind()
        source.answer = { PickResult("skipped", "Your copy is already FLAC, so nothing would be better.") }
        val watch = doneWatch(source, asksFirst = false)
        watch.pick("f1", FakeFind.copy)
        assertEquals(listOf<Boolean?>(null), source.anyways)
        assertNull(watch.question.value)
        assertEquals("Your copy is already FLAC, so nothing would be better.", watch.picked.value!!.detail)
        watch.close()
    }

    @Test
    fun aServerThatAsksFirstGetsAnywayFalse_AndItsQuestionWaits() = runTest {
        val source = FakeFind()
        source.answer = { PickResult("confirm", question) }
        val watch = doneWatch(source, asksFirst = true)
        val first = watch.pick("f1", FakeFind.copy)
        assertTrue(first.confirm)
        assertEquals(listOf<Boolean?>(false), source.anyways)
        assertEquals(PickQuestion("f1", FakeFind.copy, question, title = "Holocene"), watch.question.value)
        assertNull("A question is not a refusal", watch.picked.value)
        watch.close()
        assertNull(watch.question.value)
    }

    @Test
    fun replaceAnywaySendsTheSameCopyWithAnywayTrue() = runTest {
        val source = FakeFind()
        source.answer = { PickResult("confirm", question) }
        val watch = doneWatch(source, asksFirst = true)
        watch.pick("f1", FakeFind.copy)
        val asked = watch.question.value!!

        source.answer = { PickResult("queued", "Getting it.", "soulseek:x") }
        val result = watch.replaceAnyway(asked)!!
        assertTrue(result.queued)
        assertEquals(listOf("f1" to FakeFind.copy, "f1" to FakeFind.copy), source.picks)
        assertEquals(listOf<Boolean?>(false, true), source.anyways)
        assertNull(watch.question.value)
        assertEquals("soulseek:x", watch.picked.value!!.key)

        // Answered once: a second tap sends nothing.
        assertNull(watch.replaceAnyway(asked))
        assertEquals(2, source.picks.size)
        watch.close()
    }

    @Test
    fun keepMineSendsNothing() = runTest {
        val source = FakeFind()
        source.answer = { PickResult("confirm", "") }
        val watch = doneWatch(source, asksFirst = true)
        watch.pick("f1", FakeFind.copy)
        assertEquals("No words from the server: ours", REPLACE_ANYWAY_FALLBACK, watch.question.value!!.words)
        val asked = watch.question.value!!

        watch.keepMine()
        assertNull(watch.question.value)
        assertNull(watch.picked.value)
        assertEquals("f1", watch.found.value!!.id)
        assertNull("Kept: replacing is no longer on offer", watch.replaceAnyway(asked))
        assertEquals(1, source.picks.size)
        watch.close()
    }

    @Test
    fun aQuestionGoesWithItsSearch() = runTest {
        val source = FakeFind()
        source.answer = { PickResult("confirm", question) }
        val scope = TestScope(StandardTestDispatcher(testScheduler))
        val watch = FindSongsWatch(source, scope)
        watch.asksFirst = true
        watch.search("nd-1")
        scope.advanceTimeBy(FIND_POLL_MS * 3)
        watch.pick("f1", FakeFind.copy)
        val asked = watch.question.value!!

        watch.search("nd-1")
        scope.runCurrent()
        assertNull(watch.question.value)
        assertNull(watch.replaceAnyway(asked))
        assertEquals(1, source.picks.size)
        watch.close()
    }

    @Test
    fun nothingIsPickedWhileTheSearchRuns() = runTest {
        val source = FakeFind()
        val scope = TestScope(StandardTestDispatcher(testScheduler))
        val watch = FindSongsWatch(source, scope)
        watch.search("nd-1")
        scope.runCurrent()
        assertTrue(watch.found.value!!.searching)
        assertFalse(canPick(watch.found.value, FakeFind.copy))

        val picked = watch.pick("f1", FakeFind.copy)
        assertFalse(picked.queued)
        assertEquals(FIND_PICK_WAIT, picked.detail)
        assertTrue("The server is not asked", source.picks.isEmpty())

        scope.advanceTimeBy(FIND_POLL_MS * 3)
        assertTrue(canPick(watch.found.value, FakeFind.copy))
        assertFalse("A copy the server did not name", canPick(watch.found.value, FoundCandidate(source = "Soulseek")))
        watch.close()
    }

    @Test
    fun aPickFromAReplacedListIsRefused_AndALateAnswerStaysWithItsSearch() = runTest {
        val source = FakeFind()
        val scope = TestScope(StandardTestDispatcher(testScheduler))
        val watch = FindSongsWatch(source, scope)
        watch.search("nd-1")
        scope.advanceTimeBy(FIND_POLL_MS * 3)
        assertEquals("f1", watch.found.value!!.id)

        // Search again: the old list's copies are not picked from the new one.
        watch.search("nd-1")
        scope.advanceTimeBy(FIND_POLL_MS * 3)
        assertEquals("f2", watch.found.value!!.id)
        assertEquals(FIND_LIST_CHANGED, watch.pick("f1", FakeFind.copy).detail)
        assertTrue(source.picks.isEmpty())

        // A pick answered after another search began says nothing on the new one.
        source.answer = {
            watch.search("nd-1")
            PickResult("skipped", "That copy is gone.")
        }
        watch.pick("f2", FakeFind.copy)
        assertEquals(listOf("f2" to FakeFind.copy), source.picks)
        assertNull(watch.picked.value)
        watch.close()
    }

    @Test
    fun aSearchIsShownUntilClosedOrReplaced() = runTest {
        val source = FakeFind()
        val scope = TestScope(StandardTestDispatcher(testScheduler))
        val watch = FindSongsWatch(source, scope)
        watch.search("nd-1")
        scope.runCurrent()
        assertTrue(watch.showing("f1"))
        watch.search("nd-1")
        scope.runCurrent()
        assertFalse(watch.showing("f1"))
        assertTrue(watch.showing("f2"))
        watch.close()
        assertFalse(watch.showing("f2"))
    }

    @Test
    fun aCopysKeyIsItsIdOrItsPlace() {
        assertEquals("id:c1", copyKey(FoundCandidate(index = 0, id = "c1")))
        assertEquals("at:0", copyKey(FoundCandidate(index = 0)))
    }

    @Test
    fun thePillSpeaksForTheSongFurthestAlong() {
        val rows = listOf(
            rowOf(download("s:a", "queued", startedAt = "2026-10-04T17:50:00Z")),
            rowOf(download("s:b", "downloading", startedAt = "2026-10-04T17:52:00Z", progress = 0.42f)),
            rowOf(download("s:c", "downloading", startedAt = "2026-10-04T17:51:00Z", progress = 0.9f)),
            rowOf(download("s:d", "done")),
        )
        // Two at the same step: the one that started first, not the one further in.
        assertEquals("s:c", pillLead(rows)?.key)
        assertEquals("Downloading 90%", stepWords(pillLead(rows)!!))
        assertEquals("Downloading 90%, Song s:c. 2 more on the way", pillSpoken(rows))
        assertNull(pillLead(listOf(rowOf(download("s:d", "done")))))
        assertEquals("Checking", stepWords(rowOf(download("s:a", "verifying"))))
        assertEquals("Adding", stepWords(rowOf(download("s:a", "importing"))))
        assertEquals("Searching", stepWords(rowOf(download("s:a", "searching"))))
        assertEquals("Downloading", stepWords(rowOf(download("s:a", "downloading"))))
    }

    @Test
    fun eachPhaseSitsOnItsStep_AndAFailureStopsWhereItsLogGot() {
        assertEquals(0, stepOf(rowOf(download("s:a", "queued"))))
        assertEquals(1, stepOf(rowOf(download("s:a", "downloading"))))
        assertEquals(2, stepOf(rowOf(download("s:a", "verifying"))))
        assertEquals(3, stepOf(rowOf(download("s:a", "importing"))))
        assertEquals(DownloadStep.entries.size, stepOf(rowOf(download("s:a", "done"))))
        val failed = rowOf(download("s:a", "failed"))
        val log = listOf(
            AcquisitionEvent(kind = "search", text = "Looking"),
            AcquisitionEvent(kind = "transfer", text = "Downloading"),
            AcquisitionEvent(kind = "check", text = "Checking the file"),
            AcquisitionEvent(kind = "failed", text = "Wrong song"),
            AcquisitionEvent(kind = "note", text = "Gave up"),
        )
        assertEquals(DownloadStep.Check.ordinal, stepOf(failed, log))
        assertEquals(DownloadStep.Find.ordinal, stepOf(failed))
    }

    @Test
    fun aCopysBadgeTakesItsKind_AndTheFactsKeepTheRest() {
        val flac = FoundCandidate(source = "Soulseek", format = "flac", quality = "FLAC 16-bit 44.1 kHz", size = 36_100_000, length = 329, freeSlot = true)
        assertEquals("FLAC", copyBadge(flac))
        assertEquals(listOf("16-bit 44.1 kHz", "34.4 MB", "5:29", "Soulseek", "Free to send now"), badgeFacts(flac, Locale.ROOT))
        val plain = FoundCandidate(source = "Soulseek", format = "flac", quality = "FLAC")
        assertEquals(listOf("Soulseek"), badgeFacts(plain, Locale.ROOT))
        assertNull(copyBadge(FoundCandidate(source = "Lidarr")))
        assertEquals(listOf("1st choice", "2nd choice", "3rd choice", "4th choice", "11th choice", "22nd choice"), listOf(1, 2, 3, 4, 11, 22).map(::rankWords))
    }

    // ---------------------------------------------------------------------
    // Replacing a library song's copy
    // ---------------------------------------------------------------------

    private val compare = PickCompare(PickSide("FLAC", 420, "live recording"), PickSide("FLAC", 298, "the plain song"))

    @Test
    fun aBetterCopyIsAskedTheUsualWay_ThenSentOnceWithAnywayTrue() = runTest {
        val source = FakeFind()
        source.libraryId = "nd-1"
        source.answer = { PickResult("ready", null, null, compare) }
        val watch = doneWatch(source, asksFirst = true)
        watch.pick("f1", FakeFind.copy)
        val asked = watch.question.value!!
        assertEquals(AskKind.Ready, asked.kind)
        assertEquals(replaceQuestion(FakeFind.copy), asked.words)
        assertEquals("nd-1", asked.songId)
        assertEquals("Holocene", asked.title)
        assertEquals(listOf<Boolean?>(false), source.anyways)

        source.answer = { PickResult("queued", "Getting it.", null) }
        assertTrue(watch.replaceAnyway(asked)!!.queued)
        assertNull(watch.replaceAnyway(asked))
        assertEquals(listOf<Boolean?>(false, true), source.anyways)
        watch.close()
    }

    @Test
    fun aCopyThatNeedsAWordCarriesTheServersSentenceAndBothSides() = runTest {
        val source = FakeFind()
        source.libraryId = "nd-1"
        source.answer = { PickResult("confirm", "Yours looks like a live recording and this copy is the plain song. Replace yours anyway?", null, compare) }
        val watch = doneWatch(source, asksFirst = true)
        watch.pick("f1", FakeFind.copy)
        val asked = watch.question.value!!
        assertEquals(AskKind.Confirm, asked.kind)
        assertEquals("Yours looks like a live recording and this copy is the plain song. Replace yours anyway?", asked.words)
        assertEquals(listOf("Yours: FLAC, 7:00, live recording", "This copy: FLAC, 4:58, the plain song"), compareLines(asked.compare))
        watch.close()
    }

    @Test
    fun anOutsideSongIsPickedAtOnceEvenWhenTheServerAsksFirst() = runTest {
        val source = FakeFind()
        val watch = doneWatch(source, asksFirst = true)
        assertTrue(watch.pick("f1", FakeFind.copy).queued)
        assertNull(watch.question.value)
        assertEquals(listOf<Boolean?>(false), source.anyways)
        watch.close()
    }

    @Test
    fun aComparisonLeavesOutWhatIsMissing() {
        assertEquals(listOf("Yours: MP3 320", "This copy: 4:58, the plain song"), compareLines(PickCompare(PickSide("MP3 320", null, null), PickSide(null, 298, "the plain song"))))
        assertEquals(emptyList<String>(), compareLines(PickCompare(PickSide(), null)))
        assertEquals(emptyList<String>(), compareLines(null))
    }

    @Test
    fun aCopysTagAndTheTakeLine() {
        val same = FoundCandidate(source = "Soulseek", vsYours = "same", vsYoursText = "Same as yours")
        assertEquals("Same as yours", vsYoursTag(same))
        assertEquals("Compared with your copy: Same as yours", vsYoursSpoken(same))
        assertNull(vsYoursTag(FoundCandidate(source = "Soulseek")))
        assertEquals("Yours looks like a live recording. Pick the plain song to replace it.", takeLine(" Yours looks like a live recording. Pick the plain song to replace it. "))
        assertNull(takeLine(" "))
    }

    private fun replacing(plain: Boolean = true) = Replacing("nd-1", "Holocene", "f1", "id:c1", plainSong = plain)

    private fun job(state: String, at: String = "2026-10-11T12:05:00Z", detail: String? = null, id: String = "nd-1") =
        Upgrade(id = id, title = "Holocene", state = state, detail = detail, updatedAt = at)

    @Test
    fun aReplacementIsFollowedUntilItIsReplaced() {
        val all = Replacements()
        all.start(replacing(), emptyList())
        assertTrue(all.replacing("nd-1"))
        assertEquals("id:c1", all.of("f1", "id:c1")?.copyKey)

        // Not listed yet, then under way: still replacing.
        assertTrue(all.update(emptyList()).isEmpty())
        assertTrue(all.update(listOf(job("working"))).isEmpty())
        assertTrue(all.now.value["nd-1"]!!.seen)

        val ends = all.update(listOf(job("upgraded", detail = "Now FLAC.")))
        val end = ends.single() as ReplaceEnd.Replaced
        assertEquals("Replaced with the plain song", end.words)
        assertFalse(all.replacing("nd-1"))
        // Undo puts the old copy back by the song's id.
        assertEquals(LIBRARY_ACTION_RESTORE, end.putBack.action)
        assertEquals("nd-1", end.putBack.id)
        assertEquals(end.putBack, end.putBack.undo)
    }

    @Test
    fun aReplacementThatFailsSaysYourCopyWasKept_AndWhereToLook() {
        val all = Replacements()
        all.start(replacing(plain = false), emptyList())
        val end = all.update(listOf(job("failed", detail = "The copy you picked was not the right recording, so it was thrown away. Your copy was kept."))).single()
        assertTrue(end is ReplaceEnd.Kept)
        assertEquals(
            "The copy you picked was not the right recording, so it was thrown away. Your copy was kept. Details are in Downloads.",
            end.words,
        )
        assertEquals("Replaced with the copy you picked", replacedLine(plainSong = false))
        assertEquals("The copy you picked did not replace yours. Your copy was kept. Details are in Downloads.", keptLine(null))
    }

    @Test
    fun anOlderJobsEndIsNotThisReplacements() {
        val all = Replacements()
        val older = job("upgraded", at = "2026-10-10T12:00:00Z")
        all.start(replacing(), listOf(older))
        // Still the older job's end, and this one never seen under way.
        assertTrue(all.update(listOf(older)).isEmpty())
        assertTrue(all.replacing("nd-1"))
        // Another song's job says nothing about this one.
        assertTrue(all.update(listOf(older, job("failed", id = "nd-2"))).isEmpty())
        // A later end is this one's.
        assertTrue(all.update(listOf(job("failed", at = "2026-10-11T12:05:00Z", detail = "No copy came. Your copy was kept."))).single() is ReplaceEnd.Kept)
    }

    @Test
    fun theReplacingRowSaysTheStepThePillWould() {
        val r = replacing()
        val row = rowOf(Upgrade(id = "nd-1", title = "Holocene", state = "working", progress = 0.4))
        assertEquals(row, replacingRow(r, listOf(row)))
        assertEquals("Replacing... Searching", replacingWords(row))
        assertEquals("Replacing...", replacingWords(null))
        val downloading = rowOf(download("s:a", "downloading", progress = 0.42f), Upgrade(id = "nd-1", state = "working"))
        assertEquals("Replacing... Downloading 42%", replacingWords(replacingRow(r, listOf(downloading))))
    }
}
