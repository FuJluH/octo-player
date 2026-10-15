package app.winters.octo.player

import androidx.compose.ui.graphics.Color
import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.combinedClickable
import androidx.compose.foundation.horizontalScroll
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.ColumnScope
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.lazy.rememberLazyListState
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.material3.SwipeToDismissBox
import androidx.compose.material3.SwipeToDismissBoxValue
import androidx.compose.material3.Text
import androidx.compose.material3.rememberSwipeToDismissBoxState
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.alpha
import androidx.compose.ui.hapticfeedback.HapticFeedbackType
import androidx.compose.ui.platform.LocalFocusManager
import androidx.compose.ui.platform.LocalHapticFeedback
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import app.winters.octo.ui.common.SongTitle
import app.winters.octo.design.GlassPopup
import app.winters.octo.design.GlassSheet
import app.winters.octo.design.GlazeInset
import app.winters.octo.design.OctoColors
import app.winters.octo.design.OctoIcons
import app.winters.octo.design.OctoType
import app.winters.octo.design.elevation3
import app.winters.octo.design.mix
import app.winters.octo.playback.NoSource
import app.winters.octo.playback.QueueEntry
import app.winters.octo.playback.queueSourceTitle
import app.winters.octo.playback.sourceRuns
import app.winters.octo.ui.common.Artwork
import app.winters.octo.ui.common.DragHandle
import app.winters.octo.ui.common.RemoveBackground
import app.winters.octo.ui.common.asLength
import app.winters.octo.ui.common.isOutsideLibrary
import app.winters.octo.ui.common.songs
import app.winters.octo.ui.common.GlassMenuAction
import app.winters.octo.ui.common.GlassMenuHeader
import app.winters.octo.ui.common.GlassMenuPage
import app.winters.octo.ui.common.GlassMenuSeparator
import app.winters.octo.ui.common.rememberOpenedBeside
import app.winters.octo.ui.playlist.NewPlaylistForm
import kotlinx.coroutines.launch
import dev.chrisbanes.haze.HazeState
import sh.calvin.reorderable.ReorderableItem
import sh.calvin.reorderable.rememberReorderableLazyListState

private val RowShape = RoundedCornerShape(12.dp)

// The sheet's own colour, so a row hides what is under it while it moves.
private val RowFill: Color get() = mix(OctoColors.Background, OctoColors.Accent, 0.05f)

// The song that is on, lit a little brighter than the sheet.
private val CurrentFill: Color get() = mix(OctoColors.BackgroundTertiary, OctoColors.Accent, 0.12f)

// Songs already played sit above the current one, dimmed.
private const val PLAYED_ALPHA = 0.5f

// The queue sheet over the player, a long working list, then the menu of
// one of its songs and the name form for saving the queue as a playlist,
// each a glass card floating over it. `backdrop` is what the cards frost.
@Composable
fun QueueSheets(model: PlayerViewModel, shuffle: Boolean, visible: Boolean, onDismiss: () -> Unit, backdrop: HazeState) {
    // The song whose menu is open, kept after closing so it can slide away.
    var menuOpen by remember { mutableStateOf(false) }
    var menuFor by remember { mutableStateOf<QueueMenuFor?>(null) }
    var saving by remember { mutableStateOf(false) }
    // Closing the name form puts the keyboard away with it.
    val focus = LocalFocusManager.current
    LaunchedEffect(saving) { if (!saving) focus.clearFocus() }

    GlassSheet(visible = visible, onDismiss = onDismiss) {
        val played by model.played.collectAsStateWithLifecycle()
        val upNext by model.upNext.collectAsStateWithLifecycle()
        QueueSheet(
            played = played,
            queue = upNext,
            shuffle = shuffle,
            actions = QueueActions(
                move = model::moveInQueue,
                remove = model::removeFromQueue,
                play = model::playAt,
                menu = { entry, place ->
                    menuFor = QueueMenuFor(entry, place)
                    menuOpen = true
                },
                clear = model::clearQueue,
                removePlayed = model::removePlayed,
                save = { saving = true },
            ),
        )
    }
    GlassPopup(
        visible = menuOpen,
        anchor = rememberOpenedBeside(menuOpen),
        onDismiss = { menuOpen = false },
        backdrop = backdrop,
        title = "Song in the queue",
    ) {
        val shown = menuFor ?: return@GlassPopup
        QueueRowMenu(shown, model, onDone = { menuOpen = false })
    }
    GlassPopup(
        visible = saving,
        anchor = rememberOpenedBeside(saving),
        onDismiss = { saving = false },
        backdrop = backdrop,
        title = "Save as playlist",
    ) {
        NewPlaylistForm { name ->
            model.saveQueueAsPlaylist(name)
            saving = false
        }
    }
}

// Where a song sits relative to the one playing.
enum class QueuePlace { Played, Current, Upcoming }

class QueueMenuFor(val entry: QueueEntry, val place: QueuePlace)

