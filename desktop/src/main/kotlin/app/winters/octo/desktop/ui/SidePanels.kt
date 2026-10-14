package app.winters.octo.desktop.ui

import app.winters.octo.catalog.isExplicit
import androidx.compose.runtime.CompositionLocalProvider
import androidx.compose.ui.draw.drawBehind
import androidx.compose.ui.semantics.clearAndSetSemantics
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.focused
import androidx.compose.ui.semantics.selected
import androidx.compose.ui.semantics.semantics
import app.winters.octo.design.LocalFocusVisibility
import app.winters.octo.design.scrollbar
import app.winters.octo.design.LocalKeyboardHere
import app.winters.octo.design.LocalTabStops
import app.winters.octo.design.drawFocusRing
import app.winters.octo.design.menuKey
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.focusable
import androidx.compose.foundation.hoverable
import androidx.compose.foundation.interaction.MutableInteractionSource
import androidx.compose.foundation.interaction.collectIsHoveredAsState
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.ColumnScope
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.lazy.rememberLazyListState
import androidx.compose.runtime.Composable
import androidx.compose.runtime.DisposableEffect
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.produceState
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.ExperimentalComposeUiApi
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.alpha
import androidx.compose.ui.focus.FocusRequester
import androidx.compose.ui.focus.focusRequester
import androidx.compose.ui.focus.onFocusChanged
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.input.key.Key
import androidx.compose.ui.input.key.KeyEvent
import androidx.compose.ui.input.key.KeyEventType
import androidx.compose.ui.input.key.isAltPressed
import androidx.compose.ui.input.key.isCtrlPressed
import androidx.compose.ui.input.key.isMetaPressed
import androidx.compose.ui.input.key.isShiftPressed
import androidx.compose.ui.input.key.key
import androidx.compose.ui.input.key.onPreviewKeyEvent
import androidx.compose.ui.input.key.type
import androidx.compose.ui.input.pointer.PointerEventType
import androidx.compose.ui.input.pointer.isCtrlPressed
import androidx.compose.ui.input.pointer.isMetaPressed
import androidx.compose.ui.input.pointer.isPrimaryPressed
import androidx.compose.ui.input.pointer.isSecondaryPressed
import androidx.compose.ui.input.pointer.isShiftPressed
import androidx.compose.ui.input.pointer.onPointerEvent
import androidx.compose.ui.layout.onGloballyPositioned
import androidx.compose.ui.unit.IntOffset
import androidx.compose.ui.unit.IntRect
import app.winters.octo.design.ControlHeight
import app.winters.octo.design.Corner
import app.winters.octo.design.CutTxt
import app.winters.octo.design.DesktopType
import app.winters.octo.design.FrameSize
import app.winters.octo.design.GlassField
import app.winters.octo.design.GlazeCapsule
import app.winters.octo.design.GlazeSegments
import app.winters.octo.design.GlazeSelected
import app.winters.octo.design.HoverFill
import app.winters.octo.design.IconAction
import app.winters.octo.design.IconSize
import app.winters.octo.design.MenuRow
import app.winters.octo.design.MenuSeparator
import app.winters.octo.design.MenuTitle
import app.winters.octo.design.OctoColors
import app.winters.octo.design.OctoIcons
import app.winters.octo.design.OctoType
import app.winters.octo.design.PopupPadding
import app.winters.octo.design.RowHeight
import app.winters.octo.design.Separator
import app.winters.octo.design.Space
import app.winters.octo.design.TextAction
import app.winters.octo.design.Txt
import app.winters.octo.design.chromeFilm
import app.winters.octo.desktop.AppState
import app.winters.octo.desktop.player.isLineup
import app.winters.octo.desktop.SidePanel
import app.winters.octo.desktop.clearUpcoming
import app.winters.octo.desktop.dropIntoQueue
import app.winters.octo.desktop.library.Cover
import app.winters.octo.desktop.library.TableSelection
import app.winters.octo.desktop.library.lengthText
import app.winters.octo.desktop.lyrics.LyricsMenuButton
import app.winters.octo.desktop.lyrics.LyricsView
import app.winters.octo.desktop.moveToEnd
import app.winters.octo.desktop.moveToNext
import app.winters.octo.desktop.player.PlayerState
import app.winters.octo.desktop.player.QueueEntry
import app.winters.octo.desktop.player.QueueSection
import app.winters.octo.desktop.player.SectionKind
import app.winters.octo.desktop.player.queueSections
import app.winters.octo.desktop.player.queueSummary
import app.winters.octo.desktop.removePlayed
import app.winters.octo.desktop.removeQueued
import app.winters.octo.desktop.saveQueueAsPlaylist
import app.winters.octo.desktop.setAutoplay
import app.winters.octo.desktop.undoQueue
import dev.chrisbanes.haze.HazeState
import java.time.LocalDateTime
import kotlinx.coroutines.delay
import kotlinx.coroutines.launch
import sh.calvin.reorderable.ReorderableItem
import sh.calvin.reorderable.rememberReorderableLazyListState

