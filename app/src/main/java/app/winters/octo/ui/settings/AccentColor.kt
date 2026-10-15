package app.winters.octo.ui.settings

import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.unit.dp
import androidx.hilt.lifecycle.viewmodel.compose.hiltViewModel
import androidx.lifecycle.ViewModel
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import androidx.lifecycle.viewModelScope
import app.winters.octo.design.AccentSwatch
import app.winters.octo.design.AccentSwatches
import app.winters.octo.design.OctoColors
import app.winters.octo.design.OctoType
import app.winters.octo.playback.PlaybackConnection
import app.winters.octo.player.ArtworkPalette
import app.winters.octo.player.PlayerColors
import app.winters.octo.player.PlayerSettings
import app.winters.octo.theme.AccentChoice
import app.winters.octo.theme.FixedAccents
import app.winters.octo.theme.accentArgb
import app.winters.octo.theme.accentHelp
import app.winters.octo.ui.settings.rows.RowFrame
import androidx.compose.ui.graphics.toArgb
import dagger.hilt.android.lifecycle.HiltViewModel
import javax.inject.Inject
import kotlinx.coroutines.ExperimentalCoroutinesApi
import kotlinx.coroutines.flow.SharingStarted
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.distinctUntilChanged
import kotlinx.coroutines.flow.flatMapLatest
import kotlinx.coroutines.flow.flowOf
import kotlinx.coroutines.flow.map
import kotlinx.coroutines.flow.mapLatest
import kotlinx.coroutines.flow.stateIn
import kotlinx.coroutines.launch

// The accent chosen in Appearance, and the colour it means now: a fixed
// one, or for From the album art the playing cover's, Octo's own while
// there is none.
@OptIn(ExperimentalCoroutinesApi::class)
@HiltViewModel
class AccentViewModel @Inject constructor(
    private val settings: PlayerSettings,
    palette: ArtworkPalette,
    playback: PlaybackConnection,
) : ViewModel() {
    val choice: StateFlow<AccentChoice?> = settings.prefs
        .map<_, AccentChoice?> { it.accent }
        .distinctUntilChanged()
        .stateIn(viewModelScope, SharingStarted.WhileSubscribed(5_000), null)

    val accent: StateFlow<Int?> = choice
        .flatMapLatest { choice ->
            when (choice) {
                null -> flowOf(null)
                AccentChoice.FromArt -> playback.now
                    .map { it.artwork }
                    .distinctUntilChanged()
                    .mapLatest { artwork -> accentArgb(choice, palette.colorsFor(artwork).seed()) }
                else -> flowOf(accentArgb(choice, null))
            }
        }
        .distinctUntilChanged()
        .stateIn(viewModelScope, SharingStarted.WhileSubscribed(5_000), null)

    fun setChoice(choice: AccentChoice) {
        viewModelScope.launch { settings.setAccent(choice) }
    }
}

// The cover's colour an accent grows from: its most vivid, or none for
// music without artwork.
private fun PlayerColors.seed(): Int? = if (this === PlayerColors.Quiet) null else mesh[1].toArgb()

// Keeps the app drawn in the chosen accent. Placed once, at the root.
@Composable
fun KeepAccent(vm: AccentViewModel = hiltViewModel()) {
    val accent by vm.accent.collectAsStateWithLifecycle()
    LaunchedEffect(accent) { accent?.let { OctoColors.useAccent(Color(it)) } }
}

// Appearance's accent picker: a circle for each accent and one for the
// playing cover's, the chosen one checked, and a line naming it and saying
// what it colours.
@Composable
fun AccentPicker(vm: AccentViewModel = hiltViewModel()) {
    val chosen = vm.choice.collectAsStateWithLifecycle().value ?: AccentChoice.Octo
    RowFrame(SettingsIndex.AccentColor) {
        Column(Modifier.weight(1f)) {
            Text(SettingsIndex.AccentColor.title, style = OctoType.body, color = OctoColors.TextPrimary)
            AccentSwatches(
                swatches = AccentChoice.entries.map { choice ->
                    AccentSwatch(choice.label, choice.argb?.let(::Color), selected = choice == chosen)
                },
                onPick = { vm.setChoice(AccentChoice.entries[it]) },
                spectrum = FixedAccents.drop(1).map { Color(it.argb!!) },
                modifier = Modifier.fillMaxWidth().padding(top = 8.dp),
            )
            Text(
                "${chosen.label}: ${accentHelp(chosen)}",
                style = OctoType.caption,
                color = OctoColors.TextMuted,
                modifier = Modifier.padding(top = 6.dp),
            )
        }
    }
}
