package app.winters.octo.sound

import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test
import kotlin.math.PI
import kotlin.math.abs
import kotlin.math.log10
import kotlin.math.pow
import kotlin.math.sin
import kotlin.math.sqrt

class SoundPathTest {
    private val rate = 48_000

    private fun sine(frequency: Float, frames: Int, amplitude: Float = 0.25f, channels: Int = 1): FloatArray =
        FloatArray(frames * channels) { i -> amplitude * sin(2 * PI * frequency * (i / channels) / rate).toFloat() }

    private fun rms(samples: FloatArray, from: Int, to: Int): Double =
        sqrt((from until to).sumOf { samples[it].toDouble() * samples[it] } / (to - from))

    @Test
    fun aPeakFilterGivesItsGainAtItsFrequency() {
        val bank = filterBank(listOf(EqFilter(FilterType.Peak, 1_000f, 6f, 1.41f)), rate, 1)
        val input = sine(1_000f, rate)
        val output = input.copyOf()
        bank.process(output, rate)
        // Measure after the filter has settled.
        val gainDb = 20 * log10(rms(output, rate / 2, rate) / rms(input, rate / 2, rate))
        assertEquals(6.0, gainDb, 0.05)
    }

    @Test
    fun eachChannelIsFilteredOnItsOwn() {
        val bank = filterBank(listOf(EqFilter(FilterType.Peak, 1_000f, -12f, 1.41f)), rate, 2)
        // Left carries the tone, right is silent and must stay silent.
        val samples = FloatArray(rate * 2) { i -> if (i % 2 == 0) 0.5f * sin(2 * PI * 1_000 * (i / 2) / rate).toFloat() else 0f }
        bank.process(samples, rate)
        assertTrue((1 until samples.size step 2).all { samples[it] == 0f })
        val left = FloatArray(rate) { samples[it * 2] }
        val gainDb = 20 * log10(rms(left, rate / 2, rate) / (0.5 / sqrt(2.0)))
        assertEquals(-12.0, gainDb, 0.1)
    }

    @Test
    fun bandsTooCloseToTheTopAreLeftOut() {
        val filters = listOf(EqFilter(FilterType.Peak, 1_000f, 3f), EqFilter(FilterType.Peak, 21_000f, 6f))
        assertEquals(1, bandCoefficients(filters, 44_100).size)
        assertEquals(2, bandCoefficients(filters, 96_000).size)
    }

    @Test
    fun theLimiterNeverGoesOverItsCeiling() {
        val limiter = Limiter(2, rate)
        val ceiling = 10f.pow(LIMITER_CEILING_DB / 20f)
        // Quiet, then a sudden burst four times over full scale, then quiet.
        val frames = rate / 2
        val input = FloatArray(frames * 2) { i ->
            val frame = i / 2
            val level = if (frame in 10_000 until 12_000) 4f else 0.3f
            level * sin(2 * PI * 440 * frame / rate).toFloat()
        }
        val output = FloatArray(input.size)
        val written = limiter.process(input, frames, output)
        val tail = FloatArray(limiter.latency * 2)
        val drained = limiter.drain(tail)
        tail.copyInto(output, written * 2, 0, drained * 2)
        assertEquals(frames, written + drained)
        assertTrue(output.all { abs(it) <= ceiling })
        // The burst is held right at the ceiling, not crushed far below it.
        assertTrue(output.maxOf { abs(it) } > ceiling * 0.99f)
    }

    @Test
    fun theLimiterLosesNoFramesAndLeavesQuietSoundAlone() {
        val limiter = Limiter(1, rate)
        val input = sine(440f, 4_800)
        val output = FloatArray(input.size)
        val out = limiter.process(input, input.size, output)
        assertEquals(input.size - limiter.latency, out)
        val tail = FloatArray(limiter.latency)
        assertEquals(limiter.latency, limiter.drain(tail))
        tail.copyInto(output, out)
        // Everything comes out, in order, unchanged.
        for (i in input.indices) assertEquals(input[i], output[i], 0f)
    }

    @Test
    fun untouchedSoundPassesThroughExactly() {
        val shaper = SoundShaper(rate, 2)
        shaper.apply(SoundSettings(), null, instant = true)
        val input = sine(1_000f, 2_000, amplitude = 0.99f, channels = 2)
        val output = FloatArray(input.size)
        val n = shaper.process(input.copyOf(), 2_000, output)
        val tail = FloatArray(shaper.latency * 2)
        val m = shaper.drain(tail)
        tail.copyInto(output, n * 2, 0, m * 2)
        assertEquals(2_000, n + m)
        for (i in input.indices) assertEquals(input[i], output[i], 0f)
    }

    @Test
    fun monoAndBalanceMixTheChannels() {
        val shaper = SoundShaper(rate, 2)
        shaper.apply(SoundSettings(mono = true, balance = 0.5f, limiter = false), null, instant = true)
        val frames = 1_000
        val input = FloatArray(frames * 2) { if (it % 2 == 0) 0.4f else 0f }
        val output = FloatArray(input.size)
        val n = shaper.process(input, frames, output)
        // Both sides get the average; the right side is at full, the left at half.
        assertEquals(0.1f, output[(n - 1) * 2], 1e-6f)
        assertEquals(0.2f, output[(n - 1) * 2 + 1], 1e-6f)
    }

    @Test
    fun crossfeedSendsOneSideToTheOtherEarAtItsFeedLevel() {
        val shaper = SoundShaper(rate, 2)
        val crossfeed = Crossfeed(on = true, preset = CrossfeedPreset.ChuMoy)
        shaper.apply(SoundSettings(limiter = false, crossfeed = crossfeed), null, instant = true)
        val frames = 4_800
        val input = FloatArray(frames * 2) { if (it % 2 == 0) 0.5f else 0f }
        val output = FloatArray(input.size)
        val n = shaper.process(input, frames, output)
        // Steady sound on the left reaches the right ear 6 dB below the left.
        val left = output[(n - 1) * 2]
        val right = output[(n - 1) * 2 + 1]
        assertEquals(-6.0, 20 * log10(right.toDouble() / left), 0.01)
        assertEquals(0.5f, left + right, 1e-5f)
    }

    @Test
    fun crossfeedTurnsTheShapingOnAndMonoTurnsItOff() {
        assertTrue(SoundSettings(limiter = false, crossfeed = Crossfeed(on = true)).shapesSound())
        val shaper = SoundShaper(rate, 2)
        shaper.apply(SoundSettings(limiter = false, mono = true, crossfeed = Crossfeed(on = true)), null, instant = true)
        val input = FloatArray(200) { if (it % 2 == 0) 0.4f else 0f }
        val output = FloatArray(input.size)
        val n = shaper.process(input, 100, output)
        assertEquals(0.2f, output[(n - 1) * 2 + 1], 1e-6f)
    }
}
