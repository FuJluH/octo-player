package app.winters.octo.subsonic

import kotlinx.serialization.Serializable

// The OpenSubsonic extension an Octo server lists when it imports lists:
// the signed-in user's imported lists with what the library has of each,
// and the trickle that fetches the rest. The field names below are the
// server's, so they decode by name, and fields the apps do not read are
// left out.
const val OCTO_IMPORTS = "octoImports"

// The octoImports version that adds the services list and file and text
// imports: getImportServices, importFile and importText.
const val OCTO_IMPORTS_FILES = 2

// The largest file importFile takes.
const val IMPORT_FILE_MAX_BYTES = 64L * 1024 * 1024

// The services a person can bring their music from.
@Serializable
data class ImportServices(
    val services: List<ImportServiceLink> = emptyList(),
)

// One service: its name, the page that exports its lists to a file, and
// the words on that page's tile for it, since the page does not pick the
// service by itself.
@Serializable
data class ImportServiceLink(
    val id: String = "",
    val name: String = "",
    val exportUrl: String = "",
    val tile: String = "",
)

// Everything the import view shows for the signed-in user.
@Serializable
data class ImportOverview(
    val lists: List<ImportListSummary> = emptyList(),
    val trickle: TrickleStatus = TrickleStatus(),
    // Why the server cannot tell which songs the library has, when it cannot.
    // Nothing is fetched until it can.
    val libraryProblem: String? = null,
    // Set only for a family member whose missing songs wait for approval.
    val approval: ImportApproval? = null,
)

// Who approves a family member's downloads before Octo fetches them.
@Serializable
data class ImportApproval(
    val needed: Boolean = false,
    // The approver's name; blank when the server has none.
    val by: String? = null,
)

// Where a list came from.
enum class ImportSource(val wire: String) {
    SpotifyLiked("spotifyLiked"),
    SpotifyPlaylist("spotifyPlaylist"),
    Link("link"),
    File("file"),
    Unknown(""),
    ;

    // Liked songs or a playlist read through a Spotify account sign-in: it
    // stays as it was last read and no longer updates.
    val fromSignIn: Boolean get() = this == SpotifyLiked || this == SpotifyPlaylist

    companion object {
        fun of(text: String?): ImportSource = entries.firstOrNull { it != Unknown && it.wire == text } ?: Unknown
    }
}

@Serializable
data class ImportListSummary(
    val id: String = "",
    val name: String = "",
    val source: String = "",
    // Who made it on Spotify, when someone else did.
    val by: String? = null,
    val imageUrl: String? = null,
    val total: Int = 0,
    val have: Int = 0,
    val missing: Int = 0,
    val queued: Int = 0,
    val downloading: Int = 0,
    val done: Int = 0,
    val notFound: Int = 0,
    val skipped: Int = 0,
    // Kept as a Navidrome playlist of the songs the library has.
    val keepPlaylist: Boolean = false,
    val playlistId: String? = null,
    val playlistNote: String? = null,
    // Its missing songs, and songs added to it later, go to the trickle.
    val getMissing: Boolean = false,
    // Why only part of it could be read, in the server's words.
    val partial: String? = null,
    // It can be read again from where it came from.
    val canRefresh: Boolean = false,
    val readUtc: String? = null,
    val matchedUtc: String? = null,
) {
    val origin: ImportSource get() = ImportSource.of(source)

    // It can be read again from where it came from: a link or a file, never
    // a list from a Spotify account sign-in.
    val readsAgain: Boolean get() = canRefresh && !origin.fromSignIn

    // How much of it the library has, 0 to 1.
    val fraction: Float get() = if (total <= 0) 0f else (have.toFloat() / total).coerceIn(0f, 1f)

    // Songs on their way: waiting in the trickle or being fetched.
    val coming: Int get() = queued + downloading
}

// Where one song of a list stands.
enum class ImportTrackState(val wire: String) {
    // In the library already.
    Have("have"),

    // Not in the library, and nobody asked for it yet.
    Missing("missing"),
    Queued("queued"),
    Downloading("downloading"),

    // Fetched; it shows as Have once the library lists it.
    Done("done"),
    NotFound("notFound"),
    Skipped("skipped"),

    // A state this app does not know yet, from a newer server.
    Unknown(""),
    ;

    // Can be asked for: it is not there and nothing is fetching it.
    val askable: Boolean get() = this == Missing || this == NotFound || this == Skipped

    companion object {
        fun of(text: String?): ImportTrackState = entries.firstOrNull { it != Unknown && it.wire == text } ?: Unknown
    }
}

@Serializable
data class ImportTrack(
    // The same song in every list; what songs and skips are asked by.
    val key: String = "",
    val title: String = "",
    val artist: String = "",
    val album: String? = null,
    val seconds: Int? = null,
    val state: String = "",
    // What it is waiting for, or what happened, in the server's words.
    val detail: String? = null,
    // The library's song, once there is one.
    val libraryId: String? = null,
    // 0 to 1 while it downloads.
    val progress: Double? = null,
    val updatedUtc: String? = null,
) {
    val stage: ImportTrackState get() = ImportTrackState.of(state)
}

@Serializable
data class ImportListDetail(
    val list: ImportListSummary = ImportListSummary(),
    val tracks: List<ImportTrack> = emptyList(),
)

// What the trickle is doing for the signed-in user.
enum class TrickleState(val wire: String) {
    // Nothing to fetch.
    Idle("idle"),

    // Fetching, or waiting for its next turn.
    Running("running"),
    Paused("paused"),

    // Songs an hour is 0 on the server.
    Off("off"),

    // Someone's own downloads come first.
    Yielding("yielding"),
    WaitingForSoulseek("waitingForSoulseek"),
    Unknown(""),
    ;

    companion object {
        fun of(text: String?): TrickleState = entries.firstOrNull { it != Unknown && it.wire == text } ?: Unknown
    }
}

@Serializable
data class TrickleStatus(
    val state: String = "",
    // When the next song starts.
    val nextUtc: String? = null,
    val perHour: Int = 0,
    val queued: Int = 0,
    val downloading: Int = 0,
    val done: Int = 0,
    val notFound: Int = 0,
    val skipped: Int = 0,
    // The song being fetched now.
    val current: ImportTrack? = null,
    // The songs that finished last, newest first.
    val recent: List<ImportTrack> = emptyList(),
    // The next few songs in line.
    val next: List<ImportTrack> = emptyList(),
) {
    val stage: TrickleState get() = TrickleState.of(state)
}

// What one import action did, in the server's words.
@Serializable
data class ImportAnswer(
    val ok: Boolean = false,
    val message: String = "",
    // The list a link or file became.
    val listId: String? = null,
    val count: Int = 0,
)

// The actions importAction knows.
object ImportActions {
    const val ADD_LINK = "addLink"
    const val PLAYLIST = "playlist"
    const val FETCH = "fetch"
    const val SONGS = "songs"
    const val REFRESH = "refresh"
    const val REMOVE = "remove"
    const val PAUSE = "pause"
    const val RESUME = "resume"
    const val RETRY = "retry"
    const val SKIP = "skip"
    const val CLEAR = "clear"
}
