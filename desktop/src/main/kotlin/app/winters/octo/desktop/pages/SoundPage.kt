package app.winters.octo.desktop.pages

import androidx.compose.foundation.Canvas
import androidx.compose.foundation.layout.Arrangement
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.fillMaxWidth
import androidx.compose.foundation.layout.padding
import androidx.compose.foundation.layout.size
import androidx.compose.runtime.Composable
import androidx.compose.runtime.collectAsState
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableIntStateOf
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.remember
import androidx.compose.runtime.setValue
import androidx.compose.ui.Alignment
import androidx.compose.ui.Modifier
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.Path
import androidx.compose.ui.graphics.drawscope.Stroke
import androidx.compose.ui.layout.onGloballyPositioned
import androidx.compose.ui.unit.IntRect
import app.winters.octo.design.ControlHeight
import app.winters.octo.design.DesktopType
import app.winters.octo.design.FrameSize
import app.winters.octo.design.GlassField
import app.winters.octo.design.GlazeCapsule
import app.winters.octo.design.GlazeSegments
import app.winters.octo.design.MenuRow
import app.winters.octo.design.MenuSeparator
import app.winters.octo.design.MenuTitle
import app.winters.octo.design.OctoColors
import app.winters.octo.design.OctoIcons
import app.winters.octo.design.OctoSwitch
import app.winters.octo.design.PopupPadding
import app.winters.octo.design.SettingsSize
import app.winters.octo.design.Space
import app.winters.octo.design.TextAction
import app.winters.octo.design.Txt
import app.winters.octo.desktop.AppState
import app.winters.octo.desktop.nav.Visit
import app.winters.octo.desktop.settings.PlaybackPrefs
import app.winters.octo.desktop.sound.DEFAULT_BLEND_SECONDS
import app.winters.octo.desktop.sound.EqCurve
import app.winters.octo.desktop.sound.LONGEST_BLEND_SECONDS
import app.winters.octo.desktop.sound.SHORTEST_BLEND_SECONDS
import app.winters.octo.desktop.sound.SoundController
import app.winters.octo.desktop.ui.windowRect
import app.winters.octo.playback.FadeCurve
import app.winters.octo.playback.curveRowLook
import app.winters.octo.playback.detail
import app.winters.octo.playback.fadeInGain
import app.winters.octo.playback.fadeOutGain
import app.winters.octo.playback.label
import app.winters.octo.playback.FASTEST_SPEED
import app.winters.octo.playback.PITCH_RANGE_SEMITONES
import app.winters.octo.playback.SLOWEST_SPEED
import app.winters.octo.playback.semitonesAt
import app.winters.octo.playback.semitonesFraction
import app.winters.octo.playback.semitonesLabel
import app.winters.octo.playback.speedAt
import app.winters.octo.playback.speedFraction
import app.winters.octo.playback.speedLabel
import app.winters.octo.sound.CROSSFEED_ABOUT
import app.winters.octo.sound.CROSSFEED_CUT_HELP
import app.winters.octo.sound.CROSSFEED_CUT_TITLE
import app.winters.octo.sound.CROSSFEED_FEED_HELP
import app.winters.octo.sound.CROSSFEED_FEED_TITLE
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
import app.winters.octo.sound.FilterType
import app.winters.octo.sound.ParametricEqFile
import app.winters.octo.sound.ReplayGainMode
import app.winters.octo.sound.SoundSettings
import app.winters.octo.ui.sound.MAX_FILTERS
import app.winters.octo.ui.sound.MAX_HZ
import app.winters.octo.ui.sound.MAX_Q
import app.winters.octo.ui.sound.MIN_HZ
import app.winters.octo.ui.sound.MIN_Q
import app.winters.octo.ui.sound.cleanGain
import app.winters.octo.ui.sound.presetLabel
import app.winters.octo.ui.sound.readDb
import app.winters.octo.ui.sound.readHz
import app.winters.octo.ui.sound.tidyHz
import app.winters.octo.ui.sound.withFilter
import app.winters.octo.ui.sound.withMode
import app.winters.octo.ui.sound.withNewFilter
import app.winters.octo.ui.sound.withPreset
import app.winters.octo.ui.sound.withoutFilter
import java.awt.FileDialog
import java.awt.Frame
import java.io.File
import java.util.Locale
import kotlin.math.abs
import kotlin.math.ln
import kotlin.math.pow
import kotlin.math.roundToInt

