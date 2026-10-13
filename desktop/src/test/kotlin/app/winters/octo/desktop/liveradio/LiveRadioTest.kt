package app.winters.octo.desktop.liveradio

import app.winters.octo.desktop.FakeServer
import app.winters.octo.desktop.player.PlayerState
import app.winters.octo.desktop.player.QueueEntry
import app.winters.octo.desktop.queue.serverQueueOf
import app.winters.octo.desktop.settings.AppSettings
import app.winters.octo.desktop.settings.LiveRadioPrefs
import app.winters.octo.desktop.settings.SettingsStore
import app.winters.octo.liveradio.KeptStations
import app.winters.octo.liveradio.LivePlace
import app.winters.octo.liveradio.LiveSort
import app.winters.octo.liveradio.LiveStation
import app.winters.octo.liveradio.MILE_METERS
import app.winters.octo.liveradio.RadioBrowser
import app.winters.octo.playback.isRadio
import app.winters.octo.playback.radioOf
import app.winters.octo.subsonic.OCTO_PLACES
import app.winters.octo.subsonic.Place
import app.winters.octo.subsonic.RadioStation
import app.winters.octo.subsonic.Song
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.runBlocking
import mockwebserver3.Dispatcher
import mockwebserver3.MockResponse
import mockwebserver3.MockWebServer
import mockwebserver3.RecordedRequest
import okhttp3.OkHttpClient
import org.junit.After
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Rule
import org.junit.Test
import org.junit.rules.TemporaryFolder
import java.io.File
import java.util.Locale
import java.util.concurrent.CopyOnWriteArrayList
import kotlin.math.roundToInt

class LiveRadioTest {
    @get:Rule val folder = TemporaryFolder()

    private val server = FakeServer()

    // A stand-in for the radio catalog, never the real one.
    private val catalog = MockWebServer()
    private val asked = CopyOnWriteArrayList<RecordedRequest>()
    private var catalogDown = false

    private fun station(uuid: String, name: String, distance: Double?, state: String = "Minnesota") =
        """{"stationuuid":"$uuid","name":"$name","url_resolved":"http://s/$uuid","favicon":"","codec":"MP3","bitrate":128,"hls":0,""" +
            """"country":"The United States Of America","countrycode":"US","state":"$state","tags":"jazz","clickcount":3,"lastcheckok":1""" +
            (distance?.let { ""","geo_distance":$it""" } ?: "") + "}"

    init {
        catalog.dispatcher = object : Dispatcher() {
            override fun dispatch(request: RecordedRequest): MockResponse {
                asked += request
                if (catalogDown) return MockResponse.Builder().code(503).build()
                val body = if (request.url.queryParameter("geo_lat") != null) "[${station("a", "KBEM", 1200.0)}]" else "[${station("b", "Texas Public", null, request.url.queryParameter("state") ?: "Texas")}]"
                return MockResponse.Builder().body(body).build()
            }
        }
        catalog.start()
    }

    @After
    fun stop() {
        server.close()
        catalog.close()
    }

    private fun store() = SettingsStore(File(folder.root, SettingsStore.FILE_NAME))

    private fun model(settings: SettingsStore, extensions: List<String>): LiveRadioModel {
        val connection = server.connection(extensions)
        return LiveRadioModel(
            settings,
            RadioBrowser(OkHttpClient(), "Octo/test (desktop)", servers = { listOf(catalog.url("/").toString()) }),
            { connection },
            CoroutineScope(Dispatchers.Unconfined),
            homeCountry = "US",
        )
    }

    private fun waitFor(what: () -> Boolean) {
        val until = System.currentTimeMillis() + 5_000
        while (!what() && System.currentTimeMillis() < until) Thread.sleep(20)
        assertTrue("waited too long", what())
    }

    // The Where field

    @Test
    fun wordsWithADigitAreAPostalCode() {
        assertEquals(WhereAsked(code = "55401", country = "US"), whereOf(" 55401 ", "us"))
        assertEquals(WhereAsked(code = "SW1A 1AA", country = "GB"), whereOf("sw1a 1aa", "GB"))
    }

    @Test
    fun anythingElseIsACityWithItsStateAfterAComma() {
        assertEquals(WhereAsked(name = "Austin", state = "Texas", country = "US"), whereOf("Austin, Texas", "US"))
        assertEquals(WhereAsked(name = "Lyon", country = "FR"), whereOf("Lyon", "fr"))
        assertNull(whereOf("   ", "US"))
        assertNull(whereOf(", Texas", "US"))
    }

