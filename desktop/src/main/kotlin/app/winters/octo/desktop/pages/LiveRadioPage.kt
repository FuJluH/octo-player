package app.winters.octo.desktop.pages

import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.ColumnScope
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.height
import androidx.compose.foundation.layout.heightIn
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.layout.widthIn
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.LazyListScope
import androidx.compose.foundation.lazy.items
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.input.key.Key
import androidx.compose.ui.input.key.KeyEventType
import androidx.compose.ui.input.key.isShiftPressed
import androidx.compose.ui.input.key.key
import androidx.compose.ui.input.key.onPreviewKeyEvent
import androidx.compose.ui.input.key.type
import androidx.compose.ui.layout.onGloballyPositioned
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.unit.IntRect
import app.winters.octo.design.ChipRow
import app.winters.octo.design.ControlHeight
import app.winters.octo.design.Corner
import app.winters.octo.design.DesktopType
import app.winters.octo.design.FrameSize
import app.winters.octo.design.GlassField
import app.winters.octo.design.GlazeCapsule
import app.winters.octo.design.GlazeSegments
import app.winters.octo.design.Glyph
import app.winters.octo.design.IconAction
import app.winters.octo.design.IconSize
import app.winters.octo.design.MenuRow
import app.winters.octo.design.MenuSeparator
import app.winters.octo.design.OctoColors
import app.winters.octo.design.OctoIcons
import app.winters.octo.design.OctoType
import app.winters.octo.design.RowHeight
import app.winters.octo.design.Space
import app.winters.octo.design.Txt
import app.winters.octo.design.hoverLift
import app.winters.octo.design.scrollbar
import app.winters.octo.desktop.AppState
import app.winters.octo.desktop.liveradio.CATALOG_DOWN
import app.winters.octo.desktop.liveradio.LIVE_RADIO_NEAR
import app.winters.octo.desktop.liveradio.LiveFind
import app.winters.octo.desktop.liveradio.hiddenStationsLine
import app.winters.octo.desktop.liveradio.nothingFound
import app.winters.octo.desktop.liveradio.radiusChoices
import app.winters.octo.desktop.liveradio.radiusLabel
import app.winters.octo.desktop.liveradio.soundText
import app.winters.octo.desktop.liveradio.tagsText
import app.winters.octo.desktop.liveradio.whereText
import app.winters.octo.desktop.nav.Page
import app.winters.octo.desktop.nav.Visit
import app.winters.octo.desktop.playLive
import app.winters.octo.desktop.ui.DOUBLE_CLICK_MS
import app.winters.octo.desktop.ui.FailedLine
import app.winters.octo.desktop.ui.LoadingLine
import app.winters.octo.desktop.ui.LocalBottomRoom
import app.winters.octo.desktop.ui.LocalPointer
import app.winters.octo.desktop.ui.PageTitle
import app.winters.octo.desktop.ui.SectionTitle
import app.winters.octo.desktop.ui.StationLogo
import app.winters.octo.desktop.ui.LiveStationMenu
import app.winters.octo.desktop.ui.liveStationMenu
import app.winters.octo.desktop.ui.windowRect
import app.winters.octo.desktop.ui.onRightClick
import app.winters.octo.desktop.ui.pagePadding
import app.winters.octo.desktop.ui.rememberListState
import app.winters.octo.liveradio.LiveSort
import app.winters.octo.liveradio.LiveStation
import app.winters.octo.liveradio.located
import java.util.Locale

// Said under a city found with no server to look it up: Radio Browser is
// asked for its stations by the words typed, as a state.
const val AS_TYPED = "Searched by Radio Browser as typed, without a map position, so stations are matched by the state's name."

// The words the Where field shows while empty.
const val WHERE_HINT = "ZIP or postal code, or a city and state"

// The order choices, in words.
fun sortLabel(sort: LiveSort): String = when (sort) {
    LiveSort.Distance -> "Nearest"
    LiveSort.Popular -> "Most played"
}

// A country's name in the listener's own language, from its ISO code.
fun countryName(code: String, locale: Locale = Locale.getDefault()): String =
    Locale.Builder().setRegion(code).build().getDisplayCountry(locale).ifBlank { code }

// Every country there is, by name.
private val Countries: List<String> by lazy { Locale.getISOCountries().sortedBy { countryName(it).lowercase() } }