// The ranges the page offers, in decibels, as on the phone.
private val PreampRange = -12f..6f
private val ReplayGainPreampRange = -12f..12f
private val FallbackRange = -12f..6f

private val ReplayGainModes = listOf(ReplayGainMode.Off, ReplayGainMode.Track, ReplayGainMode.Album, ReplayGainMode.Smart)
private val ReplayGainHelp = mapOf(
    ReplayGainMode.Off to "Songs play at the level they were made.",
    ReplayGainMode.Track to "Evens out volume between songs, for shuffles and mixes.",
    ReplayGainMode.Album to "Keeps an album's quiet and loud songs as the artist made them.",
    ReplayGainMode.Smart to "Album while you play an album in order, otherwise song.",
)

private val FilterTypes = listOf(FilterType.Peak, FilterType.LowShelf, FilterType.HighShelf)

// Sound: which output it is for, the equalizer, loudness, balance,
// crossfade and speed, and a correction for headphones, each a section in
// the list beside the page. Everything is heard as it moves and saved.
@Composable
fun SoundPage(app: AppState, visit: Visit) {
    val controller = app.sound
    val playerState by app.player.state.collectAsState()
    val all by app.settings.state.collectAsState()
    if (controller == null) {
        SectionedPage(
            app,
            visit,
            "Sound",
            listOf(
                PageSection("none", "No sound engine", OctoIcons.Speaker) {
                    Rows { SettingRow("Nothing to shape", "Octo's sound engine couldn't start on this computer.") }
                },
            ),
        )
        return
    }
    val eq by controller.current.collectAsState()
    val device = playerState.playingOn?.name ?: "this computer"
    SectionedPage(
        app,
        visit,
        "Sound",
        listOf(
            PageSection("output", "Output", OctoIcons.Speaker, detail = if (all.sound.perOutput) "These settings are for $device." else "These settings are for every output.") {
                Rows {
                    SwitchRow(
                        "Each output keeps its own sound",
                        "Speakers, headphones and each USB device remember theirs.",
                        all.sound.perOutput,
                        controller::setPerOutput,
                    )
                }
            },
            PageSection("eq", "Equalizer", OctoIcons.Equalizer, trailing = { OctoSwitch(eq.eqEnabled, { on -> controller.update { it.copy(eqEnabled = on) } }) }) {
                Equalizer(app, controller)
            },
            PageSection("loudness", "Loudness", OctoIcons.Loudness) { LoudnessRows(controller) },
            PageSection("balance", "Balance", OctoIcons.Balance) { BalanceRows(controller) },
            PageSection("crossfeed", "Crossfeed", OctoIcons.Headphones, detail = CROSSFEED_ABOUT, trailing = {
                OctoSwitch(eq.crossfeed.on, { on -> controller.update { it.copy(crossfeed = it.crossfeed.copy(on = on)) } })
            }) { CrossfeedRows(controller) },
            PageSection("playback", "Crossfade and speed", OctoIcons.Crossfade) { PlaybackRows(app, all.playback) },
            PageSection("correction", "Headphone correction", OctoIcons.Headphones) { CorrectionRows(controller) },
        ),
    )
}

