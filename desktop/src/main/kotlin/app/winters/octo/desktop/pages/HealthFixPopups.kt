package app.winters.octo.desktop.pages

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.ColumnScope
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateListOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.unit.dp
import app.winters.octo.design.DesktopType
import app.winters.octo.design.GlazeCapsule
import app.winters.octo.design.MenuRow
import app.winters.octo.design.MenuSeparator
import app.winters.octo.design.MenuTitle
import app.winters.octo.design.OctoColors
import app.winters.octo.design.OctoIcons
import app.winters.octo.design.PopupPadding
import app.winters.octo.design.Space
import app.winters.octo.design.Txt
import app.winters.octo.desktop.AppState
import app.winters.octo.desktop.runFix
import app.winters.octo.health.AlbumJoin
import app.winters.octo.health.DuplicateFix
import app.winters.octo.health.DuplicateGroup
import app.winters.octo.health.FixStep
import app.winters.octo.health.HealthCheck
import app.winters.octo.health.LOOK_UP_TAGS
import app.winters.octo.health.PUT_BACK
import app.winters.octo.health.RECENTLY_REMOVED
import app.winters.octo.health.SubsonicHealth
import app.winters.octo.health.TagChange
import app.winters.octo.health.albumJoin
import app.winters.octo.health.changes
import app.winters.octo.health.copyName
import app.winters.octo.health.countText
import app.winters.octo.health.duplicateFix
import app.winters.octo.health.fixMeaning
import app.winters.octo.health.goneText
import app.winters.octo.health.replacedSpoken
import app.winters.octo.health.replacedText
import app.winters.octo.health.restoreStep
import app.winters.octo.health.heading
import app.winters.octo.health.origin
import app.winters.octo.health.steps
import app.winters.octo.health.tagName
import app.winters.octo.health.words
import app.winters.octo.health.SplitAlbum
import app.winters.octo.subsonic.Song
import app.winters.octo.subsonic.SongLookup
import java.time.Instant

// The questions Library health asks before it changes anything: each
// shows what will happen, song by song, and only a button press does it.
// Everything they do is said in the notice line after, with Undo.

private val WideForm = 560.dp

// How many lines a long preview shows before it says how many more.
internal const val PREVIEW_LINES = 120

// The buttons at the foot of a question: Cancel and the one that does it.
@Composable
private fun ColumnScope.Buttons(go: String, enabled: Boolean = true, close: () -> Unit, run: () -> Unit) {
    Row(Modifier.fillMaxWidth().padding(top = Space.S), horizontalArrangement = Arrangement.spacedBy(Space.M, Alignment.End)) {
        GlazeCapsule(null, "Cancel", close)
        GlazeCapsule(OctoIcons.Check, go, {
            close()
            run()
        }, lit = true, enabled = enabled)
    }
}

@Composable
private fun Line(text: String, muted: Boolean = false, lines: Int = 3) =
    Txt(text, DesktopType.body, if (muted) OctoColors.TextSecondary else OctoColors.TextPrimary, maxLines = lines)

@Composable
private fun More(shown: Int, total: Int) {
    if (total > shown) Txt("And ${countText(total - shown, "more", "more")}.", DesktopType.meta, OctoColors.TextMuted)
}

// What fixing one set of copies does, in a line for a list.
internal fun DuplicateFix<Song>.line(): String {
    val keepName = copyName(keep, SubsonicHealth)
    val gone = countText(remove.size, "copy", "copies")
    val filled = if (fills.isEmpty()) "" else " Fills in ${fills.joinToString(", ") { tagName(it.tag).lowercase() }}."
    return "Keeps $keepName and moves $gone to the trash.$filled"
}

