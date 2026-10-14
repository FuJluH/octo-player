package app.winters.octo.ui.imports

import android.content.Context
import android.content.Intent
import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.compose.foundation.background
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.LazyListScope
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.lazy.itemsIndexed
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.text.KeyboardActions
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.DisposableEffect
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.text.input.ImeAction
import androidx.compose.ui.text.input.KeyboardType
import androidx.compose.ui.unit.dp
import androidx.core.net.toUri
import androidx.hilt.lifecycle.viewmodel.compose.hiltViewModel
import androidx.lifecycle.ViewModel
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import androidx.lifecycle.viewModelScope
import app.winters.octo.data.SessionRepository
import app.winters.octo.data.SessionState
import app.winters.octo.data.accountId
import app.winters.octo.design.AccentButton
import app.winters.octo.design.ButtonSize
import app.winters.octo.design.GlassInput
import app.winters.octo.design.GlazeButton
import app.winters.octo.design.OctoColors
import app.winters.octo.design.OctoSwitch
import app.winters.octo.design.OctoType
import app.winters.octo.subsonic.ImportListSummary
import app.winters.octo.subsonic.ImportOverview
import app.winters.octo.subsonic.ImportTrack
import app.winters.octo.subsonic.ImportTrackState
import app.winters.octo.subsonic.TrickleState
import app.winters.octo.ui.common.BackButton
import app.winters.octo.ui.common.DetailTopGap
import app.winters.octo.ui.common.ScreenTitle
import app.winters.octo.ui.common.SectionTitle
import app.winters.octo.ui.common.screenPadding
import dagger.hilt.android.lifecycle.HiltViewModel
import dagger.hilt.android.qualifiers.ApplicationContext
import kotlinx.coroutines.flow.distinctUntilChanged
import kotlinx.coroutines.flow.drop
import kotlinx.coroutines.flow.filter
import kotlinx.coroutines.flow.map
import kotlinx.coroutines.launch
import javax.inject.Inject

// The screen's state is the shared ImportModel, kept for as long as the
// screen is, so a wait for a file TuneMyMusic saves outlives the screen
// going to the background. Another server in use starts it over, as the
// desktop's does: nothing of the last server's lists stays.
@HiltViewModel
class ImportViewModel @Inject constructor(
    @ApplicationContext context: Context,
    sessions: SessionRepository,
    val inbox: ImportInbox,
) : ViewModel() {
    val model = ImportModel(
        { (sessions.state.value as? SessionState.SignedIn)?.session?.client },
        viewModelScope,
        openUrl = { openInBrowser(context, it) },
    )

    // Whether the screen is showing, so the new server is asked at once.
    private var showing = false

    init {
        viewModelScope.launch {
            sessions.state.filter { it !is SessionState.Loading }.map { it.accountId }.distinctUntilChanged().drop(1).collect {
                model.forget()
                if (showing) model.watch()
            }
        }
    }

    fun show() {
        showing = true
        model.watch()
    }

    fun hide() {
        showing = false
        model.stop()
    }

    override fun onCleared() = model.forget()
}

// Opens Import when another app shares a list to Octo.
@HiltViewModel
class ImportShellViewModel @Inject constructor(val inbox: ImportInbox) : ViewModel()

internal fun openInBrowser(context: Context, url: String) {
    runCatching { context.startActivity(Intent(Intent.ACTION_VIEW, url.toUri()).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)) }
}

