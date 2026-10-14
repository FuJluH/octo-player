package app.winters.octo.desktop.pages

import androidx.compose.animation.animateColorAsState
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.BoxWithConstraints
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.ExperimentalLayoutApi
import androidx.compose.foundation.layout.FlowRow
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.selection.selectable
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.text.BasicText
import androidx.compose.foundation.text.TextAutoSize
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.alpha
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.input.pointer.PointerIcon
import androidx.compose.ui.input.pointer.pointerHoverIcon
import androidx.compose.ui.platform.testTag
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import app.winters.octo.design.CardEdge
import app.winters.octo.design.DesktopType
import app.winters.octo.design.GlassField
import app.winters.octo.design.Glyph
import app.winters.octo.design.GlazeCapsule
import app.winters.octo.design.IconSize
import app.winters.octo.design.LocalPopups
import app.winters.octo.design.MenuTitle
import app.winters.octo.design.OctoColors
import app.winters.octo.design.OctoDuration
import app.winters.octo.design.OctoIcons
import app.winters.octo.design.OctoInk
import app.winters.octo.design.PopupHost
import app.winters.octo.design.PopupPadding
import app.winters.octo.design.ProgressRing
import app.winters.octo.design.Space
import app.winters.octo.design.Txt
import app.winters.octo.design.hoverLift
import app.winters.octo.design.motionScale
import app.winters.octo.design.octoTween
import app.winters.octo.desktop.imports.chooseImportFile
import app.winters.octo.desktop.imports.sendImportFile
import app.winters.octo.subsonic.ImportServiceLink
import app.winters.octo.subsonic.ImportServices
import app.winters.octo.ui.imports.GET_MY_MUSIC_LINE
import app.winters.octo.ui.imports.IMPORT
import app.winters.octo.ui.imports.ImportModel
import app.winters.octo.ui.imports.ImportStep
import app.winters.octo.ui.imports.PASTED_LIST_NAME
import app.winters.octo.ui.imports.PASTE_A_LIST
import app.winters.octo.ui.imports.PASTE_LINE
import app.winters.octo.ui.imports.USE_A_FILE
import app.winters.octo.ui.imports.USE_DOWNLOADED_FILE
import app.winters.octo.ui.imports.WAITING_ANY_LINE
import app.winters.octo.ui.imports.service
import app.winters.octo.ui.imports.waitingLine
import app.winters.octo.ui.imports.waitingTitle

// Get my music on the desktop: a tile for each service, which opens its
// export page on TuneMyMusic in the browser, then the wait for the file it
// saves, which comes back by the file window, a drop on the page, or a
// pasted list.

// The section's line under its name.
internal fun getDetail(model: ImportModel): String = when (val step = model.step) {
    ImportStep.Choose -> "From another service, a file or a list"
    is ImportStep.Waiting -> waitingTitle(step.service)
    is ImportStep.Sending -> "Sending ${step.name}"
    is ImportStep.Sent -> "Your lists are in"
}

@Composable
internal fun GetMyMusicSection(model: ImportModel, services: ImportServices) {
    val scope = rememberCoroutineScope()
    val popups = LocalPopups.current
    val step = model.step
    val pickFile = { chooseImportFile()?.let { sendImportFile(scope, model, it) } ?: Unit }
    val paste = { askToPaste(popups, model) }
    val grid = @Composable {
        Txt(GET_MY_MUSIC_LINE, DesktopType.meta, OctoColors.TextMuted, Modifier.padding(horizontal = RowInset), maxLines = 3)
        ServiceGrid(services.services, chosen = step.service?.id, enabled = step !is ImportStep.Sending, onPick = model::choose)
    }
    // Past the grid, the step in hand comes first, so it is in view
    // without scrolling; the grid stays under it to pick another service.
    when (step) {
        ImportStep.Choose -> {
            grid()
            Said(model)
            Group("Already have a file") {
                ActionRow(USE_A_FILE, "CSV, TXT, JSON or ZIP. You can also drop it on this page.", "Choose file", pickFile)
                ActionRow(PASTE_A_LIST, PASTE_LINE, "Paste", paste)
            }
        }
        is ImportStep.Waiting -> {
            WaitingCard(model, step.service, pickFile, paste)
            grid()
        }
        is ImportStep.Sending -> {
            Rows {
                SettingRow("Sending ${step.name}", "Octo reads your lists, then checks them against your library.") { ProgressRing(null, size = IconSize.Transport) }
            }
            grid()
        }
        is ImportStep.Sent -> {
            SentCard(model, step)
            grid()
        }
    }
}

// The export page is open in the browser: what to do there, then the file.
@Composable
private fun WaitingCard(model: ImportModel, service: ImportServiceLink?, pickFile: () -> Unit, paste: () -> Unit) {
    Card {
        Column(Modifier.fillMaxWidth().padding(horizontal = RowInset, vertical = Space.L), verticalArrangement = Arrangement.spacedBy(Space.M)) {
            Txt(waitingTitle(service), DesktopType.emphasis, maxLines = 2)
            Txt(service?.let(::waitingLine) ?: WAITING_ANY_LINE, DesktopType.body, OctoColors.TextSecondary, maxLines = 4)
            Txt("You can also drop the file on this page.", DesktopType.meta, OctoColors.TextMuted, maxLines = 2)
            Buttons {
                GlazeCapsule(OctoIcons.Download, USE_DOWNLOADED_FILE, pickFile, lit = true)
                GlazeCapsule(null, PASTE_A_LIST, paste)
            }
            Buttons {
                if (service != null) RowAction("Open TuneMyMusic again", { model.openExport(service) }, icon = OctoIcons.Globe)
                RowAction("Pick another service", model::backToServices)
            }
        }
    }
    Said(model)
}

