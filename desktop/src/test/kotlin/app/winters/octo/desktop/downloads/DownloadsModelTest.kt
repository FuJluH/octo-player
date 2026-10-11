package app.winters.octo.desktop.downloads

import app.winters.octo.desktop.FakeServer
import app.winters.octo.health.FixStep
import app.winters.octo.ui.downloads.AskKind
import app.winters.octo.ui.downloads.ReplaceEnd
import app.winters.octo.ui.downloads.compareLines
import java.util.concurrent.CountDownLatch
import java.util.concurrent.TimeUnit
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.Job
import kotlinx.coroutines.cancel
import kotlinx.coroutines.delay
import kotlinx.coroutines.runBlocking
import kotlinx.coroutines.withTimeout
import org.junit.After
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test

// The downloads drawer against a pretend Octo server: asked live whether it
// keeps logs, the list, a log, Find songs and a pick.
class DownloadsModelTest {
    private val server = FakeServer()
    private val scope = CoroutineScope(Dispatchers.Default + Job())

    @After
    fun stop() {
        scope.cancel()
        server.close()
    }

    private suspend fun until(what: String, test: () -> Boolean) {
        try {
            withTimeout(5_000) { while (!test()) delay(10) }
        } catch (e: Exception) {
            throw AssertionError("timed out waiting for: $what")
        }
    }

    private fun extensions(acquisitions: String) = server.answer(
        "getOpenSubsonicExtensions",
        """"openSubsonicExtensions":[{"name":"octoAcquisitions","versions":$acquisitions},{"name":"octoLibraryActions","versions":[1,2]}]""",
        type = "octo",
    )

    private fun downloads() {
        server.answer(
            "getAcquisitions",
            """"acquisitions":{"acquisition":[{"id":"ab","artist":"Air","title":"Sexy Boy","state":"downloading","progress":0.5,"source":"Soulseek","startedAt":"2026-10-04T18:00:00Z","updatedAt":"2026-10-04T18:00:05Z","key":"soulseek:ab","kind":"download","logLines":3}]}""",
            type = "octo",
        )
        server.answer("getUpgrades", """"upgrades":[{"id":"nd-1","title":"Holocene","artist":"Bon Iver","state":"queued","updatedAt":"2026-10-04T17:59:00Z"}]""", type = "octo")
    }

    @Test
    fun aServerThatKeepsLogsListsItsDownloadsAndUpgrades() = runBlocking {
        extensions("[1,2]")
        downloads()
        val model = DownloadsModel(server.client(), scope)
        model.start()
        until("the list was read") { model.rows.value.size == 2 }
        assertEquals(true, model.supported)
        assertEquals(listOf("soulseek:ab", "upgrade:nd-1"), model.rows.value.map { it.key })
        assertEquals("Downloading from Soulseek, 50%", model.rows.value[0].status)
        model.close()
    }

    @Test
    fun anOlderServerIsNotAskedForTheList() = runBlocking {
        extensions("[1]")
        val model = DownloadsModel(server.client(), scope)
        model.start()
        until("the server said") { model.supported != null }
        assertEquals(false, model.supported)
        delay(100)
        assertTrue("getAcquisitions" !in server.endpoints())
        model.close()
    }

    @Test
    fun aServerOutOfReachAtTheStartIsAskedAgainUntilItSays() = runBlocking {
        downloads()
        var asked = 0
        server.answerBy("getOpenSubsonicExtensions") {
            asked++
            if (asked == 1) "<html>Bad gateway</html>"
            else server.ok(""""openSubsonicExtensions":[{"name":"octoAcquisitions","versions":[1,2]}]""", type = "octo")
        }
        val model = DownloadsModel(server.client(), scope, probeRetryMs = 50)
        model.start()
        until("the server said") { model.supported != null }
        assertEquals("Never taken for a no", true, model.supported)
        assertTrue(asked >= 2)
        until("the list was read") { model.rows.value.isNotEmpty() }
        model.close()
    }

