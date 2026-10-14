package app.winters.octo.ui.settings

import androidx.annotation.DrawableRes
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.text.KeyboardActions
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.Icon
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.produceState
import androidx.compose.runtime.remember
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.platform.LocalFocusManager
import androidx.compose.ui.res.painterResource
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.text.input.ImeAction
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.hilt.lifecycle.viewmodel.compose.hiltViewModel
import androidx.lifecycle.ViewModel
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import androidx.lifecycle.viewModelScope
import androidx.navigation3.runtime.NavKey
import app.winters.octo.BuildConfig
import app.winters.octo.catalog.CatalogDao
import app.winters.octo.connection.ConnectionChooser
import app.winters.octo.connection.Place
import app.winters.octo.data.KeptServers
import app.winters.octo.data.SessionRepository
import app.winters.octo.data.SessionState
import app.winters.octo.design.GlassInput
import app.winters.octo.design.OctoColors
import app.winters.octo.design.OctoIcons
import app.winters.octo.design.OctoType
import app.winters.octo.device.DEVICE
import app.winters.octo.device.DeviceLibrary
import app.winters.octo.listening.ListenBrainzPrefs
import app.winters.octo.listening.ListenBrainzSync
import app.winters.octo.lyrics.LyricsTiming
import app.winters.octo.offline.OfflinePrefs
import app.winters.octo.offline.OfflineSettings
import app.winters.octo.player.LiveBackgroundSupported
import app.winters.octo.player.PlayerPrefs
import app.winters.octo.player.PlayerSettings
import app.winters.octo.player.StreamPrefs
import app.winters.octo.server.LastSync
import app.winters.octo.server.ServerSync
import app.winters.octo.sound.SoundEngine
import app.winters.octo.sound.SoundSettings
import app.winters.octo.ui.common.ScreenTitle
import app.winters.octo.ui.common.screenPadding
import app.winters.octo.ui.nav.SettingsPageRoute
import app.winters.octo.ui.nav.SignInRoute
import app.winters.octo.ui.nav.SoundRoute
import app.winters.octo.ui.settings.rows.ActionRow
import app.winters.octo.ui.settings.rows.CategoryRow
import app.winters.octo.ui.settings.rows.IconRowInset
import app.winters.octo.ui.settings.rows.IconTile
import app.winters.octo.ui.settings.rows.NoteRow
import app.winters.octo.ui.settings.rows.SettingsGroup
import app.winters.octo.ui.sound.SoundScreen
import app.winters.octo.ui.sound.soundSummary
import dagger.hilt.android.lifecycle.HiltViewModel
import javax.inject.Inject
import kotlinx.coroutines.delay
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.SharingStarted
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.stateIn

// How often the front page's "Synced 5 min ago" is worked out again.
private const val CLOCK_MS = 30_000L

@HiltViewModel
class SettingsViewModel @Inject constructor(
    val library: DeviceLibrary,
    dao: CatalogDao,
    player: PlayerSettings,
    soundEngine: SoundEngine,
    offline: OfflineSettings,
    lyrics: LyricsTiming,
    listenBrainz: ListenBrainzSync,
    sessions: SessionRepository,
    sync: ServerSync,
    chooser: ConnectionChooser,
) : ViewModel() {
    private fun <T> Flow<T>.held(initial: T): StateFlow<T> =
        stateIn(viewModelScope, SharingStarted.WhileSubscribed(5_000), initial)

    // What the category lines say.
    val sound: StateFlow<SoundSettings> = soundEngine.current
    val playerPrefs: StateFlow<PlayerPrefs> = player.prefs.held(PlayerPrefs())
    val streamPrefs: StateFlow<StreamPrefs> = player.streamPrefs.held(StreamPrefs())
    val offlinePrefs: StateFlow<OfflinePrefs> = offline.prefs.held(OfflinePrefs())
    val keepScreenOn: StateFlow<Boolean> = lyrics.keepScreenOn.held(true)
    val listenBrainz: StateFlow<ListenBrainzPrefs> = listenBrainz.prefs.held(ListenBrainzPrefs())
    val songCount: StateFlow<Int> = dao.trackCount(DEVICE).held(0)

    // The server, for the account card.
    val session: StateFlow<SessionState> = sessions.state
    val servers: StateFlow<KeptServers> = sessions.servers
    val syncing: StateFlow<Boolean> = sync.syncing
    val problem: StateFlow<String?> = sync.problem
    val last: StateFlow<LastSync?> = sync.last.held(null)
    val place: StateFlow<Place> = chooser.place
}

