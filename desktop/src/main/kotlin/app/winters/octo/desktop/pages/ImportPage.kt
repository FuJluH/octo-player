package app.winters.octo.desktop.pages

import androidx.compose.foundation.clickable
import androidx.compose.foundation.interaction.MutableInteractionSource
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.width
import androidx.compose.runtime.Composable
import androidx.compose.runtime.DisposableEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.unit.dp
import app.winters.octo.design.Corner
import app.winters.octo.design.CutTxt
import app.winters.octo.design.DesktopType
import app.winters.octo.design.GlassField
import app.winters.octo.design.GlazeCapsule
import app.winters.octo.design.IconSize
import app.winters.octo.design.LocalPopups
import app.winters.octo.design.MenuTitle
import app.winters.octo.design.MeterLine
import app.winters.octo.design.OctoColors
import app.winters.octo.design.OctoIcons
import app.winters.octo.design.OctoSwitch
import app.winters.octo.design.PopupHost
import app.winters.octo.design.PopupPadding
import app.winters.octo.design.ProgressRing
import app.winters.octo.design.RowHeight
import app.winters.octo.design.Space
import app.winters.octo.design.Txt
import app.winters.octo.design.hoverLift
import app.winters.octo.desktop.AppState
import app.winters.octo.desktop.imports.ImportDropZone
import app.winters.octo.desktop.imports.sendImportFile
import app.winters.octo.ui.imports.ImportModel
import app.winters.octo.desktop.nav.Visit
import app.winters.octo.subsonic.ImportListSummary
import app.winters.octo.subsonic.ImportOverview
import app.winters.octo.subsonic.ImportTrack
import app.winters.octo.subsonic.ImportTrackState
import app.winters.octo.subsonic.TrickleState
import app.winters.octo.ui.imports.GET_MISSING_SONGS
import app.winters.octo.ui.imports.GET_MY_MUSIC
import app.winters.octo.ui.imports.IMPORT
import app.winters.octo.ui.imports.KEEP_AS_PLAYLIST
import app.winters.octo.ui.imports.REMOVE_LIST
import app.winters.octo.ui.imports.countsLine
import app.winters.octo.ui.imports.label
import app.winters.octo.ui.imports.line
import app.winters.octo.ui.imports.originLine
import app.winters.octo.ui.imports.removeLine
import app.winters.octo.ui.imports.title

// Import on an Octo server: get music from another service through a file
// TuneMyMusic saves (a tile for each service, then the file by a dialog or
// dropped on the page, or a pasted list) or a public link, see what the
// library has of each list, keep one as a playlist, fetch the songs it is
// missing, and follow the trickle that fetches them. The server reads,
// matches and fetches; this page shows what it says.
@Composable
fun ImportPage(app: AppState, visit: Visit) {
    val model = app.imports
    DisposableEffect(app.connection) {
        model.watch()
        onDispose { model.stop() }
    }
    val overview = model.overview
    val problem = model.problem
    if (overview == null) {
        SectionedPage(
            app,
            visit,
            IMPORT,
            listOf(
                PageSection("get", GET_MY_MUSIC, OctoIcons.Download) {
                    Rows { SettingRow(if (problem == null) "Reading" else "Not here yet", problem ?: "Asking the server about your lists.") }
                },
            ),
        )
        return
    }
    val services = model.services
    val trickle = overview.trickle
    val scope = rememberCoroutineScope()
    val sections = buildList {
        if (services != null) {
            add(PageSection("get", GET_MY_MUSIC, OctoIcons.Download, detail = getDetail(model)) { GetMyMusicSection(model, services) })
        }
        add(PageSection("link", "Public link", OctoIcons.Link, detail = "A Spotify playlist or album") { LinkSection(model, files = services != null) })
        add(PageSection("lists", "Your lists", OctoIcons.Playlists, detail = listsDetail(overview)) { ListsSection(model, overview) })
        add(
            PageSection(
                "trickle",
                "Trickle",
                OctoIcons.Downloading,
                detail = trickle.title(),
                trailing = if (trickle.stage == TrickleState.Idle && trickle.queued == 0) null else {
                    { PauseSwitch(model, trickle.stage == TrickleState.Paused) }
                },
            ) { TrickleSection(model, overview) },
        )
    }
    // A list file dropped anywhere on the page is sent, once the server takes files.
    ImportDropZone(enabled = services != null, onFile = { file -> sendImportFile(scope, model, file) }) {
        SectionedPage(app, visit, IMPORT, sections)
    }
}

