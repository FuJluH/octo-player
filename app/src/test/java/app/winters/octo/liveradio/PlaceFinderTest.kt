package app.winters.octo.liveradio

import app.winters.octo.subsonic.Credentials
import app.winters.octo.subsonic.SubsonicClient
import kotlinx.coroutines.runBlocking
import mockwebserver3.MockResponse
import mockwebserver3.MockWebServer
import okhttp3.OkHttpClient
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test
import java.io.IOException

class PlaceFinderTest {
    // A place service that answers as told and remembers what it was asked.
    private class FakeService(
        private val typedAnswer: LivePlace? = null,
        private val aroundAnswer: LivePlace? = null,
        private val fails: Boolean = false,
    ) : PlaceService {
        val asked = mutableListOf<String>()

        override suspend fun typed(asked: TypedPlace, country: String): LivePlace? {
            this.asked += "typed ${asked.words} $country"
            if (fails) throw IOException("no answer")
            return typedAnswer
        }

        override suspend fun around(latitude: Double, longitude: Double): LivePlace? {
            asked += "around $latitude,$longitude"
            if (fails) throw IOException("no answer")
            return aroundAnswer
        }
    }

    private val austin = LivePlace(30.27, -97.74, "Austin, Texas", "Texas", "US")

    // A finder whose server looks places up (`server`) or does not (null).
    private fun finder(server: PlaceService?, phone: PlaceService?) =
        PlaceFinder({ server?.let { ServerRoute.Asks(it) } ?: ServerRoute.NoPlaces }, { phone }, waitMs = 2_000)

    @Test
    fun whatWasTypedIsACodeOrATownWithItsState() {
        assertEquals(TypedPlace(code = "55401"), typedPlace(" 55401 "))
        assertEquals(TypedPlace(code = "SW1A 1AA"), typedPlace("sw1a  1aa"))
        assertEquals(TypedPlace(name = "Austin", state = "Texas"), typedPlace("Austin, Texas"))
        assertEquals(TypedPlace(name = "Saint Paul"), typedPlace("Saint Paul"))
        assertEquals(TypedPlace(name = "Austin"), typedPlace("Austin,"))
        assertEquals(TypedPlace(code = "78701", name = "Austin", state = "TX"), typedPlace("Austin, TX 78701"))
        assertNull(typedPlace("   "))
    }

    @Test
    fun aServerThatListsPlacesIsAskedAndThePhoneIsNot() = runBlocking {
        val server = FakeService(typedAnswer = austin)
        val phone = FakeService(typedAnswer = LivePlace(1.0, 1.0, "Wrong"))
        val finder = this@PlaceFinderTest.finder(server, phone)
        assertEquals(PlaceSource.Server, finder.source())
        assertEquals(PlaceAnswer.Found(austin), finder.typed("Austin, Texas", "US"))
        assertEquals(listOf("typed Austin, Texas US"), server.asked)
        assertTrue(phone.asked.isEmpty())
    }

    @Test
    fun aPlaceTheServerDoesNotKnowIsNotLookedForOnThePhone() = runBlocking {
        val phone = FakeService(typedAnswer = austin)
        val finder = this@PlaceFinderTest.finder(FakeService(), phone)
        assertEquals(PlaceAnswer.NotFound(PlaceSource.Server), finder.typed("00000", "US"))
        assertTrue(phone.asked.isEmpty())
    }

    @Test
    fun aServerThatDoesNotAnswerSaysSoAndThePhoneIsNotAsked() = runBlocking {
        val phone = FakeService(typedAnswer = austin)
        val finder = this@PlaceFinderTest.finder(FakeService(fails = true), phone)
        assertEquals(PlaceAnswer.ServerDown, finder.typed("Austin", "US"))
        assertTrue(phone.asked.isEmpty())
    }

    @Test
    fun withoutPlacesOnTheServerThePhoneLooksItUp() = runBlocking {
        val phone = FakeService(typedAnswer = austin)
        val finder = this@PlaceFinderTest.finder(null, phone)
        assertEquals(PlaceSource.Phone, finder.source())
        assertEquals(PlaceAnswer.Found(austin), finder.typed("78701", "US"))
        assertEquals(listOf("typed 78701 US"), phone.asked)
        assertEquals(PlaceAnswer.NotFound(PlaceSource.Phone), finder(null, FakeService()).typed("Nowhere", "US"))
        assertEquals(PlaceAnswer.NotFound(PlaceSource.Phone), finder(null, FakeService(fails = true)).typed("Nowhere", "US"))
    }

