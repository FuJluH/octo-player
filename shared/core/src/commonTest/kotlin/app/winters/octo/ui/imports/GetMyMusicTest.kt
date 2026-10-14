package app.winters.octo.ui.imports

import app.winters.octo.subsonic.ImportApproval
import app.winters.octo.subsonic.ImportOverview
import app.winters.octo.subsonic.ImportServiceLink
import app.winters.octo.ui.family.FamilyFakeServer
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.Job
import kotlinx.coroutines.cancel
import kotlinx.coroutines.delay
import kotlinx.coroutines.runBlocking
import kotlinx.coroutines.withTimeout
import org.junit.After
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test
import java.util.concurrent.CopyOnWriteArrayList

// "Get my music": which export pages open, the steps from a tile tapped to
// the lists read, and what a family member whose downloads are approved
// first reads once their lists are in.
class GetMyMusicTest {
    private val server = FamilyFakeServer()
    private val scope = CoroutineScope(Dispatchers.Default + Job())
    private val opened = CopyOnWriteArrayList<String>()

    @After
    fun stop() {
        scope.cancel()
        server.close()
    }

    private val spotify = ImportServiceLink("spotify", "Spotify", "https://www.tunemymusic.com/transfer/spotify-to-file", "Spotify")
    private val apple = ImportServiceLink("apple-music", "Apple Music", "https://www.tunemymusic.com/transfer/apple-music-to-file", "Apple Music")

    private fun until(check: () -> Boolean) = runBlocking { withTimeout(5_000) { while (!check()) delay(20) } }

    // `spotifyConnect` is what an older server says when it can still sign in to Spotify.
    private fun octo(versions: String = "[1,2]", spotifyConnect: Boolean = false, approval: String? = null) {
        server.answer("getOpenSubsonicExtensions") { """"openSubsonicExtensions":[{"name":"octoImports","versions":$versions}]""" }
        server.answer("getImports") {
            val account = if (spotifyConnect) """"spotify":{"configured":true,"connected":true,"redirectUri":"http://127.0.0.1/callback"},""" else ""
            """"imports":{$account"lists":[],"trickle":{"state":"idle"}${approval?.let { ",\"approval\":$it" }.orEmpty()}}"""
        }
        server.answer("getImportServices") {
            """"importServices":{"services":[
            {"id":"spotify","name":"Spotify","exportUrl":"${spotify.exportUrl}","tile":"Spotify"},
            {"id":"apple-music","name":"Apple Music","exportUrl":"${apple.exportUrl}","tile":"Apple Music"},
            {"id":"bad","name":"Bad","exportUrl":"https://evil.example.com/transfer","tile":"Bad"}],
            "spotifyConnect":$spotifyConnect}"""
        }
    }

    private fun model(): ImportModel {
        val model = ImportModel({ server.client() }, scope, openUrl = { opened += it }, busyPollMs = 30, idlePollMs = 30)
        model.watch()
        return model
    }

    // ---- The export page allowlist ------------------------------------------------------------

    @Test
    fun onlyTuneMyMusicOverHttpsOpens() {
        assertEquals("https://www.tunemymusic.com/transfer/spotify-to-file", tuneMyMusicUrl("https://www.tunemymusic.com/transfer/spotify-to-file"))
        assertEquals("https://tunemymusic.com/transfer/tidal-to-file", tuneMyMusicUrl(" https://tunemymusic.com/transfer/tidal-to-file "))
        assertEquals("https://www.tunemymusic.com/", tuneMyMusicUrl("HTTPS://WWW.TuneMyMusic.com"))
        for (refused in listOf(
            "http://www.tunemymusic.com/transfer/spotify-to-file",
            "https://tunemymusic.com.evil.example/transfer",
            "https://evil.example/tunemymusic.com",
            "https://app.tunemymusic.com/transfer",
            "https://tunemymusic.com@evil.example/",
            "https://user:pass@tunemymusic.com/",
            "https://www.tunemymusic.com:8443/transfer",
            "javascript:alert(1)",
            "intent://tunemymusic.com#Intent;end",
            "file:///sdcard/Download/x.csv",
            "",
            "not a link",
        )) {
            assertNull(refused, tuneMyMusicUrl(refused))
        }
    }

    @Test
    fun theWaitSaysWhichTileToTap() {
        assertEquals(
            "Tap the Apple Music tile, sign in, choose your playlists or Liked songs, then Export to file as CSV.",
            waitingLine(apple),
        )
        assertEquals("Waiting for your Apple Music file", waitingTitle(apple))
        assertEquals("Waiting for your file", waitingTitle(null))
        assertTrue(isImportFileName("My Library.CSV"))
        assertTrue(isImportFileName("export.zip"))
        assertTrue(!isImportFileName("song.mp3"))
    }

    // ---- The steps ----------------------------------------------------------------------------

    @Test
    fun aServerWithoutVersion2ShowsNoServices() {
        octo(versions = "[1]")
        val model = model()
        until { model.overview != null }
        runBlocking { delay(150) }
        assertNull(model.services)
        assertTrue(server.called("getImportServices").isEmpty())
    }

    @Test
    fun aTileOpensItsExportPageAndWaitsForTheFile() {
        octo()
        val model = model()
        until { model.services != null }
        assertEquals(listOf("spotify", "apple-music", "bad"), model.services!!.services.map { it.id })
        model.choose(apple)
        assertEquals(listOf(apple.exportUrl), opened.toList())
        assertEquals(ImportStep.Waiting(apple), model.step)
        model.backToServices()
        assertEquals(ImportStep.Choose, model.step)
    }

