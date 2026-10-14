package app.winters.octo.discovery

import app.winters.octo.catalog.ArtworkRef
import app.winters.octo.liveradio.radioId
import app.winters.octo.playback.radioDetailsOf
import app.winters.octo.subsonic.RadioStation
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

class HomeStationsTest {
    private val yourMix = "or3kZ9QpLmN2xY7wV1bC0a"

    // Octo's own stations play their songs; a station added to the server
    // keeps its stream and its cover.
    @Test
    fun anAddedStationPlaysItsStream() {
        val radio = listOf(
            RadioStation(yourMix, "Your Radio", "https://octo/radio/stream/abc", coverArt = yourMix),
            RadioStation("rs-1", "City Radio", "https://radio.example.com/live.mp3", coverArt = "ra-rs-1", homePageUrl = "https://city.example"),
        )
        val stations = homeStations(radio, "src1")
        assertNull("Octo's own station plays its songs", stations[0].streamUrl)
        assertEquals("https://radio.example.com/live.mp3", stations[1].streamUrl)
        assertEquals(ArtworkRef.Server("src1", "ra-rs-1").encode(), stations[1].artwork)
        assertEquals("https://city.example", stations[1].homepage)
        assertEquals("https://city.example", radioDetailsOf(stations[1].radioId()).homepage)
    }

    @Test
    fun anAddedStationWithoutACoverStillPlaysItsStream() {
        val station = homeStations(listOf(RadioStation("rs-2", "Town FM", "https://town.example.com/fm")), "src1").single()
        assertEquals("https://town.example.com/fm", station.streamUrl)
        assertEquals(ArtworkRef.Server("src1", "rs-2").encode(), station.artwork)
    }

    @Test
    fun anAddedStationWithoutAStreamIsLeftOut() {
        assertTrue(homeStations(listOf(RadioStation("rs-3", "Empty", coverArt = "ra-rs-3")), "src1").isEmpty())
    }
}
