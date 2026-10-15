package app.winters.octo.animated

// How long the still crossfades into the loop once its first frame is
// drawn, and back when the loop goes.
const val LOOP_FADE_MS = 450

// What a loop on screen does right now.
enum class LoopPlay {
    // Plays, muted and looping.
    Play,

    // Stops where it is: the frame it stopped on stays (the still, when it
    // never started).
    Hold,

    // Shows only the still: the loop is not even loaded.
    StillOnly,
}

// What a loop does: only the still with Reduce motion on; held while its
// view is not seen (screen off, app in the background, player closed, page
// covered) or while the device saves power; else it plays.
fun loopPlay(seen: Boolean, powerSave: Boolean, reduceMotion: Boolean): LoopPlay = when {
    reduceMotion -> LoopPlay.StillOnly
    !seen || powerSave -> LoopPlay.Hold
    else -> LoopPlay.Play
}

// The albums whose art to ask about when a song starts: its own, then the
// next songs' (each once, blanks left out).
fun albumsToAsk(playing: String?, next: List<String?>, ahead: Int = 1): List<String> =
    (listOf(playing) + next.take(ahead)).filterNotNull().filter(String::isNotBlank).distinct()