// Import on an Octo server: get music from another service through a file
// TuneMyMusic saves, a shared file, a pasted list or a public link; see
// what the library has of each list, keep one as a playlist, fetch what it
// is missing, and follow the trickle. The server does the work; this shows
// what it says.
@Composable
fun ImportScreen(onBack: () -> Unit, owner: ImportViewModel = hiltViewModel()) {
    val context = LocalContext.current
    val vm = owner.model
    DisposableEffect(Unit) {
        owner.show()
        onDispose { owner.hide() }
    }
    val scope = rememberCoroutineScope()
    var pasting by rememberSaveable { mutableStateOf(false) }
    val sendFile: (android.net.Uri, String?) -> Unit = { uri, type -> scope.launch { sendPickedFile(context, vm, uri, type) } }
    val pick = rememberLauncherForActivityResult(OpenInDownloads()) { uri -> uri?.let { sendFile(it, null) } }
    val pickFile = { pick.launch(IMPORT_PICK_TYPES) }
    // A list shared to Octo is sent once the server is known to answer.
    val shared by owner.inbox.pending.collectAsStateWithLifecycle()
    val ready = vm.overview != null
    LaunchedEffect(shared, ready) {
        if (shared == null || !ready) return@LaunchedEffect
        when (val share = owner.inbox.take()) {
            is SharedImport.File -> sendFile(share.file, share.type)
            is SharedImport.Text -> vm.sendText(share.text, share.name ?: PASTED_LIST_NAME)
            null -> Unit
        }
    }
    Box(Modifier.fillMaxSize()) {
        LazyColumn(Modifier.fillMaxSize(), contentPadding = screenPadding(extraTop = DetailTopGap)) {
            item(key = "title") { ScreenTitle(IMPORT) }
            val overview = vm.overview
            if (overview == null) {
                item(key = "waiting") { Line(vm.problem ?: "Asking the server about your lists.") }
            } else {
                overview.libraryProblem?.let { item(key = "library") { Line(it, OctoColors.SignalOrange) } }
                val services = vm.services
                if (services != null) {
                    getMyMusic(vm, services, pickFile = pickFile, paste = { pasting = true })
                    vm.said?.let { item(key = "said") { Line(it, OctoColors.TextSecondary) } }
                    link(vm)
                } else {
                    link(vm)
                    vm.said?.let { item(key = "said") { Line(it, OctoColors.TextSecondary) } }
                }
                val opened = overview.lists.firstOrNull { it.id == vm.openId }
                if (opened != null) openedList(vm, opened) else lists(vm, overview)
                trickle(vm, overview)
            }
        }
        BackButton(onBack)
        PasteSheet(pasting, onDismiss = { pasting = false }) { text, name ->
            pasting = false
            vm.sendText(text, name)
        }
    }
}

@Composable
internal fun Line(text: String, color: androidx.compose.ui.graphics.Color = OctoColors.TextMuted) {
    Text(text, style = OctoType.bodySmall, color = color, modifier = Modifier.padding(horizontal = 20.dp, vertical = 6.dp))
}

// A public Spotify playlist or album by its link, which the server reads.
private fun LazyListScope.link(vm: ImportModel) {
    item(key = "link:title") { SectionTitle("Public link", Modifier.padding(top = 12.dp)) }
    item(key = "link") {
        var link by rememberSaveable { mutableStateOf("") }
        Column(Modifier.padding(horizontal = 20.dp, vertical = 8.dp), verticalArrangement = Arrangement.spacedBy(8.dp)) {
            Text("Share, then Copy link, on a Spotify playlist or album. A link shows Octo the first 100 songs.", style = OctoType.caption, color = OctoColors.TextMuted)
            val add = {
                if (link.isNotBlank()) {
                    vm.addLink(link)
                    link = ""
                }
            }
            Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                GlassInput(
                    link,
                    { link = it },
                    placeholder = "https://open.spotify.com/playlist/…",
                    modifier = Modifier.weight(1f),
                    keyboardOptions = KeyboardOptions(keyboardType = KeyboardType.Uri, imeAction = ImeAction.Done),
                    keyboardActions = KeyboardActions(onDone = { add() }),
                )
                GlazeButton("Add", add, size = ButtonSize.Medium, enabled = link.isNotBlank() && !vm.working)
            }
        }
    }
}

private fun LazyListScope.lists(vm: ImportModel, overview: ImportOverview) {
    item(key = "lists:title") { SectionTitle("Your lists", Modifier.padding(top = 8.dp)) }
    if (overview.lists.isEmpty()) {
        item(key = "lists:none") {
            Line(
                if (vm.services != null) "No lists yet. Pick your service under $GET_MY_MUSIC, or add a link."
                else "No lists yet. Add a public link above.",
            )
        }
    }
    items(overview.lists, key = { "list:${it.id}" }) { list -> ListRow(vm, list) }
}

