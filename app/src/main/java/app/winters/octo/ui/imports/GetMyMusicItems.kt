package app.winters.octo.ui.imports

import android.content.Context
import android.content.Intent
import android.net.Uri
import android.provider.DocumentsContract
import android.provider.OpenableColumns
import androidx.activity.result.contract.ActivityResultContracts
import androidx.compose.animation.animateColorAsState
import androidx.compose.foundation.background
import androidx.compose.foundation.border
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.ExperimentalLayoutApi
import androidx.compose.foundation.layout.FlowRow
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.imePadding
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.lazy.LazyListScope
import androidx.compose.foundation.selection.selectable
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.text.BasicText
import androidx.compose.foundation.text.BasicTextField
import androidx.compose.foundation.text.TextAutoSize
import androidx.compose.material3.Icon
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.alpha
import androidx.compose.ui.draw.clip
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.SolidColor
import androidx.compose.ui.res.painterResource
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.style.TextAlign
import androidx.compose.ui.unit.dp
import androidx.compose.ui.unit.sp
import app.winters.octo.design.AccentButton
import app.winters.octo.design.ButtonSize
import app.winters.octo.design.GlassInput
import app.winters.octo.design.GlassSheet
import app.winters.octo.design.GlazeButton
import app.winters.octo.design.OctoColors
import app.winters.octo.design.OctoIcons
import app.winters.octo.design.OctoType
import app.winters.octo.subsonic.IMPORT_FILE_MAX_BYTES
import app.winters.octo.subsonic.ImportServiceLink
import app.winters.octo.subsonic.ImportServices
import app.winters.octo.ui.settings.rows.SettingsGroup
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.withContext
import java.io.ByteArrayOutputStream
import java.io.IOException
import java.io.InputStream

// Get my music on the phone: a tile for each service, which opens its
// export page on TuneMyMusic in the browser, then the wait for the file it
// saves to Downloads, which comes back by the picker opened at Downloads,
// a share to Octo, or a pasted list.

private const val ROW_SIDE = 16

internal fun LazyListScope.getMyMusic(vm: ImportModel, services: ImportServices, pickFile: () -> Unit, paste: () -> Unit) {
    val step = vm.step
    val grid: LazyListScope.() -> Unit = {
        item(key = "get:grid") {
            SettingsGroup(Modifier.padding(vertical = 8.dp), title = if (step == ImportStep.Choose) GET_MY_MUSIC else "Pick another service") {
                Column(Modifier.padding(ROW_SIDE.dp), verticalArrangement = Arrangement.spacedBy(12.dp)) {
                    if (step == ImportStep.Choose) Text(GET_MY_MUSIC_LINE, style = OctoType.caption, color = OctoColors.TextMuted)
                    ServiceGrid(services.services, chosen = step.service?.id, enabled = step !is ImportStep.Sending, onPick = vm::choose)
                }
            }
        }
    }
    // Past the grid, the step in hand comes first, so it shows without
    // scrolling; the grid stays under it to pick another service.
    when (step) {
        ImportStep.Choose -> {
            grid()
            item(key = "get:file") {
                SettingsGroup(Modifier.padding(vertical = 8.dp), title = "Already have a file") {
                    StepRow(USE_A_FILE, "CSV, TXT, JSON or ZIP, from Downloads or any folder.") { GlazeButton("Choose", pickFile, size = ButtonSize.Small) }
                    StepRow(PASTE_A_LIST, PASTE_LINE) { GlazeButton("Paste", paste, size = ButtonSize.Small) }
                }
            }
        }
        is ImportStep.Waiting -> {
            item(key = "get:waiting") {
                val service = step.service
                StepCard(waitingTitle(service), service?.let(::waitingLine) ?: WAITING_ANY_LINE) {
                    AccentButton(USE_DOWNLOADED_FILE, pickFile, Modifier.fillMaxWidth(), size = ButtonSize.Medium)
                    GlazeButton(PASTE_A_LIST, paste, Modifier.fillMaxWidth(), size = ButtonSize.Medium)
                    if (service != null) GlazeButton("Open TuneMyMusic again", { vm.openExport(service) }, Modifier.fillMaxWidth(), size = ButtonSize.Small)
                }
            }
            grid()
        }
        is ImportStep.Sending -> {
            item(key = "get:sending") {
                StepCard("Sending ${step.name}", "Octo reads your lists, then checks them against your library.") {
                    GlazeButton("Sending", {}, Modifier.fillMaxWidth(), size = ButtonSize.Medium, enabled = false, loading = true)
                }
            }
            grid()
        }
        is ImportStep.Sent -> {
            item(key = "get:sent") {
                StepCard(step.message.ifBlank { "Your lists are in." }, step.approval) {
                    AccentButton("Import more", vm::backToServices, Modifier.fillMaxWidth(), size = ButtonSize.Medium)
                }
            }
            grid()
        }
    }
}

