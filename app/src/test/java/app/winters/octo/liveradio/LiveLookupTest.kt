package app.winters.octo.liveradio

import app.winters.octo.catalog.TrackEntity
import kotlinx.coroutines.CompletableDeferred
import kotlinx.coroutines.async
import kotlinx.coroutines.test.runTest
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Assert.assertSame
import org.junit.Test

// The song on air is looked up through Octo once per song, and the cover
// and the heart share the answer.
class LiveLookupTest {
    private val joy = OnAir("Joy", "Raye", "https://i.iheart.com/x")

    private fun track(id: String, title: String, artist: String, artwork: String?) = TrackEntity(
        id = id, sourceId = "src", nativeId = id, title = title, searchKey = title.lowercase(), sortKey = title.lowercase(),
        artist = artist, artistId = "", album = "", albumId = "", trackNo = null, discNo = null, year = null,
        durationMs = 0, addedAt = 0, mimeType = null, sizeBytes = null, artwork = artwork, uri = null,
    )

    @Test
    fun theSureMatchGivesTheCoverTheLibrarysFirst() {
        val library = track("t-1", "Joy", "RAYE", "server:src|al-1")
        val outside = track("find:2", "Joy", "Raye", "online:src|al-2")
        val remix = track("find:3", "Joy (Remix)", "Raye", "online:src|al-3")
        val both = songLookupOf(joy, listOf(library), listOf(remix, outside))
        assertEquals("t-1", both.match?.id)
        assertEquals("server:src|al-1", both.cover)
        val onlyOutside = songLookupOf(joy, emptyList(), listOf(remix, outside))
        assertEquals("online:src|al-2", onlyOutside.cover)
        // A remix alone is not the song: no cover.
        assertNull(songLookupOf(joy, emptyList(), listOf(remix)).cover)
        assertNull(songLookupOf(joy, listOf(track("t-4", "Joy", "Raye", null)), emptyList()).cover)
    }

    @Test
    fun eachSongIsLookedUpOnceAndKept() = runTest {
        var searches = 0
        val lookups = SongLookups { air -> searches++; SongLookup(match = HeartCandidate("t-1", air.title, air.artist, true)) }
        assertNull(lookups.known(joy))
        val first = lookups.look(joy)
        assertSame(first, lookups.look(joy))
        // The same song with other artwork, or in other letters, is the same song.
        assertSame(first, lookups.look(joy.copy(artwork = "")))
        assertSame(first, lookups.known(OnAir("JOY", "raye")))
        assertEquals(1, searches)
        lookups.look(OnAir("Lush Life", "Zara Larsson"))
        assertEquals(2, searches)
        // Nothing named is never looked up.
        assertEquals(SongLookup(), lookups.look(OnAir(tagline = "LA's #1 Hit Music Station")))
        assertEquals(2, searches)
    }

    @Test
    fun askedTwiceAtOnceItIsLookedUpOnce() = runTest {
        var searches = 0
        val gate = CompletableDeferred<Unit>()
        val lookups = SongLookups { searches++; gate.await(); SongLookup() }
        val a = async { lookups.look(joy) }
        val b = async { lookups.look(joy) }
        testScheduler.runCurrent()
        gate.complete(Unit)
        assertSame(a.await(), b.await())
        assertEquals(1, searches)
    }

    @Test
    fun aLookThatCouldNotReachOctoIsAskedAgainOnlyWhenAskedTo() = runTest {
        var searches = 0
        val lookups = SongLookups { searches++; SongLookup(complete = searches > 1) }
        lookups.look(joy)
        lookups.look(joy)
        assertEquals(1, searches)
        lookups.look(joy, again = true)
        assertEquals(2, searches)
        lookups.look(joy, again = true)
        assertEquals(2, searches)
    }

    @Test
    fun onlyTheLatestSongsAreKept() = runTest {
        var searches = 0
        val lookups = SongLookups(kept = 2) { searches++; SongLookup() }
        lookups.look(OnAir("A", "x"))
        lookups.look(OnAir("B", "x"))
        lookups.look(OnAir("C", "x"))
        assertNull(lookups.known(OnAir("A", "x")))
        lookups.look(OnAir("C", "x"))
        assertEquals(3, searches)
    }
}
