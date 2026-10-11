package app.winters.octo.ui.downloads

import app.winters.octo.health.FixStep
import app.winters.octo.subsonic.FoundCandidate
import app.winters.octo.subsonic.PickCompare
import app.winters.octo.subsonic.PickSide
import app.winters.octo.subsonic.Upgrade
import app.winters.octo.subsonic.UpgradeStage
import java.time.Instant
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.update

// Replacing a library song's copy with one picked in Find songs, as both
// apps show it: the question before, the row while it runs, and the line
// once it ends, with Undo. The apps run the calls and draw; the words and
// what each answer means are here.

// The two questions a pick can come back with on a server that asks first.
enum class AskKind {
    // A better copy of the right song: the usual "Replace your copy?".
    Ready,

    // A copy that needs the person's word, in the server's own sentence.
    Confirm,
}

// The confirm's title, its two buttons, and the line a dialog opens with.
const val REPLACE_TITLE = "Replace your copy?"
const val REPLACE_ANYWAY = "Replace anyway"
const val KEEP_MINE = "Keep mine"

// What is asked when the server sends no words of its own.
const val REPLACE_ANYWAY_FALLBACK = "This copy is not better than yours. Replace yours anyway?"

// The usual question for a better copy, by its first facts.
fun replaceQuestion(copy: FoundCandidate): String =
    "Replace your copy with ${candidateFacts(copy).take(2).joinToString(", ")}?"

// One side of the comparison in a line: "Yours: FLAC, 7:00, live
// recording". Missing parts are left out, and a side with none is null.
fun compareLine(label: String, side: PickSide?): String? {
    val parts = listOfNotNull(
        side?.quality?.trim()?.takeIf(String::isNotEmpty),
        side?.length?.takeIf { it > 0 }?.let(::clockText),
        side?.take?.trim()?.takeIf(String::isNotEmpty),
    )
    return if (parts.isEmpty()) null else "$label: ${parts.joinToString(", ")}"
}

// Both lines of a comparison, the library's first.
fun compareLines(compare: PickCompare?): List<String> =
    listOfNotNull(compareLine("Yours", compare?.yours), compareLine("This copy", compare?.copy))

// The tag beside a copy's kind that says how it stands against the
// library's copy, and what a screen reader says for it.
fun vsYoursTag(copy: FoundCandidate): String? = copy.vsYoursText?.trim()?.takeIf(String::isNotEmpty)

fun vsYoursSpoken(copy: FoundCandidate): String? = vsYoursTag(copy)?.let { "Compared with your copy: $it" }

// The line a Find songs search shows over its copies when the library's
// copy looks like another take of the song.
fun takeLine(take: String?): String? = take?.trim()?.takeIf(String::isNotEmpty)

// A pick waiting for an answer. `words` is the whole question: the
// server's sentence for Confirm, the usual question for Ready. `songId` is
// the library song it would replace, and `title` names it.
data class PickQuestion(
    val search: String,
    val copy: FoundCandidate,
    val words: String,
    val kind: AskKind = AskKind.Confirm,
    val compare: PickCompare? = null,
    val songId: String? = null,
    val title: String = "",
)

// The take the server calls the plain song, which the line after names.
private const val PLAIN_SONG = "the plain song"

// A library song being replaced by a picked copy. `copyKey` and `search`
// name the copy's row on the list it was picked from.
data class Replacing(
    val songId: String,
    val title: String,
    val search: String,
    val copyKey: String,
    val plainSong: Boolean,
    // When the server last changed an older job for the song, as it was
    // listed when this one started; only a later end is this one's.
    val before: String? = null,
    // Seen on the server's list while still under way.
    val seen: Boolean = false,
) {
    companion object {
        fun of(question: PickQuestion): Replacing? {
            val songId = question.songId ?: return null
            val take = question.compare?.copy?.take?.trim()
            return Replacing(songId, question.title, question.search, copyKey(question.copy), take.equals(PLAIN_SONG, ignoreCase = true))
        }
    }
}

// How a replacement ended: the copy took the place of the library's, or
// the library's copy was kept, with the server's words why.
sealed interface ReplaceEnd {
    val replacing: Replacing
    val words: String

    data class Replaced(override val replacing: Replacing) : ReplaceEnd {
        override val words: String get() = replacedLine(replacing.plainSong)

