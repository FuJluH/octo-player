package app.winters.octo.player

import app.winters.octo.liveradio.HeartCandidate
import app.winters.octo.liveradio.LiveLineup
import app.winters.octo.liveradio.OnAir
import app.winters.octo.liveradio.liveShown
import app.winters.octo.playback.LiveNow
import app.winters.octo.playback.RadioDetails
import app.winters.octo.playback.radioId
import kotlinx.coroutines.test.runTest
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

// The live heart hearts the song on air and nothing else, and the station's
// menu and info say what can be done and what is known.
class LiveHeartTest {
    private val petal = OnAir("Petal", "Ariana Grande", "https://art")
    private val library = HeartCandidate("t-1", "Petal", "Ariana Grande", inLibrary = true)
    private val outsideCopy = HeartCandidate("find:9", "Petal", "Ariana Grande", inLibrary = false)
    private val remix = HeartCandidate("find:2", "Petal (Remix)", "Ariana Grande", inLibrary = false)
    private val other = HeartCandidate("t-3", "Petal", "Someone Else", inLibrary = true)

    private class Fake(var found: List<HeartCandidate>) {
        val asked = mutableListOf<String>()
        val starred = mutableListOf<HeartCandidate>()
        val unstarred = mutableListOf<HeartCandidate>()
        val heart = LiveHeart(
            find = { query, _ -> asked += query; found },
            star = { starred += it; true },
            unstar = { unstarred += it; true },
        )
    }

    @Test
    fun aSureMatchIsStarredTheLibrarysFirst() = runTest {
        val fake = Fake(listOf(other, remix, outsideCopy, library))
        fake.heart.onAir(petal)
        assertTrue(fake.heart.state.value.shown)
        assertEquals(HeartOutcome.Starred(library), fake.heart.tap())
        assertEquals(listOf("Ariana Grande Petal"), fake.asked)
        assertEquals(listOf(library), fake.starred)
        assertEquals(library, fake.heart.state.value.starred)
        assertFalse(fake.heart.state.value.working)
        // Outside the library, the outside copy is starred, which Octo downloads.
        val outside = Fake(listOf(remix, outsideCopy))
        outside.heart.onAir(petal)
        assertEquals(HeartOutcome.Starred(outsideCopy), outside.heart.tap())
    }

    @Test
    fun noSureMatchStarsNothingAndOffersTheSearch() = runTest {
        val fake = Fake(listOf(remix, other))
        fake.heart.onAir(petal)
        assertEquals(HeartOutcome.NoMatch("Ariana Grande Petal"), fake.heart.tap())
        assertTrue(fake.starred.isEmpty())
        assertNull(fake.heart.state.value.starred)
    }

    @Test
    fun aNewSongOnAirResetsTheHeartAndNothingNamedHidesIt() = runTest {
        val fake = Fake(listOf(library))
        fake.heart.onAir(petal)
        fake.heart.tap()
        assertEquals(library, fake.heart.state.value.starred)
        // The same song heard again keeps it.
        fake.heart.onAir(petal.copy(artwork = "https://other"))
        assertEquals(library, fake.heart.state.value.starred)
        fake.heart.onAir(OnAir("Lush Life", "Zara Larsson"))
        assertNull(fake.heart.state.value.starred)
        fake.heart.onAir(OnAir(tagline = "LA's #1 Hit Music Station"))
        assertFalse(fake.heart.state.value.shown)
        assertEquals(HeartOutcome.Ignored, fake.heart.tap())
    }

    @Test
    fun aSecondTapTakesTheLibrarysStarOff() = runTest {
        val fake = Fake(listOf(library))
        fake.heart.onAir(petal)
        fake.heart.tap()
        assertEquals(HeartOutcome.Unstarred, fake.heart.tap())
        assertEquals(listOf(library), fake.unstarred)
        assertNull(fake.heart.state.value.starred)
    }

    @Test
    fun theHeartIsNamedForTheSong() {
        assertEquals("Heart Petal by Ariana Grande", liveHeartLabel(petal))
        assertEquals("Heart Interlude", liveHeartLabel(OnAir("Interlude")))
        assertEquals("Ariana Grande - Petal", copiedSongName(petal))
    }

    @Test
    fun theStationMenuOffersWhatCanBeDone() {
        assertEquals(
            listOf(LiveAction.Info, LiveAction.Keep, LiveAction.AddToServer, LiveAction.FindSong, LiveAction.CopySong),
            liveActions(named = true, keepable = true, kept = false, addable = true),
        )
        assertEquals(listOf(LiveAction.Info, LiveAction.Remove), liveActions(named = false, keepable = true, kept = true, addable = false))
        // A server's station has no Radio Browser id to keep it by.
        assertEquals(listOf(LiveAction.Info), liveActions(named = false, keepable = false, kept = false, addable = false))
    }

    @Test
    fun stationInfoSaysWhatIsKnownOnALineEach() {
        val id = radioId(
            "https://stream.revma.ihrhls.com/zc185",
            "102.7 KIIS FM",
            details = RadioDetails(codec = "AAC", bitrate = 128, country = "The United States Of America", state = "California", tags = listOf("pop", "top 40"), homepage = "https://www.kiisfm.com/"),
        )
        val live = LiveNow(liveShown(id, null)!!, LiveLineup(listOf(id), 0), null)
        assertEquals(
            listOf(
                InfoLine("Stream", "AAC 128 kbps"),
                InfoLine("Where", "California, The United States Of America"),
                InfoLine("Plays", "Pop, Top 40"),
                InfoLine("Website", "kiisfm.com", "https://www.kiisfm.com/"),
            ),
            stationInfoLines(live),
        )
        val bare = LiveNow(liveShown(radioId("http://s/a", "A"), null)!!, LiveLineup(listOf("a"), 0), null)
        assertEquals(listOf(InfoLine("Stream", "Live radio")), stationInfoLines(bare))
    }

    @Test
    fun aStationIdGivesBackTheStationToKeep() {
        val id = radioId("https://s/live", "One", hls = true, details = RadioDetails(logo = "https://logo", codec = "AAC", bitrate = 64, state = "Texas", tags = listOf("jazz"), uuid = "u-1"))
        val station = liveStationOf(id)!!
        assertEquals("u-1", station.uuid)
        assertEquals("One", station.name)
        assertEquals("https://s/live", station.streamUrl)
        assertEquals("https://logo", station.favicon)
        assertTrue(station.hls)
        assertEquals(listOf("jazz"), station.tags)
        assertNull(liveStationOf("t-1"))
    }
}
