package app.winters.octo.playback

import androidx.media3.common.Player
import org.junit.Assert.assertEquals
import org.junit.Assert.assertFalse
import org.junit.Assert.assertNull
import org.junit.Assert.assertTrue
import org.junit.Test
import kotlin.math.abs

class AutomixTimingTest {
    private fun plan(start: Long = 180_000, entry: Long = 4_000, overlap: Long = 8_000, rate: Double? = null, beatMs: Double? = 500.0) =
        TransitionPlan(start, entry, overlap, TransitionKind.BLEND, BLEND_CURVE, FILTER_STRENGTH, rate, beatMs, beatMs?.let { 0.0 }, false, 1.0, "test")

    @Test
    fun theRunUpStartsSoTheEntryLandsOnTheStart() {
        val p = plan()
        assertEquals(1_500L, p.preRollFromMs())
        assertEquals(177_500.0, p.preRollAtMs(), 1e-9)
        assertEquals(4_000.0, p.incomingAtMs(180_000.0), 1e-9)
        // A song that comes in at its very start cannot run up.
        val early = plan(entry = 1_000)
        assertEquals(0L, early.preRollFromMs())
        assertEquals(179_000.0, early.preRollAtMs(), 1e-9)
    }

    @Test
    fun aTempoMatchedSongRunsUpAtItsRate() {
        val p = plan(rate = 1.02)
        assertEquals(4_000L - 2_550L, p.preRollFromMs())
        assertEquals(180_000 - 2_550 / 1.02, p.preRollAtMs(), 1e-9)
        // Half a second into the blend the incoming song has moved 510 ms.
        assertEquals(4_510.0, p.incomingAtMs(180_500.0), 1e-9)
        assertEquals(0.0, p.alignmentErrorMs(180_500.0, 4_510.0), 1e-9)
        assertEquals(10.0, p.alignmentErrorMs(180_500.0, 4_520.2), 1e-9)
    }

    // A deck that starts late and stops a while on every move, the way an
    // audio output does.
    private class Decks(val plan: TransitionPlan, val startLag: Long, val seekLag: Long) {
        var now = 0L
        private val runUpAt = plan.preRollAtMs()
        var incoming = plan.preRollFromMs().toDouble()
        private var resumesAt = startLag
        val outgoing: Double get() = runUpAt + now
        val playing: Boolean get() = now >= resumesAt

        fun tick(ms: Long) {
            repeat(ms.toInt()) {
                now++
                if (playing) incoming += plan.incomingRate()
            }
        }

        fun seek(to: Long) {
            incoming = to.toDouble()
            resumesAt = now + seekLag
        }
    }

    private fun align(decks: Decks): Pair<Aligner.Step.Settled, Int> {
        val aligner = Aligner(decks.plan)
        var seeks = 0
        while (true) {
            when (val step = aligner.observe(decks.now, decks.outgoing, decks.incoming, decks.playing)) {
                is Aligner.Step.Settled -> return step to seeks
                is Aligner.Step.Seek -> {
                    seeks++
                    decks.seek(step.toMs)
                }
                Aligner.Step.Wait -> Unit
            }
            decks.tick(40)
        }
    }

    @Test
    fun aLateStartIsMovedIntoLineBeforeTheBlend() {
        val decks = Decks(plan(), startLag = 180, seekLag = 90)
        val (settled, seeks) = align(decks)
        assertTrue("${settled.errorMs}", abs(settled.errorMs!!) < BAR_LOCK_TOLERANCE_MS)
        assertTrue(settled.locked)
        assertTrue(seeks in 1..ALIGN_MOST_SEEKS)
        // Settled while the incoming song was still silent.
        assertTrue(decks.outgoing < plan().startMs)
        // And it really is in line.
        assertTrue(abs(plan().alignmentErrorMs(decks.outgoing, decks.incoming)) < BAR_LOCK_TOLERANCE_MS)
    }

    @Test
    fun aTempoMatchedSongIsLinedUpToo() {
        val p = plan(rate = 0.97)
        val decks = Decks(p, startLag = 250, seekLag = 140)
        val (settled, _) = align(decks)
        assertTrue("${settled.errorMs}", settled.locked)
    }

    @Test
    fun aDeckThatIsAlreadyInLineIsLeftAlone() {
        val decks = Decks(plan(), startLag = 0, seekLag = 90)
        val (settled, seeks) = align(decks)
        assertEquals(0, seeks)
        assertTrue(settled.locked)
    }

    @Test
    fun aDeckThatNeverPlaysInTimeGoesAheadUnmeasured() {
        val decks = Decks(plan(), startLag = 5_000, seekLag = 90)
        val (settled, seeks) = align(decks)
        assertEquals(0, seeks)
        assertNull(settled.errorMs)
        assertFalse(settled.locked)
    }

