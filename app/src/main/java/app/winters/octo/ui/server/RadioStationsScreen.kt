package app.winters.octo.ui.server

import android.util.Log
import androidx.compose.animation.core.animateFloatAsState
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.Icon
import androidx.compose.material3.IconButton
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.key
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.draw.alpha
import androidx.compose.ui.res.painterResource
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.text.input.ImeAction
import androidx.compose.ui.text.input.KeyboardCapitalization
import androidx.compose.ui.text.input.KeyboardType
import androidx.compose.ui.text.style.TextOverflow
import androidx.compose.ui.unit.dp
import androidx.hilt.lifecycle.viewmodel.compose.hiltViewModel
import androidx.lifecycle.ViewModel
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import androidx.lifecycle.viewModelScope
import androidx.navigation3.runtime.NavKey
import app.winters.octo.data.userMessage
import app.winters.octo.design.AccentButton
import app.winters.octo.design.GlassInput
import app.winters.octo.design.GlassPopup
import app.winters.octo.design.GlazeButton
import app.winters.octo.design.OctoColors
import app.winters.octo.design.OctoIcons
import app.winters.octo.design.OctoType
import app.winters.octo.discovery.Discovery
import app.winters.octo.playback.PlaybackConnection
import app.winters.octo.liveradio.lineupOf
import app.winters.octo.liveradio.radioId
import app.winters.octo.server.ServerControls
import app.winters.octo.subsonic.RadioStationDetails
import app.winters.octo.subsonic.SubsonicException
import app.winters.octo.ui.common.BackButton
import app.winters.octo.ui.common.DetailTopGap
import app.winters.octo.ui.common.LoadState
import app.winters.octo.ui.common.LocalHaze
import app.winters.octo.ui.common.rememberLast
import app.winters.octo.ui.common.ScreenTitle
import app.winters.octo.ui.common.screenPadding
import app.winters.octo.ui.liveradio.FindNearRow
import app.winters.octo.ui.nav.LiveRadioNearRoute
import dagger.hilt.android.lifecycle.HiltViewModel
import kotlinx.coroutines.CancellationException
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.launch
import kotlinx.coroutines.withContext
import okhttp3.HttpUrl.Companion.toHttpUrlOrNull
import javax.inject.Inject

// Whether text is a web address a station could stream from.
fun isStreamAddress(text: String): Boolean {
    val url = text.trim().toHttpUrlOrNull() ?: return false
    return url.host.isNotEmpty()
}

// A station being added (no id) or changed.
data class StationDraft(val id: String?, val name: String, val streamUrl: String, val homepage: String) {
    val ready: Boolean get() = name.isNotBlank() && isStreamAddress(streamUrl) && (homepage.isBlank() || isStreamAddress(homepage))
}