// The panel down the right of the frame, in its glass: the queue, the
// lyrics, or the song's details, on tabs, so it can stay open while the
// listener browses, or the downloads drawer on its own. The lyrics' menu
// sits beside the tabs; the queue has its own over its list.
@Composable
fun ContextPanel(app: AppState, panel: SidePanel, backdrop: HazeState, modifier: Modifier = Modifier) {
    Column(modifier.chromeFilm(backdrop).padding(top = Space.M)) {
        Row(Modifier.fillMaxWidth().padding(start = Space.L, end = Space.S), verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(Space.Xs)) {
            // The downloads drawer is a sheet of its own, under its name; the
            // others share the tabs.
            if (panel == SidePanel.Downloads) {
                Txt(panel.title, DesktopType.section, OctoColors.TextPrimary, Modifier.padding(vertical = Space.S))
            } else {
                GlazeSegments(SidePanel.entries - SidePanel.Downloads, panel, { it.title }, app::showSidePanel)
            }
            Spacer(Modifier.weight(1f))
            if (panel == SidePanel.Lyrics) LyricsMenuButton(app)
            IconAction(OctoIcons.Close, "Close the panel", { app.showSidePanel(null) }, size = ControlHeight.M, iconSize = IconSize.Toolbar)
        }
        when (panel) {
            SidePanel.Queue -> QueueList(app)
            SidePanel.Lyrics -> LyricsView(app, Modifier.fillMaxSize())
            SidePanel.Info -> InfoPanel(app, Modifier.fillMaxSize())
            SidePanel.Downloads -> DownloadsPanel(app, Modifier.fillMaxSize())
        }
    }
}

// What each tab is called.
private val SidePanel.title: String
    get() = when (this) {
        SidePanel.Queue -> "Queue"
        SidePanel.Lyrics -> "Lyrics"
        SidePanel.Info -> "Info"
        SidePanel.Downloads -> "Downloads"
    }

// One line of the queue's list: a part's heading, or a song.
private sealed interface QueueItem {
    val key: String

    data class Heading(val section: QueueSection, override val key: String) : QueueItem

    data class Song(val entry: QueueEntry, val kind: SectionKind) : QueueItem {
        override val key: String get() = songKey(entry.key)
    }
}

private fun songKey(key: Long) = "song:$key"

// The list's lines, part by part.
private fun itemsOf(sections: List<QueueSection>): List<QueueItem> = buildList {
    sections.forEachIndexed { i, section ->
        add(QueueItem.Heading(section, "part:$i:${section.kind}"))
        section.entries.forEach { add(QueueItem.Song(it, section.kind)) }
    }
}

