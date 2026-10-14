package app.winters.octo.desktop.liveradio

import app.winters.octo.desktop.search.FetchPhase
import app.winters.octo.liveradio.LiveSongButton
import app.winters.octo.liveradio.OnAir
import app.winters.octo.liveradio.liveSongButtonLabel
import app.winters.octo.subsonic.Song
import kotlinx.coroutines.CompletableDeferred
import kotlinx.coroutines.ExperimentalCoroutinesApi
import kotlinx.coroutines.test.TestScope
import kotlinx.coroutines.test.UnconfinedTestDispatcher
import kotlinx.coroutines.test.runCurrent
import kotlinx.coroutines.test.runTest
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

// The button beside the song on air: the song is looked for in Octo once,
// the one sure match (the library's first) is hearted, or added when Octo
// found it online, and with no sure match the plus opens the search and
// stars nothing.
@OptIn(ExperimentalCoroutinesApi::class)
class LiveHeartTest {
    private val petal = OnAir("Petal", "Ariana Grande", "https://i.iheart.com/v3/catalog/track/421089822")
    private val starred = ArrayList<Pair<String, Boolean>>()
    private val added = ArrayList<String>()
    private val missed = ArrayList<String>()
    private val asked = ArrayList<String>()
    private val landed = HashSet<String>()

    private val library = Song("lib-1", "Petal", artist = "Ariana Grande")
    private val outside = Song("ext-1", "Petal", artist = "Ariana Grande", isExternal = true)
    private val remix = Song("lib-2", "Petal (Remix)", artist = "Ariana Grande")
    private val other = Song("lib-3", "Petals", artist = "Someone Else")

    private fun TestScope.heart(find: suspend (String) -> List<FoundSong>?) = LiveHeart(
        backgroundScope,
        { asked += it; find(it) },
        { s, on -> starred += s.id to on },
        { _, q -> missed += q },
        add = { added += it.id },
        landed = { it.id in landed },
    )

    @Test
    fun aLibraryMatchGetsTheHeartAndIsStarred() = runTest(UnconfinedTestDispatcher()) {
        val heart = heart { listOf(FoundSong(outside, false), FoundSong(remix, true), FoundSong(library, true)) }
        heart.follow(petal)
        runCurrent()
        assertEquals(LiveSongButton.Heart(starred = false), heart.button(FetchPhase.None, starredNow = false))
        assertEquals("Heart Petal by Ariana Grande", liveSongButtonLabel(heart.button(FetchPhase.None, false), petal))
        heart.press()
        assertEquals(listOf("Ariana Grande Petal"), asked)
        assertEquals(listOf("lib-1" to true), starred)
        assertEquals(LiveSongButton.Heart(starred = true), heart.button(FetchPhase.None, starredNow = false))
        // A second press takes the heart back.
        heart.press(starredNow = true)
        assertEquals("lib-1" to false, starred.last())
        assertEquals(HeartPhase.Idle, heart.phase)
    }

    @Test
    fun aLibrarySongThatIsAFavoriteAlreadyIsTakenBack() = runTest(UnconfinedTestDispatcher()) {
        val heart = heart { listOf(FoundSong(library, true)) }
        heart.follow(petal)
        runCurrent()
        assertEquals(LiveSongButton.Heart(starred = true), heart.button(FetchPhase.None, starredNow = true))
        heart.press(starredNow = true)
        assertEquals(listOf("lib-1" to false), starred)
    }

    @Test
    fun anOutsideMatchGetsThePlusAndIsAddedThenTheHeart() = runTest(UnconfinedTestDispatcher()) {
        val heart = heart { listOf(FoundSong(outside, false)) }
        heart.follow(petal)
        runCurrent()
        val plus = heart.button(FetchPhase.None, false)
        assertEquals(LiveSongButton.Add(adding = false), plus)
        assertEquals("Add Petal by Ariana Grande to your library", liveSongButtonLabel(plus, petal))
        heart.press()
        assertEquals(listOf("ext-1"), added)
        assertTrue("never hearted in place", starred.isEmpty())
        assertEquals(LiveSongButton.Add(adding = true), heart.button(FetchPhase.Downloading(0.4f), false))
        // On its way, a press waits.
        heart.press()
        assertEquals(listOf("ext-1"), added)
        assertTrue(starred.isEmpty())
        // In the library: the heart, filled.
        landed += "ext-1"
        assertEquals(LiveSongButton.Heart(starred = true), heart.button(FetchPhase.Done, false))
    }