// Every set of copies at once: what each comes to, then one press.
// Only blank tags are filled; where the copies disagree, nothing is picked.
fun askToFixDuplicates(app: AppState, groups: List<DuplicateGroup<Song>>) {
    val canFill = app.health.actions?.canEdit == true
    val fixes = groups.map { duplicateFix(it, SubsonicHealth).let { fix -> if (canFill) fix else fix.copy(fills = emptyList()) } }
    val removing = fixes.sumOf { it.remove.size }
    app.popups.showCentred(WideForm) { close ->
        MenuTitle("Fix ${countText(fixes.size, "song", "songs")} you have twice")
        PopupPadding {
            Line(HealthCheck.Duplicates.fixMeaning(), muted = true, lines = 4)
            fixes.take(PREVIEW_LINES).forEachIndexed { i, fix ->
                Column(verticalArrangement = Arrangement.spacedBy(2.dp)) {
                    Txt(groups[i].heading(SubsonicHealth), DesktopType.emphasis, maxLines = 2)
                    Line(fix.line(), muted = true)
                    fix.note?.let { Line(it, muted = true) }
                }
            }
            More(PREVIEW_LINES, fixes.size)
            Buttons("Move ${countText(removing, "copy", "copies")} to the trash", close = close) {
                app.runFix("Fixing copies", fixes.flatMap { it.steps(SubsonicHealth) }, HealthCheck.Duplicates)
            }
        }
    }
}

// One set of copies: which is kept and why, the tags to fill in from the
// others (each can be left out), and where the copies disagree, which
// value the kept copy ends with.
fun askToFixCopies(app: AppState, group: DuplicateGroup<Song>, keep: Song = group.best) {
    val canFill = app.health.actions?.canEdit == true
    val fix = duplicateFix(group, SubsonicHealth, keep)
    app.popups.showCentred(WideForm) { close ->
        val fills = remember { mutableStateListOf<TagChange>().apply { if (canFill) addAll(fix.fills) } }
        // For each tag the copies disagree on, the value picked (the kept copy's at first).
        val chosen = remember { mutableStateOf(fix.differs.associate { it.tag to it.values.getValue(keep.id) }) }
        MenuTitle("Fix these copies")
        PopupPadding {
            Txt(group.heading(SubsonicHealth), DesktopType.emphasis, maxLines = 3)
            Line(fix.why)
            val where = if (fix.remove.size == 1) "where it can be put back" else "where they can be put back"
            Line("Moves ${fix.remove.joinToString(", ") { copyName(it, SubsonicHealth) }} to the trash, $where.", muted = true)
            fix.note?.let { Line(it, muted = true) }
        }
        if (canFill && fix.fills.isNotEmpty()) {
            MenuSeparator()
            MenuTitle("Fill in from the other copies")
            fix.fills.forEach { change ->
                MenuRow(change.words(), {
                    if (change in fills) fills.remove(change) else fills.add(change)
                }, checked = change in fills)
            }
        }
        if (canFill && fix.differs.isNotEmpty()) {
            MenuSeparator()
            MenuTitle("Where the copies disagree")
            fix.differs.forEach { choice ->
                choice.values.values.distinct().forEach { value ->
                    MenuRow("${tagName(choice.tag)}: $value", {
                        chosen.value = chosen.value + (choice.tag to value)
                    }, checked = chosen.value[choice.tag] == value)
                }
            }
        }
        PopupPadding {
            Buttons("Fix", close = close) {
                val picked = fills.toList() + fix.differs.mapNotNull { choice ->
                    val value = chosen.value.getValue(choice.tag)
                    val now = choice.values[keep.id]
                    if (value == now) null else TagChange(choice.tag, now, value)
                }
                app.runFix("Fixing copies", fix.steps(SubsonicHealth, picked), HealthCheck.Duplicates)
            }
        }
    }
}

