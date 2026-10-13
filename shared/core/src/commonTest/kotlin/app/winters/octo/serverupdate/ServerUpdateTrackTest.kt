package app.winters.octo.serverupdate

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

class ServerUpdateTrackTest {
    private fun release(tag: String, notes: String = "") = ServerRelease(tag = tag, name = tag, notes = notes, url = "https://github.com/winters27/octo/releases/tag/$tag")

    private fun status(
        running: String = "2026.10.11",
        newer: List<String> = listOf("2026.10.13"),
        helper: UpdateHelper = UpdateHelper(installed = true, version = "2", mode = "image", outdated = false),
        pending: Boolean = false,
        pendingId: String? = null,
        unanswered: String? = null,
        run: UpdateRun? = null,
        standing: String = if (newer.isEmpty()) "current" else "behind",
    ) = ServerUpdateStatus(
        enabled = true,
        repo = "winters27/octo",
        running = running,
        latest = newer.firstOrNull()?.let { release(it) } ?: release(running),
        newer = newer.map { release(it) },
        updateAvailable = newer.isNotEmpty(),
        standing = standing,
        helper = helper,
        reinstallCommand = "scripts/updater/install-updater.sh",
        pending = pending,
        pendingId = pendingId,
        unanswered = unanswered,
        run = run,
    )

    private fun answered(s: ServerUpdateStatus) = UpdateRead.Answered(s)

    private fun UpdateTrack.panel() = panelOf(this)

    @Test
    fun aNewerReleaseShowsThePanelWithUpdateNow() {
        val panel = UpdateTrack().read(answered(status()), 0).panel() as UpdatePanel.Available
        assertEquals("2026.10.13", panel.latest.tag)
        assertEquals(UpdateWay.Now, panel.way)
        assertEquals("Octo 2026.10.13 is out.", headline(panel))
        assertEquals("Your server runs 2026.10.11.", detail(panel))
    }

    @Test
    fun severalReleasesSayHowFarAhead() {
        val panel = UpdateTrack().read(answered(status(newer = listOf("2026.10.13", "2026.10.12", "2026.10.11.1"))), 0).panel() as UpdatePanel.Available
        assertEquals("Your server runs 2026.10.11. That is 3 releases ahead.", detail(panel))
        assertEquals(3, panel.newer.size)
    }

    @Test
    fun upToDateShowsNoPanelButAFactsLine() {
        val track = UpdateTrack().read(answered(status(running = "2026.10.13", newer = emptyList())), 0)
        assertEquals(UpdatePanel.Hidden, track.panel())
        assertFalse(showsDot(track))
        assertEquals("Octo 2026.10.13, up to date", upToDateLine(track))
    }

    @Test
    fun anUnknownStandingSaysNothingAboutBeingUpToDate() {
        val track = UpdateTrack().read(answered(status(running = "2026.10.13", newer = emptyList(), standing = "unknown")), 0)
        assertNull(upToDateLine(track))
    }

    @Test
    fun noHelperOffersTheDashboard() {
        val panel = UpdateTrack().read(answered(status(helper = UpdateHelper(installed = false))), 0).panel() as UpdatePanel.Available
        assertEquals(UpdateWay.NoHelper, panel.way)
        assertEquals("You can update it from Octo's dashboard.", wayWords(panel.way))
    }

    @Test
    fun anOutdatedHelperAsksForItToBeReinstalled() {
        val panel = UpdateTrack().read(answered(status(helper = UpdateHelper(installed = true, version = "1", outdated = true))), 0).panel() as UpdatePanel.Available
        assertEquals(UpdateWay.HelperOutdated, panel.way)
        assertEquals("scripts/updater/install-updater.sh", panel.reinstallCommand)
    }

    @Test
    fun aServerThatDoesNotOfferItShowsNothing() {
        val shown = UpdateTrack().read(answered(status()), 0)
        val track = shown.read(UpdateRead.NotOffered, 1)
        assertEquals(UpdatePanel.Hidden, track.panel())
        assertFalse(showsDot(track))
        assertEquals(UpdatePanel.Hidden, UpdateTrack().read(UpdateRead.NotOffered, 0).panel())
    }

    @Test
    fun noAnswerOutsideAnUpdateKeepsWhatWasKnown() {
        val shown = UpdateTrack().read(answered(status()), 0)
        assertEquals(shown, shown.read(UpdateRead.NoAnswer, 1))
        assertEquals(UpdatePanel.Hidden, UpdateTrack().read(UpdateRead.NoAnswer, 0).panel())
    }

