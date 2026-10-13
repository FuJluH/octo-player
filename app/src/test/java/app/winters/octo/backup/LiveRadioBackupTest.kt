package app.winters.octo.backup

import androidx.datastore.core.DataStore
import androidx.datastore.preferences.core.Preferences
import androidx.datastore.preferences.core.emptyPreferences
import app.winters.octo.liveradio.LIVE_RADIO_STORE
import app.winters.octo.liveradio.LivePlace
import app.winters.octo.liveradio.LiveRadioStore
import app.winters.octo.liveradio.LiveStation
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.first
import kotlinx.coroutines.runBlocking
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test
import java.io.File

// What a backup takes from Live radio near you and puts back: the kept
// stations, as Backups.make and Backups.restore use it; and what Android's
// own backup leaves out: the last place.
class LiveRadioBackupTest {
    private class MemoryStore : DataStore<Preferences> {
        private val current = MutableStateFlow(emptyPreferences())
        override val data: Flow<Preferences> = current

        override suspend fun updateData(transform: suspend (t: Preferences) -> Preferences): Preferences =
            transform(current.value).also { current.value = it }
    }

    private fun station(uuid: String, hls: Boolean = false) =
        LiveStation(uuid = uuid, name = "Station $uuid", streamUrl = "https://stream.example/$uuid", hls = hls, state = "Ohio")

    @Test
    fun keptStationsGoIntoABackupAndComeBackOnAnotherPhone() = runBlocking {
        val here = LiveRadioStore(MemoryStore())
        here.keep(station("a"))
        here.keep(station("b", hls = true))
        here.setPlace(LivePlace(39.96, -83.0, "Columbus, Ohio", "Ohio", "US"))
        val made = Backup(keptStations = LiveRadioBackup(here).saved())
        val text = encodeBackup(made)
        // The place they were found around is not in it.
        assertFalse(text.contains("Columbus"))
        assertFalse(text.contains("39.96"))

        val read = (decodeBackup(text) as BackupRead.Read).backup
        val there = LiveRadioStore(MemoryStore())
        there.keep(station("mine"))
        LiveRadioBackup(there).restore(read)
        assertEquals(listOf("mine", "b", "a"), there.keptNow().stations.map { it.uuid })
        assertEquals(true, there.keptNow().stations.first { it.uuid == "b" }.hls)
        // Restoring never sets a place.
        assertNull(there.search.first().place)
    }

    @Test
    fun aBackupWithoutStationsLeavesTheKeptOnesAlone() = runBlocking {
        val store = LiveRadioStore(MemoryStore())
        store.keep(station("a"))
        LiveRadioBackup(store).restore(Backup())
        assertEquals(listOf("a"), store.keptNow().stations.map { it.uuid })
    }

    // Android's own cloud backup and device transfer leave out the file with
    // the last place; the manifest points at both sets of rules.
    @Test
    fun theLastPlaceStaysOutOfAndroidsCloudBackup() {
        val file = "datastore/$LIVE_RADIO_STORE.preferences_pb"
        val extraction = File("src/main/res/xml/data_extraction_rules.xml").readText()
        assertEquals(2, Regex("""<exclude domain="file" path="${Regex.escape(file)}" />""").findAll(extraction).count())
        assertTrue(extraction.contains("<cloud-backup>") && extraction.contains("<device-transfer>"))
        // Only exclusions: everything else is copied as before.
        assertFalse(extraction.contains("<include"))
        val older = File("src/main/res/xml/backup_rules.xml").readText()
        assertTrue(older.contains("""<exclude domain="file" path="$file" />"""))
        assertFalse(older.contains("<include"))
        val manifest = File("src/main/AndroidManifest.xml").readText()
        assertTrue(manifest.contains("""android:dataExtractionRules="@xml/data_extraction_rules""""))
        assertTrue(manifest.contains("""android:fullBackupContent="@xml/backup_rules""""))
    }
}