// What the queue sheet's rows and tools do.
class QueueActions(
    val move: (from: Int, to: Int) -> Unit,
    val remove: (QueueEntry) -> Unit,
    val play: (Int) -> Unit,
    val menu: (QueueEntry, QueuePlace) -> Unit,
    val clear: () -> Unit,
    val removePlayed: () -> Unit,
    val save: () -> Unit,
)

// The "Up next" sheet: songs already played, dimmed, then the song that is
// on, then the rest of the queue in the order it will play, under headings
// by where each part came from ("Next from you", "Next from OK Computer"),
// as the desktop's queue shows it. It opens at
// the song that is on. Drag a song by its handle to move it, swipe it left
// to take it out, tap it to play it, long-press it for its menu. Moving is
// off while shuffle is on. Tools along the top clear the queue, take out
// the songs played, save it as a playlist, or scroll back to the song on.
@Composable
fun ColumnScope.QueueSheet(played: List<QueueEntry>, queue: List<QueueEntry>, shuffle: Boolean, actions: QueueActions) {
    val current = queue.firstOrNull()
    val upcoming = queue.drop(1)
    // The rows as drawn. A drag moves them at once; the queue catches up on drop.
    var rows by remember(upcoming) { mutableStateOf(upcoming) }
    val haptics = LocalHapticFeedback.current
    val scope = rememberCoroutineScope()
    val listState = rememberLazyListState(initialFirstVisibleItemIndex = played.size)
    val reorder = rememberReorderableLazyListState(listState) { from, to ->
        val a = rows.indexOfFirst { it.key == from.key }
        val b = rows.indexOfFirst { it.key == to.key }
        if (a >= 0 && b >= 0) {
            rows = rows.toMutableList().apply { add(b, removeAt(a)) }
            haptics.performHapticFeedback(HapticFeedbackType.SegmentFrequentTick)
        }
    }
    fun longPress(entry: QueueEntry, place: QueuePlace) {
        haptics.performHapticFeedback(HapticFeedbackType.LongPress)
        actions.menu(entry, place)
    }

    Column(Modifier.padding(start = 20.dp, end = 20.dp)) {
        Text("Up next", style = OctoType.section, color = OctoColors.TextPrimary)
        Text(queueSummary(rows), style = OctoType.caption, color = OctoColors.TextMuted)
    }
    Row(
        Modifier.fillMaxWidth().horizontalScroll(rememberScrollState()).padding(horizontal = 8.dp, vertical = 4.dp),
        horizontalArrangement = Arrangement.spacedBy(2.dp),
    ) {
        QueueTool("Now playing", enabled = current != null) { scope.launch { listState.animateScrollToItem(played.size) } }
        QueueTool("Clear", enabled = upcoming.isNotEmpty() || played.isNotEmpty(), onClick = actions.clear)
        QueueTool("Remove played", enabled = played.isNotEmpty(), onClick = actions.removePlayed)
        QueueTool("Save as playlist", enabled = current != null, onClick = actions.save)
    }
    LazyColumn(
        Modifier.weight(1f, fill = false),
        state = listState,
        contentPadding = PaddingValues(top = 4.dp, bottom = 12.dp),
    ) {
        items(played, key = { it.key }) { entry ->
            SongLine(
                entry,
                Modifier
                    .alpha(PLAYED_ALPHA)
                    .combinedClickable(
                        onClickLabel = "Play",
                        onLongClickLabel = "Song options",
                        onLongClick = { longPress(entry, QueuePlace.Played) },
                        onClick = { actions.play(entry.index) },
                    )
                    .padding(horizontal = 20.dp),
            )
        }
        if (current != null) {
            item(key = current.key) {
                GlazeInset(
                    fill = CurrentFill,
                    shape = RowShape,
                    modifier = Modifier.padding(horizontal = 12.dp, vertical = 4.dp).fillMaxWidth(),
                ) {
                    SongLine(
                        current,
                        Modifier
                            .combinedClickable(
                                onClickLabel = null,
                                onLongClickLabel = "Song options",
                                onLongClick = { longPress(current, QueuePlace.Current) },
                                onClick = {},
                            )
                            .padding(horizontal = 8.dp),
                    )
                }
            }
        }
        if (shuffle && rows.isNotEmpty()) {
            item(key = "shuffle-note") {
                Text(
                    "Turn off shuffle to reorder",
                    style = OctoType.caption,
                    color = OctoColors.TextMuted,
                    modifier = Modifier.padding(horizontal = 20.dp, vertical = 8.dp),
                )
            }
        }
        // What is to come, part by part. A single list with no name needs
        // no heading under "Up next".
        val runs = sourceRuns(rows) { it.source }
        val headed = runs.size > 1 || runs.singleOrNull()?.first.let { it != null && it != NoSource }
        runs.forEach { (source, run) ->
            if (headed) item(key = "part:${run.first().key}") { PartHeading(queueSourceTitle(source)) }
            items(run, key = { it.key }) { entry ->
                ReorderableItem(reorder, key = entry.key, enabled = !shuffle) { dragging ->
                    // Moves the song in the queue to the place of the one it landed on.
                    val drop = {
                        val landed = rows.indexOfFirst { it.key == entry.key }
                        val to = upcoming.getOrNull(landed)?.index
                        if (to != null && to != entry.index) actions.move(entry.index, to)
                    }
                    val swipe = rememberSwipeToDismissBoxState()
                    SwipeToDismissBox(
                        state = swipe,
                        enableDismissFromStartToEnd = false,
                        gesturesEnabled = !dragging,
                        onDismiss = {
                            rows = rows.filterNot { it.key == entry.key }
                            actions.remove(entry)
                        },
                        backgroundContent = { RemoveBackground(swipe.dismissDirection == SwipeToDismissBoxValue.EndToStart, RowShape) },
                    ) {
                        SongLine(
                            entry,
                            Modifier
                                .then(if (dragging) Modifier.elevation3(RowShape) else Modifier)
                                .background(RowFill, RowShape)
                                .combinedClickable(
                                    onClickLabel = "Play",
                                    onLongClickLabel = "Song options",
                                    onLongClick = { longPress(entry, QueuePlace.Upcoming) },
                                    onClick = { actions.play(entry.index) },
                                )
                                .padding(horizontal = 20.dp),
                            handle = if (shuffle) {
                                null
                            } else {
                                Modifier.draggableHandle(onDragStopped = drop)
                            },
                        )
                    }
                }
            }
        }
    }
}

