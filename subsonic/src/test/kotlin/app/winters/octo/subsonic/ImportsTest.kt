package app.winters.octo.subsonic

import kotlinx.coroutines.runBlocking
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

// Octo's imports as the apps call it: the overview, one list, the actions,
// the services, and files and text sent to the server.
class ImportsTest {
    private val server = MockWebServer()

    @Before
    fun start() = server.start()

    @After
    fun stop() = server.close()

    private fun client() = SubsonicClient(server.url("/"), Credentials("winters", "secret"), OkHttpClient())

    private fun answer(body: String) = server.enqueue(MockResponse.Builder().body(body).build())

    private fun ok(inner: String) = """{"subsonic-response":{"status":"ok","version":"1.16.1","type":"octo","openSubsonic":true,$inner}}"""

    // An older server still sends its Spotify sign-in and reading state;
    // they are not read, and the rest still is.
    @Test
    fun readsTheOverview() = runBlocking {
        answer(
            ok(
                """"imports":{"spotify":{"configured":true,"connected":true,"account":"Brandon","redirectUri":"http://127.0.0.1/callback",
                "octoFinishes":false,"endsUtc":"2027-04-01T00:00:00Z"},"reading":{"busy":true,"step":"Reading your liked songs"},
                "lists":[{"id":"spotify-liked","name":"Liked Songs","source":"spotifyLiked","total":10,"have":6,"missing":2,"queued":1,
                "downloading":1,"keepPlaylist":false,"getMissing":true,"canRefresh":true,"newField":1}],
                "trickle":{"state":"waitingForSoulseek","perHour":20,"queued":1,"current":{"key":"spotify:a","title":"Angel","artist":"Massive Attack",
                "state":"downloading","progress":0.4}},"libraryProblem":null}""",
            ),
        )
        val overview = client().imports()
        assertEquals("/rest/getImports", server.takeRequest().url.encodedPath)
        val liked = overview.lists.single()
        assertEquals(ImportSource.SpotifyLiked, liked.origin)
        assertTrue(liked.origin.fromSignIn)
        assertFalse(liked.readsAgain)
        assertEquals(0.6f, liked.fraction, 0.001f)
        assertEquals(2, liked.coming)
        assertEquals(TrickleState.WaitingForSoulseek, overview.trickle.stage)
        assertEquals(ImportTrackState.Downloading, overview.trickle.current?.stage)
    }

    @Test
    fun readsOneListsSongs() = runBlocking {
        answer(ok(""""import":{"list":{"id":"file-1","name":"Gym","source":"file"},"tracks":[
            {"key":"song:a","title":"A","artist":"B","state":"notFound","detail":"No source had it"},
            {"key":"song:c","title":"C","artist":"D","state":"have","libraryId":"nd-1"},
            {"key":"song:e","title":"E","artist":"F","state":"brandNew"}]}"""))
        val detail = client().importList("file-1")
        assertEquals("file-1", server.takeRequest().url.queryParameter("id"))
        assertEquals(listOf(ImportTrackState.NotFound, ImportTrackState.Have, ImportTrackState.Unknown), detail.tracks.map { it.stage })
        assertTrue(detail.tracks[0].stage.askable)
        assertFalse(detail.tracks[1].stage.askable)
    }

    @Test
    fun anActionSendsItsParametersAndEverySongKey() = runBlocking {
        answer(ok(""""importAction":{"ok":true,"message":"Queued 2 songs.","count":2}"""))
        val result = client().importAction(ImportActions.SONGS, mapOf("id" to "file-1"), listOf("song:a", "spotify:b"))
        val request = server.takeRequest()
        assertEquals("/rest/importAction", request.url.encodedPath)
        assertEquals("songs", request.url.queryParameter("action"))
        assertEquals(listOf("song:a", "spotify:b"), request.url.queryParameterValues("key"))
        assertTrue(result.ok)
        assertEquals(2, result.count)
    }

    @Test
    fun aRefusedActionStillReadsAsAnAnswer() = runBlocking {
        answer(ok(""""importAction":{"ok":false,"message":"That link is not a public playlist or album."}"""))
        val result = client().importAction(ImportActions.ADD_LINK, mapOf("url" to "https://example.com/x"))
        val request = server.takeRequest()
        assertEquals("addLink", request.url.queryParameter("action"))
        assertEquals("https://example.com/x", request.url.queryParameter("url"))
        assertFalse(result.ok)
        assertEquals("That link is not a public playlist or album.", result.message)
        assertNull(result.listId)
    }

    @Test
    fun aListFromAServiceThisAppDoesNotKnowStillReads() = runBlocking {
        answer(ok(""""imports":{"lists":[{"id":"t1","name":"Gym","source":"textList"},{"id":"f1","name":"Road","source":"file"}]}"""))
        val lists = client().imports().lists
        assertEquals(listOf(ImportSource.Unknown, ImportSource.File), lists.map { it.origin })
    }

