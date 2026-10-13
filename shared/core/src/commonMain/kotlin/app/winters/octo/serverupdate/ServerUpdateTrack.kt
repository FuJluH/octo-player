package app.winters.octo.serverupdate

// What the apps know about updating the server, and what the panel shows
// from it. Every change comes through `read`, `started` or the listener's
// own choices, so the rules can be checked without a server.

// What asking the server gave.
sealed interface UpdateRead {
    data class Answered(val status: ServerUpdateStatus) : UpdateRead

    // The server does not offer this to this user: a listener's account, or
    // a server too old for it. The app then shows nothing.
    data object NotOffered : UpdateRead

    // No answer: away, restarting, or a connection that went nowhere.
    data object NoAnswer : UpdateRead
}

// What asking the server to update gave.
sealed interface UpdateStart {
    data class Started(val id: String?, val tag: String) : UpdateStart

    // Why it would not, in the server's own words where it gave them.
    data class Refused(val words: String) : UpdateStart
}

// The steps a run goes through, as the panel lists them.
enum class UpdateStep { Handed, Fetching, Bringing, Restarting }

// An update being followed until it ends: the release, the request this
// app made for it (if it made one), and the step it was last seen on.
// `quietSinceMs` is when the server stopped answering, during a restart.
data class UpdateWatch(
    val tag: String,
    val requestId: String? = null,
    val byThisApp: Boolean = false,
    val step: UpdateStep = UpdateStep.Handed,
    val mode: String? = null,
    val quietSinceMs: Long? = null,
)

// How an update followed here ended.
sealed interface UpdateOutcome {
    val tag: String

    data class Done(override val tag: String) : UpdateOutcome

    data class Failed(override val tag: String, val words: String) : UpdateOutcome

    // The server stopped answering during the restart and has not come back.
    data class NotBack(override val tag: String) : UpdateOutcome
}

data class UpdateTrack(
    // The server's last answer, or null when it gave none or does not offer this.
    val status: ServerUpdateStatus? = null,
    // The newest release the listener chose Later for, on this server.
    val dismissed: String? = null,
    val watch: UpdateWatch? = null,
    val outcome: UpdateOutcome? = null,
    // The request to update is on its way.
    val starting: Boolean = false,
    // Why the server would not start the update, until the next try.
    val startProblem: String? = null,
) {
    // Takes the server's answer, or its silence, at `nowMs`.
    fun read(result: UpdateRead, nowMs: Long): UpdateTrack = when (result) {
        is UpdateRead.Answered -> answered(result.status)
        UpdateRead.NotOffered -> if (watch != null) quiet(nowMs) else copy(status = null)
        UpdateRead.NoAnswer -> if (watch != null) quiet(nowMs) else this
    }

    // What the server said to the request to update.
    fun started(result: UpdateStart): UpdateTrack = when (result) {
        is UpdateStart.Started -> copy(
            starting = false,
            startProblem = null,
            outcome = null,
            watch = UpdateWatch(result.tag, result.id, byThisApp = true, mode = status?.helper?.mode),
        )
        is UpdateStart.Refused -> copy(starting = false, startProblem = result.words)
    }

    private fun answered(s: ServerUpdateStatus): UpdateTrack {
        val w = watch ?: return copy(status = s).followIfBusy(s)
        // The run for this release, by its request or its tag.
        val run = s.run?.takeIf { (w.requestId != null && it.id == w.requestId) || it.tag == w.tag }
        return when {
            s.running == w.tag || run?.state == RunState.DONE ->
                copy(status = s, watch = null, outcome = if (w.byThisApp) UpdateOutcome.Done(w.tag) else null)
            run?.state == RunState.FAILED ->
                copy(status = s, watch = null, outcome = UpdateOutcome.Failed(w.tag, run.error?.takeIf(String::isNotBlank) ?: STOPPED))
            w.requestId != null && s.unanswered == w.requestId ->
                copy(status = s, watch = null, outcome = UpdateOutcome.Failed(w.tag, HELPER_SILENT))
            s.busy -> {
                val active = s.run?.takeIf { it.active }
                // Another release's run under way is the one to follow.
                if (active?.tag != null && active.tag != w.tag) {
                    copy(status = s, watch = UpdateWatch(active.tag, active.id, mode = s.helper.mode, step = stepOf(active)))
                } else {
                    copy(status = s, watch = w.copy(step = active?.let(::stepOf) ?: UpdateStep.Handed, quietSinceMs = null, mode = s.helper.mode ?: w.mode))
                }
            }
            else -> copy(status = s, watch = null, outcome = UpdateOutcome.Failed(w.tag, stoppedEarly(s.running)))
        }
    }

    // Starts following a run the server says is under way, from any app or
    // the dashboard.
    private fun followIfBusy(s: ServerUpdateStatus): UpdateTrack {
        if (!s.busy) return this
        val active = s.run?.takeIf { it.active }
        val tag = active?.tag ?: s.latest?.tag ?: return this
        return copy(watch = UpdateWatch(tag, active?.id ?: s.pendingId, mode = s.helper.mode, step = active?.let(::stepOf) ?: UpdateStep.Handed))
    }

    // No answer while an update is under way: the server is restarting,
    // until it has been quiet too long.
    private fun quiet(nowMs: Long): UpdateTrack {
        val w = watch ?: return this
        val since = w.quietSinceMs ?: nowMs
        return if (nowMs - since >= RESTART_GRACE_MS) {
            copy(watch = null, outcome = UpdateOutcome.NotBack(w.tag))
        } else {
            copy(watch = w.copy(quietSinceMs = since, step = UpdateStep.Restarting))
        }
    }

    // The listener put the news away until a newer release.
    fun later(): UpdateTrack = copy(dismissed = status?.latest?.tag ?: dismissed)

    // The listener read how it ended.
    fun closeOutcome(): UpdateTrack = copy(outcome = null)

    // How long until asking again.
    val nextReadMs: Long get() = if (watch != null || starting) ACTIVE_READ_MS else IDLE_READ_MS
}

