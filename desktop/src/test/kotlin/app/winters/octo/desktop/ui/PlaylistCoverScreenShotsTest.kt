package app.winters.octo.desktop.ui

import androidx.compose.runtime.CompositionLocalProvider
import androidx.compose.ui.ImageComposeScene
import androidx.compose.ui.unit.Density
import app.winters.octo.covers.PlaylistCoverStyle
import app.winters.octo.design.LocalTyping
import app.winters.octo.design.TypingState
import app.winters.octo.desktop.AppState
import app.winters.octo.desktop.FakeServer
import app.winters.octo.desktop.nav.Page
import app.winters.octo.desktop.nav.ScrollSpot
import app.winters.octo.desktop.secrets.SessionOnlySecrets
import app.winters.octo.desktop.server.Accounts
import app.winters.octo.desktop.server.SignInOutcome
import app.winters.octo.desktop.settings.DesktopOs
import app.winters.octo.desktop.settings.SettingsStore
import app.winters.octo.desktop.songJson
import app.winters.octo.livelists.LiveList
import app.winters.octo.query.FilterPresets
import app.winters.octo.query.LibraryQuery
import app.winters.octo.query.QuerySort
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.runBlocking
import okhttp3.OkHttpClient
import org.jetbrains.skia.EncodedImageFormat
import org.jetbrains.skia.Paint
import org.jetbrains.skia.Rect
import org.jetbrains.skia.Surface
import org.junit.Assume.assumeTrue
import org.junit.Rule
import org.junit.Test
import org.junit.rules.TemporaryFolder
import java.io.File
import javax.swing.SwingUtilities

// The window with designed playlist covers: the sidebar full of playlists
// (long names, Japanese, Arabic, emoji, one with no covers, a live list),
// Home's playlists, playlist pages, the add-to-playlist menu, the setting,
// and the same with album mosaics. Only when asked:
// OCTO_SHOTS=1 ./gradlew :desktop:test --tests '*PlaylistCoverScreenShotsTest*'
class PlaylistCoverScreenShotsTest {
    @get:Rule val folder = TemporaryFolder()

    // A plain cover of two colours, different for each id.
    private fun cover(id: String): ByteArray {
        val colours = listOf(0xFF1B2A4A, 0xFFE0703A, 0xFF3AA6A0, 0xFFF2D06B, 0xFF6B3A7A, 0xFFC0463F, 0xFF2F5D3A, 0xFF4A6BD8).map { it.toInt() }
        val seed = id.hashCode() and 0x7fffffff
        val surface = Surface.makeRasterN32Premul(300, 300)
        surface.canvas.clear(colours[seed % colours.size])
        val paint = Paint().apply { color = colours[(seed / 7 + 3) % colours.size] }
        surface.canvas.drawCircle(200f, 110f, 100f, paint)
        if (id.startsWith("pl-")) {
            // A playlist's picture: four album covers in a square.
            for (q in 0 until 4) {
                val tile = org.jetbrains.skia.Image.makeFromEncoded(cover("al-$q$id"))
                surface.canvas.drawImageRect(tile, Rect.makeXYWH(150f * (q % 2), 150f * (q / 2), 150f, 150f))
            }
        }
        return surface.makeImageSnapshot().encodeToData(EncodedImageFormat.PNG)!!.bytes
    }

