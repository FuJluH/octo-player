package app.winters.octo.player

import app.winters.octo.catalog.TrackEntity
import app.winters.octo.discovery.DownloadPhase
import app.winters.octo.liveradio.LiveLineup
import app.winters.octo.liveradio.LiveSongButton
import app.winters.octo.liveradio.OnAir
import app.winters.octo.liveradio.SongLookup
import app.winters.octo.liveradio.liveShown
import app.winters.octo.liveradio.liveSongButtonLabel
import app.winters.octo.liveradio.songLookupOf
import app.winters.octo.playback.LiveNow
import app.winters.octo.playback.RadioDetails
import app.winters.octo.playback.radioId
import kotlinx.coroutines.CompletableDeferred
import kotlinx.coroutines.async
import kotlinx.coroutines.test.runTest
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

// The live player's song button: a heart for a song in the library, a plus
// that adds one from outside it or searches for one Octo is not sure of,
// and the station's menu and info.
class LiveHeartTest {
    private val petal = OnAir("Petal", "Ariana Grande", "https://art")

    private fun track(id: String, title: String = "Petal", artist: String = "Ariana Grande") = TrackEntity(
        id = id, sourceId = "src", nativeId = id, title = title, searchKey = title.lowercase(), sortKey = title.lowercase(),
        artist = artist, artistId = "", album = "", albumId = "", trackNo = null, discNo = null, year = null,
        durationMs = 0, addedAt = 0, mimeType = null, sizeBytes = null, artwork = null, uri = null,
    )

    private val inLibrary = songLookupOf(petal, listOf(track("t-1")), emptyList())
    private val outside = songLookupOf(petal, emptyList(), listOf(track("find:9"), track("find:2", title = "Petal (Remix)")))
    private val unsure = songLookupOf(petal, listOf(track("t-3", artist = "Someone Else")), listOf(track("find:2", title = "Petal (Remix)")))

    private class Fake(val answer: suspend () -> SongLookup) {
        val liked = mutableSetOf<String>()
        val added = mutableListOf<String>()
        val searched = mutableListOf<String>()
        var looks = 0
        var library = LibraryNow()
        val song = LiveSong(
            look = { _, _ -> looks++; answer() },
            like = { id, on -> if (on) liked += id else liked -= id; library = library.copy(liked = liked.toSet()) },
            add = { added += it.id; true },
            search = { searched += it },
        )

        fun button() = song.button(song.state.value, library)

        suspend fun tap() = song.tap { library }
    }

    @Test
    fun aLibrarySongShowsTheHeartWhichFillsOnceStarred() = runTest {
        val fake = Fake { inLibrary }
        fake.song.onAir(petal)
        fake.song.lookUp()
        assertEquals(LiveSongButton.Heart(starred = false), fake.button())
        assertEquals("Heart Petal by Ariana Grande", liveSongButtonLabel(fake.button(), petal))
        assertEquals(SongTap.Hearted("t-1"), fake.tap())
        assertEquals(LiveSongButton.Heart(starred = true), fake.button())
        assertEquals(SongTap.Unhearted("t-1"), fake.tap())
        assertEquals(LiveSongButton.Heart(starred = false), fake.button())
        assertTrue(fake.added.isEmpty())
    }

    @Test
    fun anOutsideSongShowsThePlusThatAddsItThenTheHeartOnceInTheLibrary() = runTest {
        val fake = Fake { outside }
        fake.song.onAir(petal)
        fake.song.lookUp()
        assertEquals(LiveSongButton.Add(adding = false), fake.button())
        assertEquals("Add Petal by Ariana Grande to your library", liveSongButtonLabel(fake.button(), petal))
        assertEquals("find:9", (fake.tap() as SongTap.Adding).song.id)
        assertEquals(listOf("find:9"), fake.added)
        // On its way: the ring, and a second tap asks for nothing more.
        assertEquals(LiveSongButton.Add(adding = true), fake.button())
        fake.library = fake.library.copy(phases = mapOf("find:9" to DownloadPhase.Downloading(0.4f)))
        assertEquals(LiveSongButton.Add(adding = true), fake.button())
        assertEquals(SongTap.Ignored, fake.tap())
        assertEquals(1, fake.added.size)
        // In the library now: the filled heart.
        fake.library = fake.library.copy(phases = mapOf("find:9" to DownloadPhase.Done), adoptions = mapOf("find:9" to "t-9"))
        assertEquals(LiveSongButton.Heart(starred = true), fake.button())
        // Taking the heart off unlikes the library's copy.
        fake.liked += "t-9"
        fake.library = fake.library.copy(liked = setOf("t-9"))
        assertEquals(SongTap.Unhearted("t-9"), fake.tap())
        assertEquals(LiveSongButton.Heart(starred = false), fake.button())
    }

    @Test
    fun noSureMatchShowsThePlusThatSearchesAndStarsNothing() = runTest {
        val fake = Fake { unsure }
        fake.song.onAir(petal)
        fake.song.lookUp()
        assertEquals(LiveSongButton.Search, fake.button())
        assertEquals(SongTap.Searched("Ariana Grande Petal"), fake.tap())
        assertEquals(listOf("Ariana Grande Petal"), fake.searched)
        assertTrue(fake.added.isEmpty())
        assertTrue(fake.liked.isEmpty())
    }

    @Test
    fun aTapWhileStillLookingWaitsForTheAnswer() = runTest {
        val gate = CompletableDeferred<SongLookup>()
        val fake = Fake { gate.await() }
        fake.song.onAir(petal)
        // Still looking: the plus, which does nothing on its own.
        assertEquals(LiveSongButton.Add(adding = false), fake.button())
        val tap = async { fake.tap() }
        testScheduler.runCurrent()
        gate.complete(inLibrary)
        assertEquals(SongTap.Hearted("t-1"), tap.await())
        assertEquals(1, fake.looks)
    }

    @Test
    fun noSongNamedHasNoButtonAndANewSongStartsAfresh() = runTest {
        val fake = Fake { outside }
        fake.song.onAir(OnAir(tagline = "LA's #1 Hit Music Station"))
        assertNull(fake.song.lookUp())
        assertEquals(LiveSongButton.None, fake.button())
        assertEquals(SongTap.Ignored, fake.tap())
        assertEquals(0, fake.looks)
        fake.song.onAir(petal)
        fake.song.lookUp()
        fake.tap()
        assertEquals(LiveSongButton.Add(adding = true), fake.button())
        // The same song heard again keeps its state; a new song does not.
        fake.song.onAir(petal.copy(artwork = "https://other"))
        assertEquals(LiveSongButton.Add(adding = true), fake.button())
        fake.song.onAir(OnAir("Lush Life", "Zara Larsson"))
        assertEquals(LiveSongButton.Add(adding = false), fake.button())
        assertNull(fake.song.state.value.lookup)
    }

    @Test
    fun theSongsNameIsCopiedArtistFirst() {
        assertEquals("Ariana Grande - Petal", copiedSongName(petal))
        assertEquals("Interlude", copiedSongName(OnAir("Interlude")))
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
