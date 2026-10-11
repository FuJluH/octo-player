package app.winters.octo.health

import app.winters.octo.catalog.SongIdentity
import app.winters.octo.subsonic.LIBRARY_ACTION_COVER
import app.winters.octo.subsonic.LIBRARY_ACTION_JOIN_ALBUM
import app.winters.octo.subsonic.LIBRARY_ACTION_REMOVE
import app.winters.octo.subsonic.LIBRARY_ACTION_RESTORE
import app.winters.octo.subsonic.LIBRARY_ACTION_RETAG
import app.winters.octo.subsonic.LIBRARY_ACTION_UNDO
import app.winters.octo.subsonic.LibraryActionResult
import app.winters.octo.subsonic.LibraryActionState
import app.winters.octo.subsonic.SongLookup
import app.winters.octo.subsonic.SongTag
import java.util.Locale

// Library health's fixes: what each finding comes to when it is put
// right, worked out from the songs alone so it can be shown before
// anything changes, and then done one song at a time through the server.
// Both apps plan and run fixes with these; only the drawing differs.

// A song's tags as the server names them, for the ones the app can see.
// Blank is null.
fun <T> tagValues(song: T, fields: HealthFields<T>): Map<String, String?> {
    fun text(value: String?) = value?.takeIf(String::isNotBlank)
    fun number(value: Int?) = value?.takeIf { it > 0 }?.toString()
    return mapOf(
        SongTag.TITLE to text(fields.title(song)),
        SongTag.ARTIST to text(fields.artist(song)),
        SongTag.ALBUM to text(fields.album(song)),
        SongTag.ALBUM_ARTIST to (if (HealthTag.AlbumArtist in fields.seen) text(fields.albumArtist(song)) else null),
        SongTag.YEAR to number(fields.year(song)),
        SongTag.GENRE to text(fields.genres(song).filter(String::isNotBlank).joinToString("; ")),
        SongTag.TRACK to number(fields.track(song)),
        SongTag.DISC to number(fields.disc(song)),
        SongTag.ISRC to text(fields.isrcs(song).firstOrNull()),
    )
}

// The report with songs fixed for one check left out of that check only,
// until the server's list catches up: a song given its year still lacks
// its genre.
fun <T> HealthReport<T>.settledFor(check: HealthCheck, ids: Set<String>, fields: HealthFields<T>): HealthReport<T> {
    if (ids.isEmpty()) return this
    val only = without(ids, fields)
    return when (check) {
        HealthCheck.Duplicates -> copy(duplicates = only.duplicates)
        HealthCheck.SplitAlbums -> copy(splitAlbums = only.splitAlbums)
        HealthCheck.NoLength -> copy(noLength = only.noLength)
        else -> {
            val tag = check.tag ?: return this
            val left = missing[tag].orEmpty().filter { fields.id(it) !in ids }
            copy(missing = if (left.isEmpty()) missing - tag else missing + (tag to left))
        }
    }
}

// One tag a fix would write: what the song says now and what it gets.
data class TagChange(val tag: String, val now: String?, val value: String, val from: String? = null)

// One tag two copies disagree on, each copy's value by the copy's id.
data class TagChoice(val tag: String, val values: Map<String, String>)

// A set of copies put right: one kept, the rest removed, and the tags the
// kept one lacks taken from the others.
data class DuplicateFix<T>(
    val keep: T,
    val remove: List<T>,
    // Why that one is kept, in plain words.
    val why: String,
    // Blank tags on the kept copy another copy can fill. Done by "fix all".
    val fills: List<TagChange>,
    // Tags the copies say differently, for a person to pick from.
    val differs: List<TagChoice>,
    // Something worth knowing first, like a copy that is the only one on
    // its album.
    val note: String?,
)

// The tags filled first, in this order.
private val FillOrder = listOf(SongTag.ALBUM, SongTag.ALBUM_ARTIST, SongTag.TRACK, SongTag.DISC, SongTag.YEAR, SongTag.GENRE, SongTag.ISRC)

