package app.winters.octo.subsonic

import kotlinx.coroutines.test.runTest
import mockwebserver3.MockResponse
import mockwebserver3.MockWebServer
import okhttp3.OkHttpClient
import org.junit.After
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Before
import org.junit.Test

class PlacesTest {
    private val server = MockWebServer()

    @Before
    fun start() = server.start()

    @After
    fun stop() = server.close()

    private fun client() = SubsonicClient(server.url("/"), Credentials("winters", "secret"), OkHttpClient())

    private fun answer(body: String) = server.enqueue(MockResponse.Builder().body(body).build())

    @Test
    fun aPostalCodeComesBackAsAPlace() = runTest {
        answer(
            """{"subsonic-response":{"status":"ok","version":"1.16.1","openSubsonic":true,
               "place":{"code":"55401","name":"Minneapolis","state":"Minnesota","country":"US","latitude":44.98,"longitude":-93.27}}}""",
        )
        val place = client().place("55401", null, null, "us")
        assertEquals(Place("55401", "Minneapolis", "Minnesota", "US", 44.98, -93.27), place)

        val url = server.takeRequest().url
        assertEquals("/rest/getPlace", url.encodedPath)
        assertEquals("55401", url.queryParameter("code"))
        assertEquals("US", url.queryParameter("country"))
        assertNull(url.queryParameter("name"))
        assertNull(url.queryParameter("state"))
    }

    @Test
    fun aCityIsAskedByNameAndState() = runTest {
        answer(
            """{"subsonic-response":{"status":"ok","version":"1.16.1",
               "place":{"name":"Austin","state":"Texas","country":"US","latitude":30.27,"longitude":-97.74}}}""",
        )
        val place = client().place(" ", " Austin ", "Texas", "US")
        assertEquals("", place?.code)
        assertEquals(30.27, place!!.latitude, 0.0)

        val url = server.takeRequest().url
        assertNull(url.queryParameter("code"))
        assertEquals("Austin", url.queryParameter("name"))
        assertEquals("Texas", url.queryParameter("state"))
        assertEquals("US", url.queryParameter("country"))
    }

    @Test
    fun aPlaceTheServerDoesNotKnowIsNull() = runTest {
        answer("""{"subsonic-response":{"status":"failed","version":"1.16.1","error":{"code":70,"message":"Octo does not know that place."}}}""")
        assertNull(client().place("00000", null, null, "US"))
    }
}
