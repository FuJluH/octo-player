package app.winters.octo.desktop.pages

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
import androidx.compose.foundation.shape.CircleShape
import androidx.compose.foundation.text.selection.SelectionContainer
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.semantics.LiveRegionMode
import androidx.compose.ui.semantics.liveRegion
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.font.FontFamily
import app.winters.octo.design.ControlHeight
import app.winters.octo.design.Corner
import app.winters.octo.design.DesktopType
import app.winters.octo.design.Glyph
import app.winters.octo.design.GlazeCapsule
import app.winters.octo.design.IconSize
import app.winters.octo.design.MenuTitle
import app.winters.octo.design.OctoColors
import app.winters.octo.design.OctoIcons
import app.winters.octo.design.PopupPadding
import app.winters.octo.design.SettingsSize
import app.winters.octo.design.Space
import app.winters.octo.design.Spinner
import app.winters.octo.design.Txt
import app.winters.octo.desktop.AppState
import app.winters.octo.desktop.family.copyText
import app.winters.octo.serverupdate.CONFIRM_TITLE
import app.winters.octo.serverupdate.ServerRelease
import app.winters.octo.serverupdate.StepState
import app.winters.octo.serverupdate.UpdateOutcome
import app.winters.octo.serverupdate.UpdatePanel
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

// Settings > Servers: a newer Octo for the server in use, at the top of the
// section. Shown only when one is out, while an update is under way, or
// once one started here has ended. The section opening asks the server.

// What the small dot means, for a screen reader.
internal const val SERVER_UPDATE_MARK = "Server update available"

// Whether Settings, and its Servers section, carry the small dot.
@Composable
internal fun serverUpdateWaits(app: AppState): Boolean {
    val track by app.serverUpdate.track.collectAsState()
    return showsDot(track)
}

@OptIn(ExperimentalLayoutApi::class)
@Composable
internal fun ServerUpdateCard(app: AppState) {
    val watcher = app.serverUpdate
    val track by watcher.track.collectAsState()
    LaunchedEffect(Unit) { watcher.refresh() }
    val panel = panelOf(track)
    if (panel == UpdatePanel.Hidden) return
    Column(
        Modifier
            .fillMaxWidth()
            .clip(Corner.PanelShape)
            .background(OctoColors.Accent.copy(alpha = 0.10f))
            .padding(horizontal = RowInset, vertical = Space.L)
            .semantics { liveRegion = LiveRegionMode.Polite },
        verticalArrangement = Arrangement.spacedBy(Space.Xs),
    ) {
        when (panel) {
            UpdatePanel.Hidden -> Unit
            is UpdatePanel.Available -> {
                Txt(headline(panel), DesktopType.emphasis, maxLines = 3)
                Txt(detail(panel), DesktopType.meta, OctoColors.TextSecondary, maxLines = 3)
                wayWords(panel.way)?.let { Txt(it, DesktopType.meta, OctoColors.TextSecondary, maxLines = 3) }
                if (panel.way == UpdateWay.HelperOutdated && panel.reinstallCommand.isNotBlank()) Command(app, panel.reinstallCommand)
                panel.lastFailure?.let { Txt(lastFailureWords(it), DesktopType.meta, OctoColors.SignalOrange, maxLines = 4) }
                panel.problem?.let { Txt(it, DesktopType.meta, OctoColors.SignalOrange, maxLines = 4) }
                Buttons {
                    if (panel.way == UpdateWay.Now) {
                        GlazeCapsule(null, if (panel.starting) "Starting" else "Update now", { confirmUpdate(app, panel.latest.tag) }, lit = true, enabled = !panel.starting, height = ControlHeight.M)
                    } else {
                        GlazeCapsule(null, "Open dashboard", app::openDashboard, lit = true, height = ControlHeight.M)
                    }
                    GlazeCapsule(null, "What's new", { showServerNotes(app, panel.newer) }, height = ControlHeight.M)
                    GlazeCapsule(null, "Later", watcher::later, enabled = !panel.starting, height = ControlHeight.M)
                }
            }
            is UpdatePanel.Updating -> {
                Txt(updatingTitle(panel.tag), DesktopType.emphasis, maxLines = 3)
                Column(Modifier.padding(top = Space.S), verticalArrangement = Arrangement.spacedBy(Space.S)) {
                    panel.steps.forEach { StepRow(it.words, it.state) }
                }
                Txt("Music from your server stops for a minute or two.", DesktopType.meta, OctoColors.TextMuted, Modifier.padding(top = Space.S), maxLines = 2)
            }
            is UpdatePanel.Finished -> {
                val outcome = panel.outcome
                Txt(outcomeTitle(outcome), DesktopType.emphasis, maxLines = 3)
                outcomeDetail(outcome)?.let { Txt(it, DesktopType.meta, OctoColors.TextSecondary, maxLines = 6) }
                Buttons {
                    if (outcome is UpdateOutcome.Done) {
                        GlazeCapsule(null, "Done", watcher::closeOutcome, lit = true, height = ControlHeight.M)
                    } else {
                        GlazeCapsule(null, "Open dashboard", app::openDashboard, lit = true, height = ControlHeight.M)
                        GlazeCapsule(null, "Close", watcher::closeOutcome, height = ControlHeight.M)
                    }
                }
            }
        }
    }
}

