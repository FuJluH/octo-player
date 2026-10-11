package app.winters.octo.subsonic

import kotlinx.coroutines.test.runTest
import mockwebserver3.MockResponse
import mockwebserver3.MockWebServer
import okhttp3.OkHttpClient
import org.junit.After
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Before
import org.junit.Test

// A download's log, clearing finished ones, and Find songs, as an Octo
// server says them.
class DownloadLogTest {
    private val server = MockWebServer()

    @Before
    fun start() = server.start()

    @After
    fun stop() = server.close()

    private fun client() = SubsonicClient(server.url("/"), Credentials("winters", "secret"), OkHttpClient())

    private fun answer(name: String) {
        val body = requireNotNull(javaClass.getResource("/fixtures/$name.json")).readText(Charsets.UTF_8)
        server.enqueue(MockResponse.Builder().body(body).build())
    }

    @Test
    fun readsOneDownloadWithItsLog() = runTest {
        answer("getAcquisition")
        val one = client().acquisition("soulseek:3kX9Qm")

        val request = server.takeRequest()
        assertEquals("/rest/getAcquisition", request.url.encodedPath)
        assertEquals("soulseek:3kX9Qm", request.url.queryParameter("key"))

        assertEquals("soulseek:3kX9Qm", one.key)
        assertEquals(AcquisitionKind.DOWNLOAD, one.kind)
        assertEquals("FLAC 16-bit 44.1 kHz", one.quality)
        assertEquals("peer1", one.peer)
        assertEquals(4, one.logLines)
        assertEquals(listOf(LogKind.Queued, LogKind.Search, LogKind.Found, LogKind.Unknown), one.event.map { it.logKind })
        assertEquals("By winters", one.event[0].detail)
        val copy = one.event[2].candidate.single()
        assertEquals("peer1", copy.peer)
        assertEquals(1, copy.rank)
        assertEquals(true, copy.freeSlot)
        assertEquals(31_000_000L, copy.size)
    }

    @Test
    fun readsAFindSongsSearch() = runTest {
        answer("findSongs")
        val found = client().findSongs("nd-7")

        assertEquals("/rest/findSongs", server.takeRequest().url.encodedPath)
        assertFalse(found.searching)
        assertEquals("Sexy Boy", found.song.title)
        assertEquals("MP3 220 kbps", found.song.quality)
        assertEquals(listOf(FIND_DONE, FIND_OFF), found.source.map { it.state })
        assertEquals(listOf(0, 1), found.candidate.map { it.index })
        // A copy's own id, and none from a server older than copy ids.
        assertEquals(listOf("c-7f3a", null), found.candidate.map { it.id })
        assertNull(found.candidate[1].rank)
        assertEquals("Another version: a remix, an edit or a live take", found.candidate[1].note)
    }

    @Test
    fun pickingSendsTheSearchAndTheCopysId() = runTest {
        answer("pickFoundSong")
        val result = client().pickFoundSong("a1b2c3", FoundCandidate(source = "Soulseek", index = 3, id = "c-7f3a"))

        val request = server.takeRequest()
        assertEquals("/rest/pickFoundSong", request.url.encodedPath)
        assertEquals("a1b2c3", request.url.queryParameter("search"))
        assertEquals("c-7f3a", request.url.queryParameter("copy"))
        assertNull("The id alone names the copy", request.url.queryParameter("candidate"))
        assertTrue(result.queued)
        assertEquals("soulseek:3kX9Qm", result.key)
    }

    @Test
    fun anywayIsSentOnlyWhenAsked_AndAQuestionIsReadBack() = runTest {
        answer("pickFoundSong")
        client().pickFoundSong("a1b2c3", FoundCandidate(source = "Soulseek", index = 3, id = "c-7f3a"))
        assertNull("Not asked, not sent", server.takeRequest().url.queryParameter("anyway"))

        val question = "This copy is FLAC like yours, so it is not better. Replace yours anyway?"
        server.enqueue(
            MockResponse.Builder()
                .body("""{"subsonic-response":{"status":"ok","version":"1.16.1","pick":{"state":"confirm","detail":"$question","key":null}}}""")
                .build(),
        )
        val asked = client().pickFoundSong("a1b2c3", FoundCandidate(source = "Soulseek", id = "c-7f3a"), anyway = false)
        assertEquals("false", server.takeRequest().url.queryParameter("anyway"))
        assertTrue(asked.confirm)
        assertFalse(asked.queued)
        assertEquals(question, asked.detail)
        assertNull(asked.key)

        answer("pickFoundSong")
        client().pickFoundSong("a1b2c3", FoundCandidate(source = "Soulseek", id = "c-7f3a"), anyway = true)
        val again = server.takeRequest()
        assertEquals("true", again.url.queryParameter("anyway"))
        assertEquals("c-7f3a", again.url.queryParameter("copy"))
        assertEquals("a1b2c3", again.url.queryParameter("search"))
    }

