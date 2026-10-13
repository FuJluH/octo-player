package app.winters.octo.ui.settings

import androidx.compose.foundation.layout.padding
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.unit.dp
import androidx.hilt.lifecycle.viewmodel.compose.hiltViewModel
import androidx.lifecycle.ViewModel
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import androidx.lifecycle.viewModelScope
import app.winters.octo.ambient.AmbienceViewModel
import app.winters.octo.ambient.AmbientArea
import app.winters.octo.ambient.AmbientPrefs
import app.winters.octo.ambient.AmbientPreview
import app.winters.octo.ambient.AmbientStrength
import app.winters.octo.covers.PlaylistCoverStyle
import app.winters.octo.covers.playlistCoverStyleHelp
import app.winters.octo.covers.playlistCoverStyleName
import app.winters.octo.design.OctoIcons
import app.winters.octo.home.DefaultHomeSections
import app.winters.octo.home.homeSectionsSummary
import app.winters.octo.ui.nav.HomeSectionsRoute
import androidx.navigation3.runtime.NavKey
import app.winters.octo.player.PlayerPrefs
import app.winters.octo.player.PlayerSettings
import app.winters.octo.playlists.PlaylistArtSettings
import app.winters.octo.ui.common.Choice
import app.winters.octo.ui.common.ChoiceRequest
import app.winters.octo.ui.common.LocalChoiceSheet
import app.winters.octo.ui.settings.rows.ActionRow
import app.winters.octo.ui.settings.rows.ChoiceRow
import app.winters.octo.ui.settings.rows.SettingsGroup
import app.winters.octo.ui.settings.rows.SettingsPageFrame
import app.winters.octo.ui.settings.rows.SwitchRow
import dagger.hilt.android.lifecycle.HiltViewModel
import javax.inject.Inject
import kotlinx.coroutines.flow.SharingStarted
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.stateIn
import kotlinx.coroutines.launch

private val StrengthChoices = mapOf(
    AmbientStrength.Off to Choice("Off", "The plain dark background everywhere."),
    AmbientStrength.Subtle to Choice("Subtle", "A faint glow of the artwork's colours behind the pages."),
    AmbientStrength.Rich to Choice("Rich", "A fuller glow, still kept dark enough for text."),
)

// Whether playlists show designed covers or their album mosaics.
@HiltViewModel
class PlaylistCoversViewModel @Inject constructor(private val settings: PlaylistArtSettings) : ViewModel() {
    val style: StateFlow<PlaylistCoverStyle> = settings.style.stateIn(viewModelScope, SharingStarted.WhileSubscribed(5_000), PlaylistCoverStyle.Designed)

    fun setStyle(style: PlaylistCoverStyle) {
        viewModelScope.launch { settings.setStyle(style) }
    }
}

// The Octo-wide switch for less movement.
@HiltViewModel
class MotionViewModel @Inject constructor(private val settings: PlayerSettings) : ViewModel() {
    val prefs: StateFlow<PlayerPrefs> = settings.prefs.stateIn(viewModelScope, SharingStarted.WhileSubscribed(5_000), PlayerPrefs())

    fun setReduceMotion(on: Boolean) {
        viewModelScope.launch { settings.setReduceMotion(on) }
    }
}

// How the app looks: the artwork's colours glowing behind the pages, how
// strongly and where, Home's sections, the player's background, and how
// much moves.
@Composable
fun AppearancePage(
    onOpen: (NavKey) -> Unit,
    onBack: () -> Unit,
    highlight: String?,
    vm: AmbienceViewModel = hiltViewModel(),
    motion: MotionViewModel = hiltViewModel(),
    covers: PlaylistCoversViewModel = hiltViewModel(),
    home: HomeSectionsViewModel = hiltViewModel(),
) {
    val prefs = vm.prefs.collectAsStateWithLifecycle().value ?: AmbientPrefs()
    val sections by home.sections.collectAsStateWithLifecycle()
    val motionPrefs by motion.prefs.collectAsStateWithLifecycle()
    val coverStyle by covers.style.collectAsStateWithLifecycle()
    val sheet = LocalChoiceSheet.current

    SettingsPageFrame("Appearance", onBack, highlight) {
        AmbientPreview(prefs.strength, Modifier.padding(horizontal = 16.dp))
        SettingsGroup {
            ChoiceRow(SettingsIndex.Ambient, value = StrengthChoices.getValue(prefs.strength).label, onClick = {
                val options = AmbientStrength.entries
                sheet.show(
                    ChoiceRequest(SettingsIndex.Ambient.title, options.map(StrengthChoices::getValue), options.indexOf(prefs.strength)) {
                        vm.setStrength(options[it])
                    },
                )
            })
        }
        if (prefs.strength != AmbientStrength.Off) {
            SettingsGroup(title = "Where it shows", icon = OctoIcons.Layout) {
                SwitchRow(SettingsIndex.AmbientHome, prefs.home, { vm.setArea(AmbientArea.Home, it) })
                SwitchRow(
                    SettingsIndex.AmbientLibrary,
                    prefs.library,
                    { vm.setArea(AmbientArea.Library, it) },
                )
                SwitchRow(SettingsIndex.AmbientSearch, prefs.search, { vm.setArea(AmbientArea.Search, it) })
                SwitchRow(SettingsIndex.AmbientSettings, prefs.settings, { vm.setArea(AmbientArea.Settings, it) })
                SwitchRow(SettingsIndex.AmbientBar, prefs.bar, vm::setBar, helper = "A trace of the song's colour in its glass.")
                SwitchRow(
                    SettingsIndex.AmbientPageArtwork,
                    prefs.pageArtwork,
                    vm::setPageArtwork,
                    helper = "The glow follows the page's album or artist, not the song.",
                )
            }
        }
        SettingsGroup(title = "Home", icon = OctoIcons.Home) {
            ActionRow(
                SettingsIndex.HomeSections,
                onClick = { onOpen(HomeSectionsRoute) },
                helper = homeSectionsSummary(sections ?: DefaultHomeSections),
            )
        }
        PlayerBackgroundSection()
        SettingsGroup(title = "Playlists", icon = OctoIcons.Playlists) {
            ChoiceRow(SettingsIndex.PlaylistCovers, value = playlistCoverStyleName(coverStyle), onClick = {
                val options = PlaylistCoverStyle.entries
                sheet.show(
                    ChoiceRequest(
                        SettingsIndex.PlaylistCovers.title,
                        options.map { Choice(playlistCoverStyleName(it), playlistCoverStyleHelp(it)) },
                        options.indexOf(coverStyle),
                    ) { covers.setStyle(options[it]) },
                )
            })
        }
        SettingsGroup(title = "Motion", icon = OctoIcons.Sparkle) {
            SwitchRow(
                SettingsIndex.ReduceMotion,
                checked = motionPrefs.reduceMotion,
                onChange = motion::setReduceMotion,
                helper = "Backgrounds and lyrics hold still. On by itself when the phone's animations are off.",
            )
        }
    }
}
