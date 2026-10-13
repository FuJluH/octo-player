package app.winters.octo.liveradio

import androidx.datastore.core.DataStore
import androidx.datastore.preferences.core.Preferences
import androidx.datastore.preferences.core.emptyPreferences
import kotlinx.coroutines.flow.Flow
import kotlinx.coroutines.flow.MutableStateFlow
import kotlinx.coroutines.flow.first
import kotlinx.coroutines.runBlocking
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

class LiveRadioStoreTest {
    // A store held in memory, standing in for the phone's.
    private class MemoryStore : DataStore<Preferences> {
        private val current = MutableStateFlow(emptyPreferences())
        override val data: Flow<Preferences> = current

        override suspend fun updateData(transform: suspend (t: Preferences) -> Preferences): Preferences =
            transform(current.value).also { current.value = it }
    }

    private fun station(uuid: String, distance: Double? = null) =
        LiveStation(uuid = uuid, name = "Station $uuid", streamUrl = "https://stream.example/$uuid", distanceMeters = distance, tags = listOf("jazz"))

    @Test
    fun keptStationsAreKeptNewestFirstAndCanBeLetGo() = runBlocking {
        val store = LiveRadioStore(MemoryStore())
        assertTrue(store.kept.first().stations.isEmpty())
        store.keep(station("a", distance = 1200.0))
        store.keep(station("b"))
        assertEquals(listOf("b", "a"), store.kept.first().stations.map { it.uuid })
        // Kept without the distance from where it was found.
        assertNull(store.kept.first().stations.last().distanceMeters)
        assertTrue(store.kept.first().has("a"))
        store.drop("a")
        assertEquals(listOf("b"), store.keptNow().stations.map { it.uuid })
    }

    @Test
    fun keepingAgainMovesItToTheTop() = runBlocking {
        val store = LiveRadioStore(MemoryStore())
        store.keep(station("a"))
        store.keep(station("b"))
        store.keep(station("a"))
        assertEquals(listOf("a", "b"), store.keptNow().stations.map { it.uuid })
    }

    @Test
    fun theLastPlaceRadiusAndOrderAreRemembered() = runBlocking {
        val store = LiveRadioStore(MemoryStore())
        assertEquals(LiveSearch(), store.search.first())
        assertEquals(LIVE_RADIUS_DEFAULT_INDEX, store.search.first().radiusIndex)
        val place = LivePlace(45.52, -122.68, "Portland, Oregon", "Oregon", "US")
        store.setPlace(place)
        store.setRadius(3)
        store.setSort(LiveSort.Popular)
        assertEquals(LiveSearch(place, 3, LiveSort.Popular), store.search.first())
    }

    @Test
    fun aRestoreJoinsTheBackupsStationsToTheOnesHere() = runBlocking {
        val store = LiveRadioStore(MemoryStore())
        store.keep(station("here"))
        store.restore(listOf(station("here"), station("backup")))
        assertEquals(listOf("here", "backup"), store.keptNow().stations.map { it.uuid })
    }
}
