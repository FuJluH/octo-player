package app.winters.octo.sound

import android.app.UiModeManager
import android.content.BroadcastReceiver
import android.content.Context
import android.content.Intent
import android.content.IntentFilter
import android.content.res.Configuration
import android.media.AudioDeviceCallback
import android.media.AudioDeviceInfo
import android.media.AudioManager
import android.os.Handler
import android.os.Looper
import androidx.core.content.ContextCompat
import androidx.datastore.preferences.core.booleanPreferencesKey
import androidx.datastore.preferences.core.edit
import androidx.datastore.preferences.core.stringPreferencesKey
import androidx.datastore.preferences.preferencesDataStore
import dagger.hilt.android.qualifiers.ApplicationContext
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.SharingStarted
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.combine
import kotlinx.coroutines.flow.first
import kotlinx.coroutines.flow.map
import kotlinx.coroutines.flow.stateIn
import kotlinx.coroutines.launch
import kotlinx.serialization.builtins.MapSerializer
import kotlinx.serialization.builtins.serializer
import kotlinx.serialization.json.Json
import javax.inject.Inject
import javax.inject.Singleton

// Where the sound is going: the phone's speaker, a cable, or one Bluetooth
// or USB device, each keeping its own sound settings. `formerKeys` are the
// keys the same output was saved under before, read when nothing is saved
// under `key` yet. `headphones` says whether it is worn: false for a
// speaker.
data class AudioOutput(
    val key: String,
    val label: String,
    val formerKeys: List<String> = emptyList(),
    val headphones: Boolean = true,
) {
    // Every key this output's settings may be saved under, the current one first.
    val keys: List<String> get() = listOf(key) + formerKeys
}

val PhoneSpeaker = AudioOutput("speaker", "Phone speaker", headphones = false)

// The start of a Bluetooth output's key; the rest is the device's name.
const val BLUETOOTH_OUTPUT_PREFIX = "bluetooth:"

// One output device as Android lists it. `speaker` marks a Bluetooth
// speaker rather than headphones.
data class OutputDevice(val kind: OutputKind, val name: String, val address: String, val speaker: Boolean = false)

enum class OutputKind(val rank: Int) { Bluetooth(0), Usb(1), Wired(2), Other(9) }

// The output music goes to: a Bluetooth or USB device or a cable when one
// is connected, otherwise the speaker. A pair of earbuds is often listed
// more than once, once for each bud or each way it connects, each with its
// own address and in no fixed order, so a Bluetooth output is known by its
// name. Its addresses are where its settings were saved before.
fun outputFor(devices: List<OutputDevice>): AudioOutput {
    val kind = devices.minOfOrNull { it.kind.rank }?.let { rank -> OutputKind.entries.first { it.rank == rank } }
    if (kind == null || kind == OutputKind.Other) return PhoneSpeaker
    val listed = devices.filter { it.kind == kind }.sortedWith(compareBy({ it.name.isEmpty() }, { it.name }, { it.address }))
    val name = listed.first().name
    return when (kind) {
        OutputKind.Bluetooth -> {
            val same = listed.filter { it.name == name }
            val addresses = same.map { it.address }.filter(String::isNotEmpty).distinct()
            val key = BLUETOOTH_OUTPUT_PREFIX + name.ifEmpty { addresses.firstOrNull().orEmpty() }
            val former = if (name.isEmpty()) addresses.drop(1) else addresses
            AudioOutput(key, name.ifEmpty { "Bluetooth" }, former.map { "$BLUETOOTH_OUTPUT_PREFIX$it" }, headphones = same.none { it.speaker })
        }
        OutputKind.Usb -> AudioOutput("usb:$name", name.ifEmpty { "USB audio" })
        else -> AudioOutput("wired", "Headphones")
    }
}

// The settings saved for an output: under its key, or else under a key it
// had before.
fun <T> savedFor(saved: Map<String, T>, output: AudioOutput): T? = output.keys.firstNotNullOfOrNull { saved[it] }

private val Context.soundData by preferencesDataStore("sound")

// The sound settings, for the output playing now. With "each output its
// own sound" on, every output remembers its own; otherwise one set is used
// everywhere. The audio path reads `current` on every change.
@Singleton
class SoundEngine @Inject constructor(@ApplicationContext private val context: Context) {
    private val scope = CoroutineScope(SupervisorJob() + Dispatchers.Default)
    private val audio = context.getSystemService(AudioManager::class.java)
    private val json = Json { ignoreUnknownKeys = true; encodeDefaults = false }
    private val mapSerializer = MapSerializer(String.serializer(), SoundSettings.serializer())

    private val _output = MutableStateFlow(currentOutput())
    val output: StateFlow<AudioOutput> = _output

    // Settings saved per output key; "all" holds the shared set.
    private val saved: StateFlow<Map<String, SoundSettings>> = context.soundData.data
        .map { p -> p[PROFILES]?.let { runCatching { json.decodeFromString(mapSerializer, it) }.getOrNull() }.orEmpty() }
        .stateIn(scope, SharingStarted.Eagerly, emptyMap())

    val perOutput: StateFlow<Boolean> = context.soundData.data
        .map { it[PER_OUTPUT] ?: false }
        .stateIn(scope, SharingStarted.Eagerly, false)