    @Test
    fun laterHidesTheNewsUntilANewerRelease() {
        val dismissed = UpdateTrack().read(answered(status()), 0).later()
        assertEquals("2026.10.13", dismissed.dismissed)
        assertEquals(UpdatePanel.Hidden, dismissed.panel())
        assertFalse(showsDot(dismissed))
        // The same release asked about again stays put away.
        assertEquals(UpdatePanel.Hidden, dismissed.read(answered(status()), 1).panel())
        // A newer one brings it back.
        val newer = dismissed.read(answered(status(newer = listOf("2026.10.13.1", "2026.10.13"))), 2)
        assertTrue(newer.panel() is UpdatePanel.Available)
        assertTrue(showsDot(newer))
    }

    @Test
    fun laterNeverHidesAnUpdateUnderWay() {
        val track = UpdateTrack(dismissed = "2026.10.13")
            .read(answered(status(run = UpdateRun(id = "r1", tag = "2026.10.13", state = RunState.FETCHING))), 0)
        assertTrue(track.panel() is UpdatePanel.Updating)
    }

    @Test
    fun aStartedUpdateWalksThroughItsSteps() {
        val start = UpdateTrack().read(answered(status()), 0).started(UpdateStart.Started("r1", "2026.10.13"))
        assertEquals(ACTIVE_READ_MS, start.nextReadMs)
        fun steps(t: UpdateTrack) = (t.panel() as UpdatePanel.Updating).steps.map { it.state }

        assertEquals(listOf(StepState.Now, StepState.Waiting, StepState.Waiting, StepState.Waiting), steps(start))
        val pending = start.read(answered(status(pending = true, pendingId = "r1")), 1)
        assertEquals(listOf(StepState.Now, StepState.Waiting, StepState.Waiting, StepState.Waiting), steps(pending))
        val fetching = pending.read(answered(status(run = UpdateRun(id = "r1", tag = "2026.10.13", state = RunState.FETCHING))), 2)
        assertEquals(listOf(StepState.Done, StepState.Now, StepState.Waiting, StepState.Waiting), steps(fetching))
        val pulling = fetching.read(answered(status(run = UpdateRun(id = "r1", tag = "2026.10.13", state = RunState.BUILDING))), 3)
        assertEquals("Pulling the new Octo", (pulling.panel() as UpdatePanel.Updating).steps[2].words)
        val restarting = pulling.read(answered(status(run = UpdateRun(id = "r1", tag = "2026.10.13", state = RunState.RESTARTING))), 4)
        assertEquals(listOf(StepState.Done, StepState.Done, StepState.Done, StepState.Now), steps(restarting))
    }

    @Test
    fun aHelperThatBuildsSaysSo() {
        val track = UpdateTrack().read(answered(status(helper = UpdateHelper(installed = true, mode = "build"))), 0)
            .started(UpdateStart.Started("r1", "2026.10.13"))
        assertEquals("Building the new Octo", (track.panel() as UpdatePanel.Updating).steps[2].words)
    }

    @Test
    fun theUpdateIsDoneWhenTheServerRunsTheNewRelease() {
        val going = UpdateTrack().read(answered(status()), 0).started(UpdateStart.Started("r1", "2026.10.13"))
            .read(answered(status(run = UpdateRun(id = "r1", tag = "2026.10.13", state = RunState.RESTARTING))), 1)
        // The new release answers, its run still saying "restarting".
        val done = going.read(answered(status(running = "2026.10.13", newer = emptyList(), run = UpdateRun(id = "r1", tag = "2026.10.13", state = RunState.RESTARTING))), 2)
        assertEquals(UpdatePanel.Finished(UpdateOutcome.Done("2026.10.13")), done.panel())
        assertEquals("Your server now runs 2026.10.13.", outcomeTitle(UpdateOutcome.Done("2026.10.13")))
        assertNull(done.watch)
        assertEquals(IDLE_READ_MS, done.nextReadMs)
        // Closing it leaves nothing: the server is up to date.
        assertEquals(UpdatePanel.Hidden, done.closeOutcome().panel())
    }

    @Test
    fun theUpdateIsDoneWhenItsRunSaysSo() {
        val going = UpdateTrack().read(answered(status()), 0).started(UpdateStart.Started("r1", "2026.10.13"))
        val done = going.read(answered(status(run = UpdateRun(id = "r1", tag = "2026.10.13", state = RunState.DONE))), 1)
        assertEquals(UpdatePanel.Finished(UpdateOutcome.Done("2026.10.13")), done.panel())
    }

    @Test
    fun aFailedRunSaysWhyInTheServersWords() {
        val going = UpdateTrack().read(answered(status()), 0).started(UpdateStart.Started("r1", "2026.10.13"))
        val failed = going.read(answered(status(run = UpdateRun(id = "r1", tag = "2026.10.13", state = RunState.FAILED, error = "docker compose pull failed: no space left"))), 1)
        val outcome = (failed.panel() as UpdatePanel.Finished).outcome as UpdateOutcome.Failed
        assertEquals("docker compose pull failed: no space left", outcome.words)
        assertTrue(showsDot(failed))
        // Once read, the release is offered again, with the reason.
        val again = failed.closeOutcome().panel() as UpdatePanel.Available
        assertEquals("docker compose pull failed: no space left", again.lastFailure)
    }