// Presets first, then the kind of curve, the curve itself, and the level
// before it.
@Composable
private fun Equalizer(app: AppState, sound: SoundController) {
    val settings by sound.current.collectAsState()
    var chosen by remember { mutableIntStateOf(0) }
    val selected = chosen.coerceIn(0, (settings.filters.size - 1).coerceAtLeast(0))
    val parametric = settings.mode == EqMode.Parametric
    Rows {
        if (!parametric) {
            SettingRow("Preset", null) { PresetButton(app, sound, settings) }
        }
        ChoiceRow(
            "Bands",
            if (parametric) "Filters placed anywhere, for correcting a room or headphones." else "Ten fixed bands, the simplest way.",
            listOf(EqMode.Graphic, EqMode.Parametric),
            settings.mode,
            { if (it == EqMode.Graphic) "Ten bands" else "Free filters" },
            { mode -> sound.update { withMode(it, mode) } },
        )
    }
    Card {
        EqCurve(
            settings,
            selected,
            onSelect = { chosen = it },
            onPreview = sound::preview,
            onSettle = sound::settle,
            modifier = Modifier.padding(horizontal = RowInset).padding(top = Space.L),
            plotHeight = SettingsSize.EqPlot,
        )
        Txt(
            if (parametric) "Drag a point to move a filter; the wheel nudges its gain, a double click sets it flat." else "Drag a band up or down; the wheel nudges it, a double click sets it flat.",
            DesktopType.meta,
            OctoColors.TextMuted,
            Modifier.padding(horizontal = RowInset).padding(top = Space.S, bottom = Space.L),
        )
    }
    if (parametric) FilterEditor(settings, selected, sound) { chosen = it }
    Rows {
        SwitchRow("Automatic preamp", "Lowers the level by the curve's top boost, so it never distorts.", settings.autoPreamp) { on ->
            sound.update { it.copy(autoPreamp = on) }
        }
        if (!settings.autoPreamp) {
            DbSlider("Preamp", "Lower it if a boosted curve distorts.", settings.preampDb, PreampRange, sound) { s, db -> s.copy(preampDb = db) }
        }
    }
}

// The preset in use, opening the list of presets to pick from, save to
// and delete.
@Composable
private fun PresetButton(app: AppState, sound: SoundController, settings: SoundSettings) {
    var anchor by remember { mutableStateOf(IntRect.Zero) }
    Box(Modifier.onGloballyPositioned { anchor = it.windowRect() }) {
        GlazeCapsule(OctoIcons.Sound, presetLabel(settings), {
            app.popups.showUnder(anchor, width = FrameSize.Menu) { close ->
                MenuTitle("Presets")
                // Watched, so a preset deleted here leaves the list at once.
                val saved by app.settings.state.collectAsState()
                val now by sound.current.collectAsState()
                val own = saved.sound.presets.map { it.name }.toSet()
                sound.presets().forEach { preset ->
                    Row(verticalAlignment = Alignment.CenterVertically) {
                        Box(Modifier.weight(1f)) {
                            MenuRow(preset.name, {
                                sound.update { withPreset(it, preset) }
                                close()
                            }, if (preset.name == now.preset) OctoIcons.Check else null)
                        }
                        if (preset.name in own) TextAction("Delete", { sound.deletePreset(preset.name) }, Modifier.padding(end = Space.M))
                    }
                }
                MenuSeparator()
                MenuRow("Save as preset", {
                    close()
                    app.popups.showCentred { done -> SavePreset(sound, done) }
                }, OctoIcons.AddToLibrary)
            }
        }, height = ControlHeight.M)
    }
}

@Composable
private fun SavePreset(sound: SoundController, close: () -> Unit) {
    var name by remember { mutableStateOf("") }
    MenuTitle("Save as preset")
    PopupPadding {
        GlassField(name, { name = it }, placeholder = "Preset name", onSubmit = {
            if (sound.canSaveAs(name)) {
                sound.savePreset(name)
                close()
            }
        })
        if (name.isNotBlank() && !sound.canSaveAs(name)) Txt("A built-in preset has that name.", DesktopType.meta, OctoColors.TextMuted)
        Row(horizontalArrangement = Arrangement.spacedBy(Space.M)) {
            GlazeCapsule(null, "Save", {
                sound.savePreset(name)
                close()
            }, enabled = sound.canSaveAs(name), height = ControlHeight.M)
            GlazeCapsule(null, "Cancel", close, height = ControlHeight.M)
        }
    }
}

