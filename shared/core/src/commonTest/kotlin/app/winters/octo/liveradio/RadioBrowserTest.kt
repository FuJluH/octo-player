package app.winters.octo.liveradio

import kotlinx.coroutines.cancelAndJoin
import kotlinx.coroutines.launch
import kotlinx.coroutines.test.runTest
import mockwebserver3.Dispatcher
import mockwebserver3.MockResponse
import mockwebserver3.MockWebServer
import mockwebserver3.RecordedRequest
import okhttp3.OkHttpClient
import org.junit.After
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Before
import org.junit.Test

// Finding live radio around a place, always against a local stand-in for
// the catalog, never the real one.
class RadioBrowserTest {
    private val server = MockWebServer()
    private val asked = mutableListOf<RecordedRequest>()
    private var clock = 0L

    private fun station(uuid: String, name: String, distance: Double? = null, clicks: Int = 0, state: String = "California", codec: String = "MP3", ok: Int = 1) =
        """{"stationuuid":"$uuid","name":"$name","url":"http://x/$uuid","url_resolved":"http://s/$uuid","favicon":"http://f/$uuid.png","codec":"$codec","bitrate":128,"hls":0,""" +
            """"country":"The United States Of America","countrycode":"US","state":"$state","tags":"jazz,news, jazz","homepage":"https://$uuid.example/ ","clickcount":$clicks,"lastcheckok":$ok""" +
            (distance?.let { ""","geo_distance":$it""" } ?: "") + "}"

    private var nearBody = "[]"
    private var regionalBody = "[]"

    @Before
    fun start() {
        server.dispatcher = object : Dispatcher() {
            override fun dispatch(request: RecordedRequest): MockResponse {
                asked += request
                val url = request.url
                return when {
                    url.encodedPath == "/json/stations/search" && url.queryParameter("geo_lat") != null -> ok(nearBody)
                    url.encodedPath == "/json/stations/search" -> ok(regionalBody)
                    url.encodedPath.startsWith("/json/url/") -> ok("""{"ok":true}""")
                    else -> MockResponse.Builder().code(404).build()
                }
            }
        }
        server.start()
    }

    @After
    fun stop() = server.close()

    private fun ok(body: String) = MockResponse.Builder().code(200).body(body).build()

    private fun catalog() = RadioBrowser(OkHttpClient(), "Octo/test (Android)", servers = { listOf(server.url("/").toString()) }, now = { clock })

    private val sf = LivePlace(37.774929, -122.419416, "San Francisco", state = "California", countryCode = "US")

    @Test
    fun stationsNearAPlaceComeNearestFirstThenTheUnplacedMostPlayedFirst() = runTest {
        nearBody = "[${station("a", "KQED", 9094.3, 50)},${station("b", "KDFC", 807.7, 10)}]"
        regionalBody = "[${station("b", "KDFC", null, 10)},${station("c", "Quiet FM", null, 5)},${station("d", "Loud FM", null, 90)}]"
        val found = catalog().near(sf, 40_000.0, LiveSort.Distance)
        assertEquals(listOf("b", "a", "d", "c"), found.map { it.uuid })
        assertEquals(listOf("jazz", "news"), found[0].tags)
        assertEquals("https://${found[0].uuid}.example/", found[0].homepage)
        assertEquals("http://s/b", found[0].streamUrl)
    }

    @Test
    fun aStationOfTheStateThatIsPlacedOutsideTheCircleIsLeftOut() = runTest {
        nearBody = "[${station("a", "KQED", 9094.3, 50)}]"
        val farButPlaced = station("far", "Far FM", null, 99).dropLast(1) + ""","geo_lat":34.05,"geo_long":-118.24}"""
        regionalBody = "[$farButPlaced,${station("c", "Unplaced FM", null, 5)}]"
        assertEquals(listOf("a", "c"), catalog().near(sf, 40_000.0, LiveSort.Distance).map { it.uuid })
    }