// The queue, in parts: Played (the last few, or all when opened), Now
// playing, then what is to come by where it came from ("Next from you",
// "Next from OK Computer"). Songs are picked like a table's rows (click,
// Ctrl, Shift, the arrow keys). Drag a song by any part of its row to move
// it (with the others picked); Alt+Up and Alt+Down move the picked songs;
// Delete takes them out; Enter or a double click plays one; Ctrl+Z takes
// the last edit back. A right click opens the song menu with the queue's
// own moves. Over it, a quiet line says how long is left, with the
// queue's menu beside it. Songs dragged here from a list go above or below
// the song to come they are dropped on, next when dropped on the one
// playing, and last anywhere else in the panel.
@OptIn(ExperimentalComposeUiApi::class)
@Composable
fun QueueList(app: AppState, modifier: Modifier = Modifier.fillMaxSize()) {
    val state by app.player.state.collectAsState()
    // A lineup of stations shows its stations, to switch between.
    if (state.live != null && isLineup(state.queue.map { it.song })) return LiveLineupList(app, state, modifier)
    var playedOpen by remember { mutableStateOf(false) }
    val sections = remember(state.played, state.current, state.upcoming, playedOpen) { queueSections(state, playedOpen) }
    val shown = remember(sections) { itemsOf(sections) }
    // The lines as drawn. A drag moves them at once; the queue catches up on drop.
    var items by remember(shown) { mutableStateOf(shown) }
    val songs = remember(shown) { shown.filterIsInstance<QueueItem.Song>() }
    val order = remember(songs) { songs.map { it.entry.key.toString() } }
    val selection = remember { TableSelection() }
    LaunchedEffect(order) { selection.keepOnly(order.toHashSet()) }
    val list = rememberLazyListState(initialFirstVisibleItemIndex = shown.indexOfFirst { it is QueueItem.Heading && it.section.kind == SectionKind.NowPlaying }.coerceAtLeast(0))
    val focus = remember { FocusRequester() }
    val lists = LocalListFocus.current
    var hasFocus by remember { mutableStateOf(false) }
    DisposableEffect(Unit) { onDispose { if (hasFocus) lists.active = false } }
    val scope = rememberCoroutineScope()
    val clicks = remember { QueueClicks() }
    val pointer = LocalPointer.current
    val drag = LocalDrag.current

    val reorder = rememberReorderableLazyListState(list) { from, to ->
        val a = items.indexOfFirst { it.key == from.key }
        val b = items.indexOfFirst { it.key == to.key }
        if (a >= 0 && b >= 0) items = items.toMutableList().apply { add(b, removeAt(a)) }
    }

    fun pickedEntries(): List<QueueEntry> = songs.map { it.entry }.filter { it.key.toString() in selection.picked }

    // The picked songs that can move or come out: any but the one playing.
    fun movable(): List<Long> {
        val playing = app.player.state.value.current?.key
        return pickedEntries().map { it.key }.filter { it != playing }
    }

    // A song let go after a drag: it moves (with the others picked) to play
    // before the song now under it.
    fun dropped(entry: QueueEntry) {
        val picked = movable()
        val moving = if (entry.key in picked) picked else listOf(entry.key)
        val at = items.indexOfFirst { it.key == songKey(entry.key) }
        val under = items.drop(at + 1).filterIsInstance<QueueItem.Song>().firstOrNull { it.entry.key !in moving }?.entry
        val coming = app.player.state.value.upcoming
        val wasUnder = coming.drop(coming.indexOfFirst { it.key == entry.key } + 1).firstOrNull { it.key !in moving }
        if (moving.size == 1 && under?.key == wasUnder?.key) {
            items = shown
            return
        }
        app.player.move(moving, under?.key)
    }

    fun openMenu(at: IntOffset) {
        val picked = pickedEntries().ifEmpty { return }
        val keys = movable()
        app.popups.showAt(at) { close ->
            SongMenu(
                app,
                picked.map { it.song },
                close,
                outside = app.anyOutside(picked.map { it.song }),
                place = SongPlace.Queue(keys),
                extra = if (keys.isEmpty()) null else ({ QueueMoves(app, picked, keys, close) }),
            )
        }
    }

    fun reveal(key: String) {
        val index = items.indexOfFirst { it is QueueItem.Song && it.entry.key.toString() == key }.takeIf { it >= 0 } ?: return
        scope.launch {
            val shownNow = list.layoutInfo.visibleItemsInfo
            val first = shownNow.firstOrNull()?.index ?: 0
            val last = shownNow.lastOrNull()?.index ?: 0
            when {
                index <= first -> list.scrollToItem((index - 1).coerceAtLeast(0))
                index >= last -> list.scrollToItem((index - shownNow.size + 3).coerceAtLeast(0))
            }
        }
    }

    // Moves the picked songs still to come one place up or down, together.
    fun shiftPicked(down: Boolean) {
        val coming = app.player.state.value.upcoming
        val picked = coming.filter { it.key.toString() in selection.picked }.map { it.key }
        if (picked.isEmpty()) return
        if (down) {
            val last = coming.indexOfLast { it.key in picked }
            if (last >= coming.lastIndex) return
            app.player.move(picked, coming.getOrNull(last + 2)?.key)
        } else {
            val first = coming.indexOfFirst { it.key in picked }
            if (first <= 0) return
            app.player.move(picked, coming[first - 1].key)
        }
        selection.focus?.let(::reveal)
    }

    fun onKey(event: KeyEvent): Boolean {
        if (event.type != KeyEventType.KeyDown) return false
        val command = if (app.mac) event.isMetaPressed else event.isCtrlPressed
        if (command && event.key == Key.Z) {
            app.undoQueue()
            return true
        }
        if (order.isEmpty()) return false
        fun step(by: Int): Boolean {
            selection.move(by, event.isShiftPressed, order)?.let(::reveal)
            return true
        }
        return when {
            event.isAltPressed && event.key == Key.DirectionUp -> true.also { shiftPicked(down = false) }
            event.isAltPressed && event.key == Key.DirectionDown -> true.also { shiftPicked(down = true) }
            event.key == Key.DirectionDown -> step(1)
            event.key == Key.DirectionUp -> step(-1)
            event.key == Key.MoveHome -> step(-order.size)
            event.key == Key.MoveEnd -> step(order.size)
            command && event.key == Key.A -> true.also { selection.selectAll(order) }
            event.key == Key.Enter -> true.also { selection.focus?.toLongOrNull()?.let(app.player::skipTo) }
            event.key == Key.Delete || (app.mac && event.key == Key.Backspace) -> {
                val keys = movable()
                if (keys.isNotEmpty()) {
                    app.removeQueued(keys)
                    selection.clear()
                }
                true
            }
            event.key == Key.Escape && selection.picked.isNotEmpty() -> true.also { selection.clear() }
            else -> false
        }
    }

    Column(
        modifier
            .then(if (drag.active) Modifier.dropTarget(QueueDrop, "Add to the queue") { app.addToQueue(it) } else Modifier)
            .background(if (isDropOver(QueueDrop)) DropLit else Color.Transparent)
            .focusRequester(focus)
            .onFocusChanged {
                hasFocus = it.hasFocus
                lists.active = it.hasFocus
            }
            .onPreviewKeyEvent(::onKey)
            .menuKey { panel ->
                val row = list.layoutInfo.visibleItemsInfo.firstOrNull { it.key == selection.focus?.toLongOrNull()?.let(::songKey) }
                if (selection.picked.isEmpty()) selection.focus?.let(selection::pickForMenu)
                openMenu(IntOffset(panel.left + panel.width / 4, panel.top + (row?.let { it.offset + it.size } ?: 0)))
            }
            .semantics { contentDescription = "Queue" }
            .focusable(),
    ) {
        QueueHeader(app, state)
        if (state.current == null) {
            Txt(
                "Nothing is queued. Play something, or right-click a song and pick Add to queue.",
                OctoType.bodySmall,
                OctoColors.TextMuted,
                Modifier.padding(horizontal = Space.Xl, vertical = Space.L),
                maxLines = 4,
            )
            return@Column
        }
        LazyColumn(
            Modifier.fillMaxSize().scrollbar(list),
            state = list,
            contentPadding = PaddingValues(start = Space.M, end = Space.M, top = Space.Xs, bottom = Space.Xl),
        ) {
            items(items, key = { it.key }) { item ->
                when (item) {
                    is QueueItem.Heading -> {
                        val heading = @Composable {
                            PartHeading(item.section, playedOpen) { playedOpen = !playedOpen }
                        }
                        // What is to come can be dragged past its headings.
                        if (item.section.kind == SectionKind.Coming) ReorderableItem(reorder, key = item.key, enabled = false) { heading() } else heading()
                    }
                    is QueueItem.Song -> {
                        val entry = item.entry
                        val key = entry.key.toString()
                        val row = @Composable { handle: Modifier, lifted: Boolean ->
                            QueueRow(
                                entry,
                                item.kind,
                                picked = key in selection.picked,
                                focused = hasFocus && selection.focus == key,
                                ringed = LocalFocusVisibility.current.keyboard,
                                lifted = lifted,
                                failed = app.failedSongs[entry.song.id] != null,
                                modifier = handle,
                                onPress = { primary, toggle, range ->
                                    runCatching { focus.requestFocus() }
                                    if (primary) {
                                        if (clicks.isDouble(key) && !toggle && !range) app.player.skipTo(entry.key)
                                        else selection.click(key, toggle, range, order)
                                    } else {
                                        selection.pickForMenu(key)
                                        openMenu(pointer.point)
                                    }
                                },
                                onRemove = { app.removeQueued(listOf(entry.key)) },
                            )
                        }
                        // Songs dragged from a list: above or below a song
                        // to come, or next on the one playing.
                        val dropId = "$QueueDrop:$key"
                        val next = item.kind == SectionKind.NowPlaying
                        val takes = drag.active && item.kind != SectionKind.Played
                        val target = if (!takes) {
                            Modifier
                        } else {
                            Modifier.dropTarget(dropId, if (next) "Play next" else "Add here") { songs ->
                                val at = if (next) 0 else app.player.state.value.upcoming.indexOfFirst { it.key == entry.key } + if (drag.below) 1 else 0
                                app.dropIntoQueue(songs, at)
                            }
                        }
                        val placed = @Composable { handle: Modifier, lifted: Boolean ->
                            Box(target) {
                                row(handle, lifted)
                                when {
                                    !takes -> {}
                                    next -> if (isDropOver(dropId)) Box(Modifier.matchParentSize().background(DropLit, Corner.RowShape))
                                    else -> DropLine(dropId)
                                }
                            }
                        }
                        if (item.kind == SectionKind.Coming) {
                            ReorderableItem(reorder, key = item.key) { dragging ->
                                placed(Modifier.draggableHandle(onDragStopped = { dropped(entry) }), dragging)
                            }
                        } else {
                            placed(Modifier, false)
                        }
                    }
                }
            }
        }
    }
}