private fun listsDetail(overview: ImportOverview): String {
    val lists = overview.lists
    if (lists.isEmpty()) return "None yet"
    val songs = lists.sumOf { it.total }
    val have = lists.sumOf { it.have }
    return "${lists.size} ${if (lists.size == 1) "list" else "lists"}, $have of $songs songs in your library"
}

@Composable
internal fun Said(model: ImportModel) {
    val said = model.said ?: return
    Txt(said, DesktopType.meta, OctoColors.TextSecondary, Modifier.padding(horizontal = RowInset), maxLines = 4)
}

// A public Spotify playlist or album by its link, which the server reads.
// On a server that takes files, a file from any service is under Get my
// music; an older one only says where to send one.
@Composable
private fun LinkSection(model: ImportModel, files: Boolean) {
    Rows {
        LinkRow(model)
        if (!files) SettingRow("A file", "A CSV from Exportify or TuneMyMusic, or Spotify's own data export, imports on the Octo dashboard, on its import page.")
    }
    Said(model)
}

@Composable
private fun LinkRow(model: ImportModel) {
    var link by remember { mutableStateOf("") }
    Column(Modifier.fillMaxWidth().padding(horizontal = RowInset, vertical = Space.L), verticalArrangement = Arrangement.spacedBy(Space.S)) {
        Txt("Paste a link", DesktopType.body)
        Txt("Share, then Copy link, on a Spotify playlist or album. A link shows Octo the first 100 songs.", DesktopType.meta, OctoColors.TextMuted, maxLines = 2)
        Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(Space.M)) {
            val add = {
                if (link.isNotBlank()) {
                    model.addLink(link)
                    link = ""
                }
            }
            GlassField(link, { link = it }, Modifier.weight(1f), placeholder = "https://open.spotify.com/playlist/…", onSubmit = add)
            GlazeCapsule(OctoIcons.Add, "Add", add, enabled = link.isNotBlank() && !model.working)
        }
    }
}

@Composable
private fun ListsSection(model: ImportModel, overview: ImportOverview) {
    overview.libraryProblem?.let { Txt(it, DesktopType.body, OctoColors.SignalOrange, Modifier.padding(horizontal = RowInset), maxLines = 4) }
    Said(model)
    val openId = model.openId
    val opened = overview.lists.firstOrNull { it.id == openId }
    if (opened != null) {
        OpenedList(model, opened)
        return
    }
    if (overview.lists.isEmpty()) {
        Rows {
            SettingRow(
                "No lists yet",
                if (model.services != null) "Pick your service under $GET_MY_MUSIC, or add a link under Public link."
                else "Add a link under Public link.",
            )
        }
        return
    }
    Rows {
        overview.lists.forEach { list -> ListRow(model, list) }
    }
}

// One list: its name and where it is from, what the library has of it, and
// its two switches. A click on its name opens its songs.
@Composable
private fun ListRow(model: ImportModel, list: ImportListSummary) {
    Column(Modifier.fillMaxWidth().padding(horizontal = RowInset, vertical = Space.L), verticalArrangement = Arrangement.spacedBy(Space.S)) {
        Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(Space.L)) {
            Column(
                Modifier
                    .weight(1f)
                    .clip(Corner.ControlShape)
                    .clickable(interactionSource = remember { MutableInteractionSource() }, indication = null, role = Role.Button) { model.open(list.id) },
            ) {
                Txt(list.name, DesktopType.emphasis, maxLines = 2)
                Txt(list.originLine(), DesktopType.meta, OctoColors.TextMuted)
            }
            Txt(list.countsLine(), DesktopType.meta, OctoColors.TextSecondary)
            RowAction("Open", { model.open(list.id) })
        }
        MeterLine(list.fraction)
        list.partial?.let { Txt(it, DesktopType.meta, OctoColors.TextMuted, maxLines = 3) }
        list.playlistNote?.let { Txt(it, DesktopType.meta, OctoColors.TextMuted, maxLines = 2) }
        Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(Space.Xl)) {
            LabelledSwitch(KEEP_AS_PLAYLIST, list.keepPlaylist, enabled = !model.working) { model.keepPlaylist(list.id, it) }
            LabelledSwitch(GET_MISSING_SONGS, list.getMissing, enabled = !model.working) { model.getMissing(list.id, it) }
            Box(Modifier.weight(1f))
            if (list.readsAgain) RowAction("Read again", { model.readList(list.id) }, enabled = !model.working)
            val popups = LocalPopups.current
            RowAction("Remove", { askToRemove(popups, model, list) }, enabled = !model.working)
        }
    }
}

