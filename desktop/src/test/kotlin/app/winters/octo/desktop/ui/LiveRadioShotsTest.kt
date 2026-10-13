package app.winters.octo.desktop.ui

import androidx.compose.runtime.CompositionLocalProvider
import androidx.compose.ui.ImageComposeScene
import androidx.compose.ui.unit.Density
import androidx.compose.ui.unit.IntOffset
import app.winters.octo.design.LocalTyping
import app.winters.octo.design.TypingState
import app.winters.octo.desktop.AppState
import app.winters.octo.desktop.FakeServer
import app.winters.octo.desktop.liveradio.LiveFind
import app.winters.octo.desktop.nav.Page
import app.winters.octo.desktop.pages.StationDraft
import app.winters.octo.desktop.pages.showSection
import app.winters.octo.desktop.pages.stationSheet
import app.winters.octo.desktop.player.SilentPlayer
import app.winters.octo.desktop.secrets.SessionOnlySecrets
import app.winters.octo.desktop.server.Accounts
import app.winters.octo.desktop.server.SignInOutcome
import app.winters.octo.desktop.server.SignInRequest
import app.winters.octo.desktop.settings.DesktopOs
import app.winters.octo.desktop.settings.SettingsStore
import app.winters.octo.liveradio.KeptStations
import app.winters.octo.liveradio.LiveSort
import app.winters.octo.liveradio.LiveStation
import app.winters.octo.liveradio.RadioBrowser
import app.winters.octo.lyrics.OnlineLyrics
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.runBlocking
import mockwebserver3.Dispatcher
import mockwebserver3.MockResponse
import mockwebserver3.MockWebServer
import mockwebserver3.RecordedRequest
import okhttp3.HttpUrl.Companion.toHttpUrl
import okhttp3.OkHttpClient
import org.jetbrains.skia.EncodedImageFormat
import org.junit.Assume.assumeTrue
import org.junit.Rule
import org.junit.Test
import org.junit.rules.TemporaryFolder
import java.io.File
import javax.swing.SwingUtilities

// Pictures of live radio against a pretend Octo server and a pretend radio
// catalog: Home's Live radio shelf, the Live radio page before and after a
// place is found, a station's menu, and Settings > Radio stations. Only
// when asked: OCTO_SHOTS=1 ./gradlew :desktop:test --tests '*LiveRadioShotsTest*'.
class LiveRadioShotsTest {
    @get:Rule val folder = TemporaryFolder()

    private val stations = listOf(
        Triple("KBEM Jazz 88", "jazz,public radio", 1_800.0),
        Triple("The Current", "indie,alternative,public radio", 3_400.0),
        Triple("MPR News", "news,talk", 3_400.0),
        Triple("KFAI Fresh Air", "community,eclectic", 5_100.0),
        Triple("Cities 97.1", "adult alternative,pop", 9_600.0),
        Triple("Go 95.3", "hip hop,r&b", 12_700.0),
        Triple("KQRS 92.5", "classic rock", 21_000.0),
        Triple("WCCO 830", "news,sports", 30_500.0),
    )

    private fun catalogStation(index: Int, name: String, tags: String, meters: Double?, base: String) =
        """{"stationuuid":"uuid-$index","name":"$name","url_resolved":"https://stream.example/$index.mp3","favicon":"${if (index % 3 == 2) "" else "${base}logo/$index.png"}",""" +
            """"codec":"${if (index % 4 == 1) "AAC" else "MP3"}","bitrate":${if (index % 4 == 1) 64 else 128},"hls":0,"country":"The United States Of America","countrycode":"US","state":"Minnesota",""" +
            """"tags":"$tags","clickcount":${400 - index * 37},"lastcheckok":1""" + (meters?.let { ""","geo_distance":$it""" } ?: "") + "}"