// Type, frequency, gain and width of the chosen filter, with adding and
// deleting filters.
@Composable
private fun FilterEditor(settings: SoundSettings, selected: Int, sound: SoundController, onChoose: (Int) -> Unit) {
    val filter = settings.filters.getOrNull(selected)
    Rows {
        if (filter == null) {
            SettingRow("No filters yet", "Add one, then drag it on the curve.")
        } else {
            ChoiceRow("Filter ${selected + 1} of ${settings.filters.size}", null, FilterTypes, filter.type, ::typeName) { type ->
                sound.update { edit(it, selected) { f -> f.copy(type = type) } }
            }
            val logHz = ln(MAX_HZ / MIN_HZ)
            SliderRow(
                "Frequency",
                null,
                readHz(filter.frequency),
                ln(filter.frequency / MIN_HZ) / logHz,
                { x -> sound.preview { edit(it, selected) { f -> f.copy(frequency = tidyHz(MIN_HZ * (MAX_HZ / MIN_HZ).pow(x))) } } },
                onRelease = sound::settle,
            )
            SliderRow(
                "Gain",
                null,
                readDb(filter.gainDb),
                (filter.gainDb + 12f) / 24f,
                { x -> sound.preview { edit(it, selected) { f -> f.copy(gainDb = cleanGain(x * 24f - 12f)) } } },
                onRelease = sound::settle,
                wheelStep = 0.5f / 24f,
            )
            val logQ = ln(MAX_Q / MIN_Q)
            SliderRow(
                "Width (Q)",
                "Lower is wider.",
                String.format(Locale.ROOT, "%.2f", filter.q),
                ln(filter.q / MIN_Q) / logQ,
                { x -> sound.preview { edit(it, selected) { f -> f.copy(q = MIN_Q * (MAX_Q / MIN_Q).pow(x)) } } },
                onRelease = sound::settle,
            )
        }
        SettingRow(
            if (settings.filters.size < MAX_FILTERS) "Filters" else "Filters, all $MAX_FILTERS in use",
            null,
        ) {
            RowAction("Add filter", {
                val next = settings.filters.size
                sound.update { withNewFilter(it).copy(eqEnabled = true) }
                onChoose(next)
            }, enabled = settings.filters.size < MAX_FILTERS, icon = OctoIcons.AddToLibrary)
            if (filter != null) RowAction("Delete filter", { sound.update { withoutFilter(it, selected) } }, icon = OctoIcons.Delete)
        }
    }
}

// Changes one filter, and turns the equalizer on so the change is heard.
private fun edit(settings: SoundSettings, index: Int, change: (EqFilter) -> EqFilter): SoundSettings {
    val filter = settings.filters.getOrNull(index) ?: return settings
    return withFilter(settings, index, change(filter)).copy(eqEnabled = true)
}

private fun typeName(type: FilterType) = when (type) {
    FilterType.Peak -> "Peak"
    FilterType.LowShelf -> "Low shelf"
    FilterType.HighShelf -> "High shelf"
}

// A level in decibels on a slider, heard as it moves.
@Composable
private fun DbSlider(label: String, caption: String?, value: Float, range: ClosedFloatingPointRange<Float>, sound: SoundController, set: (SoundSettings, Float) -> SoundSettings) {
    val span = range.endInclusive - range.start
    SliderRow(
        label,
        caption,
        readDb(value),
        (value - range.start) / span,
        { x -> sound.preview { set(it, tenths(range.start + x * span)) } },
        onRelease = sound::settle,
        wheelStep = 0.5f / span,
    )
}

private fun tenths(db: Float): Float = (db * 10f).roundToInt() / 10f

