package app.winters.octo.ui.sound

import androidx.activity.compose.rememberLauncherForActivityResult
import androidx.activity.result.contract.ActivityResultContracts
import androidx.compose.foundation.clickable
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Column
import androidx.compose.foundation.layout.ColumnScope
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.width
import androidx.compose.foundation.rememberScrollState
import androidx.compose.foundation.shape.RoundedCornerShape
import androidx.compose.foundation.verticalScroll
import androidx.compose.material3.Text
import androidx.compose.runtime.Composable
import androidx.compose.runtime.LaunchedEffect
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.saveable.rememberSaveable
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.platform.LocalFocusManager
import androidx.compose.ui.semantics.Role
import androidx.compose.ui.semantics.contentDescription
import androidx.compose.ui.semantics.heading
import androidx.compose.ui.semantics.semantics
import androidx.compose.ui.text.input.KeyboardCapitalization
import androidx.compose.ui.unit.dp
import androidx.hilt.lifecycle.viewmodel.compose.hiltViewModel
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import app.winters.octo.design.GlassPopup
import app.winters.octo.design.GlazeButton
import app.winters.octo.design.OctoColors
import app.winters.octo.design.OctoSwitch
import app.winters.octo.design.OctoType
import app.winters.octo.design.raisedPanel
import app.winters.octo.sound.CROSSFEED_ABOUT
import app.winters.octo.sound.CROSSFEED_CUT_HELP
import app.winters.octo.sound.CROSSFEED_CUT_TITLE
import app.winters.octo.sound.CROSSFEED_FEED_HELP
import app.winters.octo.sound.CROSSFEED_FEED_TITLE
import app.winters.octo.sound.CROSSFEED_HEADPHONES_ONLY
import app.winters.octo.sound.CROSSFEED_MAX_CUT_HZ
import app.winters.octo.sound.CROSSFEED_MAX_FEED_DB
import app.winters.octo.sound.CROSSFEED_MIN_CUT_HZ
import app.winters.octo.sound.CROSSFEED_MIN_FEED_DB
import app.winters.octo.sound.CROSSFEED_MONO
import app.winters.octo.sound.Crossfeed
import app.winters.octo.sound.CrossfeedPreset
import app.winters.octo.sound.detail
import app.winters.octo.sound.label
import app.winters.octo.sound.EqFilter
import app.winters.octo.sound.EqMode
import app.winters.octo.sound.EqPresets
import app.winters.octo.sound.FilterType
import app.winters.octo.sound.ParametricEqFile
import app.winters.octo.sound.ReplayGainMode
import app.winters.octo.sound.SoundSettings
import app.winters.octo.ui.common.BackButton
import app.winters.octo.ui.common.DetailTopGap
import app.winters.octo.ui.common.LocalHaze
import app.winters.octo.ui.common.PopupNameForm
import app.winters.octo.ui.common.PopupQuestion
import app.winters.octo.ui.common.rememberOpenedBeside
import app.winters.octo.ui.common.ScreenTitle
import app.winters.octo.ui.common.Segmented
import app.winters.octo.ui.common.screenPadding
import app.winters.octo.ui.settings.Card
import app.winters.octo.ui.settings.ChoiceLine
import app.winters.octo.ui.settings.SwitchLine
import java.util.Locale
import kotlin.math.ln
import kotlin.math.pow
import kotlin.math.roundToInt

private val CardShape = RoundedCornerShape(20.dp)

// The manual preamp's range, in decibels.
private val PreampRange = -12f..6f

// The loudness sliders' ranges, in decibels.
private val ReplayGainPreampRange = -12f..12f
private val FallbackRange = -12f..6f

private val ReplayGainModes = listOf(ReplayGainMode.Off, ReplayGainMode.Track, ReplayGainMode.Album, ReplayGainMode.Smart)
private val ReplayGainNames = listOf("Off", "Song", "Album", "Smart")
private val ReplayGainHelp = listOf(
    "Songs play at the level they were made.",
    "Evens out volume between songs.",
    "Keeps an album's quiet and loud songs as the artist made them.",
    "Album while you play an album in order, otherwise song.",
)

