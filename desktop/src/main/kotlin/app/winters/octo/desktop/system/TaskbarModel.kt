package app.winters.octo.desktop.system

import app.winters.octo.desktop.player.PlayProblem
import app.winters.octo.desktop.player.PlayerState

// What Octo's taskbar button shows on Windows: three buttons on its
// thumbnail and the song's progress across it, worked out from the player
// apart from the system so it can be checked without a window.

// Previous, play or pause, and next. `playing` puts pause in the middle,
// or Stop for a live station (`live`), which has no pause.
data class TaskbarButtons(
    val playing: Boolean,
    val previous: Boolean,
    val toggle: Boolean,
    val next: Boolean,
    val live: Boolean = false,
) {
    val previousTip: String get() = if (live) "Previous station" else "Previous"
    val toggleTip: String get() = if (!playing) "Play" else if (live) "Stop" else "Pause"
    val nextTip: String get() = if (live) "Next station" else "Next"
}

// How the progress shows, by the system library's numbers.
enum class TaskbarProgressKind(val code: Int) { None(0), Normal(1), Paused(2), Error(3) }

// The progress: how it shows, and how far into the song, in milliseconds.
data class TaskbarProgress(val kind: TaskbarProgressKind, val doneMs: Long = 0, val totalMs: Long = 0) {
    // How far along in thousandths, the finest step the bar can show.
    val thousandths: Int get() = if (totalMs <= 0) 0 else ((doneMs.coerceIn(0, totalMs) * 1000) / totalMs).toInt()
}

data class TaskbarView(val buttons: TaskbarButtons, val progress: TaskbarProgress)

private val NoProgress = TaskbarProgress(TaskbarProgressKind.None)

// The buttons and progress for the player as it is. With nothing in, the
// buttons are there but greyed out and there is no progress. A song paused
// at its very start (a queue brought back when Octo opened) shows none
// either, rather than a paused bar at nothing. `failing` shows the bar red.
fun taskbarViewOf(state: PlayerState, positionMs: Long, failing: Boolean = false): TaskbarView {
    val now = nowPlayingOf(state)
    val buttons = TaskbarButtons(
        playing = now?.playing == true,
        previous = now?.canPrevious == true,
        toggle = now != null,
        next = now?.canNext == true,
        live = now?.live == true,
    )
    val length = now?.durationMs ?: 0
    val progress = when {
        now == null -> NoProgress
        failing -> TaskbarProgress(TaskbarProgressKind.Error, positionMs, length.coerceAtLeast(1))
        length <= 0 -> NoProgress
        now.playing -> TaskbarProgress(TaskbarProgressKind.Normal, positionMs, length)
        positionMs > 0 -> TaskbarProgress(TaskbarProgressKind.Paused, positionMs, length)
        else -> NoProgress
    }
    return TaskbarView(buttons, progress)
}

// Keeps the bar red for a moment after a song could not play. Each new
// problem starts the moment again.
class TaskbarFailures(private val showMs: Long = FAILURE_SHOWN_MS) {
    private var last: PlayProblem? = null
    private var until = Long.MIN_VALUE

    fun failing(problem: PlayProblem?, now: Long): Boolean {
        if (problem != null && problem !== last) until = now + showMs
        last = problem
        return now < until
    }

    // Whether the red from the last failure is still up, without taking a
    // new one in.
    fun showing(now: Long): Boolean = now < until

    companion object {
        const val FAILURE_SHOWN_MS = 3_000L
    }
}

// What to hand the taskbar now, so it is told little: the buttons only
// when they change, the progress at once when the way it shows changes,
// and otherwise its place at most every `gapMs`, and only once it has moved
// a step the bar can show.
class TaskbarThrottle(private val gapMs: Long = PROGRESS_GAP_MS) {
    private var buttons: TaskbarButtons? = null
    private var progress: TaskbarProgress? = null
    private var progressAt = Long.MIN_VALUE

    // Null for anything that need not be sent.
    fun next(view: TaskbarView, now: Long): Pair<TaskbarButtons?, TaskbarProgress?> {
        val newButtons = view.buttons.takeIf { it != buttons }
        val sent = progress
        val newProgress = view.progress.takeIf { wanted ->
            when {
                sent == null || sent.kind != wanted.kind || sent.totalMs != wanted.totalMs -> true
                wanted.kind == TaskbarProgressKind.None -> false
                wanted.thousandths == sent.thousandths -> false
                else -> now - progressAt >= gapMs
            }
        }
        if (newButtons != null) buttons = newButtons
        if (newProgress != null) {
            progress = newProgress
            progressAt = now
        }
        return newButtons to newProgress
    }

    companion object {
        // A few updates a second at most.
        const val PROGRESS_GAP_MS = 500L
    }
}