private const val QueueDrop = "queue"

// The queue's own rows at the top of a song's menu there: play it now, or
// move the picked songs to play next or last.
@Composable
private fun ColumnScope.QueueMoves(app: AppState, picked: List<QueueEntry>, keys: List<Long>, close: () -> Unit) {
    val one = picked.singleOrNull()
    if (one != null) MenuRow("Play now", { app.player.skipTo(one.key); close() }, OctoIcons.Play)
    MenuRow("Move to next", { app.moveToNext(keys); close() }, OctoIcons.PlayNext)
    MenuRow("Move to the end", { app.moveToEnd(keys); close() }, OctoIcons.AddToQueue)
}

// A part's heading. Played folds to its last few songs, with a word to
// show the rest.
@Composable
private fun PartHeading(section: QueueSection, playedOpen: Boolean, togglePlayed: () -> Unit) {
    Row(
        Modifier.fillMaxWidth().padding(start = Space.M + Space.Xxs, top = Space.M, bottom = Space.Xs),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        Txt(section.title, OctoType.caption, OctoColors.TextMuted, Modifier.weight(1f))
        if (section.kind == SectionKind.Played && (section.hidden > 0 || playedOpen)) {
            TextAction(if (playedOpen) "Show fewer" else "Show ${section.hidden} more", togglePlayed)
        }
    }
}

