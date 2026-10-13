package app.winters.octo.ui.settings

import app.winters.octo.family.FamilyHub
import app.winters.octo.ui.nav.FamilyRoute
import app.winters.octo.family.family
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.text.KeyboardActions
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.runtime.staticCompositionLocalOf
import androidx.compose.ui.Modifier
import androidx.compose.ui.text.input.ImeAction
import androidx.compose.ui.text.input.KeyboardType
import androidx.compose.ui.text.input.PasswordVisualTransformation
import androidx.compose.ui.unit.dp
import androidx.hilt.lifecycle.viewmodel.compose.hiltViewModel
import androidx.lifecycle.ViewModel
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import androidx.lifecycle.viewModelScope
import androidx.navigation3.runtime.NavKey
import app.winters.octo.connection.ConnectionChooser
import app.winters.octo.connection.FolderChoice
import app.winters.octo.connection.Place
import app.winters.octo.data.KeptServers
import app.winters.octo.data.ServerLook
import app.winters.octo.data.Session
import app.winters.octo.data.SessionRepository

import app.winters.octo.data.SessionState
import app.winters.octo.data.runsOcto
import app.winters.octo.design.AccentButton
import app.winters.octo.design.GlassInput
import app.winters.octo.design.GlassPopup
import app.winters.octo.design.GlazeButton
import app.winters.octo.design.OctoColors
import app.winters.octo.design.OctoIcons
import app.winters.octo.design.OctoType
import app.winters.octo.playback.ServerSwitch
import app.winters.octo.playback.SwitchOutcome
import app.winters.octo.playlists.PlaylistSync
import app.winters.octo.server.LastSync
import app.winters.octo.server.PasswordChange
import app.winters.octo.server.PasswordDraft
import app.winters.octo.server.ServerCheck
import app.winters.octo.server.ServerSync
import app.winters.octo.server.passwordChangeWords
import app.winters.octo.server.passwordDraftProblem
import app.winters.octo.server.scanWords
import app.winters.octo.server.serverKind
import app.winters.octo.server.serverOffers
import app.winters.octo.serverupdate.upToDateLine
import app.winters.octo.subsonic.AuthMode
import app.winters.octo.subsonic.MusicFolder
import app.winters.octo.ui.common.Choice
import app.winters.octo.ui.common.ChoiceRequest
import app.winters.octo.ui.common.LocalChoiceSheet
import app.winters.octo.ui.common.LocalFeedback
import app.winters.octo.ui.common.LocalHaze
import app.winters.octo.ui.common.PopupQuestion
import app.winters.octo.ui.common.rememberOpenedBeside
import app.winters.octo.ui.nav.EditConnectionRoute
import app.winters.octo.ui.nav.OctoAdminRoute
import app.winters.octo.ui.nav.ImportRoute
import app.winters.octo.ui.nav.SignInRoute
import app.winters.octo.ui.settings.rows.ActionRow
import app.winters.octo.ui.settings.rows.ChoiceRow
import app.winters.octo.ui.settings.rows.InfoRow
import app.winters.octo.ui.settings.rows.NoteRow
import app.winters.octo.ui.settings.rows.SettingsGroup
import app.winters.octo.ui.settings.rows.SettingsPageFrame
import app.winters.octo.ui.settings.rows.SwitchRow
import dagger.hilt.android.lifecycle.HiltViewModel
import javax.inject.Inject
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.SharingStarted
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.stateIn
import kotlinx.coroutines.flow.update
import kotlinx.coroutines.launch

