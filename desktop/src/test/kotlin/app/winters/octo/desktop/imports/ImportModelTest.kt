package app.winters.octo.desktop.imports

import app.winters.octo.desktop.FakeServer
import app.winters.octo.ui.imports.ImportModel
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

// The Import page's state against a pretend Octo server: reading the
// overview and a list, passing on what was switched, and what an older Octo
// without the feature says. The list is one an older Spotify sign-in read.
class ImportModelTest {
    private val server = FakeServer()
    private val scope = CoroutineScope(Dispatchers.Default + Job())

    @After
    fun stop() {
        scope.cancel()
        server.close()
    }

    private fun model() = ImportModel({ server.client() }, scope, openUrl = {}, busyPollMs = 30, idlePollMs = 30)

    private fun until(check: () -> Boolean) = runBlocking { withTimeout(5_000) { while (!check()) delay(20) } }

    private fun overview(getMissing: Boolean = false) = server.answer(
        "getImports",
        """"imports":{"lists":[{"id":"spotify-liked","name":"Liked Songs","source":"spotifyLiked","total":3,"have":1,"missing":2,"getMissing":$getMissing,"canRefresh":true}],
        "trickle":{"state":"idle","perHour":20}}""",
        type = "octo",
    )

    @Test
    fun readsTheOverviewAndAnOpenedList() {
        overview()
        server.answer(
            "getImport",
            """"import":{"list":{"id":"spotify-liked","name":"Liked Songs"},"tracks":[{"key":"spotify:a","title":"Angel","artist":"Massive Attack","state":"missing"}]}""",
            type = "octo",
        )
        val model = model()
        model.watch()
        until { model.overview != null }
        assertEquals("Liked Songs", model.overview!!.lists.single().name)
        model.open("spotify-liked")
        until { model.detail != null }
        assertEquals("Angel", model.detail!!.tracks.single().title)
        model.close()
        assertNull(model.detail)
    }

    @Test
    fun aSwitchIsPassedOnAndTheServersWordsShown() {
        overview()
        server.answerBy("importAction") { request ->
            assertEquals("fetch", request.url.queryParameter("action"))
            assertEquals("spotify-liked", request.url.queryParameter("id"))
            assertEquals("true", request.url.queryParameter("on"))
            overview(getMissing = true)
            server.ok(""""importAction":{"ok":true,"message":"Queued 2 songs.","count":2}""", type = "octo")
        }
        val model = model()
        model.getMissing("spotify-liked", true)
        until { model.said == "Queued 2 songs." && model.overview?.lists?.single()?.getMissing == true }
        assertTrue(server.endpoints().contains("importAction"))
    }

    @Test
    fun anOlderOctoSaysItHasNoImportYet() {
        server.fail("getImports", 70, "not found")
        val model = model()
        model.watch()
        until { model.problem != null }
        assertTrue(model.problem!!.contains("Update Octo"))
    }

    @Test
    fun anotherServerForgetsEverything() {
        overview()
        val model = model()
        model.watch()
        until { model.overview != null }
        model.forget()
        assertNull(model.overview)
        assertNull(model.openId)
    }
}
