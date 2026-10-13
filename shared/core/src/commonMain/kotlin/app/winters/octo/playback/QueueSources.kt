package app.winters.octo.playback

// Where each song in the queue came from, so the queue can show the
// listener's own picks apart from the list they were playing: "Next from
// you", then "Next from OK Computer". The phone and the desktop both keep
// one per queue entry and cut the songs to come into runs by it.
sealed interface QueueSource {
    // The listener put it in: Play next, Add to queue, or dropped in.
    data object You : QueueSource

    // Part of a list that was played: an album, a playlist, the songs, a
    // radio. `name` is how the queue shows it, or null for a list with no
    // name worth showing.
    data class Played(val name: String?) : QueueSource

    // Added by Autoplay once the listener's own queue ran out.
    data object Autoplay : QueueSource

    // A station the server runs, by its id and name. A station never ends:
    // as its songs run low, more of its kind are added under the same name.
    data class Station(val id: String, val name: String) : QueueSource
}

// A played list with no name.
val NoSource: QueueSource = QueueSource.Played(null)

// The heading over a run of songs to come from one source.
fun queueSourceTitle(source: QueueSource): String = when (source) {
    QueueSource.You -> "Next from you"
    QueueSource.Autoplay -> "Next from Autoplay"
    is QueueSource.Played -> source.name?.let { "Next from $it" } ?: "Up next"
    is QueueSource.Station -> "Next from ${source.name}"
}

// The songs to come cut into runs of one source each, in the order they
// play. Songs from one source that are apart stay in runs of their own.
fun <T> sourceRuns(items: List<T>, sourceOf: (T) -> QueueSource): List<Pair<QueueSource, List<T>>> {
    val runs = mutableListOf<Pair<QueueSource, MutableList<T>>>()
    items.forEach { item ->
        val source = sourceOf(item)
        val last = runs.lastOrNull()
        if (last != null && last.first == source) last.second += item else runs += source to mutableListOf(item)
    }
    return runs
}

// The source a song takes once moved (or dropped) among the songs to come,
// between `before` and `after` (null at either end): inside a run it joins
// that run, so a song dragged in among the listener's own becomes theirs;
// at the edge between two runs it keeps its own. It never becomes
// Autoplay's, so a song of the listener's moved past Autoplay's stays
// theirs.
fun movedSource(own: QueueSource, before: QueueSource?, after: QueueSource?): QueueSource {
    val joined = when {
        before != null && after != null -> if (before == after) before else own
        before != null -> before
        after != null -> after
        else -> own
    }
    return if (joined == QueueSource.Autoplay && own != QueueSource.Autoplay) own else joined
}

// A source as a short word, for saving a queue and for the phone's queue
// entries: "you", "autoplay", "list", "list:<name>" or
// "station:<id>:<name>".
fun QueueSource.encoded(): String = when (this) {
    QueueSource.You -> "you"
    QueueSource.Autoplay -> "autoplay"
    is QueueSource.Played -> if (name == null) "list" else "list:$name"
    is QueueSource.Station -> "station:$id:$name"
}

// The source a saved word stands for; an unknown or missing one is a list
// with no name.
fun queueSourceOf(word: String?): QueueSource = when {
    word == "you" -> QueueSource.You
    word == "autoplay" -> QueueSource.Autoplay
    word != null && word.startsWith("list:") -> QueueSource.Played(word.removePrefix("list:").ifEmpty { null })
    word != null && word.startsWith("station:") -> stationSourceOf(word.removePrefix("station:"))
    else -> NoSource
}

// "<id>:<name>" as a station; an id is never empty and holds no colon, a
// name may.
private fun stationSourceOf(rest: String): QueueSource {
    val id = rest.substringBefore(':', "")
    return if (id.isEmpty()) NoSource else QueueSource.Station(id, rest.substringAfter(':'))
}