    @Test
    fun withNoWayToLookUpPlacesTypingCannotWork() = runBlocking {
        val finder = this@PlaceFinderTest.finder(null, null)
        assertEquals(PlaceSource.None, finder.source())
        assertEquals(PlaceAnswer.NoLookup, finder.typed("Austin", "US"))
    }

    @Test
    fun aPositionIsNamedByTheServerFirst() = runBlocking {
        val named = LivePlace(30.27, -97.74, "Austin, Texas", "Texas", "US")
        val server = FakeService(aroundAnswer = named)
        val phone = FakeService(aroundAnswer = LivePlace(0.0, 0.0, "Wrong"))
        assertEquals(PlaceAnswer.Found(named), finder(server, phone).around(30.27, -97.74))
        assertEquals(listOf("around 30.27,-97.74"), server.asked)
        assertTrue(phone.asked.isEmpty())
    }

    @Test
    fun aPositionIsNamedByThePhoneWhenTheServerHasNoPlaces() = runBlocking {
        val phone = FakeService(aroundAnswer = austin)
        assertEquals(PlaceAnswer.Found(austin), finder(null, phone).around(30.27, -97.74))
    }

    @Test
    fun aPositionNoOneCanNameIsSearchedByItsRadiusAlone() = runBlocking {
        val bare = PlaceAnswer.Found(LivePlace(30.27, -97.74, "Your location"))
        assertEquals(bare, finder(FakeService(fails = true), FakeService(aroundAnswer = austin)).around(30.27, -97.74))
        assertEquals(bare, finder(FakeService(), null).around(30.27, -97.74))
        assertEquals(bare, finder(null, FakeService(fails = true)).around(30.27, -97.74))
        assertEquals(bare, finder(null, null).around(30.27, -97.74))
    }

    @Test
    fun placesAreListedByTheOctoPlacesExtension() {
        assertTrue(listsPlaces(setOf("octoRadio", "octoPlaces")))
        assertTrue(listsPlaces(setOf("octoPlaces:1")))
        assertFalse(listsPlaces(setOf("octoRadio", "octoPlacesOther")))
        assertFalse(listsPlaces(emptySet()))
    }

    @Test
    fun theNoteSaysWherePlacesAreLookedUp() {
        assertTrue(placeSourceLine(PlaceSource.Server).contains("on your Octo server"))
        assertTrue(placeSourceLine(PlaceSource.Phone).contains("by your phone's place service"))
        assertNull(placeProblemLine(PlaceAnswer.Found(austin), typed = true))
        assertTrue(placeProblemLine(PlaceAnswer.NotFound(PlaceSource.Server), typed = true)!!.startsWith("Your Octo server does not know"))
    }

    @Test
    fun theServerIsAskedForATypedCodeAndForAPosition() = runBlocking {
        MockWebServer().use { web ->
            web.start()
            val places = ServerPlaces(SubsonicClient(web.url("/"), Credentials("winters", "secret"), OkHttpClient()))
            web.enqueue(
                MockResponse.Builder().body(
                    """{"subsonic-response":{"status":"ok","version":"1.16.1",
                       "place":{"code":"78701","name":"Austin","state":"Texas","country":"US","latitude":30.2711,"longitude":-97.7437}}}""",
                ).build(),
            )
            assertEquals(LivePlace(30.27, -97.74, "Austin, Texas", "Texas", "US"), places.typed(TypedPlace(code = "78701"), "us"))
            val typed = web.takeRequest().url
            assertEquals("78701", typed.queryParameter("code"))
            assertEquals("US", typed.queryParameter("country"))

            web.enqueue(
                MockResponse.Builder().body(
                    """{"subsonic-response":{"status":"ok","version":"1.16.1",
                       "place":{"code":"78701","name":"Austin","state":"Texas","country":"US","latitude":30.2711,"longitude":-97.7437}}}""",
                ).build(),
            )
            // The phone's own rounded position is kept; the server names it.
            assertEquals(LivePlace(30.28, -97.75, "Austin, Texas", "Texas", "US"), places.around(30.28, -97.75))
            val around = web.takeRequest().url
            assertEquals("30.28", around.queryParameter("latitude"))
            assertEquals("-97.75", around.queryParameter("longitude"))
            assertNull(around.queryParameter("country"))

            web.enqueue(MockResponse.Builder().body("""{"subsonic-response":{"status":"failed","version":"1.16.1","error":{"code":70,"message":"Unknown place"}}}""").build())
            assertNull(places.around(0.5, 0.5))
        }
    }

