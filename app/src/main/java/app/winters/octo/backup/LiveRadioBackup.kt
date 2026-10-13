package app.winters.octo.backup

import app.winters.octo.liveradio.LiveRadioStore
import app.winters.octo.liveradio.LiveStation

// The part of a backup Live radio near you gives: the stations kept on the
// phone, never the place they were found around.
class LiveRadioBackup(private val store: LiveRadioStore) {
    suspend fun saved(): List<LiveStation> = store.keptNow().stations

    // The backup's stations join the ones kept here.
    suspend fun restore(backup: Backup) = store.restore(backup.keptStations)
}