// Songs already played are dimmed, as on the phone.
private const val PLAYED_ALPHA = 0.5f

// The playing song's row, tinted faintly with the cover's colour.
private const val PLAYING_TINT = 0.10f

private val FocusLine = Space.Xxs / 2

// One song in the queue: its cover, title and artist, and length. The
// picked ones sit in the darker inset pill; the playing one is lit.
@OptIn(ExperimentalComposeUiApi::class)
@Composable
private fun QueueRow(
    entry: QueueEntry,
    kind: SectionKind,
    picked: Boolean,
    focused: Boolean,
    ringed: Boolean,
    lifted: Boolean,
    failed: Boolean,
    modifier: Modifier,
    onPress: (primary: Boolean, toggle: Boolean, range: Boolean) -> Unit,
    onRemove: () -> Unit,
) {
    val song = entry.song
    val playing = kind == SectionKind.NowPlaying
    val interaction = remember { MutableInteractionSource() }
    val hovered by interaction.collectIsHoveredAsState()
    val keyColour = LocalKeyColour.current
    Box(
        modifier
            .fillMaxWidth()
            .height(RowHeight.Roomy)
            .hoverable(interaction)
            .onPointerEvent(PointerEventType.Press) { event ->
                val keys = event.keyboardModifiers
                when {
                    event.buttons.isSecondaryPressed -> onPress(false, false, false)
                    event.buttons.isPrimaryPressed -> onPress(true, keys.isCtrlPressed || keys.isMetaPressed, keys.isShiftPressed)
                }
            }
            .clearAndSetSemantics {
                contentDescription = queueSpeech(song.title, song.displayArtist ?: song.artist, lengthText(song.duration), kind, picked, failed, song.isExplicit)
                selected = picked
                this.focused = focused
            },
        contentAlignment = Alignment.CenterStart,
    ) {
        when {
            lifted -> Box(Modifier.matchParentSize().background(OctoColors.BackgroundTertiary, Corner.RowShape))
            picked -> GlazeSelected(Modifier.matchParentSize(), Corner.RowShape)
            playing -> Box(Modifier.matchParentSize().background(keyColour.copy(alpha = PLAYING_TINT), Corner.RowShape))
            hovered -> Box(Modifier.matchParentSize().background(HoverFill, Corner.RowShape))
        }
        if (focused) {
            if (ringed) Box(Modifier.matchParentSize().drawBehind { drawFocusRing(Corner.RowShape) })
            else Box(Modifier.matchParentSize().border(FocusLine, OctoColors.FocusRing, Corner.RowShape))
        }
        Row(
            Modifier
                .fillMaxWidth()
                .alpha(if (kind == SectionKind.Played && !hovered && !picked) PLAYED_ALPHA else 1f)
                .padding(horizontal = Space.M),
            verticalAlignment = Alignment.CenterVertically,
            horizontalArrangement = Arrangement.spacedBy(Space.M + Space.Xxs),
        ) {
            Cover(song.coverArt, Modifier.size(RowHeight.Roomy - Space.L), shape = Corner.ArtMShape, placeholder = OctoIcons.Songs)
            Column(Modifier.weight(1f)) {
                // The keyboard's row shows its cut title whole.
                CompositionLocalProvider(LocalKeyboardHere provides (focused && ringed)) {
                    MarkedTitle(song, DesktopType.tableTitle) { title ->
                        CutTxt(
                            song.title,
                            DesktopType.tableTitle,
                            when {
                                playing -> OctoColors.Accent
                                failed -> OctoColors.TextMuted
                                else -> OctoColors.TextPrimary
                            },
                            title,
                        )
                    }
                }
                CutTxt(song.displayArtist ?: song.artist.orEmpty(), DesktopType.meta, OctoColors.TextMuted)
            }
            if (hovered && !playing) {
                CompositionLocalProvider(LocalTabStops provides false) {
                    IconAction(OctoIcons.Close, "Remove from the queue", onRemove, size = ControlHeight.Xs, iconSize = IconSize.Inline, tint = OctoColors.TextSecondary)
                }
            } else {
                Txt(lengthText(song.duration), DesktopType.meta.copy(fontFeatureSettings = "tnum"), OctoColors.TextMuted)
            }
        }
    }
}

