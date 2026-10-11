package app.winters.octo.desktop.ui

import androidx.compose.animation.AnimatedVisibility
import androidx.compose.animation.core.RepeatMode
import androidx.compose.animation.core.animateFloat
import androidx.compose.animation.core.animateFloatAsState
import androidx.compose.animation.core.infiniteRepeatable
import androidx.compose.animation.core.rememberInfiniteTransition
import androidx.compose.animation.core.tween
import androidx.compose.animation.fadeIn
import androidx.compose.animation.fadeOut
import androidx.compose.foundation.Canvas
import androidx.compose.foundation.ScrollState
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.clickable
import androidx.compose.foundation.hoverable
import androidx.compose.foundation.interaction.MutableInteractionSource
import androidx.compose.foundation.interaction.collectIsHoveredAsState
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.IntrinsicSize
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxHeight
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.lazy.itemsIndexed
import androidx.compose.foundation.lazy.rememberLazyListState
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.verticalScroll
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.runtime.Composable
import androidx.compose.runtime.DisposableEffect
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue
import androidx.compose.runtime.snapshotFlow
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.geometry.CornerRadius
import androidx.compose.ui.geometry.Size
import androidx.compose.ui.graphics.Brush
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.vector.ImageVector
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.heading
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.semantics.stateDescription
import androidx.compose.ui.unit.dp
import app.winters.octo.design.AccentButton
import app.winters.octo.design.ButtonSize
import app.winters.octo.design.ControlHeight
import app.winters.octo.design.Corner
import app.winters.octo.design.CutTxt
import app.winters.octo.design.DesktopType
import app.winters.octo.design.FrameSize
import app.winters.octo.design.GlazeCapsule
import app.winters.octo.design.Glyph
import app.winters.octo.design.IconAction
import app.winters.octo.design.IconSize
import app.winters.octo.design.MenuTitle
import app.winters.octo.design.OctoDuration
import app.winters.octo.design.motionScale
import app.winters.octo.design.octoTween
import app.winters.octo.design.OctoColors
import app.winters.octo.design.OctoIcons
import app.winters.octo.design.PopupPadding
import app.winters.octo.design.ProgressRing
import app.winters.octo.design.RowHeight
import app.winters.octo.design.Separator
import app.winters.octo.design.SeparatorColor
import app.winters.octo.design.Space
import app.winters.octo.design.TextAction
import app.winters.octo.design.Txt
import app.winters.octo.design.hoverLift
import app.winters.octo.design.scrollbar
import app.winters.octo.desktop.AppState
import app.winters.octo.desktop.downloads.DownloadsModel
import app.winters.octo.desktop.downloads.DrawerView
import app.winters.octo.desktop.library.Cover
import app.winters.octo.subsonic.AcquisitionEvent
import app.winters.octo.subsonic.FIND_OFF
import app.winters.octo.subsonic.FIND_SEARCHING
import app.winters.octo.subsonic.FindSourceState
import app.winters.octo.subsonic.FoundCandidate
import app.winters.octo.subsonic.FoundSongs
import app.winters.octo.ui.downloads.DOWNLOADS_EMPTY
import app.winters.octo.ui.downloads.DownloadStep
import app.winters.octo.ui.downloads.LOG_COPIES_SHOWN
import app.winters.octo.ui.downloads.badgeFacts
import app.winters.octo.ui.downloads.copyBadge
import app.winters.octo.ui.downloads.isLosslessCopy
import app.winters.octo.ui.downloads.rankWords
import app.winters.octo.ui.downloads.stepOf
import app.winters.octo.ui.downloads.DownloadRow
import app.winters.octo.ui.downloads.FIND_DOWNLOADS
import app.winters.octo.ui.downloads.FIND_PICK_WAIT
import app.winters.octo.ui.downloads.KEEP_MINE
import app.winters.octo.ui.downloads.PickQuestion
import app.winters.octo.ui.downloads.REPLACE_ANYWAY
import app.winters.octo.ui.downloads.findReplaces
import app.winters.octo.ui.family.MORE_BELOW
import kotlinx.coroutines.launch
import app.winters.octo.ui.downloads.FIND_SONGS
import app.winters.octo.ui.downloads.LogMark
import app.winters.octo.ui.downloads.RowPhase
import app.winters.octo.ui.downloads.candidateFacts
import app.winters.octo.ui.downloads.candidateTitle
import app.winters.octo.ui.downloads.candidateVerdict
import app.winters.octo.ui.downloads.canPick
import app.winters.octo.ui.downloads.copyKey
import app.winters.octo.ui.downloads.drawerSummary
import app.winters.octo.ui.downloads.kindLabel
import app.winters.octo.ui.downloads.logTime
import app.winters.octo.ui.downloads.markOf
import app.winters.octo.ui.downloads.ownedCopyText
import app.winters.octo.ui.downloads.rowOf

