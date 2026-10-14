package app.winters.octo.liveradio

import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

// Real metadata blocks, as stations sent them on 2026-10-13.
class OnAirTest {
    private val kiisSong = "StreamTitle='Ariana Grande - text=\"Petal\" song_spot=\"M\" MediaBaseId=\"3246947\" itunesTrackId=\"0\" " +
        "amgTrackId=\"-1\" amgArtistId=\"0\" TAID=\"0\" TPID=\"421089822\" cartcutId=\"0447960001\" " +
        "amgArtworkURL=\"https://i.iheart.com/v3/catalog/track/421089822?ops=fit(200,200),format(%22jpeg%22)\" " +
        "length=\"00:02:59\" unsID=\"-1\" spotInstanceId=\"-1\"';"
    private val kiisSpot = "StreamTitle='LA's #1 Hit Music Station - text=\"102.7 KIIS FM\" song_spot=\"T\" MediaBaseId=\"0\" " +
        "itunesTrackId=\"0\" amgTrackId=\"0\" amgArtistId=\"0\" TAID=\"0\" TPID=\"0\" cartcutId=\"0\" amgArtworkURL=\"\" " +
        "length=\"00:00:00\" unsID=\"0\" spotInstanceId=\"-1\"';"
    private val kiisLushLife = "StreamTitle='Zara Larsson - text=\"Lush Life\" song_spot=\"M\" MediaBaseId=\"2123647\" itunesTrackId=\"0\" " +
        "amgTrackId=\"-1\" amgArtistId=\"0\" TAID=\"883390\" TPID=\"45849925\" cartcutId=\"0886408001\" " +
        "amgArtworkURL=\"http://image.iheart.com/ihr-ingestion-pipeline-production-sbmg/A10301A00036327915_20190402040656160/45785635.20126.jpg\" " +
        "length=\"00:03:18\" unsID=\"-1\" spotInstanceId=\"-1\"';"

    private fun read(block: String, station: String): OnAir {
        val fields = icyFields(block)
        return onAir(fields["StreamTitle"], icyArtworkField(fields), station)
    }

    @Test
    fun iHeartNamesTheSongItsArtistAndArtwork() {
        val air = read(kiisSong, "102.7 KIIS FM")
        assertEquals("Petal", air.title)
        assertEquals("Ariana Grande", air.artist)
        assertEquals("https://i.iheart.com/v3/catalog/track/421089822?ops=fit(600,600),format(%22jpeg%22)", air.artwork)
        assertEquals(OnAir("Lush Life", "Zara Larsson", "http://image.iheart.com/ihr-ingestion-pipeline-production-sbmg/A10301A00036327915_20190402040656160/45785635.20126.jpg"), read(kiisLushLife, "102.7 KIIS FM"))
    }

    @Test
    fun anIHeartSpotThatIsNotMusicNamesNoSongButGivesTheTagline() {
        val air = read(kiisSpot, "102.7 KIIS FM")
        assertFalse(air.named)
        assertEquals("", air.artwork)
        assertEquals("LA's #1 Hit Music Station", air.tagline)
    }

    @Test
    fun aQuoteInsideAValueStaysInIt() {
        assertEquals("LA's #1 Hit Music Station - text=\"102.7 KIIS FM\"", icyFields("StreamTitle='LA's #1 Hit Music Station - text=\"102.7 KIIS FM\"';")["StreamTitle"])
        assertEquals(OnAir("I DON'T WANNA MISS A THING", "AEROSMITH"), read("StreamTitle='AEROSMITH - I DON'T WANNA MISS A THING';", "538"))
        assertEquals(OnAir("Dick's Boogie", "Riccardo Garzoni"), read("StreamTitle='Riccardo Garzoni - Dick's Boogie';", "Swiss Jazz"))
        // A block cut before its closing quote keeps what it has.
        assertEquals("It's on", icyFields("StreamTitle='It's on")["StreamTitle"])
        assertEquals("Dick's Boogie", icyFields("StreamTitle='Dick's Boogie'")["StreamTitle"])
    }