    @Test
    fun noSureMatchGetsThePlusThatOpensTheSearch() = runTest(UnconfinedTestDispatcher()) {
        val heart = heart { listOf(FoundSong(remix, true), FoundSong(other, true)) }
        heart.follow(petal)
        runCurrent()
        val plus = heart.button(FetchPhase.None, false)
        assertEquals(LiveSongButton.Search, plus)
        assertEquals("Search for Petal by Ariana Grande", liveSongButtonLabel(plus, petal))
        heart.press()
        assertTrue(starred.isEmpty())
        assertTrue(added.isEmpty())
        assertEquals(listOf("Ariana Grande Petal"), missed)
        assertEquals(HeartPhase.Idle, heart.phase)
    }

    @Test
    fun aPressWhileLookingWaitsForTheAnswer() = runTest(UnconfinedTestDispatcher()) {
        val answer = CompletableDeferred<List<FoundSong>>()
        val heart = heart { answer.await() }
        heart.follow(petal)
        assertEquals("the plus while looking", LiveSongButton.Add(adding = false), heart.button(FetchPhase.None, false))
        heart.press()
        assertEquals(HeartPhase.Looking, heart.phase)
        answer.complete(listOf(FoundSong(library, true)))
        runCurrent()
        assertEquals(listOf("lib-1" to true), starred)
        assertEquals(1, asked.size)
    }

    @Test
    fun withNoServerThePlusOpensTheSearch() = runTest(UnconfinedTestDispatcher()) {
        val heart = heart { null }
        heart.follow(petal)
        heart.press()
        runCurrent()
        assertEquals(listOf("Ariana Grande Petal"), missed)
    }

    @Test
    fun aStationBreakHasNoButton() = runTest(UnconfinedTestDispatcher()) {
        val heart = heart { listOf(FoundSong(library, true)) }
        heart.follow(OnAir(tagline = "LA's #1 Hit Music Station"))
        assertFalse(heart.shows)
        assertEquals(LiveSongButton.None, heart.button(FetchPhase.None, false))
        heart.press()
        assertTrue(asked.isEmpty())
        assertTrue(starred.isEmpty())
    }

    @Test
    fun eachSongIsLookedForOnceAndANewSongStartsAfresh() = runTest(UnconfinedTestDispatcher()) {
        val heart = heart { listOf(FoundSong(library, true)) }
        heart.follow(petal)
        runCurrent()
        // Looked for as soon as it is on air, for its cover, before any press.
        assertEquals(listOf("Ariana Grande Petal"), asked)
        assertEquals(library, heart.match?.song)
        heart.press()
        assertTrue(heart.phase is HeartPhase.Starred)
        heart.follow(OnAir("Lush Life", "Zara Larsson"))
        runCurrent()
        assertEquals(HeartPhase.Idle, heart.phase)
        assertEquals(null, heart.match)
        heart.follow(petal)
        runCurrent()
        assertEquals("a song heard before is not searched again", 2, asked.size)
        assertEquals(library, heart.match?.song)
    }

    @Test
    fun anAnswerForASongGoneByStarsNothing() = runTest(UnconfinedTestDispatcher()) {
        val answer = CompletableDeferred<List<FoundSong>>()
        val heart = heart { if (it.contains("Petal")) answer.await() else emptyList() }
        heart.follow(petal)
        heart.press()
        heart.follow(OnAir("Lush Life", "Zara Larsson"))
        answer.complete(listOf(FoundSong(library, true)))
        runCurrent()
        assertTrue(starred.isEmpty())
        assertTrue(missed.isEmpty())
    }
}
