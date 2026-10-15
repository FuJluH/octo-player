package app.winters.octo.desktop.ui

import androidx.compose.runtime.CompositionLocalProvider
import androidx.compose.runtime.getValue
import androidx.compose.runtime.mutableStateOf
import androidx.compose.runtime.setValue
import androidx.compose.ui.ImageComposeScene
import app.winters.octo.desktop.player.DesktopPlayer
import app.winters.octo.desktop.player.SilentPlayer
import app.winters.octo.subsonic.Song
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test
import java.util.concurrent.atomic.AtomicInteger

// The player bar's clock asks the player where the song is only while it
// can move and be seen: a paused song, or a hidden window, asks nothing,
// and a seek while paused still shows at once.
class PositionReadsTest {
    private var clock = 0L

    private class Counting(private val inner: DesktopPlayer) : DesktopPlayer by inner {
        val asked = AtomicInteger()

        override fun positionMs(): Long {
            asked.incrementAndGet()
            return inner.positionMs()
        }
    }

    @Test
    fun theClockOnlyAsksWhileASongPlaysOnScreen() {
        val player = Counting(SilentPlayer(clock = { clock }))
        player.play(listOf(Song("s1", "Song", duration = 300)))
        player.pause()
        var shown by mutableStateOf(true)
        var seen = -1L
        val scene = ImageComposeScene(100, 100) {
            CompositionLocalProvider(LocalWindowShown provides shown) {
                val position by rememberPosition(player, lengthPx = 600f)
                seen = position
            }
        }
        fun runFor(ms: Long) {
            val until = System.currentTimeMillis() + ms
            while (System.currentTimeMillis() < until) {
                scene.render()
                Thread.sleep(20)
            }
        }
        runFor(200)
        player.asked.set(0)
        runFor(1_000)
        assertEquals("paused, the place is not asked for", 0, player.asked.get())

        player.seekTo(42_000)
        runFor(100)
        assertEquals("a seek while paused shows at once", 42_000L, seen)

        shown = false
        player.resume()
        runFor(200)
        player.asked.set(0)
        runFor(1_000)
        assertEquals("a hidden window does not ask", 0, player.asked.get())

        shown = true
        runFor(1_000)
        assertTrue("playing on screen, it asks a few times a second", player.asked.get() >= 3)
        scene.close()
    }
}