    @Test
    fun aMoveThatKeepsMissingStopsAndTheBlendGoesSmooth() {
        // Each move lands 40 ms off, first early then late, so it never settles.
        val p = plan()
        val aligner = Aligner(p)
        val misses = listOf(-40.0, 40.0, -40.0, 40.0)
        // It starts 100 ms behind.
        var now = 0L
        var outgoing = p.preRollAtMs()
        var incoming = p.preRollFromMs() - 100.0
        var seeks = 0
        var settled: Aligner.Step.Settled? = null
        while (settled == null) {
            when (val step = aligner.observe(now, outgoing, incoming, true)) {
                is Aligner.Step.Settled -> settled = step
                is Aligner.Step.Seek -> incoming = step.toMs + misses[seeks++]
                Aligner.Step.Wait -> Unit
            }
            now += 20
            outgoing += 20
            incoming += 20
        }
        assertEquals(ALIGN_MOST_SEEKS, seeks)
        assertFalse(settled.locked)
        assertTrue(outgoing <= p.startMs)
    }

    // 20 s of a kick every half second (120 BPM) with a quiet tone under it.
    private fun beatEnvelope(): SectionEnvelope {
        val rate = 44_100
        val builder = EnvelopeBuilder(rate, 1, 0)
        val samples = FloatArray(rate * 20) { n ->
            val sinceKick = (n % (rate / 2)).toDouble() / rate
            (0.6 * kotlin.math.exp(-sinceKick * 30) * kotlin.math.sin(2 * kotlin.math.PI * 60 * n / rate) +
                0.05 * kotlin.math.sin(2 * kotlin.math.PI * 880.0 * n / rate)).toFloat()
        }
        builder.push(samples)
        return builder.build()
    }

    @Test
    fun theScoutsHandTheSongsTagTempoToTheAnalysis() {
        val envelope = beatEnvelope()
        assertEquals(120.0, tailAnalyzer(null)(envelope).features.tempo!!.bpm, 1.0)
        assertEquals(60.0, tailAnalyzer(61.0)(envelope).features.tempo!!.bpm, 1.0)
        assertEquals(60.0, headAnalyzer(61.0)(envelope).features.tempo!!.bpm, 1.0)
    }

    @Test
    fun aSpareParkedWhereItShouldBeIsNotMovedAgain() {
        assertFalse(needsRepark(1_500, 1_500))
        assertFalse(needsRepark(1_520, 1_500))
        assertTrue(needsRepark(0, 1_500))
        assertTrue(needsRepark(1_500, 0))
    }

    @Test
    fun aRebufferIsNotAPause() {
        val none = Player.PLAYBACK_SUPPRESSION_REASON_NONE
        assertTrue(isRebuffering(true, Player.STATE_BUFFERING, none))
        // Paused by the listener, or by unplugged headphones.
        assertFalse(isRebuffering(false, Player.STATE_BUFFERING, none))
        assertFalse(isRebuffering(false, Player.STATE_READY, none))
        // Held back by a call.
        assertFalse(isRebuffering(true, Player.STATE_READY, Player.PLAYBACK_SUPPRESSION_REASON_TRANSIENT_AUDIO_FOCUS_LOSS))
        assertFalse(isRebuffering(true, Player.STATE_BUFFERING, Player.PLAYBACK_SUPPRESSION_REASON_TRANSIENT_AUDIO_FOCUS_LOSS))
        // Played out.
        assertFalse(isRebuffering(true, Player.STATE_ENDED, none))
    }

    @Test
    fun theFixedCrossfadeLastsAsLongAtAnySpeed() {
        val settings = AutomixSettings(maxOverlapMs = 8_000, smart = false)
        val a = FadeSong("a", 1, 200_000)
        val b = FadeSong("b", 1, 200_000)
        val context = TransitionContext(nowMs = 100_000, pace = 1.5)
        val plan = planTransition(a, b, null, null, settings.atSpeed(1.5f), context)
        // 12 s of the song pass in 8 s at 1.5x.
        assertEquals(12_000L, plan.overlapMs)
        assertEquals(188_000L, plan.startMs)
        assertEquals(settings, settings.atSpeed(1f))
        assertEquals(4_000L, settings.atSpeed(0.5f).maxOverlapMs)
    }

    @Test
    fun aTapReadEarlyIsReadAgainOnceItsLevelCounts() {
        // Read 3 s in, having heard 2 s: again once 18 more seconds have played.
        assertFalse(tapReadsAgain(2_000, askedAtMs = 3_000, positionMs = 20_000, speed = 1f, enoughMs = 20_000))
        assertTrue(tapReadsAgain(2_000, askedAtMs = 3_000, positionMs = 21_000, speed = 1f, enoughMs = 20_000))
        // At 2x the song time runs ahead of what is heard.
        assertFalse(tapReadsAgain(2_000, askedAtMs = 3_000, positionMs = 21_000, speed = 2f, enoughMs = 20_000))
        assertTrue(tapReadsAgain(2_000, askedAtMs = 3_000, positionMs = 39_000, speed = 2f, enoughMs = 20_000))
    }

    @Test
    fun aTapReadWithItsLevelHeardOrNotOnTheSongIsNotReadAgain() {
        assertFalse(tapReadsAgain(20_000, askedAtMs = 21_000, positionMs = 200_000, speed = 1f, enoughMs = 20_000))
        assertFalse(tapReadsAgain(null, askedAtMs = 3_000, positionMs = 200_000, speed = 1f, enoughMs = 20_000))
    }
}
