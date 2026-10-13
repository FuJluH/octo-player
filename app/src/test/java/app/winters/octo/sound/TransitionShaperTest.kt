package app.winters.octo.sound

import androidx.media3.common.C
import androidx.media3.common.audio.AudioProcessor
import androidx.media3.common.util.UnstableApi
import app.winters.octo.playback.FadeCurve
import app.winters.octo.playback.FILTER_STRENGTH
import app.winters.octo.playback.MIX_ONLY_HEADROOM_DB
import app.winters.octo.playback.TransitionKind
import app.winters.octo.playback.TransitionPlan
import app.winters.octo.playback.automixInGain
import app.winters.octo.playback.automixOutGain
import app.winters.octo.playback.fixedCrossfadePlan
import kotlinx.serialization.json.Json
import kotlinx.serialization.json.JsonObject
import kotlinx.serialization.json.double
import kotlinx.serialization.json.int
import kotlinx.serialization.json.jsonArray
import kotlinx.serialization.json.jsonObject
import kotlinx.serialization.json.jsonPrimitive
import org.junit.Assert.assertEquals
import org.junit.Assert.assertTrue
import org.junit.Test
import java.io.File
import java.nio.ByteBuffer
import java.nio.ByteOrder
import kotlin.math.PI
import kotlin.math.abs
import kotlin.math.pow
import kotlin.math.sin
import kotlin.math.sqrt

@UnstableApi
class TransitionShaperTest {
    private val rate = 48_000

    // The vectors the shared planner and the desktop engine are checked against.
    private val vectors: JsonObject by lazy {
        val file = listOf(
            "../shared/core/src/commonTest/resources/automix-vectors.json",
            "shared/core/src/commonTest/resources/automix-vectors.json",
        ).map(::File).first { it.exists() }
        Json.parseToJsonElement(file.readText()).jsonObject
    }

    private fun plan(
        start: Long = 1_000,
        entry: Long = 0,
        overlap: Long = 1_000,
        k: Double = 0.4,
        strength: Double = 0.0,
        headroomDb: Double = 0.0,
        beatMs: Double? = null,
        beatAnchorMs: Double? = null,
        rate: Double? = null,
    ) = TransitionPlan(start, entry, overlap, TransitionKind.BLEND, k, strength, rate, beatMs, beatAnchorMs, false, headroomDb, "test")

    // `frames` mono frames at a fixed level, 16-bit.
    private fun level(frames: Int, value: Short = 16_384): ByteBuffer {
        val buffer = ByteBuffer.allocateDirect(frames * 2).order(ByteOrder.nativeOrder())
        repeat(frames) { buffer.putShort(value) }
        buffer.flip()
        return buffer
    }

    private fun tone(frames: Int, hz: Double, from: Int = 0): ByteBuffer {
        val buffer = ByteBuffer.allocateDirect(frames * 2).order(ByteOrder.nativeOrder())
        repeat(frames) { buffer.putShort((16_000 * sin(2 * PI * hz * (from + it) / rate)).toInt().toShort()) }
        buffer.flip()
        return buffer
    }

    private fun AudioProcessor.collect(into: MutableList<Float>) {
        val out = output
        while (out.hasRemaining()) into += out.float
    }

    // A processor with nothing to shape, kept running for crossfade, its
    // stream starting at `fromMs` in its song.
    private fun processor(fromMs: Long = 0, speed: Float = 1f, entry: String? = null): OctoDspProcessor {
        val off = SoundSettings(limiter = false)
        val processor = OctoDspProcessor(keepActive = { true }, entryOf = { entry }) { off }
        assertEquals(C.ENCODING_PCM_FLOAT, processor.configure(AudioProcessor.AudioFormat(rate, 1, C.ENCODING_PCM_16BIT)).encoding)
        processor.setSpeed(speed)
        processor.flush(AudioProcessor.StreamMetadata(fromMs * 1_000))
        return processor
    }