// Live radio near you: where (a postal code, or a city with its state, and
// the country), the stations the radio catalog has around it, nearest or
// most played first, in a circle of the listener's choosing, and the
// stations kept on this computer above them. A click plays a station; a
// right click keeps or removes it, and lets an admin add it to the server.
@Composable
fun LiveRadioPage(app: AppState, visit: Visit) {
    val model = app.liveRadio
    val settings by app.settings.state.collectAsState()
    val prefs = settings.liveRadio
    LaunchedEffect(model, app.connection) {
        model.open()
        model.readServerStations()
    }
    val kept = remember(prefs.kept) { model.kept(prefs).stations }
    val keptIds = remember(kept) { kept.mapTo(HashSet()) { it.uuid } }
    val list = rememberListState(app.navigator, visit)
    val find = model.find
    LazyColumn(Modifier.scrollbar(list, LocalBottomRoom.current), state = list, contentPadding = pagePadding(LocalBottomRoom.current)) {
        item(key = "title") {
            PageTitle(LIVE_RADIO_NEAR, detail = "Stations on the air around you, from the Radio Browser catalog.")
        }
        item(key = "where") { WhereControls(app, prefs.where, model.country(prefs)) }
        item(key = "order") { OrderControls(app, prefs.sort, prefs.radius, located = (prefs.place?.located ?: false)) }
        if (kept.isNotEmpty()) {
            item(key = "kept-title") { SectionTitle("Kept here") }
            items(kept, key = { "kept:${it.uuid}" }) { station -> StationRow(app, station, kept = true, miles = model.miles, near = false, lineup = kept, source = "Kept here") }
        }
        stations(app, find, keptIds, prefs.radius, model.miles)
    }
}

// The stations found, or why there are none.
private fun LazyListScope.stations(app: AppState, find: LiveFind, keptIds: Set<String>, radius: Int, miles: Boolean) {
    when (find) {
        LiveFind.NoPlace -> item(key = "no-place") {
            NothingHere("Where are you listening?", "Type a ZIP or postal code, or a city with its state after a comma, then press Find.")
        }
        LiveFind.Finding -> item(key = "finding") { LoadingLine("Finding stations") }
        is LiveFind.Problem -> item(key = "problem") { Txt(find.words, OctoType.bodySmall, OctoColors.TextSecondary, Modifier.padding(vertical = Space.Page), maxLines = 3) }
        is LiveFind.CatalogDown -> item(key = "down") { FailedLine(CATALOG_DOWN, app.liveRadio::retry) }
        is LiveFind.Found -> {
            item(key = "near-title") { SectionTitle(if (find.place.located) "Near ${find.place.label}" else "In ${find.place.label}") }
            if (!find.place.located) {
                item(key = "as-typed") { Txt(AS_TYPED, DesktopType.meta, OctoColors.TextMuted, Modifier.padding(bottom = Space.S), maxLines = 2) }
            }
            if (find.stations.isEmpty()) {
                val value = radiusChoices(miles).let { it[radius.coerceIn(it.indices)] }
                item(key = "none") { NothingHere(nothingFound(find.place, value, miles)) }
            }
            items(find.stations, key = { "near:${it.uuid}" }) { station -> StationRow(app, station, kept = station.uuid in keptIds, miles = miles, near = true, lineup = find.stations, source = LIVE_RADIO_NEAR) }
            hiddenStationsLine(find.hidden)?.let { line ->
                item(key = "hidden") { Txt(line, DesktopType.meta, OctoColors.TextMuted, Modifier.padding(vertical = Space.S), maxLines = 2) }
            }
        }
    }
}

// Where: the postal code or city, the country it is in, and Find.
@Composable
private fun WhereControls(app: AppState, saved: String, savedCountry: String) {
    var where by remember(saved) { mutableStateOf(saved) }
    var country by remember(savedCountry) { mutableStateOf(savedCountry) }
    val pointer = LocalPointer.current
    val find = { app.liveRadio.lookUp(where, country) }
    Row(
        Modifier.fillMaxWidth().padding(bottom = Space.L),
        verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.spacedBy(Space.M),
    ) {
        GlassField(where, { where = it }, Modifier.widthIn(max = FrameSize.SearchWidth).weight(1f, fill = false), placeholder = WHERE_HINT, icon = OctoIcons.Globe, onSubmit = find)
        GlazeCapsule(null, countryName(country), {
            app.popups.showAt(pointer.point) { close -> CountryMenu(country, { country = it }, close) }
        })
        GlazeCapsule(OctoIcons.Search, "Find", find, lit = true, enabled = where.isNotBlank())
    }
}

// The order, and the circle's size for a place that has coordinates.
@Composable
private fun OrderControls(app: AppState, sort: LiveSort, radius: Int, located: Boolean) {
    val miles = app.liveRadio.miles
    val choices = radiusChoices(miles)
    Row(
        Modifier.fillMaxWidth().padding(bottom = Space.M),
        verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.spacedBy(Space.L),
    ) {
        GlazeSegments(LiveSort.entries, sort, ::sortLabel, app.liveRadio::setSort)
        if (located) {
            ChipRow(choices.indices.toList(), radius.coerceIn(choices.indices), { radiusLabel(choices[it], miles) }, app.liveRadio::setRadius)
        }
    }
}

