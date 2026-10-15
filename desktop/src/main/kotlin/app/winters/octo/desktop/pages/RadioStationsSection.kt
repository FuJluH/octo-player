package app.winters.octo.desktop.pages

import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.ColumnScope
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.key
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.rememberCoroutineScope
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.focus.FocusRequester
import app.winters.octo.design.ControlHeight
import app.winters.octo.design.Corner
import app.winters.octo.design.DesktopType
import app.winters.octo.design.GlassField
import app.winters.octo.design.GlazeCapsule
import app.winters.octo.design.IconSize
import app.winters.octo.design.MenuTitle
import app.winters.octo.design.OctoColors
import app.winters.octo.design.PopupPadding
import app.winters.octo.design.SettingsSize
import app.winters.octo.design.Space
import app.winters.octo.design.Spinner
import app.winters.octo.design.TextAction
import app.winters.octo.design.Txt
import app.winters.octo.desktop.AppState
import app.winters.octo.desktop.liveradio.FIND_STATIONS_NEAR
import app.winters.octo.desktop.liveradio.LIVE_RADIO
import app.winters.octo.desktop.settings.AppSettings
import app.winters.octo.radio.LIVE_RADIO_ABOUT
import app.winters.octo.radio.RadioAdventure
import app.winters.octo.radio.RadioDiscovery
import app.winters.octo.radio.RadioVariety
import app.winters.octo.radio.SONG_RADIO
import app.winters.octo.radio.SONG_RADIO_ABOUT
import app.winters.octo.radio.discoveryRowLook
import app.winters.octo.desktop.liveradio.isOctoStation
import app.winters.octo.desktop.nav.Page
import app.winters.octo.desktop.playServerStation
import app.winters.octo.desktop.server.userMessage
import app.winters.octo.desktop.ui.StationLogo
import app.winters.octo.subsonic.RadioStationDetails
import app.winters.octo.subsonic.SubsonicException
import kotlinx.coroutines.launch
import okhttp3.HttpUrl.Companion.toHttpUrlOrNull

// Whether text is a web address a station could stream from.
fun isStreamAddress(text: String): Boolean = text.trim().toHttpUrlOrNull()?.host?.isNotEmpty() == true

// A station being added (no id) or changed.
data class StationDraft(val id: String?, val name: String, val streamUrl: String, val homepage: String) {
    val ready: Boolean get() = name.isNotBlank() && isStreamAddress(streamUrl) && (homepage.isBlank() || isStreamAddress(homepage))
}

// Settings > Radio, in two parts that say which is which: song radio, which
// Octo mixes from your music, and live radio, the stations on the air.
@Composable
internal fun RadioRows(app: AppState, settings: AppSettings) {
    SongRadioRows(app, settings)
    Group(LIVE_RADIO, footer = LIVE_RADIO_ABOUT) {
        ActionRow(FIND_STATIONS_NEAR, "Stations on the air around a place, to play or keep.", "Open", { app.navigator.go(Page.LiveRadio) })
    }
    RadioStationRows(app)
}

// How song radio picks its songs, for a radio started from a song, album or
// artist and for Autoplay. With Library songs only on, Discovery has no say
// and says so.
@Composable
private fun SongRadioRows(app: AppState, settings: AppSettings) {
    val playback = settings.playback
    Group(SONG_RADIO, footer = SONG_RADIO_ABOUT) {
        val discovery = discoveryRowLook(playback.radioDiscovery, settings.libraryOnly, where = "Playback")
        if (discovery.choosable) {
            ChoiceRow("Discovery", discovery.helper, RadioDiscovery.entries, playback.radioDiscovery, { it.label }) { d ->
                app.settings.update { it.copy(playback = it.playback.copy(radioDiscovery = d)) }
            }
        } else {
            SettingRow("Discovery", discovery.helper, dim = true) {
                Txt(discovery.value, DesktopType.meta, OctoColors.TextMuted)
            }
        }
        ChoiceRow("Adventure", playback.radioAdventure.detail, RadioAdventure.entries, playback.radioAdventure, { it.label }) { a ->
            app.settings.update { it.copy(playback = it.playback.copy(radioAdventure = a)) }
        }
        ChoiceRow("Artist variety", playback.radioVariety.detail, RadioVariety.entries, playback.radioVariety, { it.label }) { v ->
            app.settings.update { it.copy(playback = it.playback.copy(radioVariety = v)) }
        }
        SwitchRow("Favorites more often", "Songs you hearted or rated 4 or 5 stars come around more often.", playback.radioFavorites) { on ->
            app.settings.update { it.copy(playback = it.playback.copy(radioFavorites = on)) }
        }
    }
}