    @Test
    fun aPlainTitleSplitsAtTheFirstDash() {
        assertEquals(OnAir("Angoon", "Portugal. The Man", "http://img.radioparadise.com/covers/l/24684.jpg"),
            read("StreamTitle='Portugal. The Man - Angoon';StreamUrl='http://img.radioparadise.com/covers/l/24684.jpg';", "Radio Paradise"))
        assertEquals(OnAir("Dance Machine", "Flo The Duchess"), read("StreamTitle='Flo The Duchess - Dance Machine';", "NPO Radio2"))
        assertEquals(OnAir("Jamaican (Bam Bam)", "HUGEL & SOLTO"), read("StreamTitle='HUGEL & SOLTO  - Jamaican (Bam Bam)';", "538 Party"))
        assertEquals(OnAir("We Be Clubbin` (Clean Radio Edit)", "Ice Cube"),
            read("StreamTitle='Ice Cube - We Be Clubbin` (Clean Radio Edit) ';StreamUrl='';StreamArtwork='';", "181.FM Old School"))
        assertEquals(OnAir("Song - Part 2", "Artist"), onAir("Artist - Song - Part 2"))
        assertEquals(OnAir("Welcome To Heartlight", "Kenny Loggins"), read("StreamTitle='Kenny Loggins - Welcome To Heartlight';", "ANTENNE BAYERN"))
    }

    @Test
    fun anImageStreamUrlIsTheArtwork() {
        val soma = read("StreamTitle='Reef Project - True Clown';StreamUrl='https://somafm.com/logos/512/groovesalad512.jpg';", "Groove Salad")
        assertEquals(OnAir("True Clown", "Reef Project", "https://somafm.com/logos/512/groovesalad512.jpg"), soma)
        // A web page is not artwork.
        assertEquals("", read("StreamTitle='A - B';StreamUrl='https://station.example/now';", "X").artwork)
        assertEquals("https://cdn.example/cover.png", read("StreamTitle='A - B';StreamArtwork='https://cdn.example/cover.png';", "X").artwork)
    }

    @Test
    fun aTitleAloneIsATitle() {
        assertEquals(OnAir("Interlude"), onAir("Interlude", station = "Some FM"))
        assertEquals(OnAir("Petal"), onAir("Petal", station = ""))
        assertFalse(onAir("Advertisement").named)
    }

    @Test
    fun nothingIsNamedByEmptyPunctuationTheStationAdsOrCartCodes() {
        assertFalse(onAir("").named)
        assertFalse(onAir("   ").named)
        assertFalse(onAir(null).named)
        assertFalse(onAir(" - ").named)
        assertFalse(onAir("NPO Radio2", station = "NPO Radio2").named)
        assertFalse(onAir("npo radio 2", station = "NPO Radio 2").named)
        // KROQ between songs.
        assertFalse(read("StreamTitle='- Advertisement';", "KROQ").named)
        // 181.FM's playout cart number.
        assertFalse(read("StreamTitle='GWMR0446000';StreamUrl='';StreamArtwork='';", "181.FM").named)
        // A song whose name is in capitals is still a song.
        assertTrue(onAir("ABBA - SOS").named)
        assertTrue(onAir("U2").named)
    }

    @Test
    fun iHeartTitleAndArtistKeys() {
        val air = onAir("title=\"Blinding Lights\" artist=\"The Weeknd\" url=\"x\"", station = "Some FM")
        assertEquals(OnAir("Blinding Lights", "The Weeknd"), air)
        // A text that is only the station's name is no song.
        assertFalse(onAir("text=\"102.7 KIIS FM\" song_spot=\"M\"", station = "102.7 KIIS FM").named)
    }

    @Test
    fun fieldsReadEveryKeyOnce() {
        val fields = icyFields("StreamTitle='A - B';StreamUrl='';StreamArtwork='';\u0000\u0000")
        assertEquals(mapOf("StreamTitle" to "A - B", "StreamUrl" to "", "StreamArtwork" to ""), fields)
        assertEquals(emptyMap<String, String>(), icyFields(""))
        assertEquals(null, icyArtworkField(fields))
    }

    @Test
    fun iHeartArtworkIsAskedForAtThePlayersSize() {
        assertEquals("https://i.iheart.com/v3/catalog/track/1?ops=fit(600,600),format(%22jpeg%22)", sharperArtwork("https://i.iheart.com/v3/catalog/track/1?ops=fit(200,200),format(%22jpeg%22)"))
        assertEquals("https://i.iheart.com/x?ops=fit(1000,1000)", sharperArtwork("https://i.iheart.com/x?ops=fit(1000,1000)"))
        assertEquals("https://cdn.example/fit(200,200).jpg", sharperArtwork("https://cdn.example/fit(200,200).jpg"))
        assertEquals("http://image.iheart.com/a/b.jpg", sharperArtwork("http://image.iheart.com/a/b.jpg"))
    }
}