// One step: its heading and words, then its buttons, full width, one under
// another, so no label is ever cut.
@Composable
private fun StepCard(title: String, line: String?, buttons: @Composable () -> Unit) {
    SettingsGroup(Modifier.padding(vertical = 8.dp)) {
        Column(Modifier.padding(ROW_SIDE.dp), verticalArrangement = Arrangement.spacedBy(10.dp)) {
            Text(title, style = OctoType.body, color = OctoColors.TextPrimary)
            line?.let { Text(it, style = OctoType.bodySmall, color = OctoColors.TextSecondary) }
            Column(Modifier.padding(top = 4.dp), verticalArrangement = Arrangement.spacedBy(8.dp)) { buttons() }
        }
    }
}

@Composable
private fun StepRow(title: String, line: String, control: @Composable () -> Unit) {
    Row(Modifier.fillMaxWidth().padding(horizontal = ROW_SIDE.dp, vertical = 12.dp), verticalAlignment = Alignment.CenterVertically) {
        Column(Modifier.weight(1f).padding(end = 12.dp)) {
            Text(title, style = OctoType.body, color = OctoColors.TextPrimary)
            Text(line, style = OctoType.caption, color = OctoColors.TextMuted)
        }
        control()
    }
}

private val TileShape = RoundedCornerShape(14.dp)
private val OnAccent = Color(0xFF0C0C0D)

// The services, two to a row on a phone.
@OptIn(ExperimentalLayoutApi::class)
@Composable
private fun ServiceGrid(services: List<ImportServiceLink>, chosen: String?, enabled: Boolean, onPick: (ImportServiceLink) -> Unit) {
    FlowRow(Modifier.fillMaxWidth(), horizontalArrangement = Arrangement.spacedBy(8.dp), verticalArrangement = Arrangement.spacedBy(8.dp), maxItemsInEachRow = 2) {
        services.forEach { service ->
            ServiceTile(service, service.id == chosen, enabled, Modifier.weight(1f)) { onPick(service) }
        }
        // An odd last tile keeps the width of the others.
        if (services.size % 2 == 1) Box(Modifier.weight(1f))
    }
}

// One service, filled in the accent with a check while it is the one in
// use, outlined when not.
@Composable
private fun ServiceTile(service: ImportServiceLink, chosen: Boolean, enabled: Boolean, modifier: Modifier, onPick: () -> Unit) {
    val fill by animateColorAsState(if (chosen) OctoColors.Accent else OctoColors.Accent.copy(alpha = 0.06f), label = "tile fill")
    val ink by animateColorAsState(if (chosen) OnAccent else OctoColors.TextPrimary, label = "tile ink")
    Box(
        modifier
            .heightIn(min = 56.dp)
            .clip(TileShape)
            .background(fill, TileShape)
            .border(1.dp, if (chosen) Color.Transparent else OctoColors.TextMuted.copy(alpha = 0.25f), TileShape)
            .alpha(if (enabled) 1f else 0.5f)
            .selectable(selected = chosen, enabled = enabled, role = Role.RadioButton, onClick = onPick)
            .semantics { contentDescription = service.name },
    ) {
        // 15 sp, smaller only when there is no room, so the name is never cut.
        BasicText(
            service.name,
            style = OctoType.body.copy(color = ink, textAlign = TextAlign.Center, fontSize = 15.sp),
            maxLines = 2,
            autoSize = TextAutoSize.StepBased(minFontSize = 10.sp, maxFontSize = 15.sp),
            modifier = Modifier.align(Alignment.Center).padding(horizontal = 20.dp, vertical = 8.dp),
        )
        if (chosen) {
            Icon(painterResource(OctoIcons.Check), contentDescription = null, tint = ink, modifier = Modifier.align(Alignment.TopEnd).padding(6.dp).size(14.dp))
        }
    }
}