    @Test
    fun theMostPlayedComeFirstWhenAsked() = runTest {
        nearBody = "[${station("a", "KQED", 9094.3, 50)},${station("b", "KDFC", 807.7, 10)}]"
        assertEquals(listOf("a", "b"), catalog().near(sf, 40_000.0, LiveSort.Popular).map { it.uuid })
    }

    @Test
    fun onlyTheRoundedPlaceIsSentWithTheAppsName() = runTest {
        catalog().near(sf, 40_233.6, LiveSort.Distance)
        val geo = asked.first { it.url.queryParameter("geo_lat") != null }
        assertEquals("37.77", geo.url.queryParameter("geo_lat"))
        assertEquals("-122.42", geo.url.queryParameter("geo_long"))
        assertEquals("40234", geo.url.queryParameter("geo_distance"))
        assertEquals("true", geo.url.queryParameter("hidebroken"))
        assertEquals("Octo/test (Android)", geo.headers["User-Agent"])
        val regional = asked.first { it.url.queryParameter("countrycode") != null }
        assertEquals("California", regional.url.queryParameter("state"))
    }

    @Test
    fun answersAreKeptForSixHours() = runTest {
        val radio = catalog()
        radio.near(sf, 40_000.0, LiveSort.Distance)
        val first = asked.size
        clock = 5 * 60 * 60 * 1000L
        radio.near(sf, 40_000.0, LiveSort.Popular)
        assertEquals("kept", first, asked.size)
        clock = 7 * 60 * 60 * 1000L
        radio.near(sf, 40_000.0, LiveSort.Distance)
        assertTrue("asked again", asked.size > first)
    }

    @Test
    fun stationsThisAppCannotPlayOrThatAreDownAreLeftOut() = runTest {
        nearBody = "[${station("a", "Ogg FM", 10.0, codec = "OGG")},${station("b", "MP3 FM", 20.0)},${station("c", "Down FM", 30.0, ok = 0)}]"
        val found = catalog().near(sf, 40_000.0, LiveSort.Distance) { it.codec != "OGG" }
        assertEquals(listOf("b"), found.map { it.uuid })
    }

    @Test
    fun aPlaceWithNoCountryIsOnlySearchedAround() = runTest {
        catalog().near(LivePlace(51.5, -0.12, "Somewhere"), 10_000.0, LiveSort.Distance)
        assertTrue(asked.none { it.url.queryParameter("countrycode") != null })
    }

    @Test
    fun aPlaceWithNoCoordinatesIsSearchedByItsStateOnly() = runTest {
        regionalBody = "[${station("c", "Quiet FM", null, 5, state = "Texas")}]"
        val found = catalog().near(LivePlace(0.0, 0.0, "Austin", state = "Texas", countryCode = "US"), 40_000.0, LiveSort.Distance)
        assertEquals(listOf("c"), found.map { it.uuid })
        assertTrue(asked.none { it.url.queryParameter("geo_lat") != null })
        assertEquals("Texas", asked.single().url.queryParameter("state"))
    }

    @Test
    fun aServerAnsweringSomethingElseIsLeftForAnother() = runTest {
        nearBody = "<html>busy</html>"
        var asks = 0
        val radio = RadioBrowser(OkHttpClient(), "Octo/test (Android)", servers = { asks++; listOf(server.url("/").toString()) }, now = { clock })
        assertTrue(runCatching { radio.near(sf, 40_000.0, LiveSort.Distance) }.exceptionOrNull() is java.io.IOException)
        nearBody = "[]"
        radio.near(sf, 40_000.0, LiveSort.Distance)
        assertEquals("a server was picked again", 2, asks)
    }

    @Test
    fun aStartedStationIsCounted() = runTest {
        catalog().started("abc-123")
        assertEquals("/json/url/abc-123", asked.single().url.encodedPath)
    }

