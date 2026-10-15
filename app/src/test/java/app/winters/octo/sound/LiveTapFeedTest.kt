package app.winters.octo.sound

import org.junit.After
import org.junit.Assert.assertEquals
import org.junit.Assert.assertNotNull
import org.junit.Assert.assertNull
import org.junit.Test
import java.util.concurrent.Executors
import kotlin.math.PI
import kotlin.math.exp
import kotlin.math.sin

class LiveTapFeedTest {
    private val worker = Executors.newSingleThreadScheduledExecutor()
    private val rate = 44_100

    @After
    fun stop() {
        worker.shutdownNow()
    }

    // `seconds` of stereo sine at half scale: an RMS of -9 dBFS.
    private fun sine(seconds: Double): FloatArray {
        val frames = (seconds * rate).toInt()
        return FloatArray(frames * 2) { (0.5 * sin(2 * PI * 440 * (it / 2) / rate)).toFloat() }
    }

    // A kick every half second (120 BPM) with a bass note under it.
    private fun beat(seconds: Double): FloatArray {
        val frames = (seconds * rate).toInt()
        return FloatArray(frames * 2) {
            val n = it / 2
            val sinceKick = (n % (rate / 2)).toDouble() / rate
            (0.6 * exp(-sinceKick * 30) * sin(2 * PI * 60 * n / rate) + 0.05 * sin(2 * PI * 880 * n / rate)).toFloat()
        }
    }

    private fun LiveTapFeed.pushAll(samples: FloatArray) {
        // In 10 ms blocks, as the audio thread hands them over.
        val block = rate / 100 * 2
        var at = 0
        while (at < samples.size) {
            val n = minOf(block, samples.size - at)
            push(samples.copyOfRange(at, at + n), n)
            at += n
            if (at % (block * 50) == 0) drain()
        }
    }

    @Test
    fun theTapHearsTheSongsLevel() {
        val feed = LiveTapFeed(worker)
        feed.begin("q:1", rate, 2)
        feed.pushAll(sine(5.0))
        val reading = feed.reading("q:1")!!
        assertEquals(5_000L, reading.heardMs)
        assertEquals(-9.03, reading.bodyLevelDb!!, 0.2)
    }

    @Test
    fun aNewSongStartsANewTapWhereItsSoundStarts() {
        val feed = LiveTapFeed(worker)
        feed.begin("q:1", rate, 2)
        feed.push(sine(1.0), rate * 2)
        feed.begin("q:2", rate, 2)
        feed.push(sine(1.0), rate * 2)
        // Nothing drained yet: the switch still lands where the new song starts.
        assertNull(feed.reading("q:1"))
        assertEquals(1_000L, feed.reading("q:2")!!.heardMs)
    }

    @Test
    fun aSteadyBeatGivesATempo() {
        val feed = LiveTapFeed(worker)
        feed.begin("q:1", rate, 2)
        feed.pushAll(beat(20.0))
        val tempo = feed.reading("q:1")!!.tempoPrior
        assertNotNull(tempo)
        assertEquals(120.0, tempo!!, 1.0)
    }

    @Test
    fun soundThatDoesNotFitIsDroppedNotWrappedOver() {
        val feed = LiveTapFeed(worker)
        feed.begin("q:1", rate, 1)
        val tooMuch = FloatArray(TAP_RING_SAMPLES + 10) { 0.5f }
        feed.push(tooMuch, tooMuch.size)
        assertEquals(0L, feed.reading("q:1")!!.heardMs)
    }

    @Test
    fun theSongsTagTempoPicksTheOctaveHeard() {
        val feed = LiveTapFeed(worker)
        feed.begin("q:1", rate, 2)
        feed.pushAll(beat(20.0))
        assertEquals(60.0, feed.reading("q:1", tagBpm = 61.0)!!.tempoPrior!!, 1.0)
        assertEquals(120.0, feed.reading("q:1")!!.tempoPrior!!, 1.0)
    }

    @Test
    fun aSongReadEarlyKeepsBeingFedUntilItsLevelCounts() {
        val feed = LiveTapFeed(worker)
        feed.begin("q:1", rate, 2)
        feed.pushAll(sine(2.0))
        assertEquals(2_000L, feed.reading("q:1")!!.heardMs)
        // Read a few seconds in, the tap goes on hearing the song.
        feed.pushAll(sine(19.0))
        val enough = feed.reading("q:1")!!
        assertEquals(21_000L, enough.heardMs)
        assertNotNull(enough.bodyLevelDb)
        // Read with its level heard, the rest of the song is left out.
        feed.pushAll(sine(3.0))
        assertEquals(21_000L, feed.reading("q:1")!!.heardMs)
        // The next song is fed from its start.
        feed.begin("q:2", rate, 2)
        feed.pushAll(sine(1.0))
        assertEquals(1_000L, feed.reading("q:2")!!.heardMs)
    }

    @Test
    fun aSongReadForAnotherEntryKeepsBeingFed() {
        val feed = LiveTapFeed(worker)
        feed.begin("q:1", rate, 2)
        feed.pushAll(sine(1.0))
        assertNull(feed.reading("q:9"))
        feed.pushAll(sine(1.0))
        assertEquals(2_000L, feed.reading("q:1")!!.heardMs)
    }
}