@Composable
private fun LoudnessRows(sound: SoundController) {
    val settings by sound.current.collectAsState()
    Rows {
        ChoiceRow("Match loudness", ReplayGainHelp.getValue(settings.replayGain), ReplayGainModes, settings.replayGain, {
            when (it) {
                ReplayGainMode.Off -> "Off"
                ReplayGainMode.Track -> "Song"
                ReplayGainMode.Album -> "Album"
                ReplayGainMode.Smart -> "Smart"
            }
        }, { mode -> sound.update { it.copy(replayGain = mode) } })
        if (settings.replayGain != ReplayGainMode.Off) {
            DbSlider("Preamp", "Raise it if matched songs sound too quiet.", settings.replayGainPreampDb, ReplayGainPreampRange, sound) { s, db -> s.copy(replayGainPreampDb = db) }
            DbSlider("Songs without loudness info", "The level for songs that were never measured.", settings.replayGainFallbackDb, FallbackRange, sound) { s, db ->
                s.copy(replayGainFallbackDb = db)
            }
            SwitchRow("Prevent clipping", "Turns a song down rather than letting a boost distort it.", settings.preventClipping) { on ->
                sound.update { it.copy(preventClipping = on) }
            }
        }
        SwitchRow("Limiter", "Catches any peak that would still distort.", settings.limiter) { on ->
            sound.update { it.copy(limiter = on) }
        }
    }
}

@Composable
private fun BalanceRows(sound: SoundController) {
    val settings by sound.current.collectAsState()
    Rows {
        SliderRow(
            "Left and right",
            "Shift the sound toward one ear.",
            readBalance(settings.balance),
            (settings.balance + 1f) / 2f,
            { x ->
                // Snaps to the middle when close, so centred is easy to find.
                val value = (x * 2f - 1f).let { if (abs(it) < 0.04f) 0f else (it * 100f).roundToInt() / 100f }
                sound.preview { it.copy(balance = value) }
            },
            onRelease = sound::settle,
            wheelStep = 0.05f,
        )
        SwitchRow("Mono", "Both ears hear the same thing. Handy with one earbud.", settings.mono) { on ->
            sound.update { it.copy(mono = on) }
        }
    }
}

// The balance in words: "Center", "20% left".
private fun readBalance(balance: Float): String {
    val percent = (abs(balance) * 100).roundToInt()
    return when {
        percent == 0 -> "Center"
        balance < 0 -> "$percent% left"
        else -> "$percent% right"
    }
}

// Crossfade, speed and pitch: for every output, not one at a time.
@Composable
private fun PlaybackRows(app: AppState, playback: PlaybackPrefs) {
    fun change(edit: (PlaybackPrefs) -> PlaybackPrefs) = app.settings.update { it.copy(playback = edit(it.playback)) }
    Rows {
        SwitchRow("Crossfade", "Songs blend into the next. An album played in order runs straight on.", playback.crossfadeSeconds > 0) { on ->
            change { it.copy(crossfadeSeconds = if (on) DEFAULT_BLEND_SECONDS else 0) }
        }
        if (playback.crossfadeSeconds > 0) {
            val seconds = playback.crossfadeSeconds.coerceIn(SHORTEST_BLEND_SECONDS, LONGEST_BLEND_SECONDS)
            val span = (LONGEST_BLEND_SECONDS - SHORTEST_BLEND_SECONDS).toFloat()
            SliderRow(
                "Longest blend",
                "How long two songs may play over each other.",
                "$seconds s",
                (seconds - SHORTEST_BLEND_SECONDS) / span,
                { x -> change { it.copy(crossfadeSeconds = SHORTEST_BLEND_SECONDS + (x * span).roundToInt()) } },
                live = false,
                wheelStep = 1f / span,
            )
            CurveRow(app, playback.crossfadeCurve, playback.smartTransitions) { curve -> change { it.copy(crossfadeCurve = curve) } }
            SwitchRow(
                "Smart transitions",
                "Each blend starts where the music allows, on the beat or as the song winds down. Off, songs fade at the very end.",
                playback.smartTransitions,
            ) { on -> change { it.copy(smartTransitions = on) } }
            if (playback.smartTransitions) {
                SwitchRow("Filter sweeps", "The song that is ending thins out as the next one comes in.", playback.filterSweeps) { on ->
                    change { it.copy(filterSweeps = on) }
                }
                SwitchRow("Match tempo", "Nudges the next song's speed to the beat of this one while they blend.", playback.matchTempo) { on ->
                    change { it.copy(matchTempo = on) }
                }
            }
        }
        SliderRow(
            "Speed",
            "How fast music plays.",
            speedLabel(playback.speed),
            speedFraction(playback.speed),
            { x -> change { it.copy(speed = speedAt(x)) } },
            live = false,
            wheelStep = 0.05f / (FASTEST_SPEED - SLOWEST_SPEED),
        )
        SwitchRow("Keep the pitch", "Off, voices rise and fall with the speed, like a record.", playback.keepPitch) { on ->
            change { it.copy(keepPitch = on) }
        }
        SliderRow(
            "Pitch",
            "Shifts every song up or down, in semitones.",
            semitonesLabel(playback.pitchSemitones),
            semitonesFraction(playback.pitchSemitones),
            { x -> change { it.copy(pitchSemitones = semitonesAt(x)) } },
            live = false,
            wheelStep = 1f / (2 * PITCH_RANGE_SEMITONES),
        )
        if (playback.speed != 1f || !playback.keepPitch || playback.pitchSemitones != 0) {
            ActionRow("Speed or pitch changed", "Every song plays this way until it is set back.", "Back to normal", {
                change { it.copy(speed = 1f, keepPitch = true, pitchSemitones = 0) }
            })
        }
    }
}