// The downloads drawer, as the side panel's Downloads tab: every download
// the server is doing for this person or did lately, each opening to its
// log, and Find songs, where a song's search runs again and one copy is
// picked. Open, it is asked about every two seconds.
@Composable
fun DownloadsPanel(app: AppState, modifier: Modifier = Modifier) {
    val model = app.downloads
    if (model == null || model.supported == false) {
        Txt(
            "This server does not keep a log of its downloads. An Octo server from October 2026 or later does.",
            DesktopType.body, OctoColors.TextMuted, modifier.padding(Space.Xl), maxLines = 4,
        )
        return
    }
    DisposableEffect(model) {
        model.open = true
        onDispose { model.open = false }
    }
    when (val view = model.view) {
        DrawerView.List -> DownloadList(model, modifier)
        is DrawerView.Log -> DownloadLog(app, model, view.key, modifier)
        is DrawerView.Find -> FindSongs(app, model, view, modifier)
    }
}

// ---------------------------------------------------------------------------
// The list
// ---------------------------------------------------------------------------

@Composable
private fun DownloadList(model: DownloadsModel, modifier: Modifier) {
    val rows by model.rows.collectAsState()
    val loaded by model.loaded.collectAsState()
    Column(modifier) {
        Row(Modifier.fillMaxWidth().padding(start = Space.L, end = Space.S, top = Space.S), verticalAlignment = Alignment.CenterVertically) {
            Txt(drawerSummary(rows), DesktopType.meta, OctoColors.TextMuted, Modifier.weight(1f))
            if (rows.any { it.finished }) TextAction("Clear finished", { model.clear() })
        }
        if (rows.isEmpty()) {
            Txt(if (loaded) DOWNLOADS_EMPTY else "Asking the server", DesktopType.body, OctoColors.TextMuted, Modifier.padding(Space.L), maxLines = 4)
            return
        }
        val list = rememberLazyListState()
        LazyColumn(Modifier.weight(1f).scrollbar(list), list, contentPadding = PaddingValues(start = Space.S, end = Space.S, top = Space.Xs, bottom = Space.Xl)) {
            items(rows, key = { it.key }) { row ->
                DownloadLine(
                    row,
                    // A higher quality copy still waiting its turn has no log yet.
                    onOpen = row.logKey?.let { key -> { model.showLog(key) } },
                    onFind = row.findId?.let { id -> { model.find(id, row.title, row.logKey) } },
                    onClear = { model.clear(row.key) },
                )
            }
        }
    }
}

// One download: its cover, its names, the line saying where it is, and a
// ring while it runs. Hovered, a finished one offers to leave the list, and
// any can be looked for again.
@Composable
private fun DownloadLine(row: DownloadRow, onOpen: (() -> Unit)?, onFind: (() -> Unit)?, onClear: () -> Unit) {
    val hover = remember { MutableInteractionSource() }
    val hovered by hover.collectIsHoveredAsState()
    Row(
        Modifier
            .fillMaxWidth()
            .hoverable(hover)
            .hoverLift(Corner.RowShape, clickable = onOpen != null)
            .clickable(enabled = onOpen != null, role = Role.Button) { onOpen?.invoke() }
            .semantics {
                contentDescription = "${row.title}, ${row.artist}"
                stateDescription = row.status
            }
            .padding(horizontal = Space.S, vertical = Space.S),
        verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.spacedBy(Space.L),
    ) {
        Cover(row.coverArt, Modifier.size(LineCover), shape = Corner.ArtSShape, placeholder = OctoIcons.Songs)
        Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(Space.Xxs)) {
            Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(Space.S)) {
                CutTxt(row.title, DesktopType.tableTitle, OctoColors.TextPrimary, Modifier.weight(1f, fill = false))
                kindLabel(row.kind)?.let { KindMark(it) }
            }
            if (row.artist.isNotBlank()) Txt(row.artist, DesktopType.meta, OctoColors.TextSecondary)
            Txt(row.status, DesktopType.meta, if (row.phase == RowPhase.Failed) OctoColors.SignalOrange else OctoColors.TextMuted, maxLines = 2)
        }
        when {
            hovered && onFind != null && row.finished -> Row {
                IconAction(OctoIcons.Search, FIND_SONGS, onFind, size = ControlHeight.S, iconSize = IconSize.Table, tint = OctoColors.TextSecondary)
                IconAction(OctoIcons.Close, "Clear this one", onClear, size = ControlHeight.S, iconSize = IconSize.Table, tint = OctoColors.TextSecondary)
            }
            !row.finished -> ProgressRing(row.fraction, size = IconSize.Transport)
            row.phase == RowPhase.Done -> Glyph(OctoIcons.Downloaded, size = IconSize.Table, tint = OctoColors.TextSecondary)
            else -> Glyph(OctoIcons.Info, size = IconSize.Table, tint = OctoColors.SignalOrange)
        }
    }
}

