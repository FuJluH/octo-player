package app.winters.octo.ui.settings

import android.content.ClipData
import android.content.ClipboardManager
import android.content.Context
import android.content.Intent
import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.ExperimentalLayoutApi
import androidx.compose.foundation.layout.FlowRow
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.text.selection.SelectionContainer
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.Icon
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.res.painterResource
import androidx.compose.ui.semantics.LiveRegionMode
import androidx.compose.ui.semantics.heading
import androidx.compose.ui.semantics.liveRegion
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import androidx.core.net.toUri
import androidx.hilt.lifecycle.viewmodel.compose.hiltViewModel
import androidx.lifecycle.ViewModel
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import app.winters.octo.admin.ServerUpdates
import app.winters.octo.design.AccentButton
import app.winters.octo.design.ButtonSize
import app.winters.octo.design.GlassPopup
import app.winters.octo.design.GlazeButton
import app.winters.octo.design.OctoColors
import app.winters.octo.design.OctoIcons
import app.winters.octo.design.OctoType
import app.winters.octo.design.Spinner
import app.winters.octo.markdown.MarkdownText
import app.winters.octo.serverupdate.CONFIRM_TITLE
import app.winters.octo.serverupdate.ServerRelease
import app.winters.octo.serverupdate.StepState
import app.winters.octo.serverupdate.UpdateOutcome
import app.winters.octo.serverupdate.UpdatePanel
import app.winters.octo.serverupdate.UpdateTrack
import app.winters.octo.serverupdate.UpdateWay
import app.winters.octo.serverupdate.confirmDetail
import app.winters.octo.serverupdate.detail
import app.winters.octo.serverupdate.headline
import app.winters.octo.serverupdate.lastFailureWords
import app.winters.octo.serverupdate.outcomeDetail
import app.winters.octo.serverupdate.outcomeTitle
import app.winters.octo.serverupdate.panelOf
import app.winters.octo.serverupdate.releaseNotes
import app.winters.octo.serverupdate.releaseTitle
import app.winters.octo.serverupdate.showsDot
import app.winters.octo.serverupdate.updatingTitle
import app.winters.octo.serverupdate.wayWords
import app.winters.octo.ui.common.LocalFeedback
import app.winters.octo.ui.common.LocalHaze
import app.winters.octo.ui.common.PopupQuestion
import dagger.hilt.android.lifecycle.HiltViewModel
import javax.inject.Inject
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.launch

@HiltViewModel
class ServerUpdateViewModel @Inject constructor(private val updates: ServerUpdates) : ViewModel() {
    val track: StateFlow<UpdateTrack> = updates.track

    fun refresh() = updates.refresh()

    fun updateNow() = updates.updateNow()

    fun later() = updates.later()

    fun closeOutcome() = updates.closeOutcome()

    suspend fun dashboard(): String? = updates.dashboard()
}

// What the small dot means, for a screen reader.
const val SERVER_UPDATE_MARK = "Server update available"

// Whether Settings' way to the server page carries the small dot.
@Composable
fun rememberServerUpdateDot(vm: ServerUpdateViewModel = hiltViewModel()): Boolean {
    val track by vm.track.collectAsStateWithLifecycle()
    return showsDot(track)
}

private val PanelShape = RoundedCornerShape(20.dp)

