package app.winters.octo.desktop.perf

import androidx.compose.runtime.CompositionLocalProvider
import androidx.compose.ui.awt.ComposeWindow
import androidx.compose.ui.text.font.FontFamily
import androidx.compose.ui.text.font.FontWeight
import androidx.compose.ui.text.platform.SystemFont
import app.winters.octo.design.LocalTyping
import app.winters.octo.design.ProvideWindowLook
import app.winters.octo.design.TextLook
import app.winters.octo.design.TypingState
import app.winters.octo.desktop.a11y.A11yScene
import app.winters.octo.desktop.nav.Page
import app.winters.octo.desktop.songJson
import app.winters.octo.desktop.ui.Shell
import app.winters.octo.desktop.window.useTextPixels
import org.jetbrains.skia.PixelGeometry
import org.junit.Assume.assumeTrue
import org.junit.Rule
import org.junit.Test
import org.junit.rules.TemporaryFolder
import java.awt.Dimension
import java.awt.Rectangle
import java.awt.Robot
import java.io.File
import javax.imageio.ImageIO
import javax.swing.SwingUtilities

// The real window on screen, read back from the screen itself, so the
// pictures are exactly what the listener sees: Home with a song in the
// player bar, an album's songs, and Settings. For comparing how text is
// drawn, at native pixels. Only when asked, one way per run, as a new JVM
// (the way is fixed once the first text style is read):
// OCTO_SHOTS=1 OCTO_TEXT=grey|colour OCTO_TEXT_FACE=system|variable
// ./gradlew :desktop:test --tests '*ScreenTextShots*'
// Writes OCTO_SHOTS_DIR (else build/shots) screen-<way>-<page>.png.
@OptIn(androidx.compose.ui.text.ExperimentalTextApi::class)
class ScreenTextShots {
    @get:Rule val folder = TemporaryFolder()

    @Test(timeout = 300_000)
    fun readTheScreen() {
        assumeTrue(System.getenv("OCTO_SHOTS") == "1" && System.getenv("OCTO_TEXT") != null)
        val colour = System.getenv("OCTO_TEXT") == "colour"
        val face = System.getenv("OCTO_TEXT_FACE") ?: "system"
        TextLook.colour = colour
        if (face == "variable") {
            TextLook.family = FontFamily(listOf(FontWeight.Light, FontWeight.Normal, FontWeight.Medium, FontWeight.SemiBold, FontWeight.Bold, FontWeight.Black).map { SystemFont("Segoe UI Variable Text", it) })
        }
        val way = "${if (colour) "colour" else "grey"}-$face"
        val out = File(System.getenv("OCTO_SHOTS_DIR") ?: "build/shots").apply { mkdirs() }
        A11yScene(folder.newFolder()).use { s ->
            s.onUi { s.app.play(s.app.library!!.index!!.songs, 0) }
            s.onUi { s.app.player.togglePlay() }
            lateinit var window: ComposeWindow
            SwingUtilities.invokeAndWait {
                window = ComposeWindow().apply {
                    title = "Octo text"
                    size = Dimension(1280, 800)
                    setLocation(40, 40)
                    isAlwaysOnTop = true
                    setContent {
                        ProvideWindowLook(reduceMotion = true) {
                            CompositionLocalProvider(LocalTyping provides TypingState()) { Shell(s.app, null) {} }
                        }
                    }
                    useTextPixels(this, if (colour) PixelGeometry.RGB_H else null)
                    isVisible = true
                }
            }
            SwingUtilities.invokeAndWait { println("$way: window layer pixels ${layerOf(window)?.pixelGeometry}") }
            s.server.answer("getAlbum", """"album":{"id":"a1","name":"OK Computer","artist":"Radiohead","year":1997,"songCount":3,"song":[${listOf(songJson("s1", "Airbag", artist = "Radiohead", album = "OK Computer", albumId = "a1", duration = 284), songJson("s2", "Paranoid Android", artist = "Radiohead", album = "OK Computer", albumId = "a1", duration = 387), songJson("s3", "Karma Police", artist = "Radiohead", album = "OK Computer", albumId = "a1", duration = 261)).joinToString(",")}]}""")
            val robot = Robot()
            fun capture(page: String) {
                Thread.sleep(2_500)
                lateinit var bounds: Rectangle
                SwingUtilities.invokeAndWait {
                    val at = window.contentPane.locationOnScreen
                    bounds = Rectangle(at.x, at.y, window.contentPane.width, window.contentPane.height)
                }
                ImageIO.write(robot.createScreenCapture(bounds), "png", File(out, "screen-$way-$page.png"))
            }
            try {
                capture("home")
                s.onUi { s.app.navigator.go(Page.Album("a1")) }
                capture("album")
                s.onUi { s.app.navigator.go(Page.Settings) }
                capture("settings")
                s.onUi {
                    s.app.playerPanel?.let(s.app::togglePlayerPanel)
                    s.app.fullPlayer = true
                }
                capture("player")
            } finally {
                SwingUtilities.invokeAndWait { window.dispose() }
            }
        }
    }
}

private fun layerOf(component: java.awt.Component): org.jetbrains.skiko.SkiaLayer? {
    if (component is org.jetbrains.skiko.SkiaLayer) return component
    if (component is java.awt.Container) component.components.forEach { child -> layerOf(child)?.let { return it } }
    return null
}