// "Higher quality" or "Picked", small beside a title.
@Composable
private fun KindMark(text: String) {
    Txt(
        text.uppercase(),
        DesktopType.label,
        OctoColors.TextSecondary,
        Modifier.clip(RoundedCornerShape(Corner.ArtS)).background(Chip).padding(horizontal = Space.S, vertical = Space.Xxs),
    )
}

// ---------------------------------------------------------------------------
// One download's log
// ---------------------------------------------------------------------------

@Composable
private fun DownloadLog(app: AppState, model: DownloadsModel, key: String, modifier: Modifier) {
    val rows by model.rows.collectAsState()
    val log by model.log.collectAsState()
    val problem by model.logProblem.collectAsState()
    // The list's row knows how an upgrade ended; the log's own row is the download.
    val row = rows.firstOrNull { it.logKey == key } ?: log?.let { rowOf(it) }
    val events = log?.event.orEmpty()
    val running = row?.finished == false
    val list = rememberLazyListState()
    // A running download opens on its newest step and keeps it in view; a
    // finished one opens at its start. Scrolling up lets go; back at the
    // end, or "Latest step", follows again.
    var follow by remember(key) { mutableStateOf<Boolean?>(null) }
    LaunchedEffect(key, row != null) { if (row != null && follow == null) follow = !row.finished }
    LaunchedEffect(list) {
        snapshotFlow { list.isScrollInProgress }.collect { scrolling ->
            if (!scrolling && follow != null) follow = !list.canScrollForward
        }
    }
    // By the line's own place: the list has not laid the new lines out yet.
    LaunchedEffect(events.size, follow) {
        if (follow == true && events.isNotEmpty()) list.animateScrollToItem(events.lastIndex)
    }
    Column(modifier) {
        Row(Modifier.fillMaxWidth().padding(horizontal = Space.L), verticalAlignment = Alignment.CenterVertically) {
            IconAction(OctoIcons.Back, "Back to downloads", model::showList, size = ControlHeight.M, iconSize = IconSize.Toolbar, tint = OctoColors.TextSecondary)
            Spacer(Modifier.weight(1f))
            row?.findId?.let { id -> TextAction(FIND_SONGS, { model.find(id, row.title, key) }, icon = OctoIcons.Search) }
            if (row?.finished == true) TextAction("Clear", { model.clear(row.key); model.showList() })
        }
        // The song and where it is stay put; only the steps scroll.
        if (row != null) LogHead(row, events, Modifier.padding(horizontal = Space.L))
        problem?.let { Txt(it, DesktopType.meta, OctoColors.SignalOrange, Modifier.padding(horizontal = Space.L, vertical = Space.S), maxLines = 2) }
        Separator(Modifier.padding(top = Space.L))
        Box(Modifier.weight(1f).fillMaxWidth()) {
            LazyColumn(Modifier.fillMaxSize().scrollbar(list), state = list, contentPadding = PaddingValues(start = Space.L, end = Space.L, top = Space.L, bottom = Space.Xl)) {
                if (log == null && problem == null) item(key = "wait") { ProgressRing(null, size = IconSize.Transport) }
                itemsIndexed(events, key = { index, _ -> index }) { index, line ->
                    LogLine(line, last = index == events.lastIndex, live = running && index == events.lastIndex)
                }
            }
            if (follow == false && running && list.canScrollForward) {
                GlazeCapsule(OctoIcons.Downloading, "Latest step", { follow = true }, Modifier.align(Alignment.BottomCenter).padding(bottom = Space.L))
            }
        }
    }
}