private val FilterTypes = listOf(FilterType.Peak, FilterType.LowShelf, FilterType.HighShelf)
private val FilterTypeNames = listOf("Peak", "Low shelf", "High shelf")

// What the page asks about in its sheet.
private sealed interface SoundSheet {
    data object SavePreset : SoundSheet
    data class DeletePreset(val name: String) : SoundSheet
}

// Everything that shapes the sound: the equalizer and its presets,
// loudness, balance, crossfeed, and a correction for the headphones in use.
@Composable
fun SoundScreen(onBack: () -> Unit, vm: SoundViewModel = hiltViewModel()) {
    val saved by vm.saved.collectAsStateWithLifecycle()
    val output by vm.output.collectAsStateWithLifecycle()
    val perOutput by vm.perOutput.collectAsStateWithLifecycle()
    val headphones by vm.forHeadphones.collectAsStateWithLifecycle()
    val settings = vm.draft ?: saved
    var sheet by remember { mutableStateOf<SoundSheet?>(null) }
    var lastSheet by remember { mutableStateOf<SoundSheet?>(null) }
    val show: (SoundSheet) -> Unit = {
        sheet = it
        lastSheet = it
    }

    Box(Modifier.fillMaxSize()) {
        Column(
            Modifier
                .fillMaxSize()
                .verticalScroll(rememberScrollState())
                .padding(screenPadding(extraTop = DetailTopGap)),
        ) {
            ScreenTitle("Sound")
            Column(verticalArrangement = Arrangement.spacedBy(16.dp)) {
                OutputLine(output.label, perOutput, vm::setPerOutput)
                EqualizerCard(settings, vm, onSave = { show(SoundSheet.SavePreset) }, onDelete = { show(SoundSheet.DeletePreset(it)) })
                LoudnessCard(settings, vm)
                BalanceCard(settings, vm)
                CrossfeedCard(settings, headphones, vm)
                CorrectionCard(settings, vm)
            }
        }
        BackButton(onBack)
        SoundSheetHost(sheet, lastSheet, vm, onClose = { sheet = null })
    }
}

// Which output these settings are for, and whether each keeps its own.
@Composable
private fun OutputLine(label: String, perOutput: Boolean, onPerOutput: (Boolean) -> Unit) {
    Column(Modifier.padding(horizontal = 20.dp)) {
        Text("Sound for $label", style = OctoType.body, color = OctoColors.TextPrimary)
        SwitchLine(
            label = "Each output keeps its own sound",
            detail = "The speaker, headphones and each Bluetooth device remember their own settings.",
            checked = perOutput,
            onChange = onPerOutput,
        )
    }
}

// A card with a switch beside its title.
@Composable
private fun SwitchCard(
    title: String,
    checked: Boolean,
    onChange: (Boolean) -> Unit,
    enabled: Boolean = true,
    content: @Composable ColumnScope.() -> Unit,
) {
    Column(
        Modifier
            .padding(horizontal = 20.dp)
            .fillMaxWidth()
            .raisedPanel(CardShape)
            .padding(horizontal = 16.dp, vertical = 20.dp),
        verticalArrangement = Arrangement.spacedBy(12.dp),
    ) {
        Row(Modifier.fillMaxWidth().padding(horizontal = 4.dp), verticalAlignment = Alignment.CenterVertically) {
            Text(
                title,
                style = OctoType.section,
                color = OctoColors.TextPrimary,
                modifier = Modifier.weight(1f).semantics { heading() },
            )
            OctoSwitch(checked = checked, onCheckedChange = onChange, enabled = enabled, modifier = Modifier.semantics { contentDescription = title })
        }
        content()
    }
}

