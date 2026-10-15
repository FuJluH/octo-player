package app.winters.octo.desktop.perf

import androidx.compose.runtime.mutableStateOf
import androidx.compose.ui.window.application
import app.winters.octo.desktop.a11y.A11yScene
import app.winters.octo.desktop.settings.DesktopOs
import app.winters.octo.desktop.settings.WindowSpot
import app.winters.octo.desktop.system.MINI_HEIGHT
import app.winters.octo.desktop.system.MINI_SQUARE_HEIGHT
import app.winters.octo.desktop.system.MINI_SQUARE_WIDTH
import app.winters.octo.desktop.system.MINI_WIDTH
import app.winters.octo.desktop.system.MiniPlayerWindow
import org.jetbrains.skia.EncodedImageFormat
import org.jetbrains.skia.Paint
import org.jetbrains.skia.Surface
import org.junit.Assume.assumeTrue
import org.junit.Rule
import org.junit.Test
import org.junit.rules.TemporaryFolder
import java.awt.Color
import java.awt.Frame
import java.awt.Rectangle
import java.awt.Robot
import java.io.File
import javax.imageio.ImageIO
import javax.swing.JFrame
import javax.swing.SwingUtilities
import kotlin.concurrent.thread

// The real mini player window on screen, over a plain white window, read
// back from the screen: its whole frame and a little round it, so its
// corners show as the listener sees them, as a bar and with the cover
// large. Only when asked: OCTO_SHOTS=1 ./gradlew :desktop:test --tests
// '*MiniCornersShots*'. Writes OCTO_SHOTS_DIR (else build/shots)
// mini-corners-<shape>.png; OCTO_SHOTS_NAME is put before the shape.
class MiniCornersShots {
    @get:Rule val folder = TemporaryFolder()

    @Test(timeout = 300_000)
    fun readTheCorners() {
        assumeTrue(System.getenv("OCTO_SHOTS") == "1")
        val out = File(System.getenv("OCTO_SHOTS_DIR") ?: "build/shots").apply { mkdirs() }
        val prefix = System.getenv("OCTO_SHOTS_NAME")?.let { "$it-" }.orEmpty()
        val cover = Surface.makeRasterN32Premul(300, 300).run {
            canvas.clear(0xFFE0703A.toInt())
            canvas.drawCircle(150f, 150f, 90f, Paint().apply { color = 0xFF3AA6A0.toInt() })
            makeImageSnapshot().encodeToData(EncodedImageFormat.PNG)!!.bytes
        }
        A11yScene(folder.newFolder(), cover = cover, coverId = "corners").use { s ->
            s.onUi { s.app.play(s.app.library!!.index!!.songs, 0) }
            s.onUi { s.app.player.togglePlay() }
            lateinit var back: JFrame
            SwingUtilities.invokeAndWait {
                back = JFrame("white").apply {
                    isUndecorated = true
                    contentPane.background = Color.WHITE
                    bounds = Rectangle(60, 60, 640, 640)
                    isVisible = true
                }
            }
            val robot = Robot()
            for ((shape, size) in listOf("bar" to (MINI_WIDTH to MINI_HEIGHT), "cover" to (MINI_SQUARE_WIDTH to MINI_SQUARE_HEIGHT), "pinned" to (MINI_WIDTH to MINI_HEIGHT))) {
                if (shape == "pinned") s.app.settings.update { it.copy(system = it.system.copy(miniPlayerPinned = false)) }
                val open = mutableStateOf(true)
                val app = thread {
                    application(exitProcessOnExit = false) {
                        if (open.value) {
                            MiniPlayerWindow(s.app, WindowSpot(140f, 140f, size.first, size.second), DesktopOs.Windows, null, onMoved = {}, onClose = { open.value = false }, reduceMotion = true)
                        }
                    }
                }
                Thread.sleep(3_000)
                // Pinned while open, as the pin button does.
                if (shape == "pinned") {
                    s.app.settings.update { it.copy(system = it.system.copy(miniPlayerPinned = true)) }
                    Thread.sleep(1_500)
                }
                val window = Frame.getFrames().firstOrNull { it.title == "Octo mini player" && it.isShowing } ?: error("no mini player")
                val at = window.locationOnScreen
                val grab = Rectangle(at.x - 12, at.y - 12, window.width + 24, window.height + 24)
                ImageIO.write(robot.createScreenCapture(grab), "png", File(out, "${prefix}mini-corners-$shape.png"))

                SwingUtilities.invokeAndWait { open.value = false }
                app.join(5_000)
            }
            SwingUtilities.invokeAndWait { back.dispose() }
        }
    }
}