// The paste sheet: a name, a box for the list that scrolls its own lines,
// and the buttons always in view at the bottom, above the keyboard.
@Composable
internal fun PasteSheet(visible: Boolean, onDismiss: () -> Unit, onSend: (String, String) -> Unit) {
    GlassSheet(visible = visible, onDismiss = onDismiss, scrolls = false) {
        var text by rememberSaveable { mutableStateOf("") }
        var name by rememberSaveable { mutableStateOf("") }
        Column(Modifier.padding(horizontal = 20.dp).padding(bottom = 16.dp).imePadding(), verticalArrangement = Arrangement.spacedBy(12.dp)) {
            Text(PASTE_A_LIST, style = OctoType.headline, color = OctoColors.TextPrimary)
            Text(PASTE_LINE, style = OctoType.bodySmall, color = OctoColors.TextSecondary)
            GlassInput(name, { name = it }, placeholder = "Name: $PASTED_LIST_NAME")
            PasteBox(text, { text = it }, Modifier.weight(1f, fill = false).heightIn(min = 140.dp))
            Row(horizontalArrangement = Arrangement.spacedBy(10.dp)) {
                GlazeButton("Cancel", onDismiss, Modifier.weight(1f), size = ButtonSize.Medium)
                AccentButton("Import", {
                    onSend(text, name.trim())
                    text = ""
                    name = ""
                }, Modifier.weight(1f), enabled = text.isNotBlank(), size = ButtonSize.Medium)
            }
        }
    }
}

@Composable
private fun PasteBox(text: String, change: (String) -> Unit, modifier: Modifier) {
    val shape = RoundedCornerShape(16.dp)
    Box(
        modifier
            .fillMaxWidth()
            .clip(shape)
            .background(OctoColors.Accent.copy(alpha = 0.10f))
            .border(1.dp, OctoColors.Accent.copy(alpha = 0.10f), shape)
            .padding(14.dp),
    ) {
        if (text.isEmpty()) Text("Massive Attack - Angel", style = OctoType.body, color = OctoColors.TextMuted)
        BasicTextField(
            text,
            change,
            textStyle = OctoType.body.copy(color = OctoColors.TextPrimary),
            cursorBrush = SolidColor(OctoColors.Accent),
            modifier = Modifier.fillMaxSize().semantics { contentDescription = PASTE_A_LIST },
        )
    }
}

// The system's file picker, opened at Downloads, where the browser saved
// TuneMyMusic's file.
internal class OpenInDownloads : ActivityResultContracts.OpenDocument() {
    override fun createIntent(context: Context, input: Array<String>): Intent =
        super.createIntent(context, input)
            .putExtra(DocumentsContract.EXTRA_INITIAL_URI, DocumentsContract.buildDocumentUri("com.android.providers.downloads.documents", "downloads"))
}

// Reads a picked or shared file and sends it. A file too big is never read
// past the limit; the screen says why.
internal suspend fun sendPickedFile(context: Context, vm: ImportModel, uri: Uri, type: String?) {
    val read = withContext(Dispatchers.IO) {
        try {
            val resolver = context.contentResolver
            val shown = resolver.query(uri, arrayOf(OpenableColumns.DISPLAY_NAME), null, null, null)?.use { cursor ->
                if (cursor.moveToFirst() && !cursor.isNull(0)) cursor.getString(0) else null
            }
            val name = importFileName(shown, type ?: resolver.getType(uri))
            val bytes = resolver.openInputStream(uri)?.use { readAtMost(it, IMPORT_FILE_MAX_BYTES) }
            Read.File(name, bytes)
        } catch (e: IOException) {
            Read.Failed
        } catch (e: SecurityException) {
            Read.Failed
        }
    }
    when (read) {
        Read.Failed -> vm.tell("Octo could not read that file.")
        is Read.File -> if (read.bytes == null) vm.tell(FILE_TOO_BIG) else vm.sendFile(read.name, read.bytes)
    }
}

private sealed interface Read {
    // `bytes` is null for a file over the limit.
    class File(val name: String, val bytes: ByteArray?) : Read

    data object Failed : Read
}

// The stream's bytes, or null once it goes past `limit`.
internal fun readAtMost(input: InputStream, limit: Long): ByteArray? {
    val out = ByteArrayOutputStream()
    val buffer = ByteArray(64 * 1024)
    var total = 0L
    while (true) {
        val count = input.read(buffer)
        if (count < 0) return out.toByteArray()
        total += count
        if (total > limit) return null
        out.write(buffer, 0, count)
    }
}