// The song, the steps it walks with the one it is on, and the copy being
// fetched.
@Composable
private fun LogHead(row: DownloadRow, events: List<AcquisitionEvent>, modifier: Modifier = Modifier) {
    Column(modifier.fillMaxWidth().padding(top = Space.S), verticalArrangement = Arrangement.spacedBy(Space.L)) {
        Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(Space.L)) {
            Cover(row.coverArt, Modifier.size(HeadCover), shape = Corner.ArtMShape, placeholder = OctoIcons.Songs)
            Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(Space.Xxs)) {
                Txt(row.title, DesktopType.emphasis, maxLines = 2)
                val by = listOfNotNull(row.artist.takeIf(String::isNotBlank), row.album?.takeIf(String::isNotBlank))
                if (by.isNotEmpty()) Txt(by.joinToString(" · "), DesktopType.meta, OctoColors.TextSecondary, maxLines = 2)
            }
        }
        Steps(row, stepOf(row, events))
        Column(verticalArrangement = Arrangement.spacedBy(Space.S)) {
            Txt(row.status, DesktopType.table, if (row.phase == RowPhase.Failed) OctoColors.SignalOrange else OctoColors.TextPrimary, maxLines = 3)
            val facts = listOfNotNull(row.quality, row.source, kindLabel(row.kind))
            if (facts.isNotEmpty()) Row(horizontalArrangement = Arrangement.spacedBy(Space.Xs)) { facts.forEach { Tag(it) } }
        }
    }
}

// The four steps as a strip: done ones filled, the one it is on filling
// with the file while it downloads (breathing while nobody can tell how
// far), and the ones still to come faint.
@Composable
private fun Steps(row: DownloadRow, at: Int) {
    val failed = row.phase == RowPhase.Failed
    val pulse = if (row.finished || row.fraction != null) 1f else rememberPulse()
    Row(
        Modifier.fillMaxWidth().semantics(mergeDescendants = true) {
            contentDescription = if (at >= DownloadStep.entries.size) "Every step done" else "Step ${at + 1} of ${DownloadStep.entries.size}, ${DownloadStep.entries[at].label}"
        },
        horizontalArrangement = Arrangement.spacedBy(Space.Xs),
    ) {
        DownloadStep.entries.forEach { step ->
            val index = step.ordinal
            val target = when {
                index < at -> 1f
                index > at -> 0f
                failed -> 1f
                row.phase == RowPhase.Downloading -> row.fraction ?: 0.5f
                else -> 0.5f
            }
            val fill = when {
                failed && index == at -> OctoColors.SignalOrange
                row.phase == RowPhase.Done -> OctoColors.SignalGreen
                else -> OctoColors.TextPrimary
            }
            val shown by animateFloatAsState(target, octoTween(motionScale(), OctoDuration.Neutral), label = "step")
            val alpha = if (index == at && !row.finished) pulse else 1f
            Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(Space.Xs)) {
                Canvas(Modifier.fillMaxWidth().height(StepLine)) {
                    val round = CornerRadius(size.height / 2)
                    drawRoundRect(Color.White.copy(alpha = 0.14f), cornerRadius = round)
                    if (shown > 0f) drawRoundRect(fill.copy(alpha = alpha), size = Size(size.width * shown, size.height), cornerRadius = round)
                }
                Txt(
                    step.label,
                    DesktopType.meta,
                    when {
                        failed && index == at -> OctoColors.SignalOrange
                        index == at && !row.finished -> OctoColors.TextPrimary
                        index < at || row.phase == RowPhase.Done -> OctoColors.TextSecondary
                        else -> OctoColors.TextMuted
                    },
                )
            }
        }
    }
}

// A slow breath, for the step whose end nobody can tell yet.
@Composable
private fun rememberPulse(): Float {
    if (motionScale().distance == 0f) return 1f
    val pulse = rememberInfiniteTransition(label = "pulse")
    val alpha by pulse.animateFloat(0.45f, 1f, infiniteRepeatable(tween(900), RepeatMode.Reverse), label = "alpha")
    return alpha
}

// A small fact in a soft capsule: "FLAC 16-bit 44.1 kHz", "Soulseek".
@Composable
private fun Tag(text: String) {
    Txt(text, DesktopType.meta, OctoColors.TextSecondary, Modifier.clip(RoundedCornerShape(Corner.ArtS)).background(Chip).padding(horizontal = Space.S, vertical = Space.Xxs))
}

