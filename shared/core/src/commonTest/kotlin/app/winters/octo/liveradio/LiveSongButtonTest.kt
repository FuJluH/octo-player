package app.winters.octo.liveradio

import org.junit.Assert.assertEquals
import org.junit.Test

class LiveSongButtonTest {
    private val petal = OnAir("Petal", "Ariana Grande")
    private val inLibrary = HeartCandidate("1", "Petal", "Ariana Grande", inLibrary = true)
    private val outside = HeartCandidate("find:1", "Petal", "Ariana Grande", inLibrary = false)

    private fun button(onAir: OnAir = petal, match: HeartCandidate? = null, looked: Boolean = true, starred: Boolean = false, now: Boolean = false, adding: Boolean = false) =
        liveSongButton(onAir, match, looked, starred, now, adding)

    @Test
    fun aLibrarySongGetsTheHeart() {
        assertEquals(LiveSongButton.Heart(false), button(match = inLibrary))
        assertEquals(LiveSongButton.Heart(true), button(match = inLibrary, starred = true))
        assertEquals("Heart Petal by Ariana Grande", liveSongButtonLabel(LiveSongButton.Heart(false), petal))
    }

    @Test
    fun anOutsideSongGetsThePlusUntilItIsInTheLibrary() {
        assertEquals(LiveSongButton.Add(false), button(match = outside))
        assertEquals("Add Petal by Ariana Grande to your library", liveSongButtonLabel(LiveSongButton.Add(false), petal))
        // Starred, on its way.
        assertEquals(LiveSongButton.Add(true), button(match = outside, adding = true))
        assertEquals(LiveSongButton.Add(true), button(match = outside, starred = true))
        assertEquals("Adding Petal by Ariana Grande to your library", liveSongButtonLabel(LiveSongButton.Add(true), petal))
        // Arrived: a filled heart.
        assertEquals(LiveSongButton.Heart(true), button(match = outside, starred = true, now = true))
    }

    @Test
    fun noSongOctoIsSureOfGetsThePlusThatSearches() {
        assertEquals(LiveSongButton.Search, button(match = null, looked = true))
        assertEquals("Search for Petal by Ariana Grande", liveSongButtonLabel(LiveSongButton.Search, petal))
        // Still looking: the plus, not yet a search.
        assertEquals(LiveSongButton.Add(false), button(match = null, looked = false))
    }

    @Test
    fun aStationBreakGetsNoButton() {
        assertEquals(LiveSongButton.None, button(onAir = OnAir(tagline = "LA's #1 Hit Music Station"), match = inLibrary))
        assertEquals(LiveSongButton.None, button(onAir = OnAir.Nothing))
    }
}