@Composable
private fun EqualizerCard(
    settings: SoundSettings,
    vm: SoundViewModel,
    onSave: () -> Unit,
    onDelete: (String) -> Unit,
) {
    val own by vm.presets.collectAsStateWithLifecycle()
    val parametric = settings.mode == EqMode.Parametric
    // The chosen filter in parametric mode.
    var chosen by rememberSaveable { mutableIntStateOf(0) }
    val selected = chosen.coerceIn(0, (settings.filters.size - 1).coerceAtLeast(0))

    SwitchCard("Equalizer", settings.eqEnabled, onChange = { on -> vm.change { it.copy(eqEnabled = on) } }) {
        Segmented(
            options = listOf("Graphic", "Parametric"),
            selected = if (parametric) 1 else 0,
            onSelect = { index -> vm.change { withMode(it, if (index == 1) EqMode.Parametric else EqMode.Graphic) } },
        )
        ResponseGraph(
            settings = settings,
            selected = selected,
            onSelect = { chosen = it },
            onPreview = vm::preview,
            onSettle = vm::settle,
        )
        if (parametric) {
            FilterEditor(settings, selected, vm, onChoose = { chosen = it })
        }
        val label = presetLabel(settings)
        val choices = buildList {
            if (label == CUSTOM) add(PresetChoice(CUSTOM, own = false))
            EqPresets.forEach { add(PresetChoice(it.name, own = false)) }
            own.forEach { add(PresetChoice(it.name, own = true)) }
        }
        PresetBar(
            choices = choices,
            selected = label,
            onPick = { choice ->
                val preset = if (choice.own) own.firstOrNull { it.name == choice.name } else EqPresets.firstOrNull { it.name == choice.name }
                preset?.let(vm::applyPreset)
            },
            onLongPress = { onDelete(it.name) },
        )
        if (!parametric) {
            TextAction("Save as preset…", Modifier.padding(horizontal = 4.dp), onClick = onSave)
        }
        Hairline()
        Preamp(settings, vm)
        Hairline()
        HoldButton(
            text = "Hold to hear it flat",
            enabled = settings.eqEnabled || vm.heldFlat,
            onHold = vm::hearFlat,
            modifier = Modifier.align(Alignment.CenterHorizontally),
        )
    }
}

// Type, frequency, gain and width of the chosen filter, with adding and
// deleting filters.
@Composable
private fun FilterEditor(settings: SoundSettings, selected: Int, vm: SoundViewModel, onChoose: (Int) -> Unit) {
    val filter = settings.filters.getOrNull(selected)
    Column(Modifier.padding(horizontal = 4.dp), verticalArrangement = Arrangement.spacedBy(4.dp)) {
        if (filter == null) {
            Text("No filters yet. Add one, then drag it on the curve.", style = OctoType.caption, color = OctoColors.TextMuted)
        } else {
            Text(
                "Filter ${selected + 1} of ${settings.filters.size}",
                style = OctoType.caption,
                color = OctoColors.TextMuted,
            )
            Segmented(
                options = FilterTypeNames,
                selected = FilterTypes.indexOf(filter.type).coerceAtLeast(0),
                onSelect = { index -> vm.change { edit(it, selected) { f -> f.copy(type = FilterTypes[index]) } } },
                modifier = Modifier.padding(vertical = 6.dp),
            )
            val logHz = ln(MAX_HZ / MIN_HZ)
            ValueSlider(
                label = "Frequency",
                value = filter.frequency,
                range = MIN_HZ..MAX_HZ,
                reading = readHz(filter.frequency),
                onChange = { hz -> vm.preview { edit(it, selected) { f -> f.copy(frequency = tidyHz(hz)) } } },
                step = 1f,
                toFraction = { ln(it / MIN_HZ) / logHz },
                fromFraction = { MIN_HZ * (MAX_HZ / MIN_HZ).pow(it) },
            )
            ValueSlider(
                label = "Gain",
                value = filter.gainDb,
                range = -12f..12f,
                reading = readDb(filter.gainDb),
                onChange = { db -> vm.preview { edit(it, selected) { f -> f.copy(gainDb = db) } } },
                step = 0.1f,
            )
            val logQ = ln(MAX_Q / MIN_Q)
            ValueSlider(
                label = "Q",
                value = filter.q,
                range = MIN_Q..MAX_Q,
                reading = String.format(Locale.ROOT, "%.2f", filter.q),
                onChange = { q -> vm.preview { edit(it, selected) { f -> f.copy(q = q) } } },
                step = 0.01f,
                toFraction = { ln(it / MIN_Q) / logQ },
                fromFraction = { MIN_Q * (MAX_Q / MIN_Q).pow(it) },
            )
        }
        Row(Modifier.fillMaxWidth().padding(top = 6.dp), horizontalArrangement = Arrangement.spacedBy(12.dp)) {
            GlazeButton(
                "Add filter",
                onClick = {
                    val next = settings.filters.size
                    vm.change { withNewFilter(it) }
                    onChoose(next)
                },
                enabled = settings.filters.size < MAX_FILTERS,
            )
            if (filter != null) {
                GlazeButton("Delete filter", onClick = { vm.change { withoutFilter(it, selected) } })
            }
        }
    }
}

