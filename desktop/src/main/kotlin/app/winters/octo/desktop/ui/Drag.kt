package app.winters.octo.desktop.ui

import androidx.compose.ui.graphics.Color
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.BoxScope
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.offset
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.runtime.Composable
import androidx.compose.runtime.DisposableEffect
import androidx.compose.runtime.Stable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateMapOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.runtime.staticCompositionLocalOf
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.composed
import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.geometry.Rect
import androidx.compose.ui.layout.boundsInWindow
import androidx.compose.ui.layout.onGloballyPositioned
import androidx.compose.ui.unit.IntOffset
import app.winters.octo.design.Corner
import app.winters.octo.design.DesktopType
import app.winters.octo.design.Glaze
import app.winters.octo.design.GlazeLight
import app.winters.octo.design.Glyph
import app.winters.octo.design.IconSize
import app.winters.octo.design.OctoColors
import app.winters.octo.design.OctoIcons
import app.winters.octo.design.Space
import app.winters.octo.design.Txt
import app.winters.octo.desktop.library.TableRow
import app.winters.octo.subsonic.Song
import kotlin.math.roundToInt

// A place songs can be dropped: where it is in the window, what it says it
// will do ("Add to Late night"), and what it does with them. Where targets
// overlap, the higher `layer` wins (the floating player over the page),
// then the smaller (a queue row over the queue panel).
class DropTarget(val bounds: Rect, val action: String, val layer: Int = 0, val onDrop: (List<Song>) -> Unit)

// What a table's rows do with songs dropped on one: `action` is what the
// label says, `takes` whether a drag from there can land here at all, and
// `onDrop` gets the songs, where they came from, the row, and whether they
// go below it.
class RowDrop(
    val action: String,
    val takes: (SongPlace?) -> Boolean,
    val onDrop: (songs: List<Song>, from: SongPlace?, row: TableRow, below: Boolean) -> Unit,
)

// Songs being dragged across the window, from a song table to the queue or a
// playlist in the sidebar. The drag starts once the pointer has moved a
// little with a row held down; letting go over a target drops the songs
// there, anywhere else it does nothing.
@Stable
class DragState {
    var songs by mutableStateOf<List<Song>>(emptyList())
        private set

    // Where the pointer is, in the window.
    var at by mutableStateOf(Offset.Zero)
        private set

    // Where the songs came from, when the table knows (a playlist's
    // places), so a drop in the same playlist moves them.
    var from by mutableStateOf<SongPlace?>(null)
        private set

    private val targets = mutableStateMapOf<String, DropTarget>()

    val active: Boolean get() = songs.isNotEmpty()

    // The target under the pointer, if any.
    val over: Pair<String, DropTarget>?
        get() = if (!active) {
            null
        } else {
            targets.entries
                .filter { it.value.bounds.contains(at) }
                .maxWithOrNull(compareBy<Map.Entry<String, DropTarget>> { it.value.layer }.thenByDescending { it.value.bounds.width * it.value.bounds.height })
                ?.toPair()
        }

    // Whether the pointer is in the lower half of the target under it, for
    // rows that take songs above or below themselves.
    val below: Boolean get() = over?.second?.bounds?.let { at.y > it.center.y } ?: false

    fun start(songs: List<Song>, at: Offset, from: SongPlace? = null) {
        if (songs.isEmpty()) return
        this.songs = songs
        this.at = at
        this.from = from
    }

    fun move(to: Offset) {
        if (active) at = to
    }

    // Lets go: the songs go to the target under the pointer. Answers whether
    // they were dropped somewhere.
    fun drop(): Boolean {
        val target = over?.second
        // The target still sees the drag while it takes the songs.
        target?.onDrop(songs)
        cancel()
        return target != null
    }

    fun cancel() {
        songs = emptyList()
        from = null
    }

    fun place(id: String, target: DropTarget) {
        targets[id] = target
    }

    fun forget(id: String) {
        targets.remove(id)
    }

    // Where the target `id` is, for tests to aim at.
    internal fun boundsOf(id: String): Rect? = targets[id]?.bounds
}

val LocalDrag = staticCompositionLocalOf { DragState() }

// Makes this a place songs can be dropped. isDropOver tells it whether
// songs are being held over it now, for it to show.
fun Modifier.dropTarget(id: String, action: String, layer: Int = 0, onDrop: (List<Song>) -> Unit): Modifier = composed {
    val drag = LocalDrag.current
    DisposableEffect(id) { onDispose { drag.forget(id) } }
    onGloballyPositioned { drag.place(id, DropTarget(it.boundsInWindow(), action, layer, onDrop)) }
}

// Whether songs are being held over the target named `id`.
@Composable
fun isDropOver(id: String): Boolean = LocalDrag.current.over?.first == id

// What follows the pointer while songs are dragged: how many, or the one
// song's title, and what letting go here would do.
@Composable
fun DragLabel(drag: DragState) {
    if (!drag.active) return
    val songs = drag.songs
    val over = drag.over?.second
    val what = if (songs.size == 1) songs.single().title else "${songs.size} songs"
    Box(Modifier.offset { IntOffset(drag.at.x.roundToInt() + LabelOffset, drag.at.y.roundToInt() + LabelOffset) }) {
        Glaze(shape = Corner.ControlShape, light = GlazeLight.Lifted) {
            Row(Modifier.padding(horizontal = Space.L, vertical = Space.S), verticalAlignment = Alignment.CenterVertically) {
                Glyph(if (over != null) OctoIcons.AddToPlaylist else OctoIcons.Songs, Modifier.padding(end = Space.M), size = IconSize.Table, tint = if (over != null) OctoColors.TextPrimary else OctoColors.TextSecondary)
                Txt(if (over != null) "${over.action}: $what" else what, DesktopType.emphasis)
            }
        }
    }
}

// A place lit while songs are held over it: a wash of the accent.
val DropLit: Color get() = OctoColors.Accent.copy(alpha = 0.14f)

// Where songs held over the row `id` would land: a line along its top, or
// its foot when the pointer is in its lower half.
@Composable
fun BoxScope.DropLine(id: String) {
    val drag = LocalDrag.current
    if (drag.over?.first != id) return
    Box(Modifier.align(if (drag.below) Alignment.BottomStart else Alignment.TopStart).fillMaxWidth().height(Space.Xxs).background(OctoColors.Accent, CircleShape))
}

// The label sits just below and right of the pointer, in pixels.
private const val LabelOffset = 14
