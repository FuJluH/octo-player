package app.winters.octo.desktop.perf

import androidx.compose.foundation.background
import androidx.compose.foundation.layout.Box
import androidx.compose.foundation.layout.Row
import androidx.compose.foundation.layout.Spacer
import androidx.compose.foundation.layout.fillMaxHeight
import androidx.compose.foundation.layout.fillMaxSize
import androidx.compose.runtime.Composable
import androidx.compose.runtime.currentComposer
import androidx.compose.runtime.tooling.CompositionData
import androidx.compose.ui.ImageComposeScene
import androidx.compose.ui.Modifier
import androidx.compose.ui.unit.Density
import app.winters.octo.design.OctoColors
import app.winters.octo.desktop.lyrics.FlowingLyrics
import app.winters.octo.desktop.lyrics.lyricEngine
import app.winters.octo.desktop.lyrics.madeUpLyrics
import app.winters.octo.desktop.lyrics.madeUpLyricsAnswer
import app.winters.octo.desktop.a11y.A11yScene
import app.winters.octo.desktop.player.wash.WashCover
import app.winters.octo.desktop.player.wash.WashCovers
import app.winters.octo.desktop.ui.ImmersiveBackdrop
import app.winters.octo.lyrics.Lyrics
import app.winters.octo.lyrics.LyricsLook
import app.winters.octo.lyrics.engine.LyricEngine
import app.winters.octo.player.immersive.BaseBpm
import app.winters.octo.player.immersive.WashTuning
import org.jetbrains.skia.EncodedImageFormat
import org.jetbrains.skia.Image
import org.jetbrains.skia.Paint
import org.jetbrains.skia.Rect
import org.jetbrains.skia.Surface
import org.jetbrains.skiko.graphicapi.DirectXOffscreenContext
import org.junit.Assume.assumeTrue
import org.junit.Rule
import org.junit.Test
import org.junit.rules.TemporaryFolder
import java.io.File
import java.lang.management.ManagementFactory
import java.time.LocalDateTime
import javax.swing.SwingUtilities

// Times the full player's flowing lyrics while a song plays, off screen,
// and writes what it found to build/perf/lyrics.txt: the whole frame
// (lyrics alone, and over the moving wash), what composing costs a second,
// and how many lines are drawn again each frame. On Windows the frames are
// drawn with Direct3D, the way the window draws them, and each is timed
// until the graphics card has finished it; everywhere they are also drawn
// on the processor, which is what the window falls back to without a
// usable graphics card. It only runs when asked:
// OCTO_PERF=1 ./gradlew :desktop:test --tests '*LyricsPerfTest*'.
// OCTO_PERF_LABEL names the run in the file; OCTO_PERF_NO_WASH=1 leaves out
// the runs over the wash, and OCTO_PERF_GPU_ONLY=1 those on the processor.
class LyricsPerfTest {
    @get:Rule val folder = TemporaryFolder()

    private val lines = mutableListOf<String>()

    private fun say(line: String) {
        println(line)
        lines += line
    }

    private class Size(val width: Int, val height: Int, val density: Float) {
        override fun toString() = "$width x $height at ${density}x"
    }

    @Test
    fun measureTheLyrics() {
        assumeTrue(System.getenv("OCTO_PERF") == "1")
        val runtime = ManagementFactory.getRuntimeMXBean()
        say("Octo flowing lyrics performance, ${LocalDateTime.now().withNano(0)}")
        say("JVM ${runtime.vmVendor} ${runtime.vmName} ${System.getProperty("java.version")}, ${Runtime.getRuntime().availableProcessors()} cores")
        say("The lyrics fill the right half, as in the full player, playing word-timed lines (48, a held word every fourth, a translation every sixth, one interlude).")
        say("Frames are offered on a 60 Hz beat in real time. Frame = ms to draw it whole, until the graphics card finished; cpu = ms on the window's thread before that.")
        say("Recomposed = composable scopes run again a second while playing; redrawn = lines drawn again a frame, of those on screen.")
        val lyrics = madeUpLyrics()
        val cover = WashCovers.prepared("perf", madeUpCover(), WashTuning())
        val gpu = offscreenGpu()
        val label = System.getenv("OCTO_PERF_LABEL")?.let { " ($it)" } ?: ""
        val gpuOnly = gpu != null && System.getenv("OCTO_PERF_GPU_ONLY") == "1"
        for (size in SIZES) {
            say("")
            say("$size$label")
            for (wash in if (System.getenv("OCTO_PERF_NO_WASH") == "1") listOf(false) else listOf(false, true)) {
                if (gpu != null) measure(size, wash, lyrics, cover, gpu, GPU_FRAMES, GPU_WARMUP) else if (!wash) say("  Direct3D off screen is not available here.")
                if (!gpuOnly) measure(size, wash, lyrics, cover, null, CPU_FRAMES, CPU_WARMUP)
            }
        }
        say("")
        say("The whole window at 1440 x 900 as the app draws it (Shell, signed in to a pretend server), the full player open on these lyrics over the cover's moving wash$label")
        if (gpu != null) measureWindow(gpu, GPU_FRAMES, GPU_WARMUP)
        if (!gpuOnly) measureWindow(null, WINDOW_CPU_FRAMES, CPU_WARMUP)
        gpu?.close()
        val out = File("build/perf").apply { mkdirs() }
        File(out, "lyrics.txt").writeText(lines.joinToString("\n", postfix = "\n"))
    }

