package app.winters.octo.desktop.lyrics

import androidx.compose.ui.geometry.Offset
import androidx.compose.ui.geometry.Size
import androidx.compose.ui.graphics.Color
import androidx.compose.ui.graphics.skiaImageFilter
import androidx.compose.ui.unit.Density
import androidx.compose.ui.unit.LayoutDirection
import app.winters.octo.lyrics.engine.LineState
import app.winters.octo.lyrics.engine.SyncLine
import app.winters.octo.lyrics.engine.SyncWord
import org.jetbrains.skia.Bitmap
import org.jetbrains.skia.Paint
import org.jetbrains.skia.Picture
import org.jetbrains.skia.PictureRecorder
import org.jetbrains.skia.RTreeFactory
import org.jetbrains.skia.Rect
import org.jetbrains.skia.Surface
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertNotSame
import org.junit.Assert.assertNull
import org.junit.Assert.assertSame
import org.junit.Assert.assertTrue
import org.junit.Test
import kotlin.math.abs

// A line resting at a blur is shown from a copy blurred off the window's
// thread; one whose drawing or blur moves draws itself again, and copies
// that arrive too late are dropped.
class LinePicturesTest {
    private val tasks = ArrayDeque<Runnable>()
    private val pictures = LinePictures(density = 2f, worker = { tasks.addLast(it) })
    private val states = listOf(LineState(SyncLine(0, "line", listOf(SyncWord("line", 0.0, 1.0, true)), 0.0, 1.0)))
    private val st = states[0]
    private val ms = 1_000_000L

    private fun draw() {
        pictures.record(pictures.line(0), st.drawVersion.intValue, Size(200f, 40f), Density(2f), LayoutDirection.Ltr) {
            drawRect(Color.White, Offset(10f, 8f), Size(120f, 20f))
        }
    }

    private fun frame(at: Long) = pictures.follow(states, 0..0, at)

    private fun work() {
        while (tasks.isNotEmpty()) tasks.removeFirst().run()
    }

    private val shown get() = pictures.line(0).copy.value

    @Test
    fun aLineThatHoldsStillIsShownFromACopyAtItsBlur() {
        st.blur = 1.0
        draw()
        frame(0)
        frame(50 * ms)
        assertTrue("nothing is made while the line may still be moving", tasks.isEmpty())
        frame(120 * ms)
        assertEquals(1, tasks.size)
        frame(130 * ms)
        assertEquals("one copy at a time", 1, tasks.size)
        assertNull(shown)
        work()
        frame(140 * ms)
        assertNotNull(shown)
        val copy = shown!!
        assertEquals(2f, copy.radius)
        assertEquals(st.drawVersion.intValue, copy.version)
        assertNotNull(copy.image)
    }

    @Test
    fun aNewBlurDrawsLiveUntilItsOwnCopyIsMadeAndTheOldOneIsKept() {
        st.blur = 1.0
        draw()
        frame(0)
        frame(120 * ms)
        work()
        frame(130 * ms)
        val first = shown!!
        st.blur = 2.0
        frame(140 * ms)
        assertNull("no copy at the new strength yet", shown)
        frame(300 * ms)
        work()
        frame(310 * ms)
        assertEquals(4f, shown!!.radius)
        st.blur = 1.0
        frame(320 * ms)
        assertSame("the copy at the earlier strength is still there", first, shown)
    }

    @Test
    fun aNewDrawingDropsTheCopiesAndALateCopyIsNotUsed() {
        st.blur = 1.0
        draw()
        frame(0)
        frame(120 * ms)
        work()
        frame(130 * ms)
        assertNotNull(shown)

        // The line changes: its copy goes at once, and it draws itself.
        st.drawVersion.intValue++
        frame(140 * ms)
        assertNull(shown)
        draw()
        frame(300 * ms)
        assertEquals(1, tasks.size)
        // It changes again before the copy is made.
        st.drawVersion.intValue++
        frame(310 * ms)
        draw()
        work()
        frame(320 * ms)
        assertNull("a copy of an older drawing is never shown", shown)
    }

    @Test
    fun aSharpLineIsNeverCopied() {
        st.blur = 0.0
        draw()
        repeat(20) { frame(it * 50 * ms) }
        assertTrue(tasks.isEmpty())
        assertNull(shown)
    }

    @Test
    fun aLineThatGoesOffScreenIsLetGo() {
        st.blur = 1.0
        draw()
        frame(0)
        frame(120 * ms)
        work()
        frame(130 * ms)
        val before = pictures.line(0)
        assertNotNull(before.copy.value)
        pictures.follow(states, IntRange.EMPTY, 140 * ms)
        assertNull(before.copy.value)
        assertNotSame(before, pictures.line(0))
    }

    @Test
    fun aCopyDrawsWhatTheLayerBlurDraws() {
        val radius = 6f
        val picture = shapes()
        val filter = blurOf(radius).skiaImageFilter
        val copy = blurredCopy(picture, filter, radius, 0)
        // Where the line sits makes no difference on whole pixels.
        for ((x, y) in listOf(20f to 30f, 0f to 0f, 57f to 11f)) {
            val live = Surface.makeRasterN32Premul(320, 160)
            live.canvas.translate(x, y)
            live.canvas.saveLayer(null, Paint().apply { imageFilter = filter })
            live.canvas.drawPicture(picture)
            live.canvas.restore()
            val copied = Surface.makeRasterN32Premul(320, 160)
            copied.canvas.translate(x, y)
            copy.draw(copied.canvas)
            assertTrue("at $x, $y", largestDifference(live, copied) <= 1)
        }
    }

    @Test
    fun aLineThatDrawsNothingNeedsNoImage() {
        val recorder = PictureRecorder()
        recorder.beginRecording(Rect.makeWH(100f, 100f), RTreeFactory())
        val copy = blurredCopy(recorder.finishRecordingAsPicture(), blurOf(2f).skiaImageFilter, 2f, 3)
        assertNull(copy.image)
        assertEquals(3, copy.version)
    }

    // Soft-edged shapes, as letters are.
    private fun shapes(): Picture {
        val recorder = PictureRecorder()
        val canvas = recorder.beginRecording(Rect.makeLTRB(-40f, -40f, 280f, 120f), RTreeFactory())
        val paint = Paint().apply {
            color = 0xFFFFFFFF.toInt()
            isAntiAlias = true
        }
        canvas.drawCircle(40f, 40f, 23.5f, paint)
        canvas.drawRect(Rect.makeXYWH(90.5f, 20.25f, 60f, 30f), paint)
        paint.color = 0x99FFFFFF.toInt()
        canvas.drawCircle(200f, 50f, 17f, paint)
        return recorder.finishRecordingAsPicture()
    }

    private fun largestDifference(a: Surface, b: Surface): Int {
        val first = Bitmap.makeFromImage(a.makeImageSnapshot())
        val second = Bitmap.makeFromImage(b.makeImageSnapshot())
        var largest = 0
        for (y in 0 until first.height) {
            for (x in 0 until first.width) {
                val p = first.getColor(x, y)
                val q = second.getColor(x, y)
                for (shift in intArrayOf(0, 8, 16, 24)) largest = maxOf(largest, abs((p shr shift and 0xFF) - (q shr shift and 0xFF)))
            }
        }
        return largest
    }
}