// Tags that belong to an album: taken only from a copy on the same album,
// or with the album itself when the kept copy has none.
private val AlbumTags = setOf(SongTag.ALBUM, SongTag.ALBUM_ARTIST, SongTag.TRACK, SongTag.DISC, SongTag.YEAR)

// The plan for one set of copies, keeping `keep` (the best copy unless a
// person picked another).
fun <T> duplicateFix(group: DuplicateGroup<T>, fields: HealthFields<T>, keep: T = group.best): DuplicateFix<T> {
    val others = group.copies.filter { fields.id(it) != fields.id(keep) }
    val mine = tagValues(keep, fields)
    // The fullest tagged donors first.
    val donors = others.sortedByDescending { tagsOf(it, fields) }
    val myAlbum = SongIdentity.key(mine[SongTag.ALBUM])
    val fills = ArrayList<TagChange>()
    // With no album, the album comes from one donor whole: its title, album
    // artist, track and disc together.
    val albumDonor = if (myAlbum.isEmpty()) donors.firstOrNull { tagValues(it, fields)[SongTag.ALBUM] != null } else null
    for (tag in FillOrder) {
        if (mine[tag] != null) continue
        val donor = donors.firstOrNull { donor ->
            val theirs = tagValues(donor, fields)
            theirs[tag] != null && (
                tag !in AlbumTags ||
                    (albumDonor != null && fields.id(donor) == fields.id(albumDonor)) ||
                    (myAlbum.isNotEmpty() && SongIdentity.key(theirs[SongTag.ALBUM]) == myAlbum)
                )
        } ?: continue
        fills += TagChange(tag, null, tagValues(donor, fields)[tag]!!, fields.id(donor))
    }
    val differs = listOf(SongTag.TITLE, SongTag.ARTIST, SongTag.ALBUM, SongTag.ALBUM_ARTIST, SongTag.YEAR, SongTag.GENRE).mapNotNull { tag ->
        val values = LinkedHashMap<String, String>()
        mine[tag]?.let { values[fields.id(keep)] = it }
        for (other in others) tagValues(other, fields)[tag]?.let { values[fields.id(other)] = it }
        if (mine[tag] != null && values.values.distinct().size > 1) TagChoice(tag, values) else null
    }
    // A copy that is the only song of its album here takes the album with it.
    val lonely = others.firstOrNull { other ->
        val album = SongIdentity.key(fields.album(other))
        album.isNotEmpty() && album != myAlbum
    }
    val note = lonely?.let { "${copyName(it, fields)} is on ${fields.album(it)!!.trim()}, so that album will no longer have this song." }
    return DuplicateFix(keep, others, keepWhy(group, keep, fields), fills, differs, note)
}

// Why `keep` is the one kept, in words.
fun <T> keepWhy(group: DuplicateGroup<T>, keep: T, fields: HealthFields<T>): String {
    val quality = qualityText(keep, fields)
    if (fields.id(keep) != fields.id(group.best)) return "You picked this copy ($quality) to keep."
    return when (group.bestReason) {
        BestReason.Sound -> "Keeps the $quality copy, because it sounds best."
        BestReason.Tags -> "The copies sound alike, so this keeps the one with the fullest tags ($quality)."
        BestReason.None -> "The copies sound alike and have the same tags, so this keeps the first ($quality)."
    }
}

// "Holocene (MP3, 320 kbps)".
fun <T> copyName(song: T, fields: HealthFields<T>): String = "${fields.title(song)} (${qualityText(song, fields)})"

// A tag's name for people.
fun tagName(tag: String): String = when (tag) {
    SongTag.TITLE -> "Title"
    SongTag.ARTIST -> "Artist"
    SongTag.ALBUM -> "Album"
    SongTag.ALBUM_ARTIST -> "Album artist"
    SongTag.YEAR -> "Year"
    SongTag.GENRE -> "Genre"
    SongTag.TRACK -> "Track number"
    SongTag.DISC -> "Disc number"
    SongTag.ISRC -> "ISRC"
    else -> tag.replaceFirstChar { it.titlecase(Locale.ROOT) }
}