    // Plays `ms` of `source` through the processor in 10 ms buffers.
    private fun run(processor: OctoDspProcessor, ms: Int, source: (frames: Int, from: Int) -> ByteBuffer = { n, _ -> level(n) }): List<Float> {
        val out = mutableListOf<Float>()
        val step = rate / 100
        var at = 0
        while (at < ms * rate / 1_000) {
            processor.queueInput(source(step, at))
            processor.collect(out)
            at += step
        }
        processor.queueEndOfStream()
        processor.collect(out)
        return out
    }

    private fun msToFrame(ms: Double) = (ms * rate / 1_000).toInt()

    private fun rms(samples: List<Float>, from: Int, to: Int): Double =
        sqrt(samples.subList(from, to).sumOf { it.toDouble() * it } / (to - from))

    @Test
    fun theSweepFiltersMatchTheSharedFilters() {
        val failures = mutableListOf<String>()
        for (case in vectors["biquads"]!!.jsonArray) {
            val o = case.jsonObject
            val kind = if (o["type"]!!.jsonPrimitive.content == "lowPass") FilterKind.LowPass else FilterKind.HighPass
            val sampleRate = o["rate"]!!.jsonPrimitive.int
            val hz = o["hz"]!!.jsonPrimitive.double
            val expected = o["coefficients"]!!.jsonArray.map { it.jsonPrimitive.double }
            val got = sweepCoefficients(kind, sampleRate, hz)
            expected.forEachIndexed { i, e -> if (abs(got[i] - e) > 1e-12) failures += "$kind $sampleRate $hz: coefficient $i $e, got ${got[i]}" }
            val filter = SweptFilter(kind, sampleRate, 1).apply { setCutoff(hz) }
            val impulse = o["impulse"]!!.jsonArray.map { it.jsonPrimitive.double }
            impulse.forEachIndexed { n, e ->
                val y = filter.process(if (n == 0) 1.0 else 0.0, 0)
                if (abs(y - e) > 1e-9) failures += "$kind $sampleRate $hz: impulse $n $e, got $y"
            }
        }
        assertTrue(failures.take(10).joinToString("\n"), failures.isEmpty())
    }

    @Test
    fun aFixedCrossfadeFollowsItsCurveAndHeadroom() {
        val plan = fixedCrossfadePlan(200_000, 8_000, "test", FadeCurve.MixOnly)
        val out = DeckTransition("a", plan, incoming = false)
        val into = DeckTransition("b", plan, incoming = true)
        // Mid-blend both songs play full, lowered by the 3 dB of headroom.
        val lowered = 10.0.pow(-MIX_ONLY_HEADROOM_DB / 20)
        assertEquals(lowered, out.gainAt(0.5), 1e-12)
        assertEquals(lowered, into.gainAt(0.5), 1e-12)
        val linear = fixedCrossfadePlan(200_000, 8_000, "test", FadeCurve.Linear)
        assertEquals(0.75, DeckTransition("a", linear, incoming = false).gainAt(0.25), 1e-12)
        assertEquals(0.25, DeckTransition("b", linear, incoming = true).gainAt(0.25), 1e-12)
    }

