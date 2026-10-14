package app.winters.octo.desktop.sound

import app.winters.octo.audio.AutomixSettings
import app.winters.octo.audio.DspSettings
import app.winters.octo.audio.EqSettings
import app.winters.octo.audio.ReplayGainSettings
import app.winters.octo.desktop.audio.SoundTarget
import app.winters.octo.desktop.settings.AppSettings
import app.winters.octo.desktop.settings.SHARED_SOUND
import app.winters.octo.desktop.settings.SavedCurve
import app.winters.octo.desktop.settings.SettingsStore
import app.winters.octo.desktop.settings.SoundPrefs
import app.winters.octo.playback.Pace
import app.winters.octo.playback.paceOf
import app.winters.octo.sound.EqPreset
import app.winters.octo.sound.EqPresets
import app.winters.octo.sound.SoundSettings
import app.winters.octo.ui.sound.CUSTOM
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Job
import kotlinx.coroutines.delay
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.SharingStarted
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.combine
import kotlinx.coroutines.flow.stateIn
import kotlinx.coroutines.launch

// How often a drag saves while the pointer moves.
const val SAVE_EVERY_MS = 100L

// Which saved set a device uses: its own with "each output its own sound"
// on, otherwise the shared one.
fun soundKey(prefs: SoundPrefs, device: String?): String = if (prefs.perOutput && device != null) device else SHARED_SOUND

// The sound for a device. An output never set up starts from the shared
// set, as on the phone.
fun soundFor(prefs: SoundPrefs, device: String?): SoundSettings =
    prefs.profiles[soundKey(prefs, device)] ?: prefs.profiles[SHARED_SOUND] ?: SoundSettings()

// Everything the engine is told about the sound at once.
data class EngineSound(
    val eq: EqSettings,
    val replayGain: ReplayGainSettings,
    val dsp: DspSettings,
    val crossfadeMs: Int,
    val automix: AutomixSettings,
    val pace: Pace,
)

// The longest blend the crossfade setting allows, and where it starts
// when crossfade is turned on.
const val LONGEST_BLEND_SECONDS = 16
const val SHORTEST_BLEND_SECONDS = 2
const val DEFAULT_BLEND_SECONDS = 8

fun engineSound(settings: AppSettings, device: String?): EngineSound {
    val sound = soundFor(settings.sound, device)
    val playback = settings.playback
    return EngineSound(
        eq = sound.engineEq(),
        replayGain = sound.engineReplayGain(),
        dsp = sound.engineDsp(),
        crossfadeMs = playback.crossfadeSeconds.coerceIn(0, LONGEST_BLEND_SECONDS) * 1_000,
        automix = AutomixSettings(
            smartTransitions = playback.smartTransitions,
            filterSweeps = playback.filterSweeps,
            matchTempo = playback.matchTempo,
            maxOverlapMs = (playback.crossfadeSeconds.coerceIn(0, LONGEST_BLEND_SECONDS) * 1_000).toUInt(),
            fadeCurve = playback.crossfadeCurve.engine(),
        ),
        pace = paceOf(playback.speed, playback.keepPitch, playback.pitchSemitones),
    )
}

// Keeps the engine sounding the way the Sound page says, for the output
// playing now: when a setting changes, and when sound moves to another
// device (headphones plugged in, a USB DAC picked), whose own set then
// applies. Only what changed is sent, so the engine's glides are not
// restarted for nothing.
class SoundController(private val target: SoundTarget, private val settings: SettingsStore, private val scope: CoroutineScope) {
    private var applied: EngineSound? = null

    // The settings as a drag has left them, ahead of the saved ones: heard
    // at once, while the file is written at most every SAVE_EVERY_MS.
    private val draft = MutableStateFlow<SoundSettings?>(null)
    private var pending: ((SoundSettings) -> SoundSettings)? = null
    private var writer: Job? = null

    // The set the Sound page shows and changes.
    val current: StateFlow<SoundSettings> = combine(settings.state, target.deviceKey, draft) { s, device, moving -> moving ?: soundFor(s.sound, device) }
        .stateIn(scope, SharingStarted.Eagerly, soundFor(settings.current.sound, target.deviceKey.value))

    init {
        scope.launch {
            combine(settings.state, target.deviceKey, draft) { s, device, moving ->
                val shown = if (moving == null) s else s.copy(sound = s.sound.copy(profiles = s.sound.profiles + (soundKey(s.sound, device) to moving)))
                engineSound(shown, device)
            }.collect(::apply)
        }
    }

    // A change from a moving pointer: heard and shown at once, saved at
    // most every SAVE_EVERY_MS, and once more by `settle`. Each edit sets
    // values outright, so saving only the latest loses nothing.
    fun preview(change: (SoundSettings) -> SoundSettings) {
        draft.value = change(draft.value ?: current.value)
        pending = change
        if (writer?.isActive != true) {
            writer = scope.launch {
                while (true) {
                    val edit = pending ?: break
                    pending = null
                    update(edit)
                    delay(SAVE_EVERY_MS)
                }
            }
        }
    }

    // The pointer let go: save the last position now.
    fun settle() {
        pending?.let {
            pending = null
            update(it)
        }
        writer?.cancel()
        draft.value = null
    }

    private fun apply(sound: EngineSound) {
        val before = applied
        applied = sound
        if (before == null || before.eq != sound.eq || before.replayGain != sound.replayGain || before.dsp != sound.dsp) {
            target.shape(sound.eq, sound.replayGain, sound.dsp)
        }
        if (before?.crossfadeMs != sound.crossfadeMs) target.setCrossfade(sound.crossfadeMs)
        if (before?.automix != sound.automix) target.setAutomix(sound.automix)
        if (before?.pace != sound.pace) target.setSpeed(sound.pace.speed, sound.pace.pitch)
    }

    // Changes the set for the output playing now (or the shared one).
    fun update(change: (SoundSettings) -> SoundSettings) {
        val device = target.deviceKey.value
        settings.update { s ->
            val key = soundKey(s.sound, device)
            s.copy(sound = s.sound.copy(profiles = s.sound.profiles + (key to change(soundFor(s.sound, device)))))
        }
    }

    // Whether each output keeps its own sound. Turning it on starts every
    // output from the shared set.
    fun setPerOutput(on: Boolean) = settings.update { it.copy(sound = it.sound.copy(perOutput = on)) }

    // The built-in curves, then the listener's own.
    fun presets(): List<EqPreset> = EqPresets + settings.current.sound.presets.map { EqPreset(it.name, it.gains) }

    // Saves the ten bands under a name, and marks the curve as that preset.
    fun savePreset(name: String) {
        val clean = name.trim()
        if (!canSaveAs(clean)) return
        val gains = current.value.graphicGains
        settings.update { s -> s.copy(sound = s.sound.copy(presets = s.sound.presets.filterNot { it.name == clean } + SavedCurve(clean, gains))) }
        update { it.copy(preset = clean) }
    }

    fun deletePreset(name: String) {
        settings.update { s -> s.copy(sound = s.sound.copy(presets = s.sound.presets.filterNot { it.name == name })) }
        if (current.value.preset == name) update { it.copy(preset = null) }
    }

    // A name can be used unless a built-in preset has it.
    fun canSaveAs(name: String): Boolean {
        val clean = name.trim()
        return clean.isNotEmpty() && !clean.equals(CUSTOM, ignoreCase = true) && EqPresets.none { it.name.equals(clean, ignoreCase = true) }
    }
}