    @Test
    fun drawThePlaylistCovers() {
        assumeTrue(System.getenv("OCTO_SHOTS") == "1")
        val out = File("build/shots/playlist-covers").apply { mkdirs() }
        FakeServer().use { server ->
            val songs = (1..12).joinToString(",") { i ->
                songJson("s$i", "Song $i", artist = "Artist ${i % 3}", album = "Album ${i % 5}", albumId = "a${i % 5}").dropLast(1) +
                    ""","coverArt":"al-a${i % 5}","genre":"Trip Hop","suffix":"flac","created":"2026-09-01T10:00:00Z"}"""
            }
            val lists = listOf(
                "p1" to "Late night", "p2" to "Running", "p3" to "Everything I have ever loved, in the order I found it",
                "p4" to "夜のドライブ", "p5" to "أغاني الصيف", "p6" to "🔥 Gym 🔥", "p7" to "Dinner with friends",
                "p8" to "Empty for now", "p9" to "Kitchen dancing", "p10" to "Sunday morning",
            )
            val playlistJson = lists.joinToString(",") { (id, name) ->
                val cover = if (id == "p8") "" else ""","coverArt":"pl-$id""""
                val owner = if (id == "p9") "sam" else "winters"
                """{"id":"$id","name":"$name","owner":"$owner","songCount":${if (id == "p8") 0 else 12 + id.drop(1).toInt() * 3},"changed":"2026-09-28T10:00:00Z"$cover}"""
            }
            server.answer("ping", type = "octo")
            server.answer("getAlbumList2", """"albumList2":{"album":[]}""")
            server.answer("getArtists", """"artists":{"index":[]}""")
            server.answer("search3", """"searchResult3":{"song":[$songs]}""")
            server.answer("getStarred2", """"starred2":{}""")
            server.answer("getPlaylists", """"playlists":{"playlist":[$playlistJson]}""")
            server.answerBy("getPlaylist") { request ->
                val id = request.url.queryParameter("id").orEmpty()
                val name = lists.first { it.first == id }.second.replace("\"", "\\\"")
                val entries = if (id == "p8") "" else songs
                val cover = if (id == "p8") "" else ""","coverArt":"pl-$id""""
                val owner = if (id == "p9") "sam" else "winters"
                val count = if (id == "p8") 0 else 12
                server.ok(""""playlist":{"id":"$id","name":"$name","owner":"$owner","comment":"Made for the drive home","songCount":$count,"changed":"2026-09-28T10:00:00Z"$cover,"entry":[$entries]}""")
            }
            server.answer("getInternetRadioStations", """"internetRadioStations":{"internetRadioStation":[{"id":"st1","name":"Discover Weekly","coverArt":"st1"},{"id":"st2","name":"Rock mix","coverArt":"st2"}]}""")
            server.fileBy("getCoverArt") { cover(it.url.queryParameter("id").orEmpty()) }

            val settings = SettingsStore(File(folder.root, "settings.json"))
            settings.update { it.copy(lyrics = it.lyrics.copy(online = false)) }
            val http = OkHttpClient()
            val accounts = Accounts(settings, SessionOnlySecrets(), http)
            lateinit var app: AppState
            SwingUtilities.invokeAndWait {
                app = AppState(settings, accounts, http, CoroutineScope(SupervisorJob() + Dispatchers.Main), DesktopOs.Windows)
            }
            val scene = ImageComposeScene(1440, 900, Density(1f)) {
                CompositionLocalProvider(LocalTyping provides TypingState()) { Shell(app, null) {} }
            }
            fun shot(name: String?, settleMs: Long = 2_000, on: ImageComposeScene = scene) {
                val begin = System.currentTimeMillis()
                var t = 0L
                while (System.currentTimeMillis() < begin + settleMs) {
                    SwingUtilities.invokeAndWait { on.render(t) }
                    Thread.sleep(30)
                    t = (System.currentTimeMillis() - begin) * 1_000_000
                }
                val image = on.render(t)
                if (name != null) File(out, "$name.png").writeBytes(image.encodeToData(EncodedImageFormat.PNG)!!.bytes)
            }
            val done = runBlocking { accounts.signIn(server.address, "winters", "pw") } as SignInOutcome.Done
            SwingUtilities.invokeAndWait {
                app.signedIn(done.connection)
                app.liveLists.save(LiveList.new("Trip hop nights", LibraryQuery(listOf(FilterPresets.genre("Trip Hop")), sort = QuerySort("Title")), System.currentTimeMillis()))
            }
            shot("home", 4_000)
            // Home further down, where its playlists are.
            val home = app.navigator.current
            SwingUtilities.invokeAndWait { app.navigator.go(Page.Songs) }
            shot(null, 300)
            SwingUtilities.invokeAndWait {
                app.navigator.keepScroll(home, ScrollSpot(1))
                app.navigator.back()
            }
            shot("home-playlists", 3_000)
            for ((id, name) in listOf("p1" to "playlist", "p3" to "playlist-long", "p4" to "playlist-cjk", "p5" to "playlist-rtl", "p6" to "playlist-emoji", "p8" to "playlist-no-covers", "p9" to "playlist-someone-elses")) {
                SwingUtilities.invokeAndWait { app.navigator.go(Page.Playlist(id)) }
                shot(name, 2_500)
            }
            SwingUtilities.invokeAndWait { app.navigator.go(Page.LiveList(app.liveLists.lists.value.first().id)) }
            shot("livelist", 2_500)
            SwingUtilities.invokeAndWait {
                app.navigator.go(Page.Playlist("p1"))
                app.popups.showAt(androidx.compose.ui.unit.IntOffset(560, 150)) { close ->
                    PlaylistChooser(app, { emptyList() }, close) { close() }
                }
            }
            shot("add-to-playlist", 1_500)
            SwingUtilities.invokeAndWait { app.popups.close() }
            // Settings, turned down to Appearance's Playlists group.
            fun wheel(clicks: Int) {
                repeat(clicks) {
                    SwingUtilities.invokeAndWait {
                        scene.sendPointerEvent(androidx.compose.ui.input.pointer.PointerEventType.Scroll, androidx.compose.ui.geometry.Offset(900f, 500f), scrollDelta = androidx.compose.ui.geometry.Offset(0f, 1f))
                    }
                }
            }
            SwingUtilities.invokeAndWait { app.navigator.go(Page.Settings) }
            shot(null, 800)
            wheel(8)
            shot("settings", 1_500)
            // The same with the album mosaics.
            SwingUtilities.invokeAndWait {
                app.settings.update { it.copy(appearance = it.appearance.copy(playlistCovers = PlaylistCoverStyle.Mosaic)) }
                app.navigator.go(Page.Playlist("p1"))
            }
            shot("mosaic-playlist", 2_500)
            SwingUtilities.invokeAndWait { app.navigator.go(Page.Home) }
            shot(null, 800)
            SwingUtilities.invokeAndWait { app.navigator.go(Page.Settings) }
            shot(null, 800)
            wheel(8)
            shot("mosaic-settings", 1_500)
            scene.close()
        }
    }
}
