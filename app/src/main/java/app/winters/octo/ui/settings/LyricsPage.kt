package app.winters.octo.ui.settings

import androidx.compose.foundation.layout.padding
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.unit.dp
import androidx.hilt.lifecycle.viewmodel.compose.hiltViewModel
import androidx.lifecycle.ViewModel
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import androidx.lifecycle.viewModelScope
import app.winters.octo.design.OctoIcons
import app.winters.octo.lyrics.LookDial
import app.winters.octo.lyrics.LyricsLook
import app.winters.octo.lyrics.LyricsLookSettings
import app.winters.octo.lyrics.LyricsStyle
import app.winters.octo.lyrics.LyricsTiming
import app.winters.octo.lyrics.OUTPUT_TIMING_LIMIT_MS
import app.winters.octo.lyrics.OutputTiming
import app.winters.octo.lyrics.automaticOutputTiming
import app.winters.octo.lyrics.outputTimingAbout
import app.winters.octo.lyrics.signedTiming
import app.winters.octo.player.PlayerPrefs
import app.winters.octo.player.PlayerSettings
import app.winters.octo.sound.AudioOutput
import app.winters.octo.sound.SoundEngine
import app.winters.octo.ui.common.Choice
import app.winters.octo.ui.common.ChoiceRequest
import app.winters.octo.ui.common.LocalChoiceSheet
import app.winters.octo.ui.common.TimingButtons
import app.winters.octo.ui.settings.rows.ChoiceRow
import app.winters.octo.ui.settings.rows.InfoRow
import app.winters.octo.ui.settings.rows.SettingsGroup
import app.winters.octo.ui.settings.rows.SettingsPageFrame
import app.winters.octo.ui.settings.rows.SliderRow
import app.winters.octo.ui.settings.rows.SwitchRow
import dagger.hilt.android.lifecycle.HiltViewModel
import javax.inject.Inject
import kotlin.math.roundToInt
import kotlinx.coroutines.flow.SharingStarted
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.stateIn
import kotlinx.coroutines.launch

// The look's sliders move in steps of this many percent.
private const val DIAL_STEP = 5

@HiltViewModel
class LyricsSettingsViewModel @Inject constructor(
    private val player: PlayerSettings,
    private val timing: LyricsTiming,
    private val looks: LyricsLookSettings,
    private val sound: SoundEngine,
) : ViewModel() {
    val prefs: StateFlow<PlayerPrefs> = player.prefs.stateIn(viewModelScope, SharingStarted.WhileSubscribed(5_000), PlayerPrefs())
    val keepScreenOn: StateFlow<Boolean> = timing.keepScreenOn.stateIn(viewModelScope, SharingStarted.WhileSubscribed(5_000), true)
    val look: StateFlow<LyricsLook> = looks.look.stateIn(viewModelScope, SharingStarted.WhileSubscribed(5_000), LyricsLook())

    // The output playing now and its lyrics timing.
    val output: StateFlow<AudioOutput> = sound.output
    val outputTiming: StateFlow<OutputTiming> = timing.outputTimingFor(sound.output)
        .stateIn(viewModelScope, SharingStarted.WhileSubscribed(5_000), OutputTiming(automaticOutputTiming(sound.output.value.key), automatic = true))

    fun stepOutput(steps: Int) {
        val output = sound.output.value
        viewModelScope.launch { timing.stepOutput(output, steps) }
    }

    fun resetOutput() {
        val output = sound.output.value
        viewModelScope.launch { timing.resetOutput(output) }
    }

    fun setLyricsOnline(on: Boolean) {
        viewModelScope.launch { player.setLyricsOnline(on) }
    }

    fun setKeepScreenOn(on: Boolean) {
        viewModelScope.launch { timing.setKeepScreenOn(on) }
    }

    fun setStyle(style: LyricsStyle) {
        viewModelScope.launch { looks.setStyle(style) }
    }

    fun setDial(dial: LookDial, percent: Int) {
        viewModelScope.launch { looks.setDial(dial, percent) }
    }

    fun setKeepCompleted(on: Boolean) {
        viewModelScope.launch { looks.setKeepCompleted(on) }
    }

    fun setBloomFast(on: Boolean) {
        viewModelScope.launch { looks.setBloomFast(on) }
    }

    fun setArc(on: Boolean) {
        viewModelScope.launch { looks.setArc(on) }
    }
}