@HiltViewModel
class ServerViewModel @Inject constructor(
    private val sessions: SessionRepository,
    private val family: FamilyHub,
    private val sync: ServerSync,
    private val playlists: PlaylistSync,
    private val switcher: ServerSwitch,
    chooser: ConnectionChooser,
) : ViewModel() {
    val session: StateFlow<SessionState> = sessions.state

    // Every kept server, the one being switched to, and how each answered.
    val servers: StateFlow<KeptServers> = sessions.servers
    val switching: StateFlow<String?> = switcher.switching
    private val _checks = MutableStateFlow<Map<String, ServerCheck>>(emptyMap())
    val checks: StateFlow<Map<String, ServerCheck>> = _checks

    // Asks every kept server how it is. Servers signed out of are not asked.
    fun refreshChecks() {
        sessions.servers.value.servers.forEach { server ->
            viewModelScope.launch {
                val check = sessions.check(server.id)
                _checks.update { it + (server.id to check) }
            }
        }
    }

    suspend fun switchTo(id: String): SwitchOutcome = switcher.switchTo(id)

    fun signOut(id: String) = switcher.signOut(id)

    fun remove(id: String, forgetHere: Boolean) = switcher.remove(id, forgetHere)
    val syncing: StateFlow<Boolean> = sync.syncing
    val problem: StateFlow<String?> = sync.problem
    val last: StateFlow<LastSync?> = sync.last.stateIn(viewModelScope, SharingStarted.WhileSubscribed(5_000), null)
    val place: StateFlow<Place> = chooser.place

    // Whether playlists go to the server, shown while one that keeps them is connected.
    val playlistsAvailable: StateFlow<Boolean> = playlists.available.stateIn(viewModelScope, SharingStarted.WhileSubscribed(5_000), false)
    val newPlaylistsOnServer: StateFlow<Boolean> = playlists.newOnServer.stateIn(viewModelScope, SharingStarted.WhileSubscribed(5_000), false)

    fun setNewPlaylistsOnServer(on: Boolean) = playlists.setNewOnServer(on)

    fun syncNow() = sync.syncNow()

    // The server's library folders, or null when they could not be read.
    suspend fun folders(): List<MusicFolder>? = runCatching { sessions.musicFolders() }.getOrNull()

    // Limits the library to one folder (null for all) and copies it again.
    fun chooseFolder(folder: FolderChoice?) {
        viewModelScope.launch {
            sessions.chooseMusicFolder(folder)
            sync.syncAgain()
        }
    }

    fun disconnect() = sync.disconnect()

    suspend fun changePassword(current: String, new: String): PasswordChange = sessions.changePassword(current, new, family = family.model.me?.managed == true)

    // Opens "Sign in on another device" on the Family screen.
    fun signInElsewhere() = family.model.handOver.open()

    suspend fun look(): ServerLook? = sessions.look()
}

// What the server offers beyond the music, from the extensions it lists.
internal fun offersOf(extensions: Set<String>): String? = serverOffers(
    lyrics = extensions.any { it.startsWith("songLyrics:") || it.startsWith("octoLyrics:") },
    adds = extensions.any { it.startsWith("octoAcquisitions:") },
)