// One line of the log: its mark on the thread that joins the lines, the
// words with their time, and the copies a search offered when it is about
// them. The newest line of a running download turns while it waits.
@Composable
private fun LogLine(line: AcquisitionEvent, last: Boolean, live: Boolean) {
    val mark = markOf(line.logKind)
    Row(Modifier.fillMaxWidth().height(IntrinsicSize.Min), horizontalArrangement = Arrangement.spacedBy(Space.M)) {
        Column(Modifier.width(MarkSize).fillMaxHeight(), horizontalAlignment = Alignment.CenterHorizontally) {
            Box(Modifier.size(MarkSize).clip(CircleShape).background(if (live) LiveFill else markFill(mark)), contentAlignment = Alignment.Center) {
                if (live && mark != LogMark.Done && mark != LogMark.Failed) {
                    ProgressRing(null, size = IconSize.Inline)
                } else {
                    Glyph(markIcon(mark), size = IconSize.Inline - Space.Xxs, tint = markTint(mark))
                }
            }
            if (!last) Box(Modifier.width(FrameSize.Hairline).weight(1f).background(SeparatorColor))
        }
        Column(Modifier.weight(1f).padding(bottom = Space.L), verticalArrangement = Arrangement.spacedBy(Space.Xxs)) {
            Row(verticalAlignment = Alignment.Top) {
                Txt(
                    line.text,
                    if (live) DesktopType.tableTitle else DesktopType.table,
                    if (mark == LogMark.Failed) OctoColors.SignalOrange else OctoColors.TextPrimary,
                    Modifier.weight(1f).padding(top = Space.Xxs),
                    maxLines = 3,
                )
                Txt(logTime(line.at), DesktopType.meta, OctoColors.TextMuted, Modifier.padding(start = Space.S, top = Space.Xxs))
            }
            line.detail?.let { Txt(it, DesktopType.meta, OctoColors.TextMuted, maxLines = 4) }
            if (line.candidate.isNotEmpty()) Copies(line.candidate)
        }
    }
}

// The copies a search offered, on one soft card: the first few, then the
// rest on asking.
@Composable
private fun Copies(copies: List<FoundCandidate>) {
    var all by remember(copies) { mutableStateOf(false) }
    val shown = if (all) copies else copies.take(LOG_COPIES_SHOWN)
    Column(Modifier.fillMaxWidth().padding(top = Space.S).clip(Corner.ControlShape).background(Card).padding(vertical = Space.Xxs)) {
        shown.forEachIndexed { index, copy ->
            if (index > 0) Separator(Modifier.padding(horizontal = Space.M))
            CopyLine(copy, compact = true)
        }
        if (copies.size > LOG_COPIES_SHOWN) {
            TextAction(if (all) "Show fewer" else "Show all ${copies.size}", { all = !all }, Modifier.padding(start = Space.Xs, bottom = Space.Xxs))
        }
    }
}

private fun markIcon(mark: LogMark): ImageVector = when (mark) {
    LogMark.Queued -> OctoIcons.History
    LogMark.Search -> OctoIcons.Search
    LogMark.Found -> OctoIcons.Songs
    LogMark.Try -> OctoIcons.Download
    LogMark.Transfer -> OctoIcons.Downloading
    LogMark.Check -> OctoIcons.Check
    LogMark.Tags -> OctoIcons.Rename
    LogMark.Cover -> OctoIcons.Album
    LogMark.Lyrics -> OctoIcons.Lyrics
    LogMark.Library -> OctoIcons.Library
    LogMark.Done -> OctoIcons.Downloaded
    LogMark.Failed -> OctoIcons.Close
    LogMark.Note -> OctoIcons.Info
}

private fun markTint(mark: LogMark): Color = when (mark) {
    LogMark.Done -> OctoColors.SignalGreen
    LogMark.Failed -> OctoColors.SignalOrange
    else -> OctoColors.TextSecondary
}

private fun markFill(mark: LogMark): Color = when (mark) {
    LogMark.Done -> OctoColors.SignalGreen.copy(alpha = 0.16f)
    LogMark.Failed -> OctoColors.SignalOrange.copy(alpha = 0.16f)
    else -> Chip
}

// ---------------------------------------------------------------------------
// Find songs
// ---------------------------------------------------------------------------