@HiltViewModel
class RadioStationsViewModel @Inject constructor(
    private val controls: ServerControls,
    private val discovery: Discovery,
    private val playback: PlaybackConnection,
) : ViewModel() {
    var stations by mutableStateOf<LoadState<List<RadioStationDetails>>>(LoadState.Loading)
        private set

    // Only an admin may add, change or delete stations.
    val admin: StateFlow<Boolean> = controls.admin

    // Stations the server will not let anyone change.
    val readOnly: StateFlow<Set<String>> = controls.readOnly

    // The station being added or changed, if the sheet is open.
    var draft by mutableStateOf<StationDraft?>(null)
        private set
    var saving by mutableStateOf(false)
        private set
    var problem by mutableStateOf<String?>(null)
        private set

    // A station whose songs are on the way.
    var starting by mutableStateOf<String?>(null)
        private set

    init {
        reload()
    }

    fun reload() {
        viewModelScope.launch {
            stations = LoadState.Loading
            stations = try {
                LoadState.Ready(controls.stations())
            } catch (e: CancellationException) {
                throw e
            } catch (e: Exception) {
                LoadState.Failed(e.userMessage())
            }
        }
    }

    fun add() {
        problem = null
        draft = StationDraft(null, "", "", "")
    }

    fun edit(station: RadioStationDetails) {
        problem = null
        draft = StationDraft(station.id, station.name, station.streamUrl, station.homePageUrl.orEmpty())
    }

    fun change(next: StationDraft) {
        draft = next
    }

    fun close() {
        if (!saving) draft = null
    }

    fun save() = act { d ->
        if (d.id == null) controls.addStation(d.streamUrl, d.name, d.homepage) else controls.updateStation(d.id, d.streamUrl, d.name, d.homepage)
    }

    fun delete() = act { d -> d.id?.let { controls.deleteStation(it) } }

    // Runs a change, then closes the sheet and reads the list again. A
    // refusal stays in the sheet, in words.
    private fun act(call: suspend (StationDraft) -> Unit) {
        val d = draft ?: return
        if (saving) return
        saving = true
        problem = null
        viewModelScope.launch {
            try {
                call(d)
                draft = null
                reload()
            } catch (e: CancellationException) {
                throw e
            } catch (e: Exception) {
                problem = if (d.id != null && d.id in controls.readOnly.value) {
                    "The server keeps this station as it is."
                } else {
                    e.userMessage()
                }
            } finally {
                saving = false
            }
        }
    }

    // A station the server made plays the songs it has lined up, like the
    // Home shelf; any other plays its stream.
    // A stream plays with the list's other streams in its order, for Back
    // and Next.
    fun play(station: RadioStationDetails) {
        if (starting != null) return
        if (station.id !in readOnly.value) {
            if (station.streamUrl.isBlank()) return
            val streams = (stations as? LoadState.Ready)?.data.orEmpty().filter { it.id !in readOnly.value && it.streamUrl.isNotBlank() }
            val (ids, start) = lineupOf(streams, streams.indexOfFirst { it.id == station.id }.coerceAtLeast(0), { it.streamUrl }, { it.radioId() })
            playback.playLineup(ids.ifEmpty { listOf(station.radioId()) }, start, source = "Radio stations")
            return
        }
        starting = station.id
        viewModelScope.launch {
            try {
                val songs = withContext(Dispatchers.IO) { discovery.stationSongs(station.id) }
                if (songs.isNotEmpty()) {
                    playback.playTracks(songs.map { it.id })
                } else if (station.streamUrl.isNotBlank()) {
                    playback.playTracks(listOf(station.radioId()))
                }
            } catch (e: CancellationException) {
                throw e
            } catch (e: SubsonicException.NotFound) {
                // Octo made it anew since the list was read: read it again.
                reload()
            } catch (e: Exception) {
                Log.w("Octo", "station failed to start: ${e.javaClass.simpleName}")
            } finally {
                starting = null
            }
        }
    }
}

// The server's internet radio stations. Tapping one plays it. An admin can
// add stations and change or delete them, except ones the server keeps.
// Above them is the way to live stations near the listener.
@Composable
fun RadioStationsScreen(onBack: () -> Unit, onOpen: (NavKey) -> Unit, vm: RadioStationsViewModel = hiltViewModel()) {
    val admin by vm.admin.collectAsStateWithLifecycle()
    val readOnly by vm.readOnly.collectAsStateWithLifecycle()
    Box(Modifier.fillMaxSize()) {
        LazyColumn(Modifier.fillMaxSize(), contentPadding = screenPadding(extraTop = DetailTopGap)) {
            item(key = "title") { ScreenTitle("Radio stations") }
            item(key = "near") { FindNearRow(onClick = { onOpen(LiveRadioNearRoute) }, modifier = Modifier.padding(bottom = 8.dp)) }
            if (admin) {
                item(key = "add") {
                    GlazeButton("Add station", onClick = vm::add, modifier = Modifier.padding(start = 20.dp, bottom = 8.dp))
                }
            }
            when (val state = vm.stations) {
                LoadState.Loading -> item(key = "loading") { Spinner(Modifier.padding(top = 24.dp)) }
                is LoadState.Failed -> item(key = "failed") {
                    Column(Modifier.padding(horizontal = 20.dp), verticalArrangement = Arrangement.spacedBy(12.dp)) {
                        Text(state.message, style = OctoType.bodySmall, color = OctoColors.TextMuted)
                        GlazeButton("Try again", onClick = vm::reload)
                    }
                }
                is LoadState.Ready -> {
                    if (state.data.isEmpty()) item(key = "none") { Note("No stations on this server yet.") }
                    items(state.data, key = { it.id }) { station ->
                        val kept = station.id in readOnly
                        StationRow(
                            station,
                            kept = kept,
                            starting = vm.starting == station.id,
                            onPlay = { vm.play(station) },
                            onEdit = if (admin && !kept) ({ vm.edit(station) }) else null,
                        )
                    }
                }
            }
        }
        BackButton(onBack)
        // A glass panel in the middle, since it holds a form; it rises above
        // the keyboard while one is typed.
        GlassPopup(
            visible = vm.draft != null,
            anchor = null,
            onDismiss = vm::close,
            backdrop = LocalHaze.current,
            title = "Station",
            maxWidth = 400.dp,
        ) {
            val draft = rememberLast(vm.draft) ?: return@GlassPopup
            key(draft.id) { StationForm(draft, vm) }
        }
    }
}