@OptIn(ExperimentalLayoutApi::class)
@Composable
private fun Buttons(content: @Composable () -> Unit) {
    FlowRow(
        Modifier.padding(top = Space.M),
        horizontalArrangement = Arrangement.spacedBy(Space.M),
        verticalArrangement = Arrangement.spacedBy(Space.M),
    ) { content() }
}

// One step: a check once done, a spinner while on it, a faint dot before it.
@Composable
private fun StepRow(words: String, state: StepState) {
    Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(Space.L)) {
        Box(Modifier.size(IconSize.Table), contentAlignment = Alignment.Center) {
            when (state) {
                StepState.Done -> Glyph(OctoIcons.Check, size = IconSize.Table, tint = OctoColors.Accent)
                StepState.Now -> Spinner(size = IconSize.Table)
                StepState.Waiting -> Box(Modifier.size(Space.S).clip(CircleShape).background(OctoColors.TextMuted.copy(alpha = 0.5f)))
            }
        }
        Txt(
            words,
            DesktopType.body,
            when (state) {
                StepState.Done -> OctoColors.TextSecondary
                StepState.Now -> OctoColors.TextPrimary
                StepState.Waiting -> OctoColors.TextMuted
            },
        )
    }
}

// A command to run on the server, in a fixed-width face, to select or copy.
@Composable
private fun Command(app: AppState, command: String) {
    Row(
        Modifier
            .fillMaxWidth()
            .padding(top = Space.Xs)
            .clip(Corner.ControlShape)
            .background(Color.Black.copy(alpha = 0.25f))
            .padding(start = Space.L, end = Space.S, top = Space.S, bottom = Space.S),
        verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.spacedBy(Space.M),
    ) {
        SelectionContainer(Modifier.weight(1f)) {
            Txt(command, DesktopType.meta.copy(fontFamily = FontFamily.Monospace), OctoColors.TextPrimary, maxLines = 3)
        }
        RowAction("Copy", {
            copyText(command)
            app.notice = "Copied"
        }, icon = OctoIcons.Copy)
    }
}

// Asks before updating: the server restarts, and its music stops a while.
internal fun confirmUpdate(app: AppState, tag: String) {
    app.popups.showCentred(width = SettingsSize.Sheet) { close ->
        MenuTitle(CONFIRM_TITLE)
        PopupPadding {
            Txt(confirmDetail(tag), DesktopType.body, OctoColors.TextPrimary, maxLines = 4)
            Row(Modifier.fillMaxWidth().padding(top = Space.Xs, bottom = Space.Xs), horizontalArrangement = Arrangement.spacedBy(Space.M, Alignment.End)) {
                GlazeCapsule(null, "Cancel", close, height = ControlHeight.L)
                GlazeCapsule(null, "Update now", {
                    close()
                    app.serverUpdate.updateNow()
                }, lit = true, height = ControlHeight.L)
            }
        }
    }
}

// Every release since the one the server runs, newest first, with its notes.
internal fun showServerNotes(app: AppState, releases: List<ServerRelease>) {
    val notes = releaseNotes(releases)
    app.popups.showCentred(width = SettingsSize.Column, maxHeight = SettingsSize.SheetMax) { _ ->
        MenuTitle("What's new on your server")
        Column(Modifier.padding(start = Space.Xl, end = Space.Xl, top = Space.S, bottom = Space.Xl)) {
            notes.forEachIndexed { index, (release, blocks) ->
                Txt(
                    releaseTitle(release),
                    DesktopType.section,
                    modifier = Modifier.padding(top = if (index == 0) Space.None else Space.Xxl, bottom = Space.M),
                    maxLines = 2,
                )
                if (blocks.isEmpty()) {
                    Txt("No notes for this release.", DesktopType.meta, OctoColors.TextMuted)
                } else {
                    MarkdownView(blocks, app.openUrl)
                }
            }
        }
    }
}