// Each slider's row in the index.
private val DialEntries = mapOf(
    LookDial.Emphasis to SettingsIndex.LyricsEmphasis,
    LookDial.Glow to SettingsIndex.LyricsGlow,
    LookDial.Lift to SettingsIndex.LyricsLift,
    LookDial.Speed to SettingsIndex.LyricsMotionSpeed,
    LookDial.InactiveScale to SettingsIndex.LyricsInactiveScale,
    LookDial.Fade to SettingsIndex.LyricsFade,
    LookDial.Cascade to SettingsIndex.LyricsCascade,
)

// Where lyrics come from, the screen while they show, how synced lyrics
// look, and their timing on the output playing now.
@Composable
fun LyricsPage(onBack: () -> Unit, highlight: String?, vm: LyricsSettingsViewModel = hiltViewModel()) {
    val prefs by vm.prefs.collectAsStateWithLifecycle()
    val keepScreenOn by vm.keepScreenOn.collectAsStateWithLifecycle()
    val look by vm.look.collectAsStateWithLifecycle()
    val output by vm.output.collectAsStateWithLifecycle()
    val outputTiming by vm.outputTiming.collectAsStateWithLifecycle()
    val sheet = LocalChoiceSheet.current

    SettingsPageFrame("Lyrics", onBack, highlight) {
        SettingsGroup {
            SwitchRow(
                SettingsIndex.LyricsOnline,
                checked = prefs.lyricsOnline,
                onChange = vm::setLyricsOnline,
                helper = "From LRCLIB when your music has none. Sends only the title, artist, album and length.",
            )
            SwitchRow(
                SettingsIndex.LyricsScreenOn,
                checked = keepScreenOn,
                onChange = vm::setKeepScreenOn,
            )
        }
        SettingsGroup(title = "Synced lyrics", icon = OctoIcons.Lyrics) {
            ChoiceRow(SettingsIndex.LyricsStyle, value = look.style.label, onClick = {
                val options = LyricsStyle.entries
                sheet.show(
                    ChoiceRequest(
                        SettingsIndex.LyricsStyle.title,
                        options.map { Choice(it.label, it.about) },
                        options.indexOf(look.style),
                    ) { vm.setStyle(options[it]) },
                )
            })
        }
        SettingsGroup(
            title = "Timing",
            icon = OctoIcons.Timer,
            footer = "Words late? Tap Earlier. Early? Tap Later. One song is set from the player's lyrics menu.",
        ) {
            InfoRow(
                SettingsIndex.LyricsOutputTiming,
                value = signedTiming(outputTiming.ms),
                title = output.label,
                helper = outputTimingAbout(output.key, outputTiming.automatic),
            )
            TimingButtons(
                outputTiming.ms,
                OUTPUT_TIMING_LIMIT_MS,
                onStep = vm::stepOutput,
                onReset = vm::resetOutput,
                modifier = Modifier.padding(top = 12.dp, start = 8.dp, end = 8.dp),
                canReset = !outputTiming.automatic,
                resetLabel = "Use automatic",
            )
        }
        SettingsGroup(title = "Look", icon = OctoIcons.Appearance, footer = "For the Flowing style.") {
            LookDial.entries.forEach { dial ->
                DialRow(dial, look.percent(dial)) { vm.setDial(dial, it) }
            }
            SwitchRow(
                SettingsIndex.LyricsKeepCompleted,
                checked = look.keepCompleted,
                onChange = vm::setKeepCompleted,
                helper = "Sung lines stay faintly above.",
            )
            SwitchRow(
                SettingsIndex.LyricsBloomFast,
                checked = look.bloomFast,
                onChange = vm::setBloomFast,
                helper = "Off, only notes held a second or more bloom.",
            )
            SwitchRow(
                SettingsIndex.LyricsArc,
                checked = look.arc,
                onChange = vm::setArc,
                helper = "Lines bend round a drum.",
            )
        }
    }
}

// One of the look's sliders, in percent.
@Composable
private fun DialRow(dial: LookDial, percent: Int, onChange: (Int) -> Unit) {
    val range = dial.range
    val span = (range.last - range.first).toFloat()
    SliderRow(
        DialEntries.getValue(dial),
        value = "$percent%",
        fraction = { (percent - range.first) / span },
        onSeek = { fraction ->
            val raw = range.first + fraction * span
            val picked = ((raw / DIAL_STEP).roundToInt() * DIAL_STEP).coerceIn(range)
            if (picked != percent) onChange(picked)
        },
    )
}