private fun stepOf(run: UpdateRun): UpdateStep = when (run.state) {
    RunState.FETCHING -> UpdateStep.Fetching
    RunState.BUILDING -> UpdateStep.Bringing
    RunState.RESTARTING -> UpdateStep.Restarting
    else -> UpdateStep.Handed
}

// How often to ask while an update is under way.
const val ACTIVE_READ_MS = 2_000L

// How often to ask otherwise. The server itself looks for releases every
// six hours, so asking more often learns nothing.
const val IDLE_READ_MS = 3 * 60 * 60 * 1_000L

// How long one question may take. A connection kept open to a server that
// has since restarted can hang with no answer; this drops it.
const val UPDATE_CALL_TIMEOUT_MS = 5_000L

// How long a server may stay quiet during a restart before the app says it
// has not come back.
const val RESTART_GRACE_MS = 15 * 60 * 1_000L

internal const val STOPPED = "The update stopped before it finished."

internal const val HELPER_SILENT =
    "The update helper on your server did not pick up the request. It may have stopped. Update from Octo's dashboard instead."

internal fun stoppedEarly(running: String) = "The update stopped before it finished. Your server still runs $running."

// What the panel shows.
sealed interface UpdatePanel {
    data object Hidden : UpdatePanel

    // A newer release is out.
    data class Available(
        val latest: ServerRelease,
        val running: String,
        val newer: List<ServerRelease>,
        val way: UpdateWay,
        val reinstallCommand: String,
        // Why the last try at this release stopped, when it did.
        val lastFailure: String?,
        val starting: Boolean,
        val problem: String?,
    ) : UpdatePanel

    data class Updating(val tag: String, val steps: List<StepLine>) : UpdatePanel

    data class Finished(val outcome: UpdateOutcome) : UpdatePanel
}

// How the server can be updated from here.
enum class UpdateWay {
    // Update now, through the helper.
    Now,

    // No helper on the host: from the dashboard instead.
    NoHelper,

    // The helper is too old and needs reinstalling first.
    HelperOutdated,
}

enum class StepState { Done, Now, Waiting }

data class StepLine(val words: String, val state: StepState)

fun panelOf(track: UpdateTrack): UpdatePanel {
    track.outcome?.let { return UpdatePanel.Finished(it) }
    track.watch?.let { w -> return UpdatePanel.Updating(w.tag, stepLines(w.step, w.mode)) }
    val s = track.status ?: return UpdatePanel.Hidden
    val latest = s.latest ?: return UpdatePanel.Hidden
    if (!s.updateAvailable) return UpdatePanel.Hidden
    if (track.dismissed != null && compareReleaseTags(latest.tag, track.dismissed) <= 0) return UpdatePanel.Hidden
    val way = when {
        !s.helper.installed -> UpdateWay.NoHelper
        s.helper.outdated -> UpdateWay.HelperOutdated
        else -> UpdateWay.Now
    }
    val failed = s.run?.takeIf { it.state == RunState.FAILED && it.tag == latest.tag }
    return UpdatePanel.Available(
        latest = latest,
        running = s.running,
        newer = s.newer.ifEmpty { listOf(latest) },
        way = way,
        reinstallCommand = s.reinstallCommand,
        lastFailure = failed?.let { it.error?.takeIf(String::isNotBlank) ?: STOPPED },
        starting = track.starting,
        problem = track.startProblem,
    )
}

// Whether the entry leading to the panel carries its small dot.
fun showsDot(track: UpdateTrack): Boolean = when (val panel = panelOf(track)) {
    UpdatePanel.Hidden -> false
    is UpdatePanel.Finished -> panel.outcome !is UpdateOutcome.Done
    else -> true
}

// "Octo 2026.10.13, up to date" for the server facts, when the server
// knows it runs the newest release.
fun upToDateLine(track: UpdateTrack): String? =
    track.status?.takeIf { it.standing == "current" && !it.updateAvailable && it.running.isNotBlank() }?.let { "Octo ${it.running}, up to date" }

private fun stepLines(now: UpdateStep, mode: String?): List<StepLine> = UpdateStep.entries.map { step ->
    StepLine(
        stepWords(step, mode),
        when {
            step.ordinal < now.ordinal -> StepState.Done
            step == now -> StepState.Now
            else -> StepState.Waiting
        },
    )
}

fun stepWords(step: UpdateStep, mode: String? = null): String = when (step) {
    UpdateStep.Handed -> "Handed to the update helper"
    UpdateStep.Fetching -> "Fetching the release"
    UpdateStep.Bringing -> if (mode == "build") "Building the new Octo" else "Pulling the new Octo"
    UpdateStep.Restarting -> "Restarting Octo"
}
