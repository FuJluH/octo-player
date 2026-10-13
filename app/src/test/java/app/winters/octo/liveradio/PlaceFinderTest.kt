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

    @Test
    fun whatWasTypedIsACodeOrATownWithItsState() {
        assertEquals(TypedPlace(code = "55401"), typedPlace(" 55401 "))
        assertEquals(TypedPlace(code = "SW1A 1AA"), typedPlace("sw1a  1aa"))
        assertEquals(TypedPlace(name = "Austin", state = "Texas"), typedPlace("Austin, Texas"))
        assertEquals(TypedPlace(name = "Saint Paul"), typedPlace("Saint Paul"))
        assertEquals(TypedPlace(name = "Austin"), typedPlace("Austin,"))
        assertNull(typedPlace("   "))
    }

    @Test
    fun aServerThatListsPlacesIsAskedAndThePhoneIsNot() = runBlocking {
        val server = FakeService(typedAnswer = austin)
        val phone = FakeService(typedAnswer = LivePlace(1.0, 1.0, "Wrong"))
        val finder = PlaceFinder({ server }, { phone })
        assertEquals(PlaceSource.Server, finder.source())
        assertEquals(PlaceAnswer.Found(austin), finder.typed("Austin, Texas", "US"))
        assertEquals(listOf("typed Austin, Texas US"), server.asked)
        assertTrue(phone.asked.isEmpty())
    }

    @Test
    fun aPlaceTheServerDoesNotKnowIsNotLookedForOnThePhone() = runBlocking {
        val phone = FakeService(typedAnswer = austin)
        val finder = PlaceFinder({ FakeService() }, { phone })
        assertEquals(PlaceAnswer.NotFound(PlaceSource.Server), finder.typed("00000", "US"))
        assertTrue(phone.asked.isEmpty())
    }

    @Test
    fun aServerThatDoesNotAnswerSaysSoAndThePhoneIsNotAsked() = runBlocking {
        val phone = FakeService(typedAnswer = austin)
        val finder = PlaceFinder({ FakeService(fails = true) }, { phone })
        assertEquals(PlaceAnswer.ServerDown, finder.typed("Austin", "US"))
        assertTrue(phone.asked.isEmpty())
    }

    @Test
    fun withoutPlacesOnTheServerThePhoneLooksItUp() = runBlocking {
        val phone = FakeService(typedAnswer = austin)
        val finder = PlaceFinder({ null }, { phone })
        assertEquals(PlaceSource.Phone, finder.source())
        assertEquals(PlaceAnswer.Found(austin), finder.typed("78701", "US"))
        assertEquals(listOf("typed 78701 US"), phone.asked)
        assertEquals(PlaceAnswer.NotFound(PlaceSource.Phone), PlaceFinder({ null }, { FakeService() }).typed("Nowhere", "US"))
        assertEquals(PlaceAnswer.NotFound(PlaceSource.Phone), PlaceFinder({ null }, { FakeService(fails = true) }).typed("Nowhere", "US"))
    }

    @Test
    fun withNoWayToLookUpPlacesTypingCannotWork() = runBlocking {
        val finder = PlaceFinder({ null }, { null })
        assertEquals(PlaceSource.None, finder.source())
        assertEquals(PlaceAnswer.NoLookup, finder.typed("Austin", "US"))
    }

    @Test
    fun aPositionIsNamedByTheServerFirst() = runBlocking {
        val named = LivePlace(30.27, -97.74, "Austin, Texas", "Texas", "US")
        val server = FakeService(aroundAnswer = named)
        val phone = FakeService(aroundAnswer = LivePlace(0.0, 0.0, "Wrong"))
        assertEquals(PlaceAnswer.Found(named), PlaceFinder({ server }, { phone }).around(30.27, -97.74))
        assertEquals(listOf("around 30.27,-97.74"), server.asked)
        assertTrue(phone.asked.isEmpty())
    }

    @Test
    fun aPositionIsNamedByThePhoneWhenTheServerHasNoPlaces() = runBlocking {
        val phone = FakeService(aroundAnswer = austin)
        assertEquals(PlaceAnswer.Found(austin), PlaceFinder({ null }, { phone }).around(30.27, -97.74))
    }

    @Test
    fun aPositionNoOneCanNameIsSearchedByItsRadiusAlone() = runBlocking {
        val bare = PlaceAnswer.Found(LivePlace(30.27, -97.74, "Your location"))
        assertEquals(bare, PlaceFinder({ FakeService(fails = true) }, { FakeService(aroundAnswer = austin) }).around(30.27, -97.74))
        assertEquals(bare, PlaceFinder({ FakeService() }, { null }).around(30.27, -97.74))
        assertEquals(bare, PlaceFinder({ null }, { FakeService(fails = true) }).around(30.27, -97.74))
        assertEquals(bare, PlaceFinder({ null }, { null }).around(30.27, -97.74))
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
}