// A correction for the headphones in use, read from a ParametricEQ.txt
// file, and the whole curve written out as one.
@Composable
private fun CorrectionRows(sound: SoundController) {
    val settings by sound.current.collectAsState()
    // Why the last import or export did not work, shown on its row.
    var importProblem by remember { mutableStateOf<String?>(null) }
    var exportProblem by remember { mutableStateOf<String?>(null) }
    val correction = settings.correction
    Rows {
        if (correction != null) {
            SettingRow(
                correction.name,
                if (correction.source == ParametricEqFile.IMPORTED) "Imported from a file." else "Measured by ${correction.source}.",
            ) {
                RowAction("Remove", { sound.update { it.copy(correction = null) } })
            }
        }
        ActionRow(
            if (correction == null) "Import a correction" else "Import another",
            importProblem ?: "From a ParametricEQ.txt file made for your headphones.",
            "Import",
            {
                val file = chooseFile("Choose a ParametricEQ.txt file", save = false) ?: return@ActionRow
                val read = runCatching { ParametricEqFile.correction(file.name, file.readText()) }.getOrNull()
                importProblem = if (read == null) "That file has no filters Octo can read." else null
                if (read != null) sound.update { it.copy(eqEnabled = true, correction = read) }
            },
        )
        ActionRow("Export my curve", exportProblem ?: "Saves the equalizer as a ParametricEQ.txt file.", "Export", {
            val file = chooseFile("Save the curve", save = true, suggested = "Octo ParametricEQ.txt") ?: return@ActionRow
            val on = settings.copy(eqEnabled = true)
            exportProblem = if (runCatching { file.writeText(ParametricEqFile.write(on.effectivePreampDb(), on.activeFilters())) }.isSuccess) null else "The file could not be saved."
        })
    }
}

// The system's own file window, for one file to open or save.
private fun chooseFile(title: String, save: Boolean, suggested: String? = null): File? {
    val dialog = FileDialog(null as Frame?, title, if (save) FileDialog.SAVE else FileDialog.LOAD)
    suggested?.let { dialog.file = it }
    dialog.isVisible = true
    val name = dialog.file ?: return null
    return File(dialog.directory, name)
}

