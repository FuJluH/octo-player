package app.winters.octo.desktop.perf

import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.runtime.CompositionLocalProvider
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue
import androidx.compose.ui.Modifier
import androidx.compose.ui.awt.ComposeWindow
import app.winters.octo.design.LocalTyping
import app.winters.octo.design.ProvideWindowLook
import app.winters.octo.design.TypingState
import app.winters.octo.desktop.AppState
import app.winters.octo.desktop.FakeServer
import app.winters.octo.desktop.SidePanel
import app.winters.octo.desktop.library.LocalCovers
import app.winters.octo.desktop.lyrics.madeUpLyricsAnswer
import app.winters.octo.desktop.nav.Page
import app.winters.octo.desktop.player.SilentPlayer
import app.winters.octo.desktop.secrets.SessionOnlySecrets
import app.winters.octo.desktop.server.Accounts
import app.winters.octo.desktop.settings.AmbienceStyle
import app.winters.octo.desktop.settings.DesktopOs
import app.winters.octo.desktop.settings.SettingsStore
import app.winters.octo.desktop.playStations
import app.winters.octo.desktop.songJson
import app.winters.octo.liveradio.LiveStation
import app.winters.octo.liveradio.radioId
import app.winters.octo.desktop.system.MINI_HEIGHT
import app.winters.octo.desktop.system.MINI_WIDTH
import app.winters.octo.desktop.system.MiniActions
import app.winters.octo.desktop.system.MiniPlayerView
import app.winters.octo.desktop.ui.LocalWindowShown
import app.winters.octo.desktop.ui.Shell
import app.winters.octo.lyrics.OnlineLyrics
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.cancel
import okhttp3.HttpUrl.Companion.toHttpUrl
import okhttp3.OkHttpClient
import org.jetbrains.skia.EncodedImageFormat
import org.jetbrains.skia.Paint
import org.jetbrains.skia.Rect
import org.jetbrains.skia.Surface
import org.jetbrains.skiko.SkiaLayer
import org.jetbrains.skiko.SkikoRenderDelegate
import org.junit.Assume.assumeTrue
import org.junit.Rule
import org.junit.Test
import org.junit.rules.TemporaryFolder
import java.awt.Component
import java.awt.Container
import java.awt.Dimension
import java.awt.Frame
import java.io.File
import java.lang.management.ManagementFactory
import java.util.concurrent.atomic.AtomicLong
import javax.swing.SwingUtilities

// The real window on screen, drawn by the graphics card, with a song
// playing on the silent player (time runs, no sound), walked through the
// places a listener spends time: Home, the full player, its lyrics, paused,
// the mini player, and minimized. For each it reads this process's
// processor time (as a share of one core) and how many frames the window
// drew, and notes when it measured each, in build/perf/playing-windows.csv,
// for the graphics card's counters read from outside. Writes
// build/perf/playing.txt. It only runs when asked:
// OCTO_PERF=1 ./gradlew :desktop:test --tests '*PlayingWindowProbe*'.
// OCTO_PERF_LABEL names the run; OCTO_PERF_SECONDS sets each window.
class PlayingWindowProbe {
    @get:Rule val folder = TemporaryFolder()

    private val lines = mutableListOf<String>()

    private fun say(line: String) {
        println(line)
        lines += line
    }