    private fun measure(size: Size, wash: Boolean, lyrics: Lyrics, cover: WashCover, gpu: DirectXOffscreenContext?, frames: Int, warmup: Int) {
        var data: CompositionData? = null
        // The song's clock: the scene's own, from 20 s in.
        var sceneNanos = 0L
        val scene = ImageComposeScene(size.width, size.height, Density(size.density)) {
            data = currentComposer.compositionData
            Probe(lyrics, cover, wash) { START_MS + sceneNanos / 1_000_000 }
        }
        val target = gpu?.let { GpuTarget(it, size.width, size.height) }
        target?.let { swapSurface(scene, it.surface) }
        val times = DoubleArray(frames)
        val cpu = DoubleArray(frames)
        var redrawn = 0L
        var onScreen = 0L
        var engine: LyricEngine? = null
        var recompositions: Recompositions? = null
        val start = System.nanoTime()
        var measuredFrom = start
        for (i in -warmup until frames) {
            waitUntil(start + (i + warmup) * FRAME_NANOS)
            if (i == 0) {
                measuredFrom = System.nanoTime()
                recompositions = Recompositions()
            }
            sceneNanos = System.nanoTime() - start
            if (engine == null) engine = data?.lyricEngine()
            val before = engine?.let { e -> IntArray(e.states.size) { e.states[it].drawVersion.intValue } }
            val begin = System.nanoTime()
            scene.render(sceneNanos).close()
            val drawn = System.nanoTime()
            target?.finish()
            val end = System.nanoTime()
            if (i >= 0) {
                times[i] = (end - begin) / 1e6
                cpu[i] = (drawn - begin) / 1e6
                val e = engine
                if (e != null && before != null) {
                    val shown = e.shown.value
                    onScreen += shown.count()
                    redrawn += shown.count { before[it] != e.states[it].drawVersion.intValue }
                }
            }
        }
        val seconds = (System.nanoTime() - measuredFrom) / 1e9
        val scopes = recompositions?.take()?.rerun ?: 0L
        recompositions?.close()
        if (target == null && size == SIZES.first()) {
            File("build/perf").mkdirs()
            File("build/perf/lyrics-${if (wash) "wash" else "plain"}.png").writeBytes(scene.render(System.nanoTime() - start).encodeToData(EncodedImageFormat.PNG)!!.bytes)
        }
        scene.close()
        target?.close()
        times.sort()
        cpu.sort()
        say(
            "  %-3s %-11s frame mean %6.2f median %6.2f p95 %6.2f max %6.2f | cpu mean %5.2f p95 %5.2f | recomposed %5.1f/s | redrawn %.2f of %.1f".format(
                if (gpu != null) "GPU" else "CPU",
                if (wash) "over wash" else "lyrics",
                times.average(),
                times[times.size / 2],
                times[(times.size * 95) / 100],
                times.last(),
                cpu.average(),
                cpu[(cpu.size * 95) / 100],
                scopes / seconds,
                redrawn.toDouble() / frames,
                onScreen.toDouble() / frames,
            ),
        )
    }