@Composable
private fun ListRow(vm: ImportModel, list: ImportListSummary) {
    // Remove asks once more before the list goes, as Remove all does on
    // Downloads.
    var confirming by remember(list.id) { mutableStateOf(false) }
    Column(Modifier.fillMaxWidth().padding(horizontal = 20.dp, vertical = 10.dp), verticalArrangement = Arrangement.spacedBy(6.dp)) {
        Column(Modifier.fillMaxWidth().clip(RoundedCornerShape(8.dp)).clickable(role = Role.Button) { vm.open(list.id) }) {
            Text(list.name, style = OctoType.body, color = OctoColors.TextPrimary, maxLines = 2)
            Text(list.originLine(), style = OctoType.caption, color = OctoColors.TextMuted)
            Text(list.countsLine(), style = OctoType.caption, color = OctoColors.TextSecondary)
        }
        Meter(list.fraction)
        list.partial?.let { Text(it, style = OctoType.caption, color = OctoColors.TextMuted) }
        list.playlistNote?.let { Text(it, style = OctoType.caption, color = OctoColors.TextMuted) }
        SwitchLine(KEEP_AS_PLAYLIST, list.keepPlaylist, !vm.working) { vm.keepPlaylist(list.id, it) }
        SwitchLine(GET_MISSING_SONGS, list.getMissing, !vm.working) { vm.getMissing(list.id, it) }
        if (confirming) {
            Text(REMOVE_LIST, style = OctoType.bodySmall, color = OctoColors.TextPrimary, modifier = Modifier.padding(top = 4.dp))
            Text(list.removeLine(), style = OctoType.caption, color = OctoColors.TextSecondary)
            Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                AccentButton("Remove", onClick = {
                    confirming = false
                    vm.remove(list.id)
                }, size = ButtonSize.Small, enabled = !vm.working)
                GlazeButton("Cancel", { confirming = false }, size = ButtonSize.Small)
            }
        } else {
            Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                GlazeButton("Open", { vm.open(list.id) }, size = ButtonSize.Small)
                if (list.readsAgain) GlazeButton("Read again", { vm.readList(list.id) }, size = ButtonSize.Small, enabled = !vm.working)
                GlazeButton("Remove", { confirming = true }, size = ButtonSize.Small, enabled = !vm.working)
            }
        }
    }
}

@Composable
private fun SwitchLine(text: String, on: Boolean, enabled: Boolean, change: (Boolean) -> Unit) {
    Row(Modifier.fillMaxWidth(), verticalAlignment = Alignment.CenterVertically) {
        Text(text, style = OctoType.bodySmall, color = OctoColors.TextSecondary, modifier = Modifier.weight(1f))
        OctoSwitch(on, change, enabled = enabled)
    }
}

@Composable
private fun Meter(fraction: Float) {
    Box(Modifier.fillMaxWidth().height(3.dp).clip(RoundedCornerShape(2.dp)).background(OctoColors.TextMuted.copy(alpha = 0.25f))) {
        Box(Modifier.fillMaxWidth(fraction.coerceIn(0f, 1f)).height(3.dp).background(OctoColors.Accent))
    }
}

private fun LazyListScope.openedList(vm: ImportModel, list: ImportListSummary) {
    item(key = "open:title") {
        Column(Modifier.padding(horizontal = 20.dp, vertical = 8.dp), verticalArrangement = Arrangement.spacedBy(6.dp)) {
            Text(list.name, style = OctoType.section, color = OctoColors.TextPrimary)
            Text("${list.countsLine()}. ${list.originLine()}", style = OctoType.caption, color = OctoColors.TextMuted)
            GlazeButton("Back to your lists", vm::close, size = ButtonSize.Small)
        }
    }
    val detail = vm.detail?.takeIf { it.list.id == list.id }
    if (detail == null) {
        item(key = "open:reading") { Line("Reading the list…") }
        return
    }
    val askable = detail.tracks.filter { it.stage.askable }
    if (askable.isNotEmpty() && !list.getMissing) {
        item(key = "open:get") {
            Row(Modifier.padding(horizontal = 20.dp, vertical = 4.dp)) {
                GlazeButton(
                    "Get the ${askable.size} missing ${if (askable.size == 1) "song" else "songs"} now",
                    { vm.getSongs(list.id, askable.map { it.key }) },
                    size = ButtonSize.Medium,
                    enabled = !vm.working,
                )
            }
        }
    }
    // One song may be on a list twice, so its place is part of its key.
    itemsIndexed(detail.tracks, key = { at, track -> "track:$at:${track.key}" }) { _, track -> TrackLine(track) }
}

