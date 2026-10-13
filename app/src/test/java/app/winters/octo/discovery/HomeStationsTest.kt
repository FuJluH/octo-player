package app.winters.octo.discovery

import app.winters.octo.catalog.ArtworkRef
import app.winters.octo.subsonic.RadioStation
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Test

class HomeStationsTest {
    // Octo's own stations play their songs; a station added to the server
    // keeps its stream and its cover.
    @Test
    fun anAddedStationPlaysItsStream() {
        val radio = listOf(
            RadioStation("lastfm-mix", "Your Mix", "https://octo/radio/stream/abc", coverArt = "lastfm-mix"),
            RadioStation("rs-1", "City Radio", "https://radio.example.com/live.mp3"),
        )
        val stations = homeStations(radio, "src1")
        assertNull("Octo's own station plays its songs", stations[0].streamUrl)
        assertEquals("https://radio.example.com/live.mp3", stations[1].streamUrl)
        assertEquals(ArtworkRef.Server("src1", "rs-1").encode(), stations[1].artwork)
    }

    @Test
    fun aStationWithoutAStreamHasNone() {
        assertNull(homeStations(listOf(RadioStation("rs-2", "Empty")), "src1").single().streamUrl)
    }
}
