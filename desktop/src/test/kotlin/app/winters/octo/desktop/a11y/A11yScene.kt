package app.winters.octo.desktop.a11y

import androidx.compose.runtime.CompositionLocalProvider
import androidx.compose.ui.ExperimentalComposeUiApi
import androidx.compose.ui.ImageComposeScene
import androidx.compose.ui.InternalComposeUiApi
import androidx.compose.ui.input.key.Key
import androidx.compose.ui.input.key.KeyEvent
import androidx.compose.ui.input.key.KeyEventType
import androidx.compose.ui.semantics.SemanticsActions
import androidx.compose.ui.semantics.SemanticsNode
import androidx.compose.ui.semantics.SemanticsProperties
import androidx.compose.ui.semantics.getOrNull
import androidx.compose.ui.platform.LocalDensity
import androidx.compose.ui.unit.Density
import app.winters.octo.design.ArrowKeys
import app.winters.octo.design.FocusVisibility
import app.winters.octo.design.LocalTyping
import app.winters.octo.design.ProvideWindowLook
import app.winters.octo.design.TypingState
import app.winters.octo.desktop.AppState
import app.winters.octo.desktop.FakeServer
import app.winters.octo.desktop.player.DesktopPlayer
import app.winters.octo.desktop.player.SilentPlayer
import app.winters.octo.desktop.secrets.SessionOnlySecrets
import app.winters.octo.desktop.server.Accounts
import app.winters.octo.desktop.settings.AppSettings
import app.winters.octo.desktop.settings.DesktopOs
import app.winters.octo.desktop.settings.SettingsStore
import app.winters.octo.desktop.songJson
import app.winters.octo.desktop.ui.Shell
import app.winters.octo.lyrics.OnlineLyrics
import kotlinx.coroutines.CoroutineScope
import kotlinx.coroutines.Dispatchers
import kotlinx.coroutines.SupervisorJob
import kotlinx.coroutines.cancel
import okhttp3.HttpUrl.Companion.toHttpUrl
import okhttp3.OkHttpClient
import java.io.File
import javax.swing.SwingUtilities