    @Test(timeout = 1_800_000)
    fun walkThePlayingWindow() {
        assumeTrue(System.getenv("OCTO_PERF") == "1")
        assumeTrue(System.getProperty("os.name").orEmpty().startsWith("Windows"))
        val seconds = System.getenv("OCTO_PERF_SECONDS")?.toIntOrNull() ?: 15
        val label = System.getenv("OCTO_PERF_LABEL") ?: "run"
        val pid = ProcessHandle.current().pid()
        say("== $label, pid $pid, $seconds s windows, ${Runtime.getRuntime().availableProcessors()} logical cores")

        val server = FakeServer()
        val scope = CoroutineScope(SupervisorJob() + Dispatchers.Main)
        val cover = madeUpCover()
        val songs = listOf(
            songJson("s1", "Airbag", artist = "Radiohead", album = "OK Computer", albumId = "a1", duration = 284),
            songJson("s2", "Paranoid Android", artist = "Radiohead", album = "OK Computer", albumId = "a1", duration = 387),
            songJson("s3", "Karma Police", artist = "Radiohead", album = "OK Computer", albumId = "a1", duration = 261),
        ).map { it.dropLast(1) + ""","coverArt":"probe"}""" }.joinToString(",")
        server.file("getCoverArt", cover)
        server.answer("getAlbumList2", """"albumList2":{"album":[{"id":"a1","name":"OK Computer","artist":"Radiohead","year":1997,"songCount":3,"coverArt":"probe"}]}""")
        server.answer("getArtists", """"artists":{"index":[{"name":"R","artist":[{"id":"r1","name":"Radiohead","albumCount":1}]}]}""")
        server.answer("getPlaylists", """"playlists":{"playlist":[]}""")
        server.answer("search3", """"searchResult3":{"song":[$songs]}""")
        server.answer("getStarred2", """"starred2":{}""")
        server.answer("getLyricsBySongId", madeUpLyricsAnswer())
        server.answer("getAlbum", """"album":{"id":"a1","name":"OK Computer","artist":"Radiohead","year":1997,"songCount":3,"coverArt":"probe","song":[$songs]}""")
        val settings = SettingsStore(File(folder.root, "settings.json"), 0)
        settings.update {
            it.copy(
                lyrics = it.lyrics.copy(online = false),
                appearance = it.appearance.copy(ambience = AmbienceStyle.Immersive),
            )
        }
        val http = OkHttpClient()
        val player = SilentPlayer(scope = scope)
        lateinit var app: AppState
        SwingUtilities.invokeAndWait {
            app = AppState(
                settings,
                Accounts(settings, SessionOnlySecrets(), http),
                http,
                scope,
                DesktopOs.Windows,
                player,
                OnlineLyrics(http, server.address.toHttpUrl()),
                restored = server.connection(listOf("songLyrics:1", "songLyrics:2")),
                listeningRoot = File(folder.root, "listening"),
            )
        }
        waitFor { app.library?.index != null }

        var shown by mutableStateOf(true)
        val mainFrames = AtomicLong()
        val miniFrames = AtomicLong()
        lateinit var main: ComposeWindow
        lateinit var mini: ComposeWindow
        SwingUtilities.invokeAndWait {
            main = ComposeWindow().apply {
                title = "Octo probe"
                size = Dimension(1440, 900)
                setLocationRelativeTo(null)
                setContent {
                    ProvideWindowLook(reduceMotion = false) {
                        CompositionLocalProvider(LocalTyping provides TypingState(), LocalWindowShown provides shown) {
                            Shell(app, null) {}
                        }
                    }
                }
                addWindowStateListener { shown = isVisible && (extendedState and Frame.ICONIFIED) == 0 }
                isVisible = true
            }
            mini = ComposeWindow().apply {
                title = "Octo probe mini"
                isUndecorated = true
                isAlwaysOnTop = true
                size = Dimension(MINI_WIDTH.toInt(), MINI_HEIGHT.toInt())
                setLocation(80, 80)
                setContent {
                    ProvideWindowLook(reduceMotion = false) {
                        CompositionLocalProvider(LocalCovers provides app.connection?.client) {
                            Box(Modifier.fillMaxSize()) {
                                MiniPlayerView(app, panel = null, pinned = false, actions = MiniActions({}, { _, _ -> }, {}, {}), dragArea = {})
                            }
                        }
                    }
                }
            }
        }
        count(main, mainFrames)

        // The windows each place was measured over, for reading the graphics
        // card's counters against (sampled from outside, since a PowerShell
        // started from here opens a console that takes the window's focus).
        val windows = File("build/perf").apply { mkdirs() }.let { File(it, "playing-windows.csv") }
        windows.appendText("label,pid,place,startMs,endMs\n")
        fun step(name: String, change: () -> Unit) {
            SwingUtilities.invokeAndWait(change)
            if (runOnUi { mini.isVisible }) count(mini, miniFrames)
            Thread.sleep(SETTLE_MS)
            val focused = runOnUi { main.isFocused || mini.isFocused }
            val cpu0 = processCpuNanos()
            val main0 = mainFrames.get()
            val mini0 = miniFrames.get()
            val t0 = System.nanoTime()
            val start = System.currentTimeMillis()
            Thread.sleep(seconds * 1000L)
            val wall = (System.nanoTime() - t0) / 1e9
            val cpu = (processCpuNanos() - cpu0) / 1e9 / wall * 100
            val frames = (mainFrames.get() - main0) / wall
            val miniRate = (miniFrames.get() - mini0) / wall
            windows.appendText("$label,$pid,$name,$start,${System.currentTimeMillis()}\n")
            say("  %-28s cpu %6.1f%% of a core | main %5.1f frames/s | mini %5.1f frames/s | focused %s".format(name, cpu, frames, miniRate, focused))
        }

        try {
            SwingUtilities.invokeAndWait {
                app.play(app.library!!.index!!.songs, 0)
                main.toFront()
                main.requestFocus()
            }
            Thread.sleep(4_000)
            step("home, playing") {}
            step("full player, playing") {
                app.playerPanel?.let(app::togglePlayerPanel)
                app.fullPlayer = true
            }
            step("lyrics, playing") { app.togglePlayerPanel(SidePanel.Lyrics) }
            step("lyrics, paused") { app.player.togglePlay() }
            step("full player, paused") {
                app.togglePlayerPanel(SidePanel.Lyrics)
            }
            step("home, paused") { app.fullPlayer = false }
            step("home, playing, Glow") {
                app.player.togglePlay()
                settings.update { it.copy(appearance = it.appearance.copy(ambience = AmbienceStyle.Glow)) }
            }
            step("home, playing, Immersive") {
                settings.update { it.copy(appearance = it.appearance.copy(ambience = AmbienceStyle.Immersive)) }
            }
            step("album page, playing") { app.navigator.go(Page.Album("a1")) }
            step("side lyrics, playing") {
                app.navigator.go(Page.Home)
                app.toggleSidePanel(SidePanel.Lyrics)
            }
            step("side lyrics, paused") { app.player.togglePlay() }
            step("home, paused, Glow") {
                app.toggleSidePanel(SidePanel.Lyrics)
                settings.update { it.copy(appearance = it.appearance.copy(ambience = AmbienceStyle.Glow)) }
            }
            step("home, live station") {
                settings.update { it.copy(appearance = it.appearance.copy(ambience = AmbienceStyle.Immersive)) }
                app.playStations(listOf(LiveStation("u1", "KROQ 106.7", "https://stream.example/kroq", state = "California").radioId()), 0, "Live radio")
            }
            step("full player, live station") { app.fullPlayer = true }
            step("home, playing again") {
                app.fullPlayer = false
                app.play(app.library!!.index!!.songs, 0)
            }
            step("mini player, playing") {
                main.isVisible = false
                shown = false
                mini.isVisible = true

            }
            step("mini player, paused") { app.player.togglePlay() }
            step("minimized, playing") {
                app.player.togglePlay()
                mini.isVisible = false
                main.isVisible = true
                main.extendedState = Frame.ICONIFIED
                shown = false
            }
        } finally {
            SwingUtilities.invokeAndWait {
                runCatching { app.player.togglePlay() }
                mini.dispose()
                main.dispose()
            }
            scope.cancel()
            server.close()
        }
        val out = File("build/perf").apply { mkdirs() }
        File(out, "playing.txt").appendText(lines.joinToString("\n", postfix = "\n"))
    }