    // Finding the place

    @Test
    fun theServerFindsAPostalCode() = runBlocking {
        val answer = resolvePlace(WhereAsked(code = "55401", country = "US")) { Place("55401", "Minneapolis", "Minnesota", "US", 44.98, -93.27) }
        assertEquals(PlaceAnswer.Found(LivePlace(44.98, -93.27, "Minneapolis, Minnesota", "Minnesota", "US")), answer)
    }

    @Test
    fun aPlaceTheServerDoesNotKnowSaysSo() = runBlocking {
        assertEquals(PlaceAnswer.Problem(UNKNOWN_PLACE), resolvePlace(WhereAsked(code = "00000", country = "US")) { null })
    }

    @Test
    fun withoutTheServerACityGoesToTheCatalogByItsState() = runBlocking {
        assertEquals(PlaceAnswer.Found(LivePlace(0.0, 0.0, "Austin, Texas", "Texas", "US")), resolvePlace(WhereAsked(name = "Austin", state = "Texas", country = "US"), null))
        // With no state typed, the city stands for it.
        assertEquals(PlaceAnswer.Found(LivePlace(0.0, 0.0, "London", "London", "GB")), resolvePlace(WhereAsked(name = "London", country = "GB"), null))
    }

    @Test
    fun withoutTheServerAPostalCodeCannotBeUsed() = runBlocking {
        assertEquals(PlaceAnswer.Problem(NO_POSTAL_LOOKUP), resolvePlace(WhereAsked(code = "55401", country = "US"), null))
    }

    @Test
    fun aServerWithPlacesIsAskedAndTheCatalogSearchesAroundIt() {
        server.answer("getPlace", """"place":{"code":"55401","name":"Minneapolis","state":"Minnesota","country":"US","latitude":44.98,"longitude":-93.27}""")
        val settings = store()
        val model = model(settings, listOf("$OCTO_PLACES:1"))
        model.lookUp("55401", "US")
        waitFor { model.find is LiveFind.Found }
        val found = model.find as LiveFind.Found
        assertEquals("Minneapolis, Minnesota", found.place.label)
        assertEquals(listOf("a", "b"), found.stations.map { it.uuid })
        assertTrue("getPlace" in server.endpoints())
        val geo = asked.first { it.url.queryParameter("geo_lat") != null }
        assertEquals("44.98", geo.url.queryParameter("geo_lat"))
        assertEquals("${(25 * MILE_METERS).roundToInt()}", geo.url.queryParameter("geo_distance"))
        // Remembered for next time.
        assertEquals(LiveRadioPrefs(where = "55401", country = "US", place = found.place), store().current.liveRadio)
    }

    @Test
    fun aServerWithoutPlacesIsNotAskedAndACitySkipsTheRadius() {
        val model = model(store(), emptyList())
        model.lookUp("Austin, Texas", "US")
        waitFor { model.find is LiveFind.Found }
        assertFalse("getPlace" in server.endpoints())
        assertTrue(asked.none { it.url.queryParameter("geo_lat") != null })
        assertEquals("Texas", asked.single().url.queryParameter("state"))
        assertEquals(listOf("b"), (model.find as LiveFind.Found).stations.map { it.uuid })
    }

    @Test
    fun aPostalCodeWithoutTheServerSaysWhatToTypeInstead() {
        val model = model(store(), emptyList())
        model.lookUp("55401", "US")
        waitFor { model.find is LiveFind.Problem }
        assertEquals(LiveFind.Problem(NO_POSTAL_LOOKUP), model.find)
        assertTrue(asked.isEmpty())
    }

    @Test
    fun aCatalogThatDoesNotAnswerIsSaidPlainly() {
        catalogDown = true
        val model = model(store(), emptyList())
        model.lookUp("Austin, Texas", "US")
        waitFor { model.find is LiveFind.CatalogDown }
    }

    // Miles or kilometers

    @Test
    fun milesOnlyWhereRoadsAreMeasuredInThem() {
        listOf("US", "GB", "LR", "MM", "us").forEach { assertTrue(it, usesMiles(it)) }
        listOf("DE", "CA", "AU", "").forEach { assertFalse(it, usesMiles(it)) }
        assertEquals(listOf(10, 25, 50, 100), radiusChoices(miles = true))
        assertEquals(listOf(15, 40, 80, 160), radiusChoices(miles = false))
        assertEquals(40_000.0, radiusMeters(1, miles = false), 0.0)
        assertEquals("GB", systemCountry(Locale.UK))
        assertEquals("US", systemCountry(Locale.ENGLISH))
    }

