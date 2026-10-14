package app.winters.octo.ui.imports

import app.winters.octo.subsonic.ImportListSummary
import app.winters.octo.subsonic.ImportOverview
import app.winters.octo.subsonic.ImportTrackState
import app.winters.octo.subsonic.TrickleStatus
import java.time.ZoneOffset
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertTrue
import org.junit.Test

// What both apps say about an import.
class ImportWordsTest {
    @Test
    fun aListSaysWhereItIsFromAndWhatTheLibraryHas() {
        val list = ImportListSummary(source = "link", by = "Spotify", total = 10, have = 6, missing = 2, queued = 1, downloading = 1, notFound = 1)
        assertEquals("Link · by Spotify", list.originLine())
        assertEquals("6 of 10 · 2 missing · 2 coming · 1 not found", list.countsLine())
        assertEquals("File", ImportListSummary(source = "file").originLine())
        assertEquals("", ImportListSummary(source = "textList").originLine())
        assertEquals("Fetched", ImportTrackState.Done.label())
    }

    @Test
    fun aListFromASpotifySignInSaysItIsNotUpdating_AndIsNotReadAgain() {
        val playlist = ImportListSummary(source = "spotifyPlaylist", by = "Spotify", canRefresh = true)
        assertEquals("Spotify · by Spotify · not updating", playlist.originLine())
        assertFalse(playlist.readsAgain)
        val liked = ImportListSummary(source = "spotifyLiked", canRefresh = true)
        assertEquals("Spotify · not updating", liked.originLine())
        assertFalse(liked.readsAgain)
        assertTrue(ImportListSummary(source = "link", canRefresh = true).readsAgain)
        assertFalse(ImportListSummary(source = "link", canRefresh = false).readsAgain)
    }

    @Test
    fun removingAListSaysWhatGoesAndWhatStays() {
        assertEquals("Octo forgets Road trip. Songs already in your library stay.", ImportListSummary(name = "Road trip").removeLine())
        assertEquals(
            "Octo forgets Road trip and stops getting its missing songs. Songs already in your library stay, and so does its playlist.",
            ImportListSummary(name = "Road trip", getMissing = true, playlistId = "pl-1").removeLine(),
        )
    }

    @Test
    fun theTrickleSaysWhatItWaitsFor() {
        val running = TrickleStatus(state = "running", perHour = 20, queued = 3, nextUtc = "2026-10-04T14:05:00Z", done = 2)
        assertEquals("Waiting for the next turn", running.title())
        assertEquals("Up to 20 songs an hour. Next song at 14:05. 3 waiting, 2 fetched.", running.line(ZoneOffset.UTC))
        assertEquals("Waiting for Soulseek", TrickleStatus(state = "waitingForSoulseek").title())
        assertEquals("Songs an hour is 0 on the server, so nothing starts.", TrickleStatus(state = "off").line(ZoneOffset.UTC))
        assertEquals("Nothing to fetch", TrickleStatus(state = "idle").title())
    }

    @Test
    fun songsOnTheirWayMeanAskingAgainSoon() {
        assertFalse(ImportOverview().moving())
        assertTrue(ImportOverview(trickle = TrickleStatus(queued = 1)).moving())
        assertTrue(ImportOverview(trickle = TrickleStatus(downloading = 1)).moving())
    }
}