    // The whole window with a song playing in the full player, its lyrics
    // from the pretend server, timed as a window frame is drawn: on the
    // window's thread, until the graphics card finished.
    private fun measureWindow(gpu: DirectXOffscreenContext?, frames: Int, warmup: Int) {
        val cover = madeUpCover().encodeToData(EncodedImageFormat.PNG)!!.bytes
        A11yScene(folder.newFolder(), cover = cover, extensions = listOf("songLyrics:1", "songLyrics:2")).use { s ->
            s.server.answer("getLyricsBySongId", madeUpLyricsAnswer())
            s.onUi {
                s.app.play(s.app.library!!.index!!.songs, 0)
                s.app.fullPlayer = true
            }
            s.player.seekTo(START_MS)
            // The cover, the wash and the lyrics arrive and settle.
            s.settle(4_000).close()
            val target = gpu?.let { GpuTarget(it, s.width, s.height) }
            target?.let { swapSurface(s.scene, it.surface) }
            val times = DoubleArray(frames)
            val cpu = DoubleArray(frames)
            var recompositions: Recompositions? = null
            val start = System.nanoTime()
            var measuredFrom = start
            for (i in -warmup until frames) {
                waitUntil(start + (i + warmup) * FRAME_NANOS)
                if (i == 0) {
                    measuredFrom = System.nanoTime()
                    recompositions = Recompositions()
                }
                var took = 0.0
                var thread = 0.0
                SwingUtilities.invokeAndWait {
                    val begin = System.nanoTime()
                    s.scene.render(begin).close()
                    val drawn = System.nanoTime()
                    target?.finish()
                    took = (System.nanoTime() - begin) / 1e6
                    thread = (drawn - begin) / 1e6
                }
                if (i >= 0) {
                    times[i] = took
                    cpu[i] = thread
                }
            }
            val seconds = (System.nanoTime() - measuredFrom) / 1e9
            val counts = recompositions?.take()
            recompositions?.close()
            // A look at the window, to be sure the lyrics were there.
            if (target == null) {
                File("build/perf").mkdirs()
                s.frameAt(System.nanoTime()).use { File("build/perf/lyrics-window.png").writeBytes(it.encodeToData(EncodedImageFormat.PNG)!!.bytes) }
            }
            target?.close()
            times.sort()
            cpu.sort()
            say(
                "  %-3s %-11s frame mean %6.2f median %6.2f p95 %6.2f max %6.2f | cpu mean %5.2f p95 %5.2f | recomposed %5.1f/s".format(
                    if (gpu != null) "GPU" else "CPU",
                    "window",
                    times.average(),
                    times[times.size / 2],
                    times[(times.size * 95) / 100],
                    times.last(),
                    cpu.average(),
                    cpu[(cpu.size * 95) / 100],
                    (counts?.rerun ?: 0L) / seconds,
                ),
            )
        }
    }

    // The full player in miniature: the wash or the page colour behind,
    // the cover's half left empty, the lyrics on the right.
    @Composable
    private fun Probe(lyrics: Lyrics, cover: WashCover, wash: Boolean, position: () -> Long) {
        Box(Modifier.fillMaxSize().background(OctoColors.Background)) {
            if (wash) ImmersiveBackdrop(cover, 1f, BaseBpm, 30, 0.125f, moving = true)
            Row(Modifier.fillMaxSize()) {
                Spacer(Modifier.weight(1f))
                Box(Modifier.weight(1f).fillMaxHeight()) {
                    FlowingLyrics(
                        lyrics,
                        playing = true,
                        trackKey = "perf",
                        positionMs = position,
                        speed = { 1f },
                        offsetMs = 0,
                        outputOffsetMs = 0,
                        look = LyricsLook(),
                        calm = false,
                        onSeek = {},
                    )
                }
            }
        }
    }

    // Waits for a moment to the tenth of a millisecond: short sleeps (the
    // system keeps those to the millisecond), then a spin.
    private fun waitUntil(moment: Long) {
        while (moment - System.nanoTime() > 2_000_000) Thread.sleep(minOf((moment - System.nanoTime()) / 1_000_000 - 1, 9))
        while (System.nanoTime() < moment) Thread.onSpinWait()
    }

    // A cover of soft coloured shapes.
    private fun madeUpCover(): Image {
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
        return surface.makeImageSnapshot()
    }

    private companion object {
        val SIZES = listOf(Size(1440, 900, 1f), Size(2560, 1440, 2f))
        const val START_MS = 20_000L
        const val GPU_WARMUP = 120
        const val GPU_FRAMES = 900
        const val CPU_WARMUP = 20
        const val CPU_FRAMES = 90
        const val WINDOW_CPU_FRAMES = 40
        const val FRAME_NANOS = 16_666_667L
    }
}
