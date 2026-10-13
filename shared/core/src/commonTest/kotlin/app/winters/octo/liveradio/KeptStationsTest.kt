package app.winters.octo.liveradio

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

class KeptStationsTest {
    private fun station(uuid: String, name: String = uuid) = LiveStation(uuid, name, "http://s/$uuid", distanceMeters = 812.0)

    @Test
    fun aKeptStationGoesOnTopOnceAndForgetsWhereItWasFound() {
        val kept = KeptStations().keep(station("a")).keep(station("b")).keep(station("a", "A again"))
        assertEquals(listOf("a", "b"), kept.stations.map { it.uuid })
        assertEquals("A again", kept.stations.first().name)
        assertEquals(null, kept.stations.first().distanceMeters)
        assertTrue(kept.has("b"))
        assertFalse(kept.drop("b").has("b"))
    }

    @Test
    fun keptStationsAreSavedAndReadBack() {
        val kept = KeptStations().keep(station("a")).keep(station("b"))
        assertEquals(kept, KeptStations.decoded(kept.encoded()))
        assertEquals(KeptStations(), KeptStations.decoded("not json"))
        assertEquals(KeptStations(), KeptStations.decoded(null))
    }
}
