package app.winters.octo.liveradio

import app.winters.octo.playback.RadioDetails
import app.winters.octo.playback.radioDetailsOf
import app.winters.octo.playback.radioId
import app.winters.octo.playback.radioIsHls
import app.winters.octo.playback.radioOf
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

class LivePlayerTest {
    private val kiis = LiveStation(
        uuid = "u-kiis",
        name = "102.7 KIIS FM",
        streamUrl = "https://stream.revma.ihrhls.com/zc185",
        favicon = "https://i.iheart.com/v3/re/assets.brands/2ebe?ops=new(),fit(100,100)",
        codec = "AAC",
        bitrate = 128,
        country = "The United States Of America",
        countryCode = "US",
        state = "California",
        tags = listOf("pop", "top 40"),
        homepage = "https://kiisfm.iheart.com/",
    )

    @Test
    fun aStationsDetailsRideInItsId() {
        val id = kiis.radioId()
        assertEquals(kiis.streamUrl to kiis.name, radioOf(id))
        assertFalse(radioIsHls(id))
        val details = radioDetailsOf(id)
        assertEquals(kiis.favicon, details.logo)
        assertEquals("AAC", details.codec)
        assertEquals(128, details.bitrate)
        assertEquals("California", details.state)
        assertEquals(listOf("pop", "top 40"), details.tags)
        assertEquals("u-kiis", details.uuid)
        assertEquals("https://kiisfm.iheart.com/", details.homepage)
        val hls = kiis.copy(hls = true).radioId()
        assertTrue(radioIsHls(hls))
        assertEquals(kiis.favicon, radioDetailsOf(hls).logo)
    }

    @Test
    fun oldIdsReadWithNoDetails() {
        assertEquals(RadioDetails(), radioDetailsOf(radioId("http://host/live", "Name")))
        assertEquals(RadioDetails(), radioDetailsOf(radioId("http://host/live", "Name", hls = true)))
        assertEquals(RadioDetails(), radioDetailsOf("find:abc"))
        // No details makes the id it always was.
        assertEquals(radioId("http://host/live", "Name"), radioId("http://host/live", "Name", details = RadioDetails()))
    }

    @Test
    fun detailsWithEveryOddCharacterRoundTrip() {
        val details = RadioDetails(logo = "https://x/a.png?a=1&b=2:3", homepage = "https://x/?q=a&b", tags = listOf("r&b", "hip-hop"))
        assertEquals(details, radioDetailsOf(radioId("http://h/s", "A: B & C", details = details)))
        assertEquals("http://h/s" to "A: B & C", radioOf(radioId("http://h/s", "A: B & C", details = details)))
    }

    @Test
    fun theLineupStepsThroughTheListAndStopsAtTheEnds() {
        val ids = listOf("radio:a:A", "radio:b:B", "radio:c:C")
        val first = liveLineup(ids, 0)!!
        assertTrue(first.shows)
        assertFalse(first.hasPrevious)
        assertNull(first.previous)
        assertEquals(1, first.next)
        val last = liveLineup(ids, 2)!!
        assertEquals(1, last.previous)
        assertFalse(last.hasNext)
        assertNull(last.next)
        val middle = liveLineup(ids, 1)!!
        assertEquals(0, middle.previous)
        assertEquals(2, middle.next)
    }

    @Test
    fun aStationAloneHasNoBackOrNext() {
        val one = liveLineup(listOf("radio:a:A"), 0)!!
        assertFalse(one.shows)
        assertNull(one.next)
        assertNull(one.previous)
        // A station among songs stands alone.
        val mixed = liveLineup(listOf("song1", "radio:a:A", "song2"), 1)!!
        assertFalse(mixed.shows)
        assertNull(liveLineup(listOf("song1"), 0))
        assertNull(liveLineup(emptyList(), 0))
    }

    @Test
    fun aListBecomesALineupWithEachStreamOnce() {
        val stations = listOf(kiis, kiis.copy(uuid = "dupe", streamUrl = "http://stream.revma.ihrhls.com/zc185/"), kiis.copy(uuid = "b", streamUrl = "https://b/live"))
        val (ids, index) = lineupOf(stations, 2, LiveStation::streamUrl) { it.radioId() }
        assertEquals(2, ids.size)
        assertEquals(1, index)
        assertEquals(0, lineupOf(stations, 1, LiveStation::streamUrl) { it.radioId() }.second)
    }

    @Test
    fun theLinesUnderTheTitle() {
        val details = kiis.radioDetails()
        assertEquals("Ariana Grande · 102.7 KIIS FM", liveSubtitle(OnAir("Petal", "Ariana Grande"), "102.7 KIIS FM", details))
        assertEquals("Petal · 102.7 KIIS FM".substringAfter(" · "), liveSubtitle(OnAir("Petal"), "102.7 KIIS FM", details))
        assertEquals("LA's #1 Hit Music Station", liveSubtitle(OnAir(tagline = "LA's #1 Hit Music Station"), "102.7 KIIS FM", details))
        assertEquals("California, The United States Of America · Pop", liveSubtitle(OnAir.Nothing, "102.7 KIIS FM", details))
        assertEquals(LIVE_RADIO_LINE, liveSubtitle(OnAir.Nothing, "X", RadioDetails()))
        assertEquals("Petal", liveTitle(OnAir("Petal", "Ariana Grande"), "102.7 KIIS FM", "u"))
        assertEquals("102.7 KIIS FM", liveTitle(OnAir.Nothing, "102.7 KIIS FM", "u"))
        assertEquals("http://h/s", liveTitle(OnAir.Nothing, "", "http://h/s"))
    }