// "Year: 1998" or, over a value, "Year: 1998, was 1997".
fun TagChange.words(): String = if (now == null) "${tagName(tag)}: $value" else "${tagName(tag)}: $value, was $now"

// A split album put right: every song of the other parts takes the album
// tags of the first part, the largest unless another's album artist names
// every part's artist. Where the album artists differ, the moved songs take
// the first part's.
data class AlbumJoin<T>(val album: SplitAlbum<T>, val lead: T, val moving: List<T>) {
    val words: String
        get() {
            val count = countText(moving.size, "song", "songs")
            val kept = album.parts[0].songs.size
            val named = kept < album.parts.maxOf { it.songs.size }
            val why = if (named) ", since its album artist names every part's artist" else ""
            val head = "Moves $count onto ${album.title.trim()}, the part with ${countText(kept, "song", "songs")}$why."
            val artist = album.artist.trim()
            val differs = album.reasons.isNotEmpty() || album.differences.any { it.kind == AlbumDifference.AlbumArtist }
            return if (differs && artist.isNotEmpty()) "$head Their album artist becomes $artist." else head
        }
}

fun <T> albumJoin(album: SplitAlbum<T>): AlbumJoin<T> =
    AlbumJoin(album, album.parts[0].songs[0], album.parts.drop(1).flatMap { it.songs })

// A tag a song lacks that the rest of its album agrees on, so it can be
// filled in without looking anything up: the year or genre every other
// song of the album has, or an album artist from the album or, when every
// song is by one artist, that artist.
fun <T> fillsFromAlbum(missing: List<T>, all: List<T>, tag: HealthTag, fields: HealthFields<T>): List<Pair<T, TagChange>> {
    val name = when (tag) {
        HealthTag.Year -> SongTag.YEAR
        HealthTag.Genre -> SongTag.GENRE
        HealthTag.AlbumArtist -> SongTag.ALBUM_ARTIST
        else -> return emptyList()
    }
    val byAlbum = all.groupBy { fields.albumId(it).orEmpty() }
    return missing.mapNotNull { song ->
        val albumId = fields.albumId(song)?.takeIf(String::isNotEmpty) ?: return@mapNotNull null
        val siblings = byAlbum[albumId].orEmpty().filter { fields.id(it) != fields.id(song) }
        val values = siblings.mapNotNull { tagValues(it, fields)[name] }.distinct()
        val value = values.singleOrNull()
            ?: if (tag == HealthTag.AlbumArtist && values.isEmpty()) {
                (siblings + song).mapNotNull { fields.artist(it)?.takeIf(String::isNotBlank) }.distinct().singleOrNull()
            } else {
                null
            }
        value?.let { song to TagChange(name, null, it) }
    }
}

// What a lookup would change: each tag found that the file says
// differently. A blank one is picked to be filled; one the file has is
// picked only when the match is sure and the tag is not the song's name.
fun SongLookup.changes(): List<Pair<TagChange, Boolean>> = SongTag.all.mapNotNull { tag ->
    val found = suggested[tag]?.takeIf(String::isNotBlank) ?: return@mapNotNull null
    val now = current[tag]?.takeIf(String::isNotBlank)
    if (now != null && now.trim() == found.trim()) return@mapNotNull null
    val named = tag == SongTag.TITLE || tag == SongTag.ARTIST || tag == SongTag.ALBUM
    TagChange(tag, now, found, source) to (now == null || (sure && !named))
}

// What the server tells about where a lookup came from: "Strong match
// from Fingerprint, on 'Mezzanine' 1998".
fun SongLookup.origin(): String {
    val how = when (confidence?.lowercase(Locale.ROOT)) {
        "strong" -> "A sure match"
        "medium" -> "A likely match"
        null -> "Found"
        else -> "A doubtful match"
    }
    val from = source?.let { " from ${sourceName(it)}" }.orEmpty()
    val on = release?.takeIf(String::isNotBlank)?.let { ", on $it" }.orEmpty()
    return "$how$from$on."
}