// What a screen reader says for a song in the queue.
internal fun queueSpeech(title: String, artist: String?, length: String, kind: SectionKind, picked: Boolean, failed: Boolean, explicit: Boolean = false): String = buildString {
    append(title)
    if (explicit) append(", explicit")
    artist?.takeIf(String::isNotBlank)?.let { append(", ").append(it) }
    if (length.isNotBlank()) append(", ").append(length)
    when (kind) {
        SectionKind.NowPlaying -> append(", now playing")
        SectionKind.Played -> append(", played")
        else -> {}
    }
    if (picked) append(", picked")
    if (failed) append(", couldn't play")
}

// Over the queue: how many songs are still to come, how long they last and
// when the music ends, and the queue's menu.
@Composable
private fun QueueHeader(app: AppState, state: PlayerState) {
    // The end time moves on while paused, so it is worked out again now and then.
    val now by produceState(LocalDateTime.now()) {
        while (true) {
            delay(SUMMARY_EVERY_MS)
            value = LocalDateTime.now()
        }
    }
    val summary = remember(state, now) { queueSummary(state, state.durationMs - app.player.positionMs(), now) }
    Row(
        Modifier.fillMaxWidth().padding(start = Space.L + Space.Xs, end = Space.S, top = Space.S),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        Txt(summary.orEmpty(), OctoType.caption, OctoColors.TextMuted, Modifier.weight(1f), maxLines = 2)
        QueueMenuButton(app, state)
    }
}

