package app.winters.octo.liveradio

import app.winters.octo.discovery.Station
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

class LiveRadioRulesTest {
    private fun station(
        uuid: String,
        stream: String = "https://stream.example/$uuid",
        codec: String = "MP3",
        hls: Boolean = false,
        distance: Double? = null,
        state: String = "",
        country: String = "",
    ) = LiveStation(uuid = uuid, name = "Station $uuid", streamUrl = stream, codec = codec, hls = hls, distanceMeters = distance, state = state, country = country)

    private val allDecoders = setOf("audio/mpeg", "audio/mp4a-latm", "audio/vorbis", "audio/opus", "audio/flac")

    @Test
    fun milesInTheUsTheUkLiberiaAndMyanmarOnly() {
        listOf("US", "GB", "LR", "MM", "us", " gb ").forEach { assertTrue(it, usesMiles(it)) }
        listOf("CA", "DE", "IE", "AU", "", "IN").forEach { assertFalse(it, usesMiles(it)) }
    }

    @Test
    fun radiusChoicesFollowTheUnits() {
        assertEquals(LiveRadiusMiles, radiusChoices(miles = true))
        assertEquals(LiveRadiusKm, radiusChoices(miles = false))
        // The usual choice is the second one: 25 miles or 40 km.
        assertEquals(25, radiusAt(true, LIVE_RADIUS_DEFAULT_INDEX))
        assertEquals(40, radiusAt(false, LIVE_RADIUS_DEFAULT_INDEX))
        assertEquals(25 * MILE_METERS, radiusMeters(true, LIVE_RADIUS_DEFAULT_INDEX), 0.001)
        assertEquals(40_000.0, radiusMeters(false, LIVE_RADIUS_DEFAULT_INDEX), 0.001)
    }

    @Test
    fun aRadiusOutOfRangeIsKeptInIt() {
        assertEquals(10, radiusAt(true, -3))
        assertEquals(160, radiusAt(false, 99))
    }

    @Test
    fun radiusWordsUseTheUnits() {
        assertEquals("25 mi", radiusLabel(true, 25))
        assertEquals("40 km", radiusLabel(false, 40))
        assertEquals("No stations within 25 miles. Try a wider circle.", noStationsLine(true, 25))
        assertEquals("No stations within 40 km. Try a wider circle.", noStationsLine(false, 40))
    }

    @Test
    fun distancesReadInTheListenersUnits() {
        assertEquals("3.2 mi", whereLine(station("a", distance = 3.2 * MILE_METERS), miles = true))
        assertEquals("12 km", whereLine(station("a", distance = 12_300.0), miles = false))
        assertEquals("Right here", whereLine(station("a", distance = 20.0), miles = false))
    }

    @Test
    fun aStationWithNoPlaceSaysWhereItIsFiled() {
        assertEquals("In Texas", whereLine(station("a", state = "Texas", country = "United States"), miles = true))
        assertEquals("In Germany", whereLine(station("a", country = "Germany"), miles = false))
        assertEquals("", whereLine(station("a"), miles = false))
    }

    @Test
    fun theStreamLineSaysKindAndSize() {
        assertEquals("MP3 128 kbps", streamLine(station("a", codec = "mp3").copy(bitrate = 128)))
        assertEquals("AAC+", streamLine(station("a", codec = "AAC+")))
        assertEquals("", streamLine(station("a", codec = "UNKNOWN")))
    }

    @Test
    fun theDetailLineJoinsWhereAndTags() {
        val s = station("a", state = "Ohio").copy(tags = listOf("jazz", "blues", "news", "talk"))
        assertEquals("In Ohio · jazz, blues, news", detailLine(s, miles = true))
        assertEquals("jazz", detailLine(station("b").copy(tags = listOf("jazz")), miles = true))
    }

    @Test
    fun onlyKindsThePlayerOpensArePlayable() {
        listOf("MP3", "AAC", "AAC+", "OGG", "OPUS", "FLAC", "mp3", " aac ").forEach {
            assertTrue(it, livePlayable(station("a", codec = it), allDecoders))
        }
        listOf("WMA", "MP3,H.264", "AAC+,H.264", "FLV").forEach {
            assertFalse(it, livePlayable(station("a", codec = it), allDecoders))
        }
    }