    @Test
    fun theVolumesAndCutoffsFollowTheSharedCurves() {
        for (case in vectors["gains"]!!.jsonArray) {
            val o = case.jsonObject
            val t = o["t"]!!.jsonPrimitive.double
            val k = o["k"]!!.jsonPrimitive.double
            val out = DeckTransition(null, plan(k = k), incoming = false)
            val into = DeckTransition(null, plan(k = k), incoming = true)
            val expectOut = if (t >= 1) 0.0 else o["out"]!!.jsonPrimitive.double
            val expectIn = if (t < 0) 0.0 else o["in"]!!.jsonPrimitive.double
            assertEquals("out at $t, k $k", expectOut, out.gainAt(t), 1e-9)
            assertEquals("in at $t, k $k", expectIn, into.gainAt(t), 1e-9)
        }
        for (case in vectors["filters"]!!.jsonArray) {
            val o = case.jsonObject
            val t = o["t"]!!.jsonPrimitive.double
            val strength = o["strength"]!!.jsonPrimitive.double
            val out = DeckTransition(null, plan(strength = strength), incoming = false)
            val into = DeckTransition(null, plan(strength = strength), incoming = true)
            assertEquals(o["outgoingLowPassHz"]!!.jsonPrimitive.double, out.lowPassAt(t), 1e-6)
            assertEquals(o["outgoingHighPassHz"]!!.jsonPrimitive.double, out.highPassAt(t), 1e-6)
            assertEquals(o["incomingHighPassHz"]!!.jsonPrimitive.double, into.highPassAt(t), 1e-6)
        }
    }

    @Test
    fun theOutgoingSongFollowsItsCurveOnItsOwnSongTime() {
        // The stream starts 500 ms into the song; the blend runs 1 s to 2 s.
        val processor = processor(fromMs = 500)
        processor.arm(DeckTransition(null, plan(k = 0.4), incoming = false))
        val out = run(processor, 2_000)
        // Untouched before the blend.
        assertTrue(out.subList(0, msToFrame(490.0)).all { it == 0.5f })
        for (t in listOf(0.1, 0.25, 0.5, 0.75, 0.9)) {
            val frame = msToFrame(500 + t * 1_000)
            assertEquals("at $t", 0.5 * automixOutGain(t, 0.4), out[frame].toDouble(), 2e-3)
        }
        // Silent once the blend is over.
        assertTrue(out.subList(msToFrame(1_540.0), out.size).all { abs(it) < 1e-6 })
    }

    @Test
    fun theIncomingSongIsSilentUntilItsEntryThenFadesInAndIsLeftAlone() {
        val processor = processor()
        processor.arm(DeckTransition(null, plan(entry = 600, overlap = 1_000, k = 0.55), incoming = true))
        val out = run(processor, 2_500)
        assertTrue(out.subList(0, msToFrame(600.0)).all { it == 0f })
        for (t in listOf(0.1, 0.5, 0.9)) {
            assertEquals("at $t", 0.5 * automixInGain(t, 0.55), out[msToFrame(600 + t * 1_000)].toDouble(), 2e-3)
        }
        // After the blend the sound is exactly what came in.
        assertTrue(out.subList(msToFrame(1_700.0), out.size).all { it == 0.5f })
    }

    @Test
    fun bothSongsDropByTheHeadroomInTheMiddleOfTheBlend() {
        val processor = processor()
        processor.arm(DeckTransition(null, plan(start = 0, headroomDb = 1.0), incoming = false))
        val out = run(processor, 800)
        val expected = 0.5 * automixOutGain(0.5, 0.4) * 10.0.pow(-1.0 / 20)
        assertEquals(expected, out[msToFrame(500.0)].toDouble(), 2e-3)
    }

    @Test
    fun theSweepsCutTheOutgoingSongsTopAndBass() {
        val strong = plan(start = 0, overlap = 2_000, strength = FILTER_STRENGTH)
        fun loudness(hz: Double, transition: DeckTransition?): Pair<Double, Double> {
            val processor = processor()
            processor.arm(transition)
            val out = run(processor, 1_900) { n, from -> tone(n, hz, from) }
            // Divide by the volume curve, so only the filters are compared.
            val early = rms(out, msToFrame(100.0), msToFrame(200.0)) / (transition?.gainAt(0.075) ?: 1.0)
            val late = rms(out, msToFrame(1_700.0), msToFrame(1_800.0)) / (transition?.gainAt(0.875) ?: 1.0)
            return early to late
        }
        val (highEarly, highLate) = loudness(6_000.0, DeckTransition(null, strong, incoming = false))
        val (_, highDry) = loudness(6_000.0, null)
        // The top is open at first and closed near the end.
        assertTrue("$highEarly vs $highDry", highEarly > highDry * 0.9)
        assertTrue("$highLate vs $highDry", highLate < highDry * 0.1)
        val (_, bassLate) = loudness(60.0, DeckTransition(null, strong, incoming = false))
        val (_, bassDry) = loudness(60.0, null)
        assertTrue("$bassLate vs $bassDry", bassLate < bassDry * 0.2)
    }