    @Test
    fun theOverviewSaysWhoApprovesAFamilyMembersDownloads() = runBlocking {
        answer(ok(""""imports":{"lists":[],"approval":{"needed":true,"by":"Sam","later":1}}"""))
        assertEquals(ImportApproval(needed = true, by = "Sam"), client().imports().approval)
        answer(ok(""""imports":{"lists":[],"approval":{"needed":true,"by":""}}"""))
        assertEquals(ImportApproval(needed = true, by = ""), client().imports().approval)
        answer(ok(""""imports":{"lists":[],"approval":{"needed":true}}"""))
        assertEquals(ImportApproval(needed = true, by = null), client().imports().approval)
    }

    @Test
    fun anOverviewWithoutApprovalReadsAsNone() = runBlocking {
        answer(ok(""""imports":{"lists":[]}"""))
        assertNull(client().imports().approval)
        answer(ok(""""imports":{"lists":[],"approval":null}"""))
        assertNull(client().imports().approval)
    }

    // ---- Version 2: services, files and text ---------------------------------------------------

    @Test
    fun version2IsReadFromTheExtensionsList() = runBlocking {
        answer(ok(""""openSubsonicExtensions":[{"name":"octoImports","versions":[1,2]}]"""))
        assertTrue(client().supports(OCTO_IMPORTS, OCTO_IMPORTS_FILES))
        answer(ok(""""openSubsonicExtensions":[{"name":"octoImports","versions":[1]}]"""))
        assertFalse(client().supports(OCTO_IMPORTS, OCTO_IMPORTS_FILES))
    }

    @Test
    fun readsTheServices() = runBlocking {
        answer(
            ok(
                """"importServices":{"services":[
                {"id":"spotify","name":"Spotify","exportUrl":"https://www.tunemymusic.com/transfer/spotify-to-file","tile":"Spotify"},
                {"id":"apple-music","name":"Apple Music","exportUrl":"https://www.tunemymusic.com/transfer/apple-music-to-file","tile":"Apple Music","later":1}],
                "spotifyConnect":true}""",
            ),
        )
        val services = client().importServices()
        assertEquals("/rest/getImportServices", server.takeRequest().url.encodedPath)
        assertEquals(listOf("spotify", "apple-music"), services.services.map { it.id })
        assertEquals("Apple Music", services.services[1].tile)
        assertEquals("https://www.tunemymusic.com/transfer/apple-music-to-file", services.services[1].exportUrl)
    }

    @Test
    fun noServicesKeyReadsAsNone() = runBlocking {
        answer(ok(""""other":{}"""))
        val services = client().importServices()
        assertTrue(services.services.isEmpty())
    }

    @Test
    fun aFileIsSentAsAMultipartPost() = runBlocking {
        answer(ok(""""importAction":{"ok":true,"message":"Read 2 lists, 340 songs.","count":2}"""))
        val bytes = "Track name,Artist name\nAngel,Massive Attack\n".toByteArray()
        val result = client().importFile("My Spotify Library.csv", bytes)
        val request = server.takeRequest()
        assertEquals("POST", request.method)
        assertEquals("/rest/importFile", request.url.encodedPath)
        assertEquals("My Spotify Library.csv", request.url.queryParameter("name"))
        assertEquals("winters", request.url.queryParameter("u"))
        assertTrue(request.headers["Content-Type"]!!.startsWith("multipart/form-data"))
        val sent = request.body!!.utf8()
        assertTrue(sent.contains("""name="file"; filename="My Spotify Library.csv""""))
        assertTrue(sent.contains("Content-Type: text/csv"))
        assertTrue(sent.contains("Angel,Massive Attack"))
        assertTrue(result.ok)
        assertEquals("Read 2 lists, 340 songs.", result.message)
    }

    @Test
    fun aRefusedFileReadsAsTheServersWords() = runBlocking {
        answer(ok(""""importAction":{"ok":false,"message":"No songs found. Each line should read Artist - Title."}"""))
        val result = client().importFile("notes.txt", "hello".toByteArray())
        assertFalse(result.ok)
        assertEquals("No songs found. Each line should read Artist - Title.", result.message)
    }

    @Test
    fun textIsSentInAFormBody() = runBlocking {
        answer(ok(""""importAction":{"ok":true,"message":"Read 1 list, 2 songs."}"""))
        val result = client().importText("Pasted list", "Massive Attack - Angel\nMGMT - Kids")
        val request = server.takeRequest()
        assertEquals("POST", request.method)
        assertEquals("/rest/importText", request.url.encodedPath)
        assertNull(request.url.queryParameter("text"))
        val form = request.body!!.utf8().split('&').associate { pair ->
            val (key, value) = pair.split('=', limit = 2)
            key to java.net.URLDecoder.decode(value, Charsets.UTF_8)
        }
        assertEquals("Pasted list", form["name"])
        assertEquals("Massive Attack - Angel\nMGMT - Kids", form["text"])
        assertTrue(result.ok)
    }

    @Test
    fun theFileTypeFollowsTheName() {
        assertEquals("text/csv", importFileType("a.CSV").toString())
        assertEquals("text/plain", importFileType("a.txt").toString())
        assertEquals("application/zip", importFileType("export.zip").toString())
        assertEquals("application/json", importFileType("x.json").toString())
        assertEquals("application/octet-stream", importFileType("noending").toString())
    }
}