// The heading over one part of what is to come.
@Composable
private fun PartHeading(title: String) {
    Text(
        title,
        style = OctoType.caption,
        color = OctoColors.TextMuted,
        modifier = Modifier.padding(start = 20.dp, end = 20.dp, top = 12.dp, bottom = 4.dp),
    )
}

// The count and length of the listener's own songs still to come, and how
// many Autoplay added after them.
private fun queueSummary(rows: List<QueueEntry>): String {
    val (auto, own) = rows.partition { it.autoplay }
    val base = "${songs(own.size)} · ${(own.sumOf { it.durationMs } / 1000).toInt().asLength()}"
    return if (auto.isEmpty()) base else "$base · ${auto.size} from Autoplay"
}

// One of the queue's tools: plain words, dimmed when there is nothing to do.
@Composable
private fun QueueTool(label: String, enabled: Boolean, onClick: () -> Unit) {
    Text(
        label,
        style = OctoType.label,
        color = if (enabled) OctoColors.TextSecondary else OctoColors.TextMuted,
        maxLines = 1,
        modifier = Modifier
            .clickable(enabled = enabled, role = Role.Button, onClick = onClick)
            .padding(horizontal = 12.dp, vertical = 10.dp),
    )
}

// A song's menu from the queue: play it next, take it out, or stop the
// music once it has played. The song that is on can only be the last one.
@Composable
private fun QueueRowMenu(shown: QueueMenuFor, model: PlayerViewModel, onDone: () -> Unit) {
    val entry = shown.entry
    GlassMenuPage(
        header = {
            GlassMenuHeader(entry.title, entry.artist) {
                Artwork(entry.artwork, 40.dp, shape = RoundedCornerShape(6.dp), outside = isOutsideLibrary(entry.trackId))
            }
            GlassMenuSeparator()
        },
    ) {
        if (shown.place != QueuePlace.Current) {
            GlassMenuAction(OctoIcons.PlayNext, "Play next", onClick = {
                model.playNextInQueue(entry)
                onDone()
            })
        }
        if (shown.place != QueuePlace.Played) {
            GlassMenuAction(OctoIcons.SleepTimer, "Stop after this song", onClick = {
                model.sleepAfter(entry)
                onDone()
            })
        }
        if (shown.place != QueuePlace.Current) {
            GlassMenuSeparator()
            GlassMenuAction(OctoIcons.Delete, "Remove from queue", onClick = {
                model.removeFromQueue(entry)
                onDone()
            })
        }
    }
}

// A song: artwork, title and artist, an "Autoplay" label on a song Autoplay
// added, and a drag handle when it can move.
@Composable
private fun SongLine(entry: QueueEntry, modifier: Modifier = Modifier, handle: Modifier? = null) {
    Row(
        modifier.fillMaxWidth().height(56.dp),
        verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.spacedBy(12.dp),
    ) {
        Artwork(entry.artwork, 44.dp, shape = RoundedCornerShape(6.dp), outside = isOutsideLibrary(entry.trackId))
        Column(Modifier.weight(1f)) {
            SongTitle(entry.title, explicit = entry.explicit, style = OctoType.bodySmall, color = OctoColors.TextPrimary)
            Text(entry.artist, style = OctoType.caption, color = OctoColors.TextMuted, maxLines = 1, overflow = TextOverflow.Ellipsis)
        }
        if (entry.autoplay) Text("Autoplay", style = OctoType.caption, color = OctoColors.TextMuted)
        if (handle != null) DragHandle(handle)
    }
}
