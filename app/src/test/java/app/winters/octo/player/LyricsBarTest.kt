package app.winters.octo.player

import org.junit.Assert.assertEquals
import org.junit.Test

class LyricsBarTest {
    @Test
    fun theArtworkSaysHowMuchHasPlayed() {
        assertEquals("1:05 of 3:20 played", playedWords(65, 200, live = false))
        assertEquals("0:00 of 3:20 played", playedWords(0, 200, live = false))
    }

    @Test
    fun aPlaceIsHeldToTheSong() {
        assertEquals("3:20 of 3:20 played", playedWords(205, 200, live = false))
        assertEquals("0:00 of 3:20 played", playedWords(-3, 200, live = false))
    }

    @Test
    fun aStationOrASongOfNoLengthSaysNothing() {
        assertEquals("", playedWords(65, 200, live = true))
        assertEquals("", playedWords(65, 0, live = false))
    }
}