// The server read it: its words, and who approves downloads first when
// someone does.
@Composable
private fun SentCard(model: ImportModel, step: ImportStep.Sent) {
    Card {
        Column(Modifier.fillMaxWidth().padding(horizontal = RowInset, vertical = Space.L), verticalArrangement = Arrangement.spacedBy(Space.M)) {
            Row(verticalAlignment = Alignment.CenterVertically, horizontalArrangement = Arrangement.spacedBy(Space.M)) {
                Glyph(OctoIcons.Check, size = IconSize.Inline, tint = OctoColors.SignalGreen)
                Txt(step.message.ifBlank { "Your lists are in." }, DesktopType.emphasis, maxLines = 3)
            }
            step.approval?.let { Txt(it, DesktopType.body, OctoColors.TextSecondary, maxLines = 3) }
            Buttons {
                GlazeCapsule(OctoIcons.Playlists, "See your lists", { showSection(IMPORT, "lists") }, lit = true)
                GlazeCapsule(null, "Import more", model::backToServices)
            }
        }
    }
}

// Buttons in a row that wraps under itself when the column is narrow, so
// none is ever cut.
@OptIn(ExperimentalLayoutApi::class)
@Composable
private fun Buttons(content: @Composable () -> Unit) {
    FlowRow(horizontalArrangement = Arrangement.spacedBy(Space.M), verticalArrangement = Arrangement.spacedBy(Space.M)) { content() }
}

private val TileMin = 150.dp
private val TileShape = RoundedCornerShape(12.dp)
private val TileType = DesktopType.emphasis.copy(fontSize = 15.sp)
private val OnAccent = Color(0xFF0C0C0D)

// The services, as many to a row as fit, every tile the same width.
@Composable
private fun ServiceGrid(services: List<ImportServiceLink>, chosen: String?, enabled: Boolean, onPick: (ImportServiceLink) -> Unit) {
    if (services.isEmpty()) return
    BoxWithConstraints(Modifier.fillMaxWidth()) {
        val gap = Space.M
        val columns = ((maxWidth + gap) / (TileMin + gap)).toInt().coerceIn(2, 5)
        val width = (maxWidth - gap * (columns - 1)) / columns
        Column(verticalArrangement = Arrangement.spacedBy(gap)) {
            services.chunked(columns).forEach { row ->
                Row(horizontalArrangement = Arrangement.spacedBy(gap)) {
                    row.forEach { service ->
                        ServiceTile(service, service.id == chosen, enabled, Modifier.width(width)) { onPick(service) }
                    }
                }
            }
        }
    }
}

// One service: its name, filled in the accent with a check while it is the
// one in use, outlined when not.
@Composable
private fun ServiceTile(service: ImportServiceLink, chosen: Boolean, enabled: Boolean, modifier: Modifier, onPick: () -> Unit) {
    val motion = motionScale()
    val fill by animateColorAsState(if (chosen) OctoColors.Accent else Color.Transparent, octoTween(motion, OctoDuration.Fill), label = "tile fill")
    val ink by animateColorAsState(if (chosen) OnAccent else OctoColors.TextPrimary, octoTween(motion, OctoDuration.Fill), label = "tile ink")
    Box(
        modifier
            .heightIn(min = 56.dp)
            .clip(TileShape)
            .background(fill, TileShape)
            .border(1.dp, if (chosen) Color.Transparent else CardEdge, TileShape)
            .then(if (chosen) Modifier else Modifier.hoverLift(TileShape))
            .alpha(if (enabled) 1f else OctoInk.DisabledAlpha)
            .pointerHoverIcon(PointerIcon.Hand)
            .selectable(selected = chosen, enabled = enabled, role = Role.RadioButton, onClick = onPick)
            .testTag("service-${service.id}"),
    ) {
        // 15 sp, smaller only when there is no room, so the name is never cut.
        BasicText(
            service.name,
            style = TileType.copy(color = ink, textAlign = TextAlign.Center),
            maxLines = 2,
            autoSize = TextAutoSize.StepBased(minFontSize = 10.sp, maxFontSize = TileType.fontSize),
            modifier = Modifier.align(Alignment.Center).padding(horizontal = 18.dp, vertical = 8.dp),
        )
        // The check sits in the corner, taking no room from the name.
        if (chosen) Glyph(OctoIcons.Check, Modifier.align(Alignment.TopEnd).padding(6.dp), size = 12.dp, tint = ink)
    }
}

// The paste sheet: a box for the list, and its buttons always in view under
// it, since the box scrolls its own lines.
internal fun askToPaste(popups: PopupHost, model: ImportModel) {
    popups.showCentred(width = 520.dp, scrim = true) { close ->
        var text by remember { mutableStateOf("") }
        var name by remember { mutableStateOf("") }
        MenuTitle(PASTE_A_LIST)
        PopupPadding {
            Txt(PASTE_LINE, DesktopType.meta, OctoColors.TextMuted, maxLines = 2)
            GlassField(name, { name = it }, Modifier.fillMaxWidth(), placeholder = "Name: $PASTED_LIST_NAME")
            GlassField(text, { text = it }, Modifier.fillMaxWidth(), placeholder = "Massive Attack - Angel", lines = 9)
            Row(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.spacedBy(Space.M, Alignment.End)) {
                GlazeCapsule(null, "Cancel", close)
                GlazeCapsule(OctoIcons.Add, "Import", {
                    close()
                    model.sendText(text, name.trim())
                }, lit = true, enabled = text.isNotBlank())
            }
        }
    }
}