// Albums split apart, joined: each one's smaller parts take the album tags
// of its largest part.
fun askToJoinAlbums(app: AppState, albums: List<SplitAlbum<Song>>) {
    val joins: List<AlbumJoin<Song>> = albums.map(::albumJoin)
    val moving = joins.sumOf { it.moving.size }
    app.popups.showCentred(WideForm) { close ->
        MenuTitle(if (joins.size == 1) "Join this album" else "Join ${countText(joins.size, "album", "albums")}")
        PopupPadding {
            Line(HealthCheck.SplitAlbums.fixMeaning(), muted = true, lines = 4)
            joins.take(PREVIEW_LINES).forEach { join ->
                Column(verticalArrangement = Arrangement.spacedBy(2.dp)) {
                    Txt(join.album.heading(), DesktopType.emphasis, maxLines = 3)
                    Line(join.words, muted = true)
                }
            }
            More(PREVIEW_LINES, joins.size)
            Buttons("Move ${countText(moving, "song", "songs")}", close = close) {
                app.runFix("Joining albums", joins.flatMap { it.steps(SubsonicHealth) }, HealthCheck.SplitAlbums)
            }
        }
    }
}

// Tags filled in from the rest of each song's album.
fun askToFill(app: AppState, check: HealthCheck, fills: List<Pair<Song, TagChange>>) {
    app.popups.showCentred(WideForm) { close ->
        MenuTitle("Fill in ${countText(fills.size, "song", "songs")}")
        PopupPadding {
            Line(check.fixMeaning(), muted = true, lines = 4)
            fills.take(PREVIEW_LINES).forEach { (song, change) -> Line("${song.title}: ${change.words()}", lines = 2) }
            More(PREVIEW_LINES, fills.size)
            Buttons("Fill in ${countText(fills.size, "song", "songs")}", close = close) {
                app.runFix("Filling in tags", fills.map { (song, change) -> FixStep.Retag(song.id, song.title, mapOf(change.tag to change.value)) }, check)
            }
        }
    }
}

// Covers looked for and put inside songs that have none.
fun askToAddCovers(app: AppState, songs: List<Song>) {
    app.popups.showCentred(WideForm) { close ->
        MenuTitle("Find ${countText(songs.size, "cover", "covers")}")
        PopupPadding {
            Line(HealthCheck.NoCover.fixMeaning(), muted = true, lines = 4)
            Buttons("Find ${countText(songs.size, "cover", "covers")}", close = close) {
                app.runFix("Finding covers", songs.map { FixStep.AddCover(it.id, it.title) }, HealthCheck.NoCover)
            }
        }
    }
}

// One song looked up the way a download is tagged, and what was found
// shown beside what the file says, each change picked or not before
// anything is written.
fun lookUpSong(app: AppState, song: Song, settle: HealthCheck?) = lookUpSongs(app, listOf(song), settle)