    @Test
    fun aRequestTheHelperNeverPickedUpFails() {
        val going = UpdateTrack().read(answered(status()), 0).started(UpdateStart.Started("r1", "2026.10.13"))
            .read(answered(status(pending = true, pendingId = "r1")), 1)
        val silent = going.read(answered(status(unanswered = "r1")), 2)
        assertEquals(UpdateOutcome.Failed("2026.10.13", HELPER_SILENT), silent.outcome)
    }

    @Test
    fun aRunThatVanishesOnTheOldReleaseFails() {
        val going = UpdateTrack().read(answered(status()), 0).started(UpdateStart.Started("r1", "2026.10.13"))
        val gone = going.read(answered(status()), 1)
        assertEquals(UpdateOutcome.Failed("2026.10.13", stoppedEarly("2026.10.11")), gone.outcome)
    }

    @Test
    fun silenceDuringAnUpdateReadsAsRestartingForFifteenMinutes() {
        val going = UpdateTrack().read(answered(status()), 0).started(UpdateStart.Started("r1", "2026.10.13"))
            .read(answered(status(run = UpdateRun(id = "r1", tag = "2026.10.13", state = RunState.BUILDING))), 1_000)
        val quiet = going.read(UpdateRead.NoAnswer, 10_000)
        val updating = quiet.panel() as UpdatePanel.Updating
        assertEquals(StepState.Now, updating.steps.last().state)
        assertEquals("Restarting Octo", updating.steps.last().words)
        // A refusal while it restarts (a proxy, an old page) is silence too.
        val stillQuiet = quiet.read(UpdateRead.NotOffered, 10_000 + RESTART_GRACE_MS - 1)
        assertTrue(stillQuiet.panel() is UpdatePanel.Updating)
        val notBack = stillQuiet.read(UpdateRead.NoAnswer, 10_000 + RESTART_GRACE_MS)
        assertEquals(UpdatePanel.Finished(UpdateOutcome.NotBack("2026.10.13")), notBack.panel())
        assertTrue(showsDot(notBack))
    }

    @Test
    fun anAnswerResetsTheQuietClock() {
        val going = UpdateTrack().read(answered(status()), 0).started(UpdateStart.Started("r1", "2026.10.13"))
        val quiet = going.read(UpdateRead.NoAnswer, 0)
        val back = quiet.read(answered(status(run = UpdateRun(id = "r1", tag = "2026.10.13", state = RunState.RESTARTING))), RESTART_GRACE_MS - 10)
        val quietAgain = back.read(UpdateRead.NoAnswer, RESTART_GRACE_MS)
        assertTrue(quietAgain.panel() is UpdatePanel.Updating)
    }

    @Test
    fun anUpdateStartedElsewhereIsFollowedButItsEndIsNotAnnounced() {
        val track = UpdateTrack().read(answered(status(pending = true, pendingId = "d1")), 0)
        assertEquals("2026.10.13", (track.panel() as UpdatePanel.Updating).tag)
        val done = track.read(answered(status(running = "2026.10.13", newer = emptyList())), 1)
        assertEquals(UpdatePanel.Hidden, done.panel())
    }

    @Test
    fun aRefusalShowsTheServersWords() {
        val refused = UpdateTrack().read(answered(status()), 0).copy(starting = true)
            .started(UpdateStart.Refused("An update is already under way."))
        val panel = refused.panel() as UpdatePanel.Available
        assertEquals("An update is already under way.", panel.problem)
        assertFalse(panel.starting)
    }

    @Test
    fun updateNowIsOnlyPossibleWhenNothingStandsInTheWay() {
        assertTrue(status().canUpdate)
        assertFalse(status(helper = UpdateHelper(installed = false)).canUpdate)
        assertFalse(status(helper = UpdateHelper(installed = true, outdated = true)).canUpdate)
        assertFalse(status(pending = true).canUpdate)
        assertFalse(status(run = UpdateRun(id = "r", tag = "2026.10.13", state = RunState.FETCHING)).canUpdate)
        assertTrue(status(run = UpdateRun(id = "r", tag = "2026.10.12", state = RunState.DONE)).canUpdate)
        assertFalse(status(newer = emptyList()).canUpdate)
    }

    @Test
    fun anOldFinishedRunIsNotFollowed() {
        val track = UpdateTrack().read(answered(status(run = UpdateRun(id = "old", tag = "2026.10.11", state = RunState.DONE))), 0)
        assertNull(track.watch)
        assertTrue(track.panel() is UpdatePanel.Available)
    }
}
