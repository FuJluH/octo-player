package app.winters.octo.desktop.ui

import app.winters.octo.desktop.a11y.A11yScene
import app.winters.octo.desktop.perf.Recompositions
import org.junit.Assert.assertTrue
import org.junit.Rule
import org.junit.Test
import org.junit.rules.TemporaryFolder

// The full player's seek line glides every frame while a song plays, but
// the player's code runs again only when a time on it changes, about once
// a second, not on every frame.
class FullPlayerFramesTest {
    @get:Rule val folder = TemporaryFolder()

    @Test(timeout = 120_000)
    fun aPlayingSongDoesNotComposeThePlayerEveryFrame() {
        A11yScene(folder.root).use { s ->
            s.onUi {
                s.app.play(s.app.library!!.index!!.songs, 0)
                s.app.fullPlayer = true
            }
            // Let the opening settle.
            s.render(90)
            val recompositions = Recompositions()
            val frames = 120
            val started = System.nanoTime()
            s.render(frames)
            val seconds = (System.nanoTime() - started) / 1e9
            val counts = recompositions.take()
            recompositions.close()
            println("Full player, $frames frames in %.1f s: ${counts.passes} passes, ${counts.visited} scopes visited, ${counts.rerun} run again".format(seconds))
            // Fewer than one every other frame, past the few a second the
            // player bar's clock and the rest of the window make.
            assertTrue("${counts.rerun} scopes run again in $frames frames over %.1f s".format(seconds), counts.rerun < frames / 2 + 8 * seconds)
        }
    }
}
