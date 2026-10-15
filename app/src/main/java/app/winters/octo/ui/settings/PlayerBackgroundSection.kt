package app.winters.octo.ui.settings

import android.os.Build
import androidx.compose.runtime.Composable
import androidx.compose.runtime.getValue
import androidx.hilt.lifecycle.viewmodel.compose.hiltViewModel
import androidx.lifecycle.ViewModel
import androidx.lifecycle.compose.collectAsStateWithLifecycle
import androidx.lifecycle.viewModelScope
import app.winters.octo.animated.AnimatedArtSetting
import app.winters.octo.design.OctoIcons
import app.winters.octo.player.LiveBackgroundSupported
import app.winters.octo.player.PlayerPrefs
import app.winters.octo.player.PlayerSettings
import app.winters.octo.player.immersive.BackgroundMode
import app.winters.octo.player.immersive.BackgroundPrefs
import app.winters.octo.player.immersive.BrightnessCapRange
import app.winters.octo.player.immersive.ContrastRange
import app.winters.octo.player.immersive.SaturationRange
import app.winters.octo.player.immersive.SpeedRange
import app.winters.octo.ui.common.Choice
import app.winters.octo.ui.common.ChoiceRequest
import app.winters.octo.ui.common.LocalChoiceSheet
import app.winters.octo.ui.settings.rows.ChoiceRow
import app.winters.octo.ui.settings.rows.SettingsGroup
import app.winters.octo.ui.settings.rows.SliderRow
import app.winters.octo.ui.settings.rows.SwitchRow
import dagger.hilt.android.lifecycle.HiltViewModel
import javax.inject.Inject
import kotlin.math.roundToInt
import kotlinx.coroutines.flow.SharingStarted
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.stateIn
import kotlinx.coroutines.launch

private val ModeChoices = mapOf(
    BackgroundMode.Default to Choice("Immersive", "The artwork torn into drifting layers, blurred into a slow wash of its colors."),
    BackgroundMode.Artwork to Choice("Artwork", "The artwork, blurred and still."),
    BackgroundMode.Colour to Choice("Color", "A flat fill of the artwork's main color."),
    BackgroundMode.Classic to Choice("Classic", "Four of the artwork's colors, flowing into each other."),
)

@HiltViewModel
class PlayerBackgroundViewModel @Inject constructor(private val settings: PlayerSettings) : ViewModel() {
    val prefs: StateFlow<PlayerPrefs> = settings.prefs.stateIn(viewModelScope, SharingStarted.WhileSubscribed(5_000), PlayerPrefs())

    fun setLiveBackground(on: Boolean) {
        viewModelScope.launch { settings.setLiveBackground(on) }
    }

    fun setAnimatedArt(setting: AnimatedArtSetting) {
        viewModelScope.launch { settings.setAnimatedArt(setting) }
    }

    fun update(change: (BackgroundPrefs) -> BackgroundPrefs) {
        viewModelScope.launch { settings.setBackground(change(prefs.value.background)) }
    }
}

// The full player's background: what it is, whether it moves, and how the
// artwork is prepared for it.
@Composable
fun PlayerBackgroundSection(vm: PlayerBackgroundViewModel = hiltViewModel()) {
    val player by vm.prefs.collectAsStateWithLifecycle()
    val background = player.background
    val sheet = LocalChoiceSheet.current
    val washes = Build.VERSION.SDK_INT >= Build.VERSION_CODES.TIRAMISU
    val moves = when (background.mode) {
        BackgroundMode.Default -> washes
        BackgroundMode.Classic -> LiveBackgroundSupported
        else -> false
    }

    SettingsGroup(title = "Player", icon = OctoIcons.Playback) {
        ChoiceRow(SettingsIndex.PlayerBackground, value = ModeChoices.getValue(background.mode).label, onClick = {
            val options = BackgroundMode.entries
            sheet.show(
                ChoiceRequest(SettingsIndex.PlayerBackground.title, options.map(ModeChoices::getValue), options.indexOf(background.mode)) {
                    vm.update { prefs -> prefs.copy(mode = options[it]) }
                },
            )
        })
        SwitchRow(
            SettingsIndex.LiveBackground,
            checked = player.liveBackground && moves,
            onChange = vm::setLiveBackground,
            enabled = moves,
            helper = when {
                background.mode == BackgroundMode.Default && !washes -> "Needs Android 13 or newer."
                background.mode == BackgroundMode.Classic && !LiveBackgroundSupported -> "Needs Android 13 or newer."
                !moves -> "This background stays still."
                else -> null
            },
        )
        if (background.prepared) {
            PercentSlider(SettingsIndex.BackgroundBrightnessCap, background.brightnessCap, BrightnessCapRange, step = 5) { value ->
                vm.update { it.copy(brightnessCap = value) }
            }
            PercentSlider(SettingsIndex.BackgroundSaturation, background.saturation, SaturationRange, step = 10) { value ->
                vm.update { it.copy(saturation = value) }
            }
            ContrastSlider(background.contrast) { value -> vm.update { it.copy(contrast = value) } }
        }
        if (background.mode == BackgroundMode.Default && washes) {
            PercentSlider(SettingsIndex.BackgroundSpeed, background.speed, SpeedRange, step = 5) { value ->
                vm.update { it.copy(speed = value) }
            }
            SwitchRow(
                SettingsIndex.BackgroundUseBpm,
                checked = background.useBpm,
                onChange = { on -> vm.update { it.copy(useBpm = on) } },
                helper = "Drifts with the song's tempo, when it's known.",
            )
        }
        AnimatedArtRow(player.animatedArt, vm::setAnimatedArt)
    }
}

// Where an album's animated art plays, from Octo servers that offer it.
@Composable
private fun AnimatedArtRow(setting: AnimatedArtSetting, onChange: (AnimatedArtSetting) -> Unit) {
    val sheet = LocalChoiceSheet.current
    val options = AnimatedArtSetting.entries
    ChoiceRow(SettingsIndex.AnimatedArt, value = setting.label, helper = AnimatedArtSetting.ABOUT, onClick = {
        sheet.show(
            ChoiceRequest(SettingsIndex.AnimatedArt.title, options.map { Choice(it.label, it.about) }, options.indexOf(setting)) {
                onChange(options[it])
            },
        )
    })
}

// A percentage along a range, in steps, saved only when it changes.
@Composable
private fun PercentSlider(entry: SettingEntry, value: Int, range: IntRange, step: Int, onChange: (Int) -> Unit) {
    val span = (range.last - range.first).toFloat()
    SliderRow(
        entry,
        value = "$value%",
        fraction = { (value - range.first) / span },
        onSeek = { fraction ->
            val picked = range.first + (fraction * span / step).roundToInt() * step
            if (picked != value) onChange(picked.coerceIn(range))
        },
    )
}

// The contrast factor, in steps of 0.05.
@Composable
private fun ContrastSlider(value: Float, onChange: (Float) -> Unit) {
    val range = ContrastRange
    val steps = ((range.endInclusive - range.start) / 0.05f).roundToInt()
    val at = ((value - range.start) / 0.05f).roundToInt()
    SliderRow(
        SettingsIndex.BackgroundContrast,
        value = String.format(java.util.Locale.ROOT, "%.2f", value),
        fraction = { at / steps.toFloat() },
        onSeek = { fraction ->
            val picked = (fraction * steps).roundToInt()
            if (picked != at) onChange(((range.start + picked * 0.05f) * 100f).roundToInt() / 100f)
        },
    )
}