    @Test
    fun aLogOpensFindSongsSearchesAndAPickFollowsItsDownload() = runBlocking {
        extensions("[1,2]")
        downloads()
        server.answer(
            "getAcquisition",
            """"acquisition":{"id":"ab","title":"Sexy Boy","state":"failed","key":"soulseek:ab","event":[{"at":"2026-10-04T18:00:00Z","kind":"queued","text":"Asked for"},{"at":"2026-10-04T18:00:09Z","kind":"failed","text":"Could not get it","detail":"No copy fits"}]}""",
            type = "octo",
        )
        val model = DownloadsModel(server.client(), scope)
        model.start()
        model.showLog("soulseek:ab")
        until("the log was read") { model.log.value?.event?.size == 2 }
        assertEquals(DrawerView.Log("soulseek:ab"), model.view)

        server.answer("findSongs", """"foundSongs":{"id":"f1","state":"searching","song":{"title":"Sexy Boy","artist":"Air"}}""", type = "octo")
        server.answer(
            "getFoundSongs",
            """"foundSongs":{"id":"f1","state":"done","song":{"title":"Sexy Boy","artist":"Air"},"candidate":[{"source":"Soulseek","peer":"p1","file":"Sexy Boy.flac","format":"flac","rank":1,"index":0,"id":"c-1"}]}""",
            type = "octo",
        )
        model.find("ab", "Sexy Boy", from = "soulseek:ab")
        until("the search ended") { model.found.value?.state == "done" }
        assertEquals("ab", server.calls.last { it.url.pathSegments.last() == "findSongs" }.url.queryParameter("id"))

        server.answer("pickFoundSong", """"pick":{"state":"queued","detail":"Getting FLAC from p1.","key":"soulseek:ab"}""", type = "octo")
        model.pick("f1", model.found.value!!.candidate.single())
        until("the pick opened its log") { model.view == DrawerView.Log("soulseek:ab") }
        val pick = server.calls.last { it.url.pathSegments.last() == "pickFoundSong" }
        assertEquals("f1", pick.url.queryParameter("search"))
        assertEquals("c-1", pick.url.queryParameter("copy"))
        model.close()
    }

    @Test
    fun aPickAnsweredAfterTheDrawerClosedLeavesItClosed() = runBlocking {
        extensions("[1,2]")
        downloads()
        server.answer("findSongs", """"foundSongs":{"id":"f1","state":"done","song":{"title":"Sexy Boy","artist":"Air"},"candidate":[{"source":"Soulseek","peer":"p1","index":0,"id":"c-1"}]}""", type = "octo")
        val answer = CountDownLatch(1)
        server.answerBy("pickFoundSong") {
            answer.await(5, TimeUnit.SECONDS)
            server.ok(""""pick":{"state":"queued","detail":"Getting it.","key":"soulseek:ab"}""", type = "octo")
        }
        val model = DownloadsModel(server.client(), scope)
        model.start()
        model.open = true
        model.find("ab", "Sexy Boy")
        until("the search ended") { model.found.value?.state == "done" }

        model.pick("f1", model.found.value!!.candidate.single())
        until("the pick was sent") { "pickFoundSong" in server.endpoints() }
        model.open = false
        answer.countDown()
        delay(300)
        assertEquals(DrawerView.List, model.view)
        assertTrue("No log is followed", "getAcquisition" !in server.endpoints())
        model.close()
    }

    private val question = "Yours looks like a live recording and this copy is the plain song. Replace yours anyway?"

    // A finished search for a song in the library, with one copy, on a
    // server listing octoAcquisitions at `acquisitions`. The server asks
    // about any pick sent with anyway=false and takes the rest.
    // What the server answers a library song's first pick: "confirm" or "ready".
    private var ask = "confirm"

    // Replacements that ended, as the app heard them.
    private val ends = java.util.concurrent.CopyOnWriteArrayList<ReplaceEnd>()

    private suspend fun pickReady(acquisitions: String): DownloadsModel {
        extensions(acquisitions)
        downloads()
        server.answer(
            "findSongs",
            """"foundSongs":{"id":"f1","state":"done","song":{"title":"Holocene","artist":"Bon Iver","libraryId":"nd-1"},"candidate":[{"source":"Soulseek","peer":"p1","format":"flac","index":0,"id":"c-1"}]}""",
            type = "octo",
        )
        server.answerBy("pickFoundSong") { request ->
            if (request.url.queryParameter("anyway") == "false") {
                val detail = if (ask == "confirm") "\"$question\"" else "null"
                server.ok(
                    """"pick":{"state":"$ask","detail":$detail,"key":null,"compare":{"yours":{"quality":"FLAC","length":420,"take":"live recording"},"copy":{"quality":"FLAC","length":298,"take":"the plain song"}}}""",
                    type = "octo",
                )
            } else {
                server.ok(""""pick":{"state":"queued","detail":"Getting FLAC from p1.","key":"soulseek:ho"}""", type = "octo")
            }
        }
        val model = DownloadsModel(server.client(), scope, ended = { ends += it })
        model.start()
        until("the server said") { model.supported != null }
        model.open = true
        model.find("nd-1", "Holocene")
        until("the search ended") { model.found.value?.state == "done" }
        return model
    }