// The shape of the crossfade, picked from a menu that draws each one. With
// smart transitions on they pick the curve, and the row says so and names
// the switch under it that frees the choice.
@Composable
private fun CurveRow(app: AppState, curve: FadeCurve, smart: Boolean, onPick: (FadeCurve) -> Unit) {
    val look = curveRowLook(curve, smart)
    if (!look.choosable) {
        SettingRow("Crossfade curve", look.helper, dim = true) {
            Txt(look.value, DesktopType.meta, OctoColors.TextMuted)
        }
        return
    }
    var anchor by remember { mutableStateOf(IntRect.Zero) }
    SettingRow("Crossfade curve", curve.detail) {
        Box(Modifier.onGloballyPositioned { anchor = it.windowRect() }) {
            GlazeCapsule(null, curve.label, {
                app.popups.showUnder(anchor, width = FrameSize.Menu) { close ->
                    MenuTitle("Crossfade curve")
                    FadeCurve.entries.forEach { option ->
                        MenuRow(
                            option.label,
                            {
                                onPick(option)
                                close()
                            },
                            leading = { CurvePreview(option) },
                            checked = option == curve,
                        )
                    }
                }
            }, height = ControlHeight.M)
        }
    }
}

// A small drawing of a curve: the outgoing song falling, the incoming one
// rising.
@Composable
private fun CurvePreview(curve: FadeCurve) {
    Canvas(Modifier.size(width = SettingsSize.CurvePreviewWidth, height = SettingsSize.CurvePreviewHeight)) {
        val steps = 24
        val stroke = SettingsSize.CurveLine.toPx()
        fun line(gain: (Double) -> Double, color: Color) {
            val path = Path()
            for (i in 0..steps) {
                val t = i.toDouble() / steps
                val x = size.width * t.toFloat()
                val y = size.height * (1f - gain(t).toFloat())
                if (i == 0) path.moveTo(x, y) else path.lineTo(x, y)
            }
            drawPath(path, color, style = Stroke(stroke))
        }
        // An 8 second blend, so mix only shows its short edges.
        line({ fadeOutGain(curve, it, 8_000.0) }, OctoColors.TextMuted)
        line({ fadeInGain(curve, it, 8_000.0) }, OctoColors.TextPrimary)
    }
}

// Crossfeed's preset, and the cut and feed of a custom one. Mono leaves
// nothing to blend, so it says so.
@Composable
private fun CrossfeedRows(sound: SoundController) {
    val settings by sound.current.collectAsState()
    val feed = settings.crossfeed
    fun change(edit: (Crossfeed) -> Crossfeed) = sound.update { it.copy(crossfeed = edit(it.crossfeed)) }
    fun preview(edit: (Crossfeed) -> Crossfeed) = sound.preview { it.copy(crossfeed = edit(it.crossfeed)) }
    Rows {
        if (settings.mono && feed.on) SettingRow(CROSSFEED_MONO, null, dim = true)
        ChoiceRow("Preset", feed.preset.detail, CrossfeedPreset.entries, feed.preset, { it.label }) { preset ->
            change { it.copy(on = true, preset = preset) }
        }
        if (feed.preset == CrossfeedPreset.Custom) {
            val logCut = ln(CROSSFEED_MAX_CUT_HZ.toFloat() / CROSSFEED_MIN_CUT_HZ)
            SliderRow(
                CROSSFEED_CUT_TITLE,
                CROSSFEED_CUT_HELP,
                readHz(feed.activeCutHz.toFloat()),
                ln(feed.activeCutHz.toFloat() / CROSSFEED_MIN_CUT_HZ) / logCut,
                { x ->
                    val hz = (CROSSFEED_MIN_CUT_HZ * (CROSSFEED_MAX_CUT_HZ.toFloat() / CROSSFEED_MIN_CUT_HZ).pow(x) / 10f).roundToInt() * 10
                    preview { it.copy(on = true, cutHz = hz) }
                },
                onRelease = sound::settle,
                wheelStep = 0.02f,
            )
            val span = CROSSFEED_MAX_FEED_DB - CROSSFEED_MIN_FEED_DB
            SliderRow(
                CROSSFEED_FEED_TITLE,
                CROSSFEED_FEED_HELP,
                readDb(-feed.activeFeedDb),
                (feed.activeFeedDb - CROSSFEED_MIN_FEED_DB) / span,
                { x -> preview { it.copy(on = true, feedDb = tenths(CROSSFEED_MIN_FEED_DB + x * span)) } },
                onRelease = sound::settle,
                wheelStep = 0.5f / span,
            )
        }
    }
}