// The whole window, signed in to a pretend server with a small library, on
// the silent player, drawn off screen at one pixel a dp, for reading what a
// screen reader and the keyboard get.
@OptIn(ExperimentalComposeUiApi::class, InternalComposeUiApi::class)
class A11yScene(
    folder: File,
    reduceMotion: Boolean = false,
    val width: Int = 1440,
    val height: Int = 900,
    // A picture every song shares as its cover, or none.
    cover: ByteArray? = null,
    // Its id: covers are kept by server name and id for the whole run, so
    // each picture needs its own.
    coverId: String = "c1",
    look: (AppSettings) -> AppSettings = { it },
    // How much bigger the words are, as the text size setting makes them.
    textScale: Float = 1f,
    // The extensions the pretend server lists, like "songLyrics:2".
    extensions: List<String> = listOf(),
    // What plays: the silent player unless a test brings its own.
    player: DesktopPlayer = SilentPlayer(),
) : AutoCloseable {
    val server = FakeServer()
    private val scope = CoroutineScope(SupervisorJob() + Dispatchers.Main)
    val player = player
    val keyboard = FocusVisibility(keyboard = true)
    val arrows = ArrowKeys()
    lateinit var app: AppState
    val scene: ImageComposeScene

    init {
        val songs = listOf(
            songJson("s1", "Airbag", artist = "Radiohead", album = "OK Computer", albumId = "a1", duration = 284),
            songJson("s2", "Paranoid Android", artist = "Radiohead", album = "OK Computer", albumId = "a1", duration = 387),
            songJson("s3", "Karma Police", artist = "Radiohead", album = "OK Computer", albumId = "a1", duration = 261),
            songJson("s4", "Roads", artist = "Portishead", album = "Dummy", albumId = "a3", duration = 305),
            songJson("s5", "Teardrop", artist = "Massive Attack", album = "Mezzanine", albumId = "a5", duration = 330),
        ).map { if (cover != null) it.dropLast(1) + ""","coverArt":"$coverId"}""" else it }.joinToString(",")
        if (cover != null) server.file("getCoverArt", cover)
        server.answer("getAlbumList2", """"albumList2":{"album":[{"id":"a1","name":"OK Computer","artist":"Radiohead","year":1997,"songCount":3},{"id":"a3","name":"Dummy","artist":"Portishead","year":1994,"songCount":1}]}""")
        server.answer("getArtists", """"artists":{"index":[{"name":"R","artist":[{"id":"r1","name":"Radiohead","albumCount":1}]}]}""")
        server.answer("getPlaylists", """"playlists":{"playlist":[{"id":"p1","name":"Late night","songCount":2}]}""")
        server.answer("search3", """"searchResult3":{"song":[$songs]}""")
        server.answer("getStarred2", """"starred2":{}""")
        val settings = SettingsStore(File(folder, "settings.json"), 0)
        settings.update { look(it.copy(lyrics = it.lyrics.copy(online = false))) }
        val http = OkHttpClient()
        SwingUtilities.invokeAndWait {
            app = AppState(
                settings,
                Accounts(settings, SessionOnlySecrets(), http),
                http,
                scope,
                DesktopOs.Windows,
                player,
                OnlineLyrics(http, server.address.toHttpUrl()),
                restored = server.connection(extensions),
                listeningRoot = File(folder, "listening"),
            )
        }
        waitFor { app.library?.index != null }
        scene = ImageComposeScene(width, height, Density(1f)) {
            ProvideWindowLook(reduceMotion = reduceMotion, focus = keyboard, arrows = arrows) {
                CompositionLocalProvider(
                    LocalTyping provides TypingState(),
                    LocalDensity provides Density(1f, textScale),
                ) { Shell(app, null) {} }
            }
        }
        render(4)
    }

    fun waitFor(what: () -> Boolean) {
        val until = System.currentTimeMillis() + 10_000
        while (!what() && System.currentTimeMillis() < until) Thread.sleep(20)
        check(what()) { "waited too long" }
    }

    // Draws a few frames on the window's thread, letting effects run.
    fun render(frames: Int = 3) {
        repeat(frames) {
            SwingUtilities.invokeAndWait { scene.render() }
            Thread.sleep(15)
        }
    }

    fun onUi(block: () -> Unit) = SwingUtilities.invokeAndWait(block)

    // Draws for a while in real time, so covers load and fades finish, and
    // gives the last frame.
    fun settle(ms: Long = 1_500): org.jetbrains.skia.Image {
        val begin = System.nanoTime()
        var image: org.jetbrains.skia.Image? = null
        while (System.nanoTime() - begin < ms * 1_000_000) {
            image?.close()
            image = frameAt(System.nanoTime())
            Thread.sleep(30)
        }
        return image!!
    }

    // One frame drawn at a given moment of the scene's clock.
    fun frameAt(nanos: Long): org.jetbrains.skia.Image {
        lateinit var image: org.jetbrains.skia.Image
        SwingUtilities.invokeAndWait { image = scene.render(nanos) }
        return image
    }

    fun press(key: Key, shift: Boolean = false) {
        SwingUtilities.invokeAndWait {
            scene.sendKeyEvent(KeyEvent(key, KeyEventType.KeyDown, isShiftPressed = shift))
            scene.sendKeyEvent(KeyEvent(key, KeyEventType.KeyUp, isShiftPressed = shift))
        }
        render(2)
    }

    // Every node, depth first, in the unmerged tree.
    fun nodes(merged: Boolean = false): List<SemanticsNode> {
        val all = mutableListOf<SemanticsNode>()
        fun walk(node: SemanticsNode) {
            all += node
            node.children.forEach(::walk)
        }
        scene.semanticsOwners.forEach { walk(if (merged) it.rootSemanticsNode else it.unmergedRootSemanticsNode) }
        return all
    }

    // Tabs until the keyboard is on the control with this name, if it can.
    fun tabTo(name: String, presses: Int = 120): Boolean {
        repeat(presses) {
            if (focused()?.name() == name) return true
            press(Key.Tab)
        }
        return focused()?.name() == name
    }

    // Saves a frame for looking at, with OCTO_SHOTS=1.
    fun shot(name: String, ms: Long = 1_200) {
        val image = settle(ms)
        if (System.getenv("OCTO_SHOTS") != "1") return
        File("build/shots").mkdirs()
        File("build/shots/$name.png").writeBytes(image.encodeToData(org.jetbrains.skia.EncodedImageFormat.PNG)!!.bytes)
    }

    // The deepest node holding the keyboard.
    fun focused(): SemanticsNode? = nodes(merged = true).lastOrNull { it.config.getOrNull(SemanticsProperties.Focused) == true }

    override fun close() {
        runCatching { SwingUtilities.invokeAndWait { scene.close() } }
        scope.cancel()
        server.close()
    }
}

// What a screen reader calls a node: its description, or its words.
fun SemanticsNode.name(): String =
    config.getOrNull(SemanticsProperties.ContentDescription)?.joinToString(" ")?.takeIf(String::isNotBlank)
        ?: config.getOrNull(SemanticsProperties.Text)?.joinToString(" ") { it.text }?.takeIf(String::isNotBlank)
        ?: config.getOrNull(SemanticsProperties.EditableText)?.text?.takeIf(String::isNotBlank)
        ?: ""

val SemanticsNode.clickable: Boolean get() = config.getOrNull(SemanticsActions.OnClick) != null
