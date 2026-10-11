package app.winters.octo.subsonic

import kotlinx.serialization.Serializable

// The OpenSubsonic extension an Octo server lists when it can act on the
// library's files for an app: take a song out of the library and, from
// version 2, look for a FLAC of it; from version 3, fix its tags, album and
// cover and put a removed song back. It is listed only while the server's
// library actions are switched on.
const val OCTO_LIBRARY_ACTIONS = "octoLibraryActions"

// Move the song's file out of the library, into the server's trash.
const val LIBRARY_ACTION_REMOVE = "remove"

// Look for a lossless copy of the song where the server downloads from
// (`upgradeSource`) and swap it in once it passes the server's checks; the
// original is kept until then. Version 2 only, and the server queues it:
// the answer comes back at once and the work runs later.
const val LIBRARY_ACTION_UPGRADE = "upgrade"

// From version 3: what Library health fixes a song with, and the way back.
// Each needs a server admin on the allowed list. Write the tags sent into
// the song's file, in place.
const val LIBRARY_ACTION_RETAG = "retag"

// Give the song the album tags of another song (`like`), which mends an
// album the server shows as two.
const val LIBRARY_ACTION_JOIN_ALBUM = "joinAlbum"

// Find the album's cover and put it inside a file that has no picture.
const val LIBRARY_ACTION_COVER = "cover"

// The tags a download of the song would get, beside what the file says;
// it writes nothing.
const val LIBRARY_ACTION_LOOKUP = "lookup"

// Put back the song's last retag, album join or cover.
const val LIBRARY_ACTION_UNDO = "undo"

// Put a removed song back from the server's trash.
const val LIBRARY_ACTION_RESTORE = "restore"

// The tag names the server reads and writes, as it spells them.
object SongTag {
    const val TITLE = "title"
    const val ARTIST = "artist"
    const val ALBUM = "album"
    const val ALBUM_ARTIST = "albumArtist"
    const val YEAR = "year"
    const val GENRE = "genre"
    const val TRACK = "track"
    const val DISC = "disc"
    const val ISRC = "isrc"

    val all = listOf(TITLE, ARTIST, ALBUM, ALBUM_ARTIST, YEAR, GENRE, TRACK, DISC, ISRC)
}

// What the server lets the signed-in user do to the library's files.
@Serializable
data class LibraryActions(
    // The server's library actions are on at all.
    val enabled: Boolean = false,
    // This user may use them.
    val allowed: Boolean = false,
    // The server only rehearses: it says what it would do and moves nothing.
    val dryRun: Boolean = true,
    val actions: List<String> = emptyList(),
    // How many days a removed file is kept in the server's trash; 0 keeps
    // it until someone clears it by hand.
    val keepDays: Int = 0,
    // How many upgrades the server runs at once; older servers leave it out.
    val parallel: Int = 1,
    // Where the server looks for a better copy, in its own words, like
    // "Soulseek"; null when it does not offer upgrades or does not say.
    val upgradeSource: String? = null,
    // Whether this user is one of the server's admins. From version 3,
    // removing and every fix need it; older servers leave it out and did
    // not ask, so it counts as yes.
    val admin: Boolean = true,
) {
    // Whether files can really be changed now: on, allowed, an admin and
    // not a rehearsal.
    private val real: Boolean get() = enabled && allowed && admin && !dryRun

    // Whether a song can really be taken out of the library now.
    val canRemove: Boolean get() = real && LIBRARY_ACTION_REMOVE in actions

    // Whether a removed song can be put back from the server's trash.
    val canRestore: Boolean get() = real && LIBRARY_ACTION_RESTORE in actions

    // Whether tags can be written, albums joined and changes undone.
    val canEdit: Boolean get() = real && LIBRARY_ACTION_RETAG in actions && LIBRARY_ACTION_UNDO in actions

    // Whether the server can join one album's songs onto another's.
    val canJoinAlbums: Boolean get() = real && LIBRARY_ACTION_JOIN_ALBUM in actions

    // Whether the server can look up a song's tags.
    val canLookUp: Boolean get() = real && LIBRARY_ACTION_LOOKUP in actions

    // Whether the server can find a cover and put it in a file.
    val canAddCover: Boolean get() = real && LIBRARY_ACTION_COVER in actions

    // Whether a FLAC can really be looked for now. A rehearsal would only
    // fill the server's queue with songs it never swaps, so not then either.
    val canUpgrade: Boolean get() = enabled && allowed && !dryRun && LIBRARY_ACTION_UPGRADE in actions
}

// How one action went, as the server tells it.
enum class LibraryActionState(val wire: String) {
    // Done: the file is out of the library.
    Applied("applied"),

    // Taken on for later: an upgrade waits in the server's queue, and
    // upgrades() says how it goes.
    Queued("queued"),

    // Only rehearsed; nothing moved.
    Rehearsed("rehearsed"),

    // Not done, and never will be as asked: off, not allowed, or done already.
    Skipped("skipped"),