// Songs looked up one after another, then every change found in one list.
fun lookUpSongs(app: AppState, songs: List<Song>, settle: HealthCheck?) {
    if (songs.isEmpty()) return
    app.popups.showCentred(WideForm) { close ->
        val found = remember { mutableStateListOf<Pair<Song, SongLookup>>() }
        val misses = remember { mutableStateListOf<String>() }
        val picked = remember { mutableStateListOf<Pair<String, TagChange>>() }
        var at by remember { mutableStateOf(0) }
        var stopped by remember { mutableStateOf(false) }
        val done = at >= songs.size || stopped
        LaunchedEffect(Unit) {
            for (song in songs) {
                if (stopped) break
                app.health.lookUp(song) { misses += it }?.let { lookup ->
                    found += song to lookup
                    lookup.changes().forEach { (change, pick) -> if (pick) picked += song.id to change }
                }
                at++
            }
        }
        MenuTitle(if (songs.size == 1) LOOK_UP_TAGS else "Look up ${countText(songs.size, "song", "songs")}")
        if (songs.size == 1) PopupPadding { Txt("${songs[0].title}, ${songs[0].artist.orEmpty()}".trimEnd(',', ' '), DesktopType.emphasis, maxLines = 3) }
        if (!done) {
            PopupPadding {
                Line(if (songs.size == 1) "Looking it up." else "Looking up ${at + 1} of ${songs.size}.", muted = true)
                if (songs.size > 1) Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.End) {
                    GlazeCapsule(null, "Stop", { stopped = true })
                }
            }
            return@showCentred
        }
        val changes = found.flatMap { (song, lookup) -> lookup.changes().map { (change, _) -> Triple(song, lookup, change) } }
        PopupPadding {
            when {
                changes.isEmpty() && found.isNotEmpty() -> Line("The tags already say what was found. Nothing to change.", muted = true)
                found.isEmpty() -> Line(misses.firstOrNull() ?: "Nothing was found.", muted = true)
                songs.size == 1 -> Line(found[0].second.origin(), muted = true)
                else -> Line("Found tags for ${countText(found.size, "song", "songs")}. Sure matches are picked; look over the rest.", muted = true)
            }
            if (misses.isNotEmpty() && found.isNotEmpty()) Line("${countText(misses.size, "song", "songs")} found nothing.", muted = true)
        }
        var last: String? = null
        changes.take(PREVIEW_LINES * 2).forEach { (song, lookup, change) ->
            if (songs.size > 1 && last != song.id) {
                last = song.id
                MenuSeparator()
                MenuTitle(song.title)
                PopupPadding { Txt(lookup.origin(), DesktopType.meta, OctoColors.TextMuted, maxLines = 2) }
            }
            val key = song.id to change
            MenuRow(change.words(), { if (key in picked) picked.remove(key) else picked.add(key) }, checked = key in picked)
        }
        PopupPadding {
            val count = picked.size
            Buttons(if (count == 0) "Write nothing" else "Write ${countText(count, "change", "changes")}", enabled = count > 0, close = close) {
                val steps = picked.groupBy({ it.first }, { it.second }).map { (id, list) ->
                    FixStep.Retag(id, songs.first { it.id == id }.title, list.associate { it.tag to it.value })
                }
                app.runFix("Writing tags", steps, settle)
            }
        }
    }
}

// The songs in the server's trash, each with when it goes for good and a
// way to put it back.
fun showTrash(app: AppState) {
    app.popups.showCentred(WideForm) { close ->
        var problem by remember { mutableStateOf<String?>(null) }
        LaunchedEffect(Unit) { app.health.readTrash { problem = it } }
        val trash = app.health.trash
        MenuTitle(RECENTLY_REMOVED)
        when {
            problem != null -> PopupPadding { Line(problem!!, muted = true) }
            trash == null -> PopupPadding { Line("Reading the server's trash.", muted = true) }
            trash.songs.isEmpty() -> PopupPadding { Line("Nothing is in the server's trash.", muted = true) }
            else -> {
                val now = System.currentTimeMillis()
                PopupPadding { Line("Pick a song to put it back where it was.", muted = true) }
                trash.songs.take(PREVIEW_LINES).forEach { song ->
                    val gone = song.goneAt?.let { runCatching { Instant.parse(it).toEpochMilli() }.getOrNull() }
                    MenuRow("${song.title}, ${song.artist}", {
                        close()
                        app.runFix("Putting back", listOf(song.restoreStep()))
                    }, OctoIcons.History, detail = goneText(gone, now))
                    // A replaced song names both files: the one in the
                    // trash and the one that took its place.
                    if (song.replaced) {
                        Txt(
                            replacedText(song.was, song.now),
                            DesktopType.meta,
                            OctoColors.TextSecondary,
                            Modifier.padding(start = 46.dp, end = 16.dp, bottom = 4.dp).semantics { contentDescription = replacedSpoken(song.was, song.now) },
                            maxLines = Int.MAX_VALUE,
                        )
                    }
                }
                PopupPadding {
                    More(PREVIEW_LINES, trash.songs.size)
                    Buttons("$PUT_BACK all ${countText(trash.songs.size, "song", "songs")}", close = close) {
                        app.runFix("Putting back", trash.songs.map { it.restoreStep() })
                    }
                }
            }
        }
    }
}
