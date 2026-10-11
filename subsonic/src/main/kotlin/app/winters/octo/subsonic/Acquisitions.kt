package app.winters.octo.subsonic

import kotlinx.serialization.Serializable

// The OpenSubsonic extension an Octo server lists when it can say how the
// downloads it was asked for are going. Version 2 adds each download's log,
// clearing finished ones, and Find songs. Version 3 lets a picked copy that
// is not better than the library's ask first and replace it anyway.
const val OCTO_ACQUISITIONS = "octoAcquisitions"

// The version of octoAcquisitions whose pickFoundSong takes `anyway` and may
// answer PICK_CONFIRM with the question to ask.
const val OCTO_REPLACE_ANYWAY_VERSION = 3

// Where one download on the server has got to.
enum class AcquisitionStage(val wire: String) {
    Queued("queued"),
    Searching("searching"),
    Downloading("downloading"),
    Verifying("verifying"),
    Importing("importing"),
    Done("done"),
    Failed("failed"),

    // A stage this app does not know yet, from a newer server.
    Unknown("");

    companion object {
        fun of(text: String?): AcquisitionStage {
            val wire = text?.trim()?.lowercase().orEmpty()
            return entries.firstOrNull { it != Unknown && it.wire == wire } ?: Unknown
        }
    }
}

// One song the server is downloading for the signed-in user. Any field can
// be missing, and finished ones stay listed for a while.
@Serializable
data class Acquisition(
    // The id that was starred: a find's id without its "find:".
    val id: String = "",
    val artist: String = "",
    val title: String = "",
    val album: String? = null,
    // As the server says it; `stage` is what it means.
    val state: String = "",
    // How far along, from 0 to 1, when the server knows.
    val progress: Float? = null,
    val bytesDone: Long? = null,
    val bytesTotal: Long? = null,
    // Where the file is coming from, in words.
    val source: String? = null,
    val startedAt: String? = null,
    val updatedAt: String? = null,
    // Why it failed, in words.
    val error: String? = null,
    // The song's id in the library once it is there, when the server knows it.
    val libraryId: String? = null,
    // How many downloads are ahead of a queued one.
    val ahead: Int? = null,
    // A short line about where it is, such as which source it tries now.
    val note: String? = null,
    // From version 2 on: the row's own key for its log, what it is for
    // (AcquisitionKind), the copy being fetched and its peer, the picture
    // to draw, and how many lines its log has.
    val key: String? = null,
    val kind: String? = null,
    val quality: String? = null,
    val peer: String? = null,
    val coverArt: String? = null,
    val logLines: Int = 0,
    // The log, oldest first; only getAcquisition sends it.
    val event: List<AcquisitionEvent> = emptyList(),
) {
    val stage: AcquisitionStage get() = AcquisitionStage.of(state)

    // How far along, kept between 0 and 1, or null when unknown.
    val fraction: Float?
        get() = progress?.takeIf { it.isFinite() }?.coerceIn(0f, 1f)
            ?: bytesDone?.let { done -> bytesTotal?.takeIf { it > 0 }?.let { (done.toFloat() / it).coerceIn(0f, 1f) } }
}

@Serializable
internal data class Acquisitions(val acquisition: List<Acquisition> = emptyList())

// Whether a server lists an extension at this version.
fun List<Extension>.lists(name: String, version: Int = 1): Boolean = any { it.name == name && version in it.versions }
