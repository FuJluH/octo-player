package app.winters.octo.ui.liveradio

import android.Manifest
import android.app.Activity
import android.content.Intent
import android.provider.Settings
import android.content.pm.PackageManager
import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.activity.result.contract.ActivityResultContracts
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.PaddingValues
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.foundation.lazy.LazyColumn
import androidx.compose.foundation.lazy.LazyRow
import androidx.compose.foundation.lazy.items
import androidx.compose.foundation.lazy.itemsIndexed
import androidx.compose.foundation.text.KeyboardActions
import androidx.compose.foundation.text.KeyboardOptions
import androidx.compose.material3.CircularProgressIndicator
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalContext
import androidx.compose.ui.platform.LocalSoftwareKeyboardController
import androidx.compose.ui.text.input.ImeAction
import androidx.compose.ui.text.input.KeyboardCapitalization
import androidx.compose.ui.unit.dp
import androidx.core.content.ContextCompat
import androidx.core.net.toUri
import androidx.hilt.lifecycle.viewmodel.compose.hiltViewModel
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import app.winters.octo.design.AccentButton
import app.winters.octo.design.ButtonSize
import app.winters.octo.design.GlassInput
import app.winters.octo.design.GlazeButton
import app.winters.octo.design.OctoColors
import app.winters.octo.design.OctoType
import app.winters.octo.liveradio.LivePlace
import app.winters.octo.liveradio.LiveSort
import app.winters.octo.liveradio.LiveStation
import app.winters.octo.liveradio.countryChoices
import app.winters.octo.liveradio.hiddenLine
import app.winters.octo.liveradio.noStationsLine
import app.winters.octo.liveradio.placeSourceLine
import app.winters.octo.liveradio.radiusChoices
import app.winters.octo.liveradio.radiusLabel
import app.winters.octo.ui.common.BackButton
import app.winters.octo.ui.common.Choice
import app.winters.octo.ui.common.ChoiceRequest
import app.winters.octo.ui.common.DetailTopGap
import app.winters.octo.ui.common.LocalChoiceSheet
import app.winters.octo.ui.common.ScreenTitle
import app.winters.octo.ui.common.SectionTitle
import app.winters.octo.ui.common.Segmented
import app.winters.octo.ui.common.choiceAnchor
import app.winters.octo.ui.common.screenPadding

private val SortWords = listOf("Nearest", "Most played")

