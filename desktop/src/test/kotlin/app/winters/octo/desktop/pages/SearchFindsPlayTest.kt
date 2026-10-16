package app.winters.octo.desktop.pages

import androidx.compose.ui.ExperimentalComposeUiApi
import androidx.compose.ui.ImageComposeScene
import androidx.compose.ui.input.pointer.PointerButtons
import androidx.compose.ui.input.pointer.PointerEventType
import androidx.compose.ui.semantics.SemanticsNode
import androidx.compose.ui.semantics.SemanticsProperties
import androidx.compose.ui.semantics.getOrNull
import androidx.compose.ui.unit.Density
import app.winters.octo.desktop.AppState
import app.winters.octo.desktop.FakeServer
import app.winters.octo.desktop.nav.Page
import app.winters.octo.desktop.nav.Visit
import app.winters.octo.desktop.player.DesktopPlayer
import app.winters.octo.desktop.player.SilentPlayer
import app.winters.octo.desktop.search.SearchState
import app.winters.octo.desktop.secrets.SessionOnlySecrets
import app.winters.octo.desktop.server.Accounts
import app.winters.octo.desktop.settings.DesktopOs
import app.winters.octo.desktop.settings.SettingsStore
import app.winters.octo.desktop.songJson
import app.winters.octo.lyrics.OnlineLyrics
import app.winters.octo.playback.QueueSource
import app.winters.octo.subsonic.Song
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.cancel
import okhttp3.HttpUrl.Companion.toHttpUrl
import okhttp3.OkHttpClient
import org.junit.After
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Rule
import org.junit.Test
import org.junit.rules.TemporaryFolder
import java.io.File

// Clicking a song the server found online, on the real Search page, against
// a pretend Octo server: it is a row of the song table like the library's.
@OptIn(ExperimentalComposeUiApi::class)
class SearchFindsPlayTest {
    @get:Rule val temp = TemporaryFolder()

    private val server = FakeServer()
    private val scope = CoroutineScope(SupervisorJob() + Dispatchers.Unconfined)
    private val silent = SilentPlayer()

    // The silent player, counting what it is asked to play.
    private val plays = mutableListOf<List<String>>()
    private val player = object : DesktopPlayer by silent {
        override fun play(songs: List<Song>, start: Int, shuffle: Boolean, source: QueueSource) {
            plays += songs.map { it.id }
            silent.play(songs, start, shuffle, source)
        }
    }

    @After
    fun stop() {
        scope.cancel()
        server.close()
    }

    private fun waitFor(what: () -> Boolean) {
        val until = System.currentTimeMillis() + 5_000
        while (!what() && System.currentTimeMillis() < until) Thread.sleep(20)
        assertTrue("waited too long", what())
    }

    // The node showing exactly this text.
    private fun find(node: SemanticsNode, text: String): SemanticsNode? {
        if (node.config.getOrNull(SemanticsProperties.Text)?.joinToString { it.text } == text) return node
        return node.children.firstNotNullOfOrNull { find(it, text) }
    }

    // Searches a library of one song on a server that finds two more online,
    // then clicks the first find on the Search page `times` times.
    private fun clickFind(times: Int) {
        val library = songJson("lib1", "Nightcall", artist = "Kavinsky")
        val finds = songJson("find1", "Odd Look", artist = "Kavinsky") + "," + songJson("find2", "Roadgame", artist = "Kavinsky")
        server.answer("getAlbumList2", """"albumList2":{"album":[]}""")
        server.answer("getArtists", """"artists":{"index":[]}""")
        server.answer("getPlaylists", """"playlists":{"playlist":[]}""")
        server.answerBy("search3") { request ->
            val songs = if (request.url.queryParameter("query").isNullOrEmpty()) library else "$library,$finds"
            server.ok(""""searchResult3":{"song":[$songs]}""")
        }
        val settings = SettingsStore(File(temp.root, "settings.json"), 0)
        val http = OkHttpClient()
        val app = AppState(
            settings,
            Accounts(settings, SessionOnlySecrets(), http),
            http,
            scope,
            DesktopOs.Windows,
            player,
            OnlineLyrics(http, server.address.toHttpUrl()),
            restored = server.connection(listOf("octoAcquisitions:1")),
        )
        waitFor { app.library?.index != null }
        app.search!!.type("kavinsky")
        waitFor { (app.search!!.state as? SearchState.Done)?.found?.outside?.songs?.size == 2 }
        val scene = ImageComposeScene(1200, 900, Density(1f)) { SearchPage(app, Visit(0, Page.Search, null)) }
        try {
            repeat(3) { scene.render() }
            val title = scene.semanticsOwners.firstNotNullOf { find(it.unmergedRootSemanticsNode, "Odd Look") }
            val spot = title.boundsInRoot.center
            scene.sendPointerEvent(PointerEventType.Enter, spot)
            repeat(times) {
                scene.sendPointerEvent(PointerEventType.Press, spot, buttons = PointerButtons(isPrimaryPressed = true))
                scene.sendPointerEvent(PointerEventType.Release, spot)
                scene.render()
            }
        } finally {
            scene.close()
        }
    }

    // Songs found online are rows of the same song table as the library's:
    // a click picks one, as in every table, and plays nothing.
    @Test
    fun aClickPicksTheFind() {
        clickFind(1)
        assertEquals(emptyList<List<String>>(), plays)
    }

    // A double click plays the list from the find, the library's song
    // before it and the finds after it, once.
    @Test
    fun aDoubleClickPlaysTheListFromTheFindOnce() {
        clickFind(2)
        assertEquals(listOf(listOf("lib1", "find1", "find2")), plays)
        assertEquals("find1", silent.state.value.current?.song?.id)
    }
}