// Where a setting's page is: Sound has a page of its own.
private fun routeFor(page: SettingsPage, highlight: String? = null): NavKey =
    if (page == SettingsPage.Sound) SoundRoute else SettingsPageRoute(page, highlight)

// Settings' front page: the account, a search across every setting, and
// the categories, each with a line on how it is set now.
@Composable
fun SettingsScreen(onOpen: (NavKey) -> Unit, vm: SettingsViewModel = hiltViewModel()) {
    var query by rememberSaveable { mutableStateOf("") }
    val padding = screenPadding()

    Column(
        Modifier
            .fillMaxSize()
            .verticalScroll(rememberScrollState())
            .padding(top = padding.calculateTopPadding(), bottom = padding.calculateBottomPadding()),
        verticalArrangement = Arrangement.spacedBy(20.dp),
    ) {
        ScreenTitle("Settings", Modifier.padding(bottom = 0.dp))
        AccountCard(onOpen, vm)
        SearchField(query, onChange = { query = it })
        if (query.isNotBlank()) {
            Results(searchSettings(query), onOpen)
        } else {
            Categories(onOpen, vm)
        }
    }
}

// The server signed in to and how it is doing, and the music on the phone.
@Composable
private fun AccountCard(onOpen: (NavKey) -> Unit, vm: SettingsViewModel) {
    val state by vm.session.collectAsStateWithLifecycle()
    val kept by vm.servers.collectAsStateWithLifecycle()
    val syncing by vm.syncing.collectAsStateWithLifecycle()
    val problem by vm.problem.collectAsStateWithLifecycle()
    val last by vm.last.collectAsStateWithLifecycle()
    val place by vm.place.collectAsStateWithLifecycle()
    val access by vm.library.access.collectAsStateWithLifecycle()
    val songs by vm.songCount.collectAsStateWithLifecycle()
    val now by rememberClock()

    SettingsGroup(separatorInset = IconRowInset) {
        when (val current = state) {
            SessionState.Loading -> Unit
            SessionState.SignedOut -> if (kept.servers.isEmpty()) {
                AccountRow(
                    icon = OctoIcons.Cloud,
                    title = "Connect a music server",
                    lines = listOf("Add the music on your own server" to OctoColors.TextMuted),
                    onClick = { onOpen(SignInRoute) },
                )
            } else {
                // Servers are kept, none in use: the list is where to go.
                AccountRow(
                    icon = OctoIcons.Cloud,
                    title = "Your servers",
                    lines = listOf("Signed out. Sign in to one, or add another." to OctoColors.TextMuted),
                    onClick = { onOpen(routeFor(SettingsPage.Server)) },
                )
            }
            is SessionState.SignedIn -> {
                val session = current.session
                val copy = last?.takeIf { it.sourceId == session.sourceId }
                val status = problem ?: serverStatus(
                    syncing = syncing,
                    place = place.takeIf { session.connection.home != null },
                    syncedAt = copy?.at,
                    now = now,
                )
                AccountRow(
                    icon = OctoIcons.Cloud,
                    title = session.name,
                    lines = listOf(
                        session.client.username.ifEmpty { "Signed in with a key" } to OctoColors.TextSecondary,
                        status to if (problem != null) OctoColors.Error else OctoColors.TextMuted,
                    ),
                    onClick = { onOpen(routeFor(SettingsPage.Server)) },
                )
            }
        }
        AccountRow(
            icon = OctoIcons.Phone,
            title = phoneLine(access, songs),
            lines = emptyList(),
            onClick = { onOpen(routeFor(SettingsPage.Library)) },
        )
    }
}