// Live radio near you: a place (the phone's rough position, or a code or
// town typed in), how far around it and in what order, then the stations
// found there. A tap plays one; its menu keeps it on the phone, or adds it
// to the server for an admin. The stations kept come last.
@Composable
fun LiveRadioScreen(onBack: () -> Unit, vm: LiveRadioViewModel = hiltViewModel()) {
    val kept by vm.kept.collectAsStateWithLifecycle()
    val sheet = LocalChoiceSheet.current
    val context = LocalContext.current
    val keyboard = LocalSoftwareKeyboardController.current
    // After a second refusal Android stops asking; then only its settings
    // for Octo can allow location.
    val ask = rememberLauncherForActivityResult(ActivityResultContracts.RequestPermission()) { granted ->
        val canAskAgain = (context as? Activity)?.shouldShowRequestPermissionRationale(Manifest.permission.ACCESS_COARSE_LOCATION) ?: true
        if (granted) vm.useLocation() else vm.locationRefused(forGood = !canAskAgain)
    }
    val openSettings = {
        context.startActivity(Intent(Settings.ACTION_APPLICATION_DETAILS_SETTINGS, "package:${context.packageName}".toUri()))
    }
    val useLocation = {
        keyboard?.hide()
        when {
            ContextCompat.checkSelfPermission(context, Manifest.permission.ACCESS_COARSE_LOCATION) == PackageManager.PERMISSION_GRANTED -> vm.useLocation()
            vm.locationBlocked -> openSettings()
            else -> ask.launch(Manifest.permission.ACCESS_COARSE_LOCATION)
        }
    }
    val countries = remember { countryChoices() }
    val pickCountry = {
        // The phone's own country first, then every other by name.
        val here = countries.filter { it.first == vm.country }
        val ordered = here + countries.filterNot { it.first == vm.country }
        sheet.show(ChoiceRequest("Country", ordered.map { Choice(it.second) }, selected = if (here.isEmpty()) -1 else 0) { vm.country = ordered[it].first })
    }
    val menu: (LiveStation) -> Unit = { station ->
        val actions = vm.actions(station)
        sheet.show(ChoiceRequest(station.name, actions.map { Choice(it.label) }, selected = -1) { vm.act(station, actions[it]) })
    }
    val search = vm.search
    val place = search?.place
    val miles = vm.miles
    Box(Modifier.fillMaxSize()) {
        LazyColumn(Modifier.fillMaxSize(), contentPadding = screenPadding(extraTop = DetailTopGap)) {
            item(key = "title") { ScreenTitle(LIVE_NEAR_TITLE) }
            if (search != null) {
                if (place == null || vm.choosing) {
                    item(key = "chooser") {
                        PlaceChooser(
                            vm = vm,
                            countryName = countries.firstOrNull { it.first == vm.country }?.second ?: vm.country,
                            canCancel = place != null,
                            onUseLocation = useLocation,
                            onOpenSettings = openSettings,
                            onPickCountry = pickCountry,
                            onFind = { text ->
                                keyboard?.hide()
                                vm.findTyped(text)
                            },
                        )
                    }
                } else {
                    item(key = "place") { PlaceLine(place, onChange = { vm.choose(true) }) }
                }
                if (place != null) {
                    item(key = "sort") {
                        Segmented(
                            options = SortWords,
                            selected = search.sort.ordinal,
                            onSelect = { vm.setSort(LiveSort.entries[it]) },
                            modifier = Modifier.padding(start = 20.dp, end = 20.dp, top = 12.dp),
                        )
                    }
                    item(key = "radius") {
                        val choices = radiusChoices(miles)
                        LazyRow(
                            contentPadding = PaddingValues(horizontal = 20.dp),
                            horizontalArrangement = Arrangement.spacedBy(8.dp),
                            modifier = Modifier.padding(top = 12.dp, bottom = 8.dp),
                        ) {
                            itemsIndexed(choices, key = { _, radius -> radius }) { index, radius ->
                                RadiusChip(radiusLabel(miles, radius), chosen = index == search.radiusIndex.coerceIn(0, choices.lastIndex)) { vm.setRadius(index) }
                            }
                        }
                    }
                }
                when (val results = vm.results) {
                    LiveResults.NoPlace -> Unit
                    LiveResults.Loading -> item(key = "loading") {
                        Box(Modifier.fillMaxWidth().padding(top = 24.dp), contentAlignment = Alignment.Center) {
                            CircularProgressIndicator(color = OctoColors.Accent, strokeWidth = 2.dp, modifier = Modifier.size(22.dp))
                        }
                    }
                    LiveResults.Offline -> item(key = "offline") {
                        Trouble("You're offline. Live radio needs a connection.", vm::load)
                    }
                    LiveResults.CatalogDown -> item(key = "down") {
                        Trouble("The radio catalog is not answering right now.", vm::load)
                    }
                    is LiveResults.Ready -> {
                        if (results.stations.isEmpty()) {
                            item(key = "none") { Note(noStationsLine(miles, vm.radius())) }
                        }
                        items(results.stations, key = { "near:${it.uuid}" }) { station ->
                            LiveStationRow(station, miles, onPlay = { vm.play(results.stations, station) }, onMenu = { menu(station) }, modifier = Modifier.choiceAnchor(sheet))
                        }
                        hiddenLine(results.hidden)?.let { line -> item(key = "hidden") { Note(line, Modifier.padding(top = 8.dp)) } }
                    }
                }
            }
            if (kept.stations.isNotEmpty()) {
                item(key = "kept-title") { SectionTitle("Kept on this phone", Modifier.padding(top = 18.dp)) }
                items(kept.stations, key = { "kept:${it.uuid}" }) { station ->
                    LiveStationRow(station, miles, onPlay = { vm.play(kept.stations, station) }, onMenu = { menu(station) }, modifier = Modifier.choiceAnchor(sheet))
                }
            }
        }
        BackButton(onBack)
    }
}