    // Counts the frames a window's drawing layer draws.
    private fun count(window: ComposeWindow, frames: AtomicLong) {
        SwingUtilities.invokeAndWait {
            val layer = findLayer(window) ?: return@invokeAndWait say("  (no drawing layer found to count frames)")
            val inner = layer.renderDelegate ?: return@invokeAndWait
            if (inner is Counting) return@invokeAndWait
            layer.renderDelegate = Counting(inner, frames)
        }
    }

    private class Counting(private val inner: SkikoRenderDelegate, private val frames: AtomicLong) : SkikoRenderDelegate {
        override fun onRender(canvas: org.jetbrains.skia.Canvas, width: Int, height: Int, nanoTime: Long) {
            frames.incrementAndGet()
            inner.onRender(canvas, width, height, nanoTime)
        }
    }

    private fun findLayer(component: Component): SkiaLayer? {
        if (component is SkiaLayer) return component
        if (component is Container) component.components.forEach { child -> findLayer(child)?.let { return it } }
        return null
    }

    private fun <T> runOnUi(block: () -> T): T {
        var value: T? = null
        SwingUtilities.invokeAndWait { value = block() }
        @Suppress("UNCHECKED_CAST")
        return value as T
    }

    private fun processCpuNanos(): Long =
        (ManagementFactory.getOperatingSystemMXBean() as com.sun.management.OperatingSystemMXBean).processCpuTime

    private fun waitFor(what: () -> Boolean) {
        val until = System.currentTimeMillis() + 15_000
        while (!what() && System.currentTimeMillis() < until) Thread.sleep(20)
        check(what()) { "waited too long" }
    }

    private fun madeUpCover(): ByteArray {
        val surface = Surface.makeRasterN32Premul(600, 600)
        val canvas = surface.canvas
        canvas.clear(0xFF1B2A4A.toInt())
        val paint = Paint()
        paint.color = 0xFFE0703A.toInt()
        canvas.drawCircle(160f, 200f, 180f, paint)
        paint.color = 0xFF3AA6A0.toInt()
        canvas.drawCircle(440f, 300f, 200f, paint)
        paint.color = 0xFFF2D06B.toInt()
        canvas.drawRect(Rect.makeXYWH(80f, 420f, 300f, 120f), paint)
        return surface.makeImageSnapshot().encodeToData(EncodedImageFormat.PNG)!!.bytes
    }

    private companion object {
        const val SETTLE_MS = 3_000L
    }
}