    private fun picks() = server.calls.filter { it.url.pathSegments.last() == "pickFoundSong" }

    @Test
    fun aServerThatAsksFirstGetsAnywayFalse_AndReplaceAnywaySendsTheSameCopy() = runBlocking {
        val model = pickReady("[1,2,3]")
        assertTrue(model.asksFirst)
        model.pick("f1", model.found.value!!.candidate.single())
        until("the question came") { model.question.value != null }
        assertEquals(question, model.question.value!!.words)
        assertEquals("c-1", model.question.value!!.copy.id)
        assertNull("A question is not a refusal", model.picked.value)
        assertEquals(DrawerView.Find("nd-1", "Holocene"), model.view)
        assertEquals("false", picks().single().url.queryParameter("anyway"))

        assertEquals(listOf("Yours: FLAC, 7:00, live recording", "This copy: FLAC, 4:58, the plain song"), compareLines(model.question.value!!.compare))

        // Yes: sent once with anyway=true, and the copy's row shows it replacing.
        model.replaceAnyway()
        model.replaceAnyway()
        until("the copy is replacing") { "nd-1" in model.replacing.value }
        assertNull(model.question.value)
        assertEquals("The drawer stays on the copies", DrawerView.Find("nd-1", "Holocene"), model.view)
        val again = picks().last()
        assertEquals(2, picks().size)
        assertEquals("true", again.url.queryParameter("anyway"))
        assertEquals("f1", again.url.queryParameter("search"))
        assertEquals("c-1", again.url.queryParameter("copy"))
        assertEquals("id:c-1", model.replacing.value["nd-1"]!!.copyKey)

        // The server swaps it in: the app hears it once, with the take named.
        server.answer("getUpgrades", """"upgrades":[{"id":"nd-1","title":"Holocene","artist":"Bon Iver","state":"upgraded","updatedAt":"${java.time.Instant.now()}"}]""", type = "octo")
        model.wake()
        until("the replacement ended") { ends.isNotEmpty() }
        val end = ends.single() as ReplaceEnd.Replaced
        assertEquals("Replaced with the plain song", end.words)
        assertEquals(FixStep.Restore("nd-1", "Holocene", replaced = true), end.putBack)
        assertTrue(model.replacing.value.isEmpty())
        model.close()
    }

    @Test
    fun aBetterCopyIsAskedTheUsualWay_AndAFailedReplaceSaysYourCopyWasKept() = runBlocking {
        ask = "ready"
        val model = pickReady("[1,2,3]")
        model.pick("f1", model.found.value!!.candidate.single())
        until("the question came") { model.question.value != null }
        assertEquals(AskKind.Ready, model.question.value!!.kind)
        assertEquals("false", picks().single().url.queryParameter("anyway"))

        model.replaceAnyway()
        until("the copy is replacing") { "nd-1" in model.replacing.value }
        assertEquals("true", picks().last().url.queryParameter("anyway"))
        server.answer(
            "getUpgrades",
            """"upgrades":[{"id":"nd-1","title":"Holocene","state":"failed","detail":"The copy you picked was not the right recording, so it was thrown away. Your copy was kept.","updatedAt":"${java.time.Instant.now()}"}]""",
            type = "octo",
        )
        model.wake()
        until("the replacement ended") { ends.isNotEmpty() }
        assertEquals(
            "The copy you picked was not the right recording, so it was thrown away. Your copy was kept. Details are in Downloads.",
            ends.single().words,
        )
        model.close()
    }

    @Test
    fun keepMineSendsNothing() = runBlocking {
        val model = pickReady("[1,2,3]")
        model.pick("f1", model.found.value!!.candidate.single())
        until("the question came") { model.question.value != null }

        model.keepMine()
        assertNull(model.question.value)
        model.replaceAnyway()
        delay(200)
        assertEquals("Only the first pick was sent", 1, picks().size)
        assertEquals(DrawerView.Find("nd-1", "Holocene"), model.view)
        assertEquals(1, model.found.value!!.candidate.size)
        model.close()
    }

    @Test
    fun anOlderServerIsNeverSentAnyway() = runBlocking {
        val model = pickReady("[1,2]")
        assertFalse(model.asksFirst)
        model.pick("f1", model.found.value!!.candidate.single())
        until("the pick opened its log") { model.view == DrawerView.Log("soulseek:ho") }
        assertNull(picks().single().url.queryParameter("anyway"))
        assertNull(model.question.value)
        model.close()
    }
}