    @Test
    fun theIncomingSongComesInThinAndOpensUp() {
        val into = DeckTransition(null, plan(entry = 0, overlap = 2_000, strength = FILTER_STRENGTH), incoming = true)
        val processor = processor()
        processor.arm(into)
        val out = run(processor, 3_000) { n, from -> tone(n, 100.0, from) }
        val early = rms(out, msToFrame(150.0), msToFrame(250.0)) / into.gainAt(0.1)
        val dry = 16_000 / 32_768.0 / sqrt(2.0)
        assertTrue("$early vs $dry", early < dry * 0.3)
        // Fully open, and untouched, after the blend.
        val after = rms(out, msToFrame(2_600.0), msToFrame(2_900.0))
        assertEquals(dry, after, dry * 0.01)
    }

    @Test
    fun anOutgoingSongThatFallsSilentFadesOutEarly() {
        val processor = processor()
        processor.arm(DeckTransition(null, plan(start = 0, overlap = 4_000, k = 0.2), incoming = false, gateDb = -50.0))
        // Loud, then 400 ms of silence, then loud again.
        val out = run(processor, 2_000) { n, from ->
            if (from >= msToFrame(500.0) && from < msToFrame(900.0)) level(n, 0) else level(n)
        }
        // Before the silence it plays on the curve...
        assertTrue(out[msToFrame(400.0)] > 0.3f)
        // ...and once the silence has lasted 300 ms it does not come back.
        assertTrue(out.subList(msToFrame(900.0), out.size).all { abs(it) < 1e-6 })
    }

    @Test
    fun aQuietPassageShorterThanTheWaitDoesNotEndTheSong() {
        val processor = processor()
        processor.arm(DeckTransition(null, plan(start = 0, overlap = 4_000, k = 0.2), incoming = false, gateDb = -50.0))
        val out = run(processor, 2_000) { n, from ->
            if (from >= msToFrame(500.0) && from < msToFrame(700.0)) level(n, 0) else level(n)
        }
        assertTrue(out[msToFrame(1_500.0)] > 0.2f)
    }

    @Test
    fun aTransitionForAnotherSongLeavesThisOneAlone() {
        val processor = processor(entry = "q:1")
        processor.arm(DeckTransition("q:9", plan(start = 0), incoming = false))
        val out = run(processor, 1_500)
        assertTrue(out.all { it == 0.5f })
        // Its own song takes it.
        val own = processor(entry = "q:9")
        own.arm(DeckTransition("q:9", plan(start = 0), incoming = false))
        assertTrue(run(own, 1_500).last() == 0f)
    }

    @Test
    fun withNothingToShapeTheSoundPassesThroughUnchanged() {
        val processor = processor()
        val out = run(processor, 300) { n, from -> tone(n, 440.0, from) }
        val again = tone(msToFrame(300.0), 440.0)
        val expected = FloatArray(msToFrame(300.0)) { again.short / 32_768f }
        assertEquals(expected.size, out.size)
        assertTrue(out.indices.all { out[it] == expected[it] })
    }

    @Test
    fun songTimeRunsWithTheSpeed() {
        // At double speed the blend at 1 s to 2 s of the song passes in half the frames.
        val processor = processor(speed = 2f)
        processor.arm(DeckTransition(null, plan(k = 0.4), incoming = false))
        val out = run(processor, 1_200)
        assertEquals(0.5 * automixOutGain(0.5, 0.4), out[msToFrame(750.0)].toDouble(), 2e-3)
        assertTrue(out.subList(msToFrame(1_020.0), out.size).all { abs(it) < 1e-6 })
    }