// The internet radio stations on the server in use. A click on Play plays
// one; an admin can add stations and change or delete them, except the ones
// Octo makes itself. Without a server, the group says so.
@Composable
private fun RadioStationRows(app: AppState) {
    val model = app.liveRadio
    val connection = app.connection
    if (connection == null) {
        Group(STATIONS_ON_SERVER) {
            SettingRow("No server connected", "Connect a server to see the stations it keeps.", dim = true)
        }
        return
    }
    // Read again each time the section opens, and after every change.
    var round by remember { mutableIntStateOf(0) }
    var failed by remember { mutableStateOf(false) }
    LaunchedEffect(connection, round) {
        model.checkAdmin()
        failed = !model.readServerStations()
    }
    val admin = model.admin == true
    val stations = model.serverStations
    Group(STATIONS_ON_SERVER) {
        when {
            stations == null && failed -> SettingRow("Couldn't read the stations", "Your server didn't answer just now.") { RowAction("Try again", { round++ }) }
            stations == null -> SettingRow("Reading the stations", null) { Spinner(size = IconSize.Table) }
            stations.isEmpty() -> SettingRow("No stations yet", if (admin) "Add one by its stream address, or find stations near you." else "An admin of your server can add some.")
            else -> {
                val streams = stations.filter { !isOctoStation(it.basic(), connection.isOcto) && it.streamUrl.isNotBlank() }
                stations.forEach { station -> StationRow(app, station, own = isOctoStation(station.basic(), connection.isOcto), admin = admin, play = { app.playServerStation(station, streams) }) { round++ } }
            }
        }
        if (admin) {
            ActionRow("Add a station", "By its stream address, for everyone on your server.", "Add", { stationSheet(app, StationDraft(null, "", "", "")) { round++ } })
        } else if (model.admin == false) {
            SettingRow("Adding and changing stations", "Only an admin of your server can do this.", dim = true)
        }
    }
}

// The part of Settings > Radio that lists the server's stations.
const val STATIONS_ON_SERVER = "Stations on your server"

private fun RadioStationDetails.basic() = app.winters.octo.subsonic.RadioStation(id, name, streamUrl, coverArt)

// One station: its logo, name and where it streams from, with Play, and
// Edit for an admin. One Octo makes itself is the server's to keep.
@Composable
private fun StationRow(app: AppState, station: RadioStationDetails, own: Boolean, admin: Boolean, play: () -> Unit, changed: () -> Unit) {
    val detail = if (own) "Made by the server" else station.streamUrl.toHttpUrlOrNull()?.host ?: station.streamUrl
    Row(
        Modifier.fillMaxWidth().padding(start = RowInset, top = Space.M, bottom = Space.M),
        verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.spacedBy(Space.L),
    ) {
        StationLogo("", station.name, Modifier.size(ControlHeight.L), Corner.ArtSShape, coverArt = station.coverArt)
        Column(Modifier.weight(1f)) {
            Txt(station.name.ifBlank { station.streamUrl }, DesktopType.body)
            Txt(detail, DesktopType.meta, OctoColors.TextMuted, Modifier.padding(top = Space.Xxs))
        }
        if (!own && station.streamUrl.isNotBlank()) RowAction("Play", play)
        if (own) RowAction("Open", { app.navigator.go(Page.Playlist(station.id)) })
        if (admin && !own) RowAction("Edit", { stationSheet(app, StationDraft(station.id, station.name, station.streamUrl, station.homePageUrl.orEmpty()), changed) })
        Spacer(Modifier.size(Space.M))
    }
}

// Adds or changes a station in a sheet in the middle of the window.
internal fun stationSheet(app: AppState, start: StationDraft, changed: () -> Unit) {
    val opening = Any()
    app.popups.showCentred(width = SettingsSize.Sheet, scrim = true) { close -> key(opening) { StationSheet(app, start, close, changed) } }
}