@Composable
private fun FindSongs(app: AppState, model: DownloadsModel, view: DrawerView.Find, modifier: Modifier) {
    val found by model.found.collectAsState()
    val problem by model.findProblem.collectAsState()
    val picked by model.picked.collectAsState()
    val question by model.question.collectAsState()
    val searching = found?.searching != false && problem == null
    val list = rememberLazyListState()
    // A copy that is not better than the library's: the server's question,
    // in a dialog of its own.
    LaunchedEffect(question) {
        question?.let { askReplaceAnyway(app, model, it, found?.song?.title?.takeIf(String::isNotBlank) ?: view.title) }
    }
    LazyColumn(modifier.scrollbar(list), list, contentPadding = PaddingValues(start = Space.L, end = Space.L, top = Space.S, bottom = Space.Xl)) {
        item(key = "bar") {
            Row(Modifier.fillMaxWidth(), verticalAlignment = Alignment.CenterVertically) {
                IconAction(
                    OctoIcons.Back,
                    if (view.from != null) "Back to the log" else "Back to downloads",
                    { view.from?.let(model::showLog) ?: model.showList() },
                    size = ControlHeight.M, iconSize = IconSize.Toolbar, tint = OctoColors.TextSecondary,
                )
                Txt(FIND_SONGS, DesktopType.emphasis, OctoColors.TextPrimary, Modifier.weight(1f).padding(start = Space.Xs))
                TextAction("Search again", model::searchAgain, enabled = !searching, icon = OctoIcons.Search)
            }
        }
        item(key = "head") { FindHead(view, found, model.asksFirst) }
        found?.source?.let { sources -> item(key = "sources") { Sources(sources) } }
        problem?.let { item(key = "problem") { Txt(it, DesktopType.meta, OctoColors.SignalOrange, Modifier.padding(vertical = Space.S), maxLines = 3) } }
        found?.error?.let { item(key = "error") { Txt(it, DesktopType.meta, OctoColors.SignalOrange, Modifier.padding(vertical = Space.S), maxLines = 3) } }
        picked?.takeIf { !it.queued }?.detail?.let { item(key = "picked") { Txt(it, DesktopType.meta, OctoColors.SignalOrange, Modifier.padding(vertical = Space.S), maxLines = 3) } }
        item(key = "rule") { Separator(Modifier.padding(vertical = Space.M)) }
        val copies = found?.candidate.orEmpty()
        if (copies.isEmpty() && !searching) item(key = "none") { Txt("Nothing found on your sources.", DesktopType.body, OctoColors.TextMuted) }
        // The list still grows while sources answer, so a copy is picked
        // only once it is done.
        if (copies.isNotEmpty() && found?.searching == true) item(key = "wait") { Txt(FIND_PICK_WAIT, DesktopType.meta, OctoColors.TextMuted, Modifier.padding(bottom = Space.S)) }
        val shown = found
        items(copies, key = ::copyKey) { copy ->
            CopyLine(copy, compact = false, onPick = if (shown != null && canPick(shown, copy)) ({ pickCopy(app, model, shown, copy) }) else null)
        }
    }
}

// The song looked for, the library's copy of it, and what picking does.
@Composable
private fun FindHead(view: DrawerView.Find, found: FoundSongs?, asksFirst: Boolean) {
    val song = found?.song
    Row(Modifier.fillMaxWidth().padding(top = Space.S), verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(Space.L)) {
        Cover(song?.coverArt ?: view.id, Modifier.size(HeadCover), shape = Corner.ArtMShape, placeholder = OctoIcons.Songs)
        Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(Space.Xxs)) {
            Txt(song?.title?.takeIf(String::isNotBlank) ?: view.title, DesktopType.emphasis, maxLines = 2)
            song?.artist?.takeIf(String::isNotBlank)?.let { Txt(it, DesktopType.meta, OctoColors.TextSecondary) }
            song?.album?.takeIf(String::isNotBlank)?.let { Txt(it, DesktopType.meta, OctoColors.TextMuted) }
        }
    }
    if (song != null) {
        Column(Modifier.fillMaxWidth().padding(top = Space.M), verticalArrangement = Arrangement.spacedBy(Space.Xxs)) {
            ownedCopyText(song.quality, song.size)?.let { Txt(it, DesktopType.table, OctoColors.TextPrimary) }
            Txt(if (song.libraryId != null) findReplaces(asksFirst) else FIND_DOWNLOADS, DesktopType.meta, OctoColors.TextMuted, maxLines = 3)
        }
    }
}