private const val SUMMARY_EVERY_MS = 15_000L

@Composable
private fun QueueMenuButton(app: AppState, state: PlayerState) {
    var anchor by remember { mutableStateOf(IntRect.Zero) }
    Box(Modifier.onGloballyPositioned { anchor = it.windowRect() }) {
        IconAction(
            OctoIcons.More,
            "Queue options",
            { app.popups.showUnder(anchor, width = FrameSize.Menu) { close -> QueueOptions(app, close) } },
            size = ControlHeight.M,
            iconSize = IconSize.Toolbar,
            active = state.stopAfterCurrent,
        )
    }
}

// The queue's menu: save it, take the last edit back, Autoplay and stop
// after this song, and last, clearing.
@Composable
private fun ColumnScope.QueueOptions(app: AppState, close: () -> Unit) {
    val now by app.player.state.collectAsState()
    val settings by app.settings.state.collectAsState()
    val autoplay = settings.playback.autoplay
    MenuRow("Save as playlist", { close(); saveQueueForm(app) }, OctoIcons.AddToPlaylist, enabled = now.current != null && app.connection != null)
    MenuRow("Undo", { app.undoQueue(); close() }, OctoIcons.Back, enabled = now.canUndo, detail = if (app.mac) "Cmd+Z" else "Ctrl+Z")
    MenuSeparator()
    MenuRow("Autoplay", { app.setAutoplay(!autoplay) }, OctoIcons.Radio, checked = autoplay)
    Txt(
        "When the queue ends, keep playing songs like the last one",
        OctoType.caption,
        OctoColors.TextMuted,
        Modifier.padding(start = Space.Wide + Space.Xxs, end = Space.Xl, bottom = Space.S),
        maxLines = 2,
    )
    MenuRow(
        "Stop after this song",
        { app.player.setStopAfterCurrent(!now.stopAfterCurrent); close() },
        OctoIcons.Pause,
        enabled = now.current != null,
        checked = now.stopAfterCurrent,
    )
    MenuSeparator()
    MenuRow("Clear upcoming", { app.clearUpcoming(); close() }, OctoIcons.Close, enabled = now.upcoming.isNotEmpty(), destructive = true)
    MenuRow("Remove played", { app.removePlayed(); close() }, OctoIcons.History, enabled = now.played.isNotEmpty(), destructive = true)
}

// A small form for naming the playlist the queue is saved as, in the
// middle of the window, like the sidebar's New playlist.
private fun saveQueueForm(app: AppState) {
    app.popups.showCentred { close ->
        var name by remember { mutableStateOf("") }
        MenuTitle("Save as playlist")
        PopupPadding {
            val save = {
                if (name.isNotBlank()) {
                    app.saveQueueAsPlaylist(name)
                    close()
                }
            }
            GlassField(name, { name = it }, Modifier.fillMaxWidth(), placeholder = "Name", onSubmit = save, onEscape = close)
            Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.spacedBy(Space.M + Space.Xxs, Alignment.End)) {
                GlazeCapsule(null, "Cancel", close)
                GlazeCapsule(null, "Save", save, lit = true, enabled = name.isNotBlank())
            }
        }
    }
}

// Tells a second click on the same row soon after the first.
private class QueueClicks {
    private var row: String? = null
    private var at = 0L

    fun isDouble(key: String): Boolean {
        val now = System.currentTimeMillis()
        val double = key == row && now - at < DOUBLE_CLICK_MS
        row = if (double) null else key
        at = now
        return double
    }
}

@Composable
fun PanelSeparator() = Separator(Modifier.padding(vertical = Space.S))