    @Test
    fun drawLiveRadio() {
        assumeTrue(System.getenv("OCTO_SHOTS") == "1")
        val out = File("build/shots").apply { mkdirs() }
        val catalog = MockWebServer()
        catalog.dispatcher = object : Dispatcher() {
            override fun dispatch(request: RecordedRequest): MockResponse {
                val base = catalog.url("/").toString()
                val path = request.url.encodedPath
                return when {
                    path.startsWith("/logo/") -> MockResponse.Builder().body(okio.Buffer().write(madeUpLogo(path))).build()
                    request.url.queryParameter("geo_lat") != null ->
                        MockResponse.Builder().body("[" + stations.mapIndexed { i, (n, t, m) -> catalogStation(i, n, t, m, base) }.joinToString(",") + "]").build()
                    path == "/json/stations/search" -> MockResponse.Builder().body("[" + catalogStation(20, "Radio K", "college,indie", null, base) + "]").build()
                    else -> MockResponse.Builder().body("{}").build()
                }
            }
        }
        catalog.start()
        FakeServer().use { server ->
            server.answer("ping", type = "octo")
            server.answer(
                "getOpenSubsonicExtensions",
                """"openSubsonicExtensions":[{"name":"octoAcquisitions","versions":[1]},{"name":"octoStations","versions":[1]},{"name":"octoPlaces","versions":[1]}]""",
                type = "octo",
            )
            server.answer("getAlbumList2", """"albumList2":{"album":[${(1..8).joinToString(",") { """{"id":"al$it","name":"Album $it","artist":"Artist $it","coverArt":"al$it"}""" }}]}""")
            server.answer("getArtists", """"artists":{"index":[]}""")
            server.answer("getPlaylists", """"playlists":{"playlist":[]}""")
            server.answer("getAcquisitions", """"acquisitions":{"acquisition":[]}""", type = "octo")
            server.answer("getUser", """"user":{"username":"winters","adminRole":true}""")
            server.answer(
                "getInternetRadioStations",
                """"internetRadioStations":{"internetRadioStation":[
                    {"id":"st1","name":"Your Radio","coverArt":"st1"},
                    {"id":"r1","name":"Jazz24","streamUrl":"https://live.wostreaming.net/direct/ppm-jazz24aac256-ibc1","homePageUrl":"https://www.jazz24.org"},
                    {"id":"r2","name":"SomaFM Groove Salad","streamUrl":"https://ice1.somafm.com/groovesalad-256-mp3"}
                ]}""",
                type = "octo",
            )
            server.answer("getPlace", """"place":{"code":"55401","name":"Minneapolis","state":"Minnesota","country":"US","latitude":44.98,"longitude":-93.27}""", type = "octo")
            server.fileBy("getCoverArt") { madeUpLogo(it.url.queryParameter("id").orEmpty()) }

            val settings = SettingsStore(File(folder.root, "settings.json"))
            val kept = KeptStations().keep(LiveStation("uuid-1", "The Current", "https://stream.example/1.mp3", favicon = catalog.url("/logo/1.png").toString(), codec = "AAC", bitrate = 64, state = "Minnesota", tags = listOf("indie")))
            settings.update {
                it.copy(
                    lyrics = it.lyrics.copy(online = false),
                    liveRadio = it.liveRadio.copy(kept = kept.encoded()),
                    // The Live radio shelf first, so the picture shows it.
                    appearance = it.appearance.copy(homeSections = "internetRadio,stations,recentlyPlayed"),
                )
            }
            val http = OkHttpClient()
            val accounts = Accounts(settings, SessionOnlySecrets(), http)
            lateinit var app: AppState
            runBlocking { accounts.signIn(SignInRequest(server.address, "winters", "pw")) } as SignInOutcome.Done
            val radio = RadioBrowser(http, "Octo/test (desktop)", servers = { listOf(catalog.url("/").toString()) })
            SwingUtilities.invokeAndWait {
                app = AppState(
                    settings, accounts, http, CoroutineScope(SupervisorJob() + Dispatchers.Main), DesktopOs.Windows, SilentPlayer(),
                    OnlineLyrics(http, server.address.toHttpUrl()), restored = accounts.restore(), listeningRoot = File(folder.root, "listening"), radioCatalog = radio,
                )
            }
            val scene = ImageComposeScene(1440, 900, Density(1f)) {
                CompositionLocalProvider(LocalTyping provides TypingState()) { Shell(app, null) {} }
            }
            fun shot(name: String, settleMs: Long = 2_500) {
                val begin = System.currentTimeMillis()
                var t = 0L
                while (System.currentTimeMillis() < begin + settleMs) {
                    SwingUtilities.invokeAndWait { scene.render(t) }
                    Thread.sleep(30)
                    t = (System.currentTimeMillis() - begin) * 1_000_000
                }
                File(out, "$name.png").writeBytes(scene.render(t).encodeToData(EncodedImageFormat.PNG)!!.bytes)
            }
            shot("live-home-shelf", 3_500)
            SwingUtilities.invokeAndWait { app.navigator.go(Page.LiveRadio) }
            shot("live-page-where")
            SwingUtilities.invokeAndWait { app.liveRadio.lookUp("55401", "US") }
            val until = System.currentTimeMillis() + 5_000
            while (app.liveRadio.find !is LiveFind.Found && System.currentTimeMillis() < until) Thread.sleep(50)
            shot("live-page-found")
            SwingUtilities.invokeAndWait {
                val station = (app.liveRadio.find as LiveFind.Found).stations[0]
                app.popups.showAt(IntOffset(760, 420)) { close -> LiveStationMenu(app, station, kept = false, close) }
            }
            shot("live-page-menu")
            SwingUtilities.invokeAndWait {
                app.popups.close()
                app.liveRadio.setSort(LiveSort.Popular)
            }
            shot("live-page-most-played")
            SwingUtilities.invokeAndWait {
                showSection("Settings", "stations")
                app.navigator.go(Page.Settings)
            }
            shot("live-settings-stations")
            SwingUtilities.invokeAndWait { stationSheet(app, StationDraft("r1", "Jazz24", "https://live.wostreaming.net/direct/ppm-jazz24aac256-ibc1", "https://www.jazz24.org")) {} }
            shot("live-settings-edit-station")
            SwingUtilities.invokeAndWait { app.popups.close() }
            SwingUtilities.invokeAndWait { app.navigator.go(Page.Search) }
            shot("live-search-row")
            scene.close()
        }
        catalog.close()
    }

    // A logo of a soft shape in colors of its own for each name.
    private fun madeUpLogo(id: String): ByteArray {
        val palette = listOf(0xFF1B2A4A, 0xFFE0703A, 0xFF3AA6A0, 0xFFF2D06B, 0xFF6B3A7A, 0xFFB8C4C9, 0xFF2F5D3A, 0xFFC0463F).map { it.toInt() }
        val seed = id.hashCode() and 0x7fffffff
        fun color(n: Int) = palette[(seed / (n + 1) + n) % palette.size]
        val surface = org.jetbrains.skia.Surface.makeRasterN32Premul(200, 200)
        val canvas = surface.canvas
        canvas.clear(color(0))
        val paint = org.jetbrains.skia.Paint()
        paint.color = color(1)
        canvas.drawCircle(100f, 100f, 60f + seed % 30, paint)
        return surface.makeImageSnapshot().encodeToData(EncodedImageFormat.PNG)!!.bytes
    }
}