// Changes one filter, and turns the equalizer on so the change is heard.
private fun edit(settings: SoundSettings, index: Int, change: (EqFilter) -> EqFilter): SoundSettings {
    val filter = settings.filters.getOrNull(index) ?: return settings
    return withFilter(settings, index, change(filter)).copy(eqEnabled = true)
}

// The level before the equalizer: automatic, or set by hand.
@Composable
private fun Preamp(settings: SoundSettings, vm: SoundViewModel) {
    val effective = remember(settings) { settings.effectivePreampDb() }
    Column(Modifier.padding(horizontal = 4.dp)) {
        SwitchLine(
            label = "Automatic preamp",
            detail = "Lowers the level by the curve's highest boost, so boosting never distorts.",
            checked = settings.autoPreamp,
            onChange = { on -> vm.change { it.copy(autoPreamp = on) } },
        )
        if (!settings.autoPreamp) {
            ValueSlider(
                label = "Preamp",
                value = settings.preampDb,
                range = PreampRange,
                reading = readDb(settings.preampDb),
                onChange = { db -> vm.preview { it.copy(preampDb = db) } },
            )
        }
        Row(Modifier.fillMaxWidth().padding(top = 4.dp)) {
            Text("Level now", style = OctoType.bodySmall, color = OctoColors.TextSecondary, modifier = Modifier.weight(1f))
            Text(readDb(effective), style = OctoType.bodySmall.copy(fontFeatureSettings = "tnum"), color = OctoColors.TextPrimary)
        }
    }
}

@Composable
private fun LoudnessCard(settings: SoundSettings, vm: SoundViewModel) {
    val mode = ReplayGainModes.indexOf(settings.replayGain).coerceAtLeast(0)
    Card("Loudness") {
        Segmented(
            options = ReplayGainNames,
            selected = mode,
            onSelect = { index -> vm.change { it.copy(replayGain = ReplayGainModes[index]) } },
        )
        Text(ReplayGainHelp[mode], style = OctoType.caption, color = OctoColors.TextMuted)
        if (settings.replayGain != ReplayGainMode.Off) {
            ValueSlider(
                label = "Preamp",
                value = settings.replayGainPreampDb,
                range = ReplayGainPreampRange,
                reading = readDb(settings.replayGainPreampDb),
                onChange = { db -> vm.preview { it.copy(replayGainPreampDb = db) } },
            )
            Text("Volume for songs without loudness info", style = OctoType.bodySmall, color = OctoColors.TextPrimary)
            ValueSlider(
                label = "Level",
                value = settings.replayGainFallbackDb,
                range = FallbackRange,
                reading = readDb(settings.replayGainFallbackDb),
                onChange = { db -> vm.preview { it.copy(replayGainFallbackDb = db) } },
            )
            SwitchLine(
                label = "Prevent clipping",
                detail = "Turns a song down rather than letting a boost distort it.",
                checked = settings.preventClipping,
                onChange = { on -> vm.change { it.copy(preventClipping = on) } },
            )
        }
        SwitchLine(
            label = "Limiter",
            detail = "Catches any peak that would still distort, just below full volume.",
            checked = settings.limiter,
            onChange = { on -> vm.change { it.copy(limiter = on) } },
        )
    }
}