    @Test
    fun droppingATransitionMidwayGlidesBackWithoutAJump() {
        val processor = processor()
        processor.arm(DeckTransition(null, plan(start = 0, overlap = 1_000, k = 0.75), incoming = false))
        val out = mutableListOf<Float>()
        val step = rate / 100
        repeat(70) {
            processor.queueInput(level(step))
            processor.collect(out)
        }
        processor.arm(null)
        repeat(20) {
            processor.queueInput(level(step))
            processor.collect(out)
        }
        val biggestStep = (1 until out.size).maxOf { abs(out[it] - out[it - 1]) }
        // From near silence back to full over at least TRANSITION_SLEW_MS.
        assertTrue("$biggestStep", biggestStep <= 0.5f / (rate * TRANSITION_SLEW_MS / 1_000).toFloat() * 1.01f)
        assertEquals(0.5f, out.last())
    }

    @Test
    fun theIncomingSongsFilterHandsOverToItsDrySoundOverTenMs() {
        // A bass note through the end of a swept blend: the high-pass's phase
        // shift fades out instead of stepping the waveform.
        val into = DeckTransition(null, plan(entry = 0, overlap = 1_000, strength = FILTER_STRENGTH), incoming = true)
        val processor = processor()
        processor.arm(into)
        val out = run(processor, 1_200) { n, from -> tone(n, 45.0, from) }
        val dry = tone(msToFrame(1_200.0), 45.0).let { b -> FloatArray(msToFrame(1_200.0)) { b.short / 32_768f } }
        val end = msToFrame(1_000.0)
        val lastWet = (end until out.size).last { out[it] != dry[it] }
        val releaseMs = (lastWet - end) * 1_000.0 / rate
        assertTrue("released over $releaseMs ms", releaseMs >= FILTER_ENGAGE_MS * 0.9 && releaseMs <= FILTER_ENGAGE_MS + 2)
        // No sample-to-sample step bigger than the note's own slope allows.
        val slope = 16_000 / 32_768.0 * 2 * PI * 45.0 / rate
        val biggest = (end - msToFrame(20.0) until lastWet + 10).maxOf { abs(out[it] - out[it - 1]).toDouble() }
        assertTrue("$biggest vs $slope", biggest <= slope * 1.6)
    }

    @Test
    fun theOutgoingSongsFiltersComeInWithoutAClick() {
        // A steady level into a swept blend: the filters start from rest, so
        // only the dry-to-wet ramp keeps the waveform from stepping.
        val processor = processor()
        processor.arm(DeckTransition(null, plan(start = 500, overlap = 1_000, strength = FILTER_STRENGTH), incoming = false))
        val out = run(processor, 800)
        val start = msToFrame(500.0)
        val biggest = (start - 10 until start + msToFrame(40.0)).maxOf { abs(out[it] - out[it - 1]) }
        assertTrue("a step of $biggest where the filters came in", biggest < 0.002f)
    }

    @Test
    fun anOutgoingSongArmedPartWayIntoItsBlendGlidesToTheCurve() {
        // A late plan armed after its start: the playing song was at full.
        val processor = processor(fromMs = 600)
        processor.arm(DeckTransition(null, plan(start = 0, overlap = 1_000, k = 0.75), incoming = false))
        val out = run(processor, 200)
        assertEquals(0.5f, out.first(), 0.5f * 0.02f)
        val biggestStep = (1 until out.size).maxOf { abs(out[it] - out[it - 1]) }
        assertTrue("$biggestStep", biggestStep <= 0.5f / (rate * TRANSITION_SLEW_MS / 1_000).toFloat() * 1.01f)
    }
}