// The current time, moving on every half minute, for "Synced 5 min ago".
@Composable
private fun rememberClock() = produceState(System.currentTimeMillis()) {
    while (true) {
        delay(CLOCK_MS)
        value = System.currentTimeMillis()
    }
}

@Composable
private fun AccountRow(@DrawableRes icon: Int, title: String, lines: List<Pair<String, Color>>, onClick: () -> Unit) {
    Row(
        Modifier
            .fillMaxWidth()
            .clickable(role = Role.Button, onClick = onClick)
            .heightIn(min = 56.dp)
            .padding(horizontal = 16.dp, vertical = 12.dp),
        verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.spacedBy(16.dp),
    ) {
        IconTile(icon)
        Column(Modifier.weight(1f)) {
            Text(title, style = OctoType.body, color = OctoColors.TextPrimary, maxLines = 1, overflow = TextOverflow.Ellipsis)
            lines.forEach { (text, color) ->
                Text(text, style = OctoType.caption, color = color, maxLines = 1, overflow = TextOverflow.Ellipsis)
            }
        }
        Icon(painterResource(OctoIcons.Chevron), contentDescription = null, tint = OctoColors.TextMuted, modifier = Modifier.size(20.dp))
    }
}

@Composable
private fun SearchField(query: String, onChange: (String) -> Unit) {
    val focus = LocalFocusManager.current
    GlassInput(
        value = query,
        onValueChange = onChange,
        placeholder = "Search settings",
        keyboardOptions = KeyboardOptions(imeAction = ImeAction.Search),
        // The results show as you type, so Search only puts the keyboard away.
        keyboardActions = KeyboardActions(onSearch = { focus.clearFocus() }),
        modifier = Modifier.padding(horizontal = 16.dp),
        trailing = {
            if (query.isEmpty()) {
                Icon(painterResource(OctoIcons.Search), contentDescription = null, tint = OctoColors.TextMuted, modifier = Modifier.size(20.dp))
            } else {
                Icon(
                    painterResource(OctoIcons.Close),
                    contentDescription = "Clear search",
                    tint = OctoColors.TextMuted,
                    modifier = Modifier.size(20.dp).clickable(role = Role.Button) { onChange("") },
                )
            }
        },
    )
}

// What a search found: each setting, with the page it is on.
@Composable
private fun Results(found: List<SettingEntry>, onOpen: (NavKey) -> Unit) {
    SettingsGroup {
        if (found.isEmpty()) NoteRow("No settings match.")
        found.forEach { entry ->
            ActionRow(null, title = entry.title, helper = entry.place, onClick = { onOpen(routeFor(entry.page, entry.id)) })
        }
    }
}