@Composable
private fun BalanceCard(settings: SoundSettings, vm: SoundViewModel) {
    Card("Balance") {
        Row(Modifier.fillMaxWidth()) {
            Text("Left and right", style = OctoType.bodySmall, color = OctoColors.TextSecondary, modifier = Modifier.weight(1f))
            Text(readBalance(settings.balance), style = OctoType.bodySmall, color = OctoColors.TextPrimary)
        }
        BalanceSlider(settings.balance, onChange = { value -> vm.preview { it.copy(balance = value) } })
        SwitchLine(
            label = "Mono",
            detail = "Both ears hear the same thing. Handy with one earbud.",
            checked = settings.mono,
            onChange = { on -> vm.change { it.copy(mono = on) } },
        )
    }
}

// Crossfeed: its preset, and the reach and level of a custom one. It only
// plays on headphones, and mono leaves it nothing to blend.
@Composable
private fun CrossfeedCard(settings: SoundSettings, headphones: Boolean, vm: SoundViewModel) {
    val feed = settings.crossfeed
    SwitchCard(
        "Crossfeed",
        checked = feed.on && headphones,
        enabled = headphones,
        onChange = { on -> vm.change { it.copy(crossfeed = it.crossfeed.copy(on = on)) } },
    ) {
        val note = when {
            !headphones -> CROSSFEED_HEADPHONES_ONLY
            settings.mono && feed.on -> CROSSFEED_MONO
            else -> CROSSFEED_ABOUT
        }
        Text(note, style = OctoType.caption, color = OctoColors.TextMuted, modifier = Modifier.padding(horizontal = 4.dp))
        if (headphones) CrossfeedChoices(feed, vm)
    }
}

// The crossfeed presets, and the sliders of a custom one.
@Composable
private fun CrossfeedChoices(feed: Crossfeed, vm: SoundViewModel) {
    val presets = CrossfeedPreset.entries
    Column(verticalArrangement = Arrangement.spacedBy(12.dp)) {
        Segmented(
            options = presets.map { it.label },
            selected = presets.indexOf(feed.preset),
            onSelect = { index -> vm.change { it.copy(crossfeed = it.crossfeed.copy(on = true, preset = presets[index])) } },
        )
        Text(feed.preset.detail, style = OctoType.caption, color = OctoColors.TextMuted, modifier = Modifier.padding(horizontal = 4.dp))
        if (feed.preset == CrossfeedPreset.Custom) {
            val minHz = CROSSFEED_MIN_CUT_HZ.toFloat()
            val maxHz = CROSSFEED_MAX_CUT_HZ.toFloat()
            val logHz = ln(maxHz / minHz)
            ValueSlider(
                label = CROSSFEED_CUT_TITLE,
                value = feed.activeCutHz.toFloat(),
                range = minHz..maxHz,
                reading = readHz(feed.activeCutHz.toFloat()),
                onChange = { hz -> vm.preview { it.copy(crossfeed = it.crossfeed.copy(on = true, cutHz = hz.roundToInt())) } },
                step = 10f,
                toFraction = { ln(it / minHz) / logHz },
                fromFraction = { minHz * (maxHz / minHz).pow(it) },
            )
            Text(CROSSFEED_CUT_HELP, style = OctoType.caption, color = OctoColors.TextMuted, modifier = Modifier.padding(horizontal = 4.dp))
            ValueSlider(
                label = CROSSFEED_FEED_TITLE,
                value = feed.activeFeedDb,
                range = CROSSFEED_MIN_FEED_DB..CROSSFEED_MAX_FEED_DB,
                reading = readDb(-feed.activeFeedDb),
                onChange = { db -> vm.preview { it.copy(crossfeed = it.crossfeed.copy(on = true, feedDb = db)) } },
            )
            Text(CROSSFEED_FEED_HELP, style = OctoType.caption, color = OctoColors.TextMuted, modifier = Modifier.padding(horizontal = 4.dp))
        }
    }
}

