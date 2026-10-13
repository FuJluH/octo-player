package app.winters.octo.serverupdate

import app.winters.octo.subsonic.Credentials
import app.winters.octo.subsonic.SubsonicClient
import kotlinx.coroutines.runBlocking
import mockwebserver3.MockResponse
import mockwebserver3.MockWebServer
import okhttp3.HttpUrl.Companion.toHttpUrl
import okhttp3.OkHttpClient
import org.junit.After
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Before
import org.junit.Test
import java.util.concurrent.TimeUnit

class ServerUpdateHttpTest {
    private val server = MockWebServer()
    private val http = OkHttpClient()

    @Before
    fun start() = server.start()

    @After
    fun stop() = server.close()

    private val client get() = SubsonicClient(server.url("/"), Credentials("winters", "secret"), http)

    private fun calls(headers: Map<String, String> = emptyMap()) = ServerUpdateHttp(http) { ownAddresses(client, headers) }

    private val answer =
        """{"enabled":true,"repo":"winters27/octo","running":"2026.10.11","latest":{"tag":"2026.10.13"},"newer":[{"tag":"2026.10.13"}],"updateAvailable":true,"standing":"behind","helper":{"installed":true,"mode":"image","outdated":false},"pending":false,"run":null}"""

    @Test
    fun readsSignedFromTheServersOwnAddress() = runBlocking {
        server.enqueue(MockResponse.Builder().body(answer).build())
        val read = calls(mapOf("CF-Access-Client-Id" to "id")).read() as UpdateRead.Answered
        assertEquals("2026.10.13", read.status.latest?.tag)
        val request = server.takeRequest()
        assertEquals("/api/admin/update", request.url.encodedPath)
        assertEquals("winters", request.url.queryParameter("u"))
        assertEquals("id", request.headers["CF-Access-Client-Id"])
        assertNull(request.headers["X-Octo-Admin"])
    }

    @Test
    fun aListenerOrAnOlderServerIsNotOffered() = runBlocking {
        for (code in listOf(401, 403, 404)) {
            server.enqueue(MockResponse.Builder().code(code).body("{}").build())
            assertEquals(UpdateRead.NotOffered, calls().read())
        }
    }

    @Test
    fun aGatewayErrorOrAPageIsNoAnswer() = runBlocking {
        server.enqueue(MockResponse.Builder().code(502).body("Bad gateway").build())
        assertEquals(UpdateRead.NoAnswer, calls().read())
        server.enqueue(MockResponse.Builder().body("<html>restarting</html>").build())
        assertEquals(UpdateRead.NoAnswer, calls().read())
    }

    @Test
    fun aConnectionThatHangsIsDropped() = runBlocking {
        server.enqueue(MockResponse.Builder().body(answer).headersDelay(60, TimeUnit.SECONDS).build())
        val began = System.nanoTime()
        assertEquals(UpdateRead.NoAnswer, calls().read())
        val tookMs = (System.nanoTime() - began) / 1_000_000
        assertTrue("took $tookMs ms", tookMs < UPDATE_CALL_TIMEOUT_MS + 3_000)
    }

    @Test
    fun startsWithTheAdminHeaderAndTheTag() = runBlocking {
        server.enqueue(MockResponse.Builder().code(202).body("""{"ok":true,"id":"r1","tag":"2026.10.13"}""").build())
        assertEquals(UpdateStart.Started("r1", "2026.10.13"), calls().start("2026.10.13"))
        val request = server.takeRequest()
        assertEquals("POST", request.method)
        assertEquals("1", request.headers["X-Octo-Admin"])
        assertEquals("""{"tag":"2026.10.13"}""", request.body?.utf8())
    }

    @Test
    fun aRefusalCarriesTheServersWords() = runBlocking {
        server.enqueue(MockResponse.Builder().code(409).body("""{"error":"An update is already under way."}""").build())
        assertEquals(UpdateStart.Refused("An update is already under way."), calls().start("2026.10.13"))
    }

    @Test
    fun theSignInGoesOnlyToTheServersOwnAddresses() {
        val place = ownAddresses(client)
        val own = place.sign("${server.url("/")}api/admin/update".toHttpUrl())
        assertEquals("winters", own.queryParameter("u"))
        val other = place.sign("https://example.com/api/admin/update".toHttpUrl())
        assertNull(other.queryParameter("u"))
        assertNull(other.queryParameter("t"))
        assertNull(other.queryParameter("p"))
    }

    @Test
    fun nowhereToAskIsNoAnswer() = runBlocking {
        assertEquals(UpdateRead.NoAnswer, ServerUpdateHttp(http) { null }.read())
        assertTrue(ServerUpdateHttp(http) { null }.start("2026.10.13") is UpdateStart.Refused)
    }
}
