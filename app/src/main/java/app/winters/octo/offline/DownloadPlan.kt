package app.winters.octo.offline

// Why a download is kept: asked for by hand, a liked song while Liked songs
// are kept, or a song of a playlist that is kept. Saved in one column,
// comma separated; playlist ids never hold a comma.
object Reasons {
    const val MANUAL = "manual"
    const val LIKED = "liked"
    private const val PLAYLIST = "playlist:"

    fun playlist(id: String) = "$PLAYLIST$id"

    // The playlist a reason is for, or null for any other reason.
    fun playlistOf(reason: String): String? = reason.takeIf { it.startsWith(PLAYLIST) }?.removePrefix(PLAYLIST)

    fun parse(text: String): Set<String> = text.split(',').filterTo(LinkedHashSet()) { it.isNotBlank() }

    fun join(reasons: Set<String>): String = reasons.sorted().joinToString(",")
}

// What to do with a finished download, now the server may have swapped the
// song's file for another: see checkKeptCopy. A download is the file as it
// is when it has the server's type, unless that type is MP3, which smaller
// downloads are made as too.
fun checkDownload(file: DownloadedFile): KeptCopyCheck = checkKeptCopy(
    keptFor = file.fileSize,
    serverSize = file.serverSize,
    copySize = file.sizeBytes,
    asIs = file.format != null && file.format == file.serverType && file.format != "audio/mpeg",
)

// What changes to bring the downloads in step with the rules: songs to
// start downloading, songs whose reasons change, and songs to let go, all
// by library id.
data class DownloadPlan(
    val add: Map<String, Set<String>> = emptyMap(),
    val change: Map<String, Set<String>> = emptyMap(),
    val remove: Set<String> = emptySet(),
) {
    val isEmpty: Boolean get() = add.isEmpty() && change.isEmpty() && remove.isEmpty()
}

// The songs the rules want kept, each with the rules that want it.
fun wantedByRules(
    keepLiked: Boolean,
    liked: Collection<String>,
    playlistSongs: Collection<PlaylistMember>,
): Map<String, Set<String>> {
    val wanted = HashMap<String, MutableSet<String>>()
    if (keepLiked) liked.forEach { wanted.getOrPut(it, ::HashSet) += Reasons.LIKED }
    playlistSongs.forEach { wanted.getOrPut(it.trackId, ::HashSet) += Reasons.playlist(it.playlistId) }
    return wanted
}

// Brings what is kept (`held`, each song with its reasons) in step with
// what the rules want. A download asked for by hand stays until it is
// removed by hand. A rule's reason goes only when the rule no longer wants
// the song, so a song that is briefly missing from the library, as during
// a sync, is not deleted. A song is newly downloaded only if it can be:
// on a server and not already on the phone.
fun planDownloads(
    held: Map<String, Set<String>>,
    wanted: Map<String, Set<String>>,
    downloadable: Set<String>,
): DownloadPlan {
    val change = HashMap<String, Set<String>>()
    val remove = HashSet<String>()
    for ((trackId, reasons) in held) {
        val kept = reasons.filterTo(HashSet()) { it == Reasons.MANUAL } + wanted[trackId].orEmpty()
        when {
            kept.isEmpty() -> remove += trackId
            kept != reasons -> change[trackId] = kept
        }
    }
    val add = wanted.filterKeys { it !in held && it in downloadable }
    return DownloadPlan(add, change, remove)
}