// The server, if one is connected: where it is, who is signed in, how fresh
// the copy of its library is, and what else it offers.
@Composable
fun ServerPage(onOpen: (NavKey) -> Unit, onBack: () -> Unit, highlight: String?, vm: ServerViewModel = hiltViewModel()) {
    val state by vm.session.collectAsStateWithLifecycle()
    val syncing by vm.syncing.collectAsStateWithLifecycle()
    val problem by vm.problem.collectAsStateWithLifecycle()
    val last by vm.last.collectAsStateWithLifecycle()
    val place by vm.place.collectAsStateWithLifecycle()
    val playlistsAvailable by vm.playlistsAvailable.collectAsStateWithLifecycle()
    val newPlaylistsOnServer by vm.newPlaylistsOnServer.collectAsStateWithLifecycle()
    val prompt = LocalDisconnectPrompt.current
    val sheet = LocalChoiceSheet.current
    val scope = rememberCoroutineScope()
    var folderProblem by remember { mutableStateOf<String?>(null) }
    var changing by remember { mutableStateOf(false) }

    val kept by vm.servers.collectAsStateWithLifecycle()

    SettingsPageFrame("Server and sync", onBack, highlight) {
        // A newer Octo for the server in use, above everything else.
        (state as? SessionState.SignedIn)?.session?.takeIf { it.runsOcto }?.let { ServerUpdateSection() }
        // Once a server is kept, the list of them leads the page.
        if (state !is SessionState.Loading && kept.servers.isNotEmpty()) ServerList(vm, onOpen, onChangePassword = { changing = true })
        when (val current = state) {
            SessionState.Loading -> Unit
            SessionState.SignedOut -> if (kept.servers.isEmpty()) {
                SettingsGroup(
                    footer = "Your server's music joins your library here.",
                ) {
                    ActionRow(SettingsIndex.ConnectServer, onClick = { onOpen(SignInRoute) })
                }
            }
            is SessionState.SignedIn -> {
                val client = current.session.client
                val connection = current.session.connection
                val copy = last?.takeIf { it.sourceId == current.session.sourceId }

                SettingsGroup(title = "Connection", icon = OctoIcons.Globe) {
                    InfoRow(SettingsIndex.ServerAddress, client.primaryUrl.toString().removeSuffix("/"))
                    // Which address is in use, when there is a choice.
                    if (connection.home != null) {
                        InfoRow(SettingsIndex.ServerConnection, if (place == Place.Home) "Connected at home" else "Connected away")
                    }
                    InfoRow(SettingsIndex.ServerUser, client.username.ifEmpty { "API key" })
                    ChoiceRow(SettingsIndex.ServerMusicFolder, value = connection.folder?.name ?: "All", onClick = {
                        scope.launch {
                            val folders = vm.folders()
                            if (folders == null) {
                                folderProblem = "Couldn't read the server's music folders."
                                return@launch
                            }
                            folderProblem = null
                            val picked = folders.indexOfFirst { it.id == connection.folder?.id } + 1
                            sheet.show(
                                ChoiceRequest(
                                    SettingsIndex.ServerMusicFolder.title,
                                    listOf(Choice("All", "Every folder on the server")) + folders.map { Choice(it.name) },
                                    picked,
                                ) { index ->
                                    val folder = folders.getOrNull(index - 1)?.let { FolderChoice(it.id, it.name) }
                                    if (folder?.id != connection.folder?.id) vm.chooseFolder(folder)
                                },
                            )
                        }
                    })
                    folderProblem?.let { NoteRow(it, color = OctoColors.Error) }
                    ActionRow(SettingsIndex.EditConnection, onClick = { onOpen(EditConnectionRoute) })
                    if (client.authMode != AuthMode.ApiKey) ActionRow(SettingsIndex.ChangePassword, onClick = { changing = true })
                    if (current.session.runsOcto) ActionRow(SettingsIndex.OctoAdmin, onClick = { onOpen(OctoAdminRoute) })
                    if (current.session.runsOcto) ActionRow(SettingsIndex.Import, onClick = { onOpen(ImportRoute) })
                    // Only while the server has Family on.
                    if (current.session.family) ActionRow(SettingsIndex.Family, onClick = { onOpen(FamilyRoute) })
                    if (current.session.family) {
                        ActionRow(SettingsIndex.SignInElsewhere, onClick = {
                            vm.signInElsewhere()
                            onOpen(FamilyRoute)
                        })
                    }
                }

                ServerFacts(vm, current.session)

                SettingsGroup(title = "Sync", icon = OctoIcons.Sync) {
                    InfoRow(SettingsIndex.LastSynced, copy?.let { timeAgo(it.at, System.currentTimeMillis()) } ?: "Not yet")
                    if (copy != null) {
                        InfoRow(null, "%,d".format(copy.songs), title = "Songs")
                        InfoRow(null, "%,d".format(copy.albums), title = "Albums")
                    }
                    ActionRow(SettingsIndex.SyncNow, onClick = vm::syncNow, busy = syncing, chevron = false)
                    problem?.let { NoteRow(it, color = OctoColors.Error) }
                    ServerQueueRow()
                    if (playlistsAvailable) {
                        SwitchRow(
                            SettingsIndex.PlaylistsToServer,
                            checked = newPlaylistsOnServer,
                            onChange = vm::setNewPlaylistsOnServer,
                            helper = "New playlists are made on your server too.",
                        )
                    }
                }

                ServerExtras(onOpen)

                SettingsGroup {
                    ActionRow(SettingsIndex.Disconnect, onClick = prompt::show, destructive = true, chevron = false)
                }
            }
        }
    }
    GlassPopup(
        visible = changing,
        anchor = null,
        onDismiss = { changing = false },
        backdrop = LocalHaze.current,
        title = SettingsIndex.ChangePassword.title,
        maxWidth = 400.dp,
    ) {
        if (changing) PasswordForm(vm) { changing = false }
    }
}