// The countries to look in, the chosen one first, then a field that narrows
// the list as a name is typed.
@Composable
private fun ColumnScope.CountryMenu(chosen: String, pick: (String) -> Unit, close: () -> Unit) {
    var typed by remember { mutableStateOf("") }
    GlassField(typed, { typed = it }, Modifier.fillMaxWidth().padding(horizontal = Space.M, vertical = Space.S), placeholder = "Country", icon = OctoIcons.Search)
    MenuRow(countryName(chosen), close, checked = true)
    MenuSeparator()
    val words = typed.trim().lowercase()
    Countries.filter { it != chosen && (words.isEmpty() || countryName(it).lowercase().contains(words) || it.lowercase() == words) }.forEach { code ->
        MenuRow(countryName(code), {
            pick(code)
            close()
        })
    }
}

// A station: its logo, its name, where it is and its tags, how it sounds,
// and its menu button. A click (or Enter) plays it with the rest of its
// `lineup` around it for Back and Next (the second click of a double click
// does not start it over); a right click, the menu key or Shift+F10 opens
// its menu where the button is.
@Composable
private fun StationRow(app: AppState, station: LiveStation, kept: Boolean, miles: Boolean, near: Boolean, lineup: List<LiveStation>, source: String) {
    val clicks = remember { longArrayOf(0L) }
    val play = { app.playLive(station, lineup, source) }
    val menu = liveStationMenu(app, station, kept, play)
    var anchor by remember { mutableStateOf(IntRect.Zero) }
    val menuHere = { app.popups.showUnder(anchor) { close -> LiveStationMenu(app, station, kept, close, play) } }
    Row(
        Modifier
            .fillMaxWidth()
            .heightIn(min = RowHeight.Roomy)
            .hoverLift(Corner.RowShape)
            .onRightClick(menu)
            .onPreviewKeyEvent { event ->
                val asks = event.type == KeyEventType.KeyDown && (event.key == Key.Menu || (event.key == Key.F10 && event.isShiftPressed))
                if (asks) menuHere()
                asks
            }
            .clickable(role = Role.Button) {
                val now = System.currentTimeMillis()
                if (now - clicks[0] >= DOUBLE_CLICK_MS) play()
                clicks[0] = now
            }
            .padding(horizontal = Space.M, vertical = Space.S),
        verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.spacedBy(Space.L),
    ) {
        StationLogo(station.favicon, station.name, Modifier.size(ControlHeight.L), Corner.ArtSShape)
        Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(Space.Xxs)) {
            Txt(station.name, DesktopType.tableTitle)
            val line = listOfNotNull(if (near) whereText(station, miles) else station.state.ifBlank { station.country }.ifBlank { null }, tagsText(station)).joinToString(" · ")
            if (line.isNotEmpty()) Txt(line, DesktopType.meta, OctoColors.TextMuted)
        }
        if (kept && near) Glyph(OctoIcons.Pinned, size = IconSize.Table, tint = OctoColors.TextMuted)
        soundText(station)?.let { Txt(it, DesktopType.meta, OctoColors.TextMuted) }
        IconAction(
            OctoIcons.More,
            "More for ${station.name}",
            menuHere,
            Modifier.onGloballyPositioned { anchor = it.windowRect() },
            size = ControlHeight.S,
            iconSize = IconSize.Table,
            tint = OctoColors.TextSecondary,
        )
    }
}

// The way to the Live radio page from Search: one row.
@Composable
fun LiveRadioSearchRow(app: AppState) {
    Row(
        Modifier
            .fillMaxWidth()
            .padding(top = Space.L)
            .widthIn(max = FrameSize.CardMax)
            .heightIn(min = RowHeight.Roomy)
            .hoverLift(Corner.RowShape)
            .clickable(role = Role.Button) { app.navigator.go(Page.LiveRadio) }
            .padding(horizontal = Space.M, vertical = Space.S),
        verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.spacedBy(Space.L),
    ) {
        Glyph(OctoIcons.Radio, size = IconSize.Transport, tint = OctoColors.TextSecondary)
        Column(Modifier.weight(1f), verticalArrangement = Arrangement.spacedBy(Space.Xxs)) {
            Txt(LIVE_RADIO_NEAR, DesktopType.tableTitle)
            Txt("Stations on the air around you, to play or keep.", DesktopType.meta, OctoColors.TextMuted)
        }
        Glyph(OctoIcons.Chevron, size = IconSize.Table, tint = OctoColors.TextMuted)
    }
}
