package app.winters.octo.ui.common

import android.os.SystemClock
import kotlinx.coroutines.delay

// Waits for the next whole `periodMs` of the phone's clock. Slow things that
// tick on the same period (the bar's ring and the glow behind the pages,
// say) wake together this way and share one frame, rather than each waking
// the whole window on its own.
suspend fun delayToNextTick(periodMs: Long) {
    if (periodMs <= 0) return
    delay(periodMs - SystemClock.uptimeMillis() % periodMs)
}
