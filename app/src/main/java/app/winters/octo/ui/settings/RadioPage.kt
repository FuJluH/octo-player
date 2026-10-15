package app.winters.octo.ui.settings

import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.hilt.lifecycle.viewmodel.compose.hiltViewModel
import androidx.lifecycle.ViewModel
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import androidx.lifecycle.viewModelScope
import androidx.navigation3.runtime.NavKey
import app.winters.octo.data.SessionRepository
import app.winters.octo.data.SessionState
import app.winters.octo.player.PlayerPrefs
import app.winters.octo.player.PlayerSettings
import app.winters.octo.radio.LIVE_RADIO_ABOUT
import app.winters.octo.radio.RadioAdventure
import app.winters.octo.radio.RadioDiscovery
import app.winters.octo.radio.RadioVariety
import app.winters.octo.radio.SONG_RADIO
import app.winters.octo.radio.SONG_RADIO_ABOUT
import app.winters.octo.radio.discoveryRowLook
import app.winters.octo.ui.common.Choice
import app.winters.octo.ui.common.ChoiceRequest
import app.winters.octo.ui.common.LocalChoiceSheet
import app.winters.octo.ui.nav.LiveRadioNearRoute
import app.winters.octo.ui.nav.RadioStationsRoute
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

@HiltViewModel
class RadioSettingsViewModel @Inject constructor(
    private val settings: PlayerSettings,
    sessions: SessionRepository,
) : ViewModel() {
    val prefs: StateFlow<PlayerPrefs> = settings.prefs.stateIn(viewModelScope, SharingStarted.WhileSubscribed(5_000), PlayerPrefs())
    val session: StateFlow<SessionState> = sessions.state

    private fun change(block: suspend PlayerSettings.() -> Unit) {
        viewModelScope.launch { settings.block() }
    }

    fun setDiscovery(discovery: RadioDiscovery) = change { setRadioDiscovery(discovery) }
    fun setAdventure(adventure: RadioAdventure) = change { setRadioAdventure(adventure) }
    fun setVariety(variety: RadioVariety) = change { setRadioVariety(variety) }
    fun setFavorites(on: Boolean) = change { setRadioFavorites(on) }
}

// Radio, in two parts that say which is which: song radio, which Octo mixes
// from your music when a radio is started from a song, album or artist (and
// for Autoplay), and live radio, the stations on the air.
@Composable
fun RadioPage(onOpen: (NavKey) -> Unit, onBack: () -> Unit, highlight: String?, vm: RadioSettingsViewModel = hiltViewModel()) {
    val prefs by vm.prefs.collectAsStateWithLifecycle()
    val session by vm.session.collectAsStateWithLifecycle()
    val sheet = LocalChoiceSheet.current

    SettingsPageFrame(SettingsPage.Radio.title, onBack, highlight) {
        SettingsGroup(title = SONG_RADIO, footer = SONG_RADIO_ABOUT) {
            val discoveries = RadioDiscovery.entries
            val discovery = discoveryRowLook(prefs.radioDiscovery, prefs.libraryOnly, where = "Library settings")
            ChoiceRow(
                SettingsIndex.RadioDiscovery,
                value = discovery.value,
                enabled = discovery.choosable,
                helper = discovery.helper,
                onClick = {
                    sheet.show(
                        ChoiceRequest(SettingsIndex.RadioDiscovery.title, discoveries.map { Choice(it.label, it.detail) }, discoveries.indexOf(prefs.radioDiscovery)) {
                            vm.setDiscovery(discoveries[it])
                        },
                    )
                },
            )
            val adventures = RadioAdventure.entries
            ChoiceRow(SettingsIndex.RadioAdventure, value = prefs.radioAdventure.label, helper = prefs.radioAdventure.detail, onClick = {
                sheet.show(
                    ChoiceRequest(SettingsIndex.RadioAdventure.title, adventures.map { Choice(it.label, it.detail) }, adventures.indexOf(prefs.radioAdventure)) {
                        vm.setAdventure(adventures[it])
                    },
                )
            })
            val varieties = RadioVariety.entries
            ChoiceRow(SettingsIndex.RadioVariety, value = prefs.radioVariety.label, helper = prefs.radioVariety.detail, onClick = {
                sheet.show(
                    ChoiceRequest(SettingsIndex.RadioVariety.title, varieties.map { Choice(it.label, it.detail) }, varieties.indexOf(prefs.radioVariety)) {
                        vm.setVariety(varieties[it])
                    },
                )
            })
            SwitchRow(
                SettingsIndex.RadioFavorites,
                checked = prefs.radioFavorites,
                onChange = vm::setFavorites,
                helper = "Songs you hearted or rated 4 or 5 stars come around more often.",
            )
        }
        SettingsGroup(title = LIVE_RADIO, footer = LIVE_RADIO_ABOUT) {
            ActionRow(
                SettingsIndex.LiveRadioNear,
                onClick = { onOpen(LiveRadioNearRoute) },
                helper = "Stations on the air around a place, to play or keep.",
            )
            val signedIn = session is SessionState.SignedIn
            ActionRow(
                SettingsIndex.RadioStations,
                onClick = { onOpen(RadioStationsRoute) },
                enabled = signedIn,
                helper = if (signedIn) "Play them, and add or change them as an admin." else "Connect a server to see the stations it keeps.",
            )
        }
    }
}