// What the server is and offers, how quickly it answers, and when it last
// looked through its folders.
@Composable
private fun ServerFacts(vm: ServerViewModel, session: Session, updates: ServerUpdateViewModel = hiltViewModel()) {
    var look by remember(session) { mutableStateOf<ServerLook?>(null) }
    LaunchedEffect(session) { look = vm.look() }
    val track by updates.track.collectAsStateWithLifecycle()
    // Octo that knows it runs the newest release says so.
    val kind = upToDateLine(track)?.takeIf { session.runsOcto } ?: serverKind(session.serverType, session.serverVersion)
    SettingsGroup(title = "Server", icon = OctoIcons.Info) {
        InfoRow(SettingsIndex.ServerKind, kind, helper = offersOf(session.extensions))
        look?.answerMs?.let { InfoRow(SettingsIndex.ServerAnswer, "$it ms") }
        scanWords(look?.scan, System.currentTimeMillis())?.let { InfoRow(SettingsIndex.ServerScan, "", helper = it) }
    }
}

// The current password, then the new one twice. Nothing is sent until the
// form is right; what the server says comes back in plain words.
@Composable
private fun PasswordForm(vm: ServerViewModel, close: () -> Unit) {
    val scope = rememberCoroutineScope()
    val feedback = LocalFeedback.current
    var draft by remember { mutableStateOf(PasswordDraft()) }
    var busy by remember { mutableStateOf(false) }
    var problem by remember { mutableStateOf<String?>(null) }
    fun change() {
        passwordDraftProblem(draft)?.let { problem = it; return }
        busy = true
        problem = null
        scope.launch {
            val result = vm.changePassword(draft.current, draft.new)
            busy = false
            if (result == PasswordChange.Changed) {
                close()
                feedback.done(passwordChangeWords(result))
            } else {
                problem = passwordChangeWords(result)
            }
        }
    }
    Column(
        Modifier.fillMaxWidth().padding(start = 20.dp, end = 20.dp, top = 18.dp, bottom = 20.dp),
        verticalArrangement = Arrangement.spacedBy(12.dp),
    ) {
        Text(SettingsIndex.ChangePassword.title, style = OctoType.body, color = OctoColors.TextPrimary)
        Text("Your other apps will ask for the new password the next time they sign in.", style = OctoType.caption, color = OctoColors.TextMuted)
        PasswordInput(draft.current, "Current password") { draft = draft.copy(current = it); problem = null }
        PasswordInput(draft.new, "New password") { draft = draft.copy(new = it); problem = null }
        PasswordInput(draft.confirm, "New password again", last = true, onDone = ::change) { draft = draft.copy(confirm = it); problem = null }
        problem?.let { Text(it, style = OctoType.caption, color = OctoColors.Error) }
        Row(horizontalArrangement = Arrangement.spacedBy(12.dp)) {
            AccentButton("Change password", onClick = ::change, loading = busy)
            GlazeButton("Cancel", onClick = close, enabled = !busy)
        }
    }
}

@Composable
private fun PasswordInput(value: String, placeholder: String, last: Boolean = false, onDone: () -> Unit = {}, onChange: (String) -> Unit) {
    GlassInput(
        value = value,
        onValueChange = onChange,
        placeholder = placeholder,
        keyboardOptions = KeyboardOptions(keyboardType = KeyboardType.Password, imeAction = if (last) ImeAction.Done else ImeAction.Next),
        keyboardActions = KeyboardActions(onDone = { onDone() }),
        visualTransformation = PasswordVisualTransformation(),
    )
}

// Whether the question before disconnecting is showing. The shell draws
// it over everything, the bar included.
class DisconnectPrompt {
    var open by mutableStateOf(false)
        private set

    fun show() {
        open = true
    }

    fun close() {
        open = false
    }
}

val LocalDisconnectPrompt = staticCompositionLocalOf<DisconnectPrompt> { error("No disconnect prompt") }

// Asks before signing out of the server in use.
@Composable
fun DisconnectSheetHost(prompt: DisconnectPrompt, vm: ServerViewModel = hiltViewModel()) {
    val state by vm.session.collectAsStateWithLifecycle()
    val name = (state as? SessionState.SignedIn)?.session?.name ?: "the server"
    GlassPopup(
        visible = prompt.open,
        anchor = rememberOpenedBeside(prompt.open),
        onDismiss = prompt::close,
        backdrop = LocalHaze.current,
        title = "Sign out",
    ) {
        PopupQuestion(
            "Sign out of $name?",
            "Its music leaves your library on this phone until you sign in again. It stays in your list, " +
                "and nothing on the server changes.",
            "Sign out",
            onConfirm = {
                vm.disconnect()
                prompt.close()
            },
            onCancel = prompt::close,
        )
    }
}