    @Test
    fun whatTheLivePlayerShows() {
        val shown = liveShown(kiis.radioId(), "Ariana Grande - text=\"Petal\" song_spot=\"M\" amgArtworkURL=\"https://i.iheart.com/v3/catalog/track/421089822\"")!!
        assertEquals("Petal", shown.title)
        assertEquals("Ariana Grande · 102.7 KIIS FM", shown.subtitle)
        assertEquals("https://i.iheart.com/v3/catalog/track/421089822", shown.cover)
        val between = liveShown(kiis.radioId(), "LA's #1 Hit Music Station - text=\"102.7 KIIS FM\" song_spot=\"T\" amgArtworkURL=\"\"")!!
        assertEquals("102.7 KIIS FM", between.title)
        assertEquals("LA's #1 Hit Music Station", between.subtitle)
        assertEquals(kiis.favicon, between.cover)
        assertEquals("", liveShown(radioId("http://h/s", "Plain"), null)!!.cover)
        assertNull(liveShown("song-1", "A - B"))
    }

    @Test
    fun theCodecPill() {
        assertEquals("AAC 128 kbps", liveCodecLine(RadioDetails(codec = "aac", bitrate = 128)))
        assertEquals("MP3", liveCodecLine(RadioDetails(codec = "MP3")))
        assertEquals("", liveCodecLine(RadioDetails(codec = "UNKNOWN")))
        assertEquals("64 kbps", liveCodecLine(RadioDetails(bitrate = 64)))
    }

    @Test
    fun howLongTheListenerHasBeenOn() {
        assertEquals("0:00", listenedFor(0))
        assertEquals("0:42", listenedFor(42_900))
        assertEquals("12:04", listenedFor((12 * 60 + 4) * 1_000L))
        assertEquals("1:02:03", listenedFor((3_600 + 2 * 60 + 3) * 1_000L))
        assertEquals("0:00", listenedFor(-5))
    }

    private fun lib(id: String, title: String, artist: String) = HeartCandidate(id, title, artist, inLibrary = true)
    private fun outside(id: String, title: String, artist: String) = HeartCandidate(id, title, artist, inLibrary = false)

    @Test
    fun theHeartFindsTheSongOnAir() {
        val petal = OnAir("Petal", "Ariana Grande")
        assertEquals("1", heartMatch(petal, listOf(lib("1", "Petal", "Ariana Grande")))?.id)
        assertEquals("1", heartMatch(petal, listOf(lib("1", "petal", "ARIANA GRANDE")))?.id)
        assertEquals("Ariana Grande Petal", heartQuery(petal))
        // A library song wins over the same song from outside.
        assertEquals("lib", heartMatch(petal, listOf(outside("out", "Petal", "Ariana Grande"), lib("lib", "Petal", "Ariana Grande")))?.id)
        // Only outside: that one.
        assertEquals("out", heartMatch(petal, listOf(outside("out", "Petal", "Ariana Grande")))?.id)
    }

    @Test
    fun featuredArtistsAndPunctuationDoNotStopAMatch() {
        val onAir = OnAir("Take Me Back", "KYGO & MAX MCNOWN")
        assertEquals("k", heartMatch(onAir, listOf(lib("k", "Take Me Back", "Kygo & Max McNown")))?.id)
        val feat = OnAir("Die With A Smile (feat. Bruno Mars)", "Lady Gaga")
        assertEquals("g", heartMatch(feat, listOf(lib("g", "Die With A Smile", "Lady Gaga, Bruno Mars")))?.id)
        val tail = OnAir("Lush Life", "Zara Larsson feat. Nobody")
        assertEquals("z", heartMatch(tail, listOf(lib("z", "Lush Life", "Zara Larsson")))?.id)
        assertEquals("w", heartMatch(OnAir("We Be Clubbin'", "Ice Cube"), listOf(lib("w", "We Be Clubbin", "Ice Cube")))?.id)
        assertEquals("p", heartMatch(OnAir("Angoon", "Portugal. The Man"), listOf(lib("p", "Angoon", "Portugal The Man")))?.id)
    }

    @Test
    fun nearMissesNeverMatch() {
        val petal = OnAir("Petal", "Ariana Grande")
        assertNull(heartMatch(petal, listOf(lib("r", "Petal (Remix)", "Ariana Grande"))))
        assertNull(heartMatch(petal, listOf(lib("l", "Petal (Live)", "Ariana Grande"))))
        assertNull(heartMatch(petal, listOf(lib("o", "Petal", "Ariana Greenblatt"))))
        assertNull(heartMatch(petal, listOf(lib("t", "Petals", "Ariana Grande"))))
        assertNull(heartMatch(petal, listOf(lib("x", "Positions", "Ariana Grande"))))
        assertNull(heartMatch(OnAir("Lush Life", "Zara Larsson"), listOf(lib("c", "Lush Life", "Some Cover Band"))))
        // No artist named: a title alone is never enough.
        assertNull(heartMatch(OnAir("Petal"), listOf(lib("1", "Petal", "Ariana Grande"))))
        assertNull(heartMatch(OnAir.Nothing, listOf(lib("1", "Petal", "Ariana Grande"))))
        assertNull(heartMatch(petal, emptyList()))
    }
}