private fun sourceName(source: String) = when (source.lowercase(Locale.ROOT)) {
    "fingerprint" -> "the song's fingerprint"
    "database" -> "MusicBrainz"
    "catalog" -> "the catalog"
    "filetags" -> "the file's own tags"
    else -> source
}

// One thing done to one song through the server.
sealed interface FixStep {
    // The song's id on the server.
    val id: String

    // The song, for what is said about it.
    val title: String

    // `copy`: one copy of a song the library keeps another of, so the song
    // itself is still wanted and the server does not refuse it later.
    data class Remove(override val id: String, override val title: String, val copy: Boolean = false) : FixStep
    data class Retag(override val id: String, override val title: String, val tags: Map<String, String>) : FixStep
    data class JoinAlbum(override val id: String, override val title: String, val like: String) : FixStep
    data class AddCover(override val id: String, override val title: String) : FixStep
    // `replaced`: the song's file was replaced by another copy, and putting
    // it back swaps the two, leaving the newer one in the trash.
    data class Restore(override val id: String, override val title: String, val replaced: Boolean = false) : FixStep
    data class Undo(override val id: String, override val title: String) : FixStep

    val action: String
        get() = when (this) {
            is Remove -> LIBRARY_ACTION_REMOVE
            is Retag -> LIBRARY_ACTION_RETAG
            is JoinAlbum -> LIBRARY_ACTION_JOIN_ALBUM
            is AddCover -> LIBRARY_ACTION_COVER
            is Restore -> LIBRARY_ACTION_RESTORE
            is Undo -> LIBRARY_ACTION_UNDO
        }

    val with: Map<String, String>
        get() = when (this) {
            is Retag -> tags
            is JoinAlbum -> mapOf("like" to like)
            is Remove -> if (copy) mapOf("copy" to "true") else emptyMap()
            else -> emptyMap()
        }

    // The step that puts this one back, once it is done.
    val undo: FixStep?
        get() = when (this) {
            is Remove -> Restore(id, title)
            is Retag, is JoinAlbum, is AddCover -> Undo(id, title)
            // Swapping a replaced file back is undone by swapping again.
            is Restore -> if (replaced) Restore(id, title, replaced = true) else Remove(id, title)
            is Undo -> null
        }
}

// The steps that fix a set of copies: fill the kept one's blank tags,
// then remove the others.
fun <T> DuplicateFix<T>.steps(fields: HealthFields<T>, fills: List<TagChange> = this.fills): List<FixStep> = buildList {
    if (fills.isNotEmpty()) add(FixStep.Retag(fields.id(keep), fields.title(keep), fills.associate { it.tag to it.value }))
    remove.forEach { add(FixStep.Remove(fields.id(it), fields.title(it), copy = true)) }
}

fun <T> AlbumJoin<T>.steps(fields: HealthFields<T>): List<FixStep> =
    moving.map { FixStep.JoinAlbum(fields.id(it), fields.title(it), fields.id(lead)) }

