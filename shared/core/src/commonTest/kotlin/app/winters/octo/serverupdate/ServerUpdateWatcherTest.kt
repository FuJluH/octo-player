package app.winters.octo.serverupdate

import kotlinx.coroutines.ExperimentalCoroutinesApi
import kotlinx.coroutines.test.TestScope
import kotlinx.coroutines.test.advanceTimeBy
import kotlinx.coroutines.test.runCurrent
import kotlinx.coroutines.test.runTest
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

@OptIn(ExperimentalCoroutinesApi::class)
class ServerUpdateWatcherTest {
    private fun release(tag: String) = ServerRelease(tag = tag)

    private fun behind(run: UpdateRun? = null, pending: Boolean = false) = ServerUpdateStatus(
        running = "2026.10.11",
        latest = release("2026.10.13"),
        newer = listOf(release("2026.10.13")),
        updateAvailable = true,
        standing = "behind",
        helper = UpdateHelper(installed = true, mode = "image"),
        run = run,
        pending = pending,
        pendingId = if (pending) "r1" else null,
    )

    private val current = ServerUpdateStatus(running = "2026.10.13", latest = release("2026.10.13"), standing = "current")

    // A pretend server: answers from a list, the last one repeated.
    private class Calls(var answers: MutableList<UpdateRead>) : ServerUpdateCalls {
        var reads = 0
        val starts = mutableListOf<String>()
        var startAnswer: UpdateStart = UpdateStart.Started("r1", "2026.10.13")

        override suspend fun read(): UpdateRead {
            reads++
            return if (answers.size > 1) answers.removeAt(0) else answers.first()
        }

        override suspend fun start(tag: String): UpdateStart {
            starts += tag
            return startAnswer
        }
    }

    private class Memory : LaterStore {
        val kept = HashMap<String, String>()

        override suspend fun dismissed(server: String): String? = kept[server]

        override suspend fun dismiss(server: String, tag: String) {
            kept[server] = tag
        }
    }

    private fun TestScope.watcher(later: LaterStore = Memory(), finished: () -> Unit = {}) =
        ServerUpdateWatcher(backgroundScope, later, now = { testScheduler.currentTime }, onFinished = { finished() })

    @Test
    fun asksOnceThenEveryFewHours() = runTest {
        val calls = Calls(mutableListOf(UpdateRead.Answered(behind())))
        val watcher = watcher()
        watcher.bind("home", calls)
        runCurrent()
        assertEquals(1, calls.reads)
        assertTrue(panelOf(watcher.track.value) is UpdatePanel.Available)
        advanceTimeBy(IDLE_READ_MS - 1)
        assertEquals(1, calls.reads)
        advanceTimeBy(2)
        assertEquals(2, calls.reads)
    }

    @Test
    fun refreshAsksAtOnce() = runTest {
        val calls = Calls(mutableListOf(UpdateRead.Answered(behind())))
        val watcher = watcher()
        watcher.bind("home", calls)
        runCurrent()
        watcher.refresh()
        runCurrent()
        assertEquals(2, calls.reads)
    }

    @Test
    fun followsAnUpdateEveryTwoSecondsUntilTheNewReleaseAnswers() = runTest {
        var finished = 0
        val calls = Calls(mutableListOf(UpdateRead.Answered(behind())))
        val watcher = watcher(finished = { finished++ })
        watcher.bind("home", calls)
        runCurrent()
        calls.answers = mutableListOf(
            UpdateRead.Answered(behind(pending = true)),
            UpdateRead.Answered(behind(UpdateRun(id = "r1", tag = "2026.10.13", state = RunState.FETCHING))),
            UpdateRead.Answered(behind(UpdateRun(id = "r1", tag = "2026.10.13", state = RunState.RESTARTING))),
            UpdateRead.NoAnswer,
            UpdateRead.NoAnswer,
            UpdateRead.Answered(current),
        )
        watcher.updateNow()
        runCurrent()
        assertEquals(listOf("2026.10.13"), calls.starts)
        assertTrue(panelOf(watcher.track.value) is UpdatePanel.Updating)
        val before = calls.reads
        advanceTimeBy(ACTIVE_READ_MS * 5 + 1)
        assertEquals(before + 5, calls.reads)
        assertEquals(UpdatePanel.Finished(UpdateOutcome.Done("2026.10.13")), panelOf(watcher.track.value))
        assertEquals(1, finished)
        // Back to the slow pace.
        advanceTimeBy(ACTIVE_READ_MS * 3)
        assertEquals(before + 5, calls.reads)
    }

    @Test
    fun aRefusedStartSaysWhy() = runTest {
        val calls = Calls(mutableListOf(UpdateRead.Answered(behind())))
        calls.startAnswer = UpdateStart.Refused("An update is already under way.")
        val watcher = watcher()
        watcher.bind("home", calls)
        runCurrent()
        watcher.updateNow()
        runCurrent()
        assertEquals("An update is already under way.", (panelOf(watcher.track.value) as UpdatePanel.Available).problem)
    }

    @Test
    fun updateNowDoesNothingWithoutAHelper() = runTest {
        val calls = Calls(mutableListOf(UpdateRead.Answered(behind().copy(helper = UpdateHelper(installed = false)))))
        val watcher = watcher()
        watcher.bind("home", calls)
        runCurrent()
        watcher.updateNow()
        runCurrent()
        assertTrue(calls.starts.isEmpty())
    }

    @Test
    fun laterIsKeptPerServer() = runTest {
        val memory = Memory()
        val home = Calls(mutableListOf(UpdateRead.Answered(behind())))
        val work = Calls(mutableListOf(UpdateRead.Answered(behind())))
        val watcher = watcher(memory)
        watcher.bind("home", home)
        runCurrent()
        watcher.later()
        runCurrent()
        assertEquals("2026.10.13", memory.kept["home"])
        assertEquals(UpdatePanel.Hidden, panelOf(watcher.track.value))
        // Another server still shows its news.
        watcher.bind("work", work)
        runCurrent()
        assertTrue(panelOf(watcher.track.value) is UpdatePanel.Available)
        // Back on the first, it stays put away.
        watcher.bind("home", Calls(mutableListOf(UpdateRead.Answered(behind()))))
        runCurrent()
        assertEquals(UpdatePanel.Hidden, panelOf(watcher.track.value))
    }

    @Test
    fun noServerShowsNothingAndAsksNothing() = runTest {
        val calls = Calls(mutableListOf(UpdateRead.Answered(behind())))
        val watcher = watcher()
        watcher.bind("home", calls)
        runCurrent()
        watcher.bind(null, null)
        runCurrent()
        assertEquals(UpdatePanel.Hidden, panelOf(watcher.track.value))
        assertNull(watcher.track.value.status)
        advanceTimeBy(IDLE_READ_MS * 2)
        assertEquals(1, calls.reads)
    }
}