    @Test
    fun aStationWithNoStreamIsLeftOut() {
        assertNull(CatalogStation(uuid = "x", name = "Nothing").toLive())
        assertEquals("http://plain", CatalogStation(uuid = "y", url = "http://plain").toLive()!!.streamUrl)
    }

    @Test
    fun aStateIsAskedForByItsExactNameAndCheckedAgain() = runTest {
        val kansas = LivePlace(39.05, -95.68, "Topeka, Kansas", state = "Kansas", countryCode = "US")
        regionalBody = "[${station("k", "Kansas FM", null, 5, state = "kansas")},${station("a", "Arkansas FM", null, 50, state = "Arkansas")}]"
        val found = catalog().near(kansas, 40_000.0, LiveSort.Distance)
        assertEquals(listOf("k"), found.map { it.uuid })
        val regional = asked.first { it.url.queryParameter("countrycode") != null }
        assertEquals("Kansas", regional.url.queryParameter("state"))
        assertEquals("true", regional.url.queryParameter("stateExact"))
    }

    @Test
    fun aPlaceWithNoStateIsNotAskedForAnExactOne() = runTest {
        catalog().near(LivePlace(51.5, -0.12, "London", countryCode = "GB"), 10_000.0, LiveSort.Distance)
        val regional = asked.first { it.url.queryParameter("countrycode") != null }
        assertNull(regional.url.queryParameter("state"))
        assertNull(regional.url.queryParameter("stateExact"))
    }

    @Test
    fun aFailingServerIsLeftForAnotherWithinTheSameAsk() = runTest {
        MockWebServer().use { broken ->
            broken.dispatcher = object : Dispatcher() {
                override fun dispatch(request: RecordedRequest): MockResponse = MockResponse.Builder().code(503).build()
            }
            broken.start()
            nearBody = "[${station("a", "KQED", 9094.3, 50)}]"
            val radio = RadioBrowser(
                OkHttpClient(),
                "Octo/test (Android)",
                servers = { listOf(broken.url("/").toString(), server.url("/").toString()) },
                now = { clock },
                pick = { it.first() },
            )
            assertEquals(listOf("a"), radio.near(sf, 40_000.0, LiveSort.Distance).map { it.uuid })
            assertTrue("the broken server was tried first", broken.requestCount > 0)
        }
    }

    @Test
    fun withNoOtherServerTheAskFails() = runTest {
        nearBody = "<html>busy</html>"
        assertTrue(runCatching { catalog().near(sf, 40_000.0, LiveSort.Distance) }.exceptionOrNull() is java.io.IOException)
    }

    @Test
    fun staleAnswersAreLetGo() = runTest {
        val radio = catalog()
        radio.near(sf, 40_000.0, LiveSort.Distance)
        radio.near(sf, 80_000.0, LiveSort.Distance)
        assertEquals(2, radio.keptCount())
        clock = 7 * 60 * 60 * 1000L
        radio.near(sf, 10_000.0, LiveSort.Distance)
        assertEquals(1, radio.keptCount())
    }

    @Test
    fun cancellingAnAskStopsItsRequest() {
        MockWebServer().use { slow ->
            slow.dispatcher = object : Dispatcher() {
                override fun dispatch(request: RecordedRequest): MockResponse =
                    MockResponse.Builder().code(200).body("[]").headersDelay(10, java.util.concurrent.TimeUnit.SECONDS).build()
            }
            slow.start()
            val radio = RadioBrowser(OkHttpClient(), "Octo/test (Android)", servers = { listOf(slow.url("/").toString()) }, now = { clock })
            val took = kotlin.system.measureTimeMillis {
                kotlinx.coroutines.runBlocking {
                    val ask = launch(kotlinx.coroutines.Dispatchers.IO) { radio.near(sf, 40_000.0, LiveSort.Distance) }
                    kotlinx.coroutines.delay(300)
                    ask.cancelAndJoin()
                }
            }
            assertTrue("cancelled in $took ms", took < 5_000)
        }
    }
}