// How a run of steps went.
data class FixOutcome(
    val done: List<FixStep> = emptyList(),
    // Steps that changed nothing because nothing needed changing.
    val unchanged: List<FixStep> = emptyList(),
    // Steps that could not be done, with the server's words.
    val failed: List<Pair<FixStep, String>> = emptyList(),
    // The server only rehearsed.
    val rehearsed: Boolean = false,
    // Stopped before the end.
    val stopped: Boolean = false,
    // The server's own words for steps done, when it gave any.
    val said: Map<FixStep, String> = emptyMap(),
) {
    val removed: Set<String> get() = done.filterIsInstance<FixStep.Remove>().mapTo(HashSet()) { it.id }

    // What puts every done step back, the last first.
    val undo: List<FixStep> get() = done.asReversed().mapNotNull { it.undo }

    // One line for the window: what was done, and what was not.
    fun summary(): String {
        // Putting back one replaced file: the server says best what it did,
        // or why there is nothing to put back.
        val only = (done + failed.map { it.first }).singleOrNull()
        if (!rehearsed && only is FixStep.Restore && only.replaced) {
            said[only]?.let { return it }
            failed.singleOrNull()?.let { return it.second }
        }
        if (rehearsed) return "The server only rehearsed this, because its library actions are in dry run. Nothing changed."
        val parts = ArrayList<String>()
        val removes = done.count { it is FixStep.Remove }
        val retags = done.filterIsInstance<FixStep.Retag>()
        val joins = done.count { it is FixStep.JoinAlbum }
        val covers = done.count { it is FixStep.AddCover }
        val restores = done.count { it is FixStep.Restore }
        val undos = done.count { it is FixStep.Undo }
        if (removes > 0) parts += "removed ${countText(removes, "song", "songs")}"
        if (retags.isNotEmpty()) parts += "changed the tags of ${countText(retags.size, "song", "songs")}"
        if (joins > 0) parts += "moved ${countText(joins, "song", "songs")} onto their album"
        if (covers > 0) parts += "added ${countText(covers, "cover", "covers")}"
        if (restores > 0) parts += "put back ${countText(restores, "song", "songs")}"
        if (undos > 0) parts += "undid the changes to ${countText(undos, "song", "songs")}"
        val head = if (parts.isEmpty()) {
            if (unchanged.isNotEmpty()) "Nothing needed changing." else "Nothing was done."
        } else {
            parts.joinToString(", ").replaceFirstChar { it.titlecase(Locale.ROOT) } + "."
        }
        val stop = if (stopped) " Stopped before the end." else ""
        val miss = when (failed.size) {
            0 -> ""
            1 -> " ${failed[0].first.title}: ${failed[0].second}"
            else -> " ${countText(failed.size, "song", "songs")} could not be done, like ${failed[0].first.title}: ${failed[0].second}"
        }
        return "$head$stop$miss"
    }
}

// Runs steps one after another through `send`, which asks the server and
// answers as it did; an exception is that step's failure, in its words.
// `progress` hears how many are done; `stop` ends the run between steps.
suspend fun runFix(
    steps: List<FixStep>,
    send: suspend (FixStep) -> LibraryActionResult,
    progress: (done: Int, total: Int) -> Unit = { _, _ -> },
    stop: () -> Boolean = { false },
    failure: (Throwable) -> String = { it.message ?: "something went wrong" },
): FixOutcome {
    val done = ArrayList<FixStep>()
    val unchanged = ArrayList<FixStep>()
    val failed = ArrayList<Pair<FixStep, String>>()
    val said = HashMap<FixStep, String>()
    var rehearsed = false
    var stopped = false
    progress(0, steps.size)
    for ((index, step) in steps.withIndex()) {
        if (stop()) {
            stopped = true
            break
        }
        try {
            val answer = send(step)
            when (answer.outcome) {
                LibraryActionState.Applied -> {
                    done += step
                    answer.detail?.takeIf(String::isNotBlank)?.let { said[step] = it }
                }
                LibraryActionState.Rehearsed -> rehearsed = true
                // Skipped with nothing to change is not a failure: the song
                // already says it, or the cover is there.
                LibraryActionState.Skipped -> if (answer.detail.isNothingToDo()) unchanged += step else failed += step to answer.words()
                else -> failed += step to answer.words()
            }
        } catch (e: Throwable) {
            if (e is kotlinx.coroutines.CancellationException) throw e
            failed += step to failure(e)
        }
        progress(index + 1, steps.size)
    }
    return FixOutcome(done, unchanged, failed, rehearsed, stopped, said)
}

private fun LibraryActionResult.words(): String = detail?.takeIf(String::isNotBlank) ?: "the server said $state"

private val NothingToDo = listOf("nothing to change", "already", "picture of its own", "has a picture")

private fun String?.isNothingToDo(): Boolean {
    val text = this?.lowercase(Locale.ROOT) ?: return false
    return NothingToDo.any { it in text }
}