    private fun ok(payload: String) =
        server.enqueue(MockResponse.Builder().body("""{"subsonic-response":{"status":"ok","version":"1.16.1",$payload}}""").build())

    @Test
    fun readsHowEachCopyStandsAgainstYours_AndTheTakeLine() = runTest {
        ok(
            """"foundSongs":{"id":"f1","state":"done","song":{"title":"Holocene","libraryId":"nd-1","take":"Yours looks like a live recording. Pick the plain song to replace it.","takeKind":"live"},
            "candidate":[{"source":"Soulseek","id":"c-1","vsYours":"same","vsYoursText":"Same as yours"},{"source":"Soulseek","id":"c-2"}]}""",
        )
        val found = client().foundSongs("f1")
        assertEquals("Yours looks like a live recording. Pick the plain song to replace it.", found.song.take)
        assertEquals(TAKE_LIVE, found.song.takeKind)
        assertEquals(listOf(VS_YOURS_SAME, null), found.candidate.map { it.vsYours })
        assertEquals(listOf("Same as yours", null), found.candidate.map { it.vsYoursText })
    }

    @Test
    fun aReadyAnswerCarriesBothCopies() = runTest {
        ok(""""pick":{"state":"ready","detail":null,"key":null,"compare":{"yours":{"quality":"FLAC","length":420,"take":"live recording"},"copy":{"quality":"FLAC","length":298,"take":null}}}""")
        val pick = client().pickFoundSong("f1", FoundCandidate(source = "Soulseek", id = "c-1"), anyway = false)
        assertTrue(pick.ready)
        assertFalse(pick.queued)
        assertEquals(PickSide("FLAC", 420, "live recording"), pick.compare!!.yours)
        assertEquals(PickSide("FLAC", 298, null), pick.compare!!.copy)
    }

    @Test
    fun readsAReplacedSongInTheTrash() = runTest {
        ok(""""libraryTrash":{"keepDays":30,"songs":[{"id":"nd-1","title":"Holocene","kind":"replaced","was":"FLAC 16-bit 44.1 kHz","now":"MP3 320"},{"id":"nd-2","title":"Towers"}]}""")
        val trash = client().libraryTrash()
        assertEquals(listOf(true, false), trash.songs.map { it.replaced })
        assertEquals("FLAC 16-bit 44.1 kHz", trash.songs[0].was)
        assertEquals("MP3 320", trash.songs[0].now)
    }

    @Test
    fun pickingOnAServerWithoutCopyIdsSendsThePlace() = runTest {
        answer("pickFoundSong")
        client().pickFoundSong("a1b2c3", FoundCandidate(source = "Soulseek", index = 3))

        val request = server.takeRequest()
        assertEquals("3", request.url.queryParameter("candidate"))
        assertNull(request.url.queryParameter("copy"))
    }

    @Test
    fun aCopyWithNeitherIdNorPlaceIsNotSent() = runTest {
        val result = client().pickFoundSong("a1b2c3", FoundCandidate(source = "Soulseek"))
        assertFalse(result.queued)
        assertEquals(0, server.requestCount)
    }

    @Test
    fun clearingAnswersHowManyLeft() = runTest {
        server.enqueue(MockResponse.Builder().body("""{"subsonic-response":{"status":"ok","version":"1.16.1","cleared":{"count":3}}}""").build())
        assertEquals(3, client().clearAcquisitions())
        assertNull(server.takeRequest().url.queryParameter("key"))

        server.enqueue(MockResponse.Builder().body("""{"subsonic-response":{"status":"ok","version":"1.16.1","cleared":{"count":1}}}""").build())
        assertEquals(1, client().clearAcquisitions("soulseek:x"))
        assertEquals("soulseek:x", server.takeRequest().url.queryParameter("key"))
    }
}