    @Test
    fun aKindIsHiddenWhenThePhoneHasNoDecoderForIt() {
        assertFalse(livePlayable(station("a", codec = "FLAC"), allDecoders - "audio/flac"))
        assertTrue(livePlayable(station("a", codec = "MP3"), allDecoders - "audio/flac"))
    }

    @Test
    fun hlsStreamsAndUnnamedKindsAreTried() {
        assertTrue(livePlayable(station("a", codec = "AAC,H.264", hls = true), emptySet()))
        assertTrue(livePlayable(station("a", codec = ""), allDecoders))
        assertTrue(livePlayable(station("a", codec = "UNKNOWN"), allDecoders))
    }

    @Test
    fun theMenuKeepsOrRemovesAndAdminsCanAddToTheServer() {
        assertEquals(listOf(StationAction.Keep), stationActions(kept = false, addable = false))
        assertEquals(listOf(StationAction.Remove), stationActions(kept = true, addable = false))
        assertEquals(listOf(StationAction.Keep, StationAction.AddToServer), stationActions(kept = false, addable = true))
        assertEquals(listOf(StationAction.Remove, StationAction.AddToServer), stationActions(kept = true, addable = true))
        assertEquals("Add to your server", StationAction.AddToServer.label)
    }

    @Test
    fun theShelfShowsTheServersStationsThenTheKeptOnesEachStreamOnce() {
        val server = listOf(
            Station("s1", "Server One", null, streamUrl = "https://Stream.Example/one/"),
            Station("s2", "Server Two", null, streamUrl = "http://stream.example/two"),
            // Octo's own station has no stream, so it is not on this shelf.
            Station("octo", "Octo station", null),
        )
        val kept = listOf(
            station("k1", stream = "http://stream.example/one"),
            station("k2", stream = "https://stream.example/three"),
            station("k3", stream = "https://stream.example/three/"),
        )
        val shelf = liveShelf(server, kept)
        assertEquals(listOf("server:s1", "server:s2", "kept:k2"), shelf.map { it.key })
    }

    @Test
    fun aServerStationThatIsAlsoKeptCarriesItsHlsMark() {
        val server = listOf(Station("s1", "FIP", null, streamUrl = "https://fip.example/live"))
        val kept = listOf(station("k1", stream = "http://FIP.example/live/", hls = true))
        val entry = liveShelf(server, kept).single() as LiveShelfEntry.Server
        assertTrue(entry.hls)
        assertEquals("k1", entry.kept?.uuid)
        assertFalse((liveShelf(server, emptyList()).single() as LiveShelfEntry.Server).hls)
    }

    @Test
    fun anEmptyShelfStaysEmpty() {
        assertTrue(liveShelf(emptyList(), emptyList()).isEmpty())
    }

    @Test
    fun aRestoredBackupAddsWhatIsNotKeptYet() {
        val now = KeptStations().keep(station("a")).keep(station("b"))
        val restored = restoredKept(now, listOf(station("b"), station("c", distance = 5.0), station("c")))
        assertEquals(listOf("b", "a", "c"), restored.stations.map { it.uuid })
        assertNull(restored.stations.last().distanceMeters)
    }

    @Test
    fun aPlaceIsNamedByTownAndState() {
        assertEquals("Portland, Oregon", placeLabel("Portland", "Oregon", "Your location"))
        assertEquals("Oregon", placeLabel(null, "Oregon", "Your location"))
        assertEquals("Monaco", placeLabel("Monaco", "Monaco", "x"))
        assertEquals("Your location", placeLabel(" ", null, "Your location"))
    }

    @Test
    fun theFootnoteCountsHiddenStations() {
        assertNull(hiddenLine(0))
        assertEquals("1 station is left out because this phone cannot play its stream.", hiddenLine(1))
        assertEquals("4 stations are left out because this phone cannot play their streams.", hiddenLine(4))
    }

    @Test
    fun noDashesInTheWords() {
        val words = listOf(
            noStationsLine(true, 10), hiddenLine(2)!!, StationAction.AddToServer.label,
            detailLine(station("a", state = "Ohio").copy(tags = listOf("x")), true),
        )
        words.forEach { assertFalse(it, it.contains(EM_DASH) || it.contains(EN_DASH)) }
    }
}

// The two dashes the app never writes, by their code points.
private const val EM_DASH = '\u2014'
private const val EN_DASH = '\u2013'