// The headphone correction, and moving curves in and out as files.
@Composable
private fun CorrectionCard(settings: SoundSettings, vm: SoundViewModel) {
    val open = rememberLauncherForActivityResult(ActivityResultContracts.OpenDocument()) { uri ->
        uri?.let(vm::importCorrection)
    }
    val create = rememberLauncherForActivityResult(ActivityResultContracts.CreateDocument("text/plain")) { uri ->
        uri?.let(vm::exportCurve)
    }
    val panel = rememberLauncherForActivityResult(ActivityResultContracts.StartActivityForResult()) { }
    val systemEqualizer = remember { vm.systemEqualizer() }
    val correction = settings.correction

    Card("Headphone correction") {
        Row(Modifier.fillMaxWidth(), verticalAlignment = Alignment.CenterVertically) {
            Column(Modifier.weight(1f).padding(end = 12.dp)) {
                Text(correction?.name ?: "None", style = OctoType.bodySmall, color = OctoColors.TextPrimary)
                Text(
                    when {
                        correction == null -> "Evens out how your headphones colour the sound."
                        correction.source == ParametricEqFile.IMPORTED -> "Imported from a file"
                        else -> "Correction by AutoEq, measured by ${correction.source}"
                    },
                    style = OctoType.caption,
                    color = OctoColors.TextMuted,
                )
            }
            if (correction != null) TextAction("Remove", onClick = vm::removeCorrection)
        }
        vm.fileProblem?.let { Text(it, style = OctoType.caption, color = OctoColors.Error) }
        Hairline()
        ChoiceLine("Import correction…", "A ParametricEQ.txt file") { open.launch(arrayOf("text/plain", "text/*")) }
        ChoiceLine("Export my curve…", "Saves it as a ParametricEQ.txt file") { create.launch("Octo ParametricEQ.txt") }
        if (systemEqualizer != null) {
            ChoiceLine("Open system equalizer", "The phone's own sound effects") {
                // Built again so it carries the session in use now.
                vm.systemEqualizer()?.let { runCatching { panel.launch(it) } }
            }
        }
    }
}

// A quiet action in words, with no button around it.
@Composable
private fun TextAction(text: String, modifier: Modifier = Modifier, onClick: () -> Unit) {
    Text(
        text,
        style = OctoType.label,
        color = OctoColors.Accent,
        modifier = modifier
            .clickable(interactionSource = null, indication = null, role = Role.Button, onClick = onClick)
            .padding(vertical = 6.dp),
    )
}

// Naming a new preset, or asking before one is deleted, in a glass card
// beside the button that asked.
@Composable
private fun SoundSheetHost(sheet: SoundSheet?, last: SoundSheet?, vm: SoundViewModel, onClose: () -> Unit) {
    val focus = LocalFocusManager.current
    LaunchedEffect(sheet) { if (sheet == null) focus.clearFocus() }
    val open = sheet != null
    GlassPopup(
        visible = open,
        anchor = rememberOpenedBeside(open),
        onDismiss = onClose,
        backdrop = LocalHaze.current,
        title = "Preset",
    ) {
        when (val shown = last) {
            SoundSheet.SavePreset -> PopupNameForm(
                "Save as preset",
                "Preset name",
                "Save",
                onBack = null,
                capitalization = KeyboardCapitalization.Words,
                ready = { vm.canSaveAs(it) },
                note = { name -> if (name.isNotBlank() && !vm.canSaveAs(name)) "A built-in preset has that name." else null },
                onDone = { name ->
                    vm.savePreset(name)
                    onClose()
                },
            )
            is SoundSheet.DeletePreset -> PopupQuestion(
                "Delete \"${shown.name}\"?",
                null,
                "Delete",
                onConfirm = {
                    vm.deletePreset(shown.name)
                    onClose()
                },
                onCancel = onClose,
            )
            null -> Unit
        }
    }
}

