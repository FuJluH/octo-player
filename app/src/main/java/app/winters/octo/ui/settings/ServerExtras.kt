package app.winters.octo.ui.settings

import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue
import androidx.hilt.lifecycle.viewmodel.compose.hiltViewModel
import androidx.lifecycle.ViewModel
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import androidx.lifecycle.viewModelScope
import androidx.navigation3.runtime.NavKey
import app.winters.octo.design.OctoIcons
import app.winters.octo.server.QueueSync
import app.winters.octo.server.ScanState
import app.winters.octo.server.ServerControls
import app.winters.octo.subsonic.NowPlayingEntry
import app.winters.octo.subsonic.SubsonicException
import app.winters.octo.ui.nav.SharesRoute
import app.winters.octo.ui.server.minutesAgo
import app.winters.octo.ui.server.scanLabel
import app.winters.octo.ui.settings.rows.ActionRow
import app.winters.octo.ui.settings.rows.InfoRow
import app.winters.octo.ui.settings.rows.SettingsGroup
import app.winters.octo.ui.settings.rows.SwitchRow
import dagger.hilt.android.lifecycle.HiltViewModel
import javax.inject.Inject
import kotlinx.coroutines.delay
import kotlinx.coroutines.flow.SharingStarted
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.stateIn
import kotlinx.coroutines.launch

// How often "Listening now" is read again while the page is on screen.
private const val LISTENING_EVERY_MS = 60_000L

@HiltViewModel
class ServerExtrasViewModel @Inject constructor(
    private val controls: ServerControls,
    private val queue: QueueSync,
) : ViewModel() {
    val queueSync: StateFlow<Boolean> = queue.enabled.stateIn(viewModelScope, SharingStarted.WhileSubscribed(5_000), true)
    val admin: StateFlow<Boolean> = controls.admin
    val sharing: StateFlow<Boolean> = controls.sharing
    val scan: StateFlow<ScanState> = controls.scan

    var listening by mutableStateOf<List<NowPlayingEntry>>(emptyList())
        private set

    init {
        // Asks once whether the server shares at all, so the row only shows
        // where links can be made.
        viewModelScope.launch {
            try {
                controls.shares()
            } catch (e: SubsonicException) {
                // Remembered by the controls when sharing is off.
            }
        }
    }

    fun setQueueSync(on: Boolean) = queue.setEnabled(on)

    fun scanNow() = controls.startScan()

    suspend fun readListening() {
        listening = try {
            controls.listening()
        } catch (e: SubsonicException) {
            emptyList()
        }
    }
}

// Keeping the play queue on the server, in the Sync group.
@Composable
internal fun ServerQueueRow(vm: ServerExtrasViewModel = hiltViewModel()) {
    val queueSync by vm.queueSync.collectAsStateWithLifecycle()
    SwitchRow(
        SettingsIndex.QueueSync,
        checked = queueSync,
        onChange = vm::setQueueSync,
        helper = "Keeps what's playing on the server, so you can pick up where another device left off.",
    )
}

// What else the server offers: shared links, a library scan for admins, and
// who is listening now. Its radio stations are under Settings, Radio.
@Composable
internal fun ServerExtras(onOpen: (NavKey) -> Unit, vm: ServerExtrasViewModel = hiltViewModel()) {
    val admin by vm.admin.collectAsStateWithLifecycle()
    val sharing by vm.sharing.collectAsStateWithLifecycle()
    val scan by vm.scan.collectAsStateWithLifecycle()

    LaunchedEffect(Unit) {
        while (true) {
            vm.readListening()
            delay(LISTENING_EVERY_MS)
        }
    }

    if (sharing || admin) {
        SettingsGroup(title = "On the server", icon = OctoIcons.Cloud) {
            if (sharing) ActionRow(SettingsIndex.Shares, onClick = { onOpen(SharesRoute) })
            if (admin) ScanRow(scan, vm::scanNow)
        }
    }
    if (vm.listening.isNotEmpty()) {
        SettingsGroup(title = SettingsIndex.ListeningNow.title, icon = OctoIcons.Listeners) {
            vm.listening.forEach { ListenerRow(it) }
        }
    }
}

// "Scan library now", then how far the scan is, then that it finished.
@Composable
private fun ScanRow(state: ScanState, onScan: () -> Unit) {
    ActionRow(
        SettingsIndex.ScanServer,
        title = scanLabel(state),
        onClick = onScan,
        busy = state is ScanState.Scanning,
        destructive = state is ScanState.Failed,
        chevron = false,
    )
}

// Someone listening: the song, then who, on which player, and when it started.
@Composable
private fun ListenerRow(entry: NowPlayingEntry) {
    val song = listOfNotNull(entry.title.takeIf(String::isNotBlank), entry.artist?.takeIf(String::isNotBlank)).joinToString(" · ")
    val who = listOfNotNull(
        entry.username.takeIf(String::isNotBlank),
        entry.playerName?.takeIf(String::isNotBlank),
        minutesAgo(entry.minutesAgo),
    ).joinToString(" · ")
    InfoRow(null, value = "", title = song, helper = who)
}