// Where the stations are found around, with a way to change it.
@Composable
private fun PlaceLine(place: LivePlace, onChange: () -> Unit) {
    Row(
        Modifier.fillMaxWidth().padding(horizontal = 20.dp),
        verticalAlignment = Alignment.CenterVertically,
        horizontalArrangement = Arrangement.spacedBy(12.dp),
    ) {
        Column(Modifier.weight(1f)) {
            Text("Near", style = OctoType.caption, color = OctoColors.TextMuted)
            Text(place.label, style = OctoType.body, color = OctoColors.TextPrimary)
        }
        GlazeButton("Change", onClick = onChange, size = ButtonSize.Small)
    }
}

// Choosing a place: the phone's rough position, or a ZIP, postal code or
// town in a country. Location is asked for only when its button is tapped.
@Composable
private fun PlaceChooser(
    vm: LiveRadioViewModel,
    countryName: String,
    canCancel: Boolean,
    onUseLocation: () -> Unit,
    onOpenSettings: () -> Unit,
    onPickCountry: () -> Unit,
    onFind: (String) -> Unit,
) {
    var typed by rememberSaveable { mutableStateOf("") }
    val sheet = LocalChoiceSheet.current
    Column(Modifier.fillMaxWidth().padding(horizontal = 20.dp), verticalArrangement = Arrangement.spacedBy(12.dp)) {
        Text(
            "Find live stations around a place. Your position is rounded to about a kilometer on the phone before anything uses it.",
            style = OctoType.bodySmall,
            color = OctoColors.TextSecondary,
        )
        vm.placeSource?.let { Text(placeSourceLine(it), style = OctoType.caption, color = OctoColors.TextMuted) }
        AccentButton("Use my location", onClick = onUseLocation, loading = vm.locating, enabled = !vm.locating)
        Text("Or type a ZIP, postal code or town", style = OctoType.caption, color = OctoColors.TextMuted, modifier = Modifier.padding(top = 4.dp))
        GlassInput(
            value = typed,
            onValueChange = { typed = it },
            placeholder = "ZIP, postal code or town",
            keyboardOptions = KeyboardOptions(capitalization = KeyboardCapitalization.Words, imeAction = ImeAction.Search),
            keyboardActions = KeyboardActions(onSearch = { onFind(typed) }),
        )
        Row(horizontalArrangement = Arrangement.spacedBy(12.dp), verticalAlignment = Alignment.CenterVertically) {
            GlazeButton(countryName, onClick = onPickCountry, size = ButtonSize.Small, modifier = Modifier.choiceAnchor(sheet))
            GlazeButton("Find", onClick = { onFind(typed) }, size = ButtonSize.Small, enabled = typed.isNotBlank() && !vm.locating)
            if (canCancel || vm.locating) GlazeButton("Cancel", onClick = { vm.choose(false) }, size = ButtonSize.Small)
        }
        vm.placeProblem?.let { Text(it, style = OctoType.caption, color = OctoColors.TextSecondary) }
        if (vm.locationBlocked) GlazeButton("Open settings", onClick = onOpenSettings, size = ButtonSize.Small)
    }
}

@Composable
private fun Note(text: String, modifier: Modifier = Modifier) {
    Text(text, style = OctoType.bodySmall, color = OctoColors.TextMuted, modifier = modifier.padding(horizontal = 20.dp, vertical = 8.dp))
}

// A list that could not be had, and a way to ask again.
@Composable
private fun Trouble(text: String, onRetry: () -> Unit) {
    Column(Modifier.padding(horizontal = 20.dp, vertical = 8.dp), verticalArrangement = Arrangement.spacedBy(12.dp)) {
        Text(text, style = OctoType.bodySmall, color = OctoColors.TextMuted)
        GlazeButton("Try again", onClick = onRetry)
    }
}