// Each source and how its look is going.
@Composable
private fun Sources(sources: List<FindSourceState>) {
    Column(Modifier.fillMaxWidth().padding(top = Space.M), verticalArrangement = Arrangement.spacedBy(Space.Xs)) {
        sources.forEach { source ->
            Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(Space.S)) {
                when (source.state) {
                    FIND_SEARCHING -> ProgressRing(null, size = IconSize.Inline)
                    FIND_OFF -> Glyph(OctoIcons.Close, size = IconSize.Inline, tint = OctoColors.TextMuted)
                    "failed" -> Glyph(OctoIcons.Info, size = IconSize.Inline, tint = OctoColors.SignalOrange)
                    else -> Glyph(OctoIcons.Check, size = IconSize.Inline, tint = OctoColors.TextSecondary)
                }
                val words = when (source.state) {
                    FIND_SEARCHING -> "Searching"
                    else -> source.text ?: if (source.state == "failed") "Could not search" else "Done"
                }
                Txt("${source.name}: $words", DesktopType.meta, if (source.state == FIND_OFF) OctoColors.TextMuted else OctoColors.TextSecondary, maxLines = 2)
            }
        }
    }
}

// One copy: its kind on a badge, its title, the folder or album it sits
// in, its facts, and whether Octo would take it. On Find songs it can be
// picked; the song's cover is drawn once, over the list.
@Composable
private fun CopyLine(copy: FoundCandidate, compact: Boolean, onPick: (() -> Unit)? = null) {
    val hover = remember { MutableInteractionSource() }
    val hovered by hover.collectIsHoveredAsState()
    Row(
        Modifier
            .fillMaxWidth()
            .hoverable(hover)
            .then(if (onPick != null) Modifier.hoverLift(Corner.RowShape, clickable = false) else Modifier)
            .padding(vertical = Space.S, horizontal = if (compact) Space.M else Space.Xs),
        verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.spacedBy(if (compact) Space.M else Space.L),
    ) {
        Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(Space.Xxs)) {
            Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(Space.S)) {
                copyBadge(copy)?.let { Badge(it, lossless = isLosslessCopy(copy)) }
                CutTxt(candidateTitle(copy), if (compact) DesktopType.table else DesktopType.tableTitle, OctoColors.TextPrimary, Modifier.weight(1f, fill = false))
            }
            val where = listOfNotNull(copy.album?.takeIf(String::isNotBlank) ?: copy.folder, copy.file?.takeIf { copy.title != null && !compact })
            if (where.isNotEmpty()) CutTxt(where.joinToString(" · "), DesktopType.meta, OctoColors.TextMuted)
            Txt(badgeFacts(copy).joinToString(" · "), DesktopType.meta, OctoColors.TextSecondary, maxLines = 2)
            // Octo's order for a copy it would try; why not, for one it would pass over.
            val verdict = copy.rank?.let(::rankWords) ?: copy.note?.let { candidateVerdict(copy) }
            verdict?.let { Txt(it, DesktopType.meta, if (copy.rank == 1) OctoColors.TextPrimary else OctoColors.TextMuted, maxLines = 2) }
        }
        if (onPick != null) {
            IconAction(OctoIcons.Download, "Get this copy", onPick, size = ControlHeight.M, iconSize = IconSize.Toolbar, active = hovered, tint = if (hovered) OctoColors.TextPrimary else OctoColors.TextSecondary)
        }
    }
}

// A copy's kind, small and boxed: "FLAC" a little brighter than "MP3".
@Composable
private fun Badge(text: String, lossless: Boolean) {
    Txt(
        text,
        DesktopType.label,
        if (lossless) OctoColors.TextPrimary else OctoColors.TextSecondary,
        Modifier.clip(RoundedCornerShape(Corner.ArtS)).background(if (lossless) LosslessChip else Chip).padding(horizontal = Space.S, vertical = Space.None),
    )
}

// Picks a copy from the search `found`. Replacing a library song's copy is
// asked first; a song not in the library is simply fetched. The question
// goes away should another search take the list's place meanwhile.
private fun pickCopy(app: AppState, model: DownloadsModel, found: FoundSongs, copy: FoundCandidate) {
    if (found.song.libraryId == null) {
        model.pick(found.id, copy)
        return
    }
    app.popups.showCentred { close ->
        val now by model.found.collectAsState()
        LaunchedEffect(now?.id) { if (now?.id != found.id) close() }
        MenuTitle(found.song.title)
        PopupPadding {
            Txt(
                "Replace your copy with ${candidateFacts(copy).take(2).joinToString(", ")}? ${findReplaces(model.asksFirst)}",
                DesktopType.body, OctoColors.TextPrimary, maxLines = 6,
            )
            Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.spacedBy(Space.M, Alignment.End)) {
                GlazeCapsule(null, "Cancel", close)
                GlazeCapsule(OctoIcons.Lossless, "Replace it", {
                    close()
                    model.pick(found.id, copy)
                }, lit = true)
            }
        }
    }
}

