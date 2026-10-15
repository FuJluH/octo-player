package app.winters.octo.desktop.animated

import app.winters.octo.desktop.settings.DesktopOs
import com.sun.jna.Library
import com.sun.jna.Native
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.delay
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.StateFlow
import kotlinx.coroutines.flow.asStateFlow
import kotlinx.coroutines.launch

// How often the power saving switch is read again.
private const val LookMs = 30_000L

// Whether the computer is saving power: Windows' battery saver (Energy
// saver on Windows 11), read now and then. Always false on macOS and
// Linux, where no cheap reading exists.
class PowerSaving(private val os: DesktopOs?) {
    private val _on = MutableStateFlow(false)
    val on: StateFlow<Boolean> = _on.asStateFlow()

    fun start(scope: CoroutineScope) {
        if (os != DesktopOs.Windows) return
        scope.launch(Dispatchers.IO) {
            while (true) {
                _on.value = windowsSavesPower()
                delay(LookMs)
            }
        }
    }
}

private interface Kernel32 : Library {
    // SYSTEM_POWER_STATUS: AC line, battery flag, battery percent, system
    // status flag (1 while battery saver is on), then two DWORDs.
    fun GetSystemPowerStatus(status: ByteArray): Boolean
}

private val kernel32: Kernel32? by lazy { runCatching { Native.load("kernel32", Kernel32::class.java) }.getOrNull() }

internal fun windowsSavesPower(): Boolean {
    val status = ByteArray(12)
    val read = runCatching { kernel32?.GetSystemPowerStatus(status) == true }.getOrDefault(false)
    return read && status[3].toInt() == 1
}
