package app.winters.octo.ui.search

import kotlin.test.Test
import kotlin.test.assertEquals
import kotlin.test.assertFalse
import kotlin.test.assertNull
import kotlin.test.assertTrue

class SearchMixTest {
    @Test
    fun lookingOnlineFollowsWhatIsKnown() {
        assertEquals(OutsideLook.Off, outsideLook(wanted = false, looking = true, failed = false, songs = 5))
        assertEquals(OutsideLook.Looking, outsideLook(wanted = true, looking = true, failed = false, songs = 0))
        assertEquals(OutsideLook.Failed, outsideLook(wanted = true, looking = false, failed = true, songs = 0))
        assertEquals(OutsideLook.Found, outsideLook(wanted = true, looking = false, failed = false, songs = 3))
        assertEquals(OutsideLook.NoneFound, outsideLook(wanted = true, looking = false, failed = false, songs = 0))
    }

    @Test
    fun theLineSaysPlainlyWhatHappened() {
        assertEquals("Searching outside your library…", outsideLine(OutsideLook.Looking, "linkin park"))
        assertEquals("No songs outside your library for \"linkin park\"", outsideLine(OutsideLook.NoneFound, " linkin park "))
        assertEquals("Couldn't search outside your library", outsideLine(OutsideLook.Failed, "x"))
        assertEquals("Not in your library", outsideLine(OutsideLook.Found, "x"))
        assertNull(outsideLine(OutsideLook.Off, "x"))
    }

    @Test
    fun allShowsAFewOfEachAndSeeAllForTheRest() {
        assertFalse(moreSongsThanShown(LIBRARY_SONGS_SHOWN, ONLINE_SONGS_SHOWN))
        assertTrue(moreSongsThanShown(LIBRARY_SONGS_SHOWN + 1, 0))
        assertTrue(moreSongsThanShown(0, ONLINE_SONGS_SHOWN + 1))
    }

    @Test
    fun songsShowWhileThereIsSomethingToSay() {
        assertTrue(songsShown(2, OutsideLook.Off))
        assertTrue(songsShown(0, OutsideLook.Looking))
        assertTrue(songsShown(0, OutsideLook.NoneFound))
        assertFalse(songsShown(0, OutsideLook.Off))
    }

    // The songs found online come within the first screen: never more than
    // a handful of library songs before them.
    @Test
    fun findsSitCloseUnderTheLibrarysSongs() {
        assertTrue(LIBRARY_SONGS_SHOWN <= 3)
        // The waiting rows are as many as the finds that take their places.
        assertEquals(ONLINE_SONGS_SHOWN, WAITING_ROWS)
    }
}
