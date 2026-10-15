package app.winters.octo.desktop.animated

import androidx.compose.runtime.CompositionLocalProvider
import androidx.compose.ui.ExperimentalComposeUiApi
import androidx.compose.ui.ImageComposeScene
import androidx.compose.ui.InternalComposeUiApi
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.unit.Density
import app.winters.octo.animated.AnimatedArtSetting
import app.winters.octo.animated.LoopShelf
import app.winters.octo.design.ArrowKeys
import app.winters.octo.design.FocusVisibility
import app.winters.octo.design.LocalTyping
import app.winters.octo.design.ProvideWindowLook
import app.winters.octo.design.TypingState
import app.winters.octo.desktop.AppState
import app.winters.octo.desktop.SidePanel
import app.winters.octo.desktop.nav.Page
import app.winters.octo.desktop.player.SilentPlayer
import app.winters.octo.desktop.secrets.SessionOnlySecrets
import app.winters.octo.desktop.server.Accounts
import app.winters.octo.desktop.server.SignInOutcome
import app.winters.octo.desktop.settings.DesktopOs
import app.winters.octo.desktop.settings.SettingsStore
import app.winters.octo.desktop.ui.LocalWindowShown
import app.winters.octo.desktop.ui.Shell
import app.winters.octo.lyrics.OnlineLyrics
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.cancel
import kotlinx.coroutines.runBlocking
import okhttp3.HttpUrl.Companion.toHttpUrl
import okhttp3.OkHttpClient
import org.jetbrains.skia.EncodedImageFormat
import org.jetbrains.skia.Image
import org.junit.Assume.assumeTrue
import org.junit.Rule
import org.junit.Test
import org.junit.rules.TemporaryFolder
import java.io.File
import javax.swing.SwingUtilities

// Animated art against a real Octo server, in the whole window drawn off
// screen on the silent player (no sound): the album header, the full
// player's square loop and its tall one, lyrics beside it, a long title,
// an album without art, Off, and the crossfade from the still. Opt in with
// OCTO_LIVE_ADDRESS, OCTO_LIVE_USER and OCTO_LIVE_PASSWORD; the pictures go
// to OCTO_SHOTS_DIR (else build/shots/animated).
@OptIn(ExperimentalComposeUiApi::class, InternalComposeUiApi::class)
class LiveAnimatedArtShotsTest {
    @get:Rule val folder = TemporaryFolder()

    private val out = File(System.getenv("OCTO_SHOTS_DIR") ?: "build/shots/animated")

    // Signs a separate profile (OCTO_LIVE_PROFILE, the folder OCTO_PROFILE_DIR
    // then names for a run of the app) in to the server, with its password in
    // the system's store, the volume at 0 and Animated art on Full screen,
    // so the app itself can be run against it.
    @Test(timeout = 120_000)
    fun seedsAProfile() {
        val profile = System.getenv("OCTO_LIVE_PROFILE")
        val address = System.getenv("OCTO_LIVE_ADDRESS")
        val user = System.getenv("OCTO_LIVE_USER")
        val password = System.getenv("OCTO_LIVE_PASSWORD")
        assumeTrue(!profile.isNullOrBlank() && !address.isNullOrBlank() && !user.isNullOrBlank() && !password.isNullOrBlank())
        val config = File(profile!!, "config").apply { mkdirs() }
        val settings = SettingsStore(File(config, SettingsStore.FILE_NAME), 0)
        settings.update { it.copy(playback = it.playback.copy(volume = 0f), appearance = it.appearance.copy(animatedArt = AnimatedArtSetting.FullScreen.key)) }
        val accounts = Accounts(settings, app.winters.octo.desktop.secrets.SecretStore.forSystem(DesktopOs.Windows), OkHttpClient())
        val signed = runBlocking { accounts.signIn(address!!, user!!, password!!) }
        check(signed is SignInOutcome.Done && signed.remembered) { "could not sign in: $signed" }
    }

