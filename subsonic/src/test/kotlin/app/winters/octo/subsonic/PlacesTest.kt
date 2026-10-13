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

    @Test
    fun aPositionAsksForTheNearestPlace() = runTest {
        answer(
            """{"subsonic-response":{"status":"ok","version":"1.16.1",
               "place":{"code":"97205","name":"Portland","state":"Oregon","country":"US","latitude":45.52,"longitude":-122.68}}}""",
        )
        val place = client().place(null, null, null, "", latitude = 45.5191, longitude = -122.6804)
        assertEquals(Place("97205", "Portland", "Oregon", "US", 45.52, -122.68), place)

        val url = server.takeRequest().url
        assertEquals("/rest/getPlace", url.encodedPath)
        // Only the rounded position goes, and no country when none is known.
        assertEquals("45.52", url.queryParameter("latitude"))
        assertEquals("-122.68", url.queryParameter("longitude"))
        assertNull(url.queryParameter("country"))
        assertNull(url.queryParameter("code"))
        assertNull(url.queryParameter("name"))
    }

    @Test
    fun aCodeOrNameWinsOverAPosition() {
        val params = placeParams("55401", null, null, "US", 1.0, 2.0)
        assertEquals(mapOf("code" to "55401", "country" to "US"), params)
    }
}
