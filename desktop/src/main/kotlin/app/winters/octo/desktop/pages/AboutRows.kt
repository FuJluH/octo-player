package app.winters.octo.desktop.pages

import app.winters.octo.desktop.system.OctopusPainter
import androidx.compose.foundation.Image
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.runtime.Composable
import androidx.compose.runtime.remember
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.painter.Painter
import app.winters.octo.design.FrameSize
import app.winters.octo.design.DesktopType
import app.winters.octo.design.OctoColors
import app.winters.octo.design.Space
import app.winters.octo.design.Txt
import app.winters.octo.desktop.AppState
import app.winters.octo.desktop.settings.AppSettings
import app.winters.octo.desktop.settings.DesktopOs
import app.winters.octo.desktop.system.LocalSystem
import app.winters.octo.desktop.update.UpdaterAvailability
import app.winters.octo.update.InstallWhen
import app.winters.octo.update.UpdatePrefs
import kotlinx.coroutines.launch

// Settings > About: Octo and its version, a ready update with what is new
// in it, and how Octo looks for new versions.
@Composable
internal fun AboutRows(app: AppState, settings: AppSettings) {
    val updates = app.updates
    val ready = updates?.ready
    AboutCard()
    Rows {
        if (updates != null && ready != null) {
            SettingRow("Update ready: ${ready.version}", updates.installHelp(ready)) {
                val system = LocalSystem.current
                RowAction(updates.installAction, { updates.install(quit = { system?.quit?.invoke() }) })
            }
        }
    }
    if (ready != null && ready.notes.isNotBlank()) {
        Card {
            Txt(
                ready.notes.trim(),
                DesktopType.meta,
                OctoColors.TextSecondary,
                Modifier.fillMaxWidth().padding(horizontal = RowInset, vertical = Space.L),
                maxLines = NOTES_LINES,
            )
        }
    }
    if (updates == null) return
    val prefs = settings.updates
    fun change(edit: (UpdatePrefs) -> UpdatePrefs) = app.settings.update { it.copy(updates = edit(it.updates)) }
    Group("Updates") {
        val availability = updates.availability
        if (availability is UpdaterAvailability.Off || !updates.enabled) {
            SettingRow("New versions", (availability as? UpdaterAvailability.Off)?.why)
            return@Group
        }
        SwitchRow(
            "Check for updates automatically",
            "Looks every few hours and downloads in the background.",
            prefs.checkAutomatically,
        ) { on -> change { it.copy(checkAutomatically = on) } }
        if (app.os == DesktopOs.Windows) {
            ChoiceRow(
                "Install updates",
                installHelp(prefs.install),
                InstallWhen.entries,
                prefs.install,
                ::installName,
            ) { choice -> change { it.copy(install = choice) } }
        }
        SwitchRow(
            "Try early versions",
            "Before they're finished. They can have rough edges.",
            prefs.earlyVersions,
        ) { on -> change { it.copy(earlyVersions = on) } }
        ActionRow(
            "New versions",
            updates.lastLine ?: "Signed releases from GitHub.",
            if (updates.checking) "Checking" else "Check now",
            { app.scope.launch { updates.check() } },
            enabled = !updates.checking,
        )
    }
}

// Octo's octopus, its name and the version.
@Composable
private fun AboutCard() {
    val octopus = remember { octopusPicture() }
    Card {
        Row(
            Modifier.padding(horizontal = RowInset, vertical = Space.Xl),
            verticalAlignment = Alignment.CenterVertically,
            horizontalArrangement = Arrangement.spacedBy(Space.Xl),
        ) {
            octopus?.let { Image(it, contentDescription = null, modifier = Modifier.size(FrameSize.OpeningMark / 2)) }
            Column {
                Txt("Octo", DesktopType.section)
                val version = appVersion()
                Txt(if (version.first().isDigit()) "Version $version" else version, DesktopType.meta, OctoColors.TextMuted, Modifier.padding(top = Space.Xxs))
            }
        }
    }
}

// The octopus the window opens on, drawn from the vector at its size.
private fun octopusPicture(): Painter = OctopusPainter()

// How many lines of a release's notes show under its row.
private const val NOTES_LINES = 12

internal fun installName(choice: InstallWhen): String = when (choice) {
    InstallWhen.Ask -> "Ask me"
    InstallWhen.OnQuit -> "When I quit"
}

private fun installHelp(choice: InstallWhen): String = when (choice) {
    InstallWhen.Ask -> "A ready update waits here until you choose Restart to update."
    InstallWhen.OnQuit -> "A ready update goes in when you quit Octo, and it's new the next time you open it."
}
