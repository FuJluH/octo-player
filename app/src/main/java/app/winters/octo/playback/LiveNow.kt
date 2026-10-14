package app.winters.octo.playback

import app.winters.octo.liveradio.LiveLineup
import app.winters.octo.liveradio.LiveShown
import app.winters.octo.liveradio.liveLineup
import app.winters.octo.liveradio.liveShown

// What the app shows about the live station on now: what it has on air,
// the stations it was started from, and since when the listener has been
// on it (an elapsedRealtime, null while it is stopped).
data class LiveNow(val shown: LiveShown, val lineup: LiveLineup, val since: Long?)

// The live station an item is, with what its stream named last; null for
// anything else.
fun liveNowOf(id: String?, read: IcyRead?, queueIds: List<String>, current: Int, since: Long?): LiveNow? {
    if (id == null || !isRadio(id)) return null
    val shown = liveShown(id, read?.streamTitle, read?.streamUrl) ?: return null
    val lineup = liveLineup(queueIds, current) ?: LiveLineup(listOf(id), 0)
    return LiveNow(shown, lineup, since)
}

// How long the listener has been on the station that plays: from when it
// started playing, afresh for each station, and afresh after Stop then
// Play. Buffering on the way does not stop the count.
class LiveClock(private val now: () -> Long) {
    private var station: String? = null
    private var since: Long? = null

    // Hears the player: the station's queue entry (null for none), whether
    // it plays, and whether it is meant to (false once stopped).
    fun heard(entry: String?, playing: Boolean, playWhenReady: Boolean): Long? {
        if (entry != station) {
            station = entry
            since = null
        }
        if (entry == null || !playWhenReady) since = null
        else if (playing && since == null) since = now()
        return since
    }
}
