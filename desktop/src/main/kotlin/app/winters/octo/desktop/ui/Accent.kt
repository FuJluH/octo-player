package app.winters.octo.desktop.ui

import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.runtime.produceState
import androidx.compose.ui.graphics.Color
import app.winters.octo.design.OctoColors
import app.winters.octo.desktop.AppState
import app.winters.octo.player.immersive.WashTuning
import app.winters.octo.theme.AccentChoice
import app.winters.octo.theme.accentArgb

// Keeps the app, the mini player included, drawn in the chosen accent: a
// fixed one, or for From the album art the playing cover's main colour,
// Octo's own while nothing with a cover plays. Placed once, in the main
// window, which stays composed while it is hidden.
@Composable
fun KeepAccent(app: AppState) {
    val settings by app.settings.state.collectAsState()
    val choice = settings.appearance.accent
    val state by app.player.state.collectAsState()
    val coverId = if (choice == AccentChoice.FromArt) state.current?.song?.coverArt else null
    val connection = app.connection
    val wash = settings.appearance.wash
    val tuning = WashTuning(wash.contrast, wash.saturation / 100f, wash.brightnessCap / 100f)
    val art by produceState<Int?>(null, coverId, connection, tuning) {
        // The last cover's colour stays until the next one is read.
        if (coverId == null || connection == null) value = null
        else app.washCovers.follow(connection.client, coverId, tuning).collect { value = it.main.takeIf { main -> main != 0 } }
    }
    LaunchedEffect(choice, art) { OctoColors.useAccent(Color(accentArgb(choice, art))) }
}