    @Test
    fun aRowSaysHowFarOrWhichState() {
        assertEquals("3 mi", distanceText(3 * MILE_METERS, miles = true))
        assertEquals("Under 1 km", distanceText(400.0, miles = false))
        assertEquals("In Texas", whereText(LiveStation("u", "X", "http://x", state = "Texas"), miles = true))
        assertEquals("MP3 128 kbps", soundText(LiveStation("u", "X", "http://x", codec = "mp3", bitrate = 128)))
        assertEquals("HLS", soundText(LiveStation("u", "X", "http://x", codec = "UNKNOWN", hls = true)))
        assertEquals("No stations within 25 miles. Try a wider circle.", nothingFound(LivePlace(1.0, 1.0, "Here"), 25, miles = true))
    }

    @Test
    fun theDesktopPlaysTheseStreams() {
        listOf("MP3", "AAC", "AAC+", "OGG", "OPUS", "FLAC", "mp3").forEach { assertTrue(it, livePlayable(LiveStation("u", "X", "http://x", codec = it))) }
        listOf("WMA", "UNKNOWN", "").forEach { assertFalse(it, livePlayable(LiveStation("u", "X", "http://x", codec = it))) }
        assertTrue("HLS of any codec", livePlayable(LiveStation("u", "X", "http://x", codec = "UNKNOWN", hls = true)))
    }

    @Test
    fun aStationPlaysAsASongWithARadioId() {
        val song = liveSong("City Jazz: FM", "https://jazz.example/live.mp3")
        assertTrue(isRadio(song.id))
        assertEquals("https://jazz.example/live.mp3" to "City Jazz: FM", radioOf(song.id))
        assertEquals("City Jazz: FM", song.title)
    }

    @Test
    fun liveRadioStaysOffTheServersQueue() {
        val radio = QueueEntry(1, liveSong("Lake FM", "https://lake.example/fm"))
        val song = QueueEntry(2, Song("s1"))
        assertNull(serverQueueOf(PlayerState(queue = listOf(radio), played = emptyList(), current = radio, upcoming = emptyList()), 0))
        assertEquals(listOf("s1"), serverQueueOf(PlayerState(queue = listOf(radio, song), played = emptyList(), current = radio, upcoming = listOf(song)), 0)!!.ids)
    }

    // Home's Live radio shelf

    @Test
    fun theShelfHoldsTheServersStreamsThenTheKeptOnesEachOnce() {
        val server = listOf(
            RadioStation("r1", "City Radio", "https://radio.example.com/live.mp3"),
            RadioStation("r2", "Town FM", "https://town.example.com/fm"),
            RadioStation("st1", "Discover Weekly", "", coverArt = "st1"),
        )
        val kept = listOf(
            LiveStation("k1", "City Radio (kept)", "HTTPS://radio.example.com/live.mp3/", favicon = "https://radio.example.com/logo.png"),
            LiveStation("k2", "Lake FM", "https://lake.example/fm"),
        )
        val shelf = liveShelf(server, kept)
        assertEquals(listOf("City Radio", "Town FM", "Lake FM"), shelf.map { it.name })
        assertEquals("the server's copy lends the kept one's logo", "https://radio.example.com/logo.png", shelf[0].logo)
        assertEquals("k1", shelf[0].kept?.uuid)
        assertEquals("r1", shelf[0].serverId)
        assertNull(shelf[2].serverId)
    }

    @Test
    fun octosOwnStationsAreNotLiveRadio() {
        val stations = listOf(RadioStation("st1", "Your Radio", "", coverArt = "st1"), RadioStation("r1", "City", "https://x/live", coverArt = "ra-r1"))
        assertEquals(listOf("r1"), liveStationsOf(stations, isOcto = true).map { it.id })
        assertTrue(isOctoStation(stations[0], isOcto = true))
        assertFalse(isOctoStation(stations[0], isOcto = false))
    }

    // The station menu

    @Test
    fun anAdminCanAddAStationTheServerDoesNotHave() {
        assertEquals(listOf(LiveAction.Play, LiveAction.Keep, LiveAction.AddToServer), liveActions(kept = false, admin = true, onServer = false))
        assertEquals(listOf(LiveAction.Play, LiveAction.Remove), liveActions(kept = true, admin = true, onServer = true))
    }