// Name, stream and home page, with Save, and Delete (asked first) for a
// station that exists. A refusal stays in the sheet, in words.
@Composable
private fun ColumnScope.StationSheet(app: AppState, start: StationDraft, close: () -> Unit, changed: () -> Unit) {
    val scope = rememberCoroutineScope()
    val first = remember { FocusRequester() }
    var draft by remember { mutableStateOf(start) }
    var busy by remember { mutableStateOf(false) }
    var problem by remember { mutableStateOf<String?>(null) }
    var deleting by remember { mutableStateOf(false) }
    LaunchedEffect(Unit) { runCatching { first.requestFocus() } }

    fun act(call: suspend () -> Unit) {
        if (busy) return
        busy = true
        problem = null
        scope.launch {
            try {
                call()
                close()
                changed()
                app.home?.liveChanged()
            } catch (e: SubsonicException) {
                problem = e.userMessage()
            } finally {
                busy = false
            }
        }
    }

    val client = app.connection?.client
    fun save() {
        if (!draft.ready || client == null) return
        val d = draft
        act {
            val homepage = d.homepage.trim().ifEmpty { null }
            if (d.id == null) client.createRadioStation(d.streamUrl.trim(), d.name.trim(), homepage) else client.updateRadioStation(d.id, d.streamUrl.trim(), d.name.trim(), homepage)
        }
    }

    MenuTitle(if (draft.id == null) "Add a station" else "Edit ${start.name}")
    PopupPadding {
        if (deleting) {
            Txt("Delete \"${start.name}\" from your server? Nobody on it can play it after that.", DesktopType.body, OctoColors.TextPrimary, maxLines = 3)
            problem?.let { Txt(it, DesktopType.meta, OctoColors.Error, maxLines = 4) }
            Row(Modifier.fillMaxWidth().padding(vertical = Space.Xs), horizontalArrangement = Arrangement.spacedBy(Space.M), verticalAlignment = Alignment.CenterVertically) {
                Spacer(Modifier.weight(1f))
                if (busy) Spinner(size = IconSize.Table)
                GlazeCapsule(null, "Cancel", { deleting = false }, height = ControlHeight.L)
                GlazeCapsule(null, "Delete", { draft.id?.let { id -> client?.let { c -> act { c.deleteRadioStation(id) } } } }, lit = true, height = ControlHeight.L)
            }
            return@PopupPadding
        }
        SheetField("Name") {
            GlassField(draft.name, { draft = draft.copy(name = it) }, Modifier.fillMaxWidth(), placeholder = "Like City Jazz FM", focusRequester = first, onSubmit = ::save)
        }
        SheetField("Stream address") {
            GlassField(draft.streamUrl, { draft = draft.copy(streamUrl = it) }, Modifier.fillMaxWidth(), placeholder = "https://example.com/live.mp3", onSubmit = ::save)
        }
        SheetField("Home page (optional)") {
            GlassField(draft.homepage, { draft = draft.copy(homepage = it) }, Modifier.fillMaxWidth(), placeholder = "https://example.com", onSubmit = ::save)
        }
        problem?.let { Txt(it, DesktopType.meta, OctoColors.Error, maxLines = 4) }
        Row(Modifier.fillMaxWidth().padding(vertical = Space.Xs), horizontalArrangement = Arrangement.spacedBy(Space.M), verticalAlignment = Alignment.CenterVertically) {
            if (draft.id != null) TextAction("Delete", { deleting = true }, enabled = !busy)
            Spacer(Modifier.weight(1f))
            if (busy) Spinner(size = IconSize.Table)
            GlazeCapsule(null, "Cancel", close, height = ControlHeight.L)
            GlazeCapsule(null, if (draft.id == null) "Add" else "Save", ::save, lit = true, enabled = draft.ready && !busy, height = ControlHeight.L)
        }
    }
}

// A field in the sheet, with its name above it.
@Composable
private fun SheetField(name: String, content: @Composable ColumnScope.() -> Unit) {
    Column(Modifier.fillMaxWidth(), verticalArrangement = Arrangement.spacedBy(Space.Xs)) {
        Txt(name, DesktopType.meta, OctoColors.TextMuted)
        content()
    }
}