@Composable
private fun TrackLine(track: ImportTrack, action: (@Composable () -> Unit)? = null) {
    Row(Modifier.fillMaxWidth().padding(horizontal = 20.dp, vertical = 8.dp), verticalAlignment = Alignment.CenterVertically) {
        Column(Modifier.weight(1f)) {
            Text(track.title, style = OctoType.bodySmall, color = OctoColors.TextPrimary, maxLines = 1)
            Text(track.artist, style = OctoType.caption, color = OctoColors.TextMuted, maxLines = 1)
            track.detail?.let { Text(it, style = OctoType.caption, color = OctoColors.TextMuted, maxLines = 2) }
        }
        val pct = track.progress?.let { " ${(it * 100).toInt()}%" }.orEmpty()
        Text(track.stage.label() + pct, style = OctoType.caption, color = stateColor(track.stage), modifier = Modifier.padding(start = 12.dp))
        action?.invoke()
    }
}

private fun stateColor(state: ImportTrackState) = when (state) {
    ImportTrackState.Have, ImportTrackState.Done -> OctoColors.SignalGreen
    ImportTrackState.NotFound, ImportTrackState.Skipped -> OctoColors.SignalOrange
    else -> OctoColors.TextSecondary
}

private fun LazyListScope.trickle(vm: ImportModel, overview: ImportOverview) {
    val trickle = overview.trickle
    item(key = "trickle:title") { SectionTitle("Trickle", Modifier.padding(top = 12.dp)) }
    item(key = "trickle:state") {
        Column(Modifier.padding(horizontal = 20.dp, vertical = 4.dp), verticalArrangement = Arrangement.spacedBy(8.dp)) {
            Text(trickle.title(), style = OctoType.body, color = OctoColors.TextPrimary)
            Text(trickle.line(), style = OctoType.caption, color = OctoColors.TextMuted)
            Row(horizontalArrangement = Arrangement.spacedBy(8.dp)) {
                if (trickle.stage != TrickleState.Idle || trickle.queued > 0) {
                    val paused = trickle.stage == TrickleState.Paused
                    GlazeButton(if (paused) "Go on" else "Pause", { if (paused) vm.resume() else vm.pause() }, size = ButtonSize.Small, enabled = !vm.working)
                }
                if (trickle.notFound > 0) GlazeButton("Try not found again", { vm.retry() }, size = ButtonSize.Small, enabled = !vm.working)
                if (trickle.done + trickle.notFound + trickle.skipped > 0) GlazeButton("Clear finished", { vm.clearFinished() }, size = ButtonSize.Small, enabled = !vm.working)
            }
        }
    }
    trickle.current?.let { current -> item(key = "trickle:now") { TrackLine(current) } }
    items(trickle.next, key = { "next:${it.key}" }) { track ->
        TrackLine(track) { GlazeButton("Skip", { vm.skip(track.key) }, size = ButtonSize.ExtraSmall, enabled = !vm.working, modifier = Modifier.padding(start = 8.dp)) }
    }
    items(trickle.recent, key = { "recent:${it.key}" }) { track ->
        val again = track.stage == ImportTrackState.NotFound || track.stage == ImportTrackState.Skipped
        TrackLine(track, if (again) {
            { GlazeButton("Try again", { vm.retry(listOf(track.key)) }, size = ButtonSize.ExtraSmall, enabled = !vm.working, modifier = Modifier.padding(start = 8.dp)) }
        } else null)
    }
}
