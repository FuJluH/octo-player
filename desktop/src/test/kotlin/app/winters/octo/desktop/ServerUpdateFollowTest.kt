package app.winters.octo.desktop

import app.winters.octo.desktop.player.SilentPlayer
import app.winters.octo.desktop.secrets.SessionOnlySecrets
import app.winters.octo.desktop.server.Accounts
import app.winters.octo.desktop.server.SignInOutcome
import app.winters.octo.desktop.server.SignInRequest
import app.winters.octo.desktop.settings.DesktopOs
import app.winters.octo.desktop.settings.SettingsStore
import app.winters.octo.lyrics.OnlineLyrics
import app.winters.octo.serverupdate.UpdatePanel
import app.winters.octo.serverupdate.panelOf
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.cancel
import kotlinx.coroutines.runBlocking
import okhttp3.HttpUrl.Companion.toHttpUrl
import okhttp3.OkHttpClient
import org.junit.After
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Rule
import org.junit.Test
import org.junit.rules.TemporaryFolder
import java.io.File
import javax.swing.SwingUtilities

// The window follows the update state of the Octo server in use, through
// its own signed admin call, and of no other kind of server.
class ServerUpdateFollowTest {
    @get:Rule val folder = TemporaryFolder()

    private val scope = CoroutineScope(SupervisorJob() + Dispatchers.Main)

    @After
    fun stop() = scope.cancel()

    private val behind =
        """{"enabled":true,"repo":"winters27/octo","running":"2026.10.11","latest":{"tag":"2026.10.13"},"newer":[{"tag":"2026.10.13"}],"updateAvailable":true,"standing":"behind","helper":{"installed":true,"mode":"image","outdated":false},"pending":false,"run":null}"""

    private fun serve(server: FakeServer, type: String) {
        server.answerBy("ping") { """{"subsonic-response":{"status":"ok","version":"1.16.1","type":"$type","serverVersion":"2026.10.11","openSubsonic":true}}""" }
        val extensions = if (type == "octo") """[{"name":"octoAcquisitions","versions":[1]}]""" else "[]"
        server.answer("getOpenSubsonicExtensions", """"openSubsonicExtensions":$extensions""", type = type)
        server.answer("getAlbumList2", """"albumList2":{"album":[]}""")
        server.answer("getArtists", """"artists":{"index":[]}""")
        server.answer("search3", """"searchResult3":{"song":[]}""")
        server.answer("getPlaylists", """"playlists":{"playlist":[]}""")
        server.answerBy("update") { behind }
    }

    private fun open(server: FakeServer, settings: SettingsStore): AppState {
        val http = OkHttpClient()
        val accounts = Accounts(settings, SessionOnlySecrets(), http)
        runBlocking { accounts.signIn(SignInRequest(server.address, "winters", "pw")) } as SignInOutcome.Done
        lateinit var app: AppState
        SwingUtilities.invokeAndWait {
            app = AppState(settings, accounts, http, scope, DesktopOs.Windows, SilentPlayer(), OnlineLyrics(http, server.address.toHttpUrl()), restored = accounts.restore(), listeningRoot = File(folder.root, "listening"), browse = {})
        }
        return app
    }

    private fun waitFor(what: () -> Boolean) {
        val until = System.currentTimeMillis() + 10_000
        while (!what() && System.currentTimeMillis() < until) Thread.sleep(20)
    }

    @Test
    fun anOctoServerIsAskedSignedAndLaterIsKept() {
        FakeServer().use { home ->
            serve(home, "octo")
            val settings = SettingsStore(File(folder.root, "settings.json"))
            val app = open(home, settings)
            waitFor { panelOf(app.serverUpdate.track.value) is UpdatePanel.Available }
            assertTrue(panelOf(app.serverUpdate.track.value) is UpdatePanel.Available)
            val asked = home.calls.first { it.url.encodedPath == "/api/admin/update" }
            assertEquals("winters", asked.url.queryParameter("u"))

            SwingUtilities.invokeAndWait { app.serverUpdate.later() }
            waitFor { settings.current.serverUpdateLater.isNotEmpty() }
            assertEquals(listOf("2026.10.13"), settings.current.serverUpdateLater.values.toList())
            assertEquals(UpdatePanel.Hidden, panelOf(app.serverUpdate.track.value))
        }
    }

    @Test
    fun anotherKindOfServerIsNeverAsked() {
        FakeServer().use { work ->
            serve(work, "navidrome")
            val app = open(work, SettingsStore(File(folder.root, "settings.json")))
            waitFor { app.library?.index != null }
            Thread.sleep(300)
            assertTrue(work.calls.none { it.url.encodedPath == "/api/admin/update" })
            assertEquals(UpdatePanel.Hidden, panelOf(app.serverUpdate.track.value))
        }
    }
}
