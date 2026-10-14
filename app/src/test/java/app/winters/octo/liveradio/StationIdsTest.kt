package app.winters.octo.liveradio

import app.winters.octo.catalog.ArtworkRef
import app.winters.octo.discovery.Station
import app.winters.octo.playback.RadioDetails
import app.winters.octo.playback.radioDetailsOf
import app.winters.octo.playback.radioIsHls
import app.winters.octo.playback.radioOf
import app.winters.octo.subsonic.RadioStationDetails
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

// Every place that plays a station puts what the player shows about it in
// the station's id.
class StationIdsTest {
    private val kiis = LiveStation(
        uuid = "uuid-kiis",
        name = "102.7 KIIS FM",
        streamUrl = "https://stream.revma.ihrhls.com/zc185",
        favicon = "https://cdn.example/kiis.png",
        codec = "AAC",
        bitrate = 128,
        country = "The United States Of America",
        countryCode = "US",
        state = "California",
        tags = listOf("pop", "top 40"),
    )

    @Test
    fun aRadioBrowserStationCarriesEverythingItKnows() {
        val id = kiis.radioId()
        assertEquals("https://stream.revma.ihrhls.com/zc185" to "102.7 KIIS FM", radioOf(id))
        assertEquals(
            RadioDetails(
                logo = "https://cdn.example/kiis.png",
                codec = "AAC",
                bitrate = 128,
                country = "The United States Of America",
                countryCode = "US",
                state = "California",
                tags = listOf("pop", "top 40"),
                uuid = "uuid-kiis",
            ),
            radioDetailsOf(id),
        )
        assertTrue(radioIsHls(kiis.copy(hls = true).radioId()))
    }

    @Test
    fun aServerStationOnTheShelfCarriesItsCoverAndWhatTheKeptCopyKnows() {
        val station = Station("ra-1", "KIIS", ArtworkRef.Server("src", "ra-1").encode(), streamUrl = "https://stream.revma.ihrhls.com/zc185")
        val alone = LiveShelfEntry.Server(station).radioId()
        assertEquals(RadioDetails(coverArt = "ra-1"), radioDetailsOf(alone))
        assertFalse(radioIsHls(alone))
        val withKept = LiveShelfEntry.Server(station, kept = kiis.copy(hls = true)).radioId()
        assertEquals("ra-1", radioDetailsOf(withKept).coverArt)
        assertEquals("https://cdn.example/kiis.png", radioDetailsOf(withKept).logo)
        assertEquals("uuid-kiis", radioDetailsOf(withKept).uuid)
        assertTrue(radioIsHls(withKept))
        assertEquals(kiis.radioId(), LiveShelfEntry.Kept(kiis).radioId())
        assertEquals("https://stream.revma.ihrhls.com/zc185", LiveShelfEntry.Server(station).streamUrl)
    }

    @Test
    fun theShelfPlaysAsALineupInItsOrderFromTheStationTapped() {
        val server = Station("ra-1", "KIIS", ArtworkRef.Server("src", "ra-1").encode(), streamUrl = "https://stream.revma.ihrhls.com/zc185")
        val other = kiis.copy(uuid = "u-2", name = "KROQ", streamUrl = "https://kroq.example/live")
        val shelf = liveShelf(listOf(server), listOf(kiis, other))
        // The kept copy of the server's stream joins the server's card.
        assertEquals(2, shelf.size)
        val (ids, start) = lineupOf(shelf, 1, { it.streamUrl }, { it.radioId() })
        assertEquals(listOf(shelf[0].radioId(), other.radioId()), ids)
        assertEquals(1, start)
        val lineup = liveLineup(ids, start)!!
        assertTrue(lineup.shows)
        assertTrue(lineup.hasPrevious)
        assertFalse(lineup.hasNext)
        // A list with the same stream twice plays it once.
        val (twice, at) = lineupOf(listOf(kiis, other, kiis.copy(uuid = "u-3")), 2, { it.streamUrl }, { it.radioId() })
        assertEquals(listOf(kiis.radioId(), other.radioId()), twice)
        assertEquals(0, at)
    }

    @Test
    fun aStationOnTheRadioStationsScreenCarriesItsHomePageAndCover() {
        val id = RadioStationDetails("ra-2", "KEXP", "https://kexp.example/live", homePageUrl = "https://kexp.org", coverArt = "ra-2").radioId()
        assertEquals("https://kexp.example/live" to "KEXP", radioOf(id))
        assertEquals(RadioDetails(coverArt = "ra-2", homepage = "https://kexp.org"), radioDetailsOf(id))
        assertEquals(RadioDetails(), radioDetailsOf(RadioStationDetails("ra-3", "Bare", "https://x/live").radioId()))
    }
}