// The server's own update, at the top of the server page: shown only when
// a newer Octo is out, while an update is under way, or once one started
// here has ended. The page opening asks the server at once.
@OptIn(ExperimentalLayoutApi::class)
@Composable
fun ServerUpdateSection(vm: ServerUpdateViewModel = hiltViewModel()) {
    val track by vm.track.collectAsStateWithLifecycle()
    LaunchedEffect(Unit) { vm.refresh() }
    val panel = panelOf(track)
    if (panel == UpdatePanel.Hidden) return
    var confirming by rememberSaveable { mutableStateOf(false) }
    var reading by rememberSaveable { mutableStateOf(false) }
    val context = LocalContext.current
    val scope = rememberCoroutineScope()
    fun openDashboard() {
        scope.launch {
            val url = vm.dashboard() ?: return@launch
            runCatching { context.startActivity(Intent(Intent.ACTION_VIEW, url.toUri()).addFlags(Intent.FLAG_ACTIVITY_NEW_TASK)) }
        }
    }

    Column(
        Modifier
            .fillMaxWidth()
            .padding(horizontal = 16.dp)
            .background(OctoColors.Accent.copy(alpha = 0.10f), PanelShape)
            .padding(horizontal = 18.dp, vertical = 16.dp)
            .semantics { liveRegion = LiveRegionMode.Polite },
        verticalArrangement = Arrangement.spacedBy(6.dp),
    ) {
        when (panel) {
            UpdatePanel.Hidden -> Unit
            is UpdatePanel.Available -> {
                PanelTitle(headline(panel))
                Text(detail(panel), style = OctoType.bodySmall, color = OctoColors.TextSecondary)
                wayWords(panel.way)?.let { Text(it, style = OctoType.bodySmall, color = OctoColors.TextSecondary) }
                if (panel.way == UpdateWay.HelperOutdated && panel.reinstallCommand.isNotBlank()) Command(panel.reinstallCommand, context)
                panel.lastFailure?.let { Text(lastFailureWords(it), style = OctoType.caption, color = OctoColors.Error) }
                panel.problem?.let { Text(it, style = OctoType.caption, color = OctoColors.Error) }
                FlowRow(
                    Modifier.padding(top = 8.dp),
                    horizontalArrangement = Arrangement.spacedBy(8.dp),
                    verticalArrangement = Arrangement.spacedBy(8.dp),
                ) {
                    if (panel.way == UpdateWay.Now) {
                        AccentButton("Update now", onClick = { confirming = true }, size = ButtonSize.Medium, loading = panel.starting)
                    } else {
                        AccentButton("Open dashboard", onClick = ::openDashboard, size = ButtonSize.Medium)
                    }
                    GlazeButton("What's new", onClick = { reading = true }, size = ButtonSize.Medium)
                    GlazeButton("Later", onClick = vm::later, size = ButtonSize.Medium, enabled = !panel.starting)
                }
                ConfirmPopup(confirming, panel.latest.tag, onConfirm = { confirming = false; vm.updateNow() }, onCancel = { confirming = false })
                NotesPopup(reading, panel.newer) { reading = false }
            }
            is UpdatePanel.Updating -> {
                PanelTitle(updatingTitle(panel.tag))
                Column(Modifier.padding(top = 6.dp), verticalArrangement = Arrangement.spacedBy(10.dp)) {
                    panel.steps.forEach { step -> StepRow(step.words, step.state) }
                }
                Text(
                    "Music from your server stops for a minute or two.",
                    style = OctoType.caption,
                    color = OctoColors.TextMuted,
                    modifier = Modifier.padding(top = 6.dp),
                )
            }
            is UpdatePanel.Finished -> {
                val outcome = panel.outcome
                PanelTitle(outcomeTitle(outcome))
                outcomeDetail(outcome)?.let { Text(it, style = OctoType.bodySmall, color = OctoColors.TextSecondary) }
                FlowRow(
                    Modifier.padding(top = 8.dp),
                    horizontalArrangement = Arrangement.spacedBy(8.dp),
                    verticalArrangement = Arrangement.spacedBy(8.dp),
                ) {
                    if (outcome is UpdateOutcome.Done) {
                        AccentButton("Done", onClick = vm::closeOutcome, size = ButtonSize.Medium)
                    } else {
                        AccentButton("Open dashboard", onClick = ::openDashboard, size = ButtonSize.Medium)
                        GlazeButton("Close", onClick = vm::closeOutcome, size = ButtonSize.Medium)
                    }
                }
            }
        }
    }
}

