package app.winters.octo.playback

import androidx.media3.common.Metadata
import androidx.media3.extractor.metadata.icy.IcyInfo
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

// A station as the phone's player shows and opens it: the song its stream
// names, which loader opens it, and how it is opened again after a drop.
class RadioItemsTest {
    // Blocks KIIS FM 102.7 sent on 2026-10-13, as the player hands them over.
    private val kiisSong = "StreamTitle='Ariana Grande - text=\"Petal\" song_spot=\"M\" MediaBaseId=\"3246947\" itunesTrackId=\"0\" " +
        "amgTrackId=\"-1\" amgArtistId=\"0\" TAID=\"0\" TPID=\"421089822\" cartcutId=\"0447960001\" " +
        "amgArtworkURL=\"https://i.iheart.com/v3/catalog/track/421089822?ops=fit(200,200),format(%22jpeg%22)\" " +
        "length=\"00:02:59\" unsID=\"-1\" spotInstanceId=\"-1\"';"
    private val kiisSpot = "StreamTitle='LA's #1 Hit Music Station - text=\"102.7 KIIS FM\" song_spot=\"T\" MediaBaseId=\"0\" " +
        "itunesTrackId=\"0\" amgTrackId=\"0\" amgArtistId=\"0\" TAID=\"0\" TPID=\"0\" cartcutId=\"0\" amgArtworkURL=\"\" " +
        "length=\"00:00:00\" unsID=\"0\" spotInstanceId=\"-1\"';"
    private val kiis = radioId(
        "https://stream.revma.ihrhls.com/zc185",
        "102.7 KIIS FM",
        details = RadioDetails(logo = "https://cdn.example/kiis.png", country = "The United States Of America", state = "California", tags = listOf("pop")),
    )

    // What the player's ICY reader makes of a block: its own title cut at
    // the first "';" it sees, the raw bytes alongside.
    private fun icy(block: String): Metadata =
        Metadata(IcyInfo(block.toByteArray(Charsets.UTF_8), block.substringAfter("StreamTitle='").substringBefore("';"), null))

    @Test
    fun theKiisSongShowsItsTitleArtistAndArtwork() {
        val read = icyReadOf(icy(kiisSong))!!
        val lines = liveLines(kiis, read)!!
        assertEquals("Petal", lines.title)
        assertEquals("Ariana Grande · 102.7 KIIS FM", lines.subtitle)
        assertEquals("Ariana Grande", lines.shown.onAir.artist)
        val art = stationArtOf(lines.artwork)!!
        assertEquals("https://i.iheart.com/v3/catalog/track/421089822?ops=fit(600,600),format(%22jpeg%22)", art.artwork)
        // The station's logo stays under it.
        assertEquals(listOf("https://cdn.example/kiis.png"), art.logos)
        assertEquals("102.7 KIIS FM", art.name)
    }

    @Test
    fun octosCoverForTheSongGoesOnTopAndOnlyWhileASongIsNamed() {
        val song = stationArtOf(liveLines(kiis, icyReadOf(icy(kiisSong)), octoCover = "online:src|al-1")!!.artwork)!!
        assertEquals("online:src|al-1", song.cover)
        assertEquals("online:src|al-1", song.pictures.first())
        val spot = stationArtOf(liveLines(kiis, icyReadOf(icy(kiisSpot)), octoCover = "online:src|al-1")!!.artwork)!!
        assertEquals("", spot.cover)
        assertEquals(listOf("https://cdn.example/kiis.png"), spot.pictures)
    }

    @Test
    fun theKiisSpotShowsTheStationWithItsTagline() {
        val lines = liveLines(kiis, icyReadOf(icy(kiisSpot)))!!
        assertEquals("102.7 KIIS FM", lines.title)
        assertEquals("LA's #1 Hit Music Station", lines.subtitle)
        assertEquals("", stationArtOf(lines.artwork)!!.artwork)
    }

    @Test
    fun withNothingNamedTheStationShowsWhereItIs() {
        val lines = liveLines(kiis, null)!!
        assertEquals("102.7 KIIS FM", lines.title)
        assertEquals("California, The United States Of America · Pop", lines.subtitle)
        // A station with nothing known about it says it is live radio, and
        // one with no name shows its address.
        assertEquals("Live radio", liveLines(radioId("http://host/live", "KEXP"), IcyRead("KEXP", null))!!.subtitle)
        assertEquals("http://host/live", liveLines(radioId("http://host/live", ""), null)!!.title)
        assertNull(liveLines("device:12", null))
    }

    @Test
    fun aPlainTitleSplitsIntoSongAndArtist() {
        val lines = liveLines(radioId("http://s/live.mp3", "KEXP"), icyReadOf(icy("StreamTitle='Nina Simone - Feeling Good';")))!!
        assertEquals("Feeling Good", lines.title)
        assertEquals("Nina Simone · KEXP", lines.subtitle)
    }

    @Test
    fun aVeryLongTitleIsCut() {
        assertEquals(200, liveLines(radioId("http://s/live.mp3", "KEXP"), IcyRead("x".repeat(500), null))!!.title.length)
    }