    @Test
    fun anyoneElseCanPlayKeepAndRemove() {
        assertEquals(listOf(LiveAction.Play, LiveAction.Keep), liveActions(kept = false, admin = false, onServer = false))
        assertEquals(listOf(LiveAction.Play, LiveAction.Remove), liveActions(kept = true, admin = false, onServer = false))
        assertEquals(listOf("Play", "Keep", "Remove", "Add to your server"), LiveAction.entries.map(::liveActionLabel))
    }

    @Test
    fun theAdminCheckAsksTheServerWhoTheUserIs() {
        server.answer("getUser", """"user":{"username":"winters","adminRole":true}""")
        val model = model(store(), emptyList())
        model.checkAdmin()
        waitFor { model.admin != null }
        assertEquals(true, model.admin)
    }

    // Settings

    @Test
    fun thePlaceRadiusOrderAndKeptStationsSurviveARestart() {
        val kept = KeptStations().keep(LiveStation("k1", "Lake FM", "https://lake.example/fm", favicon = "https://lake.example/logo.png", tags = listOf("jazz")))
        val prefs = LiveRadioPrefs(
            where = "Austin, Texas",
            country = "US",
            place = LivePlace(30.27, -97.74, "Austin, Texas", "Texas", "US"),
            radius = 3,
            sort = LiveSort.Popular,
            kept = kept.encoded(),
        )
        store().update { it.copy(liveRadio = prefs) }
        val read = store().current.liveRadio
        assertEquals(prefs, read)
        assertEquals(kept, KeptStations.decoded(read.kept))
    }

    @Test
    fun settingsFromBeforeLiveRadioReadTheDefaults() {
        val file = File(folder.root, SettingsStore.FILE_NAME)
        file.writeText("""{"density":"regular"}""")
        assertEquals(LiveRadioPrefs(), SettingsStore(file).current.liveRadio)
        assertEquals(AppSettings().liveRadio, SettingsStore(file).current.liveRadio)
    }

    @Test
    fun keepingAndDroppingGoThroughTheSettings() {
        val settings = store()
        val model = model(settings, emptyList())
        model.keep(LiveStation("k1", "Lake FM", "https://lake.example/fm"))
        model.keep(LiveStation("k2", "River FM", "https://river.example/fm"))
        assertEquals(listOf("k2", "k1"), model.kept().stations.map { it.uuid })
        model.drop("k2")
        assertEquals(listOf("k1"), KeptStations.decoded(store().current.liveRadio.kept).stations.map { it.uuid })
    }

    @Test
    fun aCodeWithItsTownAndStateIsReadAsTheCode() {
        assertEquals(WhereAsked(code = "78701", name = "Austin", state = "TX", country = "US"), whereOf("Austin, TX 78701", "us"))
        assertEquals(WhereAsked(code = "10001", state = "NY", country = "US"), whereOf("10001, NY", "US"))
    }

    @Test
    fun aNewRadiusWhileAPlaceIsLookedUpKeepsThePlace() {
        val answer = java.util.concurrent.CountDownLatch(1)
        server.answerBy("getPlace") {
            answer.await(5, java.util.concurrent.TimeUnit.SECONDS)
            server.ok(""""place":{"code":"55401","name":"Minneapolis","state":"Minnesota","country":"US","latitude":44.98,"longitude":-93.27}""")
        }
        val settings = store()
        settings.update { it.copy(liveRadio = it.liveRadio.copy(place = LivePlace(30.27, -97.74, "Austin, Texas", "Texas", "US"))) }
        val model = model(settings, listOf("$OCTO_PLACES:1"))
        model.lookUp("55401", "US")
        model.setRadius(3)
        answer.countDown()
        waitFor { (model.find as? LiveFind.Found)?.place?.label == "Minneapolis, Minnesota" }
        assertEquals("Minneapolis, Minnesota", store().current.liveRadio.place?.label)
        assertEquals(3, store().current.liveRadio.radius)
        // Searched once found, with the radius chosen meanwhile.
        val geo = asked.last { it.url.queryParameter("geo_lat") != null }
        assertEquals("44.98", geo.url.queryParameter("geo_lat"))
        assertEquals("${(100 * MILE_METERS).roundToInt()}", geo.url.queryParameter("geo_distance"))
    }
}