@Composable
private fun Categories(onOpen: (NavKey) -> Unit, vm: SettingsViewModel) {
    val player by vm.playerPrefs.collectAsStateWithLifecycle()
    val sound by vm.sound.collectAsStateWithLifecycle()
    val stream by vm.streamPrefs.collectAsStateWithLifecycle()
    val offline by vm.offlinePrefs.collectAsStateWithLifecycle()
    val keepScreenOn by vm.keepScreenOn.collectAsStateWithLifecycle()
    val listenBrainz by vm.listenBrainz.collectAsStateWithLifecycle()
    val access by vm.library.access.collectAsStateWithLifecycle()
    val songs by vm.songCount.collectAsStateWithLifecycle()
    val folders by vm.library.folders.collectAsStateWithLifecycle()
    val state by vm.session.collectAsStateWithLifecycle()
    val syncing by vm.syncing.collectAsStateWithLifecycle()
    val last by vm.last.collectAsStateWithLifecycle()
    val now by rememberClock()
    val open = remember(onOpen) { { page: SettingsPage -> onOpen(routeFor(page)) } }

    val serverLine = when (val current = state) {
        SessionState.Loading -> ""
        SessionState.SignedOut -> "Not connected"
        is SessionState.SignedIn -> serverStatus(syncing, null, last?.takeIf { it.sourceId == current.session.sourceId }?.at, now)
    }

    SettingsGroup(title = "Listening", separatorInset = IconRowInset) {
        CategoryRow(OctoIcons.Playback, SettingsPage.Playback.title, playbackSummary(player)) { open(SettingsPage.Playback) }
        CategoryRow(OctoIcons.Sound, SettingsPage.Sound.title, soundSummary(sound)) { open(SettingsPage.Sound) }
        CategoryRow(
            OctoIcons.Appearance,
            SettingsPage.Appearance.title,
            appearanceSummary(player.ambient, player.liveBackground && LiveBackgroundSupported),
        ) { open(SettingsPage.Appearance) }
    }
    SettingsGroup(title = "Your music", separatorInset = IconRowInset) {
        CategoryRow(OctoIcons.Library, SettingsPage.Library.title, librarySummary(access, songs, folders)) { open(SettingsPage.Library) }
        val updateWaits = rememberServerUpdateDot()
        CategoryRow(OctoIcons.Cloud, SettingsPage.Server.title, serverLine, mark = if (updateWaits) SERVER_UPDATE_MARK else null) { open(SettingsPage.Server) }
        CategoryRow(OctoIcons.Download, SettingsPage.Streaming.title, streamingSummary(stream, offline)) { open(SettingsPage.Streaming) }
        CategoryRow(OctoIcons.AudioQuality, SettingsPage.AudioQuality.title, "At home, away, on Wi-Fi and on mobile data") { open(SettingsPage.AudioQuality) }
    }
    SettingsGroup(title = "Lyrics and history", separatorInset = IconRowInset) {
        CategoryRow(OctoIcons.Lyrics, SettingsPage.Lyrics.title, lyricsSummary(player.lyricsOnline, keepScreenOn)) { open(SettingsPage.Lyrics) }
        CategoryRow(OctoIcons.Scrobbling, SettingsPage.Scrobbling.title, scrobblingSummary(listenBrainz)) { open(SettingsPage.Scrobbling) }
    }
    SettingsGroup(title = "This app", separatorInset = IconRowInset) {
        CategoryRow(OctoIcons.Backup, SettingsPage.Backup.title, BACKUP_SUMMARY) { open(SettingsPage.Backup) }
        // A ready update shows here, quietly, in place of the version.
        val updates = hiltViewModel<UpdatesViewModel>()
        val update by updates.state.collectAsStateWithLifecycle()
        CategoryRow(OctoIcons.Info, SettingsPage.About.title, aboutSummary(BuildConfig.VERSION_NAME, update.ready?.version?.toString())) { open(SettingsPage.About) }
    }
}

// A category's page, by the page it names.
@Composable
fun SettingsPageScreen(page: SettingsPage, highlight: String?, onOpen: (NavKey) -> Unit, onBack: () -> Unit) {
    when (page) {
        SettingsPage.Playback -> PlaybackPage(onBack, highlight)
        // Sound opens its own page; this stands in should a stored route name it.
        SettingsPage.Sound -> SoundScreen(onBack)
        SettingsPage.Appearance -> AppearancePage(onOpen, onBack, highlight)
        SettingsPage.Library -> LibraryPage(onBack, highlight)
        SettingsPage.Server -> ServerPage(onOpen, onBack, highlight)
        SettingsPage.Streaming -> StreamingPage(onOpen, onBack, highlight)
        SettingsPage.AudioQuality -> AudioQualityPage(onBack, highlight)
        SettingsPage.Lyrics -> LyricsPage(onBack, highlight)
        SettingsPage.Scrobbling -> ScrobblingPage(onBack, highlight)
        SettingsPage.Backup -> BackupPage(onBack, highlight)
        SettingsPage.About -> AboutPage(onBack, highlight)
    }
}