    // Which way the server in use takes places

    private class Reads(private val answer: Set<String>?, private val fails: Boolean = false) {
        var asked = 0
        suspend fun read(): Set<String>? {
            asked++
            if (fails) throw IOException("no answer")
            return answer
        }
    }

    private val service = FakeService()

    @Test
    fun aSavedListWithPlacesAsksTheServerWithoutReadingAgain() = runBlocking {
        val reads = Reads(emptySet())
        val route = serverRoute(true, octo = true, saved = setOf("octoPlaces:1"), readAgain = reads::read, service = { service })
        assertEquals(ServerRoute.Asks(service), route)
        assertEquals(0, reads.asked)
    }

    @Test
    fun anOctoServerSavedWithoutPlacesIsAskedForItsListAgain() = runBlocking {
        val reads = Reads(setOf("octoRadio:1", "octoPlaces:1"))
        assertEquals(ServerRoute.Asks(service), serverRoute(true, octo = true, saved = emptySet(), readAgain = reads::read, service = { service }))
        assertEquals(1, reads.asked)
        // An older Octo that answers without places: the phone may look up.
        assertEquals(ServerRoute.NoPlaces, serverRoute(true, octo = true, saved = emptySet(), readAgain = Reads(setOf("octoRadio:1"))::read, service = { service }))
    }

    @Test
    fun anOctoServerThatDoesNotAnswerIsNeverPassedOverForThePhone() = runBlocking {
        assertEquals(ServerRoute.NotAnswering, serverRoute(true, octo = true, saved = emptySet(), readAgain = Reads(null, fails = true)::read, service = { service }))
        assertEquals(ServerRoute.NotAnswering, serverRoute(true, octo = true, saved = emptySet(), readAgain = Reads(null)::read, service = { service }))
        val phone = FakeService(typedAnswer = austin, aroundAnswer = austin)
        val finder = PlaceFinder({ ServerRoute.NotAnswering }, { phone })
        assertEquals(PlaceSource.Server, finder.source())
        assertEquals(PlaceAnswer.ServerDown, finder.typed("Austin, Texas", "US"))
        assertEquals(PlaceAnswer.Found(LivePlace(30.27, -97.74, "Your location")), finder.around(30.27, -97.74))
        assertTrue(phone.asked.isEmpty())
        assertEquals("Your server is not answering. Try again in a moment.", placeProblemLine(PlaceAnswer.ServerDown, typed = true))
    }

    @Test
    fun anyOtherServerOrNoneLeavesPlacesToThePhone() = runBlocking {
        val reads = Reads(setOf("octoPlaces:1"))
        assertEquals(ServerRoute.NoPlaces, serverRoute(true, octo = false, saved = emptySet(), readAgain = reads::read, service = { service }))
        assertEquals(ServerRoute.NoPlaces, serverRoute(false, octo = false, saved = emptySet(), readAgain = reads::read, service = { service }))
        assertEquals(0, reads.asked)
    }

    @Test
    fun aServerTooSlowToNameAPlaceCountsAsNotAnswering() = runBlocking {
        val slow = object : PlaceService {
            override suspend fun typed(asked: TypedPlace, country: String): LivePlace? {
                kotlinx.coroutines.delay(10_000)
                return austin
            }

            override suspend fun around(latitude: Double, longitude: Double): LivePlace? {
                kotlinx.coroutines.delay(10_000)
                return austin
            }
        }
        val finder = PlaceFinder({ ServerRoute.Asks(slow) }, { null }, waitMs = 50)
        assertEquals(PlaceAnswer.ServerDown, finder.typed("78701", "US"))
        // A position it cannot name in time is searched by its radius alone.
        assertEquals(PlaceAnswer.Found(LivePlace(30.27, -97.74, "Your location")), finder.around(30.27, -97.74))
    }
}
