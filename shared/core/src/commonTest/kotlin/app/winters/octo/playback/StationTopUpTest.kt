package app.winters.octo.playback

import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertNull

class StationTopUpTest {
    private val mix = QueueSource.Station("or3kZ9QpLmN2xY7wV1bC0a", "Your Radio")
    private val you = QueueSource.You

    @Test
    fun aStationRunningLowIsToppedUp() {
        val sources = List(50) { mix }
        assertNull(stationToTopUp(sources, current = 29), "twenty songs still to come")
        assertEquals(mix, stationToTopUp(sources, current = 30))
        assertEquals(mix, stationToTopUp(sources, current = 49))
    }

    @Test
    fun theStationCarriesOnAfterSongsQueuedBehindIt() {
        assertEquals(mix, stationToTopUp(List(10) { mix } + you, current = 9))
        assertNull(stationToTopUp(List(10) { mix } + List(25) { you }, current = 10), "twenty four songs still to come")
        assertNull(stationToTopUp(List(10) { mix } + List(3) { you }, current = 10), "the station's songs are all played")
    }

    @Test
    fun aListThatIsNotAStationIsNeverToppedUp() {
        assertNull(stationToTopUp(List(3) { QueueSource.Played("New Releases") }, current = 2))
        assertNull(stationToTopUp(emptyList(), current = 0))
        assertNull(stationToTopUp(List(3) { mix }, current = -1))
    }

    @Test
    fun onlyTheStationsOwnSongsAreSentBack() {
        val other = QueueSource.Station("or000000000000000000ab", "Discovery")
        val items = listOf("a" to mix, "b" to you, "c" to other, "d" to mix)
        assertEquals(listOf("a", "d"), stationSongsQueued(items, mix, { it.second }, { it.first }))
        val many = List(150) { "s$it" to mix }
        assertEquals(STATION_AFTER, stationSongsQueued(many, mix, { it.second }, { it.first }).size)
        assertEquals("s149", stationSongsQueued(many, mix, { it.second }, { it.first }).last())
    }

    @Test
    fun aStationSourceIsSavedAndReadBack() {
        assertEquals("Next from Your Radio", queueSourceTitle(mix))
        listOf(mix, QueueSource.Station("or1", "Radio: a:b")).forEach {
            assertEquals(it, queueSourceOf(it.encoded()))
        }
        assertEquals(NoSource, queueSourceOf("station::nameless"))
    }
}