@Composable
private fun StationRow(station: RadioStationDetails, kept: Boolean, starting: Boolean, onPlay: () -> Unit, onEdit: (() -> Unit)?) {
    val fade by animateFloatAsState(if (starting) 0.5f else 1f, label = "station")
    Row(
        Modifier
            .fillMaxWidth()
            .alpha(fade)
            .clickable(role = Role.Button, onClick = onPlay)
            .heightIn(min = 60.dp)
            .padding(start = 20.dp, end = 8.dp, top = 6.dp, bottom = 6.dp),
        verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.spacedBy(14.dp),
    ) {
        Icon(painterResource(OctoIcons.Radio), contentDescription = null, tint = OctoColors.TextSecondary, modifier = Modifier.size(22.dp))
        Column(Modifier.weight(1f)) {
            Text(station.name, style = OctoType.bodySmall, color = OctoColors.TextPrimary, maxLines = 1, overflow = TextOverflow.Ellipsis)
            val detail = if (kept) "Made by the server" else station.streamUrl.toHttpUrlOrNull()?.host ?: station.streamUrl
            Text(detail, style = OctoType.caption, color = OctoColors.TextMuted, maxLines = 1, overflow = TextOverflow.Ellipsis)
        }
        if (onEdit != null) {
            IconButton(onClick = onEdit) {
                Icon(painterResource(OctoIcons.Rename), contentDescription = "Edit ${station.name}", tint = OctoColors.TextMuted, modifier = Modifier.size(20.dp))
            }
        }
    }
}

// Name, stream and home page, with Save, and Delete for a station that exists.
@Composable
private fun StationForm(draft: StationDraft, vm: RadioStationsViewModel) {
    var confirming by remember { mutableStateOf(false) }
    Column(
        Modifier
            .fillMaxWidth()
            .verticalScroll(rememberScrollState())
            .padding(start = 20.dp, end = 20.dp, top = 18.dp, bottom = 20.dp),
        verticalArrangement = Arrangement.spacedBy(12.dp),
    ) {
        Text(if (draft.id == null) "Add station" else "Edit station", style = OctoType.body, color = OctoColors.TextPrimary)
        GlassInput(
            value = draft.name,
            onValueChange = { vm.change(draft.copy(name = it)) },
            placeholder = "Name",
            keyboardOptions = KeyboardOptions(capitalization = KeyboardCapitalization.Words, imeAction = ImeAction.Next),
        )
        GlassInput(
            value = draft.streamUrl,
            onValueChange = { vm.change(draft.copy(streamUrl = it)) },
            placeholder = "Stream address",
            keyboardOptions = KeyboardOptions(keyboardType = KeyboardType.Uri, imeAction = ImeAction.Next),
        )
        GlassInput(
            value = draft.homepage,
            onValueChange = { vm.change(draft.copy(homepage = it)) },
            placeholder = "Home page (optional)",
            keyboardOptions = KeyboardOptions(keyboardType = KeyboardType.Uri, imeAction = ImeAction.Done),
        )
        vm.problem?.let { Text(it, style = OctoType.caption, color = OctoColors.Error) }
        if (confirming) {
            Text("Delete \"${draft.name}\" from the server?", style = OctoType.bodySmall, color = OctoColors.TextSecondary)
            Row(horizontalArrangement = Arrangement.spacedBy(12.dp)) {
                AccentButton("Delete", onClick = vm::delete, loading = vm.saving)
                GlazeButton("Cancel", onClick = { confirming = false })
            }
        } else {
            Row(horizontalArrangement = Arrangement.spacedBy(12.dp)) {
                AccentButton("Save", onClick = vm::save, enabled = draft.ready, loading = vm.saving)
                if (draft.id != null) GlazeButton("Delete", onClick = { confirming = true }, enabled = !vm.saving)
            }
        }
    }
}