    @Test(timeout = 900_000)
    fun everyStateAgainstARealServer() {
        assumeTrue(System.getenv("OCTO_LIVE_PROFILE").isNullOrBlank())
        val address = System.getenv("OCTO_LIVE_ADDRESS")
        val user = System.getenv("OCTO_LIVE_USER")
        val password = System.getenv("OCTO_LIVE_PASSWORD")
        assumeTrue(!address.isNullOrBlank() && !user.isNullOrBlank() && !password.isNullOrBlank())
        out.mkdirs()
        val settings = SettingsStore(File(folder.root, "settings.json"), 0)
        settings.update { it.copy(lyrics = it.lyrics.copy(online = false)) }
        val http = OkHttpClient()
        val accounts = Accounts(settings, SessionOnlySecrets(), http)
        val signed = runBlocking { accounts.signIn(address!!, user!!, password!!) }
        check(signed is SignInOutcome.Done) { "could not sign in: $signed" }
        val scope = CoroutineScope(SupervisorJob() + Dispatchers.Main)
        lateinit var app: AppState
        SwingUtilities.invokeAndWait {
            app = AppState(
                settings, accounts, http, scope, DesktopOs.Windows, SilentPlayer(volume = 0f),
                OnlineLyrics(http, "http://127.0.0.1:9/".toHttpUrl()),
                restored = signed.connection,
                listeningRoot = File(folder.root, "listening"),
            )
            app.animated.shelf = LoopShelf(File(folder.root, "loops"), LOOP_SHELF_BYTES)
        }
        val shown = androidx.compose.runtime.mutableStateOf(true)
        val scene = ImageComposeScene(1440, 900, Density(1f)) {
            ProvideWindowLook(reduceMotion = false, focus = FocusVisibility(keyboard = false), arrows = ArrowKeys()) {
                CompositionLocalProvider(
                    LocalTyping provides TypingState(),
                    LocalDensity provides Density(1f, 1f),
                    LocalWindowShown provides shown.value,
                ) { Shell(app, null) {} }
            }
        }
        fun render(ms: Long): Image {
            val begin = System.nanoTime()
            var image: Image? = null
            while (System.nanoTime() - begin < ms * 1_000_000) {
                image?.close()
                SwingUtilities.invokeAndWait { image = scene.render(System.nanoTime()) }
                Thread.sleep(20)
            }
            return image!!
        }
        fun shot(name: String, ms: Long = 1_500) {
            val image = render(ms)
            File(out, "$name.png").writeBytes(image.encodeToData(EncodedImageFormat.PNG)!!.bytes)
            image.close()
        }
        fun loopsOnShelf(): Int = File(folder.root, "loops").listFiles { f -> f.name.endsWith(".mp4") }?.size ?: 0
        fun waitFor(ms: Long, what: () -> Boolean) {
            val until = System.currentTimeMillis() + ms
            while (!what() && System.currentTimeMillis() < until) render(100).close()
        }
        // Frames through the still giving way to the loop, a few apart.
        fun crossfade(name: String, before: Int) {
            waitFor(40_000) { loopsOnShelf() > before }
            repeat(8) { i -> shot("$name-$i", 70) }
        }
        // How much a box of the window changes over a moment, from 0 to 255:
        // a loop playing there changes it, a still does not.
        fun change(left: Int, top: Int, size: Int, ms: Long = 900): Double {
            fun grid(): IntArray {
                val image = render(60)
                val bitmap = org.jetbrains.skia.Bitmap.makeFromImage(image)
                val points = IntArray(24 * 24) { i -> bitmap.getColor(left + (i % 24) * size / 24, top + (i / 24) * size / 24) }
                bitmap.close()
                image.close()
                return points
            }
            val first = grid()
            render(ms).close()
            val second = grid()
            return first.indices.sumOf { i ->
                (0..2).sumOf { c -> kotlin.math.abs(((first[i] shr (c * 8)) and 0xFF) - ((second[i] shr (c * 8)) and 0xFF)) }.toDouble() / 3
            } / first.size
        }
        fun use(setting: AnimatedArtSetting) = settings.update { it.copy(appearance = it.appearance.copy(animatedArt = setting.key)) }

        try {
            waitFor(20_000) { app.library?.index?.albums?.isNotEmpty() == true }
            val albums = app.library!!.index!!.albums
            fun album(name: String) = albums.first { it.name.startsWith(name) }
            val sweet = album("Short n")
            val midnights = album("Midnights")
            val gnx = album("GNX")

            // The album header: the cover, then the loop over it.
            SwingUtilities.invokeAndWait { app.navigator.go(Page.Album(sweet.id)) }
            shot("album-header-still", 600)
            crossfade("album-header-fade", 0)
            shot("album-header-playing", 2_000)
            val headerMoves = change(270, 62, 178)
            println("album header change: $headerMoves")
            check(headerMoves > 1.0) { "the album header's loop does not move: $headerMoves" }

            // An album with none keeps its cover.
            SwingUtilities.invokeAndWait { app.navigator.go(Page.Album(gnx.id)) }
            shot("album-header-none", 6_000)

            // The full player, the square loop in place of the cover.
            val sweetSongs = runBlocking { app.connection!!.client.album(sweet.id).song }
            SwingUtilities.invokeAndWait {
                app.play(sweetSongs)
                app.fullPlayer = true
                if (app.playerPanel != null) app.togglePlayerPanel(app.playerPanel!!)
            }
            shot("player-square", 4_000)
            val squareMoves = change(520, 140, 400)
            println("player square change: $squareMoves")
            check(squareMoves > 1.0) { "the player's square loop does not move: $squareMoves" }
            SwingUtilities.invokeAndWait { app.togglePlayerPanel(SidePanel.Lyrics) }
            shot("player-square-lyrics", 2_000)

            // Full screen: the tall loop behind, its still first.
            val shelved = loopsOnShelf()
            use(AnimatedArtSetting.FullScreen)
            // The cover giving way to the tall loop's still and fill.
            repeat(10) { i -> shot("player-full-in-$i", 110) }
            crossfade("player-full-fade", shelved)
            shot("player-full-lyrics", 2_000)
            SwingUtilities.invokeAndWait { app.togglePlayerPanel(SidePanel.Lyrics) }
            shot("player-full", 2_000)
            val tallMoves = change(560, 80, 320)
            println("player tall change: $tallMoves")
            check(tallMoves > 1.0) { "the tall loop does not move: $tallMoves" }
            // Held when the window is away: nothing decodes or reads frames.
            fun busy(ms: Long): Double {
                val threads = java.lang.management.ManagementFactory.getThreadMXBean()
                fun loopThreads() = threads.allThreadIds.filter { id ->
                    val name = threads.getThreadInfo(id)?.threadName.orEmpty()
                    name.startsWith("octo-video") || name.startsWith("DefaultDispatcher")
                }.sumOf { threads.getThreadCpuTime(it).coerceAtLeast(0) }
                val before = loopThreads()
                Thread.sleep(ms)
                return (loopThreads() - before) / (ms * 1e4)
            }
            SwingUtilities.invokeAndWait { shown.value = false }
            render(300).close()
            val held = busy(5_000)
            SwingUtilities.invokeAndWait { shown.value = true }
            render(1_500).close()
            val playing = busy(5_000)
            println("loop threads: held $held%, playing $playing% of one core")
            check(held < 1.0) { "a held loop still works: $held%" }
            SwingUtilities.invokeAndWait { app.fullPlayer = false }
            render(800).close()
            SwingUtilities.invokeAndWait { app.fullPlayer = true }
            shot("player-full-reopened", 1_500)

            // A long title over the tall loop.
            val midnightsSongs = runBlocking { app.connection!!.client.album(midnights.id).song }
            val long = midnightsSongs.maxBy { it.title.length }
            SwingUtilities.invokeAndWait { app.play(midnightsSongs, start = midnightsSongs.indexOf(long)) }
            waitFor(40_000) { loopsOnShelf() > shelved + 1 }
            shot("player-full-long-title", 4_000)
            SwingUtilities.invokeAndWait { app.togglePlayerPanel(SidePanel.Lyrics) }
            shot("player-full-long-title-lyrics", 2_000)

            // An album with none: the wash, as ever.
            val gnxSongs = runBlocking { app.connection!!.client.album(gnx.id).song }
            SwingUtilities.invokeAndWait { app.play(gnxSongs) }
            shot("player-full-none", 6_000)

            // Off: the still cover, even for an album with art.
            use(AnimatedArtSetting.Off)
            SwingUtilities.invokeAndWait { app.play(sweetSongs) }
            shot("player-off", 3_000)
        } finally {
            SwingUtilities.invokeAndWait { scene.close() }
            scope.cancel()
        }
    }
}
