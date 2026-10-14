package app.winters.octo.ui.sound

import android.content.Intent
import android.net.Uri
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue
import androidx.lifecycle.ViewModel
import androidx.lifecycle.viewModelScope
import app.winters.octo.sound.AudioOutput
import app.winters.octo.sound.EqPreset
import app.winters.octo.sound.EqPresets
import app.winters.octo.sound.AudioSession
import app.winters.octo.sound.ParametricEqFile
import app.winters.octo.sound.SoundEngine
import app.winters.octo.sound.SoundFiles
import app.winters.octo.sound.SoundSettings
import app.winters.octo.sound.UserPresets
import dagger.hilt.android.lifecycle.HiltViewModel
import kotlinx.coroutines.Job
import kotlinx.coroutines.delay
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.first
import kotlinx.coroutines.launch
import kotlinx.coroutines.withTimeoutOrNull
import javax.inject.Inject

// How often a drag saves while the finger moves. The page itself follows
// the finger every frame.
private const val SAVE_EVERY_MS = 100L

// Everything the Sound page shows and changes. Changes go to the output
// playing now.
@HiltViewModel
class SoundViewModel @Inject constructor(
    private val engine: SoundEngine,
    private val userPresets: UserPresets,
    private val files: SoundFiles,
    private val session: AudioSession,
) : ViewModel() {
    val saved: StateFlow<SoundSettings> = engine.current
    val output: StateFlow<AudioOutput> = engine.output

    // Whether the output playing now is worn, so crossfeed can play on it.
    val forHeadphones: StateFlow<Boolean> = engine.forHeadphones
    val perOutput: StateFlow<Boolean> = engine.perOutput
    val presets: StateFlow<List<EqPreset>> = userPresets.presets

    // The settings as a drag has left them, ahead of the saved ones, so
    // the page follows the finger while writes are spaced out.
    var draft by mutableStateOf<SoundSettings?>(null)
        private set

    // Why the last file could not be read or written, until the next try.
    var fileProblem by mutableStateOf<String?>(null)
        private set

    // Whether the flat button is being held, with the equalizer off for it.
    var heldFlat by mutableStateOf(false)
        private set

    private var pending: ((SoundSettings) -> SoundSettings)? = null
    private var writer: Job? = null

    // A change saved at once, like a switch or a tap.
    fun change(edit: (SoundSettings) -> SoundSettings) {
        draft = draft?.let(edit)
        engine.update(edit)
    }

    // A change from a moving finger: shown at once, saved at most every
    // 100 ms, and once more when the finger stops. Each edit sets values
    // outright, so saving only the latest one loses nothing.
    fun preview(edit: (SoundSettings) -> SoundSettings) {
        draft = edit(draft ?: engine.current.value)
        pending = edit
        if (writer?.isActive != true) writer = viewModelScope.launch { writeWhileMoving() }
    }

    // The finger lifted: save the last position now.
    fun settle() {
        pending?.let {
            pending = null
            engine.update(it)
        }
    }

    private suspend fun writeWhileMoving() {
        while (true) {
            val edit = pending
            if (edit != null) {
                pending = null
                engine.update(edit)
                delay(SAVE_EVERY_MS)
                continue
            }
            // Keep showing the draft until the saved settings catch up, so
            // nothing flickers back for a frame.
            val target = draft
            withTimeoutOrNull(1_000) { engine.current.first { it == target } }
            if (pending == null) {
                if (draft == target) draft = null
                return
            }
        }
    }

    fun setPerOutput(on: Boolean) = engine.setPerOutput(on)

    fun applyPreset(preset: EqPreset) = change { withPreset(it, preset) }

    // Saves the ten bands under a name, and marks the curve as that preset.
    fun savePreset(name: String) {
        val clean = name.trim()
        if (!canSaveAs(clean)) return
        userPresets.save(clean, current().graphicGains)
        change { it.copy(preset = clean) }
    }

    // A name can be used unless a built-in preset has it.
    fun canSaveAs(name: String): Boolean {
        val clean = name.trim()
        return clean.isNotEmpty() && !clean.equals(CUSTOM, ignoreCase = true) &&
            EqPresets.none { it.name.equals(clean, ignoreCase = true) }
    }

    fun deletePreset(name: String) {
        userPresets.delete(name)
        if (current().preset == name) change { it.copy(preset = null) }
    }

    // While the flat button is held the equalizer is off, and it comes back
    // on when the button is let go.
    fun hearFlat(held: Boolean) {
        if (held && !heldFlat && current().eqEnabled) {
            heldFlat = true
            change { it.copy(eqEnabled = false) }
        } else if (!held && heldFlat) {
            heldFlat = false
            change { it.copy(eqEnabled = true) }
        }
    }

    // Reads a correction file the listener picked. It switches the
    // equalizer on, since a correction only plays through it.
    fun importCorrection(uri: Uri) {
        viewModelScope.launch {
            val correction = files.readCorrection(uri)
            if (correction == null) {
                fileProblem = "That file has no filters Octo can read."
            } else {
                fileProblem = null
                change { it.copy(eqEnabled = true, correction = correction) }
            }
        }
    }

    fun removeCorrection() = change { it.copy(correction = null) }

    // Writes everything the equalizer applies, correction included, as a
    // file another equalizer can load.
    fun exportCurve(uri: Uri) {
        val on = current().copy(eqEnabled = true)
        val text = ParametricEqFile.write(on.effectivePreampDb(), on.activeFilters())
        viewModelScope.launch {
            fileProblem = if (files.write(uri, text)) null else "The file could not be saved."
        }
    }

    // The phone's own equalizer screen, or nothing when no app offers one.
    fun systemEqualizer(): Intent? = files.systemEqualizer(session.id)

    private fun current(): SoundSettings = draft ?: engine.current.value

    // A held button must not leave the equalizer off if the page closes.
    override fun onCleared() {
        if (heldFlat) engine.update { it.copy(eqEnabled = true) }
        settle()
    }
}