        // What Undo sends: put back by the song's id, which swaps the old
        // copy in and leaves the newer one in Recently removed.
        val putBack: FixStep get() = FixStep.Restore(replacing.songId, replacing.title, replaced = true)
    }

    data class Kept(override val replacing: Replacing, val detail: String?) : ReplaceEnd {
        override val words: String get() = keptLine(detail)
    }
}

const val REPLACING = "Replacing..."
const val DETAILS_IN_DOWNLOADS = "Details are in Downloads."

fun replacedLine(plainSong: Boolean): String =
    if (plainSong) "Replaced with the plain song" else "Replaced with the copy you picked"

// The server's words for a replacement that did not happen, which already
// end "Your copy was kept.", and where to read more.
fun keptLine(detail: String?): String {
    val said = detail?.trim()?.takeIf(String::isNotEmpty)?.let { if (it.last() in ".!?") it else "$it." }
        ?: "The copy you picked did not replace yours. Your copy was kept."
    return "$said $DETAILS_IN_DOWNLOADS"
}

// The row under way for a replacement, when the drawer has one: the
// higher quality copy asked for the song, or its download.
fun replacingRow(replacing: Replacing, rows: List<DownloadRow>): DownloadRow? =
    rows.firstOrNull { it.findId == replacing.songId && !it.finished }

// What a replacing copy's row says: "Replacing... Downloading 42%", with
// the step the downloads pill would show for it.
fun replacingWords(row: DownloadRow?): String = row?.let { "$REPLACING ${stepWords(it)}" } ?: REPLACING

// The replacements under way on one server, by library song, followed
// through the server's list of higher quality copies (getUpgrades), which
// lists a forced pick under the song's id too.
class Replacements {
    private val _now = MutableStateFlow<Map<String, Replacing>>(emptyMap())
    val now: StateFlow<Map<String, Replacing>> = _now

    // Follows one from now; `upgrades` is the server's list as last read,
    // whose older jobs for the song are not this one's end.
    fun start(replacing: Replacing, upgrades: List<Upgrade>) {
        val before = upgrades.filter { it.id == replacing.songId }.maxOfOrNull { it.updatedAt.orEmpty() }?.ifEmpty { null }
        _now.update { it + (replacing.songId to replacing.copy(before = before)) }
    }

    // The one replacing the copy `copyKey` on the list `search`, if any.
    fun of(search: String?, copyKey: String): Replacing? =
        _now.value.values.firstOrNull { it.search == search && it.copyKey == copyKey }

    // Whether this library song is being replaced.
    fun replacing(songId: String?): Boolean = songId != null && songId in _now.value

    // Reads the server's list, and answers the replacements that ended
    // there, which are let go. An end no later than the newest job listed
    // when one started is that older job's, unless this one was seen under
    // way first.
    fun update(upgrades: List<Upgrade>): List<ReplaceEnd> {
        val ends = ArrayList<ReplaceEnd>()
        _now.update { now ->
            ends.clear()
            now.mapNotNull { (id, replacing) ->
                val entries = upgrades.filter { it.id == id }
                if (entries.any { it.stage.pending }) return@mapNotNull id to replacing.copy(seen = true)
                val last = entries.maxByOrNull { it.updatedAt.orEmpty() } ?: return@mapNotNull id to replacing
                val fresh = replacing.seen || replacing.before == null || later(last.updatedAt, replacing.before)
                val end = if (!fresh) {
                    null
                } else {
                    when (last.stage) {
                        UpgradeStage.Upgraded -> ReplaceEnd.Replaced(replacing)
                        UpgradeStage.NotFound, UpgradeStage.Failed, UpgradeStage.Skipped, UpgradeStage.Rehearsed -> ReplaceEnd.Kept(replacing, last.detail)
                        else -> null
                    }
                }
                if (end == null) {
                    id to replacing
                } else {
                    ends += end
                    null
                }
            }.toMap()
        }
        return ends
    }

    fun clear() {
        _now.value = emptyMap()
    }
}

// Whether the server's time `at` comes after `than`, read as instants, or
// as text when either is not one.
private fun later(at: String?, than: String): Boolean {
    val a = at?.let { runCatching { Instant.parse(it) }.getOrNull() }
    val b = runCatching { Instant.parse(than) }.getOrNull()
    return if (a != null && b != null) a.isAfter(b) else at.orEmpty() > than
}
