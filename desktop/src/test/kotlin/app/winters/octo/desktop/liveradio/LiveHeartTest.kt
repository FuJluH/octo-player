package app.winters.octo.desktop.liveradio

import app.winters.octo.liveradio.OnAir
import app.winters.octo.subsonic.Song
import kotlinx.coroutines.CompletableDeferred
import kotlinx.coroutines.ExperimentalCoroutinesApi
import kotlinx.coroutines.test.UnconfinedTestDispatcher
import kotlinx.coroutines.test.runCurrent
import kotlinx.coroutines.test.runTest
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

// The live player's heart: it stars the one song a search finds that is
// surely the one on air (the library's first), never another, and offers
// the search when none is sure.
@OptIn(ExperimentalCoroutinesApi::class)
class LiveHeartTest {
    private val petal = OnAir("Petal", "Ariana Grande", "https://i.iheart.com/v3/catalog/track/421089822")
    private val starred = ArrayList<Pair<String, Boolean>>()
    private val missed = ArrayList<String>()
    private val asked = ArrayList<String>()

    private fun found(vararg songs: FoundSong) = songs.toList()

    private val library = Song("lib-1", "Petal", artist = "Ariana Grande")
    private val outside = Song("ext-1", "Petal", artist = "Ariana Grande", isExternal = true)
    private val remix = Song("lib-2", "Petal (Remix)", artist = "Ariana Grande")
    private val other = Song("lib-3", "Petals", artist = "Someone Else")

    @Test
    fun aSureMatchIsStarredTheLibrarysFirst() = runTest(UnconfinedTestDispatcher()) {
        val heart = LiveHeart(backgroundScope, { asked += it; found(FoundSong(outside, false), FoundSong(remix, true), FoundSong(library, true)) }, { s, on -> starred += s.id to on }, { _, q -> missed += q })
        heart.follow(petal)
        assertTrue(heart.shows)
        heart.press()
        runCurrent()
        assertEquals(listOf("Ariana Grande Petal"), asked)
        assertEquals(listOf("lib-1" to true), starred)
        assertEquals(HeartPhase.Starred(library), heart.phase)
        // A second press takes the star back.
        heart.press()
        assertEquals("lib-1" to false, starred.last())
        assertEquals(HeartPhase.Idle, heart.phase)
    }

    @Test
    fun aSongFoundOnlineIsStarredWhenTheLibraryHasNone() = runTest(UnconfinedTestDispatcher()) {
        val heart = LiveHeart(backgroundScope, { found(FoundSong(outside, false)) }, { s, on -> starred += s.id to on }, { _, q -> missed += q })
        heart.follow(petal)
        heart.press()
        runCurrent()
        assertEquals(listOf("ext-1" to true), starred)
    }

    @Test
    fun noSureMatchStarsNothingAndOffersTheSearch() = runTest(UnconfinedTestDispatcher()) {
        val heart = LiveHeart(backgroundScope, { found(FoundSong(remix, true), FoundSong(other, true)) }, { s, on -> starred += s.id to on }, { _, q -> missed += q })
        heart.follow(petal)
        heart.press()
        runCurrent()
        assertTrue(starred.isEmpty())
        assertEquals(listOf("Ariana Grande Petal"), missed)
        assertEquals(HeartPhase.Idle, heart.phase)
        assertEquals("Couldn't find Petal by Ariana Grande in Octo for sure.", heartMissedLine(petal))
        assertEquals("Heart Petal by Ariana Grande", heartLabel(petal))
    }

    @Test
    fun withNoServerTheSearchIsOffered() = runTest(UnconfinedTestDispatcher()) {
        val heart = LiveHeart(backgroundScope, { null }, { s, on -> starred += s.id to on }, { _, q -> missed += q })
        heart.follow(petal)
        heart.press()
        runCurrent()
        assertEquals(listOf("Ariana Grande Petal"), missed)
    }

    @Test
    fun aNewSongOnAirEmptiesTheHeart() = runTest(UnconfinedTestDispatcher()) {
        val heart = LiveHeart(backgroundScope, { found(FoundSong(library, true)) }, { s, on -> starred += s.id to on }, { _, q -> missed += q })
        heart.follow(petal)
        heart.press()
        runCurrent()
        assertTrue(heart.phase is HeartPhase.Starred)
        heart.follow(OnAir("Lush Life", "Zara Larsson"))
        assertEquals(HeartPhase.Idle, heart.phase)
        // The same song again keeps the heart as it is.
        heart.follow(OnAir("Lush Life", "Zara Larsson"))
        assertEquals(HeartPhase.Idle, heart.phase)
        // While nothing is named it is hidden.
        heart.follow(OnAir(tagline = "LA's #1 Hit Music Station"))
        assertFalse(heart.shows)
        heart.press()
        assertEquals(1, starred.size)
    }

    @Test
    fun anAnswerForASongGoneByStarsNothing() = runTest(UnconfinedTestDispatcher()) {
        val answer = CompletableDeferred<List<FoundSong>>()
        val heart = LiveHeart(backgroundScope, { answer.await() }, { s, on -> starred += s.id to on }, { _, q -> missed += q })
        heart.follow(petal)
        heart.press()
        assertEquals(HeartPhase.Looking, heart.phase)
        heart.follow(OnAir("Lush Life", "Zara Larsson"))
        answer.complete(found(FoundSong(library, true)))
        runCurrent()
        assertTrue(starred.isEmpty())
        assertTrue(missed.isEmpty())
    }
}