// Asks before a list is removed, in the middle of the window, as deleting
// from disk does.
private fun askToRemove(popups: PopupHost, model: ImportModel, list: ImportListSummary) {
    popups.showCentred { close ->
        MenuTitle(REMOVE_LIST)
        PopupPadding {
            Txt(list.removeLine(), DesktopType.body, OctoColors.TextPrimary, maxLines = 6)
            Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.spacedBy(Space.M, Alignment.End)) {
                GlazeCapsule(null, "Cancel", close)
                GlazeCapsule(OctoIcons.Delete, "Remove", {
                    close()
                    model.remove(list.id)
                }, lit = true)
            }
        }
    }
}

@Composable
private fun LabelledSwitch(text: String, on: Boolean, enabled: Boolean, change: (Boolean) -> Unit) {
    Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(Space.M)) {
        Txt(text, DesktopType.meta, OctoColors.TextSecondary)
        OctoSwitch(on, change, enabled = enabled)
    }
}

@Composable
private fun PauseSwitch(model: ImportModel, paused: Boolean) {
    LabelledSwitch("Paused", paused, enabled = !model.working) { if (it) model.pause() else model.resume() }
}

@Composable
private fun OpenedList(model: ImportModel, list: ImportListSummary) {
    val detail = model.detail?.takeIf { it.list.id == list.id }
    Rows {
        SettingRow(list.name, "${list.countsLine()}. ${list.originLine()}") {
            RowAction("Back to your lists", model::close)
        }
    }
    if (detail == null) {
        Rows { SettingRow("Reading the list", null) { ProgressRing(null, size = IconSize.Transport) } }
        return
    }
    val askable = detail.tracks.filter { it.stage.askable }
    if (askable.isNotEmpty() && !list.getMissing) {
        Rows {
            ActionRow(
                "Get the ${askable.size} missing ${if (askable.size == 1) "song" else "songs"} now",
                "Only these, once. $GET_MISSING_SONGS fetches songs added to the list later too.",
                "Get them",
                { model.getSongs(list.id, askable.map { it.key }) },
                enabled = !model.working,
            )
        }
    }
    Rows {
        detail.tracks.forEach { track -> TrackRow(track) }
    }
}

@Composable
private fun TrackRow(track: ImportTrack, action: (@Composable () -> Unit)? = null) {
    Row(
        Modifier.fillMaxWidth().heightIn(min = RowHeight.Regular).hoverLift(Corner.RowShape).padding(horizontal = RowInset, vertical = Space.M),
        verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.spacedBy(Space.L),
    ) {
        Column(Modifier.weight(1f)) {
            CutTxt(track.title, DesktopType.tableTitle)
            Txt(listOfNotNull(track.artist, track.album).joinToString(" · "), DesktopType.meta, OctoColors.TextMuted)
        }
        Column(Modifier.width(240.dp), horizontalAlignment = Alignment.End) {
            Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(Space.S)) {
                if (track.stage == ImportTrackState.Downloading) ProgressRing(track.progress?.toFloat(), size = IconSize.Inline)
                Txt(track.stage.label(), DesktopType.meta, stateColor(track.stage))
            }
            track.detail?.let { Txt(it, DesktopType.meta, OctoColors.TextMuted, maxLines = 2, align = androidx.compose.ui.text.style.TextAlign.End) }
        }
        action?.invoke()
    }
}

private fun stateColor(state: ImportTrackState) = when (state) {
    ImportTrackState.Have, ImportTrackState.Done -> OctoColors.SignalGreen
    ImportTrackState.NotFound, ImportTrackState.Skipped -> OctoColors.SignalOrange
    else -> OctoColors.TextSecondary
}

@Composable
private fun TrickleSection(model: ImportModel, overview: ImportOverview) {
    val trickle = overview.trickle
    Rows {
        SettingRow(trickle.title(), trickle.line()) {
            if (trickle.notFound > 0) RowAction("Try not found again", { model.retry() }, enabled = !model.working)
        }
        if (trickle.done + trickle.notFound + trickle.skipped > 0) {
            ActionRow("Clear finished", "Forget the songs fetched, not found or skipped. The songs themselves stay.", "Clear", model::clearFinished, enabled = !model.working)
        }
    }
    trickle.current?.let { current -> Group("Now") { TrackRow(current) } }
    if (trickle.next.isNotEmpty()) {
        Group("Next") {
            trickle.next.forEach { track -> TrackRow(track) { RowAction("Skip", { model.skip(track.key) }, enabled = !model.working) } }
        }
    }
    if (trickle.recent.isNotEmpty()) {
        Group("Lately") {
            trickle.recent.forEach { track ->
                TrackRow(track, if (track.stage == ImportTrackState.NotFound || track.stage == ImportTrackState.Skipped) {
                    { RowAction("Try again", { model.retry(listOf(track.key)) }, enabled = !model.working) }
                } else null)
            }
        }
    }
}