@Composable
private fun PanelTitle(text: String) {
    Text(text, style = OctoType.body.copy(fontWeight = FontWeight.SemiBold), color = OctoColors.TextPrimary, modifier = Modifier.semantics { heading() })
}

// One step of the update: a check once done, a spinner while on it, and a
// faint dot before it.
@Composable
private fun StepRow(words: String, state: StepState) {
    Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(12.dp)) {
        Box(Modifier.size(18.dp), contentAlignment = Alignment.Center) {
            when (state) {
                StepState.Done -> Icon(painterResource(OctoIcons.Check), contentDescription = "Done", tint = OctoColors.Accent, modifier = Modifier.size(18.dp))
                StepState.Now -> Spinner(size = 16.dp, color = OctoColors.TextPrimary)
                StepState.Waiting -> Box(Modifier.size(6.dp).background(OctoColors.TextMuted.copy(alpha = 0.5f), CircleShape))
            }
        }
        Text(
            words,
            style = OctoType.bodySmall,
            color = when (state) {
                StepState.Done -> OctoColors.TextSecondary
                StepState.Now -> OctoColors.TextPrimary
                StepState.Waiting -> OctoColors.TextMuted
            },
        )
    }
}

// A command to run on the server, in a fixed-width face, to select or copy.
@Composable
private fun Command(command: String, context: Context) {
    val feedback = LocalFeedback.current
    Row(
        Modifier
            .fillMaxWidth()
            .background(Color.Black.copy(alpha = 0.25f), RoundedCornerShape(10.dp))
            .padding(start = 12.dp, end = 4.dp, top = 6.dp, bottom = 6.dp),
        verticalAlignment = Alignment.CenterVertically,
    ) {
        SelectionContainer(Modifier.weight(1f)) {
            Text(command, style = OctoType.caption.copy(fontFamily = FontFamily.Monospace, fontSize = 12.5.sp), color = OctoColors.TextPrimary)
        }
        GlazeButton("Copy", onClick = {
            context.getSystemService(ClipboardManager::class.java)?.setPrimaryClip(ClipData.newPlainText("Octo", command))
            feedback.done("Copied")
        }, size = ButtonSize.Small)
    }
}

@Composable
private fun ConfirmPopup(visible: Boolean, tag: String, onConfirm: () -> Unit, onCancel: () -> Unit) {
    GlassPopup(visible = visible, anchor = null, onDismiss = onCancel, backdrop = LocalHaze.current, title = CONFIRM_TITLE) {
        PopupQuestion(CONFIRM_TITLE, confirmDetail(tag), "Update now", onConfirm = onConfirm, onCancel = onCancel)
    }
}

// Every release since the one the server runs, newest first, with its notes.
@Composable
private fun NotesPopup(visible: Boolean, releases: List<ServerRelease>, onDismiss: () -> Unit) {
    GlassPopup(
        visible = visible,
        anchor = null,
        onDismiss = onDismiss,
        backdrop = LocalHaze.current,
        title = "What's new on your server",
        maxWidth = 460.dp,
        heightShare = 0.82f,
    ) {
        val notes = remember(releases) { releaseNotes(releases) }
        Column(
            Modifier
                .fillMaxWidth()
                .verticalScroll(rememberScrollState())
                .padding(start = 24.dp, end = 24.dp, top = 26.dp, bottom = 28.dp),
        ) {
            Text("What's new on your server", style = OctoType.label, color = OctoColors.TextSecondary)
            notes.forEachIndexed { index, (release, blocks) ->
                Text(
                    releaseTitle(release),
                    style = OctoType.title,
                    color = OctoColors.TextPrimary,
                    modifier = Modifier.padding(top = if (index == 0) 2.dp else 30.dp, bottom = 14.dp).semantics { heading() },
                )
                if (blocks.isEmpty()) {
                    Text("No notes for this release.", style = OctoType.bodySmall, color = OctoColors.TextMuted)
                } else {
                    MarkdownText(blocks)
                }
            }
        }
    }
}