    // What plays now. Starts from defaults until the saved settings are read.
    val current: StateFlow<SoundSettings> = combine(saved, perOutput, _output) { all, split, out ->
        (if (split) savedFor(all, out) else null) ?: all[SHARED] ?: SoundSettings()
    }.stateIn(scope, SharingStarted.Eagerly, SoundSettings())

    // Whether the phone is in car mode (Android Auto), when the sound goes to
    // the car however it is connected.
    private val car = MutableStateFlow(inCar())

    // Whether the output playing now is worn: not a speaker, and not a car.
    val forHeadphones: StateFlow<Boolean> = combine(_output, car) { out, inCar -> out.headphones && !inCar }
        .stateIn(scope, SharingStarted.Eagerly, _output.value.headphones && !car.value)

    // What the audio path plays: `current`, with crossfeed left out on an
    // output that is not headphones.
    val playing: StateFlow<SoundSettings> = combine(current, forHeadphones) { settings, worn -> settings.heardOn(worn) }
        .stateIn(scope, SharingStarted.Eagerly, SoundSettings())

    init {
        ContextCompat.registerReceiver(
            context,
            object : BroadcastReceiver() {
                override fun onReceive(context: Context, intent: Intent) {
                    car.value = inCar()
                }
            },
            IntentFilter().apply {
                addAction(UiModeManager.ACTION_ENTER_CAR_MODE)
                addAction(UiModeManager.ACTION_EXIT_CAR_MODE)
            },
            ContextCompat.RECEIVER_NOT_EXPORTED,
        )
        audio.registerAudioDeviceCallback(
            object : AudioDeviceCallback() {
                override fun onAudioDevicesAdded(added: Array<out AudioDeviceInfo>) { _output.value = currentOutput() }
                override fun onAudioDevicesRemoved(removed: Array<out AudioDeviceInfo>) { _output.value = currentOutput() }
            },
            Handler(Looper.getMainLooper()),
        )
    }

    // Changes the settings for the output playing now.
    fun update(change: (SoundSettings) -> SoundSettings) {
        scope.launch {
            context.soundData.edit { p ->
                val all = p[PROFILES]?.let { runCatching { json.decodeFromString(mapSerializer, it) }.getOrNull() }.orEmpty()
                val split = p[PER_OUTPUT] ?: false
                val out = _output.value
                val before = (if (split) savedFor(all, out) else null) ?: all[SHARED] ?: SoundSettings()
                // Saved under the output's key from now on, and nowhere else.
                val kept = if (split) all - out.formerKeys.toSet() else all
                p[PROFILES] = json.encodeToString(mapSerializer, kept + (keyFor(split, out) to change(before)))
            }
        }
    }

    // Whether each output keeps its own settings. Turning it on starts every
    // output from the shared set.
    fun setPerOutput(on: Boolean) {
        scope.launch { context.soundData.edit { it[PER_OUTPUT] = on } }
    }

    // Every saved set by output key, and whether each output keeps its own,
    // for a backup.
    suspend fun saved(): Pair<Boolean, Map<String, SoundSettings>> {
        val p = context.soundData.data.first()
        val all = p[PROFILES]?.let { runCatching { json.decodeFromString(mapSerializer, it) }.getOrNull() }.orEmpty()
        return (p[PER_OUTPUT] ?: false) to all
    }

    // Puts back the sets from a backup. Outputs the backup does not name
    // keep what they have.
    suspend fun restore(perOutput: Boolean, profiles: Map<String, SoundSettings>) {
        context.soundData.edit { p ->
            val all = p[PROFILES]?.let { runCatching { json.decodeFromString(mapSerializer, it) }.getOrNull() }.orEmpty()
            p[PROFILES] = json.encodeToString(mapSerializer, all + profiles)
            p[PER_OUTPUT] = perOutput
        }
    }

    private fun keyFor(perOutput: Boolean, output: AudioOutput) = if (perOutput) output.key else SHARED

    private fun inCar(): Boolean =
        context.getSystemService(UiModeManager::class.java)?.currentModeType == Configuration.UI_MODE_TYPE_CAR

    // The output Android routes music to; see outputFor.
    private fun currentOutput(): AudioOutput = outputFor(
        audio.getDevices(AudioManager.GET_DEVICES_OUTPUTS).map {
            OutputDevice(
                kindOf(it.type),
                it.productName?.toString()?.trim().orEmpty(),
                it.address.orEmpty(),
                speaker = it.type == AudioDeviceInfo.TYPE_BLE_SPEAKER,
            )
        },
    )

    private fun kindOf(type: Int): OutputKind = when (type) {
        AudioDeviceInfo.TYPE_BLUETOOTH_A2DP, AudioDeviceInfo.TYPE_BLE_HEADSET, AudioDeviceInfo.TYPE_BLE_SPEAKER -> OutputKind.Bluetooth
        AudioDeviceInfo.TYPE_USB_HEADSET, AudioDeviceInfo.TYPE_USB_DEVICE -> OutputKind.Usb
        AudioDeviceInfo.TYPE_WIRED_HEADPHONES, AudioDeviceInfo.TYPE_WIRED_HEADSET -> OutputKind.Wired
        else -> OutputKind.Other
    }

    private companion object {
        const val SHARED = "all"
        val PROFILES = stringPreferencesKey("profiles")
        val PER_OUTPUT = booleanPreferencesKey("per_output")
    }
}