// The server's question about a copy that is not better than the library's,
// word for word, under the song's whole title. "Replace anyway" sends the
// pick again to replace it all the same; "Keep mine", Escape or a click off
// the card sends nothing. The buttons stay in place under words that
// scroll, should they ever not fit. It goes away by itself once the
// question does (the search replaced, or the drawer closed).
private fun askReplaceAnyway(app: AppState, model: DownloadsModel, asked: PickQuestion, title: String) {
    app.popups.showCentred(width = 420.dp, scrim = true, scrollsItself = true) { close ->
        val now by model.question.collectAsState()
        LaunchedEffect(now) { if (now != asked) close() }
        var answered by remember { mutableStateOf(false) }
        DisposableEffect(Unit) { onDispose { if (!answered) model.keepMine(asked) } }
        Txt(
            title, DesktopType.emphasis, OctoColors.TextPrimary,
            Modifier.padding(start = Space.L, end = Space.L, top = Space.M, bottom = Space.S).semantics { heading() },
            maxLines = Int.MAX_VALUE,
        )
        val scroll = rememberScrollState()
        Box(Modifier.weight(1f, fill = false)) {
            Txt(
                asked.words, DesktopType.body, OctoColors.TextPrimary,
                Modifier.fillMaxWidth().verticalScroll(scroll).padding(horizontal = Space.L, vertical = Space.Xs),
                maxLines = Int.MAX_VALUE,
            )
            MoreBelow(scroll, Modifier.align(Alignment.BottomCenter))
        }
        Row(
            Modifier.fillMaxWidth().padding(start = Space.L, end = Space.L, top = Space.M, bottom = Space.S),
            horizontalArrangement = Arrangement.spacedBy(Space.M, Alignment.End),
            verticalAlignment = Alignment.CenterVertically,
        ) {
            GlazeCapsule(null, KEEP_MINE, close)
            AccentButton(REPLACE_ANYWAY, {
                answered = true
                model.replaceAnyway()
                close()
            }, size = ButtonSize.Medium, fill = OctoColors.Accent)
        }
    }
}

// A soft fade at the bottom of words that scroll, with a "More below"
// button that scrolls to their end; gone once the end shows.
@Composable
private fun MoreBelow(scroll: ScrollState, modifier: Modifier) {
    val scope = rememberCoroutineScope()
    val motion = motionScale()
    AnimatedVisibility(scroll.canScrollForward, modifier, enter = fadeIn(octoTween(motion, OctoDuration.Card)), exit = fadeOut(octoTween(motion, OctoDuration.Card))) {
        Box(
            Modifier.fillMaxWidth().height(48.dp).background(Brush.verticalGradient(listOf(Color.Transparent, MoreBelowFade))),
            contentAlignment = Alignment.BottomCenter,
        ) {
            Row(
                Modifier
                    .padding(bottom = Space.Xs)
                    .background(OctoColors.AccentSelected, PillShape)
                    .border(1.dp, SeparatorColor, PillShape)
                    .clickable(role = Role.Button, onClickLabel = MORE_BELOW) { scope.launch { scroll.animateScrollTo(scroll.maxValue) } }
                    .padding(horizontal = Space.M, vertical = Space.Xxs),
                verticalAlignment = Alignment.CenterVertically,
                horizontalArrangement = Arrangement.spacedBy(Space.Xs),
            ) {
                Txt(MORE_BELOW, DesktopType.label, OctoColors.TextPrimary)
                Glyph(OctoIcons.Collapse, size = 14.dp)
            }
        }
    }
}

private val PillShape = RoundedCornerShape(50)
private val MoreBelowFade = Color(0xF0141416)
private val LineCover = RowHeight.Regular
private val HeadCover = FrameSize.PlayerCover + Space.Xs
private val MarkSize = IconSize.Transport + Space.Xxs
private val StepLine = Space.Xs
private val Chip = Color.White.copy(alpha = 0.08f)
private val LosslessChip = Color.White.copy(alpha = 0.16f)
private val Card = Color.White.copy(alpha = 0.05f)
private val LiveFill = Color.White.copy(alpha = 0.14f)