    @Test
    fun anExportPageOffTuneMyMusicIsRefused() {
        octo()
        val model = model()
        until { model.services != null }
        model.choose(model.services!!.services.last())
        assertTrue(opened.isEmpty())
        assertEquals(ImportStep.Choose, model.step)
        assertEquals(NOT_TUNEMYMUSIC, model.said)
    }

    @Test
    fun spotifyOpensItsExportPage_EvenOnAServerThatCanSignInToIt() {
        for (connect in listOf(true, false)) {
            opened.clear()
            octo(spotifyConnect = connect)
            val model = model()
            until { model.services != null }
            model.choose(spotify)
            assertEquals(ImportStep.Waiting(spotify), model.step)
            assertEquals(listOf(spotify.exportUrl), opened.toList())
            model.forget()
        }
        assertTrue(server.called("importAction").isEmpty())
    }

    @Test
    fun aFileSentShowsTheServersWords() {
        octo()
        server.answer("importFile") { """"importAction":{"ok":true,"message":"Read 2 lists, 340 songs."}""" }
        val model = model()
        until { model.services != null }
        model.choose(apple)
        model.sendFile("My Library.csv", "Track name,Artist name\nAngel,Massive Attack\n".toByteArray())
        until { model.step is ImportStep.Sent }
        assertEquals(ImportStep.Sent("Read 2 lists, 340 songs.", null), model.step)
        val sent = server.called("importFile").single()
        assertEquals("POST", sent.method)
        assertEquals("My Library.csv", sent.url.queryParameter("name"))
    }

    @Test
    fun aRefusedFileKeepsTheWaitOpenWithTheServersWords() {
        octo()
        server.answer("importFile") { """"importAction":{"ok":false,"message":"No songs found. Each line should read Artist - Title."}""" }
        val model = model()
        until { model.services != null }
        model.choose(apple)
        model.sendFile("notes.txt", "hello".toByteArray())
        until { model.said != null }
        assertEquals("No songs found. Each line should read Artist - Title.", model.said)
        assertEquals(ImportStep.Waiting(apple), model.step)
    }

    @Test
    fun aFileOctoCannotReadIsNotSent() {
        octo()
        val model = model()
        until { model.services != null }
        model.useAFile()
        model.sendFile("song.mp3", byteArrayOf(1, 2, 3))
        assertEquals(NOT_A_LIST_FILE, model.said)
        model.sendFile("empty.csv", ByteArray(0))
        assertEquals(FILE_EMPTY, model.said)
        assertEquals(ImportStep.Waiting(null), model.step)
        assertTrue(server.called("importFile").isEmpty())
    }

    @Test
    fun aPastedListIsSentAsText() {
        octo()
        server.answer("importText") { """"importAction":{"ok":true,"message":"Read 1 list, 2 songs."}""" }
        val model = model()
        until { model.services != null }
        model.sendText("Massive Attack - Angel\nMGMT - Kids")
        until { model.step is ImportStep.Sent }
        assertEquals("Read 1 list, 2 songs.", (model.step as ImportStep.Sent).message)
        assertTrue(server.called("importText").single().body!!.utf8().contains("name=Pasted"))
    }

    @Test
    fun anotherServerStartsTheVisitOver() {
        octo()
        val model = model()
        until { model.services != null }
        model.choose(apple)
        model.forget()
        assertEquals(ImportStep.Choose, model.step)
        assertNull(model.services)
    }

    // ---- Approval -----------------------------------------------------------------------------

    @Test
    fun theApprovalLineNamesTheOwnerWhenItCan() {
        assertEquals("Your lists are in. Sam approves downloads before Octo fetches the missing songs.", approvalLine("Sam"))
        assertEquals("Your lists are in. The owner approves downloads before Octo fetches the missing songs.", approvalLine(null))
        assertEquals("Your lists are in. The owner approves downloads before Octo fetches the missing songs.", approvalLine("  "))
    }

    @Test
    fun theApprovalLineComesFromTheOverview() {
        assertEquals(
            "Your lists are in. Sam approves downloads before Octo fetches the missing songs.",
            ImportOverview(approval = ImportApproval(needed = true, by = "Sam")).approvalLine(),
        )
        assertEquals(
            "Your lists are in. The owner approves downloads before Octo fetches the missing songs.",
            ImportOverview(approval = ImportApproval(needed = true, by = "")).approvalLine(),
        )
        assertNull(ImportOverview(approval = ImportApproval(needed = false, by = "Sam")).approvalLine())
        assertNull(ImportOverview().approvalLine())
    }

    private fun sentWith(approval: String?): ImportStep.Sent {
        octo(approval = approval)
        server.answer("importFile") { """"importAction":{"ok":true,"message":"Read 1 list, 12 songs."}""" }
        val model = model()
        until { model.services != null }
        model.choose(apple)
        model.sendFile("Apple.csv", "Track name,Artist name\nAngel,Massive Attack\n".toByteArray())
        until { model.step is ImportStep.Sent }
        return model.step as ImportStep.Sent
    }

    @Test
    fun aMemberWhoseDownloadsWaitIsToldWhoApprovesThem() {
        assertEquals(
            ImportStep.Sent("Read 1 list, 12 songs.", "Your lists are in. Sam approves downloads before Octo fetches the missing songs."),
            sentWith("""{"needed":true,"by":"Sam"}"""),
        )
    }

    @Test
    fun anApproverWithNoNameIsTheOwner() {
        assertEquals(
            "Your lists are in. The owner approves downloads before Octo fetches the missing songs.",
            sentWith("""{"needed":true,"by":""}""").approval,
        )
    }

    @Test
    fun noApprovalInTheOverviewMeansNoLine() {
        assertNull(sentWith(null).approval)
        assertTrue(server.called("getFamily").isEmpty())
    }
}