    @Test
    fun theBlockIsReadFromItsRawBytesWithTheTitleAsFallback() {
        // Quotes inside a value stay in it, which the player's own title loses.
        assertEquals(IcyRead("Riccardo Garzoni - Dick's Boogie", null), icyReadOf(icy("StreamTitle='Riccardo Garzoni - Dick's Boogie';")))
        assertEquals(
            IcyRead("Portugal. The Man - Angoon", "http://img.radioparadise.com/covers/l/24684.jpg"),
            icyReadOf("StreamTitle='Portugal. The Man - Angoon';StreamUrl='http://img.radioparadise.com/covers/l/24684.jpg';".toByteArray(), "x", null),
        )
        // Latin-1 bytes still read.
        assertEquals("Khruangbin - Maria También", icyReadOf("StreamTitle='Khruangbin - Maria También';".toByteArray(Charsets.ISO_8859_1), null, null).streamTitle)
        // No raw block: the player's title and address.
        assertEquals(IcyRead("Khruangbin - Maria También", null), icyReadOf(Metadata(IcyInfo(byteArrayOf(), "Khruangbin - Maria También", null))))
        assertEquals(IcyRead(null, "https://x"), icyReadOf(Metadata(IcyInfo(byteArrayOf(), null, "https://x"))))
        assertNull(icyReadOf(Metadata()))
    }

    @Test
    fun aStationsCoverCarriesItsPicturesInOrder() {
        val art = StationArt("A|B FM", "key", "https://art/1.jpg?a=b|c", listOf("https://logo/2.png", "server:src|cover-1"), cover = "online:src|al-9")
        assertEquals(art, stationArtOf(art.encode()))
        // Octo's cover for the song first, then the station's artwork, then its logos.
        assertEquals(listOf("online:src|al-9", "https://art/1.jpg?a=b|c", "https://logo/2.png", "server:src|cover-1"), art.pictures)
        assertEquals(listOf("https://logo/2.png"), StationArt("A", "k", logos = listOf("https://logo/2.png")).pictures)
        assertNull(stationArtOf("server:src|cover"))
        assertNull(stationArtOf(null))
        // A server cover id in the details becomes a cover on the server in use.
        val id = radioId("http://s/live", "One", details = RadioDetails(logo = "https://logo", coverArt = "ra-1"))
        assertEquals(listOf("https://logo", "server:src-1|ra-1"), stationArt(id, sourceId = "src-1")!!.logos)
        assertEquals(listOf("https://logo"), stationArt(id)!!.logos)
        // A station with no pictures has only its drawn cover.
        assertEquals(emptyList<String>(), stationArt(radioId("http://s/live", "Two"))!!.logos)
        assertEquals("Live radio", stationArt(radioId("http://s/live", "Two"))!!.drawnSpec().line)
        assertTrue(isWebPicture("HTTPS://x"))
        assertFalse(isWebPicture("server:a|b"))
    }

    @Test
    fun aStationRetriesWithGrowingWaitsThenGivesUp() {
        assertEquals(listOf(1_000L, 2_000L, 4_000L, 8_000L), (1..RADIO_RETRIES).map { radioRetryDelayMs(it, lasting = false) })
        assertEquals(androidx.media3.common.C.TIME_UNSET, radioRetryDelayMs(RADIO_RETRIES + 1, lasting = false))
        assertEquals(androidx.media3.common.C.TIME_UNSET, radioRetryDelayMs(1, lasting = true))
    }

    @Test
    fun aDroppedConnectionIsWorthTryingAgainAndABadStreamIsNot() {
        assertFalse(lastingRadioError(java.io.IOException("connection reset")))
        assertFalse(lastingRadioError(java.net.SocketTimeoutException()))
        assertTrue(lastingRadioError(java.io.FileNotFoundException()))
        assertTrue(lastingRadioError(androidx.media3.common.ParserException.createForMalformedContainer("not audio", null)))
    }

    @Test
    fun aStreamThatEndsIsOpenedAgainAFewTimesAWhile() {
        var clock = 0L
        val ends = RadioEnds(windowMs = 120_000, now = { clock })
        repeat(RADIO_RETRIES) {
            assertTrue(ends.ended("http://s/a"))
            clock += 10_000
        }
        assertEquals(RADIO_RETRIES, ends.recent("http://s/a"))
        // Once more in the same while: it is let end, and the queue moves on.
        assertFalse(ends.ended("http://s/a"))
        assertEquals(0, ends.recent("http://s/a"))
        // Another station keeps its own count.
        assertTrue(ends.ended("http://s/b"))
        // Ends older than the window are forgotten.
        clock += 200_000
        assertEquals(0, ends.recent("http://s/b"))
    }

    @Test
    fun aStationGoesToTheLoaderForItsKind() {
        assertEquals(RadioLoader.None, radioLoader("device:12"))
        assertEquals(RadioLoader.Stream, radioLoader(radioId("http://s/live.mp3", "One")))
        assertEquals(RadioLoader.Hls, radioLoader(radioId("http://s/live", "Two", hls = true)))
        assertEquals(RadioLoader.Hls, radioLoader(radioId("https://s/master.M3U8?token=1", "Three")))
    }

    @Test
    fun newWordsForTheSameItemsLeaveABlendAlone() {
        val items = listOf("radio:a:b" to "q:1")
        assertTrue(wordsOnly(items, listOf("radio:a:b" to "q:1")))
        assertFalse(wordsOnly(items, listOf("radio:c:d" to "q:1")))
        assertFalse(wordsOnly(items, listOf("radio:a:b" to null)))
        assertFalse(wordsOnly(emptyList(), emptyList()))
    }
}
