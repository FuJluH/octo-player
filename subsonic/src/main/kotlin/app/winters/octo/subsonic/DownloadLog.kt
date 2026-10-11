package app.winters.octo.subsonic

import kotlinx.serialization.Serializable

// The version of octoAcquisitions that adds each download's log, clearing
// finished downloads, and Find songs.
const val OCTO_DOWNLOAD_LOG_VERSION = 2

// What a download is for, as the server names it.
object AcquisitionKind {
    // A heart, a play or an album walk.
    const val DOWNLOAD = "download"

    // A higher quality copy of a song already in the library.
    const val UPGRADE = "upgrade"

    // The one copy someone picked from Find songs.
    const val PICK = "pick"
}

// What one line of a download's log is about. A kind this app does not
// know yet is drawn as a plain line.
enum class LogKind(val wire: String) {
    Queued("queued"),
    Search("search"),
    Found("found"),
    Try("try"),
    Transfer("transfer"),
    Check("check"),
    Tags("tags"),
    Cover("cover"),
    Lyrics("lyrics"),
    Library("library"),
    Done("done"),
    Failed("failed"),
    Note("note"),
    Unknown(""),
    ;

    companion object {
        fun of(text: String?): LogKind {
            val wire = text?.trim()?.lowercase().orEmpty()
            return entries.firstOrNull { it != Unknown && it.wire == wire } ?: Unknown
        }
    }
}

// One line of a download's log: when, what kind of step, the words, an
// optional second line, and the copies a search offered when the step is
// about them.
@Serializable
data class AcquisitionEvent(
    val at: String? = null,
    val kind: String = "",
    val text: String = "",
    val detail: String? = null,
    val candidate: List<FoundCandidate> = emptyList(),
) {
    val logKind: LogKind get() = LogKind.of(kind)
}

// One copy a source offered: in a download's log, and in Find songs. Any
// figure can be missing. `rank` is the server's order of preference among
// the copies it would try (1 is first), null for one it would pass over,
// and `note` says why it would.
@Serializable
data class FoundCandidate(
    // "Soulseek" or "Lidarr".
    val source: String = "",
    // Soulseek: the peer sharing it. Lidarr: the indexer.
    val peer: String? = null,
    // The file's own name, or a Lidarr release's title.
    val file: String? = null,
    val folder: String? = null,
    val title: String? = null,
    val album: String? = null,
    val format: String? = null,
    // "FLAC 16-bit 44.1 kHz", "MP3 320 kbps".
    val quality: String? = null,
    val bitRate: Int? = null,
    val bitDepth: Int? = null,
    val sampleRate: Int? = null,
    val size: Long? = null,
    // In seconds.
    val length: Int? = null,
    val queueLength: Int? = null,
    val freeSlot: Boolean? = null,
    // Bytes a second.
    val speed: Int? = null,
    val rank: Int? = null,
    val note: String? = null,
    // Its place on a Find songs list. A server older than copy ids takes
    // it back for a pick, once the search has finished.
    val index: Int? = null,
    // Its own id on a Find songs list, which picking it sends back. It
    // stays the same copy while the list still grows; older servers send
    // none.
    val id: String? = null,
)

// The song a Find songs search looks for, with the library's copy when
// there is one.
@Serializable
data class FoundSong(
    val artist: String = "",
    val title: String = "",
    val album: String? = null,
    val duration: Int? = null,
    val coverArt: String? = null,
    val libraryId: String? = null,
    val format: String? = null,
    val quality: String? = null,
    val size: Long? = null,
)

// How one source's look went.
@Serializable
data class FindSourceState(
    val name: String = "",
    // searching, done, failed or off.
    val state: String = "",
    val text: String? = null,
    val query: List<String> = emptyList(),
)

// A Find songs search as it stands: searching until every source answers.
@Serializable
data class FoundSongs(
    val id: String = "",
    val state: String = "",
    val error: String? = null,
    val startedAt: String? = null,
    val song: FoundSong = FoundSong(),
    val source: List<FindSourceState> = emptyList(),
    val candidate: List<FoundCandidate> = emptyList(),
) {
    val searching: Boolean get() = state == FIND_SEARCHING
}

const val FIND_SEARCHING = "searching"
const val FIND_DONE = "done"
const val FIND_FAILED = "failed"
const val FIND_OFF = "off"

// The states a pick answers with.
const val PICK_QUEUED = "queued"
const val PICK_SKIPPED = "skipped"

// From octoAcquisitions 3, for a pick sent with anyway=false: the copy is
// not better than the library's, and `detail` holds the whole question to
// ask before sending it again with anyway=true.
const val PICK_CONFIRM = "confirm"

// What picking a copy did: queued, with the downloads row to follow when
// there is one, skipped with the server's words why, or a question to
// confirm first.
@Serializable
data class PickResult(
    val state: String = "",
    val detail: String? = null,
    val key: String? = null,
) {
    val queued: Boolean get() = state == PICK_QUEUED

    val confirm: Boolean get() = state == PICK_CONFIRM
}

@Serializable
internal data class Cleared(val count: Int = 0)