    // The server could not tell which file the song is, so it touched nothing.
    Unresolved("unresolved"),

    // It tried and could not.
    Failed("failed"),

    // A state this app does not know yet, from a newer server.
    Unknown(""),
    ;

    companion object {
        fun of(text: String?): LibraryActionState {
            val wire = text?.trim()?.lowercase().orEmpty()
            return entries.firstOrNull { it != Unknown && it.wire == wire } ?: Unknown
        }
    }
}

@Serializable
data class LibraryActionResult(
    val id: String = "",
    val action: String = "",
    // As the server says it; `outcome` is what it means.
    val state: String = "",
    // The server's own words about what happened.
    val detail: String? = null,
    // For a fix: the song's tags before and after, by SongTag name.
    val before: Map<String, String?>? = null,
    val after: Map<String, String?>? = null,
) {
    val outcome: LibraryActionState get() = LibraryActionState.of(state)
}

// What a lookup found for one song: its tags now and the ones a download
// would get (only those found), with how sure the match is and where from.
@Serializable
data class SongLookup(
    val id: String = "",
    val state: String = "",
    val detail: String? = null,
    val current: Map<String, String?> = emptyMap(),
    val suggested: Map<String, String?> = emptyMap(),
    // Strong, Medium, Ambiguous, Low or None, as the server says it.
    val confidence: String? = null,
    // Where the tags came from, like "Fingerprint" or "Deezer".
    val source: String? = null,
    // The release it matched, in the server's words.
    val release: String? = null,
) {
    val found: Boolean get() = state == "found"

    // Strong or Medium: what a download would have written without asking.
    val sure: Boolean get() = confidence.equals("Strong", ignoreCase = true) || confidence.equals("Medium", ignoreCase = true)
}

// One song in the server's trash.
@Serializable
data class TrashedSong(
    val id: String = "",
    val title: String = "",
    val artist: String = "",
    val album: String = "",
    val removedBy: String? = null,
    val removedAt: String? = null,
    // When the server deletes it for good; null keeps it until cleared.
    val goneAt: String? = null,
    // TRASH_REMOVED (also when left out) or TRASH_REPLACED: a file another
    // copy took the place of, with the file in the trash (`was`) and the
    // one in the library now (`now`), like "FLAC 16-bit 44.1 kHz". Putting
    // a replaced one back swaps the two.
    val kind: String? = null,
    val was: String? = null,
    val now: String? = null,
) {
    val replaced: Boolean get() = kind == TRASH_REPLACED
}

const val TRASH_REMOVED = "removed"
const val TRASH_REPLACED = "replaced"

@Serializable
data class LibraryTrash(
    val keepDays: Int = 0,
    val songs: List<TrashedSong> = emptyList(),
)

// Where one asked for FLAC has got to on the server.
enum class UpgradeStage(val wire: String) {
    // Waiting for its turn in the server's queue.
    Queued("queued"),

    // Held while the source is out; it carries on once it is back.
    Waiting("waiting"),

    // Being searched for, downloaded or checked.
    Working("working"),

    // Done: the FLAC passed and took the original's place.
    Upgraded("upgraded"),

    // No FLAC of it could be found; the original stays.
    NotFound("notFound"),

    // Only rehearsed; nothing changed.
    Rehearsed("rehearsed"),

    // Not done, and never will be as asked: not allowed, or already lossless.
    Skipped("skipped"),

    // It tried and could not; the original stays.
    Failed("failed"),

    // A state this app does not know yet, from a newer server.
    Unknown(""),
    ;

    // Whether the server is still on it, so it is worth asking again.
    val pending: Boolean get() = this == Queued || this == Waiting || this == Working

    companion object {
        fun of(text: String?): UpgradeStage {
            val wire = text?.trim().orEmpty()
            return entries.firstOrNull { it != Unknown && it.wire.equals(wire, ignoreCase = true) } ?: Unknown
        }
    }
}

// One song the signed-in user asked a FLAC for. Finished ones stay listed
// for a while, so an app that was closed still hears how they went.
@Serializable
data class Upgrade(
    // The song's id in the library, which stays the same after the swap.
    val id: String = "",
    val title: String = "",
    val artist: String = "",
    val album: String? = null,
    // As the server says it; `stage` is what it means.
    val state: String = "",
    // The server's own words about how it went.
    val detail: String? = null,
    // How far the download is, from 0 to 1, when the server knows.
    val progress: Double? = null,
    val updatedAt: String? = null,
    // The download fetching the replacement, by its key, once there is one.
    val acquisition: String? = null,
    // The copy picked in Find songs, in words, when one was.
    val picked: String? = null,
) {
    val stage: UpgradeStage get() = UpgradeStage.of(state)

    // How far along, kept between 0 and 1, or null when unknown.
    val fraction: Float? get() = progress?.takeIf { it.isFinite() }?.coerceIn(0.0, 1.0)?.toFloat()
}
